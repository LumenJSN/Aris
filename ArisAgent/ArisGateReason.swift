//
//  ArisGateReason.swift
//  aris-agent
//
//  When a card opens with "Asking once more because outside content was read" (ArisEscalation.taintedReason). The
//  line means one thing: without the outside content in the conversation this would have run without a card. Each
//  gate says it for an action the owner approved before (remembered, asked again), and ArisEscalation.card for one a grant
//  or the judge could have let through (a move to the Trash, a to-do). An action that simply runs by itself in a clean
//  conversation and is carded only after outside text had no such line: after the brain's own `files find` (file
//  names are outside text) the trash card carried it and the conversion's card, in the same situation, did not (third
//  VM run). The rule for that third kind is here, applied where every brain's card passes (ArisAgentRunner), so no
//  brain's card differs. Foundation only, so it is tested.
//

import Foundation

enum ArisGateReason {
    /// Whether the card is there only because outside content was read: the conversation holds it (`outside`), no
    /// hard line is in play, the action runs by itself in a clean conversation (`cleanRisk` auto), and it is one of
    /// the kinds asked after outside text (ArisRiskPolicy.asksAfterOutsideText).
    static func raised(outside: Bool, hardLine: Bool, cleanRisk: ArisRisk, asksAfter: Bool) -> Bool {
        outside && !hardLine && cleanRisk == .auto && asksAfter
    }

    /// The card with the line before its details (and before the whole text, when it has one), once; everything else
    /// of the card as it was: its fields to edit, its yes word, what it is about.
    static func card(for ask: ArisConfirmation, raised: Bool) -> ArisConfirmation {
        let reason = ArisEscalation.taintedReason
        guard raised, !ask.countdown, !ask.detail.hasPrefix(reason) else { return ask }
        return ArisConfirmation(id: ask.id, title: ask.title, detail: reason + "\n" + ask.detail, countdown: false, spoken: ask.spoken, proposal: ask.proposal,
                                full: ask.full.map { reason + "\n" + $0 }, fields: ask.fields, allow: ask.allow, memoryWrite: ask.memoryWrite, desktop: ask.desktop)
    }
}
