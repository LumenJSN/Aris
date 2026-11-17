//
//  ArisSessionRoutes.swift
//  aris-agent
//
//  POST /session-tool {"turn", "words"}: `aris-tools session list|send …` from inside a brain's turn (Codex, the open
//  and the sealed Claude, the API brain's helper), checked exactly as /aside-tool is: the turn's credential, and the
//  caller's process inside that brain's own process tree. agy's relay runs `session …` lines here directly (relayed).
//  ArisSessionSend answers with what aris-tools prints: {"status", "output"}.
//

import Foundation
import Network

enum ArisSessionRoutes {
    static func tool(_ object: [String: Any], on connection: NWConnection, agentPort: UInt16, deps: ArisSessionDeps = ArisSessionLive.deps,
                     reply: @escaping (String, Data) -> Void) {
        let refuse = { (why: String) in
            ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["answer": "refused (\(why))", "question": "session-tool"]), key: "session")
            reply("403 Forbidden", ArisMCPRoutes.json(["status": 1, "output": "aris-tools session works only inside an Aris turn."]))
        }
        guard let credential = object["turn"] as? String, let runner = ArisAgentRunner.runner(forMCPTurn: credential) else {
            return refuse("no turn credential")
        }
        guard let words = object["words"] as? [String], ArisSessionCall.isCall(words) else {
            return reply("400 Bad Request", ArisMCPRoutes.json(["status": 1, "output": ArisSessionSend.usage]))
        }
        let remotePort = ArisTeammateDesk.remotePort(of: connection)
        DispatchQueue.global(qos: .userInitiated).async {
            let now = runner.mcpSnapshot()
            guard now.active else { return refuse("no turn under way") }
            guard runner.brain != .antigravity else { return refuse("Antigravity uses the relay") }
            guard let pid = now.pid, let remotePort, ArisMCPCaller.isInside(root: pid, remotePort: remotePort, agentPort: agentPort) else {
                return refuse("not from the brain's own process")
            }
            let turn = ArisRunnerMCPTurn(runner: runner, handsFree: now.handsFree, screen: now.screen, credential: credential)
            let outcome = ArisSessionSend.answer(words, turn: turn, deps: deps)
            reply("200 OK", ArisMCPRoutes.json(["status": Int(outcome.status), "output": outcome.output]))
        }
    }

    /// One `session …` line of agy's aris-run block: the same send, card and checks.
    static func relayed(_ words: [String], turn: ArisDesktopTurn, deps: ArisSessionDeps = ArisSessionLive.deps) -> String {
        let rest = Array(words.dropFirst())
        guard ArisSessionCall.isCall(rest) else { return ArisSessionSend.usage }
        return String(ArisSessionSend.answer(rest, turn: turn, deps: deps).output.prefix(ArisAgyRelay.maxResult))
    }
}
