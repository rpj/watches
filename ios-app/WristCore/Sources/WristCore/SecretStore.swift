import Foundation

/// Minimal secret storage seam. The iOS app backs this with the Keychain
/// (WristKit.KeychainSecretStore); tests and Linux use the in-memory store.
public protocol SecretStore: Sendable {
    func get(_ key: String) throws -> String?
    func set(_ value: String, for key: String) throws
    func delete(_ key: String) throws
}

public enum SecretKeys {
    /// The bearer token for /api/wear/*.
    public static let apiToken = "wear.apiToken"
}

public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String]

    public init(_ values: [String: String] = [:]) {
        self.values = values
    }

    public func get(_ key: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }

    public func set(_ value: String, for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        values[key] = value
    }

    public func delete(_ key: String) throws {
        lock.lock(); defer { lock.unlock() }
        values[key] = nil
    }
}
