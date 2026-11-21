//
//  ArisFleetContext.swift
//  Shared/Core (app, tests)
//
//  The fleet as a few lines of each turn's context (with the same care as the work-in-progress block): how many
//  sessions, how many need the user, and one line each with only values that can't form language: its number, a
//  state of Aris's own, how long, the agent (one Aris knows by name), a tool Aris knows by name (else "a tool"), and the
//  folder's and branch's names in a strict form ([A-Za-z0-9._/-] only, short). Whoever controls a session or a
//  repository chooses those names, and a branch can be named with a sentence. Everything free (a request, a title, a
//  last message, a command, a full path, an unknown tool) comes only through `fleet.status`, which marks the
//  conversation as outside text. Pure.
//

import Foundation

enum ArisFleetContext {
    /// Sessions listed at most; the ones that need the user first.
    static let most = 8
    static let longestName = 24
    static let longestLine = 200

    static let header = "coding sessions (Aris's fleet: number, folder, tool, state; no session's own words, use fleet status for those)"

    /// The block's lines; none when no session is live.
    static func lines(_ fleet: ArisFleet, now: Date, home: String) -> [String] {
        let live = fleet.live
        guard !live.isEmpty else { return [] }
        let needing = live.filter { $0.state.needsUser }
        let shown = (needing + live.filter { !$0.state.needsUser }).prefix(most)
        let more = live.count > most ? " (\(live.count - most) more not shown)" : ""
        let head = "\(header): \(live.count) running, \(needing.count) need the user\(more)"
        return [head] + shown.map { line($0, now: now, home: home) }
    }

    /// "- 3 aris-jv-fleet (Claude Code, branch jv-fleet): waiting for the user's permission (Bash), 2 min".
    static func line(_ session: ArisFleetSession, now: Date, home: String) -> String {
        var parts = ["\(session.tool.name)"]
        if let branch = session.branch.map({ strict($0, limit: longestName) }), !branch.isEmpty { parts.append("branch \(branch)") }
        var line = "- \(session.number) \(project(session, home: home)) (\(parts.joined(separator: ", "))): "
            + state(session) + ", " + ago(session.lastActive, now: now)
        switch session.starter {
        case .arisTeammate: line += "; Aris's teammate"
        case .arisTask: line += "; Aris's task"
        case .user: break
        }
        if !session.reach.reachable, session.reach.kind != .unknown { line += "; Aris can't type into it" }
        return line.count > longestLine ? String(line.prefix(longestLine - 1)) + "…" : line
    }

    /// The folder's name in the strict form; "a folder" when nothing is left of it.
    static func project(_ session: ArisFleetSession, home: String) -> String {
        let name = strict(session.project(home: home), limit: longestName)
        return name.isEmpty ? "a folder" : name
    }

    /// Only [A-Za-z0-9._/-], cut to `limit`: a name that can't carry a sentence.
    static func strict(_ text: String, limit: Int) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._/-~")
        return String(text.filter { allowed.contains($0) }.prefix(limit))
    }

    /// The tool names Aris knows (Claude Code's, Codex's, Gemini CLI's); anything else is "a tool".
    static let knownTools: Set<String> = ["Bash", "Read", "Edit", "MultiEdit", "Write", "Grep", "Glob", "LS", "WebFetch", "WebSearch", "Task", "Agent",
                                          "TodoWrite", "NotebookEdit", "NotebookRead", "AskUserQuestion", "ExitPlanMode", "BashOutput", "KillShell",
                                          "shell", "exec_command", "apply_patch", "update_plan", "run_shell_command", "read_file", "write_file",
                                          "replace", "glob", "search_file_content", "web_fetch", "google_web_search", "list_directory"]

    static func toolName(_ name: String, korean: Bool = false) -> String {
        if knownTools.contains(name) { return name }
        if name.hasPrefix("mcp__") { return korean ? "외부 도구(MCP)" : "an MCP tool" }
        return korean ? "도구" : "a tool"
    }

    static func state(_ session: ArisFleetSession) -> String {
        switch session.state {
        case .working: return session.lastTool.map { "working (\(toolName($0)))" } ?? "working"
        case .waitingInput: return "waiting for the user's answer"
        case .waitingPermission:
            let tool = session.pending.map { " (\(toolName($0.tool)))" } ?? ""
            return "waiting for the user's permission\(tool)" + (session.answerable ? ", answerable by Aris" : "")
        case .idle: return session.lastMessage == nil ? "idle" : "finished, waiting for the next prompt"
        case .failed: return "stopped on an error"
        case .gone: return "gone"
        }
    }

    static func ago(_ date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3_600 { return "\(Int(seconds / 60)) min" }
        return "\(Int(seconds / 3_600)) h"
    }

    /// One line, no quotes or brackets that could close the block, cut short.
    static func plain(_ text: String, limit: Int) -> String {
        let flat = text.components(separatedBy: .newlines).joined(separator: " ")
            .unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let cleaned = String(String.UnicodeScalarView(flat)).replacingOccurrences(of: "“", with: "\"").replacingOccurrences(of: "”", with: "\"")
            .replacingOccurrences(of: "<", with: "‹").replacingOccurrences(of: ">", with: "›").trimmingCharacters(in: .whitespaces)
        return cleaned.count > limit ? String(cleaned.prefix(limit - 1)) + "…" : cleaned
    }
}
