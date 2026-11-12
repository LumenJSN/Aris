//
//  ArisDesktopRoutes.swift
//  aris-agent
//
//  POST /desktop-tool {"turn", "words": [...], "text"?}: `aris-tools desktop …` from inside a brain's turn (Codex, the
//  open and the sealed Claude, the API brain's helper), checked exactly as /mcp-tool is: the turn's credential, and the
//  caller's process inside that brain's own process tree. agy never calls it (its relay runs `desktop …` lines here
//  directly, ArisAgyRelay). The engine answers with what aris-tools prints: {"status", "output"}.
//

import Foundation
import Network

extension ArisRunnerMCPTurn: ArisDesktopTurn {
    var brain: ArisBrain { runner.brain }
    var ledger: ArisComputerUseLedger { runner.computerUse }
    func taint(forApp app: String) -> ArisTaint { runner.desktopTaint(forApp: app) }
    func markAppRead(_ app: String) { runner.desktopMarkRead(app) }
    func operating(_ target: ArisOperatingTarget) { runner.operating(target) }
    func desktopStep() -> Int { runner.desktopStep() }
    /// Only this call's own turn: a yes that comes in a later turn never acts.
    var live: Bool { runner.mcpSnapshot().active && ArisMCPTurnCredential.same(runner.mcpTurn, credential) }
    var request: String { runner.messageSnapshot().request }
    var critical: Bool { runner.messageSnapshot().critical }
}

extension ArisRelayMCPTurn: ArisFileRelayTurn {}

extension ArisRelayMCPTurn: ArisDesktopTurn {
    var brain: ArisBrain { .antigravity }
    var ledger: ArisComputerUseLedger { ArisDesktopRoutes.relayLedger }
    func taint(forApp app: String) -> ArisTaint { taint }
    func markAppRead(_ app: String) { takeOutsideText() }
    func desktopStep() -> Int { ArisDesktopRoutes.relaySteps.next() }
}

enum ArisDesktopRoutes {
    /// agy's conversation's ledger (its relay turns come and go; its snapshots and the user's yeses stay for the conversation).
    static let relayLedger = ArisComputerUseLedger(forget: { ArisPeekabooSnapshots.remove($0, record: ArisPeekabooSnapshots.recordFile) })
    /// agy's relayed desktop calls in its current turn (counted again from the turn's first relay round).
    /// A new relayed turn is a new turn for its ledger too (main.swift resets the count at the turn's first relay
    /// round): what the last turn selected, did or was refused no longer counts (audit desk-5: one select-all blocked
    /// typing in that window until the agent restarted).
    static let relaySteps = ArisDesktopStepCount(onReset: { relayLedger.startTurn() })

    /// How long one relayed desktop call may take, its card included.
    static let relayLimit: TimeInterval = ArisCardEdit.questionTimeout + 10

    /// One `desktop …` line of agy's aris-run block (the text, if any, is a quoted word Aris holds: never an argv).
    static func relayed(_ words: [String], turn: ArisRelayMCPTurn, engine: ArisDesktopEngine = .shared) -> String {
        let done = DispatchSemaphore(value: 0)
        let box = ArisMCPOutcomeBox()
        turn.startCall(limit: relayLimit)
        DispatchQueue.global(qos: .userInitiated).async {
            engine.handle(Array(words.dropFirst()), text: nil, positionalText: true, turn: turn) { outcome in
                if ArisDesktopHonesty.isAction(Array(words.dropFirst())) {
                    if outcome.status == 0 { turn.ledger.noteActed() } else { turn.ledger.noteNotDone() }
                }
                if outcome.status != 0 { ArisDesktopRoutes.noteNotDone(outcome, words: Array(words.dropFirst()), turn: turn) }
                box.set(outcome)
                done.signal()
            }
        }
        if done.wait(timeout: .now() + relayLimit) == .timedOut {
            turn.cancelAll()
            return "(it took too long, so Aris stopped it)"
        }
        return String((box.value?.output ?? "no answer").prefix(ArisAgyRelay.maxResult))
    }

    static func tool(_ object: [String: Any], on connection: NWConnection, agentPort: UInt16, engine: ArisDesktopEngine = .shared,
                     reply: @escaping (String, Data) -> Void) {
        let refuse = { (why: String) in
            ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["answer": "refused (\(why))", "question": "desktop-tool"]), key: "desktop")
            reply("403 Forbidden", ArisMCPRoutes.json(["status": 1, "output": "aris-tools desktop works only inside an Aris turn."]))
        }
        guard let credential = object["turn"] as? String, let runner = ArisAgentRunner.runner(forMCPTurn: credential) else {
            return refuse("no turn credential")
        }
        guard let words = object["words"] as? [String], words.count <= 24, words.allSatisfy({ $0.count <= 400 }) else {
            return reply("400 Bad Request", ArisMCPRoutes.json(["status": 1, "output": ArisDesktopWords.usage]))
        }
        let text = object["text"] as? String
        let remotePort = ArisTeammateDesk.remotePort(of: connection)
        DispatchQueue.global(qos: .userInitiated).async {
            let now = runner.mcpSnapshot()
            guard now.active else { return refuse("no turn under way") }
            guard runner.brain != .antigravity else { return refuse("Antigravity uses the relay") }
            guard let pid = now.pid, let remotePort, ArisMCPCaller.isInside(root: pid, remotePort: remotePort, agentPort: agentPort) else {
                return refuse("not from the brain's own process")
            }
            let turn = ArisRunnerMCPTurn(runner: runner, handsFree: now.handsFree, screen: now.screen, credential: credential)
            let send = { (outcome: ArisMCPOutcome) in reply("200 OK", ArisMCPRoutes.json(["status": Int(outcome.status), "output": outcome.output])) }
            // `desktop wait <id>`: a call that outlasted one shell command (ArisSlowCalls).
            if words.first == "wait" {
                guard words.count == 2, ArisSlowCalls.isID(words[1]) else { return send(.failed("usage: aris-tools desktop wait <id>")) }
                return ArisSlowCalls.shared.wait(id: words[1], owner: credential, kind: "desktop", reply: send)
            }
            // Until it is known, an action counts as not done: a reply can't claim it while its card is still up.
            let action = ArisDesktopHonesty.isAction(words)
            if action { turn.ledger.noteNotDone() }
            ArisSlowCalls.shared.run(owner: credential, kind: "desktop", work: { done in
                engine.handle(words, text: text, turn: turn) { outcome in
                    if action, outcome.status == 0 { turn.ledger.noteActed() }
                    if outcome.status != 0 { ArisDesktopRoutes.noteNotDone(outcome, words: words, turn: turn) }
                    done(outcome)
                }
            }, reply: send)
        }
    }
}

extension ArisDesktopRoutes {
    /// A desktop call that wasn't done: the engine's own reason, in the audit and in the turn's ledger (QA's next live
    /// run shows the exact check that stopped it).
    static func noteNotDone(_ outcome: ArisMCPOutcome, words: [String], turn: ArisDesktopTurn) {
        let why = ArisDesktopEngine.reason(outcome.output)
        let action = ArisDesktopHonesty.isAction(words)
        let usersNo = action && ArisDesktopEngine.isDecline(outcome.output)
        if usersNo { turn.ledger.noteDeclined() }
        turn.ledger.noteRefusal(why, usersNo: usersNo, action: action)
        turn.audit(["answer": "not done (\(why))", "action": "desktop \(words.prefix(2).joined(separator: " "))", "brain": turn.brainName])
    }
}
