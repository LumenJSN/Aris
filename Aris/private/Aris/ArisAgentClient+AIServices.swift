//
//  ArisAgentClient+AIServices.swift
//  Aris
//
//  설정 › AI 서비스 through aris-agent (POST /api-brains: ArisAPIRoutes and ArisAPIConnections), as the page's own
//  values: the API brains and the user's connections, each one's models, which one answers, and 다른 AI 연결…'s
//  불러오기, 연결 and 지우기. A key goes over once and never comes back.
//

import Foundation

extension ArisAgentClient {
    /// The API brains and connections; nil when the agent didn't answer.
    static func aiProviders() async -> ArisAIAgentAnswers.List? {
        guard case .success(let object) = await sendAPIBrains(["op": "list"]) else { return nil }
        return ArisAIAgentAnswers.list(object)
    }

    /// A provider's models, or that its list couldn't be had.
    static func aiModels(_ preset: ArisAIPreset) async -> ArisAIModelList {
        guard case .success(let object) = await sendAPIBrains(["op": "models", "id": preset.id], timeout: 20) else { return .unreachable }
        return ArisAIAgentAnswers.models(object, preset: preset)
    }

    /// Nil when done, else what to tell the user.
    private static func aiProblem(_ body: [String: Any], timeout: TimeInterval = 20) async -> String? {
        if case .failure(let problem) = await sendAPIBrains(body, timeout: timeout) { return problem.text }
        return nil
    }

    /// Makes a saved provider the API brain that answers.
    static func aiActivate(_ id: String) async -> String? { await aiProblem(["op": "activate", "id": id]) }

    /// Saves a provider: its key (nil: kept), its models (nil: kept), and whether it answers from now on.
    static func aiSave(_ id: String, key: String? = nil, quick: String? = nil, strong: String? = nil, activate: Bool) async -> String? {
        var body: [String: Any] = ["op": "save", "id": id, "activate": activate]
        if let key { body["key"] = key }
        if let quick { body["quick"] = quick }
        if let strong { body["strong"] = strong }
        return await aiProblem(body)
    }

    /// 불러오기: the models an address answers with (empty: it couldn't list), or what is wrong with the address or key.
    static func aiProbe(base: String, key: String, editing id: String?) async -> Result<[String], MCPProblem> {
        var body: [String: Any] = ["op": "probe", "base": base]
        if !key.isEmpty { body["key"] = key }
        if let id { body["id"] = id }
        switch await sendAPIBrains(body, timeout: 20) {
        case .success(let object): return .success(object["models"] as? [String] ?? [])
        case .failure(let problem): return .failure(problem)
        }
    }

    /// 연결 (or 저장 for `id`): the connection's id, or what to tell the user.
    static func aiConnect(id: String?, name: String, base: String, key: String, model: String) async -> Result<String, MCPProblem> {
        var body: [String: Any] = ["op": "connect", "name": name, "base": base, "model": model, "activate": true]
        if !key.isEmpty { body["key"] = key }
        if let id { body["id"] = id }
        switch await sendAPIBrains(body) {
        case .success(let object): return .success(object["id"] as? String ?? id ?? "")
        case .failure(let problem): return .failure(problem)
        }
    }

    static func aiDisconnect(_ id: String) async -> String? { await aiProblem(["op": "disconnect", "id": id]) }
}
