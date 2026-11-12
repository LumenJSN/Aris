//
//  ClaudeHookRoute.swift
//  Aris
//
//  What the hook server does with one whole request, decided from the request alone: no main thread, no Reminders or Calendar, no
//  helper. The checks are the ones the server always made, in the same order: the shared token first (fails closed
//  when the token file is missing), then POST to a known path, from this Mac (no Origin, Host is this listener), JSON.
//  A hook event that needs no decision is answered at once with the neutral reply and only then told to the notch;
//  the one that needs a decision is Claude's own PermissionRequest (Codex and Gemini ask in their own terminal, and
//  Aris never answers a PreToolUse: the gates of Aris's own Claude are command hooks of aris-tools, not this server).
//  Foundation only (tested).
//

import Foundation

enum HookAction {
    /// Answered at once with a refusal; `why` goes to the log.
    case refuse(HookReply, why: String)
    /// A hook event with nothing to decide: the neutral reply now, the event queued for the notch.
    case event(ClaudeHookEvent)
    /// Claude's PermissionRequest: held while the notch shows its card.
    case approval(ClaudeHookEvent)
    /// The status line's report (plan limits, context use): the neutral reply now, the report queued.
    case status([String: Any])
    /// aris-tools' `todo` and `event`: answered by the app once Reminders or Calendar has.
    case slow(path: String, body: [String: Any])
}

enum ClaudeHookRoute {
    static let hookPath = "/hook"
    static let statusPath = "/status"
    static let slowPaths: Set = ["/aris/todos", "/aris/events"]

    static func decide(_ request: HTTPRequest, token: String?, port: Int = 23350) -> HookAction {
        guard let token, request.hasToken(token) else {
            return .refuse(.refusal("401 Unauthorized"), why: "missing or wrong token")
        }
        guard request.method == "POST", request.path == hookPath || request.path == statusPath || slowPaths.contains(request.path),
              request.isLocalClient(port: port), request.isJSON,
              let object = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any] else {
            let seen = ["origin", "host", "content-type"].map { "\($0)=\(request.headers[$0] ?? "-")" }.joined(separator: " ")
            return .refuse(.refusal(HookRequestReader.badRequest), why: seen)
        }
        if slowPaths.contains(request.path) { return .slow(path: request.path, body: object) }
        if request.path == statusPath { return .status(object) }
        guard let event = ClaudeHookEvent(json: object, headers: request.headers) else {
            return .refuse(.refusal(HookRequestReader.badRequest), why: "not a hook event")
        }
        return event.needsDecision ? .approval(event) : .event(event)
    }

    /// Whether the bytes received so far open a request for a hook event (its answer, when in doubt, is the neutral one).
    static func opensHook(_ bytes: Data) -> Bool { bytes.starts(with: Data("POST \(hookPath) ".utf8)) }

    /// The same, once the head is in.
    static func isHook(_ head: HTTPHead) -> Bool { head.method == "POST" && head.path == hookPath }
}

extension ClaudeHookEvent {
    /// Only Claude's approvals are answered in the notch; every other event is only told.
    var needsDecision: Bool { name == "PermissionRequest" && agent == "claude" }
}

/// An event is read once off the wire and never changed (its JSON values are strings, numbers, lists and
/// dictionaries of them): it is passed from the server's queues to the main thread as it is.
extension ClaudeHookEvent: @unchecked Sendable {}
