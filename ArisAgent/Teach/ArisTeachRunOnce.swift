//
//  ArisTeachRunOnce.swift
//  aris-agent
//
//  The helper's side of a taught run's one card (ArisTeachRunPass, jv-quick). Before the run: each step's mark for the
//  card, from what the trust policy would decide for it now (read only: ArisTrustGate.preview), so the card is asked
//  only when it stands in for at least one step's own card and says which steps still ask. During the run: what the
//  gate really decided about each call (ArisMindJudge.outcome), which is what the pass goes by, never the preview; a
//  step that ran on the pass is written in the record as answered on the run's card.
//

import Foundation

extension ArisTeachRunner {
    /// Each step's mark for the run's one card, in the plan's order. A step that can't be read asks again.
    func marks(_ plan: ArisTeachReplay.Plan) -> [ArisTeachRunPass.Mark] {
        plan.calls.enumerated().map { index, call in
            guard let call, index < plan.steps.count, case .success(let read) = judge.read(call) else { return .asksAgain }
            let effect = read.entry.effect(read.arguments), payment = read.entry.payment(read.arguments)
            let decision = gate.preview(capability: read.entry.id, effect: effect, arguments: read.arguments, payment: payment)
            let why = ArisTeachCover.why(at: index, in: plan.steps, ownerGave: plan.ownerGave)
            // A browser's page is read at the run (decision 2): every act there asks then. Typing after a step that may
            // have selected text is decided at the run too, from the selection read then: the card says it asks again.
            if why == .browser || why == .mayTypeOver { return .asksAgain }
            let covered = why == .covered
            return ArisTeachRunPass.Mark.of(covered: covered, waits: ArisMindVerdict(decision) == .waits,
                                            judged: ArisTeachRunPass.Judged(effect: effect, asks: decision == .ask, payment: payment))
        }
    }

    /// A step's arguments as it is run: typing carries what its decision saw it would erase (`erases`: the selection it
    /// goes over, nil when nothing was selected; for a replace, the field's whole text as its card showed it), which
    /// app.type checks against the field right before it types or replaces.
    static func typing(_ read: ArisMindJudge.Read, erases: ArisErasedText?) -> [String: Any] {
        guard read.entry.id == "app.type" else { return read.arguments }
        return read.arguments.merging([ArisApps.TypeOver.argument: ArisApps.TypeOver.mark(erases: erases)]) { $1 }
    }

    /// What the gate decided about a call, as the pass reads it.
    static func judged(_ outcome: ArisTrustGate.Outcome) -> ArisTeachRunPass.Judged {
        ArisTeachRunPass.Judged(effect: outcome.effect, asks: outcome.decision == .ask, content: outcome.verdict.provenance.source != nil,
                                payment: outcome.facts.registeredPayment || outcome.facts.payment, browser: outcome.facts.browser != nil,
                                erases: outcome.facts.erases != nil, sends: outcome.facts.sends != nil)
    }

    /// The pass as the run takes it: judged by the gate's own decision of each call, used calls told to the record.
    func approval(_ pass: ArisTeachRunPass, session: String) -> ArisTeachReplay.Approval {
        ArisTeachReplay.Approval(box: ArisTeachPassBox(pass),
                                 judged: { [judge] call in judge.outcome(session: session, call: call).map(Self.judged) },
                                 used: { [gate] call in gate.passed(call: call) })
    }
}
