//
//  ArisAgyRules.swift
//  aris-agent
//
//  Antigravity's allow and deny rules for Aris, kept by the agent itself. agy reads them only from its global settings
//  (~/.gemini/antigravity-cli/settings.json), and headless agy refuses whatever they don't allow. They used to be
//  written only by install-aris-agent.sh, and only when that file already existed: Aris installed before agy, binaries
//  copied without the script, or an agy that had never been started left the Antigravity brain able to chat but
//  refused every Mac action, and without the deny rules that stand in for a risk gate (audit agy-rules-7).
//
//  Now they are checked each time the open agy is started and written when anything is missing: the same rules as
//  the script, added to what is there. The user's own rules and other settings are kept, a file that can't be read as
//  settings is left alone, and what was there before Aris is kept beside it once (settings.json.before-aris), which is
//  what Aris's uninstall puts back.
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
                for name in ["schedules.json", "routines.json", "inbox.jsonl", "activity.jsonl", "teammates.json", "work/*", "memory.sqlite*", "memory.md"] {
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
        /// Every rule was already there.
        case ready
        /// The rules were added (to a file made now, when there was none).
        case written
        /// The file is there but isn't settings Aris can add to, or couldn't be written: left as it was.
        case failed(String)
    }

    /// Makes sure agy's settings under `home` carry Aris's rules. A file that isn't there is made (with its folder); one
    /// that is there keeps everything else in it, and its first state is kept once as settings.json.before-aris.
    @discardableResult
    static func ensure(home: String, tools: String, folder: String) -> Outcome {
        // A settings file that is a link (a dotfiles folder) is written where it points, and stays a link.
        let named = settingsFile(home: home)
        let exists = FileManager.default.fileExists(atPath: named.path)
        let file = exists ? named.resolvingSymlinksInPath() : named
        var settings: [String: Any] = [:]
        var before = Data("{}\n".utf8)
        if exists {
            guard let data = try? Data(contentsOf: file) else { return .failed("couldn't read it") }
            guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return .failed("it isn't a settings object") }
            settings = object
            before = data
        }
        guard let next = merged(settings, tools: tools, folder: folder, home: home) else { return rulesReady(settings, tools: tools) }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            // What was there before Aris, once: an empty object when Aris made the file (uninstall then takes all of Aris's rules out).
            let backup = named.appendingPathExtension("before-aris")
            let mode = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.posixPermissions] as? NSNumber
            if !FileManager.default.fileExists(atPath: backup.path) {
                try before.write(to: backup, options: .atomic)
                // As private as the file it copies: settings kept 0600 were copied out readable by every account
                // (security review L3). A copy of nothing (Aris made the file) is the owner's alone.
                try FileManager.default.setAttributes([.posixPermissions: mode ?? NSNumber(value: 0o600)], ofItemAtPath: backup.path)
            }
            let data = try JSONSerialization.data(withJSONObject: next, options: [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]) + Data("\n".utf8)
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: mode ?? NSNumber(value: 0o600)], ofItemAtPath: file.path)
            return .written
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Nothing to add: ready when the allow rule for aris-tools really is there (a rule list of another shape isn't).
    private static func rulesReady(_ settings: [String: Any], tools: String) -> Outcome {
        let allowed = (settings["permissions"] as? [String: Any])?["allow"] as? [String] ?? []
        return allowed.contains("command(\(tools))") ? .ready : .failed("its rules aren't lists Aris can add to")
    }
}
