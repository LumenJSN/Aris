//
//  ArisKeyFile.swift
//  Aris
//
//  API keys Aris uses (ElevenLabs, TypeSafe). They live in the macOS Keychain (ArisKeychain, set as `secureStore` at
//  launch); settings › AI 서비스 › API 키 saves them there. A key still in an old hand-placed file in ~/.config/aris/ is
//  read as a fallback until it is moved (ArisKeychain.migrateFiles). Never in the code. A missing key just turns that
//  feature off.
//

import Foundation

enum ArisKeyFile {
    static let folder = UserHome.path + "/.config/aris/"

    /// The keys the settings page manages, by their file (and Keychain account) name.
    static let names = ["elevenlabs-key", "typesafe-key"]

    /// The Keychain lookup, set by the app at launch (nil in tests and tools, which read files only).
    nonisolated(unsafe) static var secureStore: ((String) -> String?)?
    /// Whether the user deleted that key in settings (a Keychain tombstone, ArisKeychain), set with secureStore.
    nonisolated(unsafe) static var isTombstoned: ((String) -> Bool)?

    static func key(from contents: String?) -> String? {
        let key = contents?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return key.isEmpty ? nil : key
    }

    /// The Keychain first, then the old file (unless the key was deleted).
    static func load(_ name: String) -> String? {
        resolve(keychain: secureStore?(name).flatMap { key(from: $0) }, tombstoned: isTombstoned?(name) ?? false, file: { fileKey(name) })
    }

    /// The key to use: the Keychain's; else the old file's, but never once the user deleted it (the file may still be there
    /// if the agent couldn't remove it).
    static func resolve(keychain: String?, tombstoned: Bool, file: () -> String?) -> String? {
        if let keychain { return keychain }
        return tombstoned ? nil : file()
    }

    /// What the app tells the agent before an old key file may go (POST /data dropKeyFile), from a fresh Keychain read:
    /// "saved" when the key (the one just saved, if `expected`) is there, "deleted" when only the delete's tombstone is,
    /// nil when neither is proven (the file stays).
    static func keychainCheck(stored: String?, expected: String?, tombstoned: Bool) -> String? {
        if let stored { return expected == nil || stored == expected ? "saved" : nil }
        return tombstoned && expected == nil ? "deleted" : nil
    }

    /// The key a launch-time removal of an old file must find in the Keychain: the file's own (nil after a delete,
    /// when the tombstone is the proof instead).
    static func dropExpectation(fileKey: String, tombstoned: Bool) -> String? { tombstoned ? nil : fileKey }

    /// The Keychain account that marks `name` as deleted.
    static func tombstone(_ name: String) -> String { name + ".deleted" }

    enum Migration: Equatable { case none, importThenDrop, dropOnly }

    /// What launch does with an old key file: move it in, or only have it removed (already in the Keychain, or deleted).
    static func migration(fileKey: String?, keychainKey: String?, tombstoned: Bool) -> Migration {
        guard fileKey != nil else { return .none }
        return keychainKey == nil && !tombstoned ? .importThenDrop : .dropOnly
    }

    /// The old hand-placed file's key, if there still is one.
    static func fileKey(_ name: String) -> String? {
        key(from: try? String(contentsOfFile: folder + name, encoding: .utf8))
    }

    // MARK: - What the settings field accepts

    enum Problem: Error, Equatable {
        case empty, tooShort, spaces

        var message: String {
            switch self {
            case .empty: "키를 붙여 넣어 주세요."
            case .tooShort: "키가 너무 짧아요. 처음부터 끝까지 복사했는지 확인해 주세요."
            case .spaces: "키 중간에 빈칸이 있어요. 다시 복사해 주세요."
            }
        }
    }

    /// Real keys are long; anything under this is a partial copy.
    static let minLength = 20

    /// The pasted key, trimmed, or what is wrong with it.
    static func check(_ raw: String) -> Result<String, Problem> {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return .failure(.empty) }
        guard !key.contains(where: \.isWhitespace) else { return .failure(.spaces) }
        guard key.count >= minLength else { return .failure(.tooShort) }
        return .success(key)
    }

    /// How a saved key is shown: never the key, only its last four.
    static func masked(_ key: String) -> String {
        "••••••••" + (key.count >= minLength ? String(key.suffix(4)) : "")
    }
}
