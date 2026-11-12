// Tests for auto mode inside the integration tree (2026-11-12): where the automatic check meets what the tree gained
// meanwhile. The stopped card obeys the read-to-the-end rule (ArisCardRead) like any card's yes, and a type card's
// "In:" line stays first on it; the job-claim check (ArisJobClaim) and auto mode never disagree about a background
// job's acts (a job is never checked, so every act of it is on a card or in its record, and no 확인함 mark lands on a
// job's row); the hands-free rules win over auto mode (no check, no owner's words, never asked again by Aris itself, a
// press re-asks as heard); the rollout audit is untouched. The checker is always a recorded one: no model is asked,
// no card is shown, nothing of the user's is read or changed.
// Called from main.swift; uses its check().
import CoreGraphics
import Foundation

private let aiTools = "/Users/p/.config/aris/aris-tools"
private let aiHome = "/Users/p"
private let aiSaid = "그거 할 일에 추가해 줘"
private let aiInScope: [[String]] = [
    ["todo", "add", "면옥 을지 예약하기"], ["todo", "done", "우유 사기"], ["event", "치과", "--start", "2026-11-12 10:00"],
    ["schedule", "remove", "아침 브리핑"], ["convert", "/Users/p/Desktop/영수증.heic", "--to", "pdf"],
]

func runAutomodeIntTests() {
    autoIntReadToEndTests()
    autoIntTypeCardTests()
    autoIntJobClaimTests()
    autoIntHandsFreeTests()
    autoIntRolloutTests()
}

// MARK: - Fakes

/// A checker that answers what the test recorded for it and counts what it was shown.
private final class IntChecker: ArisAutoChecking, @unchecked Sendable {
    let model = "recorded-quick"
    let budget: TimeInterval = 1
    let reply: ArisAutoRun
    private let lock = NSLock()
    private var seen = 0
    var asked: Int { lock.withLock { seen } }

    init(_ reply: ArisAutoRun) { self.reply = reply }

    func check(input: String, done: @escaping (ArisAutoRun) -> Void) {
        lock.withLock { seen += 1 }
        done(reply)
    }
}

/// A turn as the check sees it.
private final class IntAutoTurn: ArisAutoTurn, @unchecked Sendable {
    let ownerTurns: [String]?
    let book = ArisAutoBook()
    let checker: ArisAutoChecking?
    private(set) var marked: [[String]] = []

    init(owner: [String]?, checker: ArisAutoChecking?) {
        ownerTurns = owner
        self.checker = checker
    }

    func showChecking() {}
    func passed(_ argv: [String], at: Date) { marked.append(argv) }
}

/// A Claude's turn as the action gate sees it; the user's answers are taken in order.
private final class IntGateTurn: ArisMessageTurn {
    var request = aiSaid
    var isTask = false
    var taint = ArisTaint.outsideText
    var handsFree = false
    var critical = false
    var scopes: Set<ArisTeammateScope>? = nil
    var answers: [ArisMCPAnswer] = []
    var auto: ArisAutoTurn?
    private(set) var cards: [ArisMCPCard] = []

    func stillSendable() -> Bool { true }
    func ask(_ card: ArisMCPCard, answer: @escaping (ArisMCPAnswer) -> Void) {
        cards.append(card)
        if !answers.isEmpty { answer(answers.removeFirst()) }
    }
    func audit(_ fields: [String: String]) {}
}

private let aiMatch = ArisAutoRun.answered(#"{"verdict":"match"}"#)

private func aiLine(_ words: [String]) -> String { ArisAPICatalog.command(tools: aiTools, argv: words) }

private func aiEligible(_ words: [String], task: Bool = false, handsFree: Bool = false) -> [String]? {
    let action = ArisAction.shell(aiLine(words))
    return ArisAutoScope.eligible(action, tools: aiTools, home: aiHome, request: aiSaid, critical: false, blocked: ArisTaint.outsideText.blocks(covered: false),
                                  hardLine: ArisRiskPolicy.hardLine(of: action, tools: aiTools) != nil, task: task, handsFree: handsFree, countdown: false)
}

/// The two Claudes' path: the gate's card for `words`, the check, and the user's answers. What ran, and the checker.
private func aiHandOff(_ words: [String], turn: IntGateTurn, reply: ArisAutoRun = aiMatch) -> (ran: [[String]], checker: IntChecker, auto: IntAutoTurn) {
    let checker = IntChecker(reply)
    let auto = IntAutoTurn(owner: [aiSaid], checker: checker)
    turn.auto = auto
    var ran: [[String]] = []
    _ = ArisActionGate.answer(words, turn: turn, tools: aiTools, home: aiHome, limit: 1, notes: ArisHandOffNotes()) {
        ran.append($0)
        return ArisMCPOutcome(status: 0, output: "done")
    }
    return (ran, checker, auto)
}

private let aiRepo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("..")
private func aiSource(_ path: String) -> String { (try? String(contentsOf: aiRepo.appendingPathComponent(path), encoding: .utf8)) ?? "" }

// MARK: - The stopped card and the read-to-the-end rule

private func autoIntReadToEndTests() {
    let today = ArisConfirmation(id: "c1", title: "할 일에 넣기", detail: ArisEscalation.taintedReason + "\n면옥 을지 예약하기")
    let stopped = ArisAutoCard.stopped(for: today, id: "s1", why: .notAsked, english: false)
    // 그래도 하기 by a click or the Y key is a pressed yes: it waits for the card's end, as on any card. Its ↩ and esc are a no.
    check(!stopped.countdown && ArisCardRead.applies(allow: true, source: .click, countdown: stopped.countdown)
          && ArisCardRead.applies(allow: true, source: .key, countdown: stopped.countdown),
          "automode int: 그래도 하기 pressed or by Y on the stopped card is a yes the read-to-the-end rule applies to")
    check(!ArisCardRead.applies(allow: false, source: .key, countdown: stopped.countdown) && !ArisCardRead.applies(allow: false, source: .click, countdown: false),
          "automode int: 하지 않기 (↩, esc, N or the button) never waits for the card to be read")
    // A stopped card taller than its room: no pressed yes until its end has been on screen; one that fits: at once.
    var read = ArisCardRead().shown(stopped.id)
    check(!read.yesCounts(card: stopped.id), "automode int: a stopped card nothing is known of yet takes no pressed yes")
    read = read.scrolled(card: stopped.id, offset: 0, visible: 300, content: 620)
    check(!read.yesCounts(card: stopped.id), "automode int: a long stopped card whose end is below its room takes no pressed yes")
    read = read.scrolled(card: stopped.id, offset: 320, visible: 300, content: 620)
    check(read.yesCounts(card: stopped.id), "automode int: once its end has been on screen, 그래도 하기 counts")
    let fits = ArisCardRead().shown(stopped.id).scrolled(card: stopped.id, offset: 0, visible: 180, content: 180)
    check(fits.yesCounts(card: stopped.id) && !fits.yesCounts(card: today.id), "automode int: a stopped card that fits its room counts at once, and only for itself")
    // 그래도 하기 then brings up today's card under its own id: that card starts unread again.
    let next = read.following(today.id)
    check(!next.yesCounts(card: today.id), "automode int: today's card after 그래도 하기 must be read to its end on its own")
    // The stopped card reports its scroller to the reader, and its 그래도 하기 is disabled and at rest until read.
    let card = aiSource("Aris/private/Aris/Home/ArisStoppedCard.swift")
    check(card.contains("onScroll: { ArisCardReadLive.shared.scrolled(card: question.id, offset: $0, visible: $1, content: $2) }")
          && card.contains(".disabled(!read)") && card.contains("private var read: Bool { reader.readCard == question.id }")
          && card.contains(".opacity(read && still.ready == question.id ? 1 : ArisConfirmCard.restOpacity)")
          && card.contains("ArisCardRead.hint(english: english)"),
          "automode int: the stopped card tells the reader how far it has been seen, and 그래도 하기 waits at rest until its end")
    // The controller's rule has no exception for the stopped card.
    let controller = aiSource("Aris/private/Aris/ArisController.swift")
    let answer = controller.components(separatedBy: "func answerQuestion(_ allow: Bool").last?.components(separatedBy: "typedAnswer = allow").first ?? ""
    check(answer.contains("ArisCardRead.applies(allow: allow, source: source, countdown: question.countdown), !ArisCardReadLive.shared.yesCounts(card: question.id)")
          && !answer.contains("stopped"), "automode int: a pressed yes on any card, the stopped one included, counts only once the card was read to its end")
    let keys = aiSource("Aris/private/Claude/KeyboardFocus.swift")
    check(keys.contains("if ArisController.shared.session.question?.stopped == true, [KeyCode.escape, KeyCode.enter].contains(event.keyCode) {\n                ArisController.shared.answerQuestion(false, source: .key)"),
          "automode int: ↩ on the stopped card is its 하지 않기 (a no), never a yes that skips the reading")
}

// MARK: - A type card's "In:" first

private func autoIntTypeCardTests() {
    for english in [true, false] {
        let into = english ? "In: Terminal" : "입력할 곳: Terminal"
        for text in ["echo hi", String(repeating: "rm -rf ~ ", count: 400) + "\nline\nline\nline\nline\nline\nline"] {
            guard let typed = ArisCardWords.typing([text, "--app", "Terminal"], english: english) else {
                check(false, "automode int: the type card has words")
                continue
            }
            let ask = ArisConfirmation(id: "c2", title: english ? "Typing" : "입력하기", detail: ArisEscalation.taintedReason + "\n" + typed)
            let stopped = ArisAutoCard.stopped(for: ask, id: "s2", why: .notAsked, english: english)
            let quoted = ArisStoppedCopy.quoted(of: stopped).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            check(quoted.first == into && quoted.count == 2 && !quoted[1].contains("In:") && ArisStoppedCopy.action(of: stopped) == ask.title,
                  "automode int: a stopped type card (\(english ? "English" : "Korean"), \(text.count) characters) shows where the keys go first, before the text, so the six-line cut never hides it")
        }
    }
    // And no type call ever reaches the check: typing always asks on today's type card.
    check(aiEligible(["type", "echo hi", "--app", "Terminal"]) == nil && aiEligible(["type", "hello"]) == nil, "automode int: typed text is never a call the automatic check may let run")
    let turn = IntGateTurn()
    turn.answers = [.no]
    let done = aiHandOff(["type", "echo hi", "--app", "Terminal"], turn: turn)
    check(done.ran.isEmpty && done.checker.asked == 0 && !turn.cards.contains { $0.stopped },
          "automode int: a Claude's typing after outside text is today's (a card or a refusal), never the check")
}

// MARK: - The job-claim check and auto mode

private func autoIntJobClaimTests() {
    // A background job is never checked: every in-scope act of a job asks on today's card.
    for words in aiInScope {
        check(aiEligible(words) != nil && aiEligible(words, task: true) == nil, "automode int: `\(words.joined(separator: " "))` may be checked in a conversation, never in a job")
    }
    let job = IntGateTurn()
    job.isTask = true
    job.answers = [.no]
    let todo = ["todo", "add", "면옥 을지 예약하기"]
    let done = aiHandOff(todo, turn: job)
    check(done.ran.isEmpty && done.checker.asked == 0 && job.cards.count == 1 && !job.cards[0].stopped && done.auto.marked.isEmpty,
          "automode int: a job's to-do after outside text gets today's card, with no check and no mark, even when a check is on offer")
    // So the job's record holds that card's answer, and the claim check reads it as the job doing something.
    var cards = ArisJobClaim.Cards()
    cards.note(.shell(aiLine(todo)), allowed: false)
    let record = ArisJobClaim.Record(acted: false, commands: [], otherTools: false, showedCard: true, cards: cards)
    check(cards.refused == [aiLine(todo)] && !record.isEmpty
          && ArisJobClaim.unbacked("I've added the to-do.", request: "add a to-do to book the restaurant", record: record, schedulesUnchanged: true, tools: aiTools, korean: false) == nil,
          "automode int: a job's card is in its record, so the claim check never calls such a job one that did nothing")
    // A send, which a job's claim check reads, is never checked at all: today's message and mail cards.
    for words in [["message", "엄마", "곧 갈게"], ["mail", "send", "mom@example.com", "hi", "hello"]] {
        check(aiEligible(words) == nil && aiEligible(words, task: true) == nil, "automode int: `\(words[0])` always asks: the check never lets a send run")
    }
    // No 확인함 mark lands on a job's row, even one of the same kind logged just after a conversation's pass.
    let at = Date(timeIntervalSince1970: 1_800_000_000)
    let stamp = ISO8601DateFormatter().string(from: at.addingTimeInterval(1))
    let jobRow: [String: Any] = ["id": "JOB", "date": stamp, "job": "주간 보고", "worker": "Claude", "summary": "s", "undone": false, "undo": ["removeTodo": ["id": "x"]]]
    let claimed = ArisAutoMarks.claim([ArisAutoMarks.Pass(at: at, undo: "removeTodo")], rows: [jobRow], taken: [], now: at.addingTimeInterval(5))
    check(claimed.ids.isEmpty && claimed.left.count == 1, "automode int: a conversation's pass never marks a background job's row")
    // The runner: the job's claim reads its own record and card answers; the check's hook is a conversation's only.
    let runner = aiSource("ArisAgent/ArisAgentRunner.swift")
    check(runner.contains("if isTask, let line = ArisJobClaim.unbacked(") && runner.contains("cardAnswers.note(asked, allowed: allow && call == id)")
          && runner.contains("task: isTask, handsFree: handsFreeTurn") && runner.contains("if !isTask, let held = autoStops.removeValue(forKey: id) {")
          && runner.contains("if !isTask { ArisAutoMarks.shared.turnBegan() }") && runner.contains("if !isTask { ArisAutoMarks.shared.dropWaiting() }"),
          "automode int: the runner checks only a conversation's calls, and a job's claim still reads every card it showed")
}

// MARK: - The hands-free rules win

private func autoIntHandsFreeTests() {
    for words in aiInScope {
        check(aiEligible(words, handsFree: true) == nil, "automode int: `\(words.joined(separator: " "))` heard hands-free is never checked")
    }
    let heard = IntGateTurn()
    heard.handsFree = true
    heard.answers = [.no]
    let done = aiHandOff(["todo", "add", "면옥 을지 예약하기"], turn: heard)
    check(done.ran.isEmpty && done.checker.asked == 0 && !heard.cards.contains { $0.stopped },
          "automode int: a hands-free turn's write after outside text is today's (a card or a refusal), never a check that could let it run")
    // A hands-free turn is nobody's words for the check.
    let words = ArisOwnerWords()
    words.turn(aiSaid, fresh: true, his: false)
    check(words.said(endingWith: aiSaid) == nil, "automode int: words heard hands-free are never the owner's words the check reads")
    words.turn(aiSaid, fresh: false, his: true)
    check(words.said(endingWith: aiSaid) == [aiSaid], "automode int: his own keyed or typed turn is")
    // Aris never asks a hands-free turn again by itself: not after the helper comes back, not after the fix shows.
    let zero = Date(timeIntervalSince1970: 1_800_000_000)
    let question = "add a to-do to book the restaurant"
    let lostLine = ArisAgentCopy.notRunning(english: true)
    let asking = ArisFixMoment(phase: .thinking, heard: question), failed = ArisFixMoment(phase: .failed, heard: question, reply: lostLine)
    for handsFree in [true, false] {
        var watch = ArisHelperWatch().moving(from: ArisFixMoment(), to: asking, now: zero, handsFree: handsFree)
        watch = watch.moving(from: asking, to: failed, now: zero.addingTimeInterval(1), handsFree: handsFree)
        let step = watch.looked(answering: true, moment: failed, now: zero.addingTimeInterval(2)).1
        check(step == (handsFree ? .back : .askAgain(question)),
              handsFree ? "automode int: a hands-free turn lost to the helper is left to them when it comes back" : "automode int: a keyed turn lost to the helper is asked again once, as before")
    }
    check(ArisFixReturn.watches(.pane(.reminders), request: question, handsFree: true) == nil && ArisFixReturn.watches(.pane(.reminders), request: question, handsFree: false) != nil,
          "automode int: a hands-free turn is not watched to be asked again when the fix shows")
    // His press asks the words as they were heard: a hands-free turn stays hands-free (its limits and sealed route hold).
    let typed = aiSource("Aris/private/Aris/ArisController+Typed.swift"), fix = aiSource("Aris/private/Aris/ArisFixModel.swift")
    let press = fix.components(separatedBy: "private func askAgain(_ request: String) {").last?.components(separatedBy: "private func open(").first ?? ""
    check(typed.contains("turnHandsFree = again && turnHandsFree") && press.contains("ArisController.shared.submitTyped(request, again: true)")
          && fix.contains("guard let check = ArisFixReturn.watches(fix, request: request, handsFree: ArisController.shared.turnHandsFree) else { return }"),
          "automode int: his press on 다시 해보기 re-asks a hands-free turn as heard, never as his typed words")
    // The agent: a hands-free turn is no owner's turn, and the Claudes' hand-off never takes a hands-free turn.
    let main = aiSource("ArisAgent/main.swift"), routes = aiSource("ArisAgent/ArisMessageRoutes.swift")
    check(main.contains("his: peerFailure == nil && !handsFree") && routes.contains("guard now.openClaude || (now.sealedClaude && !now.handsFree) else { return refuse(\"only a Claude's own turn hands off here\") }"),
          "automode int: the helper never counts a hands-free turn as his, and a hands-free Claude's write is not handed off here")
}

// MARK: - The rollout audit is untouched

private func autoIntRolloutTests() {
    let files = ["ArisAutoCheck.swift", "ArisAutoCheckLive.swift", "ArisAutoHandOff.swift", "ArisAutoMarks.swift", "ArisAutoMode.swift", "ArisAutoScope.swift", "ArisOwnerWords.swift"]
    let auto = files.map { aiSource("ArisAgent/" + $0) }
    check(auto.allSatisfy { !$0.isEmpty } && !auto.contains { $0.contains("ArisRollout") || $0.lowercased().contains("rollout") },
          "automode int: nothing of auto mode reads or changes the rollout rule or its audit")
    // The checker's process is started where every process of the helper is (written down for the vouch, the AI's
    // program as approved): a program that waits for the owner's yes is not started, and the action stops.
    let live = aiSource("ArisAgent/ArisAutoCheckLive.swift")
    check(live.contains("do { try ArisChildren.run(process) } catch {") && !live.contains("try process.run()"),
          "automode int: the CLI checker is started through ArisChildren like the read judge, never on its own")
    let rollout = aiSource("Shared/ArisRollout.swift")
    check(rollout.contains("static let enforcing = false"), "automode int: every new refusal of the rollout is still log-only")
}
