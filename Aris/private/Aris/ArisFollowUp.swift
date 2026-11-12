//
//  ArisFollowUp.swift
//  Aris
//
//  In a conversation Aris goes back to listening after every answer (ArisConversation). Saying you're done
//  ("됐어", "그만", "고마워", "끝", "ok that's all") ends it on the Mac, without asking an AI. Includes how the
//  recognizer tends to write those short words ("고매워").
//

import Foundation

enum ArisFollowUp {
    /// One way of saying you're done (also as the recognizer writes it). A conversation ends on one of these, or two
    /// in a row ("됐어, 고마워"), with an optional lead-in ("이제", "응", "ok").
    private static let word = #"(됐어|됐어요|됬어|됐다|됐습니다|고[마매]워|고[마매]워요|고마와|감사합니다|감사해요|그만|그만해|그만하자|그만할게|끝|끝내|끝내자|끝났어|끝이야|thanks|thank you|no thanks|that'?s all|that'?s it|never mind|stop|bye|goodbye|i'?m done|we'?re done)"#
    /// These also answer a question ("다른 것도 할까요?" "괜찮아"): they end the conversation only when Aris didn't just ask one.
    private static let soft = #"(괜찮아|괜찮아요|아니야|없어|없어요|nothing|nope)"#
    private static let lead = #"((아니|이제|응|어|ok|okay|오케이|오키)[\s,.]*)?"#

    private static func pattern(_ word: String) -> String {
        "^\\s*" + lead + word + "([\\s,.!~]+" + word + ")?[\\s.!~]*$"
    }

    /// `afterQuestion`: Aris's last words asked something, so "괜찮아" or "없어" is an answer, not goodbye.
    static func isDone(_ text: String, afterQuestion: Bool = false) -> Bool {
        let words = afterQuestion ? word : "(" + word.dropFirst().dropLast() + "|" + soft.dropFirst().dropLast() + ")"
        return text.range(of: pattern(words), options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Whether Aris's reply ends on a question (a "?"), so a short "없어" answers it.
    static func asksSomething(_ reply: String) -> Bool {
        reply.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?") || reply.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("？")
    }
}
