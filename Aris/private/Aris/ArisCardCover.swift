//
//  ArisCardCover.swift
//  Aris
//
//  A confirm card can be answered only while it is the card on screen (audit card-1: a job's card kept waiting after
//  The user started a turn over it, took a click or a Y meant for the next card, and was later sent as their no). The card's
//  wait asks here every time it looks: a card whose place the notch gave to something else (the user's turn, another card)
//  is "covered": it takes no click, key or spoken word, lets go of nothing that now belongs to the card on screen, and
//  never closes a session that isn't its own any more. Pure.
//

import Foundation

enum ArisCardCover {
    /// The card `card` is the one the notch shows (`shown`: the question on screen, nil when there is none).
    static func isUp(card: String, shown: String?) -> Bool { card == shown }

    /// What a click, Y, N or typed answer means for the card that waits as `card`: its answer only while it is the one
    /// on screen. The answer slot is one for the whole app, so a covered card must never read it.
    static func answer(_ typed: Bool?, card: String, shown: String?) -> Bool? {
        isUp(card: card, shown: shown) ? typed : nil
    }

    /// Whether a card whose wait ends may clear the shared answer slot and let the Y/N keys go: not when another card
    /// has come up meanwhile (they are that card's now).
    static func ownsKeys(card: String, shown: String?) -> Bool { shown == nil || shown == card }

    /// Whether the notch still shows what Aris spoke up with under `title` (a job's result or question): the user's own
    /// turn has other words in its place, and is never closed by an announcement that ended under it.
    static func stillOwn(title: String, heard: String, speaking: Bool) -> Bool { speaking && heard == title }
}
