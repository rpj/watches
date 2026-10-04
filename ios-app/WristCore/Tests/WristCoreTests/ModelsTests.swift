import XCTest
@testable import WristCore

final class ModelsTests: XCTestCase {
    func testDecodeSampleResponse() throws {
        let response = try WristJSON.decoder.decode(WatchesResponse.self, from: Data(Fixtures.watchesResponse.utf8))
        XCTAssertEqual(response.watches.map(\.brand), ["Citizen", "Kurono", "Skagen"])
        XCTAssertEqual(response.watches[0].wearCount, 2)
        XCTAssertEqual(response.watches[0].lastWornAt, "2026-10-02T07:58:00-07:00")
        XCTAssertNil(response.watches[2].lastWornAt)
        XCTAssertTrue(response.watches[2].imageUrl?.hasSuffix("bafkreiskagenone") ?? false)
        XCTAssertEqual(response.current?.source, .notification)
        XCTAssertEqual(response.current?.recordedAt, "2026-10-03T15:05:01.204Z")
        XCTAssertEqual(response.generatedAt, "2026-10-04T15:12:32.418Z")
        XCTAssertEqual(response.watches, Fixtures.watches)
        XCTAssertEqual(response.watches[0].displayName, "Citizen Eco Drive E110-K16750")
    }

    func testDecodeNullCurrent() throws {
        let response = try WristJSON.decoder.decode(WatchesResponse.self, from: Data(Fixtures.watchesResponseWithNullCurrent.utf8))
        XCTAssertNil(response.current)
        XCTAssertEqual(response.watches.count, 3)
    }

    func testWearEventDecodesWithoutRecordedAt() throws {
        let json = #"{"id":"11111111-1111-4111-8111-111111111111","watchId":"3m2uvdvq7622g","wornAt":"2026-10-01T08:00:00-07:00","source":"app"}"#
        let event = try WristJSON.decoder.decode(WearEvent.self, from: Data(json.utf8))
        XCTAssertNil(event.recordedAt)
        XCTAssertEqual(event, Fixtures.event1)
    }

    func testEncodeNewWearEventHasExactlyFourKeys() throws {
        let new = NewWearEvent(id: "11111111-1111-4111-8111-111111111111", watchId: "3m2uvdvq7622g",
                               wornAt: "2026-10-01T08:00:00-07:00", source: .shortcut)
        let data = try WristJSON.encoder.encode(new)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let dict = try XCTUnwrap(object)
        XCTAssertEqual(Set(dict.keys), ["id", "watchId", "wornAt", "source"])
        XCTAssertEqual(dict["id"] as? String, "11111111-1111-4111-8111-111111111111")
        XCTAssertEqual(dict["watchId"] as? String, "3m2uvdvq7622g")
        XCTAssertEqual(dict["wornAt"] as? String, "2026-10-01T08:00:00-07:00")
        XCTAssertEqual(dict["source"] as? String, "shortcut")
    }

    func testParseAcceptedForms() throws {
        let expected = Date(timeIntervalSince1970: 1_791_126_751) // 2026-10-04T15:12:31Z
        let offset = try XCTUnwrap(WearDates.parse("2026-10-04T08:12:31-07:00"))
        let zulu = try XCTUnwrap(WearDates.parse("2026-10-04T15:12:31Z"))
        XCTAssertEqual(offset.timeIntervalSince1970, zulu.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(offset.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 0.001)

        let frac = try XCTUnwrap(WearDates.parse("2026-10-04T15:12:32.418Z"))
        XCTAssertEqual(frac.timeIntervalSince1970, expected.timeIntervalSince1970 + 1.418, accuracy: 0.01)
        let noFrac = try XCTUnwrap(WearDates.parse("2026-10-04T15:12:32Z"))
        XCTAssertEqual(noFrac.timeIntervalSince1970, expected.timeIntervalSince1970 + 1, accuracy: 0.001)
        let fracOffset = try XCTUnwrap(WearDates.parse("2026-10-04T08:12:31.5-07:00"))
        XCTAssertEqual(fracOffset.timeIntervalSince1970, expected.timeIntervalSince1970 + 0.5, accuracy: 0.01)

        XCTAssertNil(WearDates.parse("yesterday"))
    }

    func testStringFromDate() throws {
        let date = try XCTUnwrap(WearDates.parse("2026-10-04T08:12:31-07:00"))
        let pacific = WearDates.string(from: date, timeZone: TimeZone(secondsFromGMT: -7 * 3600)!)
        XCTAssertTrue(pacific.hasSuffix("-07:00"), pacific)
        XCTAssertFalse(pacific.contains("."), pacific)
        let back = try XCTUnwrap(WearDates.parse(pacific))
        XCTAssertEqual(back.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 0.001)

        let utc = WearDates.string(from: date, timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertTrue(utc.hasSuffix("Z"), utc)
    }
}
