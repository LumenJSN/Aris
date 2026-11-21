//
//  ClaudeSessionsRoute.swift
//  Aris
//
//  POST /aris/sessions on the hook server (the shared token, like /aris/todos): what aris-agent needs to send a prompt
//  into one of the user's own Claude Code sessions (the owner, 2026-11-15: "웹사이트 만든 세션한테 /unslop 돌리라고 해").
//  {"op": "list"}: the sessions the hooks know, each with its folder, state, last hook, how long ago, its terminal and
//  whether a card waits on it; never anything a session wrote (that stays in the turn's context lines). {"op": "watch",
//  "session": id}: the agent typed a prompt there, so the session's next Stop is said once (ClaudeSessionWatch).
//  {"op": "fleet"} and {"op": "deny"}: the fleet's (ArisFleetRoute). Foundation only (tested).
//

import Foundation

enum ClaudeSessionsRoute {
    static let path = "/aris/sessions"

    /// The last hook as the session keeps it: the event's name, and a Notification's kind after a colon.
    static func hookName(_ event: ClaudeHookEvent) -> String {
        event.name == "Notification" ? "Notification:" + (event.notificationType ?? "") : event.name
    }

    /// The terminal as the agent reads it: a kind and its one value (each already checked by TerminalRef).
    static func terminal(_ ref: TerminalRef?) -> [String: String]? {
        switch ref {
        case .warp(let url)?: return ["kind": "warp", "value": url.absoluteString]
        case .iterm(let id)?: return ["kind": "iterm", "value": id]
        case .app(let bundle)?: return ["kind": "app", "value": bundle]
        case nil: return nil
        }
    }

    /// One session's entry (no text of its own).
    static func entry(_ session: ClaudeSession, asking: Bool, now: Date) -> [String: Any] {
        var entry: [String: Any] = [
            "id": session.id, "cwd": session.cwd, "state": session.state.rawValue, "lastHook": session.lastHook,
            "secondsAgo": max(0, Int(now.timeIntervalSince(session.lastEvent))), "agent": session.agent, "asking": asking,
        ]
        if let terminal = terminal(session.terminal) { entry["terminal"] = terminal }
        return entry
    }

    /// The list, newest first.
    static func list(_ sessions: [ClaudeSession], approvals: [ClaudeApproval], now: Date) -> [String: Any] {
        let rows = sessions.sorted { $0.lastEvent > $1.lastEvent }.map { session in
            entry(session, asking: approvals.contains { $0.sessionId == session.id }, now: now)
        }
        return ["ok": true, "sessions": rows]
    }

    /// The answer for one request's body.
    @MainActor
    static func answer(_ body: [String: Any], store: ClaudeStore, watch: ClaudeSessionWatch, now: Date = Date()) -> Data {
        let json: [String: Any]
        switch body["op"] as? String {
        case "list":
            json = list(Array(store.sessions.values), approvals: store.approvals, now: now)
        case "watch":
            guard let id = body["session"] as? String, let session = store.sessions[id] else {
                json = ["ok": false, "message": "no such session"]
                break
            }
            watch.watch(id, folder: session.title, at: now)
            json = ["ok": true]
        case "fleet", "deny":
            // The fleet (jv-fleet): Claude Code's own list in, the fleet out; or a "no" to a session's permission card.
            return ArisFleetRoute.answer(body, store: store, fleet: .shared, now: now)
        default:
            json = ["ok": false, "message": "usage: {\"op\": \"list\"} or {\"op\": \"watch\", \"session\": <id>}"]
        }
        return (try? JSONSerialization.data(withJSONObject: json)) ?? Data("{}".utf8)
    }
}

/// The sessions Aris typed a prompt into: each one's next Stop is said once ("…세션이 끝냈어요"), within `keep`.
@MainActor
final class ClaudeSessionWatch {
    static let shared = ClaudeSessionWatch()
    /// How long a sent prompt is watched for its Stop.
    static let keep: TimeInterval = 3 * 3_600
    /// The most sessions watched at once.
    static let most = 8

    private var watched: [String: (folder: String, at: Date)] = [:]
    /// The watched sessions whose Stop was just said, and when (the fleet leaves their finish to this).
    private var said: [String: Date] = [:]

    func watch(_ id: String, folder: String, at now: Date) {
        let fresh = watched.filter { now.timeIntervalSince($0.value.at) < Self.keep }
        let kept = fresh.count < Self.most ? fresh : Dictionary(uniqueKeysWithValues: fresh.sorted { $0.value.at > $1.value.at }.prefix(Self.most - 1).map { ($0.key, $0.value) })
        watched = kept.merging([id: (folder, now)]) { _, new in new }
    }

    var count: Int { watched.count }

    /// Whether this session's finish is said here: it is watched, or its Stop was said within the last minute.
    func saysFinish(of id: String, at now: Date = Date()) -> Bool {
        watched[id] != nil || said[id].map { now.timeIntervalSince($0) < 60 } == true
    }

    /// A hook event for a watched session: on its Stop, the folder and Claude Code's last message (and it is watched no
    /// more); a SessionEnd forgets it. Nil otherwise.
    func heard(_ event: ClaudeHookEvent, at now: Date) -> (folder: String, message: String?)? {
        guard let entry = watched[event.sessionId] else { return nil }
        guard now.timeIntervalSince(entry.at) < Self.keep else {
            watched[event.sessionId] = nil
            return nil
        }
        switch event.name {
        case "SessionEnd":
            watched[event.sessionId] = nil
            return nil
        case "Stop":
            watched[event.sessionId] = nil
            said = said.filter { now.timeIntervalSince($0.value) < 60 }.merging([event.sessionId: now]) { _, new in new }
            return (entry.folder, event.lastMessage)
        default:
            return nil
        }
    }

    /// What is said when it finished.
    static func finishedLine(folder: String, message: String?, korean: Bool) -> String {
        let head = korean ? "\(folder) 세션이 끝냈어요." : "The \(folder) session is done."
        guard let message, !message.trimmingCharacters(in: .whitespaces).isEmpty else { return head }
        return head + " " + message
    }
}
