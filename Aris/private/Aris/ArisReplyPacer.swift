//
//  ArisReplyPacer.swift
//  Aris
//
//  Paces the answer's updates while it streams in: at most one per interval, so the notch isn't re-laid out for every
//  token. It holds the newest text until the caller's flush takes it. Each waiting text is stamped with the turn's
//  generation; `drop` (a turn cancelled, replaced or finished) moves to the next one, so a flush already on its way
//  can never paint the old turn's text into a new one.
//

import Foundation

struct ArisReplyPacer {
    let interval: TimeInterval
    private var last: TimeInterval?
    private var generation = 0
    private var pending: (generation: Int, text: String)?

    init(interval: TimeInterval) {
        self.interval = interval
    }

    /// Holds `text` as the newest piece; returns how long to wait before flushing it (0: flush now).
    mutating func offer(_ text: String, at now: TimeInterval) -> TimeInterval {
        pending = (generation, text)
        guard let last else { return 0 }
        return max(0, interval - (now - last))
    }

    /// The waiting text for a flush at `now`, if it's this generation's; nil if there's none or it's stale.
    mutating func take(at now: TimeInterval) -> String? {
        defer { pending = nil }
        guard let pending, pending.generation == generation else { return nil }
        last = now
        return pending.text
    }

    /// Forgets the waiting text, and anything still stamped with this generation.
    mutating func drop() {
        generation += 1
        pending = nil
    }
}
