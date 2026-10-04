import UserNotifications
import XCTest
import WristCore
@testable import WristKit

@MainActor
final class NudgeSchedulerTests: XCTestCase {
    private let enabled = NudgeConfig(enabled: true, hour: 8, minute: 0)

    private func makeScheduler(_ center: FakeNotificationCenter) -> NudgeScheduler {
        let now = date(2026, 10, 4, 7, 0)
        return NudgeScheduler(center: center, calendar: testCalendar, now: { now })
    }

    private func nudgeRequests(_ center: FakeNotificationCenter) -> [UNNotificationRequest] {
        center.pending.filter { NudgeSchedule.isNudgeRequest(identifier: $0.identifier) }
    }

    func testRescheduleCreatesCategoryWithTopThreeActions() async {
        let center = FakeNotificationCenter()
        let scheduler = makeScheduler(center)
        await scheduler.reschedule(config: enabled, state: makeState(watches: fiveWatches, current: nil))

        XCTAssertEqual(center.categories.count, 1)
        guard let category = center.categories.first else { return XCTFail("no category") }
        XCTAssertEqual(category.identifier, NudgeSchedule.categoryIdentifier)
        XCTAssertEqual(category.actions.count, 3)
        XCTAssertEqual(
            category.actions.map(\.identifier),
            [W1, W2, W3].map { NudgeSchedule.actionIdentifier(forWatchID: $0.id) }
        )
        XCTAssertEqual(category.actions.map(\.title), Ranking.shortLabels(for: [W1, W2, W3]))
    }

    func testRescheduleAddsSevenDailyRequestsStartingToday() async {
        let center = FakeNotificationCenter()
        let scheduler = makeScheduler(center)
        await scheduler.reschedule(config: enabled, state: makeState(watches: fiveWatches, current: nil))

        let requests = nudgeRequests(center)
        XCTAssertEqual(requests.count, 7)
        XCTAssertEqual(
            requests.map(\.identifier),
            (4...10).map { String(format: "nudge-2026-10-%02d", $0) }
        )
        for request in requests {
            guard let trigger = request.trigger as? UNCalendarNotificationTrigger else {
                XCTFail("expected calendar trigger for \(request.identifier)")
                continue
            }
            XCTAssertFalse(trigger.repeats)
            XCTAssertEqual(trigger.dateComponents.hour, 8)
            XCTAssertEqual(trigger.dateComponents.minute, 0)
            XCTAssertEqual(request.content.categoryIdentifier, NudgeSchedule.categoryIdentifier)
            XCTAssertEqual(request.content.title, NudgeScheduler.title)
        }
    }

    func testRescheduleSkipsTodayWhenLoggedToday() async {
        let center = FakeNotificationCenter()
        let scheduler = makeScheduler(center)
        let event = WearEvent(id: "e", watchId: W1.id, wornAt: "2026-10-04T06:30:00-07:00", source: .app)
        await scheduler.reschedule(config: enabled, state: makeState(watches: fiveWatches, current: event))

        let requests = nudgeRequests(center)
        XCTAssertEqual(requests.count, 7)
        XCTAssertEqual(requests.first?.identifier, "nudge-2026-10-05")
    }

    func testRescheduleRemovesStaleNudgesOnly() async {
        let center = FakeNotificationCenter()
        center.pending = [
            UNNotificationRequest(identifier: "nudge-2026-01-01", content: UNMutableNotificationContent(), trigger: nil),
            UNNotificationRequest(identifier: "other-thing", content: UNMutableNotificationContent(), trigger: nil),
        ]
        let scheduler = makeScheduler(center)
        await scheduler.reschedule(config: enabled, state: makeState(watches: fiveWatches, current: nil))

        XCTAssertEqual(center.removed, ["nudge-2026-01-01"])
        XCTAssertTrue(center.pending.contains { $0.identifier == "other-thing" })
        XCTAssertFalse(center.pending.contains { $0.identifier == "nudge-2026-01-01" })
    }

    func testDisabledRemovesEverythingAndAddsNothing() async {
        let center = FakeNotificationCenter()
        center.pending = [
            UNNotificationRequest(identifier: "nudge-2026-10-04", content: UNMutableNotificationContent(), trigger: nil),
        ]
        XCTAssertTrue(center.categories.isEmpty)
        let scheduler = makeScheduler(center)
        await scheduler.reschedule(config: NudgeConfig(enabled: false, hour: 8, minute: 0),
                                   state: makeState(watches: fiveWatches, current: nil))

        XCTAssertTrue(center.removed.contains("nudge-2026-10-04"))
        XCTAssertTrue(nudgeRequests(center).isEmpty)
        XCTAssertTrue(center.categories.isEmpty)
    }

    func testEnsureAuthorizedPromptsOnlyWhenUndetermined() async {
        let undetermined = FakeNotificationCenter()
        undetermined.status = .notDetermined
        undetermined.authorizationResult = true
        let granted = await makeScheduler(undetermined).ensureAuthorized()
        XCTAssertTrue(granted)
        XCTAssertEqual(undetermined.authorizationRequests, 1)

        let denied = FakeNotificationCenter()
        denied.status = .denied
        let deniedResult = await makeScheduler(denied).ensureAuthorized()
        XCTAssertFalse(deniedResult)
        XCTAssertEqual(denied.authorizationRequests, 0)

        let authorized = FakeNotificationCenter()
        authorized.status = .authorized
        let authorizedResult = await makeScheduler(authorized).ensureAuthorized()
        XCTAssertTrue(authorizedResult)
        XCTAssertEqual(authorized.authorizationRequests, 0)
    }
}
