//
//  ArisCardHold.swift
//  Aris
//
//  When a click on a confirm card's yes counts (security review 3, L2). The whole notch takes the first click even
//  while another app has the keyboard, the card's 허용 included, and a card for a job or a voice turn opens over the
//  top-centre of the app in use: a click meant for that app could land on 허용 as the card came down under the
//  pointer. So a click-yes counts only once the card has been on screen, in one place and at one size, for
//  ArisCardTiming.clickHold: it is ignored within that long of the card being put up, and of its frame last moving or
//  growing (the notch opening, 전체 보기, a row that wrapped). A no needs no hold, nor does the Y key, a typed or a
//  spoken answer: those can't be a click meant for something else. The button is drawn at rest until the hold is over
//  and comes to full strength then (ArisCardStill; nothing blinks). Foundation only (tested).
//

import Foundation

struct ArisCardHold: Equatable {
    /// The card on screen (its id); nil: none.
    private(set) var card: String?
    /// When it was put up, or its frame last changed (system uptime).
    private(set) var since: Double?
    /// Where it was last measured, in its window.
    private(set) var frame: CGRect?

    /// A frame that differs by no more than this (points) is the same place: layout rounds.
    static let slack: CGFloat = 0.5

    /// Whether an answer waits for the hold at all: only a yes given by a click.
    static func applies(allow: Bool, source: ArisCardAnswer.Source) -> Bool { allow && source == .click }

    /// Card `id` was put up now: its hold starts, also when the card before it had the same id.
    func shown(_ id: String, at now: Double) -> ArisCardHold {
        ArisCardHold(card: id, since: now, frame: nil)
    }

    /// The session's card as it is now: none clears the hold, and a card nobody announced starts its own.
    func following(_ id: String?, at now: Double) -> ArisCardHold {
        guard let id else { return ArisCardHold() }
        return id == card ? self : shown(id, at: now)
    }

    /// The card's view measured its frame: a new place or size starts the hold again; the same one changes nothing.
    /// A measure of another card (one that is going away) is not this card's.
    func framed(card id: String, _ measured: CGRect, at now: Double) -> ArisCardHold {
        guard id == card else { return self }
        if let frame, Self.same(frame, measured) { return self }
        return ArisCardHold(card: card, since: now, frame: measured)
    }

    /// Whether a click on card `id`'s yes counts at `now`. A card the hold knows nothing of takes no click-yes.
    func clickCounts(card id: String, at now: Double) -> Bool {
        guard id == card, let since else { return false }
        return now - since >= ArisCardTiming.clickHold
    }

    /// When the hold is over, if nothing moves before then.
    var readyAt: Double? { since.map { $0 + ArisCardTiming.clickHold } }

    private static func same(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= slack && abs(a.minY - b.minY) <= slack && abs(a.width - b.width) <= slack && abs(a.height - b.height) <= slack
    }
}
