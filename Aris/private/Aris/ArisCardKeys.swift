//
//  ArisCardKeys.swift
//  Aris
//
//  Y or N for a waiting card, typed anywhere (KeyboardFocus's tap), without letting the user's typing in another app
//  answer it: a word that starts with "y" ("you", "yes") must never approve. Y and N count only within 15 s of the
//  card appearing and after 1.5 s with no keystroke. A Y or N is also held back 250 ms: if another key follows, it
//  was typing, and both go on to the app in order; only a lone Y approves and only a lone N declines (an N declining
//  at once ate the first letter of "now" typed in another app: bug hunt 11-06 #13). Every other key goes on untouched. Times are seconds on one clock.
//

import Foundation

struct ArisCardKeys: Equatable {
    static let window: Double = 15
    static let quietBefore: Double = 1.5
    static let lone: Double = 0.25

    enum Key: Equatable { case y, n, other }

    enum Decision: Equatable {
        /// The key goes on to the app.
        case pass
        /// A Y, held back: it approves if nothing follows within `lone` (due(at:)).
        case holdYes
        /// An N, held back: it declines if nothing follows within `lone`.
        case holdNo
        /// Another key came after a held Y or N: the user is typing. The held key, then this one, go on to the app in order.
        case passHeldThenThis
    }

    let presentedAt: Double
    private(set) var lastKeyAt: Double?
    private(set) var heldAt: Double?
    private(set) var heldKey: Key?

    /// `lastKeyAt`: the last keystroke anywhere before the card came, if known.
    init(presentedAt: Double, lastKeyAt: Double? = nil) {
        self.presentedAt = presentedAt
        self.lastKeyAt = lastKeyAt
    }

    /// Y and N count now: the card is fresh and the keyboard has been quiet.
    func listens(at now: Double) -> Bool {
        now - presentedAt < Self.window && (lastKeyAt.map { now - $0 >= Self.quietBefore } ?? true)
    }

    func key(_ key: Key, at now: Double) -> (ArisCardKeys, Decision) {
        var next = self
        next.lastKeyAt = now
        if heldAt != nil {
            next.heldAt = nil
            next.heldKey = nil
            return (next, .passHeldThenThis)
        }
        guard listens(at: now) else { return (next, .pass) }
        switch key {
        case .y, .n:
            next.heldAt = now
            next.heldKey = key
            return (next, key == .y ? .holdYes : .holdNo)
        case .other:
            return (next, .pass)
        }
    }

    /// The held key stood alone long enough: the answer (a Y approves, an N declines), and nothing is held any more.
    /// Nil while nothing is due.
    func due(at now: Double) -> (ArisCardKeys, Bool?) {
        guard let held = heldAt, let key = heldKey, now - held >= Self.lone else { return (self, nil) }
        var next = self
        next.heldAt = nil
        next.heldKey = nil
        return (next, key == .y)
    }

    /// A Y or N is held: if the card goes, it goes on to the app (it was a letter after all).
    var holds: Bool { heldAt != nil }
    var holdsYes: Bool { heldKey == .y }
}
