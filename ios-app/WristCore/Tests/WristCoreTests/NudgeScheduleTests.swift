import Foundation
import XCTest
@testable import WristCore

final class NudgeScheduleTests: XCTestCase {
    // Fixed zone so results do not depend on the host.
    private let zone = TimeZone(secondsFromGMT: -7 * 3600)!
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func testDisabledYieldsNothing() {
        let dates = NudgeSchedule.nextFireDates(
            config: NudgeConfig(enabled: false, hour: 8, minute: 0),
            now: date(2026, 10, 4, 7, 0), calendar: calendar, loggedToday: false)
        XCTAssertEqual(dates, [])
    }

    func testIncludesTodayWhenTimeIsAhead() {
        let dates = NudgeSchedule.nextFireDates(
            config: NudgeConfig(enabled: true, hour: 8, minute: 0),
            now: date(2026, 10, 4, 7, 0), calendar: calendar, loggedToday: false)
        XCTAssertEqual(dates.count, NudgeSchedule.horizonDays)
        XCTAssertEqual(dates.first, date(2026, 10, 4, 8, 0))
        XCTAssertEqual(dates.last, date(2026, 10, 10, 8, 0))
    }

    func testSkipsTodayWhenTimeHasPassed() {
        let dates = NudgeSchedule.nextFireDates(
            config: NudgeConfig(enabled: true, hour: 8, minute: 0),
            now: date(2026, 10, 4, 9, 0), calendar: calendar, loggedToday: false)
        XCTAssertEqual(dates.count, NudgeSchedule.horizonDays)
        XCTAssertEqual(dates.first, date(2026, 10, 5, 8, 0))
    }

    func testSkipsTodayWhenAlreadyLogged() {
        let dates = NudgeSchedule.nextFireDates(
            config: NudgeConfig(enabled: true, hour: 8, minute: 30),
            now: date(2026, 10, 4, 7, 0), calendar: calendar, loggedToday: true)
        XCTAssertEqual(dates.count, NudgeSchedule.horizonDays)
        XCTAssertEqual(dates.first, date(2026, 10, 5, 8, 30))
    }

    func testExactMinuteCountsAsPassed() {
        let dates = NudgeSchedule.nextFireDates(
            config: NudgeConfig(enabled: true, hour: 8, minute: 0),
            now: date(2026, 10, 4, 8, 0), calendar: calendar, loggedToday: false)
        XCTAssertEqual(dates.first, date(2026, 10, 5, 8, 0))
    }

    func testRequestIdentifiersAreUniqueAndLocal() {
        let dates = NudgeSchedule.nextFireDates(
            config: NudgeConfig(enabled: true, hour: 23, minute: 30),
            now: date(2026, 10, 4, 7, 0), calendar: calendar, loggedToday: false)
        let ids = dates.map { NudgeSchedule.requestIdentifier(for: $0, calendar: calendar) }
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(ids.first, "nudge-2026-10-04")
        // 23:30 local on Oct 4 is Oct 5 in UTC; identifier must still be local.
        XCTAssertTrue(ids.allSatisfy(NudgeSchedule.isNudgeRequest))
        XCTAssertFalse(NudgeSchedule.isNudgeRequest(identifier: "other"))
    }

    func testIsLoggedToday() {
        let now = date(2026, 10, 4, 12, 0)
        XCTAssertTrue(NudgeSchedule.isLoggedToday(latestWornAt: "2026-10-04T07:58:00-07:00", now: now, calendar: calendar))
        // Same instant expressed in UTC.
        XCTAssertTrue(NudgeSchedule.isLoggedToday(latestWornAt: "2026-10-04T14:58:00Z", now: now, calendar: calendar))
        XCTAssertFalse(NudgeSchedule.isLoggedToday(latestWornAt: "2026-10-03T23:59:00-07:00", now: now, calendar: calendar))
        XCTAssertFalse(NudgeSchedule.isLoggedToday(latestWornAt: nil, now: now, calendar: calendar))
        XCTAssertFalse(NudgeSchedule.isLoggedToday(latestWornAt: "garbage", now: now, calendar: calendar))
    }

    func testActionIdentifierRoundTrip() {
        let id = NudgeSchedule.actionIdentifier(forWatchID: "3m2uvdvq7622g")
        XCTAssertEqual(id, "log:3m2uvdvq7622g")
        XCTAssertEqual(NudgeSchedule.watchID(fromActionIdentifier: id), "3m2uvdvq7622g")
        XCTAssertNil(NudgeSchedule.watchID(fromActionIdentifier: "com.apple.UNNotificationDefaultActionIdentifier"))
        XCTAssertNil(NudgeSchedule.watchID(fromActionIdentifier: "log:"))
    }

    func testConfigClampsRanges() {
        let c = NudgeConfig(enabled: true, hour: 27, minute: -5)
        XCTAssertEqual(c.hour, 23)
        XCTAssertEqual(c.minute, 0)
        XCTAssertEqual(NudgeConfig.default, NudgeConfig(enabled: false, hour: 8, minute: 0))
    }
}
