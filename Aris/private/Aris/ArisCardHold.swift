//
//  ArisCardHold.swift
//  Aris
//
//  When a click on a confirm card's yes counts (security review 3, L2). The whole notch takes the first click even
//  while another app has the keyboard, the card's 허용 included, and a card for a job or a voice turn opens over the
//  top-centre of the app in use: a click meant for that app could land on 허용 as the card came down under the
//  pointer. So a click-yes counts only once the card has been on screen, in one place and at one size, for `hold`:
//  it is ignored within that long of the card being put up, and of its frame last moving or growing (the notch
//  opening, 전체 보기, a row that wrapped). A no needs no hold, nor does the Y key, a typed or a spoken answer: those
//  can't be a click meant for something else. While the hold is on the button is drawn held, not disabled: brighter
//  than a disabled one, with a line under its label that fills once over what is left of the hold (ArisCardStill;
//  nothing blinks or pulses), and at full strength when it is over.
//  Seventh VM run, item 3: a replay's step card that came up while the notch was still resizing after the step
//  before took a press on 허용 for nothing, drawn exactly like a disabled button, so nothing said why. The hold's
//  length stays the security review's (`hold`, one second; changed only with the owner's say); what changed is how a
//  held button is drawn.
//  Eighth VM run, item 2: the hold was counted from when the card's view was laid out, but the card fades in after
//  that (`entry`), so the owner saw the button for well under the hold before a press counted (notes8/T3: the card was
//  asked at 26.371, its label was on screen at 26.637, the button woke at 27.48). A card that comes in is now held
//  from when it is fully drawn (`entering`). And a press that lands during the hold is remembered (`refused`), so the
//  card can say calmly that it wasn't taken; it is never kept to be applied later. Foundation only (tested).
//  Ninth VM run, item 4: the step-3 card comes whole as the notch grows (no fade-in), and presses 0.953 s and 0.991 s
//  after its button was first on screen were taken (notes9/H6-clk.txt, H8c-clk.txt): the hold was counted from when
//  the card was laid out, and its pixels reach the screen a frame or two later. The eighth run's fix covered only the
//  fade-in. Now the live hold is marked `undrawn` at every change (put up, come in, frame changed), takes no click-yes
//  while it is, and counts from `drawn`: when the frames that change was drawn in have gone by (ArisCardStill). The
//  hold itself is as long as before.
//

import Foundation

struct ArisCardHold: Equatable {
    /// The card on screen (its id); nil: none.
    private(set) var card: String?
    /// When it was put up, or its frame last changed (system uptime).
    private(set) var since: Double?
    /// Where it was last measured, in its window.
    private(set) var frame: CGRect?
    /// When a click on its yes last came during the hold and was not taken; nil: none.
    private(set) var refusedAt: Double?
    /// The card as it is now (put up, or its frame changed) is not known to be on the screen yet: no click-yes counts
    /// until `drawn` says it is.
    private(set) var awaitsDraw = false
    /// When the mouse last went down in the card's window (system uptime); nil: none seen.
    private(set) var pressedAt: Double?

    /// A frame that differs by no more than this (points) is the same place: layout rounds.
    static let slack: CGFloat = 0.5
    /// How long the card must have been still before a click on its yes counts (security review 3, L2). The one place
    /// the hold's length is set. Half a second since 2026-11-19, by the owner's say (it was one second: a replay's cards
    /// cost over a second each before a press counted); everything else about the hold is as it was.
    static let hold: Double = 0.5
    /// The card's fade-in (ArisConfirmCard.entry): a card laid out now is fully drawn this much later.
    static let entry: Double = 0.3
    /// One display frame at the slowest rate counted on (30 a second), and how many go by before a change of the card
    /// is taken to be on the screen: the layout is handed over at the end of its run-loop turn and shown at a later
    /// refresh.
    static let frame: Double = 1.0 / 30
    static let drawFrames = 3
    /// How long the "not taken" note stays after the hold is over (or after the press, when that is later).
    static let noteStay: Double = 2.0
    /// The longest between a press going down and its click being handled for the press's own time to be what counts
    /// (a button's click comes at the mouse's release; a press held longer than this is judged when it is released).
    static let pressSpan: Double = 1.0
    /// How long before the hold is over the button starts to be drawn ready, so its one ease ends as a click starts to
    /// count (eleventh VM run, item 9: the ease began only when the hold was over, so for 150 ms the button took a
    /// click while it still looked held).
    static let wake: Double = 0.15

    /// Whether an answer waits for the hold at all: only a yes given by a click.
    static func applies(allow: Bool, source: ArisCardAnswer.Source) -> Bool { allow && source == .click }

    /// Card `id` was put up now: its hold starts, also when the card before it had the same id.
    func shown(_ id: String, at now: Double) -> ArisCardHold {
        ArisCardHold(card: id, since: now, frame: nil)
    }

    /// Card `id`'s view came in at `now` and fades in over `entry`: the hold counts from when it is fully drawn, so the
    /// owner sees the card for the whole hold before a click on its yes counts. Never earlier than it already was.
    func entering(card id: String, at now: Double) -> ArisCardHold {
        guard id == card else { return self }
        return keepingPress(ArisCardHold(card: card, since: max(since ?? now, now + Self.entry), frame: frame, refusedAt: refusedAt))
    }

    /// A click on card `id`'s yes came during the hold and was not taken. It changes nothing of the hold itself.
    func refused(card id: String, at now: Double) -> ArisCardHold {
        guard id == card else { return self }
        return keepingPress(ArisCardHold(card: card, since: since, frame: frame, refusedAt: now, awaitsDraw: awaitsDraw))
    }

    /// The card as it is now isn't on the screen yet (it was just put up, or its frame just changed).
    func undrawn() -> ArisCardHold {
        guard card != nil, !awaitsDraw else { return self }
        return keepingPress(ArisCardHold(card: card, since: since, frame: frame, refusedAt: refusedAt, awaitsDraw: true))
    }

    /// Card `id` as it is now has been drawn: its frames have gone by at `now`. The hold counts from here, never from
    /// earlier than it already did (a fade-in still to end).
    func drawn(card id: String, at now: Double) -> ArisCardHold {
        guard id == card, awaitsDraw else { return self }
        return keepingPress(ArisCardHold(card: card, since: max(since ?? now, now), frame: frame, refusedAt: refusedAt, awaitsDraw: false))
    }

    /// When the "not taken" note of card `id` goes: `noteStay` after the hold is over, or after the press when that is
    /// later. Nil: no press was refused.
    func noteUntil(card id: String) -> Double? {
        guard id == card, let refusedAt else { return nil }
        return max(readyAt ?? refusedAt, refusedAt) + Self.noteStay
    }

    /// Whether card `id` shows its "not taken" note at `now`.
    func noteShows(card id: String, at now: Double) -> Bool {
        guard let until = noteUntil(card: id), let refusedAt else { return false }
        return now >= refusedAt && now < until
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
        // Never earlier than it already was: a first layout measured while the card still fades in (`entering`).
        return keepingPress(ArisCardHold(card: card, since: max(now, since ?? now), frame: measured, refusedAt: refusedAt))
    }

    /// Whether a click on card `id`'s yes counts at `now`. A card the hold knows nothing of takes no click-yes.
    /// The hold is measured to when the press went down, never to when its click is handled (eleventh VM run, item 9:
    /// a press 447 ms after the card was first seen was taken, because the button's action ran at the mouse's release,
    /// 128 ms later, and that was past the hold).
    func clickCounts(card id: String, at now: Double) -> Bool {
        guard id == card, let since, !awaitsDraw, now - since >= Self.hold else { return false }
        guard let pressedAt, pressedAt <= now, now - pressedAt <= Self.pressSpan else { return true }
        return pressedAt - since >= Self.hold
    }

    /// The mouse went down in the card's window at `now`.
    func pressed(at now: Double) -> ArisCardHold {
        guard card != nil else { return self }
        var next = self
        next.pressedAt = now
        return next
    }

    /// When the button starts to be drawn ready (`wake` before the hold is over).
    var wakesAt: Double? { readyAt.map { $0 - Self.wake } }

    private func keepingPress(_ next: ArisCardHold) -> ArisCardHold {
        var kept = next
        kept.pressedAt = pressedAt
        return kept
    }

    /// When the hold is over, if nothing moves before then.
    var readyAt: Double? { awaitsDraw ? nil : since.map { $0 + Self.hold } }

    /// What is left of the hold at `now`, for the line under the held button (0 when it is over or there is none).
    func remaining(at now: Double) -> Double {
        if awaitsDraw { return since.map { max($0, now) + Self.hold - now } ?? 0 }
        return readyAt.map { max(0, $0 - now) } ?? 0
    }

    private static func same(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= slack && abs(a.minY - b.minY) <= slack && abs(a.width - b.width) <= slack && abs(a.height - b.height) <= slack
    }
}
