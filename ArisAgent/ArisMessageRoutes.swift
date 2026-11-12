//
//  ArisMessageRoutes.swift
//  aris-agent
//
//  POST /message-tool {"turn", "to", "text"}: `aris-tools message` from inside the open Claude's turn (it has no gate of
//  its own), checked exactly as /mcp-tool is: the turn's credential, and the caller's process inside that brain's own
//  process tree. ArisMessageGate decides (the countdown for the user's dictated message, their card for anything else; the
//  sealed Claude only his card, and nothing after outside text) and, on their yes, the agent sends it. Only the two
//  Claudes call here: Codex and the API brain gate their own sends, and agy never sends one (its web search runs past
//  any gate, so it can't tell when outside text came in). Answers with what aris-tools prints: {"status", "output"}.
//

import Foundation
import Network

/// The runner's turn as the message gate sees it.
final class ArisRunnerMessageTurn: ArisMessageTurn {
    private let runner: ArisAgentRunner
    let request: String
    let attached: String
    let isTask: Bool
    let taint: ArisTaint
    let handsFree: Bool
    let critical: Bool
    let scopes: Set<ArisTeammateScope>?
    let sealed: Bool

    /// The turn this send belongs to: its card shows only while that turn is the runner's.
    let credential: String
    /// The route it came by, as actions.log names it.
    private let route: String

    init(runner: ArisAgentRunner, snapshot: ArisMessageSnapshot, credential: String, route: String = "message-tool") {
        self.runner = runner
        self.credential = credential
        self.route = route
        request = snapshot.request
        attached = snapshot.attached
        isTask = runner.isBackgroundTask
        taint = snapshot.taint
        handsFree = snapshot.handsFree
        critical = snapshot.critical
        scopes = snapshot.scopes
        sealed = snapshot.sealedClaude
    }

    func ask(_ card: ArisMCPCard, answer: @escaping (ArisMCPAnswer) -> Void) { runner.mcpAsk(card, credential: credential, answer: answer) }
    /// The automatic check for a conversation's handed-off write (ArisAutoHandOff); a job's is never checked.
    var auto: ArisAutoTurn? { isTask ? nil : ArisRunnerAutoTurn(runner: runner, request: request, turn: credential) }
    /// The same turn, still the same Claude, and no more outside text than when the card went up.
    func stillSendable() -> Bool {
        let now = runner.messageSnapshot()
        return now.active && (sealed ? now.sealedClaude : now.openClaude) && now.request == request && now.taint <= taint
    }
    func audit(_ fields: [String: String]) {
        let line = ArisAgentRunner.auditJSON(fields.merging(["question": route]) { $1 })
        // The turn's own record of why it asked or refused ("왜 안 돼?": ArisWhyDesk), for the conversation's turns only.
        if !isTask { ArisWhyDesk.shared.gated(line) }
        ArisAgentRunner.writeAudit(line, key: route == "message-tool" ? "message" : "action")
    }
    func auditLine(_ line: String) {
        if !isTask { ArisWhyDesk.shared.gated(line) }
        ArisAgentRunner.writeAudit(line, key: "action")
    }
}

/// A runner's turn as the check sees it, for a Claude's handed-off call (ArisAutoHandOff).
final class ArisRunnerAutoTurn: ArisAutoTurn {
    private let runner: ArisAgentRunner
    private let request: String
    private let turn: String
    /// The book of the turn this call arrived in.
    let book: ArisAutoBook

    /// `request`: the user's own words the turn was started with. `turn`: its credential (the tag shows only in that turn).
    init(runner: ArisAgentRunner, request: String, turn: String) {
        self.runner = runner
        self.request = request
        self.turn = turn
        book = runner.autoBook
    }

    var ownerTurns: [String]? { ArisOwnerWords.shared.said(endingWith: request) }
    var checker: ArisAutoChecking? { runner.autoChecker }
    func showChecking() { runner.autoChecking(turn: turn) }
    func passed(_ argv: [String], at: Date) { ArisAutoMarks.shared.passed(argv, at: at) }
}

/// What the message route reads of a runner's turn (ArisAgentRunner.messageSnapshot).
struct ArisMessageSnapshot {
    let active: Bool
    let request: String
    /// The question as it came, with the note of the files the user gave (the gate tells from it that one is being opened).
    let attached: String
    let taint: ArisTaint
    let handsFree: Bool
    let critical: Bool
    let scopes: Set<ArisTeammateScope>?
    let pid: Int32?
    /// The brain is the open Claude (its turn gate guards it).
    let openClaude: Bool
    /// The brain is the sealed Claude (a screen-seen or hands-free turn: its hook takes a lone message, and the gate
    /// shows only the user's plain card).
    let sealedClaude: Bool
}

enum ArisMessageRoutes {
    /// POST /action-tool {"turn", "words"}: a write, a send or something opened, from inside a Claude's turn (ArisHandOff:
    /// aris-tools never runs one there). Checked as /message-tool is (the turn's credential, the caller inside that
    /// brain's own process tree), judged by ArisActionGate as Codex's same command, asked on the user's card when that says
    /// to, and run by the agent itself. Answers with what aris-tools printed: {"status", "output"}.
    static func action(_ object: [String: Any], on connection: NWConnection, agentPort: UInt16, reply: @escaping (String, Data) -> Void) {
        let refuse = { (why: String) in
            ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["answer": "refused (\(why))", "question": "action-tool"]), key: "action")
            reply("403 Forbidden", ArisMCPRoutes.json(["status": 1, "output": "That works only inside an Aris turn."]))
        }
        guard let credential = object["turn"] as? String, let runner = ArisAgentRunner.runner(forMCPTurn: credential) else {
            return refuse("no turn credential")
        }
        guard let words = object["words"] as? [String], ArisHandOff.isWrite(words) else {
            return reply("400 Bad Request", ArisMCPRoutes.json(["status": 1, "output": ArisActionGate.refusal]))
        }
        let remotePort = ArisTeammateDesk.remotePort(of: connection)
        DispatchQueue.global(qos: .userInitiated).async {
            // Only the brain with no gate of its own: any other's writes go through its own gate.
            guard runner.brain == .claude else { return refuse("\(runner.brain.title) gates its own actions") }
            let now = runner.messageSnapshot()
            guard now.active else { return refuse("no turn under way") }
            // The open Claude, or the sealed one of a turn that saw the screen; never a hands-free one (the owner, 2026-11-08).
            guard now.openClaude || (now.sealedClaude && !now.handsFree) else { return refuse("only a Claude's own turn hands off here") }
            guard let pid = now.pid, let remotePort, ArisMCPCaller.isInside(root: pid, remotePort: remotePort, agentPort: agentPort) else {
                return refuse("not from the brain's own process")
            }
            let turn = ArisRunnerMessageTurn(runner: runner, snapshot: now, credential: credential, route: "action-tool")
            let outcome = ArisActionGate.answer(words, turn: turn, tools: ArisAgentRunner.toolsPath, home: NSHomeDirectory(), limit: limit(task: turn.isTask),
                                                notes: ArisHandOffLedger.shared.notes(for: runner, turn: credential)) { words in
                // As Aris itself: never the brain's environment (its turn-gate folder would hand it back here).
                let limit = ArisActionGate.runLimit(words)
                // What it does is logged as this conversation's, done by this brain (the 한 일 tab), and a schedule it makes
                // asks for this brain first.
                let own = ArisAgentRunner.environment(job: turn.isTask ? "Aris" : "대화", worker: runner.brain.title, foreground: !turn.isTask,
                                                      task: turn.isTask, brain: runner.brain)
                var environment = ArisAgyRelay.environment(own, timeout: limit, task: turn.isTask)
                environment[ArisTurnGate.stateKey] = nil
                environment[ArisHandOff.sealedKey] = nil
                let printed = ArisAgyRelay.runStatus(words, tools: ArisAgentRunner.toolsPath, environment: environment, timeout: limit)
                // Its answer may carry others' words (an event's title, what an undo put back, an error naming a list):
                // the thread holds outside text from now on, noted before anything comes back.
                if ArisActionGate.bringsInOutside(words, status: printed.status) { runner.mcpTakeOutsideText() }
                return ArisActionGate.reported(words, status: printed.status, output: printed.output)
            }
            reply("200 OK", ArisMCPRoutes.json(["status": Int(outcome.status), "output": outcome.output]))
        }
    }

    /// How long the card may wait: a job's as long as its other cards, a conversation's as long as the card itself
    /// stays up (the one card clock, and a little: a card answered in its last seconds still counts. It was 75 s
    /// against a card that showed for 120, so a yes after the 75th second did nothing).
    static func limit(task: Bool) -> TimeInterval { task ? ArisAgentRunner.mcpTaskWait + 5 : ArisCardEdit.questionTimeout + 5 }

    static func tool(_ object: [String: Any], on connection: NWConnection, agentPort: UInt16, reply: @escaping (String, Data) -> Void) {
        let refuse = { (why: String) in
            ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["answer": "refused (\(why))", "question": "message-tool"]), key: "message")
            reply("403 Forbidden", ArisMCPRoutes.json(["status": 1, "output": "aris-tools message works only inside an Aris turn."]))
        }
        guard let credential = object["turn"] as? String, let runner = ArisAgentRunner.runner(forMCPTurn: credential) else {
            return refuse("no turn credential")
        }
        guard let to = object["to"] as? String, let text = object["text"] as? String,
              to.count <= ArisMessageGate.maxTo, text.count <= ArisMessageGate.maxText else {
            return reply("400 Bad Request", ArisMCPRoutes.json(["status": 1, "output": "usage: message <name|number|email> <text>"]))
        }
        let remotePort = ArisTeammateDesk.remotePort(of: connection)
        DispatchQueue.global(qos: .userInitiated).async {
            // Only the brain with no gate of its own: any other's send goes through its own gate.
            guard runner.brain == .claude else { return refuse("\(runner.brain.title) gates its own messages") }
            let now = runner.messageSnapshot()
            guard now.active else { return refuse("no turn under way") }
            guard now.openClaude || now.sealedClaude else { return refuse("only a Claude sends through here") }
            guard let pid = now.pid, let remotePort, ArisMCPCaller.isInside(root: pid, remotePort: remotePort, agentPort: agentPort) else {
                return refuse("not from the brain's own process")
            }
            let turn = ArisRunnerMessageTurn(runner: runner, snapshot: now, credential: credential)
            let outcome = ArisMessageGate.answer(to: to, text: text, turn: turn, tools: ArisAgentRunner.toolsPath, home: NSHomeDirectory(),
                                                 limit: limit(task: turn.isTask)) { words in
                // As Aris itself: never the brain's environment (its turn-gate folder would route it back here).
                var environment = ArisAgyRelay.environment(ArisAgentRunner.environment(job: ArisSendJob.job(task: turn.isTask), worker: runner.brain.title), timeout: ArisMessageGate.sendLimit)
                environment[ArisTurnGate.stateKey] = nil
                let printed = ArisAgyRelay.run(words, tools: ArisAgentRunner.toolsPath, environment: environment, timeout: ArisMessageGate.sendLimit)
                return ArisMessageGate.reported(to: to, output: printed)
            }
            reply("200 OK", ArisMCPRoutes.json(["status": Int(outcome.status), "output": outcome.output]))
        }
    }
}
