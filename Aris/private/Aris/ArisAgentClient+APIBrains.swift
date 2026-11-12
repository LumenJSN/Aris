//
//  ArisAgentClient+APIBrains.swift
//  Aris
//
//  설정 › AI 서비스 › 두뇌 › API 브레인 through aris-agent (POST /api-brains, ArisAPIRoutes): which provider answers when
//  the brain is "API 키", its key and models. The agent keeps the profiles and puts the key in the Keychain itself; a key
//  goes over once, here, and never comes back (only whether one is saved). Only the Aris app itself is answered (ArisPeer).
//

import Foundation

/// One provider as the agent describes it.
struct ArisAPIPresetRow: Identifiable, Equatable {
    let id: String
    let title: String
    let needsKey: Bool
    let keySource: String
    let local: Bool
    let baseURL: String
    let quick: String
    let strong: String

    init?(_ object: [String: Any]) {
        guard let id = object["id"] as? String, let title = object["title"] as? String else { return nil }
        self.id = id
        self.title = title
        needsKey = object["needsKey"] as? Bool ?? true
        keySource = object["keySource"] as? String ?? ""
        local = object["local"] as? Bool ?? false
        baseURL = object["baseURL"] as? String ?? ""
        quick = object["quick"] as? String ?? ""
        strong = object["strong"] as? String ?? ""
    }
}

/// One saved profile (never its key).
struct ArisAPIProfileRow: Equatable {
    let id: String
    let quick: String
    let strong: String
    let baseURL: String?
    let hasKey: Bool
    let vision: Bool
    let tools: Bool

    init?(_ object: [String: Any]) {
        guard let id = object["id"] as? String else { return nil }
        self.id = id
        quick = object["quick"] as? String ?? ""
        strong = object["strong"] as? String ?? ""
        baseURL = object["baseURL"] as? String
        hasKey = object["hasKey"] as? Bool ?? false
        vision = object["vision"] as? Bool ?? false
        tools = object["tools"] as? Bool ?? true
    }
}

struct ArisAPIBrainList: Equatable {
    var presets: [ArisAPIPresetRow] = []
    var profiles: [ArisAPIProfileRow] = []
    var active: String?
    /// "profile/model" of every model that passed the smoke check.
    var tested: Set<String> = []
    var problem: String?
}

extension ArisAgentClient {
    private static let apiBrainsURL = URL(string: "http://127.0.0.1:23351/api-brains")!

    static func apiBrains() async -> ArisAPIBrainList? {
        guard case .success(let object) = await sendAPIBrains(["op": "list"]) else { return nil }
        let tested = (object["tested"] as? [[String: Any]] ?? []).compactMap { row -> String? in
            guard let profile = row["profile"] as? String, let model = row["model"] as? String, (row["failed"] as? [String] ?? []).isEmpty else { return nil }
            return profile + "/" + model
        }
        return ArisAPIBrainList(presets: (object["presets"] as? [[String: Any]] ?? []).compactMap(ArisAPIPresetRow.init),
                                profiles: (object["profiles"] as? [[String: Any]] ?? []).compactMap(ArisAPIProfileRow.init),
                                active: object["active"] as? String, tested: Set(tested), problem: object["problem"] as? String)
    }

    /// Saves a provider's profile (and makes it the one that answers). `key`: a new key, "" removes it, nil keeps it.
    /// Nil when saved, else what to tell the user.
    static func saveAPIBrain(id: String, key: String?, quick: String?, strong: String?, baseURL: String?) async -> String? {
        var body: [String: Any] = ["op": "save", "id": id, "activate": true]
        if let key { body["key"] = key }
        if let quick { body["quick"] = quick }
        if let strong { body["strong"] = strong }
        if let baseURL { body["baseURL"] = baseURL }
        return await sendAPIBrains(body).apiProblem
    }

    static func removeAPIBrain(_ id: String) async -> String? { await sendAPIBrains(["op": "remove", "id": id]).apiProblem }

    /// The provider's models (its own list, or the preset's).
    static func apiBrainModels(_ id: String) async -> [String] {
        guard case .success(let object) = await sendAPIBrains(["op": "models", "id": id], timeout: 20) else { return [] }
        return (object["models"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
    }

    /// 테스트: (worked, the line to show).
    static func testAPIBrain(_ id: String, model: String?) async -> (ok: Bool, message: String) {
        var body: [String: Any] = ["op": "test", "id": id]
        if let model { body["model"] = model }
        switch await sendAPIBrains(body, timeout: 90) {
        case .success(let object): return (object["ok"] as? Bool ?? false, object["message"] as? String ?? "")
        case .failure(let problem): return (false, problem.text)
        }
    }

    /// The same check for the API profile that answers now, whichever it is (the status line's "check again").
    static func testActiveAPIBrain() async -> (ok: Bool, message: String) {
        switch await sendAPIBrains(["op": "test", "active": true], timeout: 90) {
        case .success(let object): return (object["ok"] as? Bool ?? false, object["message"] as? String ?? "")
        case .failure(let problem): return (false, problem.text)
        }
    }

    static func sendAPIBrains(_ body: [String: Any], timeout: TimeInterval = 20) async -> Result<[String: Any], MCPProblem> {
        guard let token = ClaudeHookToken.load() else { return .failure(MCPProblem(text: "Aris 에이전트가 설치되지 않았어요.")) }
        var request = URLRequest(url: apiBrainsURL, timeoutInterval: timeout)
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
    var apiProblem: String? {
        if case .failure(let problem) = self { return problem.text }
        return nil
    }
}
