import Foundation
import Security

/// API keys live in the login keychain, never in UserDefaults or on disk.
/// Values are write-mostly: the UI shows whether a key exists, not the key itself.
enum Keychain {
    private static let service = "com.voicesmith.apikeys"

    /// Stores a key, reporting whether it actually landed.
    ///
    /// The result is worth checking: a locked keychain or a denied ACL fails
    /// here and nowhere else. Treated as success, the field says "Stored" and
    /// the user finds out at their next dictation, as "no API key" — which
    /// reads as "I never entered one" rather than "saving it failed".
    static func set(_ value: String, for account: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            remove(account)
            return true
        }
        guard let data = trimmed.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
        }

        guard status == errSecSuccess else {
            NSLog("VoiceSmith: could not save the \(account) key to the Keychain (OSStatus \(status)).")
            return false
        }
        return true
    }

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8)
        else { return nil }
        return string
    }

    static func has(_ account: String) -> Bool {
        get(account)?.isEmpty == false
    }

    static func remove(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
