//
//  ArisTaskRecoveryLive.swift
//  aris-agent
//
//  The live start of a task taken back (ArisTaskTakeBack): a runner of its own behind the same gates it ran behind
//  (the same brain when it can still run here, its teammate's scopes, untrusted when it was), outside text from the
//  start whether resumed or restarted (a restart's summary carries what a model wrote; a reopened session can hold more
//  than its journal says), and its replies to the inbox under its job's id (ArisTaskFollow).
//

import Foundation

enum ArisTaskRecoveryLive {
    /// Every task taken back is untrusted (outside text), whatever its journal says.
    static let marksUntrusted = true

    static func run(home: String) {
        ArisTaskTakeBack.run(home: home, hooks: ArisTaskTakeBack.Hooks(launch: { state, prompt, session in launch(state, prompt: prompt, session: session, home: home) },
                                                                        audit: { ArisAgentRunner.writeAudit($0, key: "tasks") }))
    }

    private static func launch(_ state: ArisTaskState, prompt: String, session: String?, home: String) -> Result<ArisTaskRecord.Recovery, ArisTakeBackRefusal> {
        let brain = ArisBrain(rawValue: state.brain) ?? .claude
        var teammate: ArisTeammate?
        if let id = state.origin.teammate {
            teammate = ArisTeammateStore.load(file: ArisTeammateStore.file(home: home)).first { $0.id == id }
            // A teammate the user removed since: its job isn't run under anyone else's scopes.
            guard teammate != nil else { return .failure(.refused("its teammate is gone")) }
        }
        guard let runner = ArisAgentRunner.task(brain: brain, model: state.model, title: state.title, job: state.job, untrusted: state.origin.untrusted,
                                                teammate: teammate, handsFree: state.origin.sealedHandsFree, heardHandsFree: state.origin.handsFree,
                                                helper: state.origin.helper, fresh: true) else {
            return .failure(.cancelled)
        }
        // Reopened only on the same brain (ArisJobBrain may pick another when that one can't run here now).
        let resumed = session != nil && runner.brain == brain
        let how: ArisTaskRecord.Recovery = resumed ? .resumed : .restarted
        runner.recover(how, session: resumed ? session : nil, jobText: state.prompt)
        // A reopened session goes on from its own words; a restart is told what was done (the journal's summary).
        let words = resumed ? prompt : (session == nil ? prompt : ArisTaskRecovery.restartPrompt(state, answered: nil))
        let taint = ArisTaskTrail.taint(state.taint)
        let follow = ArisTaskFollow(job: state.job, title: state.title, inbox: ArisInbox.file(home: home), live: nil)
        // Outside text from the first word, resumed or restarted (the driver's taint and the open Claude's turn-gate mark,
        // both set before the question goes in): a restart's summary carries what a model wrote, and a reopened session
        // may hold more than its journal says (a tool's line read late, or the trail's writes dropped while the last
        // helper was exiting).
        runner.ask(words, tier: ArisTier(rawValue: state.origin.tier) ?? .work, request: state.request,
                   untrusted: Self.marksUntrusted,
                   screenSeen: state.origin.screenSeen || taint == .screenSeen, handsFree: state.origin.handsFree, ownData: state.origin.ownData) { reply in
            follow.deliver(reply)
        }
        return .success(how)
    }
}
