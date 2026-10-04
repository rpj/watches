import Foundation
import WristCore

/// An in-memory stand-in for the wear API. Used by UI tests (launch argument
/// `-uiTesting`) and SwiftUI previews so the app runs with no network and no
/// token. Mirrors the server's ordering rules closely enough for the picker.
public final class FixtureTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var watches: [WearWatch]
    private var events: [WearEvent] = []

    public init(watches: [WearWatch]) {
        self.watches = watches
    }

    /// Three watches with the brands/models from ios-app/API.md and no images.
    public static func sample() -> FixtureTransport {
        FixtureTransport(watches: [
            WearWatch(id: "3m2uvdvq7622g", brand: "Citizen", model: "Eco Drive E110-K16750", imageUrl: nil, thumbnailUrl: nil,
                      postUrl: "https://bsky.app/profile/ryanswatches.com/post/3m2uvdvq7622g", wearCount: 2,
                      lastWornAt: "2026-10-02T07:58:00-07:00", postCount: 2),
            WearWatch(id: "3mwz3ctxxnc26", brand: "Kurono", model: "Malachite", imageUrl: nil, thumbnailUrl: nil,
                      postUrl: "https://bsky.app/profile/ryanswatches.com/post/3mwz3ctxxnc26", wearCount: 1,
                      lastWornAt: "2026-10-03T08:05:00-07:00", postCount: 1),
            WearWatch(id: "3m2uxrekinc2e", brand: "Skagen", model: "233LTMN Quartz", imageUrl: nil, thumbnailUrl: nil,
                      postUrl: "https://bsky.app/profile/ryanswatches.com/post/3m2uxrekinc2e", wearCount: 0,
                      lastWornAt: nil, postCount: 1),
        ])
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.lock(); defer { lock.unlock() }
        let path = request.url.path
        switch (request.method, path) {
        case ("GET", "/api/wear/watches"):
            return json(200, WatchesResponse(watches: sorted(), current: current(), generatedAt: WearDates.string(from: Date(), timeZone: TimeZone(identifier: "UTC")!)))
        case ("GET", "/api/wear/events"):
            return json(200, EventsResponse(events: events.sorted { instant($0.wornAt) > instant($1.wornAt) }))
        case ("POST", "/api/wear/events"):
            guard let body = request.body, let input = try? WristJSON.decoder.decode(NewWearEvent.self, from: body) else {
                return json(400, APIErrorBody(error: "Body must be a JSON object"))
            }
            if let existing = events.first(where: { $0.id == input.id }) {
                return json(200, RecordResponse(event: existing, created: false))
            }
            guard let index = watches.firstIndex(where: { $0.id == input.watchId }) else {
                return json(400, APIErrorBody(error: "Unknown watchId"))
            }
            let stored = WearEvent(id: input.id, watchId: input.watchId, wornAt: input.wornAt, source: input.source,
                                   recordedAt: WearDates.string(from: Date(), timeZone: TimeZone(identifier: "UTC")!))
            events.append(stored)
            let w = watches[index]
            watches[index] = WearWatch(id: w.id, brand: w.brand, model: w.model, imageUrl: w.imageUrl, thumbnailUrl: w.thumbnailUrl,
                                       postUrl: w.postUrl, wearCount: w.wearCount + 1,
                                       lastWornAt: later(w.lastWornAt, stored.wornAt), postCount: w.postCount)
            return json(201, RecordResponse(event: stored, created: true))
        case ("DELETE", _) where path.hasPrefix("/api/wear/events/"):
            let id = String(path.dropFirst("/api/wear/events/".count))
            guard let index = events.firstIndex(where: { $0.id == id }) else {
                return json(404, APIErrorBody(error: "Not found"))
            }
            let removed = events.remove(at: index)
            if let wi = watches.firstIndex(where: { $0.id == removed.watchId }) {
                let w = watches[wi]
                let remaining = events.filter { $0.watchId == w.id }.map(\.wornAt).max(by: { instant($0) < instant($1) })
                watches[wi] = WearWatch(id: w.id, brand: w.brand, model: w.model, imageUrl: w.imageUrl, thumbnailUrl: w.thumbnailUrl,
                                        postUrl: w.postUrl, wearCount: max(0, w.wearCount - 1),
                                        lastWornAt: remaining ?? (w.wearCount - 1 > 0 ? w.lastWornAt : nil), postCount: w.postCount)
            }
            return HTTPResponse(statusCode: 204)
        default:
            return json(404, APIErrorBody(error: "Not found"))
        }
    }

    // MARK: - Helpers

    private func sorted() -> [WearWatch] {
        // Stable: wearCount desc, otherwise original order (which already encodes the server's secondary keys).
        watches.enumerated().sorted { a, b in
            if a.element.wearCount != b.element.wearCount { return a.element.wearCount > b.element.wearCount }
            return a.offset < b.offset
        }.map(\.element)
    }

    private func current() -> WearEvent? {
        events.max { instant($0.wornAt) < instant($1.wornAt) }
    }

    private func instant(_ iso: String) -> Date {
        WearDates.parse(iso) ?? .distantPast
    }

    private func later(_ a: String?, _ b: String) -> String {
        guard let a else { return b }
        return instant(b) >= instant(a) ? b : a
    }

    private func json<T: Encodable>(_ status: Int, _ value: T) -> HTTPResponse {
        let data = (try? WristJSON.encoder.encode(value)) ?? Data()
        return HTTPResponse(statusCode: status, headers: ["Content-Type": "application/json"], body: data)
    }
}
