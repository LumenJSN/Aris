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
    /// Every call of one turn makes its own object: the lock knows the turn by its credential (released in finish).
    var desktopOwner: String { ArisDesktopRoutes.owner(credential: credential) }
    /// The turn's desktop actions, for its saved steps (only this turn's: a late call of an ended turn isn't noted).
    func noteDesktopAction(_ note: Result<ArisSavedStep, ArisSavedStepsRefusal>) { if live { runner.savedSteps.note(note) } }
}

extension ArisRelayMCPTurn: ArisFileRelayTurn {}

extension ArisRelayMCPTurn: ArisDesktopTurn {
    var brain: ArisBrain { .antigravity }
    var ledger: ArisComputerUseLedger { ArisDesktopRoutes.relayLedger }
    func taint(forApp app: String) -> ArisTaint { taint }
    func markAppRead(_ app: String) { takeOutsideText() }
    func desktopStep() -> Int { ArisDesktopRoutes.relaySteps.next() }
    /// agy's relayed actions go to its turn's own recorder (every round of the turn), for its saved steps.
    func noteDesktopAction(_ note: Result<ArisSavedStep, ArisSavedStepsRefusal>) { if live { ArisDesktopRoutes.relayRecorder.note(note) } }
}

enum ArisDesktopRoutes {
    /// The desktop lock's owner id for a runner's turn.
    static func owner(credential: String) -> String { "mcp:" + credential }

    /// agy's conversation's ledger (its relay turns come and go; its snapshots and the user's yeses stay for the conversation).
    static let relayLedger = ArisComputerUseLedger(forget: { ArisPeekabooSnapshots.remove($0, record: ArisPeekabooSnapshots.recordFile) })
    /// agy's relayed desktop calls in its current turn (counted again from the turn's first relay round).
    /// A new relayed turn is a new turn for its ledger too (main.swift resets the count at the turn's first relay
    /// round): what the last turn selected, did or was refused no longer counts (audit desk-5: one select-all blocked
    /// typing in that window until the agent restarted).
    static let relaySteps = ArisDesktopStepCount(onReset: { relayLedger.startTurn(); relayRecorder.start() })
    /// agy's relayed desktop actions in its current turn, each the step it could be saved as (and a line of the block
    /// that wasn't a desktop call, as a step that can't be): saved at the turn's last round (main.swift's ask).
    static let relayRecorder = ArisSavedStepsRecorder()

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
            if action { turn.ledger.noteActionStarted() }
            // While an action's card of this turn waits for the user, the waiting line says so (no retry, no new look).
            ArisSlowCalls.shared.run(owner: credential, kind: "desktop", waitingOnOwner: { turn.ledger.anyCardWaits }, work: { done in
                engine.handle(words, text: text, turn: turn) { outcome in
                    if action { turn.ledger.noteActionEnded(ok: outcome.status == 0) }
                    if outcome.status != 0 { ArisDesktopRoutes.noteNotDone(outcome, words: words, turn: turn) }
                    done(outcome)
                }
            }, reply: send)
        }
    }
}

extension ArisDesktopRoutes {
    /// POST /desktop-hold {"turn"}: `aris-tools window …` from inside a brain's turn takes that turn's turn at the keys
    /// and pointer before it moves a window (ArisDesktopLock), checked exactly as /desktop-tool is (the turn's credential,
    /// no Antigravity turn, the caller inside the brain's own process tree). The turn keeps it as after any desktop
    /// action. {"held": id}: the agent's own replay or arrangement says it holds them already (ArisDesktopLock
    /// .holdsForOwnWork). {"status", "output"}.
    static func hold(_ object: [String: Any], on connection: NWConnection, agentPort: UInt16, lock: ArisDesktopLock = .shared,
                     reply: @escaping (String, Data) -> Void) {
        let refuse = { (why: String) in
            ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["answer": "refused (\(why))", "question": "desktop-hold"]), key: "desktop")
            reply("403 Forbidden", ArisMCPRoutes.json(["status": 1, "output": "aris-tools window works only inside an Aris turn."]))
        }
        // The agent's own one-off work (a learned shortcut's replay, a window arrangement) that holds the whole Mac now.
        if let held = object["held"] as? String {
            guard held.count <= 80, lock.holdsForOwnWork(held) else { return refuse("not the agent's own held work") }
            return reply("200 OK", ArisMCPRoutes.json(["status": 0, "output": "held"]))
        }
        guard let credential = object["turn"] as? String, let runner = ArisAgentRunner.runner(forMCPTurn: credential) else { return refuse("no turn credential") }
        let remotePort = ArisTeammateDesk.remotePort(of: connection)
        DispatchQueue.global(qos: .userInitiated).async {
            let now = runner.mcpSnapshot()
            guard now.active else { return refuse("no turn under way") }
            // As /desktop-tool: Antigravity's desktop goes through its relay, never this route.
            guard runner.brain != .antigravity else { return refuse("Antigravity uses the relay") }
            guard let pid = now.pid, let remotePort, ArisMCPCaller.isInside(root: pid, remotePort: remotePort, agentPort: agentPort) else {
                return refuse("not from the brain's own process")
            }
            let turn = ArisRunnerMCPTurn(runner: runner, handsFree: now.handsFree, screen: now.screen, credential: credential)
            let english = ArisDesktopCopy.isEnglish(turn.request)
            let started = Date()
            switch lock.acquire(ArisDesktopLock.Owner(id: turn.desktopOwner, live: { turn.live }), waiting: { turn.quiet(ArisDesktopLockWords.waitingLine(english: english)) }) {
            case .acquired:
                lock.done(turn.desktopOwner)
                reply("200 OK", ArisMCPRoutes.json(["status": 0, "output": "held"]))
            case .refused(let why):
                reply("200 OK", ArisMCPRoutes.json(["status": 1, "output": ArisDesktopLockWords.refusal(why, waited: Date().timeIntervalSince(started))]))
            }
        }
    }

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
