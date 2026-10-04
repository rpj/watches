import XCTest
import WristCore
@testable import WristKit

final class FileWearPersistenceTests: XCTestCase {
    private var directory: URL!
    private var persistence: FileWearPersistence!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        persistence = FileWearPersistence(directory: directory)
    }

    override func tearDown() {
        persistence = nil
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func sampleSnapshot() -> WearSnapshot {
        WearSnapshot(
            watches: [W1, W2],
            current: WearEvent(id: "e1", watchId: W1.id, wornAt: "2026-10-04T08:00:00-07:00", source: .widget, recordedAt: "2026-10-04T15:00:01Z"),
            fetchedAt: Date()
        )
    }

    private func samplePending() -> [PendingWearEvent] {
        [
            PendingWearEvent(
                event: NewWearEvent(id: "p1", watchId: W1.id, wornAt: "2026-10-04T08:00:00-07:00", source: .app),
                attempts: 3,
                lastError: "offline"
            ),
            PendingWearEvent(event: NewWearEvent(id: "p2", watchId: W2.id, wornAt: "2026-10-04T09:00:00-07:00", source: .notification)),
        ]
    }

    func testLoadSnapshotNilWhenMissing() throws {
        XCTAssertNil(try persistence.loadSnapshot())
    }

    func testSnapshotRoundtrip() throws {
        let snapshot = sampleSnapshot()
        try persistence.saveSnapshot(snapshot)
        let loaded = try XCTUnwrap(try persistence.loadSnapshot())
        XCTAssertEqual(loaded.watches, snapshot.watches)
        XCTAssertEqual(loaded.current, snapshot.current)
        XCTAssertEqual(loaded.fetchedAt.timeIntervalSince1970, snapshot.fetchedAt.timeIntervalSince1970, accuracy: 1)
    }

    func testLoadPendingEmptyWhenMissing() throws {
        XCTAssertEqual(try persistence.loadPending(), [])
    }

    func testPendingRoundtrip() throws {
        let pending = samplePending()
        try persistence.savePending(pending)
        let loaded = try persistence.loadPending()
        XCTAssertEqual(loaded, pending)
        XCTAssertEqual(loaded.first?.attempts, 3)
        XCTAssertEqual(loaded.first?.lastError, "offline")
    }

    func testWipeClearsBoth() throws {
        try persistence.saveSnapshot(sampleSnapshot())
        try persistence.savePending(samplePending())
        persistence.wipe()
        XCTAssertNil(try persistence.loadSnapshot())
        XCTAssertEqual(try persistence.loadPending(), [])
    }
}
