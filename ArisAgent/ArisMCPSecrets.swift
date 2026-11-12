//
//  ArisMCPSecrets.swift
//  aris-agent
//
//  The Composio key and each MCP server's token, in the macOS Keychain (generic passwords, service
//  com.lumenjsn.aris.mcp, one account per server id), where Aris keeps its other keys. The agent saves and reads them
//  itself: the app hands a secret over once (POST /mcp, ArisPeer) and only ever hears back whether one is saved. A
//  secret goes only into its own server's header or environment, and is replaced with dots in anything a brain or a log
//  could see (ArisMCPPolicy.redacted).
//

import Foundation
import Security

/// What looking a secret up found: the secret, nothing saved under that name, or a Keychain that couldn't be read just
/// now (locked, a prompt denied, an agent whose signature changed). The last is not "nothing there": what depends on it
/// waits, and nothing is deleted or written over because of it (audit mcp-3).
enum ArisMCPSecretLookup: Equatable {
    case found(String)
    case missing
    case unreadable
}

protocol ArisMCPSecretStore: AnyObject {
    func secret(for id: String) -> String?
    /// `secret(for:)`, telling "nothing saved" from "couldn't read".
    func lookup(_ id: String) -> ArisMCPSecretLookup
    /// Nil when saved, else what to tell the user.
    func save(_ secret: String, for id: String) -> String?
    @discardableResult func delete(_ id: String) -> Bool
    /// Every account saved under this store (server ids and the list's signing key).
    func accounts() -> [String]
}

extension ArisMCPSecretStore {
    func lookup(_ id: String) -> ArisMCPSecretLookup { secret(for: id).map(ArisMCPSecretLookup.found) ?? .missing }
}

final class ArisMCPKeychain: ArisMCPSecretStore {
    static let service = "com.lumenjsn.aris.mcp"
    let service: String

    init(service: String = ArisMCPKeychain.service) {
        self.service = service
    }

    /// The Keychain query for one server's secret.
    static func query(service: String, id: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id]
    }

    func secret(for id: String) -> String? {
        if case .found(let secret) = lookup(id) { return secret }
        return nil
    }

    func lookup(_ id: String) -> ArisMCPSecretLookup {
        var request = Self.query(service: service, id: id)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        return Self.lookup(status: status, data: item as? Data)
    }

    /// What a Keychain answer means: only "no such item" is nothing saved; any other failure is a Keychain that
    /// couldn't be read.
    static func lookup(status: OSStatus, data: Data?) -> ArisMCPSecretLookup {
        if status == errSecSuccess, let data { return .found(String(decoding: data, as: UTF8.self)) }
        if status == errSecItemNotFound { return .missing }
        FileHandle.standardError.write(Data("aris-agent: keychain read for an MCP server failed (\(status))\n".utf8))
        return .unreadable
    }

    func save(_ secret: String, for id: String) -> String? {
        let data = Data(secret.utf8)
        var status = SecItemUpdate(Self.query(service: service, id: id) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = Self.query(service: service, id: id)
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = "Aris – MCP \(id)"
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            FileHandle.standardError.write(Data("aris-agent: keychain save for an MCP server failed (\(status))\n".utf8))
            return "키체인에 저장하지 못했어요 (오류 \(status))."
        }
        return nil
    }

    @discardableResult
    func delete(_ id: String) -> Bool {
        let status = SecItemDelete(Self.query(service: service, id: id) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    func accounts() -> [String] {
        let request: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                      kSecMatchLimit as String: kSecMatchLimitAll, kSecReturnAttributes as String: true]
        var items: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &items) == errSecSuccess, let found = items as? [[String: Any]] else { return [] }
        return found.compactMap { $0[kSecAttrAccount as String] as? String }
    }
}

/// A store in memory, for the tests.
final class ArisMCPMemorySecrets: ArisMCPSecretStore {
    private let lock = NSLock()
    private var secrets: [String: String] = [:]
    var failSaves = false
    /// The Keychain can't be read (locked, denied): every lookup says so, and nothing is found.
    var failReads = false

    func secret(for id: String) -> String? { lock.withLock { failReads ? nil : secrets[id] } }

    func lookup(_ id: String) -> ArisMCPSecretLookup {
        lock.withLock { failReads ? .unreadable : secrets[id].map(ArisMCPSecretLookup.found) ?? .missing }
    }

    func save(_ secret: String, for id: String) -> String? {
        lock.withLock {
            guard !failSaves else { return "키체인에 저장하지 못했어요 (오류 -1)." }
            secrets[id] = secret
            return nil
        }
    }

    @discardableResult
    func delete(_ id: String) -> Bool { lock.withLock { secrets[id] = nil; return true } }

    var all: [String: String] { lock.withLock { secrets } }

    func accounts() -> [String] { lock.withLock { Array(secrets.keys) } }
}
