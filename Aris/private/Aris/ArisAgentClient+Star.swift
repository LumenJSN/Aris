//
//  ArisAgentClient+Star.swift
//  Aris
//
//  The setup's last page asks aris-agent about Aris's GitHub repository through the user's own gh (ArisGitHubStar on
//  the agent's side; the app is sandboxed and can't use gh's login): {"do": "check"} says who is logged in and whether
//  the repository is starred, {"do": "star"} stars it, only from the page's own button. The answers are read by
//  ArisStarCard; nil (no helper, no answer in time) falls back to opening the repository's page.
//

import Foundation

extension ArisAgentClient {
    private static let githubStarURL = URL(string: "http://127.0.0.1:23351/github-star")!

    /// The helper's answer to `ask` ("check" or "star"); nil when it couldn't be asked or didn't answer in time (each gh
    /// call there has 10 s; the two of a check run at once).
    static func githubStar(_ ask: String) async -> [String: Any]? {
        guard let token = ClaudeHookToken.load() else { return nil }
        var request = URLRequest(url: githubStarURL, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
        request.httpBody = try? JSONSerialization.data(withJSONObject: identified(["do": ask]))
        guard let (data, response) = try? await ArisNoStore.session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
