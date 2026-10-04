import Foundation

/// The last server truth we saw. Shared between the app and the widget via
/// the App Group container (WristKit.FileWearPersistence).
public struct WearSnapshot: Codable, Sendable, Equatable {
    public var watches: [WearWatch]
    public var current: WearEvent?
    public var fetchedAt: Date

    public init(watches: [WearWatch], current: WearEvent?, fetchedAt: Date) {
        self.watches = watches
        self.current = current
        self.fetchedAt = fetchedAt
    }
}

/// A wear the user logged that has not yet been accepted by the server.
public struct PendingWearEvent: Codable, Sendable, Equatable, Identifiable {
    public var event: NewWearEvent
    public var attempts: Int
    public var lastError: String?

    public var id: String { event.id }

    public init(event: NewWearEvent, attempts: Int = 0, lastError: String? = nil) {
        self.event = event
        self.attempts = attempts
        self.lastError = lastError
    }
}

/// Storage seam for WearStore. Implementations must be safe to call from any
/// thread; WearStore only calls them from inside its actor.
public protocol WearPersistence: Sendable {
    func loadSnapshot() throws -> WearSnapshot?
    func saveSnapshot(_ snapshot: WearSnapshot) throws
    func loadPending() throws -> [PendingWearEvent]
    func savePending(_ events: [PendingWearEvent]) throws
}

public final class InMemoryWearPersistence: WearPersistence, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: WearSnapshot?
    private var pending: [PendingWearEvent]

    public init(snapshot: WearSnapshot? = nil, pending: [PendingWearEvent] = []) {
        self.snapshot = snapshot
        self.pending = pending
    }

    public func loadSnapshot() throws -> WearSnapshot? {
        lock.lock(); defer { lock.unlock() }
        return snapshot
    }

    public func saveSnapshot(_ snapshot: WearSnapshot) throws {
        lock.lock(); defer { lock.unlock() }
        self.snapshot = snapshot
    }

    public func loadPending() throws -> [PendingWearEvent] {
        lock.lock(); defer { lock.unlock() }
        return pending
    }

    public func savePending(_ events: [PendingWearEvent]) throws {
        lock.lock(); defer { lock.unlock() }
        pending = events
    }
}
