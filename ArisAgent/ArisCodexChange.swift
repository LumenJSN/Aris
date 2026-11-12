//
//  ArisCodexChange.swift
//  aris-agent
//
//  One file change of a Codex patch as the gate reads it (security review 2 H2). Codex names each change by its
//  `path`, and an update may also move the file (apply_patch's "*** Move to:"): the destination rides in the change's
//  `kind` ({"type":"update","move_path":"…"}). The gate used to read only `path`, so an edit inside Aris's work folder
//  that ended up in ~/Library/LaunchAgents was rated as work-folder business, and a card showed the old name only.
//  Here every place a change can carry a destination is read (inside `kind` or beside the path, snake or camel case),
//  so the driver rates the destination together with the path and shows "→ destination" on the card. A destination
//  that isn't a path can't be rated or shown: the edit is refused. A field of `kind` Aris doesn't know is never let
//  through at once: it asks, with the field on the card. Pure, so the tests run it.
//

import Foundation

enum ArisCodexChange {
    /// The names a change's destination may come under.
    static let destinationKeys = ["move_path", "movePath", "new_path", "newPath"]

    struct Reading: Equatable {
        var path: String?
        /// Where the file ends up, when the change moves it.
        var destinations: [String] = []
        /// Destination fields whose value isn't a path (named as "kind.move_path"): the edit can't be shown.
        var unread: [String] = []
        /// Fields of `kind` Aris doesn't know, as "name: value" for the card.
        var extra: [String] = []
    }

    static func read(_ change: [String: Any]) -> Reading {
        var reading = Reading(path: change["path"] as? String)
        let kind = change["kind"] as? [String: Any] ?? [:]
        for (holder, prefix) in [(kind, "kind."), (change, "")] {
            for key in destinationKeys {
                guard let value = holder[key], !(value is NSNull) else { continue }
                if let path = value as? String, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if !reading.destinations.contains(path) { reading.destinations.append(path) }
                } else {
                    reading.unread.append(prefix + key)
                }
            }
        }
        for key in kind.keys.sorted() where key != "type" && !destinationKeys.contains(key) {
            reading.extra.append("\(key): \(shown(kind[key] as Any))")
        }
        return reading
    }

    /// Every file the changes touch, each once, in order: each path, then where it is moved to.
    static func files(_ changes: [[String: Any]]) -> [String] {
        var files: [String] = []
        for change in changes {
            let reading = read(change)
            for file in [reading.path].compactMap({ $0 }) + reading.destinations where !files.contains(file) { files.append(file) }
        }
        return files
    }

    /// The destination fields that couldn't be read, over all changes.
    static func unread(_ changes: [[String: Any]]) -> [String] { changes.flatMap { read($0).unread } }

    /// Whether any change carries a field of `kind` Aris doesn't know.
    static func hasExtra(_ changes: [[String: Any]]) -> Bool { changes.contains { !read($0).extra.isEmpty } }

    /// The plain card's lines: each path, a "→ destination" line under one that is moved, and any unknown field.
    static func lines(_ changes: [[String: Any]]) -> [String] {
        changes.flatMap { change -> [String] in
            let reading = read(change)
            return [reading.path].compactMap { $0 } + reading.destinations.map { "→ " + $0 } + reading.extra
        }.map(ArisDesktopCard.shown)
    }

    /// Said (to the audit, the ledger and Codex) when a change's destination can't be read.
    static let unreadReason = "a file edit whose destination (where the file would end up) can't be read, so it can't be shown on the card"

    private static func shown(_ value: Any) -> String {
        if let text = value as? String { return text }
        guard JSONSerialization.isValidJSONObject([value]),
              let data = try? JSONSerialization.data(withJSONObject: [value], options: [.sortedKeys, .withoutEscapingSlashes]) else { return "\(value)" }
        return String(String(decoding: data, as: UTF8.self).dropFirst().dropLast())
    }
}
