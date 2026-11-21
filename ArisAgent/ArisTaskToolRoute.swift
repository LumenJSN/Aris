//
//  ArisTaskToolRoute.swift
//  aris-agent
//
//  POST /task-tool {"turn", "words": […]}  ->  {"status", "output"}: `aris-tools task …` from inside a conversation
//  turn (ArisTaskTool). The caller must be that turn's own brain process, as for /routine-tool. A cancel goes the way
//  the app's own does (ArisAgentRunner.cancel(job:): its cards declined, its process ended, its journal closed), and the
//  app, which follows the job, takes the helper's "cancelled" as a cancel, not a failure (ArisJobCancelLine).
//

import Foundation
import Network

enum ArisTaskToolRoute {
    static func tool(_ object: [String: Any], on connection: NWConnection, agentPort: UInt16, reply: @escaping (String, Data) -> Void) {
        let refuse = { (why: String) in
            ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["answer": "refused (\(why))", "question": "task-tool"]), key: "local")
            reply("403 Forbidden", ArisMCPRoutes.json(["status": 1, "output": "aris-tools task works only inside an Aris turn."]))
        }
        guard let credential = object["turn"] as? String, let runner = ArisAgentRunner.runner(forMCPTurn: credential) else { return refuse("no turn credential") }
        let remotePort = ArisTeammateDesk.remotePort(of: connection)
        DispatchQueue.global(qos: .userInitiated).async {
            let now = runner.messageSnapshot()
            guard now.active else { return refuse("no turn under way") }
            guard let pid = now.pid, let remotePort, ArisMCPCaller.isInside(root: pid, remotePort: remotePort, agentPort: agentPort) else {
                return refuse("not from the brain's own process")
            }
            let words = (object["words"] as? [Any] ?? []).compactMap { $0 as? String }
            guard let call = ArisTaskTool.parse(words) else {
                return reply("200 OK", ArisMCPRoutes.json(["status": 1, "output": ArisTaskTool.usage]))
            }
            let caller = ArisTaskCaller(task: runner.isBackgroundTask, handsFree: now.handsFree, tainted: now.taint != .none)
            let answer = ArisTaskTool.answer(call, caller: caller, desk: LiveDesk())
            // A status naming steps a task that read outside content wrote: this conversation is outside text from here.
            if answer.marksOutside { runner.mcpTakeOutsideText() }
            ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["action": "task \(words.first ?? "")", "answer": answer.status == 0 ? "done" : "refused"]), key: "local")
            reply("200 OK", ArisMCPRoutes.json(["status": Int(answer.status), "output": answer.output]))
        }
    }

    private struct LiveDesk: ArisTaskDesk {
        func states() -> [ArisTaskState] { ArisWorkInProgressLive.states(home: FileManager.default.homeDirectoryForCurrentUser.path) }

        func steer(job: String, note: String, brain: String) -> ArisTaskSteer.Outcome {
            ArisAgentRunner.steer(job: job, note: note)
        }

        func cancel(job: String) {
            ArisAgentRunner.cancel(job: job)
            ArisTeammateDesk.shared.cancel(job: job)
        }
    }
}
