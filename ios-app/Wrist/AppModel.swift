import SwiftUI
import Observation
import UserNotifications
import WristCore
import WristKit

/// Errors surfaced by the Setup screen while verifying a connection.
enum ConnectError: LocalizedError {
    case invalidURL
    case emptyToken
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Enter a valid http(s) URL"
        case .emptyToken: return "Enter the API token"
        case .server(let message): return message
        }
    }
}

/// Bridges the `WearStore` actor and the notification/scheduler seams to SwiftUI.
@MainActor @Observable
final class AppModel {
    enum Phase: Equatable { case loading, needsSetup, ready }

    let services: WristServices
    private(set) var phase: Phase = .loading
    private(set) var state: WearStore.State = .empty
    private(set) var store: WearStore?
    /// Drives the Undo bar; auto-cleared after 5 seconds.
    private(set) var lastLogged: NewWearEvent?
    private(set) var nudgeConfig: NudgeConfig
    private(set) var notificationsDenied = false
    private(set) var isConnecting = false
    private(set) var notificationHandler: NotificationActionHandler?
    let scheduler: NudgeScheduler

    private var observation: Task<Void, Never>?
    private var undoDismiss: Task<Void, Never>?
    private var hasStarted = false

    init(services: WristServices) {
        self.services = services
        self.nudgeConfig = services.settings.nudgeConfig
        self.scheduler = NudgeScheduler(center: services.notificationCenter)

        // Install the notification delegate during launch (before the first
        // frame), otherwise an action tap that cold-starts the app is dropped.
        let handler = NotificationActionHandler(
            onLog: { [weak self] watchID in
                guard let self else { return }
                await self.logFromNotification(watchID: watchID)
            },
            onOpen: {}
        )
        notificationHandler = handler
        UNUserNotificationCenter.current().delegate = handler
    }

    // MARK: - Derived

    var currentWatch: WearWatch? {
        state.watches.first { $0.id == state.current?.watchId }
    }

    var isLoggedToday: Bool {
        NudgeSchedule.isLoggedToday(latestWornAt: state.current?.wornAt, now: Date(), calendar: .autoupdatingCurrent)
    }

    // MARK: - Lifecycle

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        if services.isConfigured, let store = services.makeStore() {
            attach(store)
            phase = .ready
            await store.loadCached()
            await refresh()
            await rescheduleNudges()
        } else {
            phase = .needsSetup
        }
    }

    func handleForeground() {
        guard hasStarted, let store else { return }
        Task { [weak self] in
            // The widget or a notification action may have logged while we
            // were suspended; pick that up from disk before syncing.
            await store.loadCached()
            await store.refresh()
            guard let self else { return }
            await self.rescheduleNudges()
            WristServices.reloadWidgets()
        }
    }

    private func attach(_ store: WearStore) {
        observation?.cancel()
        self.store = store
        observation = Task { [weak self] in
            for await s in await store.updates() {
                self?.state = s
            }
        }
    }

    // MARK: - Connection

    func connect(serverURL: URL, token: String) async throws {
        isConnecting = true
        defer { isConnecting = false }

        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw ConnectError.emptyToken }
        let trimmed = serverURL.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host() != nil else {
            throw ConnectError.invalidURL
        }

        let client = services.makeClient(baseURL: url, token: token)
        do {
            _ = try await client.watches()
        } catch {
            throw ConnectError.server(WearStore.message(for: error))
        }

        try services.saveConnection(serverURL: url, token: token)
        guard let store = services.makeStore() else {
            throw ConnectError.server("Could not save the connection")
        }
        attach(store)
        phase = .ready
        await refresh()
        await rescheduleNudges()
    }

    func resetConnection() async {
        await scheduler.reschedule(
            config: NudgeConfig(enabled: false, hour: nudgeConfig.hour, minute: nudgeConfig.minute),
            state: .empty
        )
        services.resetConnection()
        observation?.cancel()
        undoDismiss?.cancel()
        store = nil
        state = .empty
        lastLogged = nil
        nudgeConfig = services.settings.nudgeConfig
        phase = .needsSetup
    }

    // MARK: - Logging

    func log(_ watch: WearWatch, source: WearSource = .app) async {
        guard let store else { return }
        let (event, _) = await store.logWear(watchID: watch.id, source: source)
        lastLogged = event
        undoDismiss?.cancel()
        undoDismiss = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { self?.lastLogged = nil }
        }
        WristServices.reloadWidgets()
        await rescheduleNudges()
    }

    func logFromNotification(watchID: String) async {
        if store == nil, let made = services.makeStore() {
            attach(made)
            if phase != .ready { phase = .ready }
        }
        guard let store else { return }
        await store.loadCached()
        await store.logWear(watchID: watchID, source: .notification)
        WristServices.reloadWidgets()
        await rescheduleNudges()
    }

    func undoLast() async {
        guard let event = lastLogged, let store else { return }
        lastLogged = nil
        undoDismiss?.cancel()
        await store.undo(eventID: event.id)
        WristServices.reloadWidgets()
        await rescheduleNudges()
    }

    func refresh() async {
        await store?.refresh()
    }

    // MARK: - Nudge

    func setNudge(_ config: NudgeConfig) async {
        var config = config
        if config.enabled && !nudgeConfig.enabled {
            let ok = await scheduler.ensureAuthorized()
            if !ok {
                notificationsDenied = true
                config.enabled = false
                services.settings.nudgeConfig = config
                nudgeConfig = config
                await rescheduleNudges()
                return
            }
        }
        notificationsDenied = false
        services.settings.nudgeConfig = config
        nudgeConfig = config
        await rescheduleNudges()
    }

    private func rescheduleNudges() async {
        await scheduler.reschedule(config: nudgeConfig, state: state)
    }
}
