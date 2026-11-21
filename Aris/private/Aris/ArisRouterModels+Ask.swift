//
//  ArisRouterModels+Ask.swift
//  Aris
//
//  The quick understanding on an API profile, asked through aris-agent (POST /api-brains {"op": "route"}): the agent
//  holds the key and calls the provider; Aris only ever sends the question and reads the JSON back. Every failure is
//  thrown, and routeNow then goes on as when Jev fails (the keyword rules).
//

import Foundation

extension ArisRouterModels {
    /// No API profile is connected that could answer (자동 found none, or the one chosen is gone).
    struct NoModel: Error {}

    static func ask(_ text: String, apps: [String], profile: String?) async throws -> ArisRouter.Answers {
        guard let question = question(text: text, apps: apps) else { throw ArisRouter.Failure(message: "the router's question couldn't be built") }
        var body: [String: Any] = ["op": "route", "system": question.system, "user": question.user, "schema": question.schema,
                                   "timeout": timeoutSeconds, "chatTimeout": ArisRouterPatience.limit(.chatModel)]
        if let profile { body["id"] = profile } else { body["auto"] = true }
        switch await ArisAgentClient.sendAPIBrains(body, timeout: max(2, ArisRouterPatience.appWait(api: true))) {
        case .failure(let problem): throw ArisRouter.Failure(message: problem.text)
        case .success(let object):
            if object["none"] as? Bool == true { throw NoModel() }
            if let error = object["error"] as? String {
                throw ArisRouter.Failure(message: "\(object["profile"] as? String ?? "api") \(object["kind"] as? String ?? ""): \(error)")
            }
            guard let reply = object["text"] as? String, let answers = answers(reply, for: question) else {
                throw ArisRouter.Failure(message: "\(object["model"] as? String ?? "the model")'s reply didn't make sense")
            }
            return answers
        }
    }
}
