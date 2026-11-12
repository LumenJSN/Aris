//
//  ArisAgentClient+MCP.swift
//  Aris
//
//  설정 › 연결된 서비스 through aris-agent (POST /mcp, ArisMCPRoutes): the Composio key and the user's own MCP servers. The
//  agent keeps the list and puts every key and token in the Keychain itself; a secret goes over once, here, and never
//  comes back (only whether one is saved). Sent with this app's pid and start time: the agent answers only the Aris app
//  itself (ArisPeer).
//

import Foundation

/// One service row as the agent describes it (never a secret).
struct ArisMCPServiceRow: Identifiable, Equatable {
    struct Tool: Equatable {
        let name: String
        /// "read", "write" or "unknown" (ArisMCPKind).
        let kind: String
    }

    let id: String
    let name: String
    let transport: String
    /// The URL's host or the command line, to show.
    let target: String
    /// What 바꾸기 starts from: the URL or the command line in full.
    let edit: String
    let secretName: String?
    let enabled: Bool
    let hasSecret: Bool
    let composio: Bool
    /// What the last connection listed; nil before any.
    let tools: [Tool]?
    let error: String?

    init?(_ object: [String: Any]) {
        guard let id = object["id"] as? String, let name = object["name"] as? String else { return nil }
        self.id = id
        self.name = name
        transport = object["transport"] as? String ?? "http"
        target = object["target"] as? String ?? ""
        edit = object["edit"] as? String ?? ""
        secretName = object["secretName"] as? String
        enabled = object["enabled"] as? Bool ?? false
        hasSecret = object["hasSecret"] as? Bool ?? false
        composio = object["composio"] as? Bool ?? false
        tools = (object["tools"] as? [[String: Any]]).map { list in
            list.compactMap { tool in (tool["name"] as? String).map { Tool(name: $0, kind: tool["kind"] as? String ?? "unknown") } }
        }
        error = object["error"] as? String
    }
}

extension ArisAgentClient {
    private static let mcpURL = URL(string: "http://127.0.0.1:23351/mcp")!

    /// Every service, and what's wrong with the list (changed outside Aris); nil when the agent can't be reached or refused.
    static func mcpServices() async -> (rows: [ArisMCPServiceRow], problem: String?)? {
        guard case .success(let object) = await sendMCP(["op": "list"]) else { return nil }
        return ((object["servers"] as? [[String: Any]] ?? []).compactMap(ArisMCPServiceRow.init), object["problem"] as? String)
    }

    /// Nil when saved, else what to tell the user.
    static func saveMCPService(id: String?, name: String, target: String, secretName: String?, secret: String?) async -> String? {
        var body: [String: Any] = ["op": "save", "name": name, "target": target]
        if let id { body["id"] = id }
        if let secretName, !secretName.isEmpty { body["secretName"] = secretName }
        if let secret { body["secret"] = secret }
        return await sendMCP(body).problem
    }

    /// The Composio key (nil removes Composio). Nil when done, else what to tell the user.
    static func setComposioKey(_ key: String?) async -> String? {
        await sendMCP(key.map { ["op": "composio", "key": $0] } ?? ["op": "composio"]).problem
    }

    static func removeMCPService(_ id: String) async -> String? { await sendMCP(["op": "remove", "id": id]).problem }

    static func enableMCPService(_ id: String, _ on: Bool) async -> String? { await sendMCP(["op": "enable", "id": id, "on": on]).problem }

    /// 연결 테스트: (worked, the line to show).
    static func testMCPService(_ id: String) async -> (ok: Bool, message: String) {
        switch await sendMCP(["op": "test", "id": id], timeout: 45) {
        case .success(let object): return (object["ok"] as? Bool ?? false, object["message"] as? String ?? "")
        case .failure(let problem): return (false, problem.text)
        }
    }

    struct MCPProblem: Error { let text: String }

    private static func sendMCP(_ body: [String: Any], timeout: TimeInterval = 20) async -> Result<[String: Any], MCPProblem> {
        guard let token = ClaudeHookToken.load() else { return .failure(MCPProblem(text: "Aris 에이전트가 설치되지 않았어요.")) }
        var request = URLRequest(url: mcpURL, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
        request.httpBody = try? JSONSerialization.data(withJSONObject: identified(body))
        // URLSession.shared: its sockets live in this process, which is what ArisPeer's socket check reads.
        guard let (data, response) = try? await URLSession.shared.data(for: request), let status = (response as? HTTPURLResponse)?.statusCode else {
            return .failure(MCPProblem(text: "Aris 에이전트가 답하지 않아요."))
        }
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard status == 200 else { return .failure(MCPProblem(text: object["error"] as? String ?? "에이전트가 거절했어요 (\(status)).")) }
        return .success(object)
    }
}

private extension Result where Success == [String: Any], Failure == ArisAgentClient.MCPProblem {
    var problem: String? {
        if case .failure(let problem) = self { return problem.text }
        return nil
    }
}
