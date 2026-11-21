//
//  ArisHandOffCard.swift
//  Shared/Core (aris-agent, tests)
//
//  The card of a hand-off: words handed to something that then works on its own (Aside, a background job, a schedule,
//  a routine, a coding session). The twelfth VM run (cap12/B1-card1.jpg, B1-showall.jpg): Core 2's card for an Aside
//  hand-off read only "보내기", showed the internal id "aris.aside_task" and offered "항상". A hand-off's card shows
//  where it goes in plain words ("브라우저 도우미 Aside에게 맡기기", "예약하기 · 11월 22일 09:00에 한 번") and the exact
//  words that go out, whole (the owner's rule about paying included where the carrier appends it), and it is never
//  kept: no "항상", never covered by an earlier yes, a card of its own every time. Its lines are in the UI's language
//  (`english`), so the app draws them as they are. Pure.
//

import Foundation

/// A hand-off call as its card reads it back.
struct ArisHandOffFacts: Equatable, Sendable {
    /// Where it goes, in plain words: the card's title.
    let target: String
    /// The question said aloud.
    let spoken: String
    /// The words exactly as they go out.
    let text: String
    /// Other facts, one line each ("예약 이름: 아침").
    var notes: [String] = []
    /// The card is drawn in English (the UI's language).
    var english = false
}

enum ArisHandOffCard {
    static func textLead(english: Bool) -> String { english ? "What is handed over (word for word):" : "맡길 내용 (이대로 전해져요):" }
    static func onceLine(english: Bool) -> String {
        english ? "This yes is for this hand-off only. I'll ask again next time." : "이번 한 번만 맡겨요. 다음에 맡길 때도 다시 물어봐요."
    }

    /// The hand-off's own card: its target as the title, the words that go out whole (wrapped, never cut), and that the
    /// yes is for this once. Never a countdown, never "always".
    static func card(_ item: ArisAskItem, handOff: ArisHandOffFacts, id: String, intent: String, outside: String?) -> ArisAskCard {
        let english = handOff.english
        var lines: [String] = []
        if let outside { lines.append(outside) }
        lines += handOff.notes
        lines.append(textLead(english: english))
        // Exactly the words that go out, line for line (the card wraps them as it draws them; never cut).
        lines.append(handOff.text)
        lines.append(onceLine(english: english))
        let detail = lines.joined(separator: "\n")
        return ArisAskCard(id: id, title: handOff.target, detail: detail, full: nil, countdown: false, spoken: handOff.spoken, calls: [item.call],
                           intent: intent)
    }
}
