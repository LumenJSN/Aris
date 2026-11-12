//
//  ArisKeychain.swift
//  Aris
//
//  The API keys in the macOS Keychain (generic passwords, service com.lumenjsn.aris.keys, one account per key name),
//  never in a plain file. ArisKeyFile reads through `read` (set as its secureStore at launch). A key read once is kept
//  in memory so a turn never waits on the Keychain; saving or deleting updates that copy.
//

import Foundation
import Security
import os

enum ArisKeychain {
    static let service = "com.lumenjsn.aris.keys"
    private static let log = Logger(subsystem: "com.lumenjsn.aris", category: "keychain")
    private static let cache = OSAllocatedUnfairLock<[String: String?]>(initialState: [:])

    enum Failure: Error, Equatable {
        case status(OSStatus)

        var message: String { "키체인에 저장하지 못했어요 (오류 \(code))." }
        private var code: OSStatus { if case .status(let status) = self { return status }; return 0 }
    }

    private static func query(_ name: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: name]
    }

    /// The key saved under `name`, or nil.
    static func read(_ name: String) -> String? {
        if let cached = cache.withLock({ $0[name] }) { return cached }
        return readUncached(name)
    }

    /// Straight from the Keychain (refreshing the copy in memory): the read-back before an old file may go.
    static func readUncached(_ name: String) -> String? {
        var request = query(name)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        let key = status == errSecSuccess ? (item as? Data).map { String(decoding: $0, as: UTF8.self) } : nil
        if status != errSecSuccess && status != errSecItemNotFound {
            log.error("read \(name, privacy: .public) failed: \(status, privacy: .public)")
        }
        cache.withLock { $0[name] = .some(key) }
        return key
    }

    /// Saves (or replaces) the key under `name`.
    static func save(_ key: String, as name: String) -> Result<Void, Failure> {
        let data = Data(key.utf8)
        var status = SecItemUpdate(query(name) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(name)
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = "Aris – \(name)"
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            log.error("save \(name, privacy: .public) failed: \(status, privacy: .public)")
            return .failure(.status(status))
        }
        cache.withLock { $0[name] = .some(key) }
        // A new key ends an earlier delete.
        if !name.hasSuffix(".deleted") { delete(ArisKeyFile.tombstone(name)) }
        return .success(())
    }

    /// Removes the key under `name` (nothing saved is fine).
    @discardableResult
    static func delete(_ name: String) -> Bool {
        let status = SecItemDelete(query(name) as CFDictionary)
        cache.withLock { $0[name] = .some(nil) }
        if status != errSecSuccess && status != errSecItemNotFound {
            log.error("delete \(name, privacy: .public) failed: \(status, privacy: .public)")
            return false
        }
        return true
    }

    /// Whether the user deleted `name` in settings (and hasn't saved a new one since).
    static func isTombstoned(_ name: String) -> Bool { read(ArisKeyFile.tombstone(name)) != nil }

    /// Removes the key and leaves a tombstone, so neither the file fallback nor the migration brings it back; then the
    /// agent removes the old file. Nil when done, else what to tell the user.
    static func deleteKey(_ name: String) async -> String? {
        // The tombstone first: without it the old file could bring the key back, so nothing is deleted.
        guard case .success = save("1", as: ArisKeyFile.tombstone(name)) else {
            log.error("tombstone for \(name, privacy: .public) not saved; nothing deleted")
            return "키체인에 삭제 표시를 남기지 못해서 키를 지우지 않았어요. 다시 해 주세요."
        }
        guard delete(name) else { return "키체인에서 키를 지우지 못했어요. 다시 해 주세요." }
        guard ArisKeyFile.fileKey(name) != nil else { return nil }
        if await dropVerifiedFile(name), ArisKeyFile.fileKey(name) == nil { return nil }
        return "키는 지웠지만 예전 키 파일은 남아 있어요. Aris는 그 파일을 쓰지 않아요. 에이전트가 켜지면 다시 지워 주세요."
    }

    /// Asks the agent to remove the old file only after reading the Keychain back: the key is there (the one `expecting`,
    /// when given), or the delete's tombstone is. False when that can't be shown, or the agent said no.
    static func dropVerifiedFile(_ name: String, expecting key: String? = nil) async -> Bool {
        let tombstoned = readUncached(ArisKeyFile.tombstone(name)) != nil
        guard let check = ArisKeyFile.keychainCheck(stored: readUncached(name), expected: key, tombstoned: tombstoned) else {
            log.error("\(name, privacy: .public) not found in the Keychain on read-back; its old file stays")
            return false
        }
        return await ArisAgentClient.dropKeyFile(name, keychain: check)
    }

    /// Keys still in old hand-placed files go into the Keychain, then the agent removes the file (the sandboxed app
    /// can only read ~/.config/aris). A file whose key is already in the Keychain, or that the user deleted, is just removed.
    static func migrateFiles() async {
        for name in ArisKeyFile.names {
            let fileKey = ArisKeyFile.fileKey(name)
            var expected: String?
            switch ArisKeyFile.migration(fileKey: fileKey, keychainKey: read(name), tombstoned: isTombstoned(name)) {
            case .none: continue
            case .importThenDrop:
                guard let fileKey, case .success = save(fileKey, as: name) else { continue }
                expected = fileKey
            case .dropOnly:
                // Only when the file holds the Keychain's own key (or the key was deleted): another key stays put.
                expected = ArisKeyFile.dropExpectation(fileKey: fileKey ?? "", tombstoned: isTombstoned(name))
            }
            if await dropVerifiedFile(name, expecting: expected) == false {
                log.notice("the old \(name, privacy: .public) file stays for now; tried again next launch")
            }
        }
    }
}
