import Foundation
import UserNotifications
import WristCore

/// UNUserNotificationCenterDelegate for the nudge. Action buttons log the
/// chosen watch without opening the UI; the default tap just opens the app.
public final class NotificationActionHandler: NSObject, UNUserNotificationCenterDelegate {
    public typealias LogHandler = @MainActor (_ watchID: String) async -> Void
    public typealias OpenHandler = @MainActor () -> Void

    private let onLog: LogHandler
    private let onOpen: OpenHandler

    public init(onLog: @escaping LogHandler, onOpen: @escaping OpenHandler = {}) {
        self.onLog = onLog
        self.onOpen = onOpen
    }

    /// Show the nudge even if the app happens to be in the foreground.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionID = response.actionIdentifier
        let onLog = self.onLog
        let onOpen = self.onOpen
        Task { @MainActor in
            if let watchID = NudgeSchedule.watchID(fromActionIdentifier: actionID) {
                await onLog(watchID)
            } else if actionID == UNNotificationDefaultActionIdentifier {
                onOpen()
            }
            completionHandler()
        }
    }
}
