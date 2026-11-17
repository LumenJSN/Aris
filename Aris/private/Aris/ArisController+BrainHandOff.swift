//
//  ArisController+BrainHandOff.swift
//  Aris
//
//  "아니 그냥 클로드 시켜": the request goes to the AI (or the teammate) the user named, as a background job, the way a
//  teammate's job runs (ArisBrainHandOff decides from their words; this file asks the agent what is set up and hands it
//  out). An AI that isn't set up here is said as exactly that, with where to connect it; never "no such teammate".
//

import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "turn")

extension ArisController {
    /// How long Aris's "무엇을 맡길까요?" waits for its answer.
    static let pendingHandOffLasts: TimeInterval = 120

    /// The hand-off `words` say, with the teammates' list read first if it isn't in yet; or, right after Aris asked what
    /// to hand over, these words as its task. The question is asked once: the next turn answers it or not.
    func brainHandOff(_ words: String) async -> ArisBrainHandOff? {
        let pending = pendingHandOff
        pendingHandOff = nil
        let team = ArisTeamModel.shared
        if team.load != .ready {
            team.refresh()
            for _ in 0..<10 where team.load != .ready { try? await Task.sleep(for: .milliseconds(100)) }
        }
        if let said = ArisBrainHandOff.parse(words, teammates: team.teammates) { return said }
        guard let pending, Date().timeIntervalSince(pending.at) < Self.pendingHandOffLasts, followingUp || conversation.isOpen,
              !ArisFollowUp.isDone(words, afterQuestion: true), ArisBrainHandOff.saysTask(words) else { return nil }
        return ArisBrainHandOff(target: pending.handOff.target, said: pending.handOff.said, task: words)
    }

    /// Hands the request over as `handOff` says and returns what Aris said: the hand-off line, what is missing on this
    /// Mac, or the question of what to hand over.
    func handOver(_ handOff: ArisBrainHandOff, words: String, whole: String, tier: ArisTier, brain: ArisBrain, korean: Bool) async -> String {
        let english = !korean
        let teammate = ArisTeamModel.shared.teammates.first { mate in
            if case .teammate(let id) = handOff.target { return mate.id == id }
            return false
        }
        let name = ArisBrainHandOff.name(handOff.target, teammate: teammate?.name, english: english)
        if handOff.target.brain != nil, let missing = await missingForHandOff(handOff.target, korean: korean) {
            log.notice("hand-off to a brain that isn't set up here")
            await sayLocal(missing, heard: words)
            return missing
        }
        guard let brief = ArisBrainHandOff.brief(handOff, words: words, whole: whole, history: history, to: name) else {
            // Nothing in the conversation to hand over: asked once, and the next words are the task.
            let asked = ArisBrainHandOff.askLine(name, korean: korean)
            await sayLocal(asked, heard: words)
            pendingHandOff = (handOff, Date())
            return asked
        }
        let turn = ArisHandOutPlan.Turn(words: brief.request, brain: brain, turnId: nil, screenConversation: screenConversation,
                                        outsideConversation: outsideConversation, handsFree: turnHandsFree)
        let spec = ArisJobSpec(title: brief.title, prompt: brief.prompt, assignee: .clone, cwd: nil, appHint: nil)
        // Aris's own schedules, to-dos, memory, teammates, timers and settings stay in the main turn (QA BUG-60).
        if ArisHandOutPlan.keepsInTurn([spec], turn: turn) {
            let kept = ArisHandOutPlan.keptLine(korean: korean)
            await sayLocal(kept, heard: words)
            return kept
        }
        let brains = Dictionary(ArisTeamModel.shared.teammates.map { ($0.id, ArisBrain.named($0.brain)) }, uniquingKeysWith: { first, _ in first })
        var plan = ArisBrainHandOff.plan(brief, target: handOff.target, turn: turn, teammateBrains: brains)
        var notes: [String] = []
        // A teammate whose own brain isn't set up hands its job to Aris itself, as every teammate job does.
        let (kept, fellBack) = ArisJobRouting.withoutUnreadyTeammates([plan.spec], brains: brains, ready: ArisTeamModel.shared.brains)
        if let id = fellBack.first, let mateBrain = brains[id] {
            plan = ArisJobPlan(spec: kept[0], brain: brain, provenance: plan.provenance, request: plan.request, cleanContext: plan.cleanContext, turn: nil)
            notes.append(ArisJobRouting.fallbackLine(name: name, brain: mateBrain, korean: korean))
        }
        log.notice("handed to \(handOff.target.brain?.rawValue ?? "a teammate", privacy: .public)\(plan.provenance.untrusted ? " (untrusted)" : "", privacy: .public)")
        let created = dispatch([plan], tier: tier == .critical ? .critical : .work)
        let who: String? = fellBack.isEmpty ? name : nil
        let reply = ([ArisHandoffLine.line([who], korean: korean)] + notes).joined(separator: " ")
        stats?.firstSound(at: .now)
        session = session.answering(reply)
        recordTurn(heard: words, reply: reply, job: created.first)
        await speak { await self.speaker.speak(reply) }
        return reply
    }

    /// What is missing for `target` on this Mac, asked of the agent now (a brain logged out a moment ago counts); nil
    /// when it is set up, or when the agent didn't answer (the job then says itself what is missing).
    private func missingForHandOff(_ target: ArisHandOffTarget, korean: Bool) async -> String? {
        let said = await ArisAgentClient.teamBrainsSaid()
        var api: ArisBrainHandOff.APIState?
        if case .api(service: .some) = target, let list = await ArisAgentClient.aiProviders(), list.problem == nil {
            let local = Set(list.presets.filter(\.local).map(\.id))
            api = ArisBrainHandOff.APIState(active: list.active,
                                            connected: Set(list.profiles.filter { $0.hasKey || local.contains($0.id) }.map(\.id)))
        }
        return ArisBrainHandOff.missingLine(target, ready: said?.ready, api: api, korean: korean)
    }
}
