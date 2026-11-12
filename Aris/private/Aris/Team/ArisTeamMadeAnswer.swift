//
//  ArisTeamMadeAnswer.swift
//  Aris
//
//  A yes or no said or typed while the new-teammate card is up answers the card (BUG-25c), read as any card's
//  answer is (ArisConfirmReply); nil: no card up, or not a yes or no (an ordinary turn). A spoken yes makes the teammate
//  only as a spoken yes counts on any card (ArisConfirmReply.voiceYes): never in an open conversation or hands-free,
//  where the microphone hears more than the user; then it's the card's button (or a typed yes).
//

import Foundation

enum ArisTeamMadeAnswer {
    static func reply(_ text: String, cardUp: Bool) -> Bool? {
        cardUp ? ArisConfirmReply.parse(text) : nil
    }

    /// Whether this yes makes the teammate now: typed (the user at the keyboard), or spoken where a spoken yes counts.
    static func makes(yes: Bool, typed: Bool, inConversation: Bool, handsFree: Bool) -> Bool {
        yes && (typed || ArisConfirmReply.voiceYes(inConversation: inConversation, handsFree: handsFree))
    }
}
