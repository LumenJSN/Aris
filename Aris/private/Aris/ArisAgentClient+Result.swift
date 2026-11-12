//
//  ArisAgentClient+Result.swift
//  Aris
//
//  The reader's saved results (the owner's 2A). The app is sandboxed and can't read ~/Documents/Aris, so aris-agent reads a
//  result for it and saves it as a note (POST /result), each only for a .md right in a result folder (ArisResultPath).
//

import Foundation

extension ArisAgentClient {
    private static let resultURL = URL(string: "http://127.0.0.1:23351/result")!

    /// A saved result's markdown and when it was saved; nil when the agent can't be reached or it isn't a result.
    static func readResult(_ path: String) async -> (text: String, modified: Date)? {
        guard let token = ClaudeHookToken.load() else { return nil }
        var request = URLRequest(url: resultURL, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
        request.httpBody = try? JSONSerialization.data(withJSONObject: identified(["op": "read", "path": path]))
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = body["text"] as? String else { return nil }
        let modified = (body["modified"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? Date()
        return (text, modified)
    }

    /// The reader's 메모에 저장: nil when the note was made, else what to show.
    static func noteResult(_ path: String) async -> String? {
        guard let token = ClaudeHookToken.load() else { return notSetUp }
        var request = URLRequest(url: resultURL, timeoutInterval: 25)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
        request.httpBody = try? JSONSerialization.data(withJSONObject: identified(["op": "note", "path": path]))
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if (response as? HTTPURLResponse)?.statusCode == 200 { return nil }
            let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            return body?["error"] as? String ?? refused
        } catch {
            return failure(describing: error)
        }
    }
}
