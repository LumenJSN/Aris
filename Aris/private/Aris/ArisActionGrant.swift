//
//  ArisActionGrant.swift
//  Aris (also built into aris-agent)
//
//  The exact calendar or to-do write an approval stands for (security review of batch 3: POST /aris/events and
//  /aris/todos took any holder of the hook token at its word). The agent's gate mints a one-shot grant for the key of
//  each such action it lets run (the user's yes on its card, or its own rule); the app's route turns a write away unless the
//  agent consumes a grant for that very key. The agent reads the key from aris-tools' words, the app from the request
//  body aris-tools makes of the same words: both here, so they always agree. Reads (event find, todo list) need none.
//  Pure.
//

import Foundation

enum ArisActionGrant {
    /// The key for one aris-tools argv (the words after the program); nil when it isn't a calendar or to-do write.
    static func key(argv: [String]) -> String? {
        guard let tool = argv.first else { return nil }
        let rest = Array(argv.dropFirst())
        switch tool {
        case "event": return eventBody(rest).flatMap(key(event:))
        case "todo": return todoBody(rest).flatMap(key(todo:))
        case "remind": return remindBody(rest).flatMap(key(todo:))
        default: return nil
        }
    }

    /// The key of POST /aris/events' body; nil for a read (find) or a body that isn't one.
    static func key(event body: [String: Any]) -> String? {
        guard let op = body["op"] as? String, ["add", "delete", "change", "remove-uid"].contains(op) else { return nil }
        return line("event", op, body, fields: ["id", "title", "start", "to", "rename", "uid"])
    }

    /// The key of POST /aris/todos' body; nil for a read (list).
    static func key(todo body: [String: Any]) -> String? {
        guard let op = body["op"] as? String, ["add", "done", "edit", "remove", "reopen", "set-due"].contains(op) else { return nil }
        return line("todo", op, body, fields: ["id", "text", "due", "list", "note", "title"])
    }

    /// Said when a write comes with no grant: nothing was changed.
    static let refusal = "Not done: no approval for exactly this change came from Aris's gate (a calendar or to-do change runs only after it). Nothing was changed."

    /// An undo's to-do write (by its Reminders id): the agent's own /undo vouches for it with a scope grant.
    static func isUndoKey(_ key: String) -> Bool {
        key.hasPrefix("todo|reopen|id=") || key.hasPrefix("todo|remove|id=") || key.hasPrefix("todo|set-due|id=")
    }

    /// An undo write a grant may be bound to exactly (ArisActionGrants.mintUndo(exactly:)): a to-do's, or the removal
    /// of an event an add made, by Calendar's uid. The event's is never a scope key: only its own exact grant takes it.
    static func isBoundUndoKey(_ key: String) -> Bool {
        isUndoKey(key) || key.hasPrefix(eventUndoLead)
    }

    private static let eventUndoLead = "event|remove-uid|uid="

    /// The exact key of the undo that removes the event Calendar knows by `uid` (POST /aris/events remove-uid); nil for
    /// an id that isn't a plain one Calendar gives.
    static func eventUndoKey(uid: String) -> String? {
        guard uid.range(of: #"^[A-Za-z0-9._:@\-]{1,200}$"#, options: .regularExpression) != nil else { return nil }
        return key(event: ["op": "remove-uid", "uid": uid])
    }

    private static func line(_ tool: String, _ op: String, _ body: [String: Any], fields: [String]) -> String {
        ([tool, op] + fields.compactMap { field in (body[field] as? String).map { "\(field)=\($0)" } }).joined(separator: "|")
    }

    // MARK: - The bodies aris-tools makes of its words (ArisEventKit, ArisMac.addEvent, ArisTodoCommand)

    /// `event find|delete|change …` or `event <title> --start … [--minutes N] [--calendar name]`.
    static func eventBody(_ args: [String]) -> [String: Any]? {
        var words = args
        if let verb = words.first, ["find", "delete", "change"].contains(verb) {
            words.removeFirst()
            guard let start = option("--start", in: &words) else { return nil }
            var body: [String: Any] = ["op": verb, "start": start]
            if verb == "find" { body["title"] = words.joined(separator: " "); return body }
            guard let id = option("--id", in: &words), let title = option("--title", in: &words) else { return nil }
            body["id"] = id
            body["title"] = title
            if verb == "change" {
                if let to = option("--to", in: &words) { body["to"] = to }
                if let rename = option("--rename", in: &words) { body["rename"] = rename }
            }
            return words.isEmpty ? body : nil
        }
        guard let start = option("--start", in: &words) else { return nil }
        _ = option("--minutes", in: &words)
        _ = option("--calendar", in: &words)
        let title = words.joined(separator: " ")
        return title.isEmpty ? nil : ["op": "add", "title": title, "start": start]
    }

    /// `remind <text> [--at "YYYY-MM-DD HH:MM"]`: a to-do added through the app (POST /aris/todos, jv-prompts), with
    /// the time as given as its due; nil without text.
    static func remindBody(_ args: [String]) -> [String: Any]? {
        var words = args
        let at = option("--at", in: &words)
        let text = words.joined(separator: " ")
        guard !text.isEmpty else { return nil }
        var body: [String: Any] = ["op": "add", "text": text]
        if let at { body["due"] = at }
        return body
    }

    /// `todo add|done|remove|edit <words> [--due x] [--list y] [--note z] [--title t]`; nil for the list.
    static func todoBody(_ args: [String]) -> [String: Any]? {
        guard let verb = args.first, ["add", "done", "remove", "edit"].contains(verb) else { return nil }
        var words: [String] = [], options: [String: String] = [:]
        var index = 1
        while index < args.count {
            if args[index].hasPrefix("--"), index + 1 < args.count {
                options[String(args[index].dropFirst(2))] = args[index + 1]
                index += 2
            } else {
                words.append(args[index])
                index += 1
            }
        }
        var body: [String: Any] = ["op": verb, "text": words.joined(separator: " ")]
        let kept: [String] = verb == "add" ? ["due", "list", "note"] : verb == "edit" ? ["due", "note", "title"] : []
        for key in kept { if let value = options[key] { body[key] = value } }
        return body
    }

    private static func option(_ flag: String, in words: inout [String]) -> String? {
        guard let index = words.firstIndex(of: flag), index + 1 < words.count else { return nil }
        let value = words[index + 1]
        words.removeSubrange(index...(index + 1))
        return value
    }
}
