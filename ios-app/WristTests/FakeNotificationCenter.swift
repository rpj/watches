import UserNotifications
@testable import WristKit

final class FakeNotificationCenter: NotificationCenterClient {
    var status: UNAuthorizationStatus = .notDetermined
    var authorizationResult = true
    private(set) var authorizationRequests = 0
    private(set) var categories: Set<UNNotificationCategory> = []
    var pending: [UNNotificationRequest] = []
    private(set) var removed: [String] = []

    func requestAuthorization() async throws -> Bool {
        authorizationRequests += 1
        status = authorizationResult ? .authorized : .denied
        return authorizationResult
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        status
    }

    func setCategories(_ categories: Set<UNNotificationCategory>) {
        self.categories = categories
    }

    func pendingRequestIdentifiers() async -> [String] {
        pending.map(\.identifier)
    }

    func addRequest(_ request: UNNotificationRequest) async throws {
        pending.append(request)
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        removed.append(contentsOf: identifiers)
        pending.removeAll { identifiers.contains($0.identifier) }
    }
}
