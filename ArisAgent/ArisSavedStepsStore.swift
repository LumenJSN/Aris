//
//  ArisSavedStepsStore.swift
//  aris-agent
//
//  Where saved steps live (aris/saved-steps.json, private to the user: 0600, signed, never read or written through a
//  link), the one turn's notes they are made from, and the settings page's part of POST /memory (설정 › 기억 › 저장된
//  단계: each one listed, each one deletable, and a file changed outside Aris said so).
//

import Foundation
import Security

/// A turn's desktop actions as they were done (each one saveable or why not), kept until the turn ends.
final class ArisSavedStepsRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var notes: [Result<ArisSavedStep, ArisSavedStepsRefusal>] = []

    func start() { lock.withLock { notes = [] } }
    func note(_ note: Result<ArisSavedStep, ArisSavedStepsRefusal>) { lock.withLock { notes.append(note) } }
    var all: [Result<ArisSavedStep, ArisSavedStepsRefusal>] { lock.withLock { notes } }
}

/// The recipes on disk, signed: an HMAC-SHA256 of their JSON under the key that signs the AI brains' list (its own
/// Keychain service, ArisAPISecrets.signing), as Aris keeps its other files it acts on (the services' list, the AI
/// brains' list). A file changed outside Aris (no signature, a wrong one, a link, not a plain file) is no recipe at
/// all: it is ignored, said in the audit and on the settings page, and replaced by the next save (security review 10,
/// L6). A Keychain that can't be read just now is no recipe either, but it isn't called changed and isn't saved over.
final class ArisSavedStepsStore: @unchecked Sendable {
    let file: URL
    private let signing: ArisMCPSecretStore
    private let lock = NSLock()
    /// The signing key's account (shared with ArisAPIStore; its MAC here is over a body of its own kind).
    static let signingKey = ArisAPIStore.signingKey
    /// What the MAC covers besides the recipes: this file's kind, so no other signed file's body can stand in for it.
    static let domain = Data("aris saved-steps v1\n".utf8)

    private struct Signed: Codable {
        let recipes: [String: ArisSavedRecipe]
        let mac: String
    }

    /// The file on disk was changed by something other than Aris: its recipes are ignored until the next save.
    private(set) var tampered = false
    /// The Keychain couldn't be read: no recipe is used, nothing is saved over.
    private(set) var unreadable = false

    /// Where a changed file is said (the agent's audit), once until it is saved again.
    private let report: (String) -> Void

    init(file: URL, signing: ArisMCPSecretStore, report: @escaping (String) -> Void = { _ in }) {
        self.file = file
        self.signing = signing
        self.report = report
    }

    func lookup(_ key: String) -> ArisSavedRecipe? { lock.withLock { load()[key] } }

    var all: [ArisSavedRecipe] { lock.withLock { load().values.sorted { $0.saved > $1.saved } } }

    /// Saves `recipe` under its key; the oldest go past the limit. A changed file's recipes are dropped, not kept.
    func save(_ recipe: ArisSavedRecipe) {
        lock.withLock {
            var recipes = load()
            guard !unreadable else { return }
            recipes[recipe.key] = recipe
            if recipes.count > ArisSavedSteps.limit {
                let oldest = recipes.values.sorted { $0.saved < $1.saved }.prefix(recipes.count - ArisSavedSteps.limit).map(\.key)
                oldest.forEach { recipes.removeValue(forKey: $0) }
            }
            write(recipes)
        }
    }

    @discardableResult
    func forget(_ key: String) -> Bool {
        lock.withLock {
            var recipes = load()
            guard !unreadable, recipes.removeValue(forKey: key) != nil else { return false }
            write(recipes)
            return true
        }
    }

    static func mac(_ body: Data, key: Data) -> String { ArisMCPStore.mac(domain + body, key: key) }

    private func load() -> [String: ArisSavedRecipe] {
        unreadable = false
        let present = FileManager.default.fileExists(atPath: file.path) || (try? FileManager.default.destinationOfSymbolicLink(atPath: file.path)) != nil
        guard present else { tampered = false; return [:] }
        let stored = ArisMCPStore.storedKey(signing, account: Self.signingKey)
        guard !stored.unreadable else {
            tampered = false
            unreadable = true
            return [:]
        }
        guard let data = ArisNoFollow.read(file), data.count < 4_000_000, let signed = try? JSONDecoder().decode(Signed.self, from: data),
              let body = try? Self.encoder.encode(signed.recipes), let key = stored.key,
              ArisMCPTurnCredential.same(Self.mac(body, key: key), signed.mac) else {
            if !tampered {
                FileHandle.standardError.write(Data("aris-agent: saved-steps.json was changed outside Aris; its saved steps are ignored\n".utf8))
                report("saved steps: the file was changed outside Aris, so it is ignored")
            }
            tampered = true
            return [:]
        }
        tampered = false
        return signed.recipes
    }

    private func write(_ recipes: [String: ArisSavedRecipe]) {
        guard let body = try? Self.encoder.encode(recipes), let key = key(creating: true),
              let data = try? Self.encoder.encode(Signed(recipes: recipes, mac: Self.mac(body, key: key))) else { return }
        let folder = file.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // Never through a link: whatever is at the file's place (a link, a changed file) is replaced by a plain 0600 file.
        let temp = folder.appendingPathComponent(".\(file.lastPathComponent).aris-\(UUID().uuidString)")
        guard (try? ArisNoFollow.createPrivate(temp, data)) != nil else { return }
        guard rename(temp.path, file.path) == 0 else {
            _ = ArisNoFollow.removeFile(temp)
            return
        }
        tampered = false
    }

    private func key(creating: Bool) -> Data? {
        let stored = ArisMCPStore.storedKey(signing, account: Self.signingKey)
        if let key = stored.key { return key }
        // A key is made only when there is none: never over one that just couldn't be read.
        guard creating, !stored.unreadable else { return nil }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        guard signing.save(bytes.map { String(format: "%02x", $0) }.joined(), for: Self.signingKey) == nil else { return nil }
        return Data(bytes)
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

/// POST /memory's saved-steps part (only the Aris app itself, as the rest of the page):
///   {"op": "savedSteps"}                      -> {"recipes": [{"key", "request", "steps": ["…", …], "stepsEn": […], "apps": "…", "saved", "outside"}]}
///   {"op": "savedStepsDelete", "key": "…"}    -> {"removed": bool}
/// Nil for any other op (the page's other parts answer those).
enum ArisSavedStepsRoute {
    static func handle(_ object: [String: Any], store: ArisSavedStepsStore?) -> (status: Int, body: Data, audit: String?)? {
        switch object["op"] as? String {
        case "savedSteps":
            let rows = (store?.all ?? []).map { recipe -> [String: Any] in
                ["key": recipe.key, "request": recipe.request, "saved": recipe.saved, "outside": recipe.outside == true,
                 "steps": recipe.steps.map { ArisSavedSteps.describe($0, english: false) },
                 "stepsEn": recipe.steps.map { ArisSavedSteps.describe($0, english: true) },
                 "apps": Array(NSOrderedSet(array: recipe.steps.map(\.app))).compactMap { $0 as? String }.joined(separator: ", ")]
            }
            // A file changed outside Aris is said so (its steps are ignored until the next save).
            let changed = store.map { $0.tampered } ?? false
            return (200, (try? JSONSerialization.data(withJSONObject: ["recipes": rows, "tampered": changed])) ?? Data("{}".utf8), nil)
        case "savedStepsDelete":
            guard let key = object["key"] as? String, !key.isEmpty, key.count <= 400 else { return (400, Data("{}".utf8), nil) }
            let removed = store?.forget(key) ?? false
            return (200, (try? JSONSerialization.data(withJSONObject: ["removed": removed])) ?? Data("{}".utf8), removed ? "saved steps: deleted one" : nil)
        default:
            return nil
        }
    }
}
