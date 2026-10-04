import Foundation
import XCTest
@testable import WristCore

final class WearStoreTests: XCTestCase {
    private let zone = TimeZone(secondsFromGMT: -7 * 3600)!
    private let now = WearDates.parse("2026-10-04T08:00:00-07:00")!

    private func watch(_ id: String, _ brand: String, wearCount: Int, lastWornAt: String? = nil) -> WearWatch {
        WearWatch(id: id, brand: brand, model: "M", imageUrl: nil, thumbnailUrl: nil,
                  postUrl: "https://bsky.app/profile/x/post/\(id)", wearCount: wearCount,
                  lastWornAt: lastWornAt, postCount: 1)
    }

    /// Server order: A (2 wears), B (1), C (0).
    private var baseWatches: [WearWatch] {
        [
            watch("A", "Alpha", wearCount: 2, lastWornAt: "2026-10-02T07:58:00-07:00"),
            watch("B", "Bravo", wearCount: 1, lastWornAt: "2026-10-03T08:05:00-07:00"),
            watch("C", "Charlie", wearCount: 0),
        ]
    }

    private var baseCurrent: WearEvent {
        WearEvent(id: "server-current-0001", watchId: "B", wornAt: "2026-10-03T08:05:00-07:00",
                  source: .notification, recordedAt: "2026-10-03T15:05:01.204Z")
    }

    private func watchesJSON(_ watches: [WearWatch], current: WearEvent?) -> HTTPResponse {
        let response = WatchesResponse(watches: watches, current: current, generatedAt: "2026-10-04T15:00:00.000Z")
        let data = try! WristJSON.encoder.encode(response)
        return HTTPResponse(statusCode: 200, headers: ["Content-Type": "application/json"], body: data)
    }

    private func recordJSON(_ event: NewWearEvent, status: Int = 201) -> HTTPResponse {
        let stored = WearEvent(id: event.id, watchId: event.watchId, wornAt: event.wornAt, source: event.source,
                               recordedAt: "2026-10-04T15:00:01.000Z")
        let data = try! WristJSON.encoder.encode(RecordResponse(event: stored, created: status == 201))
        return HTTPResponse(statusCode: status, headers: ["Content-Type": "application/json"], body: data)
    }

    private func makeStore(
        transport: MockTransport,
        persistence: InMemoryWearPersistence = InMemoryWearPersistence(),
        refreshAfterFlush: Bool = false,
        ids: [String] = ["evt-0001", "evt-0002", "evt-0003"]
    ) -> WearStore {
        let client = WearAPIClient(
            configuration: WearAPIConfiguration(baseURL: URL(string: "https://example.test")!, token: "test-token"),
            transport: transport)
        let counter = Counter()
        let fixedNow = now
        return WearStore(
            client: client,
            persistence: persistence,
            options: WearStore.Options(refreshAfterFlush: refreshAfterFlush, timeZone: zone),
            clock: { fixedNow },
            makeID: { ids[min(counter.next(), ids.count - 1)] })
    }

    private func body(_ request: HTTPRequest) -> NewWearEvent? {
        request.body.flatMap { try? WristJSON.decoder.decode(NewWearEvent.self, from: $0) }
    }

    // MARK: - Tests

    func testRefreshLoadsServerState() async {
        let transport = MockTransport()
        transport.enqueue(watchesJSON(baseWatches, current: baseCurrent))
        let persistence = InMemoryWearPersistence()
        let store = makeStore(transport: transport, persistence: persistence)

        let state = await store.refresh()

        XCTAssertTrue(state.isLoaded)
        XCTAssertEqual(state.watches.map(\.id), ["A", "B", "C"])
        XCTAssertEqual(state.current, baseCurrent)
        XCTAssertEqual(state.pendingCount, 0)
        XCTAssertNil(state.lastError)
        XCTAssertEqual(state.lastSyncAt, now)
        XCTAssertEqual(try persistence.loadSnapshot()?.watches.count, 3)
    }

    func testLogWearIsOptimisticAndSends() async {
        let transport = MockTransport()
        transport.enqueue(watchesJSON(baseWatches, current: baseCurrent))
        let store = makeStore(transport: transport)
        await store.refresh()
        let expected = NewWearEvent(id: "evt-0001", watchId: "C", wornAt: "2026-10-04T08:00:00-07:00", source: .app)
        transport.enqueue(recordJSON(expected))

        let (event, state) = await store.logWear(watchID: "C", source: .app)

        XCTAssertEqual(event, expected)
        // C now ties B at 1; B keeps its earlier snapshot position.
        XCTAssertEqual(state.watches.map(\.id), ["A", "B", "C"])
        XCTAssertEqual(state.watches[2].wearCount, 1)
        XCTAssertEqual(state.watches[2].lastWornAt, expected.wornAt)
        XCTAssertEqual(state.current?.id, "evt-0001")
        XCTAssertEqual(state.current?.source, .app)
        XCTAssertEqual(state.pendingCount, 0)

        let post = transport.recorded[1]
        XCTAssertEqual(post.method, "POST")
        XCTAssertEqual(body(post), expected)
    }

    func testRepeatedWearOvertakes() async {
        let transport = MockTransport()
        transport.enqueue(watchesJSON(baseWatches, current: baseCurrent))
        let store = makeStore(transport: transport)
        await store.refresh()

        transport.enqueue(recordJSON(NewWearEvent(id: "evt-0001", watchId: "B", wornAt: "", source: .app)))
        var state = (await store.logWear(watchID: "B", source: .app)).state
        // B ties A at 2; A was first in the snapshot so stays first.
        XCTAssertEqual(state.watches.map(\.id), ["A", "B", "C"])

        transport.enqueue(recordJSON(NewWearEvent(id: "evt-0002", watchId: "B", wornAt: "", source: .widget)))
        state = (await store.logWear(watchID: "B", source: .widget)).state
        XCTAssertEqual(state.watches.map(\.id), ["B", "A", "C"])
        XCTAssertEqual(state.watches[0].wearCount, 3)
    }

    func testOfflineQueuesThenRetriesWithSameID() async {
        let transport = MockTransport()
        transport.enqueue(watchesJSON(baseWatches, current: baseCurrent))
        let persistence = InMemoryWearPersistence()
        let store = makeStore(transport: transport, persistence: persistence)
        await store.refresh()

        transport.enqueue(.failure(URLErrorStub()))
        let (event, offline) = await store.logWear(watchID: "C", source: .app)
        XCTAssertEqual(offline.pendingCount, 1)
        XCTAssertEqual(offline.watches[2].wearCount, 1, "optimistic count survives the failure")
        XCTAssertEqual(offline.current?.id, event.id)
        XCTAssertEqual(offline.lastError, "Network unavailable")
        XCTAssertEqual(try persistence.loadPending().map(\.id), [event.id])
        XCTAssertEqual(try persistence.loadPending().first?.attempts, 1)

        transport.enqueue(recordJSON(event))
        let online = await store.flush()
        XCTAssertEqual(online.pendingCount, 0)
        XCTAssertNil(online.lastError)
        XCTAssertEqual(try persistence.loadPending().count, 0)

        let posts = transport.recorded.filter { $0.method == "POST" }
        XCTAssertEqual(posts.count, 2)
        XCTAssertEqual(body(posts[0])?.id, body(posts[1])?.id, "retry reuses the idempotency key")
    }

    func testUndoPendingNeedsNoNetwork() async {
        let transport = MockTransport()
        transport.enqueue(watchesJSON(baseWatches, current: baseCurrent))
        let store = makeStore(transport: transport)
        await store.refresh()
        transport.enqueue(.failure(URLErrorStub()))
        let (event, _) = await store.logWear(watchID: "C", source: .app)
        let before = transport.recorded.count

        let state = await store.undo(eventID: event.id)

        XCTAssertEqual(state.pendingCount, 0)
        XCTAssertEqual(state.watches[2].wearCount, 0)
        XCTAssertEqual(state.current, baseCurrent)
        XCTAssertEqual(transport.recorded.count, before, "no DELETE for an unsent event")
    }

    func testUndoSentIssuesDelete() async {
        let transport = MockTransport()
        transport.enqueue(watchesJSON(baseWatches, current: baseCurrent))
        let store = makeStore(transport: transport)
        await store.refresh()
        transport.enqueue(recordJSON(NewWearEvent(id: "evt-0001", watchId: "C", wornAt: "", source: .app)))
        let (event, _) = await store.logWear(watchID: "C", source: .app)

        transport.enqueue(HTTPResponse(statusCode: 204))
        let state = await store.undo(eventID: event.id)

        let delete = transport.recorded.last!
        XCTAssertEqual(delete.method, "DELETE")
        XCTAssertTrue(delete.url.absoluteString.hasSuffix("/api/wear/events/evt-0001"))
        XCTAssertEqual(state.watches[2].wearCount, 0)
        XCTAssertEqual(state.current, baseCurrent)
    }

    func testUndoServerEventRefetches() async {
        let transport = MockTransport()
        transport.enqueue(watchesJSON(baseWatches, current: baseCurrent))
        let store = makeStore(transport: transport)
        await store.refresh()

        transport.enqueue(HTTPResponse(statusCode: 204))
        let afterDelete = [
            watch("A", "Alpha", wearCount: 2, lastWornAt: "2026-10-02T07:58:00-07:00"),
            watch("B", "Bravo", wearCount: 0),
            watch("C", "Charlie", wearCount: 0),
        ]
        transport.enqueue(watchesJSON(afterDelete, current: nil))
        let state = await store.undo(eventID: baseCurrent.id)

        XCTAssertEqual(transport.recorded.map(\.method), ["GET", "DELETE", "GET"])
        XCTAssertNil(state.current)
        XCTAssertEqual(state.watches[1].wearCount, 0)
    }

    func testFlushStopsOnUnauthorizedAndKeepsQueue() async {
        let transport = MockTransport()
        transport.enqueue(watchesJSON(baseWatches, current: baseCurrent))
        let store = makeStore(transport: transport)
        await store.refresh()
        transport.enqueue(.failure(URLErrorStub()))
        await store.logWear(watchID: "C", source: .app)
        transport.enqueue(.failure(URLErrorStub()))
        await store.logWear(watchID: "A", source: .app)
        let before = transport.recorded.count

        transport.enqueue(MockTransport.json(401, #"{"error":"Unauthorized"}"#))
        let state = await store.flush()

        XCTAssertEqual(state.pendingCount, 2)
        XCTAssertEqual(state.lastError, "Token rejected by server")
        XCTAssertEqual(transport.recorded.count, before + 1, "stops after the first failure")
    }

    func testFlushDropsPermanentlyRejectedEvent() async {
        let transport = MockTransport()
        transport.enqueue(watchesJSON(baseWatches, current: baseCurrent))
        let store = makeStore(transport: transport)
        await store.refresh()
        transport.enqueue(.failure(URLErrorStub()))
        await store.logWear(watchID: "Z", source: .app)

        transport.enqueue(MockTransport.json(400, #"{"error":"Unknown watchId"}"#))
        let state = await store.flush()

        XCTAssertEqual(state.pendingCount, 0)
        XCTAssertEqual(state.lastError, "Server error 400: Unknown watchId")
        XCTAssertEqual(state.current, baseCurrent, "dropped event no longer overlays")
    }

    func testLoadCachedRestoresSnapshotAndQueueWithoutNetwork() async {
        let transport = MockTransport()
        let queued = PendingWearEvent(event: NewWearEvent(id: "evt-9", watchId: "C", wornAt: "2026-10-04T07:00:00-07:00", source: .widget), attempts: 2)
        let persistence = InMemoryWearPersistence(
            snapshot: WearSnapshot(watches: baseWatches, current: baseCurrent, fetchedAt: now.addingTimeInterval(-3600)),
            pending: [queued])
        let store = makeStore(transport: transport, persistence: persistence)

        let state = await store.loadCached()

        XCTAssertTrue(state.isLoaded)
        XCTAssertEqual(state.pendingCount, 1)
        XCTAssertEqual(state.watches.map(\.id), ["A", "B", "C"])
        XCTAssertEqual(state.watches[2].wearCount, 1)
        XCTAssertEqual(state.current?.id, "evt-9")
        XCTAssertEqual(transport.recorded.count, 0)
    }

    func testRefreshFailureKeepsCachedState() async {
        let transport = MockTransport()
        let persistence = InMemoryWearPersistence(
            snapshot: WearSnapshot(watches: baseWatches, current: baseCurrent, fetchedAt: now.addingTimeInterval(-3600)))
        let store = makeStore(transport: transport, persistence: persistence)
        await store.loadCached()

        transport.enqueue(.failure(URLErrorStub()))
        let state = await store.refresh()

        XCTAssertEqual(state.watches.map(\.id), ["A", "B", "C"])
        XCTAssertEqual(state.lastError, "Network unavailable")
        XCTAssertTrue(state.isLoaded)
    }

    func testRefreshAfterFlushAdoptsServerTruth() async {
        let transport = MockTransport()
        transport.enqueue(watchesJSON(baseWatches, current: baseCurrent))
        let store = makeStore(transport: transport, refreshAfterFlush: true)
        await store.refresh()

        let sent = NewWearEvent(id: "evt-0001", watchId: "C", wornAt: "2026-10-04T08:00:00-07:00", source: .app)
        transport.enqueue(recordJSON(sent))
        let serverAfter = [
            watch("A", "Alpha", wearCount: 2, lastWornAt: "2026-10-02T07:58:00-07:00"),
            watch("B", "Bravo", wearCount: 1, lastWornAt: "2026-10-03T08:05:00-07:00"),
            watch("C", "Charlie", wearCount: 1, lastWornAt: sent.wornAt),
        ]
        let serverCurrent = WearEvent(id: sent.id, watchId: "C", wornAt: sent.wornAt, source: .app, recordedAt: "2026-10-04T15:00:01.000Z")
        transport.enqueue(watchesJSON(serverAfter, current: serverCurrent))

        let (_, state) = await store.logWear(watchID: "C", source: .app)

        XCTAssertEqual(transport.recorded.map(\.method), ["GET", "POST", "GET"])
        XCTAssertEqual(state.watches, serverAfter)
        XCTAssertEqual(state.current, serverCurrent, "recordedAt comes from the server now")
        XCTAssertEqual(state.pendingCount, 0)
    }

    func testUpdatesStreamEmitsCurrentThenChanges() async {
        let transport = MockTransport()
        transport.enqueue(watchesJSON(baseWatches, current: baseCurrent))
        let store = makeStore(transport: transport)
        let stream = await store.updates()
        var iterator = stream.makeAsyncIterator()

        let first = await iterator.next()
        XCTAssertEqual(first?.isLoaded, false)

        await store.refresh()
        let second = await iterator.next()
        XCTAssertEqual(second?.isLoaded, true)
        XCTAssertEqual(second?.watches.count, 3)
    }

    func testClassify() {
        XCTAssertEqual(WearStore.classify(WearAPIError.server(status: 400, message: nil)), .drop)
        XCTAssertEqual(WearStore.classify(WearAPIError.server(status: 422, message: nil)), .drop)
        XCTAssertEqual(WearStore.classify(WearAPIError.server(status: 500, message: nil)), .stop)
        XCTAssertEqual(WearStore.classify(WearAPIError.unauthorized), .stop)
        XCTAssertEqual(WearStore.classify(WearAPIError.disabled), .stop)
        XCTAssertEqual(WearStore.classify(WearAPIError.rateLimited(retryAfterSeconds: 5)), .stop)
        XCTAssertEqual(WearStore.classify(WearAPIError.transport("x")), .stop)
        XCTAssertEqual(WearStore.classify(URLErrorStub()), .stop)
    }
}

// MARK: - Helpers

private struct URLErrorStub: Error, CustomStringConvertible {
    var description: String { "offline" }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int {
        lock.lock(); defer { lock.unlock() }
        let v = value
        value += 1
        return v
    }
}
