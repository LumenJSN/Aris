//
//  ArisTurnWatch.swift
//  Aris
//
//  A notch that says "생각 중" or "말하는 중" with nothing behind it never ends by itself: no wake word, no job results,
//  no cards, until the next key press (audit turn-2, imp-5). Every such state belongs to a running turn, which ends it.
//  So when a turn's task has ended by itself (it was not stopped, and no other turn took its place) and the notch is
//  still thinking or speaking with no card up, and nothing has touched it for a few seconds, it was left behind:
//  the controller puts it back to idle and logs it (ArisController+Watch). Foundation only, so it is tested.
//

import Foundation

enum ArisTurnWatch {
    /// How long a state nobody owns may stand untouched before it is put back to idle.
    static let patience: Duration = .seconds(5)

    /// The turn that just ended may have left the notch behind: worth looking again after `patience`.
    /// `busy`: the notch is thinking or speaking. `asking`: a card is up (its own wait ends it). `stopped`: the turn was
    /// cancelled (whoever stopped it set the notch). `replaced`: another turn runs now.
    static func mayBeLeftBehind(busy: Bool, asking: Bool, stopped: Bool, replaced: Bool) -> Bool {
        busy && !asking && !stopped && !replaced
    }

    /// After `patience`: the same leftover, and nothing changed the notch meanwhile (an announcement or a new turn
    /// would have).
    static func isLeftBehind(busy: Bool, asking: Bool, stopped: Bool, replaced: Bool, untouched: Bool) -> Bool {
        mayBeLeftBehind(busy: busy, asking: asking, stopped: stopped, replaced: replaced) && untouched
    }
}

/// A timer that ran out is always told: in the 기록 list at once, and in the notch at the next pause when Aris was
/// busy as it ended (audit imp-5: only the chimes played then). News that waited too long is no longer shown.
enum ArisTimerNews {
    /// Past this the notch line would only confuse; the 기록 entry still has it.
    static let showsWithin: Duration = .seconds(10 * 60)

    static func shows(waited: Duration) -> Bool { waited <= showsWithin }
}
