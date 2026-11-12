//
//  ArisJobBrain.swift
//  aris-agent
//
//  Which AI runs a background job or a schedule. The owner's ruling: no feature is locked to one brain. A job runs on the
//  AI it asked for (the one the owner chose, a teammate's own, the one a schedule was made with) when that AI can run on
//  this Mac, else on the first that can. Scheduled work and every job from a conversation that had seen the screen
//  used to be sent to Codex whatever was installed, so on a Mac with only Claude or Antigravity they ended at once
//  with "Couldn't start GPT (Codex)" (audit sched-1, jobs-codex-only-6).
//
//  A job written from outside content (a screen turn, outside text, a schedule, a model) stays behind each brain's
//  own gate for outside words, exactly as a teammate's untrusted job already runs (ArisTeammateJobs.plan): Codex with
//  its web search off and every action through the risk gate, an API brain gated the same way, the open Claude with
//  its turn gate marked from the start (reads and web calls judged, nothing outbound), Antigravity sealed. Pure.
//

import Foundation

enum ArisJobBrain {
    /// Who is tried when the AI a job asked for can't run here. Outside-written work goes first to the brains whose
    /// every action passes a gate with a card, so it can still act; the user's own work goes first to Claude.
    static func order(untrusted: Bool) -> [ArisBrain] {
        untrusted ? [.codex, .api, .claude, .antigravity] : [.claude, .codex, .api, .antigravity]
    }

    /// The AI a job runs on: `wanted` when it can run on this Mac, else the first that can; nil when none can.
    static func pick(_ wanted: ArisBrain?, untrusted: Bool, usable: (ArisBrain) -> Bool) -> ArisBrain? {
        if let wanted, usable(wanted) { return wanted }
        return order(untrusted: untrusted).first(where: usable)
    }

    /// How an untrusted job that is nobody's (main Aris's own, a schedule's) runs on `brain`: as a teammate's that may
    /// use everything, behind that brain's gate for outside words.
    static func untrustedPlan(_ brain: ArisBrain) -> ArisTeammatePlan {
        ArisTeammateJobs.plan(brain: brain, untrusted: true, scopes: Set(ArisTeammateScope.allCases))
    }

    /// Whether the job's first question is marked as outside text whatever the caller said: on the open Claude, whose
    /// turn gate is the only thing between outside words and its tools.
    static func marksFromStart(_ brain: ArisBrain, untrusted: Bool) -> Bool {
        untrusted && brain == .claude
    }

    /// The AI a schedule runs on: its teammate's own brain, else the one it was made with, else whoever can.
    static func scheduled(teammate: ArisTeammate?, madeWith: String?, usable: (ArisBrain) -> Bool) -> ArisBrain? {
        let wanted = teammate.map(ArisTeammateJobs.brain(of:)) ?? madeWith.flatMap(ArisBrain.init(rawValue:))
        return pick(wanted, untrusted: true, usable: usable)
    }
}
