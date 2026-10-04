import Foundation
import UserNotifications
import WidgetKit
import WristCore

/// Composition root. The app, the widget extension, and notification/intent
/// handlers all obtain their collaborators from here so they share one
/// Keychain item, one settings suite, and one on-disk snapshot/queue.
public struct WristServices {
    public let settings: AppGroupStore
    public let secrets: any SecretStore
    public let persistence: any WearPersistence
    public let transport: any HTTPTransport
    public let notificationCenter: any NotificationCenterClient
    /// True when running with in-memory fixtures (`-uiTesting`).
    public let isFixture: Bool

    public init(
        settings: AppGroupStore,
        secrets: any SecretStore,
        persistence: any WearPersistence,
        transport: any HTTPTransport,
        notificationCenter: any NotificationCenterClient,
        isFixture: Bool = false
    ) {
        self.settings = settings
        self.secrets = secrets
        self.persistence = persistence
        self.transport = transport
        self.notificationCenter = notificationCenter
        self.isFixture = isFixture
    }

    /// Live services, or fixtures when the process was launched with `-uiTesting`.
    public static func current() -> WristServices {
        ProcessInfo.processInfo.arguments.contains(WristConstants.uiTestingArgument) ? fixtures() : live()
    }

    public static func live() -> WristServices {
        WristServices(
            settings: AppGroupStore(),
            secrets: KeychainSecretStore(),
            persistence: FileWearPersistence.shared(),
            transport: URLSessionTransport(),
            notificationCenter: UNUserNotificationCenter.current()
        )
    }

    /// Everything in memory, already "connected", so UI tests and previews
    /// land straight on the picker.
    public static func fixtures(transport: FixtureTransport = .sample()) -> WristServices {
        let defaults = UserDefaults(suiteName: "wrist.uiTesting") ?? .standard
        defaults.removePersistentDomain(forName: "wrist.uiTesting")
        let settings = AppGroupStore(defaults: defaults)
        settings.serverURL = URL(string: "https://fixture.test")!
        return WristServices(
            settings: settings,
            secrets: InMemorySecretStore([SecretKeys.apiToken: "fixture-token"]),
            persistence: InMemoryWearPersistence(),
            transport: transport,
            notificationCenter: UNUserNotificationCenter.current(),
            isFixture: true
        )
    }

    // MARK: - Connection

    public var serverURL: URL { settings.serverURL ?? WristConstants.defaultServerURL }

    public func token() -> String? {
        (try? secrets.get(SecretKeys.apiToken)).flatMap { $0 }
    }

    public var isConfigured: Bool {
        settings.serverURL != nil && !(token() ?? "").isEmpty
    }

    public func makeClient(baseURL: URL, token: String) -> WearAPIClient {
        WearAPIClient(configuration: WearAPIConfiguration(baseURL: baseURL, token: token), transport: transport)
    }

    /// Store for the saved connection, or nil until Setup has completed.
    public func makeStore() -> WearStore? {
        guard let token = token(), !token.isEmpty, let url = settings.serverURL else { return nil }
        return WearStore(client: makeClient(baseURL: url, token: token), persistence: persistence)
    }

    /// Persist a verified connection (call after `makeClient(...).watches()` succeeded).
    public func saveConnection(serverURL: URL, token: String) throws {
        try secrets.set(token, for: SecretKeys.apiToken)
        settings.serverURL = serverURL
    }

    /// Forget the token, server, settings, and cached data.
    public func resetConnection() {
        try? secrets.delete(SecretKeys.apiToken)
        settings.reset()
        (persistence as? FileWearPersistence)?.wipe()
        try? persistence.savePending([])
    }

    // MARK: - Widgets

    /// Ask WidgetKit to re-render after anything that changes the picker state.
    public static func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
