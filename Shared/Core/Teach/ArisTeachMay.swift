//
//  ArisTeachMay.swift
//  Shared/Core/Teach (aris-agent, tests, swift test)
//
//  Who may start a run of saved steps: one rule for both ways in, the owner's words by its name (ArisTeachTurn) and a
//  model's call (ArisMindTaught), so the second is never less strict than the first. A run is only ever started by the
//  owner himself, from the Aris app, typed or with the key held: never hands-free, never by a background task or a
//  teammate's turn, never by a voice that wasn't the owner's. A turn that carries outside text or the screen may start
//  one only on his card (the owner's path, which has no such card, takes only a plain turn). Pure.
//

import Foundation

enum ArisTeachMay {
    enum Start: Equatable, Sendable {
        case run
        /// Only on the owner's yes, on a card.
        case ask
        case refuse
    }

    /// `fromApp`: the turn came from the Aris app itself; `plain`: no screen came with it or was seen in it;
    /// `untrusted`: it carries, or its conversation read, outside text; `task`: a background task; `scoped`: a
    /// teammate's turn; `speaker`: who said the words (F1).
    static func start(fromApp: Bool, plain: Bool, handsFree: Bool, untrusted: Bool, task: Bool, scoped: Bool, speaker: ArisTurnSpeaker) -> Start {
        guard fromApp, !handsFree, !task, !scoped, speaker.countsAsOwner else { return .refuse }
        return plain && !untrusted ? .run : .ask
    }
}
