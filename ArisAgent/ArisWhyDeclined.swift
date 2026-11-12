//
//  ArisWhyDeclined.swift
//  aris-agent
//
//  "why not?" after a request the AI turned down in its own words. No command was tried, so the gate saw nothing and
//  the turn's record holds no refusal; the question used to go to the AI, which then guessed at a refusal Aris never
//  made ("I don't know why Aris refused it": VM run 2026-11-11, upgrade, bug 4). The record still knows true things:
//  what he asked, which AI answered, that no card went up, that nothing was run and that Aris's gate refused nothing.
//  And when his own words hold one of the gate's money words, the rule that is behind such an answer whatever the AI
//  said: Aris never pays, with what he can do instead (the same rule and words a gate refusal gets: ArisWhyRules).
//  Here: when such a question is answered from the record, and the sentence it opens with. A question he asked ("for
//  문 대신 while 써도 돼?" → "왜 안 돼?") is still about what the AI said, and the AI answers it. Nothing here guesses
//  why the AI declined: where no rule is known the answer says only that Aris did not refuse it. Foundation only
//  (tested).
//

import Foundation

enum ArisWhyDeclined {
    /// Whether a why-not about `record` (a turn with no refusal of the gate's on record) is answered from the record:
    /// a request to do something that ended with no card and nothing run, or any request that reads as paying.
    static func answersFromRecord(_ record: ArisWhyRecord) -> Bool {
        guard record.cards.isEmpty, record.approved.isEmpty, record.autoCount == 0 else { return false }
        guard let asked = record.asked else { return true }
        return readsAsMoney(asked) || !asksAQuestion(asked)
    }

    /// His words hold a word that only means paying: read with the gate's own lists, the way it reads a tool's name
    /// (ArisRiskPolicy.hardLine: pay, purchase, buy, checkout, donate, refund, an order placed, funds transferred;
    /// never a word that only looks something up), and the same in Korean.
    static func readsAsMoney(_ asked: String) -> Bool {
        if ArisRiskPolicy.hardLine(of: .mcp(server: "", tool: asked)) == .money { return true }
        return koreanMoney.contains(where: asked.contains)
    }

    private static let koreanMoney = ["결제", "구매", "구입", "주문해", "주문 해", "송금", "이체", "기부해", "기부 해", "환불", "구독해", "구독 해", "납부",
                                      "돈 보내", "돈을 보내", "요금 내", "요금을 내"]

    private static let englishQuestion = #"^(?:what|why|how|when|where|who|whose|which|is|are|was|were|am|do|does|did|can i|could i|may i|should|shall|would it|will it|has|have i)\b"#
    private static let koreanQuestion = #"(?:될까|될까요|되나요|되나|돼|돼요|까|까요|나요|가요|인가요|니|냐|어때|어때요|뭐야|뭐예요|뭔데)$"#

    /// The request was a question ("is it ok to …?", "… 써도 돼?"), not something to do: a why-not after it is about the
    /// AI's own answer. "can you …?" and "…해 줄래?" are requests.
    static func asksAQuestion(_ asked: String) -> Bool {
        let text = asked.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let polite = text.range(of: #"^(?:can|could|will|would) you\b|(?:줄래|줄래요|주실래요|주시겠어요|줄 수 있어|줄 수 있어요)\??$"#, options: .regularExpression) != nil
        if polite { return false }
        if text.hasSuffix("?") || text.hasSuffix("？") { return true }
        return text.range(of: englishQuestion, options: .regularExpression) != nil || text.range(of: koreanQuestion, options: .regularExpression) != nil
    }

    /// The rule their words point at, when the turn did nothing and they read as paying; nil when no rule is known.
    static func rule(for record: ArisWhyRecord, done: [String]?, korean: Bool) -> ArisWhyRule? {
        guard (done ?? []).isEmpty, let asked = record.asked, readsAsMoney(asked) else { return nil }
        return ArisWhyRules.plain(ArisEscalation.moneyReason, korean: korean)
    }

    /// The sentence: Aris's rules refused nothing, who answered, whether anything was tried, and the rule when one is
    /// known. `brain`: the AI that answered, by its name (nil: Aris answered it itself). `ranNothing`: no command of any
    /// kind was part of the turn.
    static func lead(brain: String?, ranNothing: Bool, rule: ArisWhyRule?, korean: Bool) -> String {
        if korean {
            let who = brain.map { ArisJosa.attach($0, "이", "가") + " 자기 말로 답한 거예요" } ?? "AI 없이 Aris가 바로 답한 거예요"
            let tried = brain != nil && ranNothing ? ", 실행하려던 명령도 없었고요" : ""
            let known = rule.map { " 다만 요청에 돈을 내는 말이 있는데, \($0.why)." } ?? ""
            return "Aris의 규칙이 막은 건 아니에요. " + who + tried + "." + known
        }
        let who = brain.map { "\($0) answered in its own words" } ?? "Aris answered it itself, without an AI"
        let tried = brain != nil && ranNothing ? ", and no command was tried" : ""
        let known = rule.map { " Your request does have a word about paying, and \($0.why)." } ?? ""
        return "Aris's rules didn't refuse that. " + who + tried + "." + known
    }

    /// The list's rule line when the money rule is the one known.
    static func ruleNote(_ rule: ArisWhyRule, korean: Bool) -> String {
        korean ? "Aris의 문지기가 막은 건 없어요. 요청에 돈을 내는 말이 있어요: \(rule.why)." : "Nothing was refused by Aris's gate. Your request has a word about paying: \(rule.why)."
    }
}
