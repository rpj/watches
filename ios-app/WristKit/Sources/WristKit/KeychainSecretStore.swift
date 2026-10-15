import Foundation
import Security
import WristCore

/// Keychain-backed SecretStore shared between the app and the widget via the
/// App Group access group. Items are `AfterFirstUnlockThisDeviceOnly`: readable
/// by notification actions and widget intents after a reboot without the
/// phone being unlocked again, but never migrated to another device through a
/// backup or iCloud Keychain (re-paste the token on a new phone).
public final class KeychainSecretStore: SecretStore, @unchecked Sendable {
    public enum KeychainError: Error, Equatable {
        case unexpectedStatus(OSStatus)
    }

    private let service: String
    private let accessGroup: String?

    public init(service: String = WristConstants.keychainService, accessGroup: String? = WristConstants.appGroupID) {
        self.service = service
        self.accessGroup = accessGroup
    }

    public func get(_ key: String) throws -> String? {
        try withGroupFallback { group in
            var query = self.baseQuery(for: key, accessGroup: group)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            switch status {
            case errSecSuccess:
                guard let data = item as? Data else { return .success(nil) }
                return .success(String(data: data, encoding: .utf8))
            case errSecItemNotFound:
                return .success(nil)
            default:
                return .failure(status)
            }
        }
    }

    public func set(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        try withGroupFallback { group in
            let query = self.baseQuery(for: key, accessGroup: group)
            let attributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ]
            let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            switch update {
            case errSecSuccess:
                return .success(())
            case errSecItemNotFound:
                var add = query
                add.merge(attributes) { _, new in new }
                let status = SecItemAdd(add as CFDictionary, nil)
                return status == errSecSuccess ? .success(()) : .failure(status)
            default:
                return .failure(update)
            }
        }
    }

    public func delete(_ key: String) throws {
        try withGroupFallback { group in
            let status = SecItemDelete(self.baseQuery(for: key, accessGroup: group) as CFDictionary)
            return (status == errSecSuccess || status == errSecItemNotFound) ? .success(()) : .failure(status)
        }
    }

    // MARK: - Internals

    private func baseQuery(for key: String, accessGroup: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    /// Run `operation` with the configured access group; if the Keychain says
    /// the entitlement is missing (common on the Simulator or when the App
    /// Group is not provisioned yet), retry once without a group so the app
    /// still works single-process.
    private func withGroupFallback<T>(_ operation: (String?) -> Result<T, StatusFailure>) throws -> T {
        switch operation(accessGroup) {
        case .success(let value):
            return value
        case .failure(let failure):
            if accessGroup != nil && failure.status == errSecMissingEntitlement {
                switch operation(nil) {
                case .success(let value): return value
                case .failure(let retry): throw KeychainError.unexpectedStatus(retry.status)
                }
            }
            throw KeychainError.unexpectedStatus(failure.status)
        }
    }

    public struct StatusFailure: Error {
        let status: OSStatus
    }
}

private extension Result where Failure == KeychainSecretStore.StatusFailure {
    static func failure(_ status: OSStatus) -> Result {
        .failure(KeychainSecretStore.StatusFailure(status: status))
    }
}
