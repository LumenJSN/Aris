//
//  ArisMindUndoMore.swift
//  aris-agent
//
//  More of Core 2's calls carry their undo into the record (ARCHITECTURE Part 2, Record), only where one can be known
//  for certain, never a guess:
//  · a calendar event or a to-do (Apple Reminders) made through aris-tools: aris-tools writes the app's own id into
//    the activity log as it makes it; the one entry written during the call, for exactly that title, gives the record
//    `itemCreated` with that id, and taking it back goes through `aris-tools undo` of that entry (so the old 한 일 list
//    shows it undone too). Two matches, none, or anything unclear: no recipe.
//  · a shell command that only makes or moves one thing to a new name (`mkdir`, `mv`, `cp`): read word by word before
//    it runs, with every path absolute after resolving and nothing at the target yet, and confirmed after it ran.
//    Anything else (globs, variables, several commands, flags it doesn't know, a target already there): no recipe.
//  Notes and `remind` reminders give no id back, so they are recorded with none.
//

import Foundation

enum ArisMindItemUndo {
    /// What the activity log's entry for this call says, read from the call's words as aris-tools reads them.
    struct Expected: Equatable {
        let kind: String
        let summary: String
        /// The activity log's undo for it (`{"deleteEvent": {"id"}}`, `{"removeTodo": {"id"}}`).
        let undoKey: String
    }

    static func expected(_ argv: [String]) -> Expected? {
        guard let first = argv.first else { return nil }
        switch first {
        case "event":
            let rest = Array(argv.dropFirst())
            guard !["find", "delete", "change"].contains(rest.first ?? "") else { return nil }
            let title = removingOptions(rest, ["--start", "--minutes", "--calendar"]).joined(separator: " ")
            return title.isEmpty ? nil : Expected(kind: "calendar", summary: "일정 추가: " + title, undoKey: "deleteEvent")
        case "todo":
            guard argv.dropFirst().first == "add" else { return nil }
            // As aris-tools' todoOptions: every `--name value` pair out, the other words joined.
            var words: [String] = []
            var index = 2
            while index < argv.count {
                if argv[index].hasPrefix("--"), index + 1 < argv.count { index += 2 } else { words.append(argv[index]); index += 1 }
            }
            let text = words.joined(separator: " ")
            return text.trimmingCharacters(in: .whitespaces).isEmpty ? nil : Expected(kind: "reminder", summary: "할 일 추가: " + text, undoKey: "removeTodo")
        default:
            return nil
        }
    }

    /// `option(flag, in:)` of aris-tools for each flag: its first use and the value after it taken out.
    private static func removingOptions(_ words: [String], _ flags: [String]) -> [String] {
        var left = words
        for flag in flags {
            if let index = left.firstIndex(of: flag), index + 1 < left.count { left.removeSubrange(index...(index + 1)) }
        }
        return left
    }

    /// The recipe for the item this call made: the one entry written since `since`, not undone, with exactly the
    /// expected summary and an id of the expected kind.
    static func recipe(argv: [String], since: Date, entries: [[String: Any]]) -> ArisUndoRecipe? {
        guard let expected = expected(argv) else { return nil }
        let formatter = ISO8601DateFormatter()
        let from = since.addingTimeInterval(-1)
        let summary = expected.summary.precomposedStringWithCanonicalMapping
        let matches = entries.compactMap { entry -> String? in
            guard entry["undone"] as? Bool != true, let date = (entry["date"] as? String).flatMap(formatter.date(from:)), date >= from,
                  (entry["summary"] as? String)?.precomposedStringWithCanonicalMapping == summary,
                  let id = ((entry["undo"] as? [String: Any])?[expected.undoKey] as? [String: Any])?["id"] as? String, !id.isEmpty, id.count <= 300 else { return nil }
            return id
        }
        guard matches.count == 1, let id = matches.first else { return nil }
        return .itemCreated(kind: expected.kind, id: id)
    }

    /// Takes back the activity log's entries a call wrote (`aris-tools undo --id … --confirmed` each, newest first):
    /// only ids that are UUIDs, at most 20; the first that fails stops it, with what aris-tools said.
    static func undoLogged(_ ids: [String], run: ([String]) -> (status: Int32, output: String)) throws {
        let entries = ids.prefix(20).compactMap(UUID.init(uuidString:))
        guard !entries.isEmpty, entries.count == min(ids.count, 20) else { throw ArisUndoError(message: "that change isn't in the activity log any more") }
        for entry in entries.reversed() {
            let done = run(["undo", "--id", entry.uuidString, "--confirmed"])
            guard done.status == 0 else {
                let said = done.output.trimmingCharacters(in: .whitespacesAndNewlines)
                throw ArisUndoError(message: said.isEmpty ? "it couldn't be taken back" : String(said.prefix(200)))
            }
        }
    }

    /// The app's key for the write that takes a to-do back (aris-tools' undo removes it by its Reminders id).
    static func todoUndoKey(_ id: String) -> String { "todo|remove|id=" + id }

    /// Takes an item back: the activity log's entry that holds its id, undone by aris-tools (`undo --id … --confirmed`).
    /// `run`: aris-tools with those words; its status and what it said.
    static func remove(kind: String, id: String, entries: [[String: Any]], run: ([String]) -> (status: Int32, output: String)) throws {
        let key = kind == "calendar" ? "deleteEvent" : kind == "reminder" ? "removeTodo" : nil
        guard let key else { throw ArisUndoError(message: "undoing \(kind) isn't available in this helper yet") }
        let holders = entries.filter { entry in
            entry["undone"] as? Bool != true && ((entry["undo"] as? [String: Any])?[key] as? [String: Any])?["id"] as? String == id
        }
        guard holders.count == 1, let entry = (holders[0]["id"] as? String).flatMap(UUID.init(uuidString:)) else {
            throw ArisUndoError(message: "that \(kind == "calendar" ? "event" : "to-do") isn't in the activity log any more")
        }
        let done = run(["undo", "--id", entry.uuidString, "--confirmed"])
        guard done.status == 0 else {
            let said = done.output.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ArisUndoError(message: said.isEmpty ? "it couldn't be taken back" : String(said.prefix(200)))
        }
    }
}

enum ArisMindShellUndo {
    struct Plan: Equatable {
        let recipe: ArisUndoRecipe
        /// Must be there after the command ran.
        let made: String
        /// Must be gone after it ran (a move's source).
        let gone: String?
    }

    struct Disk {
        var exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
        var isDirectory: (String) -> Bool = { path in
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &directory) && directory.boolValue
        }
    }

    /// Characters that make a line mean more than its words (expansion, globs, redirection, several commands, escapes).
    private static let unsafe = CharacterSet(charactersIn: "$`*?[]{}~<>|&;()\\!\n\r\t\"'#=")

    static func plan(_ command: String, cwd: String, home: String, disk: Disk = Disk()) -> Plan? {
        guard command.count <= 2_000, command.rangeOfCharacter(from: unsafe) == nil else { return nil }
        let words = command.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let program = words.first.map({ ($0 as NSString).lastPathComponent }), ["mkdir", "mv", "cp"].contains(program),
              words[0] == program || words[0] == "/bin/" + program else { return nil }
        let flags = words.dropFirst().filter { $0.hasPrefix("-") }
        let paths = words.dropFirst().filter { !$0.hasPrefix("-") }
        // Flags only before the paths.
        guard Array(words.dropFirst().prefix(flags.count)) == flags else { return nil }
        // Every path as the sandbox and the never-list see it: inside the home folder or on an external disk, no link on
        // the way to it (its folder resolves to itself: ArisUndoRecipes.unchanged), and not a protected place once
        // resolved. So the path kept in the recipe is the resolved one, and the undo checks it again before it acts.
        func resolved(_ path: String) -> String? {
            let absolute = ((path.hasPrefix("/") ? path : (cwd as NSString).appendingPathComponent(path)) as NSString).standardizingPath
            guard (try? ArisUndoRecipes.check(absolute, home: home)) != nil, let kept = try? ArisUndoRecipes.unchanged(absolute, home: home) else { return nil }
            return kept
        }
        func freeTarget(_ target: String) -> Bool {
            !disk.exists(target) && disk.isDirectory((target as NSString).deletingLastPathComponent)
        }
        switch program {
        case "mkdir":
            guard Set(flags).isSubset(of: ["-p"]), paths.count == 1, let target = resolved(paths[0]), freeTarget(target) else { return nil }
            return Plan(recipe: .fileCreated(path: target), made: target, gone: nil)
        case "mv", "cp":
            let allowed: Set<String> = program == "mv" ? ["-n"] : ["-n", "-p", "-R", "-r"]
            guard Set(flags).isSubset(of: allowed), paths.count == 2, let source = resolved(paths[0]), let destination = resolved(paths[1]),
                  disk.exists(source) else { return nil }
            if program == "cp", disk.isDirectory(source), !flags.contains("-R"), !flags.contains("-r") { return nil }
            let target = disk.isDirectory(destination) ? (destination as NSString).appendingPathComponent((source as NSString).lastPathComponent) : destination
            guard target != source, freeTarget(target), (try? ArisUndoRecipes.check(target, home: home)) != nil,
                  (try? ArisUndoRecipes.unchanged(target, home: home)) != nil else { return nil }
            return program == "mv" ? Plan(recipe: .fileMoved(original: source, current: target), made: target, gone: source)
                : Plan(recipe: .fileCreated(path: target), made: target, gone: nil)
        default:
            return nil
        }
    }

    /// The recipe, once the command ran and the disk shows it did exactly that.
    static func confirmed(_ plan: Plan, disk: Disk = Disk()) -> ArisUndoRecipe? {
        guard disk.exists(plan.made), plan.gone.map({ !disk.exists($0) }) ?? true else { return nil }
        return plan.recipe
    }
}
