//
//  ArisTeammateEdit.swift
//  aris-agent
//
//  POST /teammates (Task 11b): the settings 팀원 page reads and saves the list here, since the sandboxed app can't
//  write ~/.config/aris. Only the Aris app itself may call it (ArisPeer, checked in main.swift): the token alone would
//  let a model's shell or a Claude Code session rename a teammate or give it another brain. A save is checked whole,
//  entry by entry, and is written only when every entry passes; the agent keeps its own memory files.
//

import Foundation

enum ArisTeammateEdit {
    /// Claude Code included.
    static let maxTeammates = 12
    /// Ids the roster or the jobs already mean something by ("aris" is main Aris's row, ArisTeamEditing.mainId).
    static let reservedIds: Set<String> = ["aris", "main", "clone"]
    /// A name or role is short text, never a payload (UTF-8 bytes, whatever its letters).
    static let maxNameBytes = 64
    static let maxRoleBytes = 320
    /// 어떻게 일할까요 (UTF-8 bytes: 800 Korean letters).
    static let maxInstructionBytes = 2_400
    /// Main Aris's names: a teammate called that couldn't be told apart when the user speaks.
    static let reservedNames: Set<String> = ["aris", "아리스"]

    enum Problem: String, Error, Equatable {
        case shape, id, duplicateId, name, duplicateName, role, instructions, scopes, look, brain, claudeCodeMissing, tooMany
    }

    /// The list a save asks for, or the first thing wrong with it.
    static func list(_ raw: Any?, current: [ArisTeammate]) -> Result<[ArisTeammate], Problem> {
        guard let entries = raw as? [Any] else { return .failure(.shape) }
        // Counted before any entry is looked at: a flood is refused whole.
        guard entries.count <= maxTeammates else { return .failure(.tooMany) }
        var out: [ArisTeammate] = []
        for item in entries {
            switch entry(item, current: current) {
            case .failure(let problem): return .failure(problem)
            case .success(let mate):
                if out.contains(where: { $0.id == mate.id }) { return .failure(.duplicateId) }
                if out.contains(where: { $0.name.lowercased() == mate.name.lowercased() }) { return .failure(.duplicateName) }
                out.append(mate)
            }
        }
        guard out.contains(where: { $0.id == ArisTeammate.claudeCodeId }) else { return .failure(.claudeCodeMissing) }
        return .success(out)
    }

    /// One entry: `id`, `name`, `routing` (or the older `role`), `instructions`, `scopes`, `look` and `brain`, each
    /// checked; anything else in it is ignored. A look or brain exactly as stored for that id is kept even when the picker
    /// no longer offers it (so a rename never bounces). Missing instructions or scopes keep what is stored.
    static func entry(_ raw: Any, current: [ArisTeammate]) -> Result<ArisTeammate, Problem> {
        guard let object = raw as? [String: Any], let id = object["id"] as? String, let rawName = object["name"] as? String,
              let rawRouting = (object["routing"] ?? object["role"]) as? String, let brain = object["brain"] as? String else { return .failure(.shape) }
        guard ArisTeammate.isValidId(id), !reservedIds.contains(id) else { return .failure(.id) }
        guard let name = checkedName(rawName) else { return .failure(.name) }
        guard let routing = checkedRole(rawRouting) else { return .failure(.role) }
        let stored = current.first { $0.id == id }
        guard let instructions = object["instructions"].map(checkedInstructions) ?? stored?.instructions ?? "" else { return .failure(.instructions) }
        // A new teammate saved without scopes may use nothing (L1); only a file from before the redesign reads as all.
        guard let scopes = object["scopes"].map(checkedScopes) ?? stored?.scopes ?? [] else { return .failure(.scopes) }
        guard let look = checkedLook(object["look"], stored: stored?.look) else { return .failure(.look) }
        guard checkedBrain(brain, id: id, stored: stored?.brain) else { return .failure(.brain) }
        // Never the request's: a memory file is a path the agent reads.
        let memoryFile = stored?.memoryFile
            ?? (id == ArisTeammate.claudeCodeId ? ArisTeammate.claudeCode.memoryFile : "teammates/\(id).md")
        return .success(ArisTeammate(id: id, name: name, routing: routing, instructions: instructions, look: look, brain: brain,
                                     scopes: scopes, memoryFile: memoryFile))
    }

    /// Lines without tags or invisible letters (a line break is fine), at most 800 letters; nil otherwise (refused, not
    /// cut: the page caps as the user types).
    static func checkedInstructions(_ raw: Any) -> String? {
        guard let text = raw as? String, text.utf8.count <= maxInstructionBytes, !text.contains("<"), !text.contains(">"),
              !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\r" && $0 != "\t" })
        else { return nil }
        let kept = ArisTeammate.instructionsText(text)
        return text.trimmingCharacters(in: .whitespacesAndNewlines).count <= ArisTeammate.maxInstructions ? kept : nil
    }

    /// A list of known scope names, each at most once.
    static func checkedScopes(_ raw: Any) -> [String]? {
        guard let list = raw as? [Any], list.count <= ArisTeammateScope.allCases.count else { return nil }
        let names = list.compactMap { $0 as? String }
        guard names.count == list.count, Set(names).count == names.count, names.allSatisfy({ ArisTeammateScope(rawValue: $0) != nil }) else { return nil }
        return ArisTeammateScope.canonical(names)
    }

    /// Trimmed, one line, no tags, within ArisTeammateName's width (refused, not cut: the page caps as the user types).
    static func checkedName(_ raw: String) -> String? {
        // Looked at before trimming, which would quietly drop a zero width space at either end.
        guard !hasMarkup(raw) else { return nil }
        let name = raw.trimmingCharacters(in: .whitespaces)
        guard name.utf8.count <= maxNameBytes, let capped = ArisTeammateName.validate(name), capped == name,
              !reservedNames.contains(name.lowercased()) else { return nil }
        return name
    }

    /// Trimmed, one line, no tags, at most 80 letters; empty is fine.
    static func checkedRole(_ raw: String) -> String? {
        guard !hasMarkup(raw) else { return nil }
        let role = raw.trimmingCharacters(in: .whitespaces)
        guard role.count <= ArisTeammate.maxRole, role.utf8.count <= maxRoleBytes else { return nil }
        return role
    }

    /// Claude Code is Claude; any other teammate any of Aris's brains (each runs its jobs behind that brain's own gates).
    static func checkedBrain(_ brain: String, id: String, stored: String?) -> Bool {
        guard ArisBrain.allCases.contains(where: { $0.rawValue == brain }) else { return false }
        if id == ArisTeammate.claudeCodeId { return brain == ArisTeammate.claudeCode.brain }
        return true
    }

    /// Exactly a type, a shading and an optional palette colour from the picker's allowlist (never the star), or the
    /// look as stored.
    static func checkedLook(_ raw: Any?, stored: ArisCharacterLook? = nil) -> ArisCharacterLook? {
        guard let object = raw as? [String: Any], let type = object["type"] as? String, let shading = object["shading"] as? String else { return nil }
        let color: String?
        switch object["colorHex"] {
        case nil, is NSNull: color = nil
        case let hex as String: color = hex
        default: return nil
        }
        let look = ArisCharacterLook(type: type, colorHex: color, shading: shading)
        return look.isPickable || look == stored ? look : nil
    }

    private static func hasMarkup(_ text: String) -> Bool {
        text.contains("<") || text.contains(">")
            || text.unicodeScalars.contains { CharacterSet.newlines.contains($0) || CharacterSet.controlCharacters.contains($0) }
    }
}

/// The route itself, pure: who asked, what they asked, and the store's load and save.
enum ArisTeammateRoute {
    struct Reply: Equatable {
        let status: Int
        let body: Data
    }

    /// `{"op": "list"}` → 200 `{"teammates": [...]}`; `{"op": "save", "teammates": [...]}` → 200 with the list as saved,
    /// 400 `{"error": "<what>"}` (nothing written) or 500 (the store refused). Anyone but the app: 403, nothing read.
    /// `removed`: after a save, the ids of the teammates it took out (their notes files go too: N18).
    static func handle(_ object: [String: Any], fromApp: Bool, load: () -> [ArisTeammate], save: ([ArisTeammate]) throws -> Void,
                       removed: ([String]) -> Void = { _ in }) -> Reply {
        guard fromApp else { return Reply(status: 403, body: Data("{}".utf8)) }
        switch object["op"] as? String {
        case "list":
            return Reply(status: 200, body: body(load()))
        case "save":
            switch ArisTeammateEdit.list(object["teammates"], current: load()) {
            case .failure(let problem):
                return Reply(status: 400, body: (try? JSONSerialization.data(withJSONObject: ["error": problem.rawValue])) ?? Data("{}".utf8))
            case .success(let list):
                let before = load().map(\.id)
                do {
                    try save(list)
                } catch {
                    return Reply(status: 500, body: Data(#"{"error":"store"}"#.utf8))
                }
                let gone = before.filter { id in !list.contains { $0.id == id } }
                if !gone.isEmpty { removed(gone) }
                return Reply(status: 200, body: body(load()))
            }
        default:
            return Reply(status: 400, body: Data("{}".utf8))
        }
    }

    private struct Body: Encodable { let teammates: [ArisTeammate] }

    static func body(_ teammates: [ArisTeammate]) -> Data {
        (try? JSONEncoder().encode(Body(teammates: teammates))) ?? Data(#"{"teammates":[]}"#.utf8)
    }
}
