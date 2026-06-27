import Foundation
import Security

/// Minimal Keychain wrapper for small secrets (auth tokens, the admin PIN hash).
///
/// Items are stored with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`:
/// readable after the first unlock following a reboot, never synced to iCloud,
/// and never included in encrypted-or-unencrypted device backups. This is the
/// correct home for bearer tokens — unlike UserDefaults, the Keychain is
/// encrypted at rest and isolated from backups.
enum Keychain {
    /// All Cortex items share one service namespace.
    private static let service = "com.docriddles.cortex.secrets"

    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Store (or overwrite) a string value. Passing `nil` deletes the item.
    static func set(_ value: String?, for account: String) {
        guard let value, let data = value.data(using: .utf8) else { delete(account); return }
        var q = query(account)
        SecItemDelete(q as CFDictionary)            // replace any existing item
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }

    /// Read a string value, or `nil` if absent.
    static func get(_ account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}
