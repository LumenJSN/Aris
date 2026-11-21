//
//  ArisVoiceIDStore.swift
//  Aris
//
//  Where the owner's voice print is kept (F1): one generic-password item in the login Keychain, its own service
//  (never the API keys' item), readable only while the Mac is unlocked, on this device only: never synced through
//  iCloud Keychain and never restored onto another Mac from a backup. The item holds the print's JSON
//  (ArisVoiceProfile: 256 numbers and two counts, no audio, no words). Nothing logs it. Deleting it removes the item;
//  the tests use the in-memory store.
//

import Foundation
import Security
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "voiceid")

protocol ArisVoiceIDStoring: AnyObject, Sendable {
    func load() -> Data?
    @discardableResult func save(_ data: Data) -> Bool
    @discardableResult func delete() -> Bool
}

final class ArisVoiceIDKeychain: ArisVoiceIDStoring, @unchecked Sendable {
    static let service = "com.lumenjsn.aris.voiceid"
    static let account = "owner"

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service, kSecAttrAccount as String: Self.account,
         kSecAttrSynchronizable as String: kCFBooleanFalse as Any]
    }

    func load() -> Data? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status != errSecSuccess, status != errSecItemNotFound { log.error("voice id: reading the print failed: \(status, privacy: .public)") }
        return status == errSecSuccess ? item as? Data : nil
    }

    func save(_ data: Data) -> Bool {
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = "Aris – 내 목소리"
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        if status != errSecSuccess { log.error("voice id: saving the print failed: \(status, privacy: .public)") }
        return status == errSecSuccess
    }

    func delete() -> Bool {
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess, status != errSecItemNotFound { log.error("voice id: deleting the print failed: \(status, privacy: .public)") }
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

/// A store that keeps the print in memory only (tests, and a Mac whose Keychain refuses: nothing is written anywhere).
final class ArisVoiceIDMemoryStore: ArisVoiceIDStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?

    init(_ data: Data? = nil) { self.data = data }

    func load() -> Data? { lock.withLock { data } }
    func save(_ data: Data) -> Bool { lock.withLock { self.data = data }; return true }
    func delete() -> Bool { lock.withLock { data = nil }; return true }
}
