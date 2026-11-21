//
//  ArisAgentClient+Models.swift
//  Aris
//
//  POST /models (ArisModelRoutes): a brain's model list as its tool gives it, and the check of a typed model id. Both
//  are answered by asking the tool, never a model.
//

import Foundation

extension ArisAgentClient {
    private static let modelsURL = URL(string: "http://127.0.0.1:23351/models")!

    /// `brain`'s models, and whether its tool listed them (false: today's fixed names). Nil: the helper didn't answer.
    static func models(_ brain: ArisBrain) async -> (options: [ArisModelOption], fromTool: Bool)? {
        guard case .success(let object) = await sendModels(["op": "list", "brain": brain.rawValue], timeout: 30) else { return nil }
        let options = (object["models"] as? [[String: Any]] ?? []).compactMap { row -> ArisModelOption? in
            guard let id = row["id"] as? String, ArisModelChoices.isModelID(id) else { return nil }
            return ArisModelOption(id: id, title: row["title"] as? String ?? id, detail: row["detail"] as? String,
                                   efforts: (row["efforts"] as? [String] ?? []).filter(ArisModelChoices.effortWords.contains))
        }
        return (options, object["fromTool"] as? Bool == true)
    }

    /// Whether `brain` takes the typed `model`: nil when it does (saved), else the line to show under the field.
    static func checkModel(_ model: String, brain: ArisBrain) async -> String? {
        switch await sendModels(["op": "check", "brain": brain.rawValue, "model": model], timeout: 30) {
        case .success(let object):
            return object["ok"] as? Bool == true ? nil : (object["message"] as? String ?? "\(brain.shortTitle)에서 쓸 수 없는 모델이에요: \(model)")
        case .failure(let problem):
            return problem.text
        }
    }

    private static func sendModels(_ body: [String: Any], timeout: TimeInterval) async -> Result<[String: Any], MCPProblem> {
        guard let token = ClaudeHookToken.load() else { return .failure(MCPProblem(text: "Aris 에이전트가 설치되지 않았어요.")) }
        var request = URLRequest(url: modelsURL, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
        request.httpBody = try? JSONSerialization.data(withJSONObject: identified(body))
        // ArisNoStore.session: its sockets live in this process, which is what ArisPeer's socket check reads.
        guard let (data, response) = try? await ArisNoStore.session.data(for: request), let status = (response as? HTTPURLResponse)?.statusCode else {
            return .failure(MCPProblem(text: "Aris 에이전트가 답하지 않아요."))
        }
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard status == 200 else { return .failure(MCPProblem(text: object["error"] as? String ?? "에이전트가 거절했어요 (\(status)).")) }
        return .success(object)
    }
}
