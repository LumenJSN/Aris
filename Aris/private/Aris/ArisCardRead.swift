//
//  ArisCardRead.swift
//  Aris
//
//  When a pressed yes on a confirm card counts, by how much of the card has been seen (security review 7, L1). A card
//  taller than its room scrolls inside it while 허용 floats in reach over its foot, so what comes after a long value
//  (a 3,000-character text, then the row that says which app it goes into) could be approved without ever being on
//  screen. So a yes given by a press, the button or the Y key, counts only once the card's end has been on screen:
//  at once for a card that fits its room, which is nearly every card, and after it has been scrolled to its end once
//  for one that does not. A card that grows (전체 보기) must be read to its new end. A no never waits. Typed and
//  spoken answers are left as they were (they are the user's own words about the card Aris has just read to them), and so
//  is a dictated message's countdown, which shows his own words.
//  The button is drawn at rest until then, as it is during the card's click hold (ArisCardHold); nothing blinks.
//  Foundation only (tested).
//

import CoreGraphics
import Foundation

struct ArisCardRead: Equatable {
    /// The card on screen (its id); nil: none.
    private(set) var card: String?
    /// How far down the card has been on screen, from its top; nil until it has been laid out.
    private(set) var seen: CGFloat?
    /// The card's whole height as last laid out.
    private(set) var content: CGFloat = 0
    /// The scroller's last layout, of whichever card was up: its whole content fitted its room. A job's next card put
    /// up in the same scroller at the same size gets no new layout event (eighth VM pass: its 허용 stayed at rest for two
    /// minutes), so a card that follows starts from it: read when the one before it fitted (its click hold, ArisCardHold,
    /// still applies), unread otherwise. A card of another size gets its own layout, which judges it again.
    private(set) var fitted = false

    /// A point of rounding still counts as the end.
    static let slack: CGFloat = 1

    /// Whether an answer waits for the card to be read at all: a yes given by a press, on a card that is not a countdown.
    static func applies(allow: Bool, source: ArisCardAnswer.Source, countdown: Bool) -> Bool {
        allow && !countdown && (source == .click || source == .key)
    }

    /// The session's card as it is now: another card starts as the scroller last laid out (`fitted`), none clears it.
    func following(_ id: String?) -> ArisCardRead {
        id == card ? self : started(id)
    }

    /// Card `id` was put up now, also when the card before it had the same id: unread, unless the scroller's last
    /// layout fitted its room (`fitted`).
    func shown(_ id: String) -> ArisCardRead { started(id) }

    /// A card just put up: read at once when the scroller's last layout fitted (nothing of it can be below its room
    /// until a layout says so), unread otherwise; after no card at all, unread.
    private func started(_ id: String?) -> ArisCardRead {
        var next = ArisCardRead(card: id)
        guard id != nil, card != nil, fitted else { return next }
        next.fitted = true
        next.seen = 0
        return next
    }

    /// The card's scroller as it stands: `offset` from its top, `visible` of its `content` on screen.
    func scrolled(card id: String, offset: CGFloat, visible: CGFloat, content: CGFloat) -> ArisCardRead {
        guard id == card, visible > 0, content > 0 else { return self }
        var next = self
        next.content = content
        next.seen = max(seen ?? 0, min(content, max(0, offset) + visible))
        next.fitted = content <= visible + Self.slack
        return next
    }

    /// The card's end has been on screen.
    var readToEnd: Bool {
        guard let seen else { return false }
        return seen >= content - Self.slack
    }

    /// Whether a pressed yes on card `id` counts. A card nothing is known of takes none.
    func yesCounts(card id: String) -> Bool { id == card && readToEnd }

    /// What the button says under the pointer while it waits.
    static func hint(english: Bool) -> String {
        english ? "Scroll to the end of the card first" : "카드를 끝까지 내려 본 뒤에 누를 수 있어요"
    }
}
