//
//  ArisPaymentHandOff.swift
//  aris-agent
//
//  The aris-tools commands that hand words to something that then works on its own, now or later: Aside (`aside`), a
//  background task given an instruction (`task add`), work that runs later (`schedule add`), a routine's steps
//  (`routine add`) and a coding session given a prompt (`session send|start`). Words that tell it to pay, buy, order,
//  subscribe or move money are refused at the gate, before any card and whatever the brain (ArisPaymentBoundary; the
//  eleventh VM run, R2: `aris-tools aside '…결제까지 진행해…'` was rated auto). The Aside tool, the session send, the
//  Claude Code launch and the background task check the same again where the words arrive. Pure.
//

import Foundation

enum ArisPaymentHandOff {
    /// Each carrier and the verbs its words come with (empty: the command's words are the brief). `session send|start`
    /// types words into one of the owner's coding sessions, or starts one with them.
    static let carriers: [String: Set<String>] = ["aside": [], "task": ["add"], "schedule": ["add"], "routine": ["add"], "session": ["send", "start"]]

    /// The words such a call hands over; nil for any other call.
    static func brief(_ arguments: [String]) -> String? {
        guard let tool = arguments.first, let verbs = carriers[tool] else { return nil }
        let rest = arguments.dropFirst()
        guard !verbs.isEmpty else { return rest.joined(separator: " ") }
        guard let verb = rest.first, verbs.contains(verb) else { return nil }
        return rest.dropFirst().joined(separator: " ")
    }

    /// What is typed into a coding session: its one line, ended with the owner's rule (on the same line) when it or the
    /// owner's request this turn is about paying, as every other hand-off's words are (ArisPaymentBoundary.bounded).
    static func sessionWords(_ text: String, request: String, english: Bool) -> String {
        guard ArisPaymentBoundary.involves(text) || ArisPaymentBoundary.involves(request) else { return text }
        let clause = ArisPaymentBoundary.stopClause(english: english)
        return text.hasSuffix(clause) ? text : text + " " + clause
    }

    /// The call hands over words that tell the job to pay. A coding session's words may name payment code as what it
    /// works on (ArisPaymentBoundary's coding context); every other carrier's may not.
    static func refuses(_ arguments: [String]) -> Bool {
        brief(arguments).map { ArisPaymentBoundary.judge(brief: $0, request: "", coding: arguments.first == "session") == .refused } ?? false
    }
}
