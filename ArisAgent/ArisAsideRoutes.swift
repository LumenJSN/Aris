//
//  ArisAsideRoutes.swift
//  aris-agent
//
//  POST /aside-tool {"turn", "brief"}: `aris-tools aside "<brief>"` from inside a brain's turn (Codex, the open and the
//  sealed Claude, the API brain's helper, and an agy background job), checked exactly as /mcp-tool is: the turn's
//  credential, and the caller's process inside that brain's own process tree. agy's conversation never calls it (its
//  relay runs `aside …` lines here directly); its job does, as outside text with a card for every call.
//  ArisAsideTool answers with what aris-tools prints: {"status", "output"}.
//

import Foundation
import Network

extension ArisRunnerMCPTurn: ArisAsideTurn {
    /// The runner's credential: a new one every turn.
    var asideTurnKey: String { "runner-" + runner.mcpTurn }
    /// The turn is still under way (a cancelled job or a finished turn has no turn).
    var asideLive: Bool { runner.mcpSnapshot().active }
    func asideRunning(_ brief: String) { runner.asideRunning(ArisAside.runningStatus(brief, english: asideEnglish)) }
    func asideWaiting(_ status: String) { runner.asideRunning(status) }
    func asideEnded() { runner.asideEnded() }
    var asideOwnData: Bool { runner.ownScheduleNamedNow }
    /// The user's request for the turn is English (the same switch as computer use's cards: ArisDesktopCopy).
    var asideEnglish: Bool { ArisDesktopCopy.isEnglish(request) }
}

/// An agy job's turn (the owner, 2026-11-08): agy's own web search has no gate, so whatever the runner saw, the job counts
/// as outside text, and every Aside call it makes shows the user a card (the route passes it as critical). No install or
/// sign-in card either: those go up only on a clean turn.
final class ArisAgyJobAsideTurn: ArisAsideTurn {
    private let turn: ArisRunnerMCPTurn
    init(_ turn: ArisRunnerMCPTurn) { self.turn = turn }

    var brainName: String { turn.brainName }
    var taint: ArisTaint { .outsideText }
    var handsFree: Bool { turn.handsFree }
    var isTask: Bool { true }
    var screen: Bool { turn.screen }
    var relayed: Bool { false }
    var asideTurnKey: String { turn.asideTurnKey }
    var asideLive: Bool { turn.asideLive }
    var asideOwnData: Bool { turn.asideOwnData }
    var asideEnglish: Bool { turn.asideEnglish }
    func takeOutsideText() { turn.takeOutsideText() }
    func ask(_ card: ArisMCPCard, answer: @escaping (ArisMCPAnswer) -> Void) { turn.ask(card, answer: answer) }
    func judgeRead(_ call: ArisReadCall, done: @escaping (ArisReadVerdict) -> Void) { done(.blocked(.undecided)) }
    func quiet(_ status: String) { turn.quiet(status) }
    func audit(_ fields: [String: String]) { turn.audit(fields.merging(["note": "agy job"]) { $1 }) }
    func asideRunning(_ brief: String) { turn.asideRunning(brief) }
    func asideWaiting(_ status: String) { turn.asideWaiting(status) }
    func asideEnded() { turn.asideEnded() }
}

extension ArisRelayMCPTurn: ArisAsideTurn {
    var asideTurnKey: String { "relay-\(ObjectIdentifier(self).hashValue)" }
    var asideLive: Bool { live }
    func asideRunning(_ brief: String) { quiet(ArisAside.runningStatus(brief, english: asideEnglish)) }
    func asideWaiting(_ status: String) { quiet(status) }
    func asideEnded() {}
    var asideEnglish: Bool { ArisDesktopCopy.isEnglish(request) }
}

enum ArisAsideRoutes {
    /// The most of a brief the route reads (ArisAside.brief refuses past its own limit).
    static let maxBody = 16_384

    static func tool(_ object: [String: Any], on connection: NWConnection, agentPort: UInt16, deps: ArisAsideDeps = .live,
                     reply: @escaping (String, Data) -> Void) {
        let refuse = { (why: String) in
            ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["answer": "refused (\(why))", "question": "aside-tool"]), key: "aside")
            reply("403 Forbidden", ArisMCPRoutes.json(["status": 1, "output": "aris-tools aside works only inside an Aris turn."]))
        }
        guard let credential = object["turn"] as? String, let runner = ArisAgentRunner.runner(forMCPTurn: credential, aside: true) else {
            return refuse("no turn credential")
        }
        guard let brief = object["brief"] as? String, brief.utf8.count <= maxBody else {
            return reply("400 Bad Request", ArisMCPRoutes.json(["status": 1, "output": ArisAside.usage]))
        }
        let remotePort = ArisTeammateDesk.remotePort(of: connection)
        DispatchQueue.global(qos: .userInitiated).async {
            let now = runner.mcpSnapshot()
            guard now.active else { return refuse("no turn under way") }
            // agy's conversation goes through the relay; its background job may call here, every call on a card.
            let agyJob = runner.brain == .antigravity && runner.isBackgroundTask
            guard runner.brain != .antigravity || agyJob else { return refuse("Antigravity uses the relay") }
            guard let pid = now.pid, let remotePort, ArisMCPCaller.isInside(root: pid, remotePort: remotePort, agentPort: agentPort) else {
                return refuse("not from the brain's own process")
            }
            let turn = ArisRunnerMCPTurn(runner: runner, handsFree: now.handsFree, screen: now.screen, credential: credential)
            let outcome = agyJob ? ArisAsideTool.answer(brief, turn: ArisAgyJobAsideTurn(turn), critical: true, deps: deps)
                : ArisAsideTool.answer(brief, turn: turn, critical: runner.mcpCritical(), deps: deps)
            reply("200 OK", ArisMCPRoutes.json(["status": Int(outcome.status), "output": outcome.output]))
        }
    }
}
