//
//  ArisTurnFallback.swift
//  aris-agent
//
//  Who answers a conversation turn when the brain it was meant for can't: out of quota, or not on this Mac (no program,
//  no key). The owner's ruling: no feature is locked to one brain. The old rule sent Codex's turns to Antigravity and
//  everyone else's to Codex whatever was installed, and never moved a turn that had seen the screen at all, so with
//  Codex at its limit every question was answered "한도에 닿았어요" although Claude was ready, and on a Mac without the
//  fixed fallback the answer was "Couldn't start … (is it installed?)" (audit fallback-dead-3).
//
//  Now the first other brain that can run here and isn't out itself takes it, in ArisJobBrain's order: the user's own turn
//  goes to Claude first; a turn that carries or follows outside content goes first to the brains whose every action
//  passes a gate. A turn that saw the screen, carries outside text or was heard hands-free still lands only where such
//  a turn always lands: the candidate's own route for it (ArisImageRouting: the gated Codex or API brain, the sealed
//  Claude, the sealed agy), never an open brain that would act unasked. Pure, so the tests run its table.
//

import Foundation

enum ArisTurnFallback {
    /// The turn as its routing reads it.
    struct Turn: Equatable {
        var images: [ArisTurnImage] = []
        /// "이거" text from the screen came with it (it goes to a gated brain only).
        var screenText = false
        /// Its conversation saw the screen.
        var screenConversation = false
        var handsFree = false
        /// Outside text came with it or into its conversation, or Aris read private data for agy in it: agy answers sealed.
        var outside = false
    }

    /// Where the turn goes instead of `brain`: the route of the first candidate that lands on a brain that can run here
    /// (`usable`), isn't out of quota (`available`) and isn't `brain` itself; nil when nobody can take it as it is.
    /// A route that would need the turn's prompt changed (the images dropped with a note, their text read instead) or
    /// that refuses it isn't taken: the prompt was written for a brain that sees what came with it.
    static func route(insteadOf brain: ArisBrain, turn: Turn, apiVision: Bool, usable: (ArisBrain) -> Bool, available: (ArisBrain) -> Bool) -> ArisImageRouting.Route? {
        let restricted = !turn.images.isEmpty || turn.screenText || turn.screenConversation || turn.handsFree || turn.outside
        func can(_ candidate: ArisBrain) -> Bool { candidate != brain && usable(candidate) && available(candidate) }
        let sight = ArisImageRouting.APISight(vision: apiVision, claude: can(.claude), codex: can(.codex))
        for candidate in ArisJobBrain.order(untrusted: restricted) where can(candidate) {
            let route = ArisImageRouting.route(requested: candidate, images: turn.images, screenText: turn.screenText, claudeInstalled: can(.claude),
                                               screenConversation: turn.screenConversation, handsFree: turn.handsFree, privateRead: turn.outside, api: sight)
            guard can(route.brain), route.refusal == nil, route.note == nil, !route.readsText, turn.images.isEmpty || route.sendsImages else { continue }
            return route
        }
        return nil
    }

    /// What the notch says when another brain takes the turn: why, and who.
    static func status(from brain: ArisBrain, to other: ArisBrain, missing: Bool) -> String {
        missing ? "\(brain.title) 없음 → \(other.title)" : "\(brain.title) 한도 → \(other.title)"
    }
}
