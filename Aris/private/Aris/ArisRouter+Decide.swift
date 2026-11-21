//
//  ArisRouter+Decide.swift
//  Aris
//
//  The router's questions put to any decision model (ArisDecider): the ask is read off the request Jev has always got,
//  and the reply, in Jev's shape, is read by the router's own parser, so the thresholds and what is acted on stay one
//  thing whoever answers. Foundation only (tested).
//

import Foundation

extension ArisRouter {
    /// Jev's questions for these words (ArisRouter.request) as an ask; nil when the request can't be read.
    static func decisionAsk(text: String, apps: [String]) -> ArisDecisionAsk? {
        guard let body = request(text: text, apps: apps, key: "").httpBody,
              let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { return nil }
        return ArisDecisionAsk(systemOne: object)
    }

    /// The time limit as a request takes it (seconds); the turn itself gives up at `timeout`.
    static let requestTimeout: TimeInterval = 5

    static func ask(_ text: String, apps: [String], decider: ArisDecider) async throws -> Answers {
        guard let ask = decisionAsk(text: text, apps: apps) else { throw Failure(message: "the router's question couldn't be built") }
        let data = try await decider.decide(ask, timeout: requestTimeout)
        guard let answers = parse(data) else { throw Failure(message: "the reply didn't make sense") }
        return answers
    }
}
