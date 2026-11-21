//
//  ClaudeHookSettings.swift
//  Aris
//
//  Settings › Claude Code 연결: what install-claude-hooks.py does to ~/.claude/settings.json, ported, for a Mac with
//  only the app (a DMG install has no script). The hooks are command hooks running a script inside Aris.app
//  (aris-claude-hook.sh) that reads the hook token from ~/.config/aris/claude-hook-token (0600, made by aris-agent) and
//  hands it to curl on a pipe: settings.json holds no secret (the script's http hooks carry the token in plain text,
//  and settings.json is often world-readable or kept in a dotfiles repo). Adding is idempotent, keeps everyone else's
//  hooks, leaves an earlier install's http hooks as they are (aris-agent's own checks know them), takes Aris's hooks
//  off the events it no longer uses, and only puts its status line where there is none or the user said so.
//  Removing takes off Aris's hooks of either kind and its status line, nothing else. Foundation only (tested).
//

import Foundation

enum ClaudeHookSettings {
    /// The notch's hook server (ClaudeHookServer), where the script's http hooks post.
    static let url = "http://127.0.0.1:23350/hook"
    /// The scripts inside Aris.app.
    static let hookScript = "aris-claude-hook.sh"
    static let statusScript = "aris-claude-statusline.sh"
    /// The status lines earlier installs put in place (the script's copy, before and after the folder's rename).
    static let oldStatusLines = ["/.config/aris/statusline.sh", "/.config/boring-notch/statusline.sh"]

    /// The events Aris uses (install-claude-hooks.py's EVENTS; ClaudeModels.swift, ClaudeStore.swift).
    static let events = ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                         "PostToolUseFailure", "Stop", "StopFailure", "Notification", "PreCompact", "PermissionRequest"]
    /// Events an earlier version registered: Aris's hooks on them are taken off.
    static let retiredEvents = ["SubagentStart", "SubagentStop"]
    /// Seconds Claude Code waits for a hook; the approval card holds its request up to 120 s (ClaudeHookHold).
    static let eventTimeout = 2
    static let permissionTimeout = 130

    static func timeout(_ event: String) -> Int { event == "PermissionRequest" ? permissionTimeout : eventTimeout }

    /// The hook's command: the script by its full path, with how long it may wait for the notch.
    static func hookCommand(script: String, event: String) -> String { "/bin/sh \"\(script)\" \(timeout(event))" }
    static func statusCommand(script: String) -> String { "/bin/bash \"\(script)\"" }

    /// One of Aris's hooks: the script's http hook, or this app's command hook.
    static func isOurs(_ hook: [String: Any]) -> Bool {
        hook["url"] as? String == url || (hook["command"] as? String)?.contains(hookScript) == true
    }

    static func hasOurs(_ groups: [[String: Any]]) -> Bool {
        groups.contains { ($0["hooks"] as? [[String: Any]] ?? []).contains(where: isOurs) }
    }

    enum StatusLine: Equatable {
        case none, ours
        /// Someone else's, by its command.
        case theirs(String)
    }

    static func statusLine(_ settings: [String: Any]) -> StatusLine {
        guard let line = settings["statusLine"] as? [String: Any] else { return .none }
        let command = line["command"] as? String ?? ""
        if command.contains(statusScript) || oldStatusLines.contains(where: { command.hasSuffix($0) }) { return .ours }
        return .theirs(command)
    }

    /// Aris hears from Claude Code: its hook is on every event it uses, and hooks aren't switched off.
    static func connected(_ settings: [String: Any]) -> Bool {
        guard settings["disableAllHooks"] as? Bool != true, let hooks = settings["hooks"] as? [String: Any] else { return false }
        return events.allSatisfy { hasOurs(hooks[$0] as? [[String: Any]] ?? []) }
    }

    /// The settings with Aris's hooks and (unless someone else's is kept) its status line. `replaceTheirs`: the user said
    /// yes to putting Aris's status line in place of theirs.
    static func connecting(_ settings: [String: Any], script: String, statusScript: String, replaceTheirs: Bool) -> [String: Any] {
        var out = settings
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for event in events {
            let groups = hooks[event] as? [[String: Any]] ?? []
            hooks[event] = hasOurs(groups) ? refreshed(groups, script: script, event: event) : groups + [entry(event, script: script)]
        }
        for event in retiredEvents {
            guard let groups = hooks[event] as? [[String: Any]], hasOurs(groups) else { continue }
            let left = withoutOurs(groups)
            hooks[event] = left.isEmpty ? nil : left
        }
        out["hooks"] = hooks
        switch statusLine(settings) {
        case .theirs where !replaceTheirs: break
        default: out["statusLine"] = ["type": "command", "command": statusCommand(script: statusScript), "padding": 0] as [String: Any]
        }
        return out
    }

    /// The settings without anything of Aris's: its hooks of either kind (a group left empty goes, an event left empty
    /// goes) and its status line. Everyone else's stays as it was.
    static func disconnecting(_ settings: [String: Any]) -> [String: Any] {
        var out = settings
        if var hooks = settings["hooks"] as? [String: Any] {
            for (event, value) in hooks {
                guard let groups = value as? [[String: Any]], hasOurs(groups) else { continue }
                let left = withoutOurs(groups)
                hooks[event] = left.isEmpty ? nil : left
            }
            out["hooks"] = hooks.isEmpty ? nil : hooks
        }
        if statusLine(settings) == .ours { out["statusLine"] = nil }
        return out
    }

    /// The copy kept before a change: settings.json.pre-aris.<stamp>.
    static func backupName(stamp: String) -> String { "settings.json.pre-aris.\(stamp)" }

    // MARK: - Pieces

    private static func entry(_ event: String, script: String) -> [String: Any] {
        ["matcher": "", "hooks": [["type": "command", "command": hookCommand(script: script, event: event), "timeout": timeout(event)]]]
    }

    /// This app's command hooks brought to today's script place and timeout; an http hook from the script is left alone.
    private static func refreshed(_ groups: [[String: Any]], script: String, event: String) -> [[String: Any]] {
        groups.map { group in
            var group = group
            group["hooks"] = (group["hooks"] as? [[String: Any]] ?? []).map { hook in
                guard hook["command"] != nil, isOurs(hook) else { return hook }
                var hook = hook
                hook["command"] = hookCommand(script: script, event: event)
                hook["timeout"] = timeout(event)
                return hook
            }
            return group
        }
    }

    private static func withoutOurs(_ groups: [[String: Any]]) -> [[String: Any]] {
        groups.compactMap { group in
            let hooks = group["hooks"] as? [[String: Any]] ?? []
            let left = hooks.filter { !isOurs($0) }
            if left.count == hooks.count { return group }
            guard !left.isEmpty else { return nil }
            var kept = group
            kept["hooks"] = left
            return kept
        }
    }
}
