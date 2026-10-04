import Foundation
import UserNotifications

/// The slice of UNUserNotificationCenter that NudgeScheduler needs, so tests
/// can substitute a fake.
public protocol NotificationCenterClient: AnyObject {
    func requestAuthorization() async throws -> Bool
    func authorizationStatus() async -> UNAuthorizationStatus
    func setCategories(_ categories: Set<UNNotificationCategory>)
    func pendingRequestIdentifiers() async -> [String]
    func addRequest(_ request: UNNotificationRequest) async throws
    func removePendingRequests(withIdentifiers identifiers: [String])
}

extension UNUserNotificationCenter: NotificationCenterClient {
    public func requestAuthorization() async throws -> Bool {
        try await requestAuthorization(options: [.alert, .sound])
    }

    public func authorizationStatus() async -> UNAuthorizationStatus {
        await notificationSettings().authorizationStatus
    }

    public func setCategories(_ categories: Set<UNNotificationCategory>) {
        setNotificationCategories(categories)
    }

    public func pendingRequestIdentifiers() async -> [String] {
        await pendingNotificationRequests().map(\.identifier)
    }

    public func addRequest(_ request: UNNotificationRequest) async throws {
        try await add(request)
    }

    public func removePendingRequests(withIdentifiers identifiers: [String]) {
        removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
