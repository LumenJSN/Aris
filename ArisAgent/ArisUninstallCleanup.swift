//
//  ArisUninstallCleanup.swift
//  aris-agent
//
//  Uninstall's tidy-up outside ~/.config/aris: only what Aris's installers added, matched by what marks it as Aris's.
//  ~/.claude/settings.json: hooks posting to the notch (http://127.0.0.1:23350/hook) and the status line script in
//  Aris's folder (install-claude-hooks.py). ~/.codex/hooks.json and ~/.gemini/settings.json: hooks running Aris's
//  agent-hook.sh (install-agent-hooks.py). ~/.gemini/antigravity-cli/settings.json: the rules install-aris-agent.sh
//  added (any naming Aris's folder, and its generic ones unless they were already there before Aris; deny rules that
//  were there before Aris come back). ~/.codex/config.toml: codex_hooks = true goes back to how it was, only when the
//  installer's oldest backup (config.toml.bak-<time>) shows it wasn't on. Everything else in those files stays. Each
//  changed file is copied to <name>.aris-uninstall-<stamp> (0600 from the start) first; a file that is a link is left
//  alone.
//

import Foundation

enum ArisUninstallCleanup {
    static let hookURL = "http://127.0.0.1:23350/hook"

    struct Result: Equatable, CustomStringConvertible {
        let file: String
        let ok: Bool
        /// "unchanged", "cleaned", "missing", "link", or what went wrong.
        let note: String
        var description: String { "\(file): \(note)" }
    }

    /// The rules install-aris-agent.sh adds that don't name Aris's folder.
    static let antigravityGeneric: Set<String> = [
        "read_url(*)", "command(rm)", "command(sudo)", "command(su)", "command(diskutil)", "command(dd)", "command(launchctl)",
        "command(csrutil)", "command(chown)", "command(tccutil)", "command(security)", "command(git push)", "command(defaults delete)",
        #"command((\S*/)?peekaboo(\s.*)?)"#, #"command(.*[;&|(]\s*(\S*/)?peekaboo(\s.*)?)"#, #"command(.*/peekaboo['"]?(\s.*)?)"#,
        #"command(.*computer-runtime.*)"#,
    ]

    private static func mentions(_ text: String, _ folders: [String]) -> Bool { folders.contains { text.contains($0) } }

    /// `hooks` ({event: [{hooks: [...]}]}) without the hooks `isOurs` matches; groups left empty go, events left empty go.
    private static func pruned(_ hooks: [String: Any], isOurs: ([String: Any]) -> Bool) -> (hooks: [String: Any], changed: Bool) {
        var out = hooks
        var changed = false
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            var kept: [[String: Any]] = []
            for group in groups {
                guard let list = group["hooks"] as? [[String: Any]] else { kept.append(group); continue }
                let left = list.filter { !isOurs($0) }
                if left.count == list.count { kept.append(group); continue }
                changed = true
                if !left.isEmpty { var copy = group; copy["hooks"] = left; kept.append(copy) }
            }
            if kept.isEmpty { out[event] = nil } else { out[event] = kept }
        }
        return (out, changed)
    }

    /// ~/.claude/settings.json without Aris's hooks and status line; nil when nothing of Aris's is in it.
    static func claude(_ settings: [String: Any], arisFolders: [String]) -> [String: Any]? {
        var out = settings
        var changed = false
        if let hooks = settings["hooks"] as? [String: Any] {
            let result = pruned(hooks) { ($0["url"] as? String) == hookURL }
            out["hooks"] = result.hooks
            changed = result.changed
        }
        if let line = settings["statusLine"] as? [String: Any], let command = line["command"] as? String,
           mentions(command, arisFolders), command.hasSuffix("statusline.sh") {
            out["statusLine"] = nil
            changed = true
        }
        return changed ? out : nil
    }

    /// ~/.codex/hooks.json or ~/.gemini/settings.json without the hooks running Aris's agent-hook.sh; nil when none.
    static func agentHooks(_ settings: [String: Any], arisFolders: [String]) -> [String: Any]? {
        guard let hooks = settings["hooks"] as? [String: Any] else { return nil }
        let result = pruned(hooks) { hook in
            guard let command = hook["command"] as? String else { return false }
            return mentions(command, arisFolders) && command.contains("agent-hook.sh")
        }
        guard result.changed else { return nil }
        var out = settings
        out["hooks"] = result.hooks
        return out
    }

    /// Antigravity's settings without Aris's rules: any naming Aris's folder, and the generic ones Aris adds unless
    /// `before` (the .before-aris copy) already had them. Nil when nothing changes.
    static func antigravity(_ settings: [String: Any], before: [String: Any]?, arisFolders: [String]) -> [String: Any]? {
        guard var permissions = settings["permissions"] as? [String: Any] else { return nil }
        let earlier = before?["permissions"] as? [String: Any]
        var changed = false
        for key in ["allow", "deny"] {
            let rules = permissions[key] as? [String] ?? []
            let had = Set(earlier?[key] as? [String] ?? [])
            let kept = rules.filter { rule in
                if mentions(rule, arisFolders) { return false }
                if before != nil, antigravityGeneric.contains(rule), !had.contains(rule) { return false }
                return true
            }
            var restored = kept
            // Deny rules the user had before Aris come back (allow rules are never added: that would widen access).
            if key == "deny" { restored += (earlier?[key] as? [String] ?? []).filter { !kept.contains($0) && !mentions($0, arisFolders) } }
            if restored != rules { permissions[key] = restored; changed = true }
        }
        guard changed else { return nil }
        var out = settings
        out["permissions"] = permissions
        return out
    }

    /// Codex's config.toml with codex_hooks back to how it was before Aris's installer (`before`: its oldest backup);
    /// nil when it was already on then, when there's no backup to tell, or when it isn't on now.
    static func codexConfig(_ current: String, before: String?) -> String? {
        guard let before else { return nil }
        let on = #"(?m)^codex_hooks\s*=\s*true\s*\n?"#
        guard current.range(of: on, options: .regularExpression) != nil,
              before.range(of: on, options: .regularExpression) == nil else { return nil }
        if before.range(of: #"(?m)^codex_hooks\s*="#, options: .regularExpression) != nil {
            return current.replacingOccurrences(of: #"(?m)^codex_hooks\s*=\s*true"#, with: "codex_hooks = false", options: .regularExpression)
        }
        var out = current.replacingOccurrences(of: on, with: "", options: .regularExpression)
        // The installer's own section ("\n[features]\n" at the end) goes with it when nothing else is in it.
        if !before.contains("[features]") {
            out = out.replacingOccurrences(of: #"\n*\[features\]\s*$"#, with: "\n", options: .regularExpression)
        }
        return out == current ? nil : out
    }

    // MARK: - On disk

    /// Cleans the five files under `home`; one result per file, Antigravity's last.
    static func run(home: URL, stamp: String) -> [Result] {
        let folders = [".config/aris", ".config/boring-notch", ".peekaboo", "Library/Application Support/Aris/computer-runtime"]
            .map { home.appendingPathComponent($0).path }
        let agy = home.appendingPathComponent(".gemini/antigravity-cli/settings.json")
        let before = ArisNoFollow.read(agy.appendingPathExtension("before-aris"))
            .flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
        let codexFolder = home.appendingPathComponent(".codex")
        let codexBackup = ArisNoFollow.contents(codexFolder).filter { $0.range(of: #"^config\.toml\.bak-\d+$"#, options: .regularExpression) != nil }
            .min { Int($0.dropFirst("config.toml.bak-".count)) ?? 0 < Int($1.dropFirst("config.toml.bak-".count)) ?? 0 }
        let codexBefore = codexBackup.flatMap { ArisNoFollow.text(codexFolder.appendingPathComponent($0)) }
        return [
            clean(home.appendingPathComponent(".claude/settings.json"), stamp: stamp) { claude($0, arisFolders: folders) },
            clean(home.appendingPathComponent(".codex/hooks.json"), stamp: stamp) { agentHooks($0, arisFolders: folders) },
            clean(home.appendingPathComponent(".gemini/settings.json"), stamp: stamp) { agentHooks($0, arisFolders: folders) },
            cleanText(codexFolder.appendingPathComponent("config.toml"), stamp: stamp) { codexConfig($0, before: codexBefore) },
            clean(agy, stamp: stamp) { antigravity($0, before: before, arisFolders: folders) },
        ]
    }

    private static func clean(_ file: URL, stamp: String, _ change: ([String: Any]) -> [String: Any]?) -> Result {
        rewrite(file, stamp: stamp) { data in
            guard let settings = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
            guard let cleaned = change(settings) else { return nil }
            return try JSONSerialization.data(withJSONObject: cleaned, options: [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]) + Data("\n".utf8)
        }
    }

    private static func cleanText(_ file: URL, stamp: String, _ change: (String) -> String?) -> Result {
        rewrite(file, stamp: stamp) { data in change(String(decoding: data, as: UTF8.self)).map { Data($0.utf8) } }
    }

    /// Reads a regular file, asks `change` for its new bytes (nil: leave it), backs it up 0600 and replaces it.
    private static func rewrite(_ file: URL, stamp: String, _ change: (Data) throws -> Data?) -> Result {
        let name = file.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
        guard FileManager.default.fileExists(atPath: file.path) || ArisNoFollow.isFile(file) else {
            // Nothing there, or a dangling link: nothing to clean.
            return Result(file: name, ok: true, note: "missing")
        }
        guard ArisNoFollow.isFile(file) else { return Result(file: name, ok: true, note: "link") }
        guard let data = ArisNoFollow.read(file) else { return Result(file: name, ok: false, note: "not readable") }
        do {
            guard let out = try change(data) else { return Result(file: name, ok: true, note: "unchanged") }
            let backup = file.deletingLastPathComponent().appendingPathComponent("\(file.lastPathComponent).aris-uninstall-\(stamp)")
            try ArisNoFollow.createPrivate(backup, data)
            try ArisNoFollow.replace(file, with: out)
            return Result(file: name, ok: true, note: "cleaned")
        } catch {
            return Result(file: name, ok: false, note: error.localizedDescription)
        }
    }
}
