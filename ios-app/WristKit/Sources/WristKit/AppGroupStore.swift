import Foundation
import WristCore

/// Small, non-secret settings shared by the app and the widget through the
/// App Group UserDefaults suite. The API token never goes here (Keychain).
public final class AppGroupStore: @unchecked Sendable {
    private enum Key {
        static let serverURL = "wear.serverURL"
        static let nudgeConfig = "wear.nudgeConfig"
    }

    private let defaults: UserDefaults
    private let lock = NSLock()

    /// Uses the App Group suite, falling back to standard defaults when the
    /// group container is unavailable (missing entitlement).
    public convenience init(suiteName: String = WristConstants.appGroupID) {
        self.init(defaults: UserDefaults(suiteName: suiteName) ?? .standard)
    }

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public var serverURL: URL? {
        get {
            lock.lock(); defer { lock.unlock() }
            return defaults.string(forKey: Key.serverURL).flatMap(URL.init(string:))
        }
        set {
            lock.lock(); defer { lock.unlock() }
            defaults.set(newValue?.absoluteString, forKey: Key.serverURL)
        }
    }

    public var nudgeConfig: NudgeConfig {
        get {
            lock.lock(); defer { lock.unlock() }
            guard let data = defaults.data(forKey: Key.nudgeConfig),
                  let config = try? JSONDecoder().decode(NudgeConfig.self, from: data) else {
                return .default
            }
            return config
        }
        set {
            lock.lock(); defer { lock.unlock() }
            defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.nudgeConfig)
        }
    }

    public func reset() {
        lock.lock(); defer { lock.unlock() }
        defaults.removeObject(forKey: Key.serverURL)
        defaults.removeObject(forKey: Key.nudgeConfig)
    }
}
