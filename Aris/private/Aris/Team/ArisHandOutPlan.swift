//
//  ArisHandOutPlan.swift
//  Aris
//
//  How a turn's handed-out work runs (security review C2, I1). A clean turn (no screen, no outside text in it or its
//  conversation) hands one job for Aris itself out as the user's own words, trusted, with the conversation around it; its
//  several jobs, or a teammate's, go as the model wrote them, untrusted, as before. An unclean turn hands every job
//  out untrusted (the agent runs it behind a per-call gate, with no web), with none of the conversation, and says so
//  to the agent (the conversation's claims). Such a job asks for the gated brain it will run on: Codex, the API brain
//  for an API-brain turn, or whichever of the two is set up on this Mac (ArisJobRouting, audit team-7). A hands-free turn (heard without a key or the name) is marked on each job too, so the agent's gate asks
//  before anything outbound; it alone doesn't make a turn unclean. A job's name comes from the user's words, never the
//  model's, so nothing a page planted is said aloud as a job's title (a clean turn's one job keeps only the model's app
//  hint, which picks the window Aris's figure perches on).
//

import Foundation

/// What a request to the agent claims about where it comes from; `fields` is exactly what /ask carries for it.
struct ArisProvenance: Equatable {
    var untrusted = false
    var screenConversation = false
    var outsideConversation = false
    var handsFree = false
    /// The turn takes no action (the rewrite of a selection declines every card): the agent's automatic check never
    /// counts its words as a request to act on.
    var noActions = false

    var fields: [String: Bool] {
        var fields: [String: Bool] = [:]
        if untrusted { fields["untrusted"] = true }
        if screenConversation { fields["screenConversation"] = true }
        if outsideConversation { fields["outsideConversation"] = true }
        if handsFree { fields["handsFree"] = true }
        if noActions { fields["noActions"] = true }
        return fields
    }
}

/// One job as it will run.
struct ArisJobPlan: Equatable {
    var spec: ArisJobSpec
    let brain: ArisBrain
    let provenance: ArisProvenance
    /// The user's own words, for the agent's policy.
    let request: String
    /// The job hears none of the conversation (its turns, the jobs' results).
    let cleanContext: Bool
    /// The dispatching turn's id (it may vouch for a Claude Code launch); never from an unclean or hands-free turn.
    let turn: String?
    /// Its finished job counts toward the offer to make a teammate (Aris's own, or a hand-out's first helper: F6).
    var countsTowardSuggestion = true
}

enum ArisHandOutPlan {
    /// The turn handing work out.
    struct Turn: Equatable {
        /// The user's words (unmarked).
        let words: String
        /// The brain that answered.
        let brain: ArisBrain
        /// The agent's turn id, if it gave one.
        let turnId: String?
        /// The agent said this turn is untrusted (an image, the screen).
        var untrustedTurn = false
        var screenConversation = false
        var outsideConversation = false
        var handsFree = false

        var isClean: Bool { !untrustedTurn && !screenConversation && !outsideConversation }
    }

    /// `specs`: the jobs block's jobs; empty when there were none to read (the agent refused the block, or "해 놔"):
    /// then one job of the user's words. `brains`: each teammate's own brain (the agent uses the stored one anyway).
    /// `helpersTaken`: the numbers helpers still at work hold (N14: this hand-out's helpers number on from them).
    /// `ready`: which brains are set up on this Mac (ArisJobRouting: an untrusted job asks for one that is).
    static func plan(_ specs: [ArisJobSpec], turn: Turn, brains: [String: ArisBrain] = [:], helpersTaken: Set<Int> = [],
                     ready: [String: Bool] = [:]) -> [ArisJobPlan] {
        counted(planned(specs, turn: turn, brains: brains, helpersTaken: helpersTaken, ready: ready)).map { plan in
            // The job's prompt keeps the user's words as said, whatever the model wrote (QA BUG-60: 큐에이 became "QA").
            guard plan.spec.prompt != turn.words, !turn.words.isEmpty else { return plan }
            var kept = plan
            kept.spec = ArisJobSpec(title: plan.spec.title, prompt: plan.spec.prompt + "\n\nThe user's own words, exactly as said (keep every name as written): “\(turn.words)”",
                                    assignee: plan.spec.assignee, cwd: plan.spec.cwd, appHint: plan.spec.appHint)
            return kept
        }
    }

    /// Aris's own data (its schedules, to-dos, memory, teammates, timers, settings) is never handed out: it is done in
    /// the main turn through its own aris-tools path and card (QA BUG-60).
    static func keepsInTurn(_ specs: [ArisJobSpec], turn: Turn) -> Bool {
        ArisOwnData.mentions(turn.words) || specs.contains { ArisOwnData.mentions($0.prompt) }
    }

    /// Said instead of handing Aris's own data out.
    static func keptLine(korean: Bool) -> String {
        korean ? "예약·할 일·기억 같은 Aris의 일은 팀원한테 넘기지 않아요. 다시 말해 주시면 제가 바로 할게요." : "Aris's own schedules, to-dos and memory never go to a teammate. Ask me again and I'll do it right away."
    }

    /// Only the hand-out's first helper counts toward the teammate offer.
    private static func counted(_ plans: [ArisJobPlan]) -> [ArisJobPlan] {
        let first = ArisHelpers.firstHelper(plans.map(\.spec))
        return plans.map { plan in
            var counted = plan
            counted.countsTowardSuggestion = ArisHelpers.countsTowardSuggestion(plan.spec.assignee, firstHelper: first)
            return counted
        }
    }

    private static func planned(_ specs: [ArisJobSpec], turn: Turn, brains: [String: ArisBrain], helpersTaken: Set<Int>,
                                ready: [String: Bool]) -> [ArisJobPlan] {
        let title = ArisHandoff.title(of: turn.words)
        let ownWords = ArisJobSpec(title: title, prompt: turn.words, assignee: .clone, cwd: nil, appHint: nil)
        let single = specs.count <= 1 && (specs.first?.assignee ?? .clone) == .clone
        let brain = { (spec: ArisJobSpec, fallback: ArisBrain) -> ArisBrain in
            if case .teammate(let id) = spec.assignee, id != ArisTeammate.claudeCodeId { return brains[id] ?? fallback }
            return fallback
        }
        guard turn.isClean else {
            let jobs = single ? [ownWords] : ArisHelpers.assign(specs.enumerated().map { index, spec in
                ArisJobSpec(title: specs.count > 1 ? "\(title) (\(index + 1))" : title, prompt: spec.prompt, assignee: spec.assignee,
                            cwd: spec.cwd, appHint: spec.appHint)
            }, taken: helpersTaken)
            let provenance = ArisProvenance(untrusted: true, screenConversation: turn.screenConversation,
                                            outsideConversation: turn.outsideConversation, handsFree: turn.handsFree)
            // The gated brain it will run on, one that is set up here (ArisJobRouting).
            let asked = ArisJobRouting.brain(forDispatched: turn.brain, ready: ready)
            return jobs.map { ArisJobPlan(spec: $0, brain: brain($0, asked), provenance: provenance, request: turn.words, cleanContext: true, turn: nil) }
        }
        let vouching = turn.handsFree ? nil : turn.turnId
        if single {
            // The model's app hint stays: it only picks the window Aris's figure perches on (ArisAppHint, exact names).
            let hinted = ArisJobSpec(title: title, prompt: turn.words, assignee: .clone, cwd: nil, appHint: specs.first?.appHint)
            // Hands-free: the agent runs it gated (Codex) or on the restricted Claude (ArisHandsFree.profile).
            return [ArisJobPlan(spec: hinted, brain: turn.brain, provenance: ArisProvenance(handsFree: turn.handsFree),
                                request: turn.words, cleanContext: false, turn: nil)]
        }
        // One job for one of the user's own teammates (not Claude Code, which opens in a terminal): the user's words as said, like
        // Aris's own single job, on the teammate's brain (the model only chose who; the teammate's scopes still hold).
        if specs.count == 1, case .teammate(let id) = specs[0].assignee, id != ArisTeammate.claudeCodeId {
            let spec = ArisJobSpec(title: title, prompt: turn.words, assignee: specs[0].assignee, cwd: nil, appHint: specs[0].appHint)
            return [ArisJobPlan(spec: spec, brain: brains[id] ?? turn.brain, provenance: ArisProvenance(handsFree: turn.handsFree),
                                request: turn.words, cleanContext: false, turn: nil)]
        }
        return ArisHelpers.assign(specs, taken: helpersTaken).map { spec in
            ArisJobPlan(spec: spec, brain: brain(spec, ArisJobRouting.brain(forDispatched: turn.brain, ready: ready)),
                        provenance: ArisProvenance(untrusted: true, handsFree: turn.handsFree), request: turn.words, cleanContext: false,
                        turn: vouching)
        }
    }
}
