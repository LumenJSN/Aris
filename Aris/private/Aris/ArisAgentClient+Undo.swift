//
//  ArisAgentClient+Undo.swift
//  Aris
//
//  The activity log through aris-agent (the app is sandboxed; the log is in ~/.config/aris): the entries, and undoing
//  one. The "한 일" tab only needs these.
//

import Foundation

// ArisActivityItem, one entry, is in Side/ArisActivityTimeline.swift with the tab's logic; ArisUndoOutcome and what it
// says are in ArisUndoWords.swift.

extension ArisAgentClient {
    private static let undoURL = URL(string: "http://127.0.0.1:23351/undo")!
    private static let activityURL = URL(string: "http://127.0.0.1:23351/activity")!

    /// Undoes the entry `id`, or the latest undoable one from the last day when `id` is nil. `confirmed` needs an `id`
    /// and what the helper's 409 said the card must show: `echo`, or the detail of the card shown (`shown`) when that
    /// is the 409's summary itself (the 한 일 tab's card). The agent checks it (ArisUndoSteps.request).
    /// Sent with this app's pid and start time, as every /confirm is: only the app itself may undo (ArisPeer).
    static func undo(id: String? = nil, confirmed: Bool = false, shown: ArisConfirmation? = nil, echo: String? = nil) async -> ArisUndoOutcome {
        var body = ArisUndoSteps.request(id: id, confirmed: confirmed, echo: echo ?? shown?.detail)
        body["pid"] = Int(ProcessInfo.processInfo.processIdentifier)
        if let started { body["started"] = started }
        // macOS may be asking aris-agent for a folder meanwhile (QA BUG-17): longer than the agent's own minute.
        guard let (status, data) = await send(undoURL, body, timeout: ArisUndoWords.clientTimeout) else { return .failed("aris-agent didn't answer") }
        return ArisUndoSteps.outcome(status: status, reply: (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:])
    }

    private static let undoFolderURL = URL(string: "http://127.0.0.1:23351/undo-folder")!
    private static let activityLogURL = URL(string: "http://127.0.0.1:23351/activity-log")!

    /// The protected folder (Desktop, Documents, Downloads) undoing `id` (or the latest change) touches, from the log
    /// alone; nil when none or the agent didn't say.
    static func undoFolder(id: String?) async -> String? {
        guard let (status, data) = await send(undoFolderURL, id.map { ["id": $0] } ?? [:], timeout: 5), status == 200 else { return nil }
        return ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["folder"] as? String
    }

    /// Logs a change the app made itself (todo-add, todo-done, timer-set, timer-cancel, volume), so "방금 한 거 되돌려"
    /// takes the latest change (QA BUG-18). Best effort. `due`, `timed`: the date a to-do had before it was put off (todo-due).
    static func logLocalChange(kind: String, summary: String, id: String? = nil, level: Int? = nil, due: Double? = nil, timed: Bool = false) {
        var body: [String: Any] = ["kind": kind, "summary": summary]
        if let id { body["id"] = id }
        if let level { body["level"] = level }
        if let due { body["due"] = due; body["timed"] = timed }
        Task {
            _ = await send(activityLogURL, body, timeout: 15)
            await ArisReceiptModel.shared.localChangeLogged()
        }
    }

    /// What Aris did (today's only, or the last 30 days), oldest first; nil when the agent didn't answer.
    static func activity(today: Bool) async -> [ArisActivityItem]? {
        guard let (status, data) = await send(activityURL, ["today": today], timeout: 25), status == 200 else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([ArisActivityItem].self, from: data)
    }

    private static func send(_ url: URL, _ body: [String: Any], timeout: TimeInterval) async -> (Int, Data)? {
        guard let token = ClaudeHookToken.load() else { return nil }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
        request.httpBody = try? JSONSerialization.data(withJSONObject: identified(body))
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { return nil }
        return (status, data)
    }
}
