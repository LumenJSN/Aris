//
//  ArisCardGroup.swift
//  aris-agent
//
//  Several same-kind calls of one request on one card (the eleventh VM run, K1: "이 문서에 적힌 할 일 미리 알림에 추가해
//  줘" put up a stopped card and then three cards, one for each to-do). Only for cards the automatic check left to the
//  owner in one turn (ArisAgentRunner.hold): the card lists every item in full, numbered, under the line that says why
//  it asks, and its one answer is the answer for each of them. It has no fields to change: an item that needs changing
//  is declined with the rest and asked for again. Pure.
//

import Foundation

enum ArisCardGroup {
    /// What the group is of: the checked kind's tool and verb ("todo add").
    static func kind(_ action: ArisAutoAction) -> String { action.tool + " " + action.verb }

    /// The twelfth VM run, K1 again: the three adds weren't checked (they never reached the automatic check), so each
    /// went up as an ordinary card, and their retries made three more. An ordinary card of one of these kinds, in a
    /// conversation, waits `gatherWait` for the same step's others of its kind, and they go up as one card. Only adds of
    /// separate items (a to-do, a reminder, an event); anything else goes up at once, as before. `argv`: the aris-tools
    /// call's words (ArisAutoScope.argv).
    static func gatherKind(_ argv: [String]?) -> String? {
        guard let argv, let tool = argv.first else { return nil }
        if tool == "todo" { return argv.dropFirst().first == "add" ? "todo add" : nil }
        if tool == "remind" { return "remind" }
        if tool == "event", !["find", "delete", "change"].contains(argv.dropFirst().first ?? "") { return "event" }
        return nil
    }
    static let gatherWait: TimeInterval = 0.4

    static func header(_ count: Int, english: Bool) -> String {
        english ? "\(count) items, asked about together:" : "\(count)개를 한 번에 물어봐요:"
    }

    /// One card for `held` (two or more, in the order they were asked): the first one's id and title.
    static func card(_ held: [(ask: ArisConfirmation, line: String)], english: Bool) -> ArisConfirmation {
        let lead = held[0]
        let items = held.enumerated().map { index, one -> String in
            let lines = ArisAutoCard.plain(one.ask.detail).split(whereSeparator: \.isNewline).map(String.init)
            return (["\(index + 1). " + (lines.first ?? "")] + lines.dropFirst()).joined(separator: "\n")
        }
        let detail = ([lead.line, header(held.count, english: english)] + items).filter { !$0.isEmpty }.joined(separator: "\n")
        return ArisConfirmation(id: lead.ask.id, title: lead.ask.title, detail: detail, full: nil, fields: [], allow: lead.ask.allow,
                                memoryWrite: lead.ask.memoryWrite, desktop: lead.ask.desktop)
    }
}
