//
//  ArisDecisionAsk.swift
//  Shared/Core (Aris, tests)
//
//  What a decision model is asked (jv-decision): some words, and typed questions about them, each a choice among
//  named options. A decision model (TypeSafe's Jev was the first) only ever picks an option and says how sure it is; it
//  writes nothing. The ask is read off the request Aris has always sent Jev, so every provider is asked exactly what Jev
//  is: the words and the options, nothing more. Pure.
//

import Foundation

struct ArisDecisionAsk: Equatable, Sendable {
    struct Question: Equatable, Sendable {
        let name: String
        let instructions: String
        /// Each option's key, and what it means.
        let options: [String: String]
    }

    /// The words the questions are about.
    let state: String
    /// By name, in order.
    let questions: [Question]

    init(state: String, questions: [Question]) {
        self.state = state
        self.questions = questions.sorted { $0.name < $1.name }
    }

    /// The ask in a request as Jev takes it ({"state", "questions": {name: {"type": "choice", "instructions", "criteria"}}});
    /// nil when it has no words, no question, or a question that is not a choice among described options.
    init?(systemOne body: [String: Any]) {
        guard let state = body["state"] as? String, let questions = body["questions"] as? [String: Any], !questions.isEmpty else { return nil }
        var read: [Question] = []
        for (name, value) in questions {
            guard let question = value as? [String: Any], question["type"] as? String == "choice",
                  let criteria = question["criteria"] as? [String: String], !criteria.isEmpty else { return nil }
            read.append(Question(name: name, instructions: question["instructions"] as? String ?? "", options: criteria))
        }
        self.init(state: state, questions: read)
    }

    /// The ask with no question over `limit` options (a provider's own limit). Of a longer list these stay, in this
    /// order: the options in `keeping`, the ones the words name (by key, or by a name inside its description such as
    /// "KakaoTalk (카톡, 카카오톡)"), then the rest by key.
    func capped(_ limit: Int, keeping: Set<String>) -> ArisDecisionAsk {
        guard questions.contains(where: { $0.options.count > limit }) else { return self }
        let words = state.lowercased()
        return ArisDecisionAsk(state: state, questions: questions.map { question in
            guard question.options.count > limit else { return question }
            let ranked = question.options.keys.sorted { first, second in
                let ranks = (Self.rank(first, question.options[first] ?? "", words: words, keeping: keeping),
                             Self.rank(second, question.options[second] ?? "", words: words, keeping: keeping))
                return ranks.0 == ranks.1 ? first < second : ranks.0 < ranks.1
            }
            let kept = Set(ranked.prefix(limit))
            return Question(name: question.name, instructions: question.instructions, options: question.options.filter { kept.contains($0.key) })
        })
    }

    private static func rank(_ key: String, _ description: String, words: String, keeping: Set<String>) -> Int {
        if keeping.contains(key) { return 0 }
        let names = [key] + description.components(separatedBy: CharacterSet(charactersIn: "(),")).map { $0.trimmingCharacters(in: .whitespaces) }
        return names.contains { $0.count >= 2 && words.contains($0.lowercased()) } ? 1 : 2
    }
}

/// One question's answer: the option picked, and how sure the model is (0 to 1).
struct ArisDecisionAnswer: Equatable, Sendable {
    let choice: String
    let confidence: Double
}
