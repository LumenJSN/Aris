//
//  ArisClaudeHookCheck.swift
//  aris-agent
//
//  Whether this Mac's Claude Code tells Aris when a session starts and stops (audit team-4). A launched Claude Code
//  job ends on its session's Stop hook, and the hooks are added to ~/.claude/settings.json outside the app
//  (install-claude-hooks.py): on a Mac that never ran it, the job would wait a day for a Stop that can't come. The
//  agent looks when it opens the window and says so with the launch, so the app can tell the user the window is open and
//  that it can't see when it ends. Read only: nothing in Claude Code's settings is ever changed here.
//

import Foundation

enum ArisClaudeHookCheck {
    /// The events a job's wait needs: the session's start (which session is the job's) and its Stop.
    static let needed = ["SessionStart", "Stop"]

    static func settingsFile(home: String) -> URL {
        URL(fileURLWithPath: home).appendingPathComponent(".claude/settings.json")
    }

    /// Whether the settings file at `home` has Aris's hook on every needed event.
    static func reports(home: String) -> Bool {
        reports(try? Data(contentsOf: settingsFile(home: home)))
    }

    /// The same for the file's bytes (nil: no file, or it couldn't be read). Hooks switched off altogether
    /// (`disableAllHooks`) report nothing.
    static func reports(_ settings: Data?) -> Bool {
        guard let settings, let object = (try? JSONSerialization.jsonObject(with: settings)) as? [String: Any],
              object["disableAllHooks"] as? Bool != true, let hooks = object["hooks"] as? [String: Any] else { return false }
        return needed.allSatisfy { event in
            (hooks[event] as? [[String: Any]] ?? []).contains { group in
                (group["hooks"] as? [[String: Any]] ?? []).contains { $0["url"] as? String == ArisUninstallCleanup.hookURL }
            }
        }
    }
}
