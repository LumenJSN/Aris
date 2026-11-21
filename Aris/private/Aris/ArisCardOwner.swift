//
//  ArisCardOwner.swift
//  Aris
//
//  Whose card is it? A job's card is put up by Aris at a pause, so the quiet rule took every one of them for Aris's own
//  initiative: in the night hours it was shown as text and no microphone opened, even when the user had asked for that job
//  seconds before and was plainly there ("실행할까요?" answered out loud, and nothing heard: his log, 03:43).
//  A card for what he himself asked a short while ago is a reply to them (ArisQuiet.Starter.user): it is read aloud and
//  listens for yes or no, also at night. Everything else stays Aris's own and exactly as it was: a schedule's card
//  (nobody asked just now), a job that asks long after, and any card while the screen is locked or asleep. Mute is
//  not looked at here: ArisQuiet.decide keeps a muted Aris to text whoever started it.
//  Foundation only, so every combination is tested.
//

import Foundation

enum ArisCardOwner {
    /// How long after his own request a job's card still counts as a reply to it.
    static let recent: TimeInterval = 300

    /// `askedAgo`: seconds since the user asked for the job the card belongs to; nil when nobody asked (a schedule's card).
    /// `conversationOpenFor`: how long the conversation has been open; nil when none is. `screenAway`: the Mac is
    /// locked or its display sleeps.
    static func isReply(askedAgo: TimeInterval?, conversationOpenFor: TimeInterval?, screenAway: Bool) -> Bool {
        guard let askedAgo, askedAgo >= 0, !screenAway else { return false }
        if askedAgo <= recent { return true }
        // Longer ago, but in the conversation that is still open: he is still talking with Aris about it.
        guard let conversationOpenFor else { return false }
        return conversationOpenFor >= askedAgo
    }

    static func starter(askedAgo: TimeInterval?, conversationOpenFor: TimeInterval?, screenAway: Bool) -> ArisQuiet.Starter {
        isReply(askedAgo: askedAgo, conversationOpenFor: conversationOpenFor, screenAway: screenAway) ? .user : .aris
    }
}
