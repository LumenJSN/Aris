//
//  ArisAgyRules.swift
//  aris-agent
//
//  Antigravity's allow and deny rules for Aris. Headless agy refuses whatever its rules don't allow, and the deny rules
//  stand in for a risk gate (audit agy-rules-7). They used to be written into the user's own global settings
//  (~/.gemini/antigravity-cli/settings.json), so they changed every agy session the user started themselves too.
//
//  Now they go only to the agy Aris starts: `agy --settings <json>` ("settings for this session only, never saved").
//  The session's settings are the user's own permissions with Aris's rules added, so whether agy layers them over its
//  global file or puts them in its place, Aris's agy may do what it could before and nothing more. A global file that
//  isn't settings Aris can read leaves the agy sealed, as before. And what an earlier Aris wrote into the user's file
//  is taken out again once (restore): Aris's rules that weren't there before it, by the copy it kept
//  (settings.json.before-aris), with the user's own rules and settings left as they are and their file as it was
//  beside it (settings.json.aris-cleanup) first.
//

import Foundation

enum ArisAgyRules {
    /// Broad rules an earlier Aris added, which also applied to the user's own agy: taken out of the allow list.
    static let retired = ["command(osascript)", "command(open)", "command(shortcuts)"]

    /// aris-tools commands agy never runs itself. It has no risk gate to ask the user: what sends, deletes, types or
    /// opens things is refused outright, and so is writing what later turns read back (memory, events, to-dos), reading
    /// The user's messages, mail, notes and Obsidian, and the connected services (Aris runs those for agy through its gate).
    static let refusedCommands = ["message", "mail", "messages", "notes", "obsidian", "maps", "mcp", "trash", "keys", "type", "link", "shortcut",
                                  "clipboard set", "schedule add", "schedule remove", "undo", "remember", "forget", "memory", "recall", "event", "todo add",
                                  "todo edit", "todo remove", "todo done", "remind", "skill", "move", "rename", "folder new",
                                  // Saving the home place is a write (security review L2): never agy's own, silently.
                                  "weather --set-home",
                                  // Restart, shut down, log out or sleep through aris-tools: Aris's relay asks first.
                                  "osascript"]

    static func settingsFile(home: String) -> URL {
        URL(fileURLWithPath: home).appendingPathComponent(".gemini/antigravity-cli/settings.json")
    }

    static func allow(tools: String) -> [String] { ["command(\(tools))", "read_url(*)"] }

    /// `tools`: aris-tools' path; `folder`: Aris's own folder (~/.config/aris/aris). The list and its order are the
    /// install script's.
    static func deny(tools: String, folder: String, home: String) -> [String] {
        var deny = ["command(rm)", "command(sudo)", "command(su)", "command(diskutil)", "command(dd)", "command(launchctl)",
                    "command(csrutil)", "command(chown)", "command(tccutil)", "command(security)", "command(git push)",
                    "command(defaults delete)", "write_file(\(folder)/shortcuts.json)"]
        // Scheduled work, what it produced, the activity log, the teammate list, the work folder and memory: only
        // aris-tools and the agent touch them. The old folder name (~/.config/boring-notch) is a link to the same files.
        let oldFolder = home + "/.config/boring-notch/aris"
        for place in [folder, oldFolder] {
            for verb in ["read_file", "write_file"] {
                for name in ["schedules.json", "routines.json", "inbox.jsonl", "activity.jsonl", "teammates.json", "work/*", "memory.sqlite*", "memory.md",
                             "tasks/*", "children.json"] {
                    deny.append("\(verb)(\(place)/\(name))")
                }
            }
        }
        deny += refusedCommands.map { "command(\(tools) \($0))" }
        // The user's Messages, Mail and Notes stores: never read directly.
        for store in ["Library/Messages", "Library/Mail", "Library/Group Containers/group.com.apple.notes", "Library/Containers/com.apple.mail"] {
            deny += ["read_file(\(home)/\(store)/*)", "read_file(\(home)/\(store)/**)"]
        }
        // Computer use's runtime and Peekaboo's store: only the agent runs or reads them. agy reads each rule as an
        // anchored regular expression: Peekaboo as the program (bare, by a path, after a separator, or quoted), and
        // anything naming the runtime folder.
        deny += [#"command((\S*/)?peekaboo(\s.*)?)"#, #"command(.*[;&|(]\s*(\S*/)?peekaboo(\s.*)?)"#, #"command(.*/peekaboo['"]?(\s.*)?)"#,
                 "command(.*computer-runtime.*)"]
        for place in [".peekaboo", "Library/Application Support/Aris/computer-runtime"] {
            for verb in ["read_file", "write_file"] {
                for glob in ["*", "**"] { deny.append("\(verb)(\(home)/\(place)/\(glob))") }
            }
        }
        // The hook token and Aris's keys: agy never reads them.
        for place in [(folder as NSString).deletingLastPathComponent, (oldFolder as NSString).deletingLastPathComponent] {
            deny += ["read_file(\(place)/claude-hook-token)", "read_file(\(place)/*-key)"]
        }
        deny.append("command(.*claude-hook-token.*)")
        return deny
    }

    /// `settings` with Aris's rules in it: the retired allow rules out, every rule of Aris's that is missing added after
    /// the ones already there, everything else as it was. Nil when nothing is missing, or when its permissions aren't
    /// the lists Aris knows how to add to (then nothing is touched).
    static func merged(_ settings: [String: Any], tools: String, folder: String, home: String) -> [String: Any]? {
        var rules: [String: Any]
        switch settings["permissions"] {
        case nil: rules = [:]
        case let existing as [String: Any]: rules = existing
        default: return nil
        }
        var changed = false
        for (key, wanted) in [("allow", allow(tools: tools)), ("deny", deny(tools: tools, folder: folder, home: home))] {
            let had: [String]
            switch rules[key] {
            case nil: had = []
            case let list as [String]: had = list
            default: return nil
            }
            let kept = key == "allow" ? had.filter { !retired.contains($0) } : had
            let next = kept + wanted.filter { !kept.contains($0) }
            if next != had {
                rules[key] = next
                changed = true
            }
        }
        guard changed else { return nil }
        var out = settings
        out["permissions"] = rules
        return out
    }

    enum Outcome: Equatable {
        /// The settings for this agy's `--settings` (inline JSON): the user's own permissions with Aris's added.
        case ready(String)
        /// The user's settings file is there but isn't settings Aris knows how to add to (or can't be read).
        case failed(String)
    }

    /// The settings the agy Aris starts gets for its session: the user's own permissions (when they have a settings
    /// file) with every rule of Aris's that is missing added after them. Nothing is written anywhere.
    static func session(home: String, tools: String, folder: String) -> Outcome {
        let named = settingsFile(home: home)
        var settings: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: named.path) {
            guard let data = try? Data(contentsOf: named.resolvingSymlinksInPath()) else { return .failed("couldn't read it") }
            guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return .failed("it isn't a settings object") }
            settings = object
        }
        guard let permissions = (merged(settings, tools: tools, folder: folder, home: home) ?? settings)["permissions"] as? [String: Any],
              carries(permissions, tools: tools, folder: folder, home: home) else { return .failed("its rules aren't lists Aris can add to") }
        guard let data = try? JSONSerialization.data(withJSONObject: ["permissions": permissions], options: [.sortedKeys, .withoutEscapingSlashes]) else {
            return .failed("its rules couldn't be written out")
        }
        return .ready(String(decoding: data, as: UTF8.self))
    }

    /// The folders whose rules are Aris's whatever their exact words (an older Aris's, with other paths).
    static func arisFolders(home: String, tools: String) -> [String] {
        [".config/aris", ".config/boring-notch", ".peekaboo", "Library/Application Support/Aris/computer-runtime"].map { home + "/" + $0 }
            + [(tools as NSString).deletingLastPathComponent].filter { $0.count > 1 }
    }

    /// `settings` without what Aris added to it: every rule naming Aris's folders, Aris's own rules (and the broad ones
    /// an older Aris allowed) that `before` didn't have, and the deny rules `before` had back. Nil when nothing changes.
    static func withoutArisRules(_ settings: [String: Any], before: [String: Any], tools: String, folder: String, home: String) -> [String: Any]? {
        let base = ArisUninstallCleanup.antigravity(settings, before: before, arisFolders: arisFolders(home: home, tools: tools)) ?? settings
        guard var permissions = base["permissions"] as? [String: Any] else { return nil }
        let ours = Set(allow(tools: tools) + deny(tools: tools, folder: folder, home: home) + retired)
        let earlier = before["permissions"] as? [String: Any]
        for key in ["allow", "deny"] {
            guard let rules = permissions[key] as? [String] else { continue }
            let had = Set(earlier?[key] as? [String] ?? [])
            permissions[key] = rules.filter { !ours.contains($0) || had.contains($0) }
        }
        var out = base
        out["permissions"] = permissions
        return NSDictionary(dictionary: out).isEqual(to: settings) ? nil : out
    }

    enum Restored: Equatable {
        /// Aris never wrote into the user's file (no copy of it from before).
        case nothing
        /// Aris's rules were taken out (or there was nothing of Aris's left in it), and the copy from before is gone.
        case restored
        /// The file couldn't be read as settings, or written: left as it is, the copy kept for the uninstall.
        case failed(String)
    }

    /// Takes out of the user's own settings what an earlier Aris wrote there (the copy it kept beside the file says
    /// what was theirs). Their file as it was is kept first, once, as settings.json.aris-cleanup (with its own mode);
    /// a file Aris made that holds nothing else afterwards is removed. Followed through a link, as Aris wrote through it.
    @discardableResult
    static func restore(home: String, tools: String, folder: String) -> Restored {
        let named = settingsFile(home: home)
        let backup = named.appendingPathExtension("before-aris")
        guard let beforeData = ArisNoFollow.read(backup) else { return .nothing }
        guard let before = (try? JSONSerialization.jsonObject(with: beforeData)) as? [String: Any] else { return .failed("the copy from before Aris isn't settings") }
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: named.path) {
                let file = named.resolvingSymlinksInPath()
                guard let data = try? Data(contentsOf: file) else { return .failed("couldn't read it") }
                guard let settings = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return .failed("it isn't a settings object") }
                if let cleaned = withoutArisRules(settings, before: before, tools: tools, folder: folder, home: home) {
                    let mode = (try? fm.attributesOfItem(atPath: file.path))?[.posixPermissions] as? NSNumber ?? NSNumber(value: 0o600)
                    let kept = named.appendingPathExtension("aris-cleanup")
                    if !fm.fileExists(atPath: kept.path) {
                        try data.write(to: kept, options: .atomic)
                        try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: kept.path)
                    }
                    if before.isEmpty, isEmptySettings(cleaned) {
                        try fm.removeItem(at: file)
                    } else {
                        let out = try JSONSerialization.data(withJSONObject: cleaned, options: [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]) + Data("\n".utf8)
                        try out.write(to: file, options: .atomic)
                        try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: file.path)
                    }
                }
            }
            try fm.removeItem(at: backup)
            return .restored
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Settings with nothing in them but empty rule lists.
    private static func isEmptySettings(_ settings: [String: Any]) -> Bool {
        guard settings.keys.allSatisfy({ $0 == "permissions" }) else { return false }
        let permissions = settings["permissions"] as? [String: Any] ?? [:]
        return permissions.values.allSatisfy { ($0 as? [Any])?.isEmpty == true }
    }

    nonisolated(unsafe) private static var restoredOnce = false
    private static let restoreLock = NSLock()

    /// `restore`, once per process (the first agy start); a failure is written to the log.
    static func restoreOnce(home: String, tools: String, folder: String) {
        let first = restoreLock.withLock { () -> Bool in
            defer { restoredOnce = true }
            return !restoredOnce
        }
        guard first else { return }
        switch restore(home: home, tools: tools, folder: folder) {
        case .nothing: break
        case .restored: FileHandle.standardError.write(Data("aris-agent: took Aris's rules back out of Antigravity's own settings (they are given to Aris's agy alone now)\n".utf8))
        case .failed(let why): FileHandle.standardError.write(Data("aris-agent: Antigravity's own settings still have Aris's rules (\(why))\n".utf8))
        }
    }

    /// Whether `permissions` has every rule of Aris's in lists of rules (a list of another shape doesn't count).
    private static func carries(_ permissions: [String: Any], tools: String, folder: String, home: String) -> Bool {
        guard let allowed = permissions["allow"] as? [String], let denied = permissions["deny"] as? [String] else { return false }
        return Set(allowed).isSuperset(of: allow(tools: tools)) && Set(denied).isSuperset(of: deny(tools: tools, folder: folder, home: home))
    }
}
