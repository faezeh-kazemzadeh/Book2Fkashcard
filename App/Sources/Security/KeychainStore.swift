import Foundation
import Security

/// Minimal Keychain wrapper for generic passwords.
struct KeychainStore: Sendable {
    enum Accessibility {
        /// Device-only, readable after first unlock (background work).
        case afterFirstUnlockThisDeviceOnly
        /// Synchronised through iCloud Keychain to the user's other devices.
        case afterFirstUnlockSynchronizable

        var isSynchronizable: Bool { self == .afterFirstUnlockSynchronizable }
        var resolvedAttribute: CFString {
            self == .afterFirstUnlockThisDeviceOnly ? kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly : kSecAttrAccessibleAfterFirstUnlock
        }
    }

    struct KeychainError: Error, LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
        }
    }

    let service: String

    init(service: String = AppConstants.keychainService) {
        self.service = service
    }

    private func baseQuery(_ account: String, synchronizable: Bool) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: synchronizable ? kCFBooleanTrue as Any : kCFBooleanFalse as Any
        ]
    }

    func set(_ data: Data, for account: String, accessibility: Accessibility = .afterFirstUnlockThisDeviceOnly) throws {
        let query = baseQuery(account, synchronizable: accessibility.isSynchronizable)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessibility.resolvedAttribute
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { _, new in new }
            status = SecItemAdd(insert as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    func data(for account: String, synchronizable: Bool = false) throws -> Data? {
        var query = baseQuery(account, synchronizable: synchronizable)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        return result as? Data
    }

    func remove(_ account: String, synchronizable: Bool = false) throws {
        let status = SecItemDelete(baseQuery(account, synchronizable: synchronizable) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}
