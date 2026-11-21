//
//  ArisDecisionWire.swift
//  Shared/Core (Aris, tests)
//
//  The two request shapes decision models take (checked on the providers' pages, 2026-11-19), and their replies read
//  back strictly:
//
//  - System One, TypeSafe's own (docs.typesafe.ai/primitives/choice): {"model", "state", "questions": {name: {"type":
//    "choice", "instructions", "criteria": {option: description}}}} -> {"answers": {name: {"choice", "confidence",
//    "probabilities"}}}. OpenRouter, Perplexity, Inception, Upstage, Liquid, Microsoft Foundry, Cloudflare Workers AI
//    and the open-source servers (Kev, Laya behind /v1/systemone) all take this shape. Cloudflare's REST API wraps
//    the reply in its usual {"result": ..., "success"} envelope.
//  - OpenAI's Decisions API (developers.openai.com/api/docs/guides/decisions): {"model", "input", "questions": [{"type":
//    "choice", "name", "instructions", "choices": [{"value", "description"}]}]} -> {"answers": [{"type": "choice",
//    "name", "choice", "confidence"}]}; any question may come back as {"type": "refusal"}.
//
//  A reply counts only when every question asked has one of its own options and a confidence from 0 to 1. A choice
//  that is not among the options, a confidence outside 0...1 or that is no number, a missing question, a refusal or
//  anything malformed is no answer, and the turn goes on as when Jev fails. Pure.
//

import Foundation

enum ArisDecisionWire: String, Sendable {
    case systemOne, openAI

    /// A reply longer than this is not read.
    static let maxReply = 1_000_000

    func body(_ ask: ArisDecisionAsk, model: String) -> [String: Any] {
        switch self {
        case .systemOne:
            let questions = ask.questions.map { ($0.name, ["type": "choice", "instructions": $0.instructions, "criteria": $0.options] as [String: Any]) }
            return ["model": model, "state": ask.state, "questions": Dictionary(uniqueKeysWithValues: questions)]
        case .openAI:
            let questions = ask.questions.map { question -> [String: Any] in
                ["type": "choice", "name": question.name, "instructions": question.instructions,
                 "choices": question.options.keys.sorted().map { ["value": $0, "description": question.options[$0] ?? ""] }]
            }
            return ["model": model, "input": ask.state, "questions": questions]
        }
    }

    /// Every question's answer, or nil when the reply is not exactly that.
    func answers(_ data: Data, for ask: ArisDecisionAsk) -> [String: ArisDecisionAnswer]? {
        guard data.count <= Self.maxReply, let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        var found: [String: [String: Any]] = [:]
        switch self {
        case .systemOne:
            let root = object["answers"] == nil ? (object["result"] as? [String: Any] ?? object) : object
            guard let answers = root["answers"] as? [String: Any] else { return nil }
            found = answers.compactMapValues { $0 as? [String: Any] }
        case .openAI:
            guard let answers = object["answers"] as? [[String: Any]] else { return nil }
            for answer in answers {
                guard let name = answer["name"] as? String, answer["type"] as? String == "choice" else { continue }
                found[name] = answer
            }
        }
        var read: [String: ArisDecisionAnswer] = [:]
        for question in ask.questions {
            guard let answer = found[question.name], let choice = answer["choice"] as? String, question.options[choice] != nil,
                  let confidence = answer["confidence"] as? NSNumber, CFGetTypeID(confidence) != CFBooleanGetTypeID(),
                  (0...1).contains(confidence.doubleValue) else { return nil }
            read[question.name] = ArisDecisionAnswer(choice: choice, confidence: confidence.doubleValue)
        }
        return read
    }

    /// Answers as Jev gives them, so what reads Jev's reply reads any provider's.
    static func systemOneReply(_ answers: [String: ArisDecisionAnswer]) -> Data {
        let body = ["answers": answers.mapValues { ["type": "choice", "choice": $0.choice, "confidence": $0.confidence] as [String: Any] }]
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }
}
