//
//  ArisTeamExtrasRoute.swift
//  aris-agent
//
//  POST /teammates' other ops (the 팀원 page, the Aris app itself only, checked by the caller like list and save):
//    {"op": "brains"}                         → {"brains": {"claude": true, …}}  which brains can answer on this Mac;
//                                               "unchecked": ["api"] when one is set up but has never answered
//    {"op": "login", "brain": "antigravity"}  → {} opens a terminal running that brain's own login (a fixed command,
//                                               never words from the request); the API brain has none (400)
//    {"op": "notes", "id": "<teammate>"}      → {"notes": [...]}   its 기억
//    {"op": "forgetNote", "id", "note"?}      → {"notes": [...]}   one note gone (no "note": all of them)
//    {"op": "knowhow"}                        → {"notes": [...]}   앱 노하우
//    {"op": "forgetKnowhow", "note"?}         → {"notes": [...]}
//    {"op": "keepNote", "id", "note"} / {"op": "keepKnowhow", "note"} → {"notes": [...]}  the user keeps a note learned from
//                                               outside content (확인 필요): turns may read it from then on
//  Pure apart from what it's handed.
//

import Foundation

enum ArisTeamExtrasRoute {
    static let ops: Set<String> = ["brains", "login", "notes", "forgetNote", "knowhow", "forgetKnowhow", "keepNote", "keepKnowhow", "acceptProgram"]

    /// Where each brain's own program is installed (the drivers look in the same places).
    static func candidates(_ brain: ArisBrain) -> [String] {
        let name: String
        switch brain {
        case .claude: name = "claude"
        case .codex: name = "codex"
        case .antigravity: name = "agy"
        case .api: return []
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [home + "/.local/bin/" + name, "/opt/homebrew/bin/" + name, "/usr/local/bin/" + name]
            + (brain == .codex ? ["/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"] : [])
    }

    /// The command a brain's login runs in a terminal: its own program by the absolute path found now (L6; claude and agy
    /// ask to log in when they aren't), quoted; nil when it isn't installed or has no login (the API brain).
    static func loginCommand(_ brain: ArisBrain, resolve: ([String]) -> String?) -> String? {
        guard let path = resolve(candidates(brain)), path.hasPrefix("/") else { return nil }
        let quoted = "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return brain == .codex ? quoted + " login" : quoted
    }

    struct World {
        var ready: (ArisBrain) -> Bool
        /// The first of the paths that is an executable file.
        var resolve: ([String]) -> String?
        var openTerminal: (String) -> Bool
        var notes: (URL) -> [ArisKeptNote]
        var forget: (String?, URL) -> Bool
        var keep: (String, URL) -> Bool = { _, _ in false }
        /// The owner's yes to an AI program that changed (ArisProgramApproval.accept).
        var acceptProgram: (ArisBrain) -> Bool = { _ in false }
        /// Set up, but it has never answered (an API key whose check failed): not ready, and said as needing a check.
        var needsCheck: (ArisBrain) -> Bool = { _ in false }
        var knowhowFile: URL
        var teammateFile: (String) -> URL?
    }

    static func handle(_ object: [String: Any], world: World) -> ArisTeammateRoute.Reply {
        switch object["op"] as? String {
        case "brains":
            let brains = Dictionary(uniqueKeysWithValues: ArisBrain.allCases.map { ($0.rawValue, world.ready($0)) })
            let unchecked = ArisBrain.allCases.filter(world.needsCheck).map(\.rawValue)
            return reply(200, unchecked.isEmpty ? ["brains": brains] : ["brains": brains, "unchecked": unchecked])
        case "login":
            guard let raw = object["brain"] as? String, let brain = ArisBrain.allCases.first(where: { $0.rawValue == raw }),
                  let command = loginCommand(brain, resolve: world.resolve) else { return reply(400, [:]) }
            return world.openTerminal(command) ? reply(200, [:]) : reply(500, ["error": "terminal"])
        case "acceptProgram":
            guard let raw = object["brain"] as? String, let brain = ArisBrain.allCases.first(where: { $0.rawValue == raw }), brain != .api else { return reply(400, [:]) }
            return world.acceptProgram(brain) ? reply(200, [:]) : reply(404, [:])
        case "notes":
            guard let file = (object["id"] as? String).flatMap(world.teammateFile) else { return reply(400, [:]) }
            return notesReply(world.notes(file))
        case "forgetNote":
            guard let file = (object["id"] as? String).flatMap(world.teammateFile) else { return reply(400, [:]) }
            guard world.forget(object["note"] as? String, file) else { return reply(500, ["error": "store"]) }
            return notesReply(world.notes(file))
        case "keepNote":
            guard let file = (object["id"] as? String).flatMap(world.teammateFile), let note = object["note"] as? String else { return reply(400, [:]) }
            guard world.keep(note, file) else { return reply(404, [:]) }
            return notesReply(world.notes(file))
        case "keepKnowhow":
            guard let note = object["note"] as? String else { return reply(400, [:]) }
            guard world.keep(note, world.knowhowFile) else { return reply(404, [:]) }
            return notesReply(world.notes(world.knowhowFile))
        case "knowhow":
            return notesReply(world.notes(world.knowhowFile))
        case "forgetKnowhow":
            guard world.forget(object["note"] as? String, world.knowhowFile) else { return reply(500, ["error": "store"]) }
            return notesReply(world.notes(world.knowhowFile))
        default:
            return reply(400, [:])
        }
    }

    private static func notesReply(_ notes: [ArisKeptNote]) -> ArisTeammateRoute.Reply {
        let rows: [[String: Any]] = notes.map { note in
            var row: [String: Any] = ["id": note.id, "text": note.text, "date": ISO8601DateFormatter().string(from: note.date),
                                      "source": note.source.rawValue, "tainted": note.tainted, "kept": note.kept]
            if let app = note.app { row["app"] = app }
            if let by = note.by { row["by"] = by }
            return row
        }
        return reply(200, ["notes": rows])
    }

    private static func reply(_ status: Int, _ object: [String: Any]) -> ArisTeammateRoute.Reply {
        ArisTeammateRoute.Reply(status: status, body: (try? JSONSerialization.data(withJSONObject: object, options: .sortedKeys)) ?? Data("{}".utf8))
    }
}
