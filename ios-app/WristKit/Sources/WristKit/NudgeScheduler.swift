import Foundation
import UserNotifications
import WristCore

/// Turns NudgeSchedule's dates into local notifications whose action buttons
/// log the top watches directly from the lock screen.
///
/// Call `reschedule` whenever the plan might have changed: app foreground,
/// after any wear is logged, after a refresh, and when settings change.
@MainActor
public final class NudgeScheduler {
    public static let title = "What's on your wrist?"
    public static let body = "Tap a watch to log it, or open Wrist to pick."

    private let center: any NotificationCenterClient
    private let calendar: Calendar
    private let now: () -> Date

    public init(
        center: any NotificationCenterClient = UNUserNotificationCenter.current(),
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping () -> Date = { Date() }
    ) {
        self.center = center
        self.calendar = calendar
        self.now = now
    }

    /// Prompt on first use; afterwards just report whether we may notify.
    public func ensureAuthorized() async -> Bool {
        switch await center.authorizationStatus() {
        case .notDetermined:
            return (try? await center.requestAuthorization()) ?? false
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    /// Replace every pending nudge with a fresh plan for the next week.
    /// Disabled config → everything removed.
    public func reschedule(config: NudgeConfig, state: WearStore.State) async {
        let stale = await center.pendingRequestIdentifiers().filter(NudgeSchedule.isNudgeRequest)
        center.removePendingRequests(withIdentifiers: stale)
        guard config.enabled else { return }

        let top = Ranking.topWatches(state.watches, limit: NudgeSchedule.maxActions)
        center.setCategories([Self.category(for: top)])

        let current = now()
        let loggedToday = NudgeSchedule.isLoggedToday(latestWornAt: state.current?.wornAt, now: current, calendar: calendar)
        for date in NudgeSchedule.nextFireDates(config: config, now: current, calendar: calendar, loggedToday: loggedToday) {
            try? await center.addRequest(Self.request(for: date, calendar: calendar))
        }
    }

    /// Category with one action per watch, titled by `Ranking.shortLabels`.
    public static func category(for watches: [WearWatch]) -> UNNotificationCategory {
        let labels = Ranking.shortLabels(for: watches)
        let actions = zip(watches, labels).map { watch, label in
            UNNotificationAction(
                identifier: NudgeSchedule.actionIdentifier(forWatchID: watch.id),
                title: label,
                options: []
            )
        }
        return UNNotificationCategory(
            identifier: NudgeSchedule.categoryIdentifier,
            actions: actions,
            intentIdentifiers: [],
            options: []
        )
    }

    /// One non-repeating calendar request for `date`, identified by local day.
    public static func request(for date: Date, calendar: Calendar) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = NudgeSchedule.categoryIdentifier
        content.threadIdentifier = "nudge"

        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        components.second = 0
        components.timeZone = calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        return UNNotificationRequest(
            identifier: NudgeSchedule.requestIdentifier(for: date, calendar: calendar),
            content: content,
            trigger: trigger
        )
    }
}
