//
//  ArisRoutineRun.swift
//  aris-agent
//
//  One run of a routine. The agent asks its steps one at a time, each as a turn of its own through everything a turn
//  goes through (the gate, the cards, the taint), and this keeps the account: which step is running, what each one
//  answered, and where it stopped. A step that fails, is answered no on its card, is left unanswered, or would hand
//  work to a teammate stops the routine; the steps after it are never started, and the answer says so.
//  While it runs, each step's own answer is held back and its status lines carry the count ("메일 보는 중 · 2/3",
//  ArisRoutineProgress); the one answer at the end opens with whether it ran through or where it stopped, then every
//  step's own answer. A step may be answered by the app instead of an AI (ArisRoutineHandBack): to the run it ends the
//  same way, with an answer or a failure. Pure.
//

import Foundation

struct ArisRoutineRun: Equatable {
    /// The user's answer to a card, as POST /confirm heard it.
    enum CardAnswer: Equatable { case yes, no, unanswered }

    /// How a step ended; the text is the step's own answer (or why it failed).
    enum Outcome: Equatable {
        case done(String)
        case failed(String)
        case declined(String)
        case unanswered(String)
        case handedOut
    }

    /// What to do with a line a step's turn produced.
    enum Effect: Equatable {
        /// Send it to the app (a status with the count, a card, a mark).
        case pass(ArisAgentReply)
        /// Keep it from the app (the step's own answer as it streams).
        case drop
        /// The step is over: say this status, then ask the next step.
        case next(step: String, status: ArisAgentReply)
        /// The routine is over: this is its answer.
        case finish(ArisAgentReply)
    }

    let routine: ArisRoutine
    let korean: Bool
    private(set) var outcomes: [Outcome] = []
    /// The cards the running step has put up (never "앞으로 이건 그냥 할까?").
    private(set) var cards: [String] = []
    private var handed = false

    init(routine: ArisRoutine, korean: Bool) {
        self.routine = routine
        self.korean = korean
    }

    /// The step running now, from 0.
    var index: Int { outcomes.count }
    var step: String { routine.steps[min(index, routine.steps.count - 1)] }

    /// What the notch shows as a step starts: its count and its own words.
    var startStatus: ArisAgentReply {
        .status(ArisRoutineProgress.line(step: index + 1, total: routine.steps.count, text: String(step.prefix(ArisRoutineAccount.statusWords))))
    }

    /// The run after `reply`, and what to do with it. `answers`: the user's answers to cards so far, by card id.
    /// `handsOut`: whether an answer hands work to a teammate (a jobs block).
    func taking(_ reply: ArisAgentReply, answers: [String: CardAnswer], handsOut: (String) -> Bool = { _ in false }) -> (run: ArisRoutineRun, effect: Effect) {
        var next = self
        switch reply {
        case .status(let text):
            return (self, .pass(.status(ArisRoutineProgress.line(step: index + 1, total: routine.steps.count, text: text))))
        case .delta:
            return (self, .drop)
        case .turn, .refusedJobs:
            // The step's answer hands work out: a routine doesn't, and the app must not act on these marks.
            next.handed = true
            return (next, .drop)
        case .confirm(let ask):
            if !ask.proposal { next.cards.append(ask.id) }
            return (next, .pass(reply))
        case .untrusted, .shownOnly, .operating, .skill, .file, .launched, .stepFailed, .helperAnswers:
            return (self, .pass(reply))
        case .failure(let why):
            return next.ended(.failed(why))
        case .answer(let text):
            let mine = cards.map { answers[$0] }
            if handed || handsOut(text) { return next.ended(.handedOut) }
            if mine.contains(.no) { return next.ended(.declined(text)) }
            // A card with no yes on record (left to run out, or its turn ended first) was not approved.
            if mine.contains(where: { $0 != .yes }) { return next.ended(.unanswered(text)) }
            return next.ended(.done(text))
        }
    }

    private func ended(_ outcome: Outcome) -> (run: ArisRoutineRun, effect: Effect) {
        var next = self
        next.outcomes.append(outcome)
        next.cards = []
        next.handed = false
        if case .done = outcome, next.outcomes.count < routine.steps.count {
            return (next, .next(step: next.step, status: next.startStatus))
        }
        return (next, .finish(ArisRoutineAccount.reply(routine, outcomes: next.outcomes, korean: korean)))
    }
}

/// The one answer of a routine's run: true about what was and was not done.
enum ArisRoutineAccount {
    /// How much of a step's own words its starting status shows.
    static let statusWords = 40

    /// The run's last line for the app: its account, whatever stopped it and wherever (VM run 2026-11-11, bug 2: a
    /// first step that failed came back bare, with no word that a routine had stopped). An answer, except when the
    /// very first step failed: nothing was done then, so the turn is a failure (asking again is safe, and its
    /// button says so), still with the account.
    static func reply(_ routine: ArisRoutine, outcomes: [ArisRoutineRun.Outcome], korean: Bool) -> ArisAgentReply {
        let account = text(routine, outcomes: outcomes, korean: korean)
        if outcomes.count == 1, case .failed = outcomes[0] { return .failure(account) }
        return .answer(account)
    }

    /// The run ended on a step that did not finish (it failed, was answered no, was left unanswered, or is a
    /// teammate's): that step's tag gets no tick.
    static func stoppedShort(_ outcomes: [ArisRoutineRun.Outcome]) -> Bool {
        if case .done? = outcomes.last { return false }
        return !outcomes.isEmpty
    }

    /// The failure line the run stopped on, when it stopped on one: the button that line earns stays with the account.
    static func failureLine(_ outcomes: [ArisRoutineRun.Outcome]) -> String? {
        if case .failed(let why)? = outcomes.last { return why }
        return nil
    }

    /// A step's failure as the account may tell it. "<one AI> isn't installed" is true of the AI that was asked, but
    /// on a Mac where no AI can answer at all the account says that instead (the app does the same for a turn's own
    /// failure line, which a line inside an account no longer is). Any other line is passed on as it came.
    static func truer(_ reply: ArisAgentReply, anyAI: () -> Bool) -> ArisAgentReply {
        guard case .failure(let line) = reply, let trouble = ArisBrainTrouble.named(in: line), trouble.brain != nil, !anyAI() else { return reply }
        return .failure(ArisBrainTrouble(brain: nil, missing: .any).line(korean: line == trouble.line(korean: true)))
    }

    static func text(_ routine: ArisRoutine, outcomes: [ArisRoutineRun.Outcome], korean: Bool) -> String {
        var parts = [head(routine, outcomes: outcomes, korean: korean)]
        for (index, outcome) in outcomes.enumerated() {
            parts.append("### \(index + 1). \(routine.steps[index])\n" + body(outcome, korean: korean))
        }
        let left = Array(routine.steps.enumerated()).dropFirst(outcomes.count)
        if !left.isEmpty {
            parts.append((korean ? "### 하지 않은 단계\n" : "### Not run\n") + left.map { "- \($0.offset + 1). \($0.element)" }.joined(separator: "\n"))
        }
        return parts.joined(separator: "\n\n")
    }

    /// The first line: ran through, or where it stopped and why. A stop that was the user's own no opens with 알겠어요 (OK),
    /// as his no does anywhere else.
    static func head(_ routine: ArisRoutine, outcomes: [ArisRoutineRun.Outcome], korean: Bool) -> String {
        let name = ArisRoutineCopy.label(routine.name, korean: korean), total = routine.steps.count, at = outcomes.count
        guard let last = outcomes.last else { return "" }
        switch last {
        case .done:
            return korean ? "\(name) \(total)단계를 끝까지 실행했어요." : "Ran \(name) through, all \(total) step\(total == 1 ? "" : "s")."
        case .failed(let why):
            return korean ? "\(name)은 \(at)단계에서 멈췄어요: \(why)" : "\(name.capitalizedStart) stopped at step \(at): \(why)"
        case .declined:
            return korean ? "알겠어요, \(name)은 \(at)단계에서 멈췄어요." : "OK, \(name) stopped at step \(at)."
        case .unanswered:
            return korean ? "\(name)은 \(at)단계에서 멈췄어요. 카드를 기다리다가 그 단계부터는 하지 않았어요."
                          : "\(name.capitalizedStart) stopped at step \(at). I waited on its card and went no further."
        case .handedOut:
            return korean ? "\(name)은 \(at)단계에서 멈췄어요. 그 단계는 팀원에게 맡기는 일이에요." : "\(name.capitalizedStart) stopped at step \(at), which is work for a teammate."
        }
    }

    private static func body(_ outcome: ArisRoutineRun.Outcome, korean: Bool) -> String {
        switch outcome {
        case .done(let text): return plain(text, else: korean ? "(답이 비어 있었어요.)" : "(It answered nothing.)")
        // Why is in the account's first line.
        case .failed: return korean ? "하지 못했어요." : "Not done."
        case .declined(let text), .unanswered(let text): return plain(text, else: korean ? "하지 않았어요." : "Not done.")
        case .handedOut: return ArisRoutineCopy.handedOut(korean: korean)
        }
    }

    /// A step's answer as it reads inside the account: a "<say>…</say>" line gives way to the full answer after it, or
    /// is kept as plain words when it is all there is.
    static func plain(_ answer: String, else empty: String = "") -> String {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let found = ArisRoutineIntent.groups(#"^<say>(.*?)</say>\s*(.*)$"#, in: trimmed) else { return trimmed.isEmpty ? empty : trimmed }
        let rest = (found[1] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let said = (found[0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? (said.isEmpty ? empty : said) : rest
    }
}

private extension String {
    var capitalizedStart: String { prefix(1).uppercased() + dropFirst() }
}

/// The user's answers to cards, by card id, as POST /confirm hears them: a routine reads them to tell whether the card a
/// step put up got their yes. Only ever used to stop a routine early; it approves nothing.
final class ArisRoutineCards: @unchecked Sendable {
    static let shared = ArisRoutineCards()
    static let kept = 300

    private let lock = NSLock()
    private var answers: [String: ArisRoutineRun.CardAnswer] = [:]
    private var order: [String] = []

    func answered(_ id: String, allow: Bool, unanswered: Bool) {
        lock.withLock {
            if answers[id] == nil { order.append(id) }
            answers[id] = allow ? .yes : unanswered ? .unanswered : .no
            while order.count > Self.kept { answers[order.removeFirst()] = nil }
        }
    }

    func answers(for ids: [String]) -> [String: ArisRoutineRun.CardAnswer] {
        lock.withLock { ids.reduce(into: [:]) { $0[$1] = answers[$1] } }
    }
}

/// A routine run by a schedule ("매일 9시에 출근 루틴 해 줘"): the scheduler asks each step as a scheduled run of its
/// own, one after another, and the routine's account is the job's result. Touched on the scheduler's queue only.
final class ArisRoutineChain {
    enum Move: Equatable {
        /// Not the end of a step: the scheduler handles the line as it does any (a card is parked for the user).
        case pass
        case next(String)
        case end(ArisAgentReply)
    }

    private var run: ArisRoutineRun
    private let cards: ArisRoutineCards

    init(routine: ArisRoutine, korean: Bool, cards: ArisRoutineCards = .shared) {
        run = ArisRoutineRun(routine: routine, korean: korean)
        self.cards = cards
    }

    var first: String { run.step }

    func take(_ reply: ArisAgentReply) -> Move {
        let taken = run.taking(reply, answers: cards.answers(for: run.cards))
        run = taken.run
        switch taken.effect {
        case .pass, .drop: return .pass
        case .next(let step, _): return .next(step)
        case .finish(let last): return .end(last)
        }
    }

    /// The routine a scheduled job's prompt runs ("출근 루틴 해 줘"), if it is one of the user's.
    static func routine(forPrompt prompt: String, in routines: [ArisRoutine]) -> ArisRoutine? {
        ArisRoutineIntent.scheduled(prompt, routines: routines)
    }
}

/// "방금 한 걸 루틴으로 저장해 줘": the user's last requests. The app's context carries its last few turns ("- user: …"), but
/// a reply in it could hold a line that only looks like one, so a line counts only when the agent itself heard those
/// words from him a little while ago, or when it is one of the small acts the app does on its own (opening an app, the
/// music, the volume, a timer), which never reach the agent.
struct ArisRoutineRecent: Equatable {
    static let window: TimeInterval = 30 * 60
    static let kept = 12

    private(set) var heard: [Heard] = []

    struct Heard: Equatable {
        let key: String
        let at: Date
    }

    /// With `words` noted as heard from the user at `at`.
    func noting(_ words: String, at: Date) -> ArisRoutineRecent {
        let key = Self.key(words)
        guard !key.isEmpty else { return self }
        var next = self
        next.heard = Array((heard.filter { at.timeIntervalSince($0.at) <= Self.window } + [Heard(key: key, at: at)]).suffix(Self.kept))
        return next
    }

    /// The steps a routine made now would hold: his requests in the context's last turns, oldest first.
    func steps(context: String?, now: Date) -> [String] {
        let known = Set(heard.filter { now.timeIntervalSince($0.at) <= Self.window }.map(\.key))
        var steps: [String] = []
        for words in Self.requests(in: context) {
            guard known.contains(Self.key(words)) || Self.isLocalAct(words), !ArisRoutineWords.mentions(words),
                  let step = ArisRoutineRules.step(words), !step.isEmpty, step.count <= ArisRoutineRules.stepLimit, steps.last != step else { continue }
            steps.append(step)
        }
        return steps
    }

    /// What the user said in the context's "recent:" turns.
    static func requests(in context: String?) -> [String] {
        let lines = (context ?? "").components(separatedBy: "\n")
        guard let start = lines.firstIndex(of: "recent:") else { return [] }
        return lines[(start + 1)...].filter { $0.hasPrefix("- user: ") }.map { String($0.dropFirst("- user: ".count)).trimmingCharacters(in: .whitespaces) }
    }

    private static let localActs = [
        #"^[^\s/~$`|&;<>]{1,20}(?:\s[^\s/~$`|&;<>]{1,12})?\s*(?:좀\s*)?(?:열어|켜|실행해|띄워)\s*(?:줘|주세요)?$"#,
        #"^(?:노래|음악|곡)\s*(?:좀\s*)?(?:틀어|재생해|꺼|멈춰|정지해|넘겨)\s*(?:줘|주세요)?$"#,
        #"^(?:다음|이전)\s*(?:곡|노래)(?:\s*(?:틀어|으로|로))?\s*(?:줘|주세요)?$"#,
        #"^(?:볼륨|소리|음량|밝기|화면\s*밝기)\s*[\d가-힣%\s]{0,12}$"#,
        #"^\d{1,3}\s*분\s*(?:타이머|집중)[가-힣\s]{0,8}$"#, #"^(?:타이머|뽀모도로)\s*[\d가-힣\s]{0,12}$"#,
        #"^(?:open|launch)\s+[a-z0-9 .]{1,24}$"#,
        #"^(?:play|pause|resume|stop|skip)\s+(?:the\s+|some\s+)?(?:music|song|track)s?$"#, #"^next\s+(?:song|track)$"#,
        #"^(?:volume|brightness)\s+[a-z0-9% ]{1,12}$"#, #"^(?:mute|unmute)$"#, #"^(?:set\s+)?(?:a\s+)?\d{1,3}[\s-]*min(?:ute)?s?\s+timer$"#,
    ]

    /// One of the small acts the app does itself without the agent: all such a line could ever ask for.
    static func isLocalAct(_ words: String) -> Bool {
        let line = words.precomposedStringWithCanonicalMapping.lowercased().trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".!~")))
        guard line.count <= 40 else { return false }
        return localActs.contains { line.range(of: $0, options: .regularExpression) != nil }
    }

    static func key(_ words: String) -> String {
        String(String.UnicodeScalarView(words.precomposedStringWithCanonicalMapping.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }))
    }
}
