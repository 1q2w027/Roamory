//
//  APIKeyStore.swift
//  Roamory
//

import Foundation

/// The Anthropic API key, entered on the phone and kept in the Keychain. It is never part of the app bundle.
enum APIKeyStore {
    private static let item = KeychainItem(service: "roamory.anthropic", account: "api-key")

    static func load() -> String? { item.load() }

    /// Stores `key`, replacing any earlier one.
    @discardableResult
    static func save(_ key: String) -> Bool { item.save(key) }

    static func delete() { item.delete() }
}
