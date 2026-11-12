//
//  ArisAgentClient+Permissions.swift
//  Aris
//
//  The standing permissions aris-agent keeps ("앞으로 이건 그냥 할까?" → 응), for the settings list, and whether a
//  parked question still waits. The agent owns the file; the app only lists, revokes and asks.
//

import Foundation

/// One kind of action Aris may do without asking: its kind, app or connector, and recipient or target.
struct ArisStandingPermission: Codable, Hashable, Identifiable, Sendable {
    let kind: String
    let app: String
    let target: String

    var id: String { [kind, app, target].joined(separator: "\u{1F}") }
}

extension ArisAgentClient {
    private static let permissionsURL = URL(string: "http://127.0.0.1:23351/permissions")!

    /// Nil when the agent didn't answer (the list shows that, rather than an empty list).
    static func standingPermissions() async -> [ArisStandingPermission]? {
        guard let data = await permissionsCall(["op": "list"]) else { return nil }
        struct Reply: Decodable { let permissions: [ArisStandingPermission] }
        return (try? JSONDecoder().decode(Reply.self, from: data))?.permissions
    }

    /// True when the agent removed it.
    static func revoke(_ permission: ArisStandingPermission) async -> Bool {
        await permissionsCall(["op": "revoke", "kind": permission.kind, "app": permission.app, "target": permission.target]) != nil
    }

    /// Whether the agent still waits for an answer to `id`. A parked question that expired (or anything unclear)
    /// is not waiting, so its card never shows.
    static func isWaiting(_ id: String) async -> Bool {
        guard let data = await permissionsCall(["op": "waiting", "id": id]),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return body["waiting"] as? Bool == true
    }

    /// An open card's waiter: false only when the agent says it no longer waits; nil when the agent didn't answer
    /// (a hiccup never closes a card the user may be answering).
    static func stillWaits(_ id: String) async -> Bool? {
        guard let data = await permissionsCall(["op": "waiting", "id": id]),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let waiting = body["waiting"] as? Bool else { return nil }
        return waiting
    }

    /// An app-handled card's answer (save-answer, teammate, schedule, memory, undo…) into the agent's audit ledger, where
    /// the agent's own cards are (fire and forget: a card is never held up by it).
    static func recordCardAnswer(id: String, title: String, allow: Bool, source: ArisCardAnswer.Source) {
        let answer = source.isNoAnswer ? "no answer" : allow ? "yes" : "no"
        Task.detached { _ = await permissionsCall(["op": "cardAnswer", "id": String(id.prefix(80)), "title": String(title.prefix(120)), "answer": answer, "source": source.rawValue]) }
    }

    /// Whether a gate of the agent let this exact calendar or to-do write run (one-shot; ArisActionGrant). No answer is no.
    static func consumeGrant(_ key: String) async -> Bool { await grant(for: key).granted }

    /// The same for a route's write, and whether the automatic check let it through (the made item is then outside text:
    /// ArisOutsideItems). No key: a read, which needs none.
    static func grant(for key: String?) async -> (granted: Bool, outside: Bool) {
        guard let key else { return (true, false) }
        guard let data = await permissionsCall(["op": "consumeGrant", "key": key]),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any], body["granted"] as? Bool == true else { return (false, false) }
        return (true, body["outside"] as? Bool == true)
    }

    /// Whether aris-agent has Full Disk Access (it reads Messages, Mail and Notes for Aris); nil when it didn't answer.
    static func agentHasDiskAccess() async -> Bool? {
        guard let data = await permissionsCall(["op": "diskAccess"]),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return body["granted"] as? Bool
    }

    /// Whether aris-agent has Screen Recording (its tools read the screen for Aris); nil when it didn't answer.
    static func agentHasScreenAccess() async -> Bool? {
        guard let data = await permissionsCall(["op": "screenAccess"]),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return body["granted"] as? Bool
    }

    /// Whether aris-agent has its own switch in Accessibility (it types dictated words, reads and replaces the
    /// selection, and clicks and types for the AIs; Aris.app's switch does not count for it); nil when it didn't
    /// answer. The agent asks macOS at each call.
    static func agentHasAccessibility() async -> Bool? {
        guard let data = await permissionsCall(["op": "accessibilityAccess"]),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return body["granted"] as? Bool
    }

    /// 설정's 허용하기 for Desktop, Documents or Downloads: aris-agent reads that folder once, so macOS asks the user now (QA
    /// BUG-17). Waits while the prompt is up; true when aris-agent may read it, nil when the agent didn't answer.
    static func touchFolder(_ folder: String) async -> Bool? {
        guard let data = await permissionsCall(["op": "folder", "folder": folder], timeout: ArisUndoWords.clientTimeout),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return body["granted"] as? Bool
    }

    private static let cancelURL = URL(string: "http://127.0.0.1:23351/cancel")!

    /// A Claude Code teammate's session finished: the agent ends it and closes its window when the user never looked at
    /// it. What became of the window ("closed", "ended", "left"); nil when the agent didn't say.
    static func teammateFinished(job: UUID) async -> String? {
        guard let data = await permissionsCall(["job": job.uuidString, "done": true], url: cancelURL),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return body["window"] as? String
    }

    /// Cancels a background job's task in the agent: its parked questions are declined and its AI stops. Closing the
    /// job's stream alone doesn't, while the app runs (a dropped stream must not end a parked job).
    static func cancel(job: UUID) async -> Bool {
        await permissionsCall(["job": job.uuidString], url: cancelURL) != nil
    }

    /// The body of a 200 answer; nil for anything else.
    /// One of the app's own calls to the agent (its token and identity), at `url`.
    static func agentCall(_ body: [String: Any], url: URL, timeout: TimeInterval) async -> Data? {
        await permissionsCall(body, url: url, timeout: timeout)
    }

    private static func permissionsCall(_ body: [String: Any], url: URL = permissionsURL, timeout: TimeInterval = 5) async -> Data? {
        guard let token = ClaudeHookToken.load() else { return nil }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
        request.httpBody = try? JSONSerialization.data(withJSONObject: identified(body))
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}
