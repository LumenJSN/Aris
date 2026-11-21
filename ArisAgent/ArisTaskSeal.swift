//
//  ArisTaskSeal.swift
//  aris-agent
//
//  The helper trusts its task journals and its list of running brains when it starts (which task to take back, with
//  whose words; which process to stop). A brain must not be able to write either: their folder is on every brain's
//  deny list like the scheduler's files, and every line is sealed with an HMAC-SHA256 whose key only the helper reads
//  (~/.config/aris/tasks-key, 0600: a `*-key` file in Aris's folder, which every brain's rules refuse to read and the
//  risk gate counts as a secret). A journal line's seal also binds its job, its place and the seal before it (a chain):
//  a line moved from another journal, reordered or repeated breaks it, and nothing from there on counts. The running
//  brains' list is bound to a generation the helper moves on at every start, so an older list never opens.
//

import CryptoKit
import Foundation

enum ArisTaskSeal {
    static func keyFile(home: String) -> URL {
        URL(fileURLWithPath: home).appendingPathComponent(".config/aris/tasks-key")
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var keys: [String: SymmetricKey] = [:]

    /// The helper's key (made once, 32 random bytes); nil when it can't be read or written privately.
    static func key(home: String) -> SymmetricKey? {
        lock.withLock {
            if let known = keys[home] { return known }
            let file = keyFile(home: home)
            if let data = ArisPrivateFile.read(file), data.count == 32 {
                keys[home] = SymmetricKey(data: data)
                return keys[home]
            }
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess, (try? ArisPrivateFile.write(Data(bytes), to: file)) != nil,
                  ArisPrivateFile.read(file) == Data(bytes) else { return nil }
            keys[home] = SymmetricKey(data: Data(bytes))
            return keys[home]
        }
    }

    /// A journal line's seal, bound to its job, its place and the seal before it (a chain): the same record copied to
    /// another journal, moved, repeated or reordered no longer verifies.
    static func lineSeal(_ json: Data, job: String, index: Int, previous: String, key: SymmetricKey) -> String {
        seal(context("task", job, String(index), previous) + json, key: key)
    }

    static func context(_ parts: String...) -> Data {
        Data(parts.map { $0 + "\n" }.joined().utf8)
    }

    static func seal(_ data: Data, key: SymmetricKey) -> String {
        Data(HMAC<SHA256>.authenticationCode(for: data, using: key)).base64EncodedString()
    }

    static func verifies(_ data: Data, seal: String, key: SymmetricKey) -> Bool {
        guard let code = Data(base64Encoded: seal) else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(code, authenticating: data, using: key)
    }

    /// `data` sealed as one file of kind `purpose` (bound to it: a file of one kind never opens as another): `<seal> <data>`.
    static func sealedFile(_ data: Data, purpose: String, home: String) -> Data? {
        guard let key = key(home: home) else { return nil }
        return Data((seal(context(purpose) + data, key: key) + " ").utf8) + data
    }

    /// A sealed file's data; nil when its seal doesn't match.
    static func opened(_ file: Data, purpose: String, home: String) -> Data? {
        guard let key = key(home: home), let space = file.firstIndex(of: 0x20) else { return nil }
        let data = Data(file[file.index(after: space)...])
        return verifies(context(purpose) + data, seal: String(decoding: file[file.startIndex..<space], as: UTF8.self), key: key) ? data : nil
    }
}
