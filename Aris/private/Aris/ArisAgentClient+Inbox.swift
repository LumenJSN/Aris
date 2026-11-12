//
//  ArisAgentClient+Inbox.swift
//  Aris
//
//  What scheduled jobs left for the user in aris-agent's inbox (the app is sandboxed; the inbox is in ~/.config/aris):
//  fetching it, and taking delivered items out.
//

import Foundation

extension ArisAgentClient {
    private static let inboxURL = URL(string: "http://127.0.0.1:23351/inbox")!

    /// Oldest first; nil when the agent didn't answer.
    static func inbox() async -> [ArisInboxItem]? {
        guard let data = await inboxCall(["op": "fetch"]) else { return nil }
        return ArisInboxItem.decode(data)
    }

    /// The items were delivered: they leave the inbox. False when the agent didn't take it.
    @discardableResult
    static func acknowledge(_ ids: [String]) async -> Bool {
        await inboxCall(["op": "ack", "ids": ids]) != nil
    }

    private static func inboxCall(_ body: [String: Any]) async -> Data? {
        guard let token = ClaudeHookToken.load() else { return nil }
        var request = URLRequest(url: inboxURL, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
        request.httpBody = try? JSONSerialization.data(withJSONObject: identified(body))
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}
