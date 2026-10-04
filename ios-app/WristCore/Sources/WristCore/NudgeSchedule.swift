import Foundation

/// User preference for the morning "what are you wearing?" nudge.
public struct NudgeConfig: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var hour: Int
    public var minute: Int

    public static let `default` = NudgeConfig(enabled: false, hour: 8, minute: 0)

    public init(enabled: Bool, hour: Int, minute: Int) {
        self.enabled = enabled
        self.hour = max(0, min(23, hour))
        self.minute = max(0, min(59, minute))
    }
}

/// Pure scheduling math for the nudge. iOS cannot skip a single occurrence
/// of a repeating local notification, so the app schedules one non-repeating
/// request per day for the next `horizonDays` days and re-plans whenever it
/// runs or a wear is logged. The platform layer (WristKit.NudgeScheduler)
/// turns these dates into UNNotificationRequests.
public enum NudgeSchedule {
    public static let horizonDays = 7
    public static let requestPrefix = "nudge-"
    public static let categoryIdentifier = "WEAR_PICK"
    public static let actionPrefix = "log:"
    /// Maximum watches offered as notification action buttons.
    public static let maxActions = 3

    /// True when the latest wear (`latestWornAt`, ISO 8601) falls on the same
    /// local day as `now` in `calendar`'s time zone.
    public static func isLoggedToday(latestWornAt: String?, now: Date, calendar: Calendar) -> Bool {
        guard let raw = latestWornAt, let date = WearDates.parse(raw) else { return false }
        return calendar.startOfDay(for: date) == calendar.startOfDay(for: now)
    }

    /// Fire dates for the next `horizonDays` days at the configured time.
    /// Today is included only if the time is still ahead and nothing has been
    /// logged today. Empty when disabled.
    public static func nextFireDates(config: NudgeConfig, now: Date, calendar: Calendar, loggedToday: Bool) -> [Date] {
        guard config.enabled else { return [] }
        var dates: [Date] = []
        let startOfToday = calendar.startOfDay(for: now)
        var offset = 0
        while dates.count < horizonDays && offset <= horizonDays {
            defer { offset += 1 }
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfToday) else { continue }
            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = config.hour
            components.minute = config.minute
            components.second = 0
            guard let fire = calendar.date(from: components) else { continue }
            if offset == 0 && (fire <= now || loggedToday) { continue }
            dates.append(fire)
        }
        return dates
    }

    /// Stable per-day identifier, e.g. "nudge-2026-10-04" (local date).
    public static func requestIdentifier(for date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return requestPrefix + "\(c.year ?? 0)-\(pad(c.month ?? 0))-\(pad(c.day ?? 0))"
    }

    public static func isNudgeRequest(identifier: String) -> Bool {
        identifier.hasPrefix(requestPrefix)
    }

    /// Identifier for the notification action that logs `watchID`.
    public static func actionIdentifier(forWatchID watchID: String) -> String {
        actionPrefix + watchID
    }

    /// Inverse of `actionIdentifier(forWatchID:)`; nil for the default tap or unrelated actions.
    public static func watchID(fromActionIdentifier identifier: String) -> String? {
        guard identifier.hasPrefix(actionPrefix) else { return nil }
        let id = String(identifier.dropFirst(actionPrefix.count))
        return id.isEmpty ? nil : id
    }

    private static func pad(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
