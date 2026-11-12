//
//  ArisAgentClient+Dictation.swift
//  Aris
//
//  Dictation's calls to aris-agent (the app is sandboxed: Accessibility, the clipboard's paste confirmation and the
//  dictionary file are the agent's): type it and learn from the edit, the caret's words, the brain polish fallback,
//  and the learned dictionary. Sent with this app's pid and start time (ArisPeer).
//

import Foundation

extension ArisAgentClient {
    private static let dictationInsertURL = URL(string: "http://127.0.0.1:23351/insert")!
    private static let caretURL = URL(string: "http://127.0.0.1:23351/caret")!
    private static let polishURL = URL(string: "http://127.0.0.1:23351/polish")!
    private static let dictionaryURL = URL(string: "http://127.0.0.1:23351/dictionary")!

    /// Dictated words typed where the cursor is; `learn`: the agent watches the field for a minute for the user's fix.
    static func insertDictation(_ text: String, learn: Bool) async -> ArisInsertOutcome {
        guard let (status, data) = await dictationSend(dictationInsertURL, ["text": text, "learn": learn], timeout: 6) else {
            return .failed("aris-agent didn't answer")
        }
        return ArisInsertOutcome.read(status: status, reply: (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:])
    }

    /// The words around the caret in the front app's field (polish only); nil when it can't or mustn't be read.
    static func caretContext() async -> (before: String, after: String)? {
        guard let (status, data) = await dictationSend(caretURL, [:], timeout: 2), status == 200,
              let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let before = reply["before"] as? String, let after = reply["after"] as? String else { return nil }
        return (before, after)
    }

    /// The brain's edit of `text` (no tools, the same instruction as on-device), or nil.
    static func polishDictation(_ text: String, style: ArisWritingStyle, words: [String], context: (before: String, after: String)?) async -> String? {
        var body: [String: Any] = ["text": text, "style": style.rawValue, "words": Array(words.prefix(ArisPolishPrompt.wordLimit))]
        if let context { body["before"] = context.before; body["after"] = context.after }
        guard let (status, data) = await dictationSend(polishURL, body, timeout: 12), status == 200,
              let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return reply["text"] as? String
    }

    /// Changes the learned dictionary: "accept", "dismiss" or "remove" a word. False when the agent couldn't.
    static func dictionary(_ op: String, text: String) async -> Bool {
        guard let (status, _) = await dictationSend(dictionaryURL, ["op": op, "text": text], timeout: 5) else { return false }
        return status == 200
    }

    private static func dictationSend(_ url: URL, _ body: [String: Any], timeout: TimeInterval) async -> (Int, Data)? {
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
