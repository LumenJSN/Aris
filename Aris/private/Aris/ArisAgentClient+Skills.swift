//
//  ArisAgentClient+Skills.swift
//  Aris
//
//  The user's skills through aris-agent (POST /skills): the sandboxed app can't reach ~/Library/Application Support/Aris
//  or run SkillSpector, so the settings 스킬 page and the notch's skill flows ask the agent, with this app's pid and start
//  time (only the app itself may change skills: ArisPeer).
//

import Foundation

extension ArisAgentClient {
    private static let skillsURL = URL(string: "http://127.0.0.1:23351/skills")!

    /// One /skills call: its status code and JSON object, or nil when the agent didn't answer. A draft can take minutes.
    static func skills(_ body: [String: Any], timeout: TimeInterval = 15) async -> (status: Int, object: [String: Any])? {
        guard let token = ClaudeHookToken.load() else { return nil }
        var payload = body
        payload["pid"] = Int(ProcessInfo.processInfo.processIdentifier)
        // The app's language: what an AI writes for the 스킬 page (a check's findings, the maker's questions) is asked for in it.
        payload["lang"] = ArisSkillWords.language(english: ArisUIWords.english)
        if let started { payload["started"] = started }
        var request = URLRequest(url: skillsURL, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { return nil }
        return (status, (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:])
    }
}
