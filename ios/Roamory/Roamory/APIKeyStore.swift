//
//  APIKeyStore.swift
//  Roamory
//

import Foundation
import Security

/// The Anthropic API key, entered on the phone and kept in the Keychain. It is never part of the app bundle.
enum APIKeyStore {
    private static let identity: [CFString: Any] = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: "roamory.anthropic",
        kSecAttrAccount: "api-key",
    ]

    static func load() -> String? {
        var query = identity
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Stores `key`, replacing any earlier one.
    @discardableResult
    static func save(_ key: String) -> Bool {
        delete()
        var item = identity
        item[kSecValueData] = Data(key.utf8)
        item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        SecItemDelete(identity as CFDictionary)
    }
}
