//
//  ArisFleetReducer.swift
//  Shared/Core (app, aris-agent, tests)
//
//  The fleet from what is heard (hook events) and what is listed (Claude Code's own list of its live sessions), one
//  step at a time, never changing what it was given. Numbers: a new session takes the smallest number no listed session
//  holds (sessions first seen together, in order of start), and keeps it while it lives; a gone session keeps its
//  number for `keepGone`, so "3번" isn't handed to another one at once. Aris's own brain sessions (its folder under
//  ~/.config/aris/aris) are never in the fleet. Pure.
//

import Foundation

/// One hook event, as the fleet needs it (the app's ClaudeHookEvent, made plain).
struct ArisFleetEvent: Equatable, Sendable {
    /// Claude Code's hook name (Gemini's are mapped to Claude's before; Codex uses Claude's).
    let name: String
    let session: String
    let cwd: String
    let tool: ArisFleetTool
    var toolName: String? = nil
    var notification: String? = nil
    /// Stop: the assistant's final message (model-written).
    var lastMessage: String? = nil
    /// UserPromptSubmit: what was typed.
    var prompt: String? = nil
    /// PermissionRequest: what it asks, from the hook's structured fields.
    var permission: ArisFleetPermission? = nil
    /// The terminal its hooks named (a guess at the host).
    var terminal: ArisFleetReach? = nil
    var at: Date
}

/// One entry of Claude Code's own list (`claude agents --json`), with what the helper found for it.
struct ArisFleetListing: Equatable, Codable, Sendable {
    let session: String
    let pid: Int32
    let cwd: String
    var started: Date? = nil
    /// Its `name` (Claude Code's, may be model-written).
    var title: String? = nil
    var background = false
    /// "busy", "idle", "waiting".
    var status: String? = nil
    var branch: String? = nil
    var reach: ArisFleetReach? = nil
}

enum ArisFleetReducer {
    /// How long a gone session stays listed (its number held).
    static let keepGone: TimeInterval = 10 * 60
    /// Nothing heard for this long: the session is gone (ClaudeSessionSweep.staleAfter).
    static let staleAfter: TimeInterval = 2 * 60 * 60
    /// Codex and Gemini never say they ended: resting this long after a turn, they are gone.
    static let restAfter: TimeInterval = 15 * 60
    /// Working and silent this long: shown idle.
    static let workingQuietAfter: TimeInterval = 60 * 60
    static let longestRequest = 120
    static let longestMessage = 600

    /// Aris's own brain sessions run here: never fleet members.
    static func isArisOwn(_ cwd: String, home: String) -> Bool {
        let own = (home as NSString).appendingPathComponent(".config/aris/aris")
        let path = (cwd as NSString).standardizingPath
        return path == own || path.hasPrefix(own + "/")
    }

    // MARK: - Events

    /// The fleet after one event. `starter`: who started this session (the app knows its teammates); kept from the
    /// first event that names Aris.
    static func apply(_ event: ArisFleetEvent, to fleet: ArisFleet, home: String, starter: ArisFleetStarter = .user) -> ArisFleet {
        guard !event.session.isEmpty, !isArisOwn(event.cwd, home: home) else { return fleet }
        let previous = fleet.session(event.session)
        if previous == nil, event.name == "SessionEnd" { return fleet }
        var session = previous.map { $0.state == .gone && event.name != "SessionEnd" ? revived($0, at: event.at) : $0 }
            ?? fresh(id: event.session, tool: event.tool, folder: event.cwd, at: event.at, number: nextNumber(fleet))
        session.heard = true
        session.tool = event.tool
        if !event.cwd.isEmpty { session.folder = event.cwd }
        session.lastActive = max(session.lastActive, event.at)
        if starter != .user { session.starter = starter }
        if let terminal = event.terminal, session.reach.kind == .unknown || session.reach.guessed { session.reach = terminal }
        session = stepped(session, by: event)
        return replacing(session, in: fleet)
    }

    /// What one event does to a session's state, tool, message and pending permission.
    private static func stepped(_ start: ArisFleetSession, by event: ArisFleetEvent) -> ArisFleetSession {
        var session = start
        switch event.name {
        case "SessionStart":
            if session.state != .working { session.state = .idle }
        case "UserPromptSubmit":
            session.state = .working
            session.pending = nil
            if session.firstRequest == nil, let prompt = oneLine(event.prompt, limit: longestRequest), !prompt.hasPrefix("/") {
                session.firstRequest = prompt
            }
        case "PreToolUse", "PostToolUse", "PostToolUseFailure", "SubagentStart", "SubagentStop", "PreCompact":
            session.state = .working
            if let tool = event.toolName, event.name == "PreToolUse" || session.lastTool == nil { session.lastTool = tool }
            if event.name != "PreToolUse", let pending = session.pending, pending.tool == event.toolName { session.pending = nil }
            if event.name == "PostToolUse" || event.name == "PostToolUseFailure", event.toolName == nil { session.pending = nil }
        case "PermissionRequest":
            let permission = event.permission
            session.pending = permission
            session.state = permission?.kind == .question ? .waitingInput : .waitingPermission
            if let tool = event.toolName { session.lastTool = tool }
        case "Notification":
            let kind = (event.notification ?? "").lowercased()
            if kind == "idle_prompt" {
                if session.state == .working { session.state = .idle }
            } else if kind == "auth_success" || kind.isEmpty {
                break
            } else if kind.contains("permission") {
                session.state = .waitingPermission
            } else {
                session.state = .waitingInput
            }
        case "Stop":
            session.state = .idle
            session.pending = nil
            if let text = oneLine(event.lastMessage, limit: longestMessage) {
                session.lastMessage = ArisFleetText(text: text, source: source(session, what: "its last message"))
            }
        case "StopFailure":
            session.state = .failed
            session.pending = nil
        case "SessionEnd":
            session.state = .gone
            session.pending = nil
            session.goneAt = event.at
        default:
            break
        }
        return session
    }

    // MARK: - Claude Code's own list

    /// The fleet after a look at Claude Code's list. `complete`: the list was read whole (then a listed Claude Code
    /// session missing from it is gone). A session only the list knows takes its state from it.
    static func apply(listing: [ArisFleetListing], complete: Bool, at now: Date, to fleet: ArisFleet, home: String) -> ArisFleet {
        let rows = listing.filter { !$0.session.isEmpty && !isArisOwn($0.cwd, home: home) }
        let known = Set(fleet.sessions.map(\.id))
        let newcomers = rows.filter { !known.contains($0.session) }.sorted { ($0.started ?? now) < ($1.started ?? now) }
        var result = fleet
        for row in newcomers {
            let session = fresh(id: row.session, tool: .claudeCode, folder: row.cwd, at: row.started ?? now, number: nextNumber(result))
            result = replacing(session, in: result)
        }
        let byId = Dictionary(rows.map { ($0.session, $0) }, uniquingKeysWith: { first, _ in first })
        result.sessions = result.sessions.map { session in
            guard session.tool == .claudeCode else { return session }
            guard let row = byId[session.id] else {
                // Listed before, missing from a whole list now: it is over.
                guard complete, session.listed, session.state.isLive else { return session }
                var gone = session
                gone.state = .gone
                gone.pending = nil
                gone.goneAt = now
                return gone
            }
            return listed(session, row: row, now: now)
        }
        return result
    }

    private static func listed(_ start: ArisFleetSession, row: ArisFleetListing, now: Date) -> ArisFleetSession {
        var session = start
        if session.state == .gone, session.goneAt.map({ now.timeIntervalSince($0) < 5 }) ?? false { return session }
        if session.state == .gone { session = revived(session, at: now) }
        session.listed = true
        session.pid = row.pid
        if !row.cwd.isEmpty, session.folder.isEmpty || !session.heard { session.folder = row.cwd }
        if let started = row.started { session.startedAt = started }
        if let title = oneLine(row.title, limit: 80) { session.title = ArisFleetText(text: title, source: source(session, what: "its title")) }
        if let branch = row.branch { session.branch = branch }
        if row.background { session.reach = ArisFleetReach(kind: .background) } else if let reach = row.reach { session.reach = reach }
        if !session.heard {
            switch row.status {
            case "busy": session.state = .working
            case "waiting": session.state = .waitingInput
            default: session.state = .idle
            }
            session.lastActive = max(session.lastActive, session.startedAt)
        }
        return session
    }

    // MARK: - Time

    /// The fleet at `now`: long-silent sessions gone, Codex and Gemini resting long gone, a working session silent an
    /// hour shown idle, gone ones dropped after `keepGone`.
    static func swept(_ fleet: ArisFleet, now: Date) -> ArisFleet {
        var result = fleet
        result.sessions = fleet.sessions.compactMap { start in
            var session = start
            if session.state == .gone {
                return now.timeIntervalSince(session.goneAt ?? session.lastActive) < keepGone ? session : nil
            }
            let quiet = now.timeIntervalSince(session.lastActive)
            let resting = session.state == .idle && session.tool != .claudeCode && quiet >= restAfter
            if (quiet >= staleAfter && !session.listed) || resting {
                session.state = .gone
                session.pending = nil
                session.goneAt = now
            } else if session.state == .working, quiet >= workingQuietAfter, session.heard {
                session.state = .idle
            }
            return session
        }
        return result
    }

    // MARK: - Parts

    /// The smallest number no listed session holds.
    static func nextNumber(_ fleet: ArisFleet) -> Int {
        let taken = Set(fleet.sessions.map(\.number))
        return (1...).first { !taken.contains($0) }!
    }

    private static func fresh(id: String, tool: ArisFleetTool, folder: String, at: Date, number: Int) -> ArisFleetSession {
        ArisFleetSession(id: id, tool: tool, number: number, pid: nil, folder: folder, branch: nil, firstRequest: nil, title: nil,
                         state: .idle, lastTool: nil, lastMessage: nil, pending: nil, startedAt: at, lastActive: at, starter: .user,
                         reach: ArisFleetReach(kind: tool == .claudeCode ? .unknown : .unsupported, app: tool == .claudeCode ? nil : tool.name))
    }

    private static func revived(_ session: ArisFleetSession, at: Date) -> ArisFleetSession {
        var back = session
        back.state = .idle
        back.goneAt = nil
        back.lastActive = max(back.lastActive, at)
        return back
    }

    private static func replacing(_ session: ArisFleetSession, in fleet: ArisFleet) -> ArisFleet {
        var result = fleet
        result.sessions = (fleet.sessions.filter { $0.id != session.id } + [session]).sorted { $0.number < $1.number }
        return result
    }

    private static func source(_ session: ArisFleetSession, what: String) -> String {
        let folder = (session.folder as NSString).lastPathComponent
        return "\(session.tool.name) session in \(folder.isEmpty ? "an unknown folder" : folder) (\(what))"
    }

    /// The first non-empty line, plain and cut short.
    static func oneLine(_ text: String?, limit: Int) -> String? {
        guard let text else { return nil }
        let line = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t#*>`-")) }
            .first { !$0.isEmpty }
        guard let line else { return nil }
        let plain = String(line.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
        return plain.count > limit ? String(plain.prefix(limit - 1)) + "…" : plain
    }
}
