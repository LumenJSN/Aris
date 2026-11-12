//
//  ArisAutoHandOff.swift
//  aris-agent
//
//  The automatic check on the path the two Claudes' writes take (ArisActionGate.answer: the agent judges the call,
//  asks and runs it), and the one way any path asks a checker and waits for it. The gate has already said "ask" by
//  the time this is reached; here a card that is there only because outside text was read (ArisAutoScope.eligible) is
//  put to the check first (ArisAutoMode): a match runs the call with no card; the checker's no shows the stopped card,
//  whose 하지 않기 declines the call as any no does and whose 그래도 하기 runs nothing: today's card for the call comes
//  next, and only the user's yes there lets it run. A check that decided nothing is today's card at once, with its line. A turn that offers no ArisAutoTurn (Antigravity's relay, a test's plain turn) is
//  never checked: its card is today's.
//  Pure: the tests run it with a fake turn and a recorded checker.
//

import Foundation

/// What a turn gives the automatic check.
protocol ArisAutoTurn: AnyObject {
    /// The user's own turns of this conversation when the turn now is their (ArisOwnerWords.said), else nil.
    var ownerTurns: [String]? { get }
    /// This turn's checks.
    var book: ArisAutoBook { get }
    /// Who checks; nil when no AI can be asked.
    var checker: ArisAutoChecking? { get }
    /// A check is taking longer than a moment: the notch's running tag.
    func showChecking()
    /// A match let this call run at `at`, and it worked: its row in the 한 일 log earns the "확인함" mark.
    func passed(_ argv: [String], at: Date)
}

/// One run's answer, set once (the checker's own, or "late" when its time ran out first).
final class ArisAutoRunBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: ArisAutoRun?

    var value: ArisAutoRun? { lock.withLock { stored } }

    /// True for the first answer only.
    func set(_ run: ArisAutoRun) -> Bool {
        lock.withLock {
            guard stored == nil else { return false }
            stored = run
            return true
        }
    }
}

enum ArisAutoAsk {
    /// Asks the checker once. `done` gets its answer, or `.late` when its budget ran out first, exactly once, on a
    /// background queue. `showTag` is called once if no answer came within ArisAutoMode.tagDelay.
    static func ask(_ checker: ArisAutoChecking, input: String, showTag: @escaping () -> Void, done: @escaping (ArisAutoRun) -> Void) {
        let box = ArisAutoRunBox()
        let finish = { (run: ArisAutoRun) in if box.set(run) { done(run) } }
        let queue = DispatchQueue.global(qos: .userInitiated)
        queue.asyncAfter(deadline: .now() + ArisAutoMode.tagDelay) { if box.value == nil { showTag() } }
        queue.asyncAfter(deadline: .now() + checker.budget) { finish(.late) }
        queue.async { checker.check(input: input, done: finish) }
    }

    /// The same, waiting (never on a runner's queue or the server's).
    static func wait(_ checker: ArisAutoChecking, input: String, showTag: @escaping () -> Void) -> ArisAutoRun {
        let answered = DispatchSemaphore(value: 0)
        let box = ArisAutoRunBox()
        ask(checker, input: input, showTag: showTag) { run in
            _ = box.set(run)
            answered.signal()
        }
        _ = answered.wait(timeout: .now() + checker.budget + 1)
        return box.value ?? .late
    }
}

enum ArisAutoHandOff {
    enum Settled: Equatable {
        /// Run the call now, with no card: the check passed it at this moment.
        case run(Date)
        /// It isn't done; what the brain reads.
        case notDone(ArisMCPOutcome)
        /// Show this card (today's, or today's with one more line) and go by the user's answer.
        case card(ArisMCPCard)
    }

    /// `card`: the gate's own card for `words`. `alwaysAsks`: Antigravity's relay, which is never checked.
    static func settle(_ words: [String], card: ArisMCPCard, turn: ArisMessageTurn, tools: String, home: String, limit: TimeInterval,
                       notes: ArisHandOffNotes, alwaysAsks: Bool) -> Settled {
        guard !alwaysAsks, let auto = turn.auto else { return .card(card) }
        let action = ArisAction.shell(ArisActionGate.commandLine(words, tools: tools))
        let covered = turn.taint == .screenSeen && !turn.handsFree && ArisRiskPolicy.coveredByRequest(action, tools: tools, arguments: [:], request: turn.request)
        // The call as the gate read it must be the very words that will run; anything else keeps today's card.
        guard let argv = ArisAutoScope.eligible(action, tools: tools, home: home, request: turn.request, critical: turn.critical,
                                                blocked: turn.taint.blocks(covered: covered), hardLine: ArisRiskPolicy.hardLine(of: action, tools: tools) != nil,
                                                task: turn.isTask, handsFree: turn.handsFree, countdown: card.countdown), argv == words else { return .card(card) }
        let english = ArisGateWords.isEnglish(turn.request)
        // The call as the checker can be shown it whole; nil (a kind it never checks, or anything that would be cut,
        // dropped or altered) keeps today's card.
        let subject = ArisAutoAction.read(words, title: card.title, detail: ArisAutoCard.plain(card.detail))
        let owner = auto.ownerTurns, checker = auto.checker
        let note = { (verdict: String, seconds: TimeInterval?) in
            guard let subject else { return }
            turn.audit(ArisAutoMode.ledger(subject, verdict: verdict, model: checker?.model ?? "", seconds: seconds))
        }
        let stop = { (why: ArisAutoStop) -> Settled in
            // Nothing decided (late, failed, odd, too few words): today's card at once, with the line why (review 9, L1).
            if let line = ArisAutoCard.todaysLine(why, english: english) { return .card(ArisMCPCard(title: card.title, detail: line + "\n" + card.detail, full: nil, fields: [])) }
            return stopped(why, card: card, turn: turn, limit: limit, notes: notes, english: english)
        }
        switch ArisAutoMode.before(argv: words, action: subject, ownerTurns: owner, available: checker != nil, book: auto.book, english: english) {
        case .asIs: return .card(card)
        case .ask(let reason): return .card(ArisMCPCard(title: card.title, detail: reason + "\n" + card.detail, full: nil, fields: []))
        case .stop(let why, let ledger):
            note(ledger, nil)
            return stop(why)
        case .check(let ticket):
            guard let checker, let subject, let owner else { return .card(card) }
            let began = Date()
            let input = ArisAutoCheck.input(ownerTurns: owner, action: subject, code: ArisAutoCheck.code())
            let run = ArisAutoAsk.wait(checker, input: input, showTag: { auto.showChecking() })
            // The words that will run are the ones checked (this function's own `words`): the ticket binds them anyway.
            let settled = ArisAutoMode.after(run, ticket: ticket, argvNow: words, book: auto.book)
            note(settled.ledger, Date().timeIntervalSince(began))
            switch settled.outcome {
            case .run: return .run(Date())
            case .stop(let why): return stop(why)
            }
        }
    }

    /// The stopped card, and the user's answer to it. 그래도 하기 gives back today's card to show next; nothing has run.
    private static func stopped(_ why: ArisAutoStop, card: ArisMCPCard, turn: ArisMessageTurn, limit: TimeInterval, notes: ArisHandOffNotes,
                                english: Bool) -> Settled {
        var shown = ArisMCPCard(title: ArisAutoCard.title(why, english: english),
                                detail: ArisAutoCard.detail(title: card.title, detail: card.detail, english: english), full: nil, fields: [])
        shown.stopped = true
        notes.showedCard()
        let done = DispatchSemaphore(value: 0)
        let said = ArisHandOffAnswer()
        turn.ask(shown) { answer in
            said.set(answer)
            done.signal()
        }
        guard done.wait(timeout: .now() + limit) == .success, let answer = said.value else {
            turn.audit(["answer": "stopped card: unanswered"])
            return .notDone(.failed(ArisActionGate.unanswered))
        }
        switch answer {
        case .yes:
            turn.audit(["answer": "stopped card: asked for the confirm card"])
            return .card(card)
        case .no:
            // His own no, as on any card: nothing else that asks runs after it this turn.
            notes.userSaidNo()
            turn.audit(["answer": "stopped card: no"])
            return .notDone(.failed(ArisActionGate.declined))
        case .unanswered:
            turn.audit(["answer": "stopped card: unanswered"])
            return .notDone(.failed(ArisActionGate.unanswered))
        }
    }
}
