//
//  ArisMindJudge.swift
//  aris-agent
//
//  The one decision for every Core 2 call (ARCHITECTURE Part 2, Judgment), bound to jv-trust's gate (ArisTrustGate):
//  the owner's words of each turn go in once (a sentence that makes or takes back a standing grant changes the
//  settings there), each call is decided with its key arguments and provenance, the calls that wait for the owner go
//  on one card per intent (the turn, or the task) in the confirm line's format, his answer lets them run or not, and
//  every call ends as one line of the record with its result and its undo, while what it read feeds the provenance
//  tracker. A call whose route is proven to ask the owner on its own card every time (ArisMindBook.alwaysCarded) gets that one
//  card, never a second in front of it; every other call gets the gate's card; what the gate refuses stays refused. Used by the Mind's own loop (ArisMindSession)
//  and by the MCP face's calls through POST /mind-call (ArisMindRoute).
//

import Foundation

final class ArisMindJudge: @unchecked Sendable {
    /// Shows one card and calls back with the owner's answer: true yes, false no, nil none in time.
    typealias Card = (_ card: ArisConfirmation, _ answer: @escaping (Bool?) -> Void) -> Void

    struct Held {
        let session: String
        let task: String?
        let name: String
        let outcome: ArisTrustGate.Outcome
        /// The capability and its aris-tools words, for the pass a yes on the gate's card mints (ArisMindPasses).
        var capability = ""
        var argv: [String]?
        var stdin: String?
        /// The pass for the route this call reaches, once the owner said yes to it on the gate's card.
        var pass: String?
        /// How much content the gate had taken in for the conversation when this call was decided (ArisTrustGate.contentRead).
        var seen = 0
        /// What it returns may hold others' words (outside content): until it reports, no judgedRun pass of the
        /// conversation is fresh (judgedRunFresh).
        var bringsContent = true
        /// A file capability's path as it was decided, links followed (ArisCore2.decidedPath): its run must land there.
        var resolved: String?
        /// The turn it was decided in, its arguments as decided, whether it may run now (decided to run, or their yes on
        /// its card), and whether its run was already handed out (`takeDecided`).
        var intent: String?
        var arguments: [String: Any] = [:]
        var runs = false
        var taken = false
        /// The owner said yes to it on a card (an undo's run then takes exactly what that card named).
        var approved = false
    }

    let gate: ArisTrustGate
    let tools: String
    /// The passes a yes on the gate's card hands down to a call's own route (one card per call, never two).
    let passes: ArisMindPasses
    /// How long a card may wait for the owner (a conversation's card, and a little).
    var cardWait: TimeInterval = ArisCardEdit.questionTimeout + 5
    private let lock = NSLock()
    private var intents: [String: String] = [:]
    private var held: [String: Held] = [:]
    /// The intents (turns) in which the owner said no to a card, or didn't answer one (tenth VM run, item 6: after his
    /// no the model tried a scroll and a script instead): nothing more that acts runs in them.
    private var declined: Set<String> = []
    /// Those of them in which he did say no (in the others every card only went unanswered).
    private var refusedIntents: Set<String> = []
    /// The intents in which a hand-off (Aside, a job, a schedule, a routine, a coding session) didn't go through (twelfth
    /// VM run, B3: Aside wasn't installed and the job drove Amazon in Safari itself). True: it failed when it ran (no
    /// Aside, no answer, his no on its own card), and nothing more that acts runs in the turn, as after his no. False:
    /// the gate refused its words, and only a hand-off with its words written again may still be tried.
    private var handOffs: [String: Bool] = [:]
    /// The intents in which a replace or a typing found its field changed after its card and changed nothing (thirteenth
    /// VM run, item 8: the model read the field and put the replace on a new card at once): nothing more acts in them.
    private var fieldChanged: Set<String> = []

    /// Said to the model, and kept in the record, for an acting call after a replace of the turn found its field changed.
    static func afterFieldChanged(english: Bool) -> String {
        let rule = "Not run: the field changed after his card, so nothing was replaced, and nothing more is done for this request now. "
            + "Tell him exactly that and ask whether to try again; never put the change on a new card in this turn."
        return english ? rule : "하지 않았어요: 카드를 띄운 뒤 칸의 글이 바뀌어서 아무것도 바꾸지 않았어요. (" + rule + ")"
    }

    /// Whether a call's result says its field changed after it was checked, so it changed nothing (ArisApps.TypeOver).
    static func foundFieldChanged(capability: String, result: ArisMindResult) -> Bool {
        capability == "app.type" && result.isError
            && [ArisApps.TypeOver.replaceRefusal, ArisApps.TypeOver.refusal].contains(where: result.text.contains)
    }

    /// Whether `session`'s turn under way had a replace find its field changed.
    func stoppedByFieldChange(session: String) -> Bool {
        lock.withLock { intents[session].map(fieldChanged.contains) ?? false }
    }

    /// Said to the model, and kept in the record, for an acting call after a hand-off of the same turn didn't go through.
    static func afterHandOff(english: Bool) -> String {
        english ? "Not run: the hand-off in this turn didn't go through, so this is not done another way. Tell him in a few words that it "
            + "couldn't be done and why; never say it was handed over or is being done."
            : "하지 않았어요: 이번 요청은 맡기지 못해서, 다른 방법으로 대신 하지 않아요. (Not run: the hand-off in this turn didn't go through, so this "
            + "is not done another way. Tell him in a few words that it couldn't be done and why; never say it was handed over or is being done.)"
    }

    /// Whether the call hands words over to something that then works on its own (ArisPaymentHandOff's carriers).
    static func handsOver(_ argv: [String]?) -> Bool { argv.map { ArisPaymentHandOff.brief($0) != nil } ?? false }

    /// A hand-off of `session`'s turn under way didn't go through: `ran` it failed when it ran; else the gate refused it.
    func noteHandOff(session: String, ran: Bool) {
        lock.withLock {
            guard let intent = intents[session] else { return }
            handOffs[intent] = (handOffs[intent] ?? false) || ran
        }
    }

    /// Whether an acting call in `session`'s turn under way is stopped by a hand-off that didn't go through.
    func stoppedByHandOff(session: String, handsOver: Bool) -> Bool {
        lock.withLock {
            guard let intent = intents[session], let ran = handOffs[intent] else { return false }
            return ran || !handsOver
        }
    }

    /// Whether `session`'s turn under way stopped acting: his no or no answer on a card, or a hand-off that didn't go
    /// through. A job that stopped is never asked again (ArisJobWork.stopped).
    func stoppedActing(session: String) -> Bool {
        lock.withLock { intents[session].map { declined.contains($0) || handOffs[$0] != nil } ?? false }
    }

    /// A background job's turn (the route's calls, a task of the Mind's loop): its own intent, so his no on one of its
    /// cards ends its acting as in a conversation, and its request for the payment boundary (never as their words).
    func jobTurn(session: String, intent: String, request: String) {
        nextIntent(session: session, intent: intent)
        gate.jobRequest(session: session, text: request)
    }

    /// Said to the model, and kept in the record, for an acting call made after his no in the same turn.
    /// `unanswered`: no card of the turn was answered no; one went unanswered, which is never told as his no.
    static func afterNo(english: Bool, unanswered: Bool = false) -> String {
        if unanswered {
            return english ? "Not run: a card in this turn got no answer in time (that is not a no), so nothing more is done for this request. Tell him so in a few words."
                : "하지 않았어요: 이번 요청의 카드에 답이 없어서, 더는 하지 않아요. (Not run: a card got no answer in this turn; that is not a no. Tell him so in a few words.)"
        }
        return english ? "Not run: the owner said no to a card in this turn, so nothing more is done for this request. Tell him so in a few words."
            : "하지 않았어요: 이번 요청에서 카드에 ‘아니요’라고 하셔서, 더는 하지 않아요. (Not run: the owner said no in this turn. Tell him so in a few words.)"
    }

    /// Whether his own no is among what ended the turn's acting.
    func saidNo(session: String) -> Bool {
        lock.withLock { intents[session].map(refusedIntents.contains) ?? false }
    }

    /// His no (or no answer) on a card of `session`'s turn under way: from the gate's own card, or a route's.
    func noteDeclined(session: String, unanswered: Bool = false) {
        lock.withLock {
            guard let intent = intents[session] else { return }
            declined.insert(intent)
            if !unanswered { refusedIntents.insert(intent) }
        }
    }

    func isDeclined(session: String) -> Bool {
        lock.withLock { intents[session].map(declined.contains) ?? false }
    }
    /// The calls whose card nobody answered in time (session and call), until their session ends: a replay's account
    /// says so, never that he said no (ninth VM run, item 3).
    private var silent: Set<String> = []

    init(gate: ArisTrustGate, tools: String = ArisAppBundle.toldTools, passes: ArisMindPasses = .shared) {
        self.gate = gate
        self.tools = tools
        self.passes = passes
    }

    nonisolated(unsafe) static var shared = ArisMindJudge(gate: ArisTrustGate.shared)

    /// How a route's own card says the owner said no (ArisDesktopEngine.noLine, ArisSkillScript.declined, ArisMCPHub).
    static let routeDeclines = ["The owner said no (or didn't answer)"]

    static let unknownTool = "Not run: there is no tool of that name."
    static let badArguments = "Not run: the arguments aren't what this tool takes."

    // MARK: - The owner's words

    /// The owner's words of a turn (`intent`: the turn's id), fed once; the intent before it ends with its asks.
    /// `speaker`: who said them (F1, the app's owner-voice verdict); not checked unless the app said.
    @discardableResult
    func turn(session: String, intent: String, words: String, speaker: ArisTurnSpeaker = .notChecked) -> ArisGrantChange? {
        let previous: String? = lock.withLock {
            let before = intents[session]
            intents[session] = intent
            return before
        }
        guard previous != intent else { return nil }
        if let previous {
            gate.end(intent: previous)
            passes.end(intent: previous)
            lock.withLock { declined.remove(previous); refusedIntents.remove(previous); handOffs[previous] = nil; fieldChanged.remove(previous) }
        }
        return gate.ownerTurn(session: session, text: words, speaker: speaker)
    }

    /// A new intent for the session with no new words (a replay going on past a step that failed, fifth VM run, D7): what
    /// the cards of the intent before it allowed ends with it, so nothing after his "go on" runs on an earlier yes.
    func nextIntent(session: String, intent: String) {
        let previous: String? = lock.withLock {
            let before = intents[session]
            intents[session] = intent
            return before
        }
        guard let previous, previous != intent else { return }
        gate.end(intent: previous)
        passes.end(intent: previous)
        lock.withLock { declined.remove(previous); refusedIntents.remove(previous); handOffs[previous] = nil; fieldChanged.remove(previous) }
    }

    /// A task's own instruction: the owner's earlier words for every step.
    func task(session: String, instruction: String) { gate.taskInstruction(session: session, text: instruction) }

    /// The session is over: its asks and its tracker go.
    func end(session: String) {
        let intent = lock.withLock { intents.removeValue(forKey: session) }
        if let intent {
            gate.end(intent: intent)
            passes.end(intent: intent)
            lock.withLock { declined.remove(intent); refusedIntents.remove(intent); handOffs[intent] = nil; fieldChanged.remove(intent) }
        }
        gate.forget(session: session)
        lock.withLock {
            held = held.filter { $0.value.session != session }
            silent = silent.filter { !$0.hasPrefix(session + "\u{1F}") }
        }
    }

    /// Whether `call`'s card got no answer in time (and so it didn't run): never his no.
    func unanswered(session: String, call: String) -> Bool { lock.withLock { silent.contains(key(session, call)) } }

    // MARK: - Deciding

    /// A call read as the book has it: its entry, its arguments, its aris-tools words and stdin.
    struct Read {
        let entry: ArisCapabilityEntry
        let arguments: [String: Any]
        let argv: [String]?
        let stdin: String?
    }

    func read(_ call: ArisMindToolCall) -> Result<Read, ArisMindError> {
        guard ArisCapabilityBook.entry(named: call.name) != nil else { return .failure(.init(Self.unknownTool)) }
        guard let arguments = call.object, let found = ArisHandsFace.call(function: call.name, input: arguments, tools: tools) else {
            return .failure(.init(Self.badArguments))
        }
        return .success(Read(entry: found.entry, arguments: arguments, argv: found.argv, stdin: found.stdin))
    }

    /// Every call of one round, decided by the gate. A call that can't be read is refused (and recorded as refused).
    /// `refusesFirst`: the call's own route's refusal that comes before any card (the desktop engine's replace guard),
    /// asked before a card could go up: such a call is refused with the route's own words and recorded, never carded
    /// (VM run 2, D4). `intent`: the turn the calls belong to; with it, a desktop call the gate lets run without a card
    /// carries a pass of the kind `judgedRun` (ArisMindPasses), so the desktop route doesn't ask for the app's yes again.
    /// A judgedRun pass is only minted when no other call of the same round can bring content in (it would come in
    /// before or while the call runs, unweighed by its decision): those calls go to their route's own card as before.
    func decide(session: String, task: String?, calls: [ArisMindToolCall], intent: String? = nil,
                refusesFirst: ((Read) -> String?)? = nil) -> [ArisMindDecided] {
        let reads = calls.map { read($0) }
        let bringing = zip(calls, reads).filter { _, read in
            if case .success(let read) = read { return Self.bringsContent(read) }
            return false
        }.map(\.0.id)
        return zip(calls, reads).map { call, read in
            switch read {
            case .failure(let error): return ArisMindDecided(call: call, verdict: .refuse(error.message))
            case .success(let read):
                let effect = read.entry.effect(read.arguments)
                let resolved = ArisCore2.decidedPath(read.entry.id, read.arguments)
                var outcome = gate.decide(session: session, task: task, call: call.id, capability: read.entry.id, effect: effect,
                                          arguments: read.arguments, argv: read.argv, stdin: read.stdin, payment: read.entry.payment(read.arguments))
                // aris-tools words it would refuse as a usage error: refused with the usage before any card, so the one
                // card that goes up is for words that run (thirteenth VM run, item 4: a delete needed two cards).
                if Self.mayRun(outcome.decision), let why = ArisToolWords.usageRefusal(read.argv) {
                    outcome = ArisTrustGate.Outcome(decision: .refuse(reason: why), verdict: outcome.verdict, facts: outcome.facts, effect: outcome.effect)
                    gate.record(session: session, task: task, call: call.id, outcome: outcome, answer: nil, result: nil, ok: false, undo: nil)
                }
                if Self.mayRun(outcome.decision), let why = refusesFirst?(read) {
                    outcome = ArisTrustGate.Outcome(decision: .refuse(reason: why), verdict: outcome.verdict, facts: outcome.facts, effect: outcome.effect)
                    gate.record(session: session, task: task, call: call.id, outcome: outcome, answer: nil, result: nil, ok: false, undo: nil)
                }
                // After his no on a card of this turn, nothing more that acts: one plain reason, recorded.
                if Self.mayRun(outcome.decision), outcome.effect != .observe, isDeclined(session: session) {
                    outcome = ArisTrustGate.Outcome(decision: .refuse(reason: Self.afterNo(english: ArisSkillLanguage.english, unanswered: !saidNo(session: session))), verdict: outcome.verdict,
                                                    facts: outcome.facts, effect: outcome.effect)
                    gate.record(session: session, task: task, call: call.id, outcome: outcome, answer: nil, result: nil, ok: false, undo: nil)
                }
                // After a hand-off of this turn didn't go through, it isn't done another way (twelfth VM run, B3).
                if Self.mayRun(outcome.decision), outcome.effect != .observe, stoppedByHandOff(session: session, handsOver: Self.handsOver(read.argv)) {
                    outcome = ArisTrustGate.Outcome(decision: .refuse(reason: Self.afterHandOff(english: ArisSkillLanguage.english)), verdict: outcome.verdict,
                                                    facts: outcome.facts, effect: outcome.effect)
                    gate.record(session: session, task: task, call: call.id, outcome: outcome, answer: nil, result: nil, ok: false, undo: nil)
                } else if !Self.mayRun(outcome.decision), Self.handsOver(read.argv) {
                    // In a background job one refused hand-off ends that line of action: it is not written again and
                    // retried (thirteenth VM run, item 3: four tries in one job); in a conversation he is there to say.
                    noteHandOff(session: session, ran: task != nil)
                }
                // After a replace of this turn found its field changed, he is asked first: nothing more acts (item 8).
                if Self.mayRun(outcome.decision), outcome.effect != .observe, stoppedByFieldChange(session: session) {
                    outcome = ArisTrustGate.Outcome(decision: .refuse(reason: Self.afterFieldChanged(english: ArisSkillLanguage.english)), verdict: outcome.verdict,
                                                    facts: outcome.facts, effect: outcome.effect)
                    gate.record(session: session, task: task, call: call.id, outcome: outcome, answer: nil, result: nil, ok: false, undo: nil)
                }
                let verdict = Self.verdict(outcome.decision, effect: effect, entry: read.entry, arguments: read.arguments)
                let seen = gate.contentRead(session: session)
                var runsNow = false
                if case .run = verdict { runsNow = true }
                lock.withLock {
                    held[key(session, call.id)] = Held(session: session, task: task, name: call.name, outcome: outcome, capability: read.entry.id,
                                                       argv: read.argv, stdin: read.stdin, seen: seen, bringsContent: Self.bringsContent(read),
                                                       resolved: resolved, intent: intent, arguments: read.arguments, runs: runsNow)
                }
                if let intent, case .run = verdict, outcome.verdict.provenance.source == nil, !bringing.contains(where: { $0 != call.id }) {
                    mintPasses(session: session, intent: intent, calls: [call.id], kind: .judgedRun)
                }
                return ArisMindDecided(call: call, verdict: verdict)
            }
        }
    }

    /// Whether a call's result can bring others' words in: an aris-tools call whose output is outside content
    /// (ArisHandsServer.content), and every helper capability (fail closed: an extra card at worst).
    static func bringsContent(_ read: Read) -> Bool {
        guard let argv = read.argv else { return true }
        return ArisHandsServer.content(argv) != nil
    }

    /// Whether a judgedRun pass of `call` still stands for exactly the content its decision saw: the conversation has
    /// taken in no content since (`seen`), and no other call of it that can bring content in is decided and not yet
    /// reported (its words would come in unweighed). Checked by the desktop gate each time it would use the pass.
    func judgedRunFresh(session: String, call: String, seen: Int) -> Bool {
        guard gate.contentRead(session: session) == seen else { return false }
        let own = key(session, call)
        return lock.withLock {
            held[own] != nil && !held.contains { $0.key != own && $0.value.session == session && $0.value.bringsContent }
        }
    }

    /// The decision lets the call run, now or on the owner's answer (anything but a refusal).
    static func mayRun(_ decision: ArisDecision) -> Bool {
        if case .refuse = decision { return false }
        return true
    }

    /// The policy's decision in the loop's terms. A call that waits for the owner keeps waiting for the gate's card,
    /// unless its route is one proven to put this very action on its own card every time (ArisMindBook.alwaysCarded):
    /// then that card is the one ask, and a reversible change keeps its undo.
    static func verdict(_ decision: ArisDecision, effect: ArisEffectClass, entry: ArisCapabilityEntry, arguments: [String: Any]) -> ArisMindVerdict {
        let verdict = ArisMindVerdict(decision)
        guard verdict == .waits, ArisMindBook.routeCardsEveryTime(entry, arguments: arguments) else { return verdict }
        return .run(undo: effect == .changeReversible, announce: false)
    }

    /// The calls that wait, on one card per intent (and a countdown card for those said first): blocks until the
    /// owner answers each card, or it times out (no answer acts as no, and is recorded as unanswered). The ids that may run.
    func ask(session: String, task: String?, intent: String, waiting: [ArisMindDecided], card: Card) -> Set<String> {
        let outcomes: [(call: String, outcome: ArisTrustGate.Outcome)] = lock.withLock {
            waiting.compactMap { item in held[key(session, item.call.id)].map { (item.call.id, $0.outcome) } }
        }
        guard !outcomes.isEmpty else { return [] }
        let planned = gate.cards(session: session, task: task, intent: intent, outcomes: outcomes)
        var allowed = Set(planned.covered)
        // Calls an earlier yes of this intent already covers run with no card of the gate's: for a desktop call, the app's
        // yes at its route too (judgedRun), never a stand-in for another card.
        mintPasses(session: session, intent: intent, calls: planned.covered, kind: .judgedRun)
        for shown in planned.cards {
            let done = DispatchSemaphore(value: 0)
            let box = ArisLocked<Bool?>(nil)
            card(shown) { answer in
                box.withLock { $0 = answer }
                done.signal()
            }
            let answer = done.wait(timeout: .now() + cardWait) == .success ? box.withLock { $0 } : nil
            // No answer in time is no for these calls, recorded as unanswered (never as his no).
            let answered = gate.answer(shown.id, allow: answer == true, unanswered: answer == nil)
            let run = answered.run
            if answer == nil { lock.withLock { silent.formUnion(answered.refused.map { key(session, $0) }) } }
            if answer != true { noteDeclined(session: session, unanswered: answer == nil) }
            allowed.formUnion(run)
            // The owner's yes on this card, for exactly these calls: each one's route takes it in place of its own card.
            if answer == true { mintPasses(session: session, intent: intent, calls: run) }
        }
        lock.withLock { for call in allowed { held[key(session, call)]?.runs = true; held[key(session, call)]?.approved = true } }
        return allowed
    }

    /// A judgedRun pass is minted with the content its decision saw (stored when it was decided), and only while that
    /// decision is still fresh (judgedRunFresh): content read between the decision and the owner's answer voids it.
    private func mintPasses(session: String, intent: String, calls: [String], kind: ArisMindPasses.Kind = .cardYes) {
        for call in calls {
            guard let found = lock.withLock({ held[key(session, call)] }) else { continue }
            if kind == .judgedRun {
                guard found.outcome.verdict.provenance.source == nil, judgedRunFresh(session: session, call: call, seen: found.seen) else { continue }
            }
            let pass = passes.mint(intent: intent, capability: found.capability, argv: found.argv, stdin: found.stdin, kind: kind,
                                   decision: kind == .judgedRun ? (session, call, found.seen) : nil)
            lock.withLock {
                if var still = held[key(session, call)] {
                    still.pass = pass
                    held[key(session, call)] = still
                }
            }
        }
    }

    /// A decided call's arguments, handed out once, for a route that runs it in the helper (ArisMindTaught): only a
    /// call of `capability` that was decided in this very turn (`intent`), may run now, and wasn't handed out before.
    /// Anything else (never decided, refused, waiting, another turn's, already taken, finished) is nil.
    func takeDecided(session: String, call: String, intent: String, capability: String) -> [String: Any]? {
        lock.withLock {
            let own = key(session, call)
            guard var found = held[own], found.capability == capability, found.intent == intent, found.runs, !found.taken else { return nil }
            found.taken = true
            held[own] = found
            return found.arguments
        }
    }

    /// The aris-tools words of a decided call (nil for a helper capability).
    func argv(session: String, call: String) -> [String]? {
        lock.withLock { held[key(session, call)]?.argv }
    }

    /// The capability of a call that was decided and hasn't reported yet (what its result is a result of).
    func capability(session: String, call: String) -> String? {
        lock.withLock { held[key(session, call)]?.capability }
    }

    /// The pass a call's route takes: for a call the owner said yes to on the gate's card, its stand-in for the route's
    /// own card; for a desktop call the gate let run without a card, the app's yes for that call (`judgedRun`).
    func pass(session: String, call: String) -> String? {
        lock.withLock { held[key(session, call)]?.pass }
    }

    /// A call is over: its line in the record (a refusal and the owner's no are already there), what it read to the
    /// provenance tracker.
    func finish(session: String, item: ArisMindDecided, result: ArisMindResult, disposition: ArisMindPorts.Disposition) {
        let found = lock.withLock { held.removeValue(forKey: key(session, item.call.id)) }
        guard let found else { return }
        switch disposition {
        case .refused, .declined: return
        case .stale:
            gate.record(session: session, task: found.task, call: item.call.id, outcome: found.outcome, answer: nil, result: "not run (a newer turn took over)",
                        ok: false, undo: nil)
        case .ran:
            gate.record(session: session, task: found.task, call: item.call.id, outcome: found.outcome, answer: nil,
                        result: String((result.isError ? ArisJournalWords.failure(result.text, english: ArisSkillLanguage.english) : result.text).prefix(ArisRecordEntry.resultLimit)),
                        ok: !result.isError, undo: result.undo, logged: result.logged)
            // A route's own card he said no to (the desktop engine's, a service's, a script's): the same no.
            if result.isError, Self.routeDeclines.contains(where: result.text.contains) { noteDeclined(session: session) }
            // A replace or a typing whose field changed after its card: nothing more acts this turn, he is asked (item 8).
            if Self.foundFieldChanged(capability: found.capability, result: result) {
                lock.withLock { if let intent = intents[session] { fieldChanged.insert(intent) } }
            }
            // A hand-off that failed when it ran (no Aside, no answer, his no on its own card): nothing more acts this turn.
            if result.isError, Self.handsOver(found.argv) { noteHandOff(session: session, ran: true) }
            // One that went through after its words were written again: the gate's refusal before it no longer stops the turn.
            if !result.isError, Self.handsOver(found.argv) {
                lock.withLock { if let intent = intents[session], handOffs[intent] == false { handOffs[intent] = nil } }
            }
            if let content = result.content {
                gate.toolResult(session: session, call: item.call.id, text: result.text, source: content, framed: result.framed)
            }
        }
    }

    /// What the gate decided about a call, until the call is over (a taught run's pass reads it: ArisTeachRunPass.Judged).
    func outcome(session: String, call: String) -> ArisTrustGate.Outcome? {
        lock.withLock { held[key(session, call)]?.outcome }
    }

    /// The provenance a decided call was given (for its undo's caller).
    func provenance(session: String, call: String) -> ArisCallProvenance? {
        lock.withLock { held[key(session, call)]?.outcome.verdict.provenance }
    }

    /// The effect a decided call was decided as (decision 4: the run of an overwrite decided reversible needs its copy).
    func effect(session: String, call: String) -> ArisEffectClass? {
        lock.withLock { held[key(session, call)]?.outcome.effect }
    }

    /// What a decided replace's card read in the field, as the mark its run checks the field against right before it
    /// sets it (ArisApps.TypeOver.mark); nil for a call the gate read nothing for.
    func erasedMark(session: String, call: String) -> String? {
        // A model's typing whose decision saw nothing selected is bound to that too (ArisTrustGate.Outcome.typingMark).
        lock.withLock { held[key(session, call)] }.flatMap {
            $0.capability == "app.type" ? $0.outcome.facts.erases.map { ArisApps.TypeOver.mark(erases: $0) } ?? $0.outcome.typingMark : nil
        }
    }

    /// A decided file call's path as it was decided, links followed (its run must land there).
    func resolved(session: String, call: String) -> String? {
        lock.withLock { held[key(session, call)]?.resolved }
    }

    /// Who spoke the words a decided call stands on (F1), for its undo's caller.
    func speaker(session: String, call: String) -> ArisTurnSpeaker {
        lock.withLock { held[key(session, call)]?.outcome.verdict.speaker } ?? .notChecked
    }

    /// The undo caller of a decided call: its session or task, its provenance and its speaker.
    func caller(session: String, task: String?, call: String) -> ArisUndoCaller {
        let found = lock.withLock { held[key(session, call)] }
        return ArisUndoCaller(session: session, task: task, provenance: provenance(session: session, call: call) ?? .ownStep,
                              approved: found?.approved == true, speaker: speaker(session: session, call: call), named: found?.outcome.undo?.named, planned: found?.outcome.undo?.ids)
    }

    private func key(_ session: String, _ call: String) -> String { session + "\u{1F}" + call }

    // MARK: - Ports

    /// The step's ports for one turn: this judge's decision and cards, `execute` for the calls allowed, `isCurrent`
    /// for the turn's identity.
    func ports(session: String, task: String?, intent: String, card: @escaping Card, execute: @escaping (ArisMindDecided, Read, ArisUndoCaller) -> ArisMindResult,
               isCurrent: @escaping () -> Bool) -> ArisMindPorts {
        ArisMindPorts(
            decide: { [self] calls in decide(session: session, task: task, calls: calls) },
            ask: { [self] waiting in ask(session: session, task: task, intent: intent, waiting: waiting, card: card) },
            execute: { [self] item in
                guard case .success(let read) = read(item.call) else { return ArisMindResult(text: Self.badArguments, isError: true) }
                return execute(item, read, caller(session: session, task: task, call: item.call.id))
            },
            finish: { [self] item, result, disposition in finish(session: session, item: item, result: result, disposition: disposition) },
            isCurrent: isCurrent,
            unanswered: { [self] call in unanswered(session: session, call: call) })
    }
}

struct ArisMindError: Error, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
}
