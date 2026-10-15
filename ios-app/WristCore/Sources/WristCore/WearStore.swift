import Foundation

/// Single source of truth for "what am I wearing" on the device.
///
/// Holds the last server snapshot plus every wear the user logged locally
/// that the server has not confirmed yet, and derives the list the UI shows
/// from both. Logging is optimistic: the tap is reflected immediately, the
/// POST happens afterwards, and failures leave the event queued for the next
/// `flush()`. Event ids are generated client-side so retries are idempotent.
public actor WearStore {
    public struct State: Sendable, Equatable {
        public var watches: [WearWatch]
        public var current: WearEvent?
        public var pendingCount: Int
        public var lastSyncAt: Date?
        public var lastError: String?
        /// True once any snapshot (cached or fresh) is available.
        public var isLoaded: Bool

        public static let empty = State(watches: [], current: nil, pendingCount: 0, lastSyncAt: nil, lastError: nil, isLoaded: false)

        public init(watches: [WearWatch], current: WearEvent?, pendingCount: Int, lastSyncAt: Date?, lastError: String?, isLoaded: Bool) {
            self.watches = watches
            self.current = current
            self.pendingCount = pendingCount
            self.lastSyncAt = lastSyncAt
            self.lastError = lastError
            self.isLoaded = isLoaded
        }
    }

    public struct Options: Sendable {
        /// After a successful flush, re-fetch the server snapshot so counts and
        /// `current` come from the server rather than the optimistic overlay.
        public var refreshAfterFlush: Bool
        /// Zone used to stamp `wornAt` on new events.
        public var timeZone: TimeZone
        /// Tapping the watch that is already current within this many seconds
        /// is a no-op (matches the server's WEAR_DEBOUNCE_MS). 0 disables.
        public var debounceInterval: TimeInterval

        public init(refreshAfterFlush: Bool = true, timeZone: TimeZone = .current, debounceInterval: TimeInterval = 10 * 60) {
            self.refreshAfterFlush = refreshAfterFlush
            self.timeZone = timeZone
            self.debounceInterval = debounceInterval
        }
    }

    enum FlushDecision: Equatable {
        /// The server rejected this event for good (4xx other than auth/rate limit); drop it.
        case drop
        /// Transient or configuration problem; keep the queue and stop for now.
        case stop
    }

    private let client: WearAPIClient
    private let persistence: any WearPersistence
    private let options: Options
    private let clock: @Sendable () -> Date
    private let makeID: @Sendable () -> String

    private var base: WearSnapshot?
    private var pending: [PendingWearEvent] = []
    /// Accepted by the server since `base` was fetched; still overlaid until the next fetch.
    private var localSent: [NewWearEvent] = []
    private var lastError: String?
    private var observers: [UUID: AsyncStream<State>.Continuation] = [:]

    public init(
        client: WearAPIClient,
        persistence: any WearPersistence,
        options: Options = Options(),
        clock: @escaping @Sendable () -> Date = { Date() },
        makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.client = client
        self.persistence = persistence
        self.options = options
        self.clock = clock
        self.makeID = makeID
    }

    // MARK: - Observation

    public var state: State { derive() }

    /// Emits the current state immediately, then every change.
    public func updates() -> AsyncStream<State> {
        let (stream, continuation) = AsyncStream<State>.makeStream()
        let id = UUID()
        observers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { await self.removeObserver(id) }
        }
        continuation.yield(derive())
        return stream
    }

    private func removeObserver(_ id: UUID) {
        observers[id] = nil
    }

    private func publish() {
        let snapshot = derive()
        for continuation in observers.values {
            continuation.yield(snapshot)
        }
    }

    // MARK: - Loading

    /// Pull whatever is on disk (snapshot + queue). Safe to call repeatedly:
    /// a newer on-disk snapshot replaces the in-memory one (another process,
    /// the widget, may have written it) and queued events are merged by id.
    @discardableResult
    public func loadCached() -> State {
        if let disk = try? persistence.loadSnapshot() {
            if let current = base {
                if disk.fetchedAt > current.fetchedAt {
                    base = disk
                    localSent.removeAll()
                }
            } else {
                base = disk
            }
        }
        if let diskPending = try? persistence.loadPending() {
            for item in diskPending where !pending.contains(where: { $0.id == item.id }) {
                pending.append(item)
            }
        }
        publish()
        return derive()
    }

    /// Fetch the server snapshot, then push anything queued.
    @discardableResult
    public func refresh() async -> State {
        await fetchBase()
        if !pending.isEmpty {
            return await flush()
        }
        return derive()
    }

    private func fetchBase() async {
        do {
            let response = try await client.watches()
            let snapshot = WearSnapshot(watches: response.watches, current: response.current, fetchedAt: clock())
            base = snapshot
            localSent.removeAll()
            lastError = nil
            try? persistence.saveSnapshot(snapshot)
        } catch {
            lastError = Self.message(for: error)
        }
        publish()
    }

    // MARK: - Logging

    /// Record that the user just put on `watchID`. Applies immediately, then
    /// tries to send. Returns the created event (for Undo) and the state after
    /// the send attempt. The event is nil when the tap was a no-op because
    /// that watch is already current and was logged within
    /// `Options.debounceInterval` (including still-unsent events).
    @discardableResult
    public func logWear(watchID: String, source: WearSource) async -> (event: NewWearEvent?, state: State) {
        let now = clock()
        if options.debounceInterval > 0,
           let current = derive().current, current.watchId == watchID,
           let since = WearDates.parse(current.wornAt),
           abs(now.timeIntervalSince(since)) < options.debounceInterval {
            return (nil, derive())
        }

        let event = NewWearEvent(
            id: makeID(),
            watchId: watchID,
            wornAt: WearDates.string(from: now, timeZone: options.timeZone),
            source: source
        )
        pending.append(PendingWearEvent(event: event))
        persistPending()
        publish()
        let state = await flush()
        return (event, state)
    }

    /// Reverse a wear. Unsent events are simply dropped from the queue; sent
    /// ones are deleted on the server.
    @discardableResult
    public func undo(eventID: String) async -> State {
        if let index = pending.firstIndex(where: { $0.id == eventID }) {
            pending.remove(at: index)
            persistPending()
            publish()
            return derive()
        }
        do {
            _ = try await client.delete(eventID: eventID)
            lastError = nil
            if let index = localSent.firstIndex(where: { $0.id == eventID }) {
                localSent.remove(at: index)
                publish()
            } else {
                // Lives in the server snapshot (e.g. `current` from the last fetch).
                await fetchBase()
            }
        } catch {
            lastError = Self.message(for: error)
            publish()
        }
        return derive()
    }

    /// Send queued events in order. Stops at the first transient failure so
    /// order is preserved; permanently rejected events are dropped.
    @discardableResult
    public func flush() async -> State {
        var sentAny = false
        var index = 0
        while index < pending.count {
            let item = pending[index]
            do {
                _ = try await client.record(item.event)
                pending.remove(at: index)
                localSent.append(item.event)
                sentAny = true
                lastError = nil
            } catch {
                let message = Self.message(for: error)
                switch Self.classify(error) {
                case .drop:
                    pending.remove(at: index)
                    lastError = message
                case .stop:
                    pending[index].attempts += 1
                    pending[index].lastError = message
                    lastError = message
                    persistPending()
                    publish()
                    return derive()
                }
            }
        }
        persistPending()
        if sentAny && options.refreshAfterFlush {
            await fetchBase()
        } else {
            publish()
        }
        return derive()
    }

    // MARK: - Derivation

    private func derive() -> State {
        let overlay = localSent + pending.map(\.event)

        var extraCounts: [String: Int] = [:]
        var latestLocal: [String: String] = [:]
        var current = base?.current
        var currentDate = current.flatMap { WearDates.parse($0.wornAt) } ?? .distantPast

        for event in overlay {
            extraCounts[event.watchId, default: 0] += 1
            guard let date = WearDates.parse(event.wornAt) else { continue }
            if let previous = latestLocal[event.watchId].flatMap(WearDates.parse), previous >= date {
                // keep the later one already recorded
            } else {
                latestLocal[event.watchId] = event.wornAt
            }
            if date >= currentDate {
                currentDate = date
                current = WearEvent(id: event.id, watchId: event.watchId, wornAt: event.wornAt, source: event.source, recordedAt: nil)
            }
        }

        var ranked: [(index: Int, watch: WearWatch)] = []
        for (index, watch) in (base?.watches ?? []).enumerated() {
            let extra = extraCounts[watch.id] ?? 0
            guard extra > 0 else {
                ranked.append((index, watch))
                continue
            }
            let lastWorn = Self.later(watch.lastWornAt, latestLocal[watch.id])
            ranked.append((index, WearWatch(
                id: watch.id,
                brand: watch.brand,
                model: watch.model,
                imageUrl: watch.imageUrl,
                thumbnailUrl: watch.thumbnailUrl,
                postUrl: watch.postUrl,
                wearCount: watch.wearCount + extra,
                lastWornAt: lastWorn,
                postCount: watch.postCount
            )))
        }
        // The server order already encodes every secondary key (post count,
        // recency, name), so re-sorting by wear count with the snapshot index
        // as the tiebreak reproduces the server's comparator exactly.
        ranked.sort { a, b in
            if a.watch.wearCount != b.watch.wearCount { return a.watch.wearCount > b.watch.wearCount }
            return a.index < b.index
        }

        return State(
            watches: ranked.map(\.watch),
            current: current,
            pendingCount: pending.count,
            lastSyncAt: base?.fetchedAt,
            lastError: lastError,
            isLoaded: base != nil
        )
    }

    private static func later(_ a: String?, _ b: String?) -> String? {
        switch (a.flatMap(WearDates.parse), b.flatMap(WearDates.parse)) {
        case (nil, nil): return a ?? b
        case (nil, _): return b
        case (_, nil): return a
        case let (da?, db?): return db > da ? b : a
        }
    }

    private func persistPending() {
        try? persistence.savePending(pending)
    }

    // MARK: - Error policy

    static func classify(_ error: Error) -> FlushDecision {
        guard let api = error as? WearAPIError else { return .stop }
        switch api {
        case .server(let status, _) where (400..<500).contains(status) && status != 401 && status != 404 && status != 429:
            return .drop
        default:
            return .stop
        }
    }

    /// Short, user-presentable description of a failure.
    public static func message(for error: Error) -> String {
        guard let api = error as? WearAPIError else { return "Something went wrong" }
        switch api {
        case .unauthorized: return "Token rejected by server"
        case .disabled: return "Wear API is disabled on the server"
        case .notFound: return "Not found"
        case .invalidURL: return "Invalid server URL"
        case .rateLimited(let retry):
            if let retry { return "Rate limited, retry in \(retry)s" }
            return "Rate limited"
        case .server(let status, let message):
            if let message, !message.isEmpty { return "Server error \(status): \(message)" }
            return "Server error \(status)"
        case .decoding: return "Unexpected response from server"
        case .transport: return "Network unavailable"
        }
    }
}
