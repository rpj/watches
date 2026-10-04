import XCTest
import WristCore
@testable import WristKit

final class FixtureTransportTests: XCTestCase {
    private let citizen = "3m2uvdvq7622g"
    private let kurono = "3mwz3ctxxnc26"
    private let skagen = "3m2uxrekinc2e"
    private let eventID = "11111111-1111-4111-8111-111111111111"

    private func makeClient() -> WearAPIClient {
        WearAPIClient(
            configuration: WearAPIConfiguration(baseURL: URL(string: "https://fixture.test")!, token: "t"),
            transport: FixtureTransport.sample()
        )
    }

    func testRecordDeleteLifecycle() async throws {
        let client = makeClient()

        let initial = try await client.watches()
        XCTAssertEqual(initial.watches.map(\.id), [citizen, kurono, skagen])
        XCTAssertNil(initial.current)

        let event = NewWearEvent(id: eventID, watchId: skagen, wornAt: "2026-10-04T08:00:00-07:00", source: .app)
        let first = try await client.record(event)
        XCTAssertTrue(first.created)
        let second = try await client.record(event)
        XCTAssertFalse(second.created)

        let afterRecord = try await client.watches()
        XCTAssertEqual(afterRecord.watches.first { $0.id == skagen }?.wearCount, 1)
        XCTAssertEqual(afterRecord.current?.id, eventID)

        let deleted = try await client.delete(eventID: eventID)
        XCTAssertTrue(deleted)
        let deletedAgain = try await client.delete(eventID: eventID)
        XCTAssertFalse(deletedAgain)

        let afterDelete = try await client.watches()
        XCTAssertNil(afterDelete.current)
    }

    func testRecordUnknownWatchThrows() async {
        let client = makeClient()
        let bad = NewWearEvent(id: "22222222-2222-4222-8222-222222222222", watchId: "nope", wornAt: "2026-10-04T08:00:00-07:00", source: .app)
        do {
            _ = try await client.record(bad)
            XCTFail("expected throw")
        } catch let error as WearAPIError {
            XCTAssertEqual(error, .server(status: 400, message: "Unknown watchId"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }
}
