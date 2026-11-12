//
//  ArisActionGate.swift
//  aris-agent
//
//  A write, a send or something opened by a brain with no gate of its own (the open and the sealed Claude: aris-tools
//  hands the call here, POST /action-tool; Antigravity: a line of its aris-run block), decided by the agent exactly as
//  Codex's and the API brain's same command is (the owner: no feature locked to one brain; audit gate-2, gate-3, gate-1,
//  gate-16). The decision is ArisAPIGate.judge itself, given what the turn is (the user's words, how far outside content
//  came in, a job, hands-free, the tier), so there is one policy: a clean turn's to-do, reminder or event goes at once,
//  the Trash, keys or a new schedule ask on his card, a write after outside text asks, and a protected place, a chained
//  command or a forged undo is refused. Stricter than Codex in three ways, since nothing here can be approved for him:
//  no remembered yes, no standing permission and no judge in their place (a card is always the user's own answer). On an
//  automatic verdict or their yes the agent runs it (aris-tools as Aris itself), never the brain.
//  Pure apart from `run`, so the tests run it with a fake turn.
//

import Foundation

enum ArisActionGate {
    enum Decision: Equatable {
        /// Run it now.
        case run
        /// The user's card, as Codex shows it for this command.
        case ask(title: String, detail: String)
        /// Don't; why, for the brain.
        case refused(String)
    }

    static let refusal = "Refused by Aris's safety rules; don't try another way."
    static let declined = "The user said no (their choice, not a refusal by the system), so it wasn't done. Don't try another way now; say plainly, in their terms, that you won't (\"알겠어요, 안 할게요.\" / \"OK, I won't.\"). A later request in a new turn gets a new card."
    static let unanswered = "The user didn't answer the card in time, so it wasn't done. Say that it is still waiting for their yes and that they can ask again; don't try another way."
    static let changed = "Not done: the conversation changed after the user's yes. Don't try it another way."
    static let hidden = "Refused: the words carry hidden or direction-changing characters."
    /// The owner's decision (2026-11-08): nothing is sent, deleted or changed for them on words anyone near the Mac could have said.
    static let handsFree = "Refused: this request was heard hands-free (anyone near the Mac could have said it), so nothing is sent, deleted or changed from it. Answer exactly \"\(ArisHandsFree.askAgainLine)\" and do nothing else."

    /// The command line the gate reads and the card shows: every word quoted so it reads back as exactly these words.
    static func commandLine(_ words: [String], tools: String) -> String { ArisAPICatalog.command(tools: tools, argv: words) }

    /// The gate's answer for these words on this turn, and its line for actions.log.
    /// `declined`: the user already said no to a card of this turn (nothing else that asks runs after it, as on Codex).
    /// `alwaysAsks`: Antigravity's relay (ArisActionRelay): Aris can't tell what agy's own web search brought into its
    /// thread, so nothing of it runs on the gate's word alone: what the gate would let run asks on the user's card too.
    static func decide(_ words: [String], turn: ArisMessageTurn, tools: String, home: String, declined: Bool = false,
                       alwaysAsks: Bool = false) -> (decision: Decision, audit: String) {
        let line = commandLine(words, tools: tools)
        let action = ArisAction.shell(line)
        let refused = { (why: String, risk: String) in (Decision.refused(why), ArisAuditWriter.auditJSON(["action": String(line.prefix(400)), "risk": risk])) }
        guard ArisHandOff.isWrite(words) else { return refused(refusal, "never (not a handed-off call)") }
        // A card must read as what runs.
        if ArisAPIDriver.hidesText(words) { return refused(hidden, "never (hidden characters)") }
        if let scopes = turn.scopes, !ArisTeammateScope.permits(action, scopes: scopes, tools: tools) {
            return refused(ArisTeammateScope.refusalLine(ArisTeammateScope.needed(forTools: words).map { $0.subtracting(scopes) }), "never (outside the teammate's scopes)")
        }
        if turn.handsFree, ArisHandsFree.asks(action, tools: tools) { return refused(handsFree, "never (hands-free)") }
        // Codex's and the API brain's own gate, set to this turn: one policy for every brain.
        let gate = ArisAPIGate(tools: tools, home: home, task: turn.isTask)
        // Its words for the gates are the user's own; the files note rides along only so that opening a file they gave is
        // told apart (his card, as on Codex: QA BUG-35).
        gate.request = turn.attached
        gate.handsFree = turn.handsFree
        gate.tier = turn.critical ? .critical : .quick
        switch turn.taint {
        case .outsideText: gate.markUntrusted()
        case .screenSeen: gate.markScreenSeen()
        case .none: break
        }
        if declined { gate.answered("", allow: false) }
        switch gate.judge(line) {
        case .allow(let audit):
            guard alwaysAsks else { return (.run, audit) }
            let (title, detail) = ArisCodexDriver.describe(command: line, tools: tools, request: turn.request)
            return (.ask(title: title, detail: detail), audit)
        case .deny(let audit, let reason): return (.refused(reason), audit)
        // A handed-off call is never one of the judged reads; if the gate ever says so, nothing runs.
        case .read(_, _, let audit): return (.refused(refusal), audit)
        case .ask(let ask, _, _, let audit): return (.ask(title: ask.title, detail: ask.detail), audit)
        }
    }

    /// Decides, asks the user when the gate says to and, on an automatic verdict or their yes, runs it (`run`: aris-tools as
    /// Aris): what the brain's aris-tools prints. Blocks until the user answers (or `limit` passes: not done).
    /// `notes`: what this turn's hand-offs did so far (a card shown, his no), kept by the caller for the turn.
    static func answer(_ words: [String], turn: ArisMessageTurn, tools: String, home: String, limit: TimeInterval, notes: ArisHandOffNotes,
                       alwaysAsks: Bool = false, run: ([String]) -> ArisMCPOutcome) -> ArisMCPOutcome {
        let decided = decide(words, turn: turn, tools: tools, home: home, declined: notes.declined, alwaysAsks: alwaysAsks)
        turn.auditLine(decided.audit)
        let what = words.prefix(2).joined(separator: " ")
        // When the automatic check let the call run (its "확인함" mark is given only once the call worked).
        var passedAt: Date?
        gate: switch decided.decision {
        case .refused(let why): return .failed(why)
        case .run: break
        case .ask(let title, let detail):
            var card = ArisMCPCard(title: title, detail: detail, full: nil, fields: [])
            // Auto mode: a card that is there only because outside text was read goes to the automatic check first
            // (ArisAutoHandOff). A match runs the call with no card; a stop is answered on the stopped card.
            switch ArisAutoHandOff.settle(words, card: card, turn: turn, tools: tools, home: home, limit: limit, notes: notes, alwaysAsks: alwaysAsks) {
            case .run(let at):
                // As after a yes: the turn must still be under way, with no more outside text than when it was checked.
                guard turn.stillSendable() else {
                    turn.audit(["answer": "not done (the turn ended or read outside text during the check)", "action": what])
                    return .failed(changed)
                }
                passedAt = at
                break gate
            case .notDone(let outcome): return outcome
            case .card(let shown): card = shown
            }
            notes.showedCard()
            let done = DispatchSemaphore(value: 0)
            let said = ArisHandOffAnswer()
            turn.ask(card) { answer in
                said.set(answer)
                done.signal()
            }
            guard done.wait(timeout: .now() + limit) == .success, let answer = said.value else {
                turn.audit(["answer": "unanswered", "action": what])
                return .failed(unanswered)
            }
            switch answer {
            case .yes: break
            case .no:
                // Only his own no closes the rest of the turn's cards; a card that ran out isn't one.
                notes.userSaidNo()
                turn.audit(["answer": "no", "action": what])
                return .failed(declined)
            case .unanswered:
                turn.audit(["answer": "unanswered", "action": what])
                return .failed(unanswered)
            }
            guard turn.stillSendable() else {
                turn.audit(["answer": "not done (the turn ended or read outside text after the yes)", "action": what])
                return .failed(changed)
            }
            turn.audit(["answer": "yes", "action": what])
        }
        notes.ran()
        // Exactly these words, once: a calendar or to-do write may reach the app's route (ArisActionGrant), marked as
        // outside text when the automatic check let it through.
        if passedAt != nil { ArisActionGrants.shared.passedByCheck(argv: words) }
        ArisActionGrants.shared.mint(argv: words)
        // And a restart, shut down, log out or sleep its one pass (ArisMessagePass.powerName).
        ArisMessagePass.mint(argv: words)
        let outcome = run(words)
        if let passedAt, outcome.status == 0 { turn.auto?.passed(words, at: passedAt) }
        return outcome
    }

    /// What a Claude reads back once the agent ran its call. One that worked and is answered in fixed words
    /// (ArisHandOff.answersInFixedWords) gets only `done`, never what aris-tools printed, so nothing anyone else wrote
    /// comes into the conversation with it; any other call, and every failure, comes back as aris-tools said it (the
    /// caller marks the conversation as outside text first).
    static func reported(_ words: [String], status: Int32, output: String) -> ArisMCPOutcome {
        status == 0 && ArisHandOff.answersInFixedWords(words) ? ArisMCPOutcome(status: 0, output: done) : ArisMCPOutcome(status: status, output: output)
    }

    static let done = "done"

    /// Whether the conversation holds outside text once this call came back: any failure (its error may name a
    /// calendar, a list, a file), and any success that isn't fixed words or a file tool's own names.
    static func bringsInOutside(_ words: [String], status: Int32) -> Bool { status != 0 || !ArisHandOff.bringsNothingIn(words) }

    /// How long aris-tools may take once the gate let a call run: a conversion its own time, a shortcut or an undo (which
    /// may wait on macOS's folder prompt) a minute, anything else twenty seconds.
    static func runLimit(_ words: [String]) -> TimeInterval {
        if ArisConvertWords.parse(words) != nil { return ArisFileRelay.runLimit(words) }
        return ["shortcut", "undo", "note", "event", "type", "keys"].contains(words.first ?? "") ? 60 : 20
    }
}

/// Antigravity's writes (audit gate-16: it could add no event, reminder, to-do or note, and remove no schedule): a line
/// of its aris-run block, put to the same gate as every other brain's and always asked on the user's card, on agy's /ask
/// stream, then run by Aris itself. The open agy's own shell still refuses them (ArisAgyRules): it has no gate.
/// Messages stay refused on Antigravity (the owner, 2026-11-08): `message` is none of these forms.
enum ArisActionRelay {
    /// One relayed write's time limit, its card included.
    static let limit: TimeInterval = 90

    /// The line run for agy: refused, or asked and run, or not done; what agy reads back.
    static func relayed(_ words: [String], turn: ArisFileRelayTurn, request: String, critical: Bool, tools: String, home: String, notes: ArisHandOffNotes,
                        run: ([String]) -> String) -> String {
        guard ArisHandOff.isWrite(words) else { return ArisAgyRelay.refused }
        turn.startCall(limit: limit)
        let outcome = ArisActionGate.answer(words, turn: ArisRelayActionTurn(relay: turn, request: request, critical: critical), tools: tools, home: home,
                                            limit: limit, notes: notes, alwaysAsks: true) { ArisMCPOutcome(status: 0, output: run($0)) }
        // A card nobody answered in time is taken down with the call.
        if outcome.status != 0 { turn.cancelAll() }
        return outcome.output
    }
}

/// agy's relayed turn as the action gate sees it.
final class ArisRelayActionTurn: ArisMessageTurn {
    private let relay: ArisFileRelayTurn
    let request: String
    let critical: Bool
    let isTask = false
    let scopes: Set<ArisTeammateScope>? = nil

    init(relay: ArisFileRelayTurn, request: String, critical: Bool) {
        self.relay = relay
        self.request = request
        self.critical = critical
    }

    /// Always as after outside text: agy's own web search runs past every gate, so its thread may hold anything.
    var taint: ArisTaint { .outsideText }
    var handsFree: Bool { relay.handsFree }
    func ask(_ card: ArisMCPCard, answer: @escaping (ArisMCPAnswer) -> Void) { relay.ask(card, answer: answer) }
    func audit(_ fields: [String: String]) { relay.audit(fields.merging(["question": "agy relay"]) { $1 }) }
    func auditLine(_ line: String) {
        guard let fields = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: String] else { return }
        relay.audit(fields.merging(["question": "agy relay"]) { $1 })
    }
    /// The relayed call is still waited for (its stream open, its time not run out).
    func stillSendable() -> Bool { relay.live }
}

/// What a turn's handed-off calls did so far, for the rules that count across them: a card shown (the turn then
/// teaches memory nothing: the user's answer to a card is never saved by learning), their own no (nothing else that asks
/// runs after it this turn), and whether anything ran (a turn that acted is never asked again on another brain).
final class ArisHandOffNotes: @unchecked Sendable {
    private let lock = NSLock()
    private var card = false, no = false, acted = false

    func showedCard() { lock.withLock { card = true } }
    func userSaidNo() { lock.withLock { no = true } }
    func ran() { lock.withLock { acted = true } }

    var showed: Bool { lock.withLock { card } }
    var declined: Bool { lock.withLock { no } }
    var didRun: Bool { lock.withLock { acted } }
}

/// Each runner's notes for its turn now (ArisHandOffNotes). A conversation turn starts new ones (startTurn); a call
/// that names another turn than the notes were made for (a job's runner, which never says it started) gets new ones
/// too, and so does a runner that only sits where an ended one was.
final class ArisHandOffLedger: @unchecked Sendable {
    static let shared = ArisHandOffLedger()

    private struct Entry {
        weak var runner: AnyObject?
        var turn: String?
        let notes: ArisHandOffNotes
    }

    private let lock = NSLock()
    private var entries: [ObjectIdentifier: Entry] = [:]

    /// A turn starts on `runner`: nothing of its last one counts. `underWay`: the credential of the turn the runner is
    /// answering right now ("" for none): a question that only meets "still answering the last one" starts nothing,
    /// so that turn's notes (the user's no to its card) stay.
    func startTurn(_ runner: AnyObject, underWay: String = "") {
        lock.withLock {
            entries = entries.filter { $0.value.runner != nil }
            if !underWay.isEmpty, let found = entries[ObjectIdentifier(runner)], found.runner === runner, found.turn == underWay { return }
            entries[ObjectIdentifier(runner)] = Entry(runner: runner, turn: nil, notes: ArisHandOffNotes())
        }
    }

    /// The notes of `runner`'s turn `turn` (its credential): the ones started for it, else new ones.
    func notes(for runner: AnyObject, turn: String) -> ArisHandOffNotes {
        lock.withLock {
            let key = ObjectIdentifier(runner)
            if var found = entries[key], found.runner === runner, found.turn == nil || found.turn == turn {
                found.turn = turn
                entries[key] = found
                return found.notes
            }
            let made = Entry(runner: runner, turn: turn, notes: ArisHandOffNotes())
            entries[key] = made
            return made.notes
        }
    }

    /// What `runner`'s turn now has noted so far; nil when it handed nothing off.
    func current(_ runner: AnyObject) -> ArisHandOffNotes? {
        lock.withLock {
            guard let found = entries[ObjectIdentifier(runner)], found.runner === runner else { return nil }
            return found.notes
        }
    }
}

/// The user's answer to a card, handed across threads.
final class ArisHandOffAnswer: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: ArisMCPAnswer?
    func set(_ answer: ArisMCPAnswer) { lock.withLock { stored = answer } }
    var value: ArisMCPAnswer? { lock.withLock { stored } }
}
