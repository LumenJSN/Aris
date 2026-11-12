//
//  ArisRoutineTurn.swift
//  aris-agent
//
//  The user's routines inside POST /ask (main.swift's handleAsk and stream call in here). His own words from the Aris app
//  that are a routine command (ArisRoutineIntent) are answered by the agent itself, on every brain alike:
//  - making, changing or deleting one reads it back on a card and saves only on their yes;
//  - "출근 루틴 해 줘" asks the routine's steps one after another, each handed back to handleAsk as a turn of its own on
//    the same connection: the same brain, gate, cards and taint as if he had just said it, nothing approved ahead by
//    having saved the routine, and outside text an early step read still marks the later ones (the conversation keeps
//    it). A step's own answer is held back; the run's one answer at the end is the account (ArisRoutineRun). A step of
//    his own words is first offered back to the app, which does what it would have done had he typed it (a timer, the
//    time, the volume, a to-do) with no AI at all; only a step the app doesn't take is asked of the AI
//    (ArisRoutineHandBack).
//  A routine whose steps an AI worded runs each step as model-written text (untrusted, none of it the user's words to any
//  gate), like a schedule's prompt. Heard hands-free a routine may run (every step gated as hands-free); nothing is
//  listed, made or changed. All of it happens on the server queue; the runs are behind a lock because other queues
//  call stream too.
//

import Foundation
import Network

enum ArisRoutineTurn {
    /// A routine running on a connection, and how its next step is asked (handleAsk again, with the step's words).
    private struct Running {
        var run: ArisRoutineRun
        let object: [String: Any]
        let connection: NWConnection
        let ask: ([String: Any], String) -> Void
        /// The app that asked answers steps offered back to it (its request said so).
        let appTakesSteps: Bool
        /// The step now offered to the app and not yet answered (ArisRoutineLocalStep's id).
        var offered: String?
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var running: [ObjectIdentifier: Running] = [:]
    /// What the agent heard from the user lately (in memory only), for "방금 한 걸 루틴으로 저장해 줘".
    nonisolated(unsafe) private static var recent = ArisRoutineRecent()

    private static var home: String { FileManager.default.homeDirectoryForCurrentUser.path }

    // MARK: - main.swift's hooks

    /// Whether this connection is in the middle of a routine: its stream is already open, so a step never opens it again.
    static func isStep(_ connection: NWConnection) -> Bool {
        lock.withLock { running[ObjectIdentifier(connection)]?.connection === connection }
    }

    /// Every line on its way to the app. On a connection running a routine the run decides: a status gets its count,
    /// a step's answer is kept and starts the next step, and the last one becomes the routine's account. Nil: not sent.
    static func through(_ reply: ArisAgentReply, on connection: NWConnection) -> ArisAgentReply? {
        let id = ObjectIdentifier(connection)
        guard isStep(connection) else { return reply }
        // On a Mac where no AI can answer, a step's "<one AI> isn't installed" is told as that (looked up before the lock).
        let heard = ArisRoutineAccount.truer(reply) { ArisBrain.allCases.contains(where: ArisSealedOneShot.available) }
        lock.lock()
        guard var now = running[id], now.connection === connection else {
            lock.unlock()
            return reply
        }
        let taken = now.run.taking(heard, answers: ArisRoutineCards.shared.answers(for: now.run.cards)) { ArisDispatch.jobsBlockRange(in: $0) != nil }
        now.run = taken.run
        if case .finish = taken.effect { running[id] = nil } else { running[id] = now }
        lock.unlock()
        switch taken.effect {
        case .pass(let line): return line
        case .drop: return nil
        case .next(_, let status):
            // Once this line is out: the step's runner has already let go of its turn.
            queue.async { askStep(id) }
            return status
        case .finish(let last):
            audit("routine: \(now.run.routine.name) ended at step \(taken.run.outcomes.count) of \(now.run.routine.steps.count)", risk: "spoken")
            // A step that did not finish gets no tick in the notch, and the button its failure earned goes out with
            // the account (ArisFixTurns), though the account is no longer that failure's own line.
            if ArisRoutineAccount.stoppedShort(taken.run.outcomes) {
                connection.send(content: ArisAgentReply.stepFailed(nil).line, completion: .contentProcessed { _ in })
            }
            if let line = ArisRoutineAccount.failureLine(taken.run.outcomes) { ArisFixTurns.shared.note(forFailureLine: line) }
            return last
        }
    }

    /// POST /ask, once its stream is open: true when the words were a routine's and are answered here.
    /// `request`: the user's words. `fromApp`: the caller is the Aris app itself. `plain`: no screen came with the turn.
    /// `step`: asks one step as a turn of its own (handleAsk with the changed request).
    static func takes(_ object: [String: Any], request: String, fromApp: Bool, handsFree: Bool, plain: Bool, on connection: NWConnection,
                      step: @escaping ([String: Any], String) -> Void) -> Bool {
        if isStep(connection) { return refusesNested(object, on: connection) }
        prune()
        // Only the user's own turn: never a model's words, another caller's, or a turn about the screen.
        guard fromApp, plain, object["untrusted"] as? Bool != true else { return false }
        let words = ArisMemoryText.ownWords(request).trimmingCharacters(in: .whitespacesAndNewlines)
        let korean = !ArisScheduleCard.isEnglish(words)
        let file = ArisRoutineStore.file(home: home)
        let stored = ArisRoutineWords.mentions(words) ? ArisRoutineStore.load(file: file) : []
        guard let intent = ArisRoutineIntent.parse(words, routines: stored) else {
            if !handsFree, !ArisRoutineWords.mentions(words) { lock.withLock { recent = recent.noting(words, at: Date()) } }
            return false
        }
        if handsFree {
            guard case .run = intent else { return false }
        }
        // Everything but a run is done here with no AI (a run's steps may ask one): said first, for the app's record.
        if !intent.asksAnAI { stream(.helperAnswers, on: connection) }
        switch intent {
        case .run(let routine): start(routine, object: object, korean: korean, on: connection, step: step)
        case .list: stream(.answer(ArisRoutineCopy.list(stored, korean: korean)), on: connection)
        case .show(let routine): stream(.answer(ArisRoutineCopy.show(routine, korean: korean)), on: connection)
        case .missing(let name): stream(.answer(ArisRoutineCopy.missing(name, routines: stored, korean: korean)), on: connection)
        case .create(let name, let steps): propose(name: name, steps: steps, stored: stored, korean: korean, on: connection)
        case .saveRecent(let name): proposeRecent(name: name, context: object["context"] as? String, stored: stored, korean: korean, on: connection)
        case .addStep(let routine, let added): proposeAdd(added, to: routine, korean: korean, on: connection)
        case .dropStep(let routine, let words): proposeDrop(words, from: routine, korean: korean, on: connection)
        case .delete(let routine): proposeDelete(routine, korean: korean, on: connection)
        }
        return true
    }

    // MARK: - Running

    private static func start(_ routine: ArisRoutine, object: [String: Any], korean: Bool, on connection: NWConnection,
                              step: @escaping ([String: Any], String) -> Void) {
        let run = ArisRoutineRun(routine: routine, korean: korean)
        guard !routine.steps.isEmpty else { return stream(.answer(ArisRoutineCopy.show(routine, korean: korean)), on: connection) }
        audit("routine: run \(routine.name) (\(routine.steps.count) steps, \(routine.own ? "their words" : "AI-worded"))", risk: "spoken")
        // Before the run is on the books, so this first status isn't counted a second time.
        stream(run.startStatus, on: connection)
        let id = ObjectIdentifier(connection)
        lock.withLock {
            running[id] = Running(run: run, object: object, connection: connection, ask: step, appTakesSteps: object["localSteps"] as? Bool == true)
        }
        // After handleAsk has returned for the routine's own turn.
        queue.async { askStep(id) }
    }

    /// The run's current step: offered to the app when it may do it by itself, else asked of the AI.
    private static func askStep(_ id: ObjectIdentifier) {
        guard let now = lock.withLock({ running[id] }) else { return }
        // The app let go of the stream between two steps: nothing more is asked.
        guard case .ready = now.connection.state else {
            lock.withLock { running[id] = nil }
            return
        }
        guard ArisRoutineHandBack.offers(own: now.run.routine.own, appTakesSteps: now.appTakesSteps) else { return askAI(id) }
        let offer = ArisRoutineLocalStep(id: UUID().uuidString, words: now.run.step)
        lock.withLock { running[id]?.offered = offer.id }
        now.connection.send(content: offer.line, completion: .contentProcessed { _ in })
        queue.asyncAfter(deadline: .now() + ArisRoutineHandBack.wait) { _ = ended(offer.id, nil) }
    }

    /// POST /routine-step, from the Aris app itself (main.swift checks the caller): how the step it was offered ended.
    /// False when no routine waits on that offer any more (it ran out, or the turn is gone).
    static func stepEnded(_ object: [String: Any]) -> Bool {
        guard let offer = object["id"] as? String, let outcome = ArisRoutineLocalOutcome.parse(object) else { return false }
        return ended(offer, outcome)
    }

    /// The offer `offer` is over: the app answered (`outcome`), or it never did (nil, after the wait).
    private static func ended(_ offer: String, _ outcome: ArisRoutineLocalOutcome?) -> Bool {
        let found: (id: ObjectIdentifier, now: Running)? = lock.withLock {
            guard let entry = running.first(where: { $0.value.offered == offer }) else { return nil }
            running[entry.key]?.offered = nil
            return (entry.key, entry.value)
        }
        guard let found else { return false }
        // After the app's POST has its answer: the next step may be a whole AI turn.
        queue.async {
            let connection = found.now.connection
            var reply = ArisAgentReply.failure(ArisRoutineHandBack.noWord(korean: found.now.run.korean))
            if let outcome {
                // Not the app's own to do: the AI's turn, as before. Otherwise its answer ends the step like an AI's would.
                guard let said = ArisRoutineHandBack.reply(outcome) else { return askAI(found.id) }
                reply = said
            } else {
                FileHandle.standardError.write(Data("aris-agent: the app didn't answer a routine step in \(Int(ArisRoutineHandBack.wait)) s\n".utf8))
            }
            // The run takes it here, so only what the run makes of it (the next step's status, or the account) is a line
            // of the turn: the step's own answer is no AI's and is not the turn's last word (ArisWhyDesk hears `stream`).
            if let line = through(reply, on: connection) { stream(line, on: connection) }
        }
        return true
    }

    /// Asks the run's current step of the AI: the request the user's turn came with, with the step's words in place of their.
    private static func askAI(_ id: ObjectIdentifier) {
        guard let now = lock.withLock({ running[id] }) else { return }
        let words = now.run.step, own = now.run.routine.own
        var object = now.object
        object["text"] = words
        // Steps an AI worded are nobody's own words: no gate takes them as the user's, and the turn is outside text.
        object["request"] = own ? words : ""
        if !own { object["untrusted"] = true }
        object["fresh"] = false
        object["tier"] = ArisRoutineTier.of(words).rawValue
        for key in ["images", "screen", "focus"] { object[key] = nil }
        now.ask(object, words)
    }

    /// A step that is itself a routine command never runs (none is saved that way; a store changed by hand could hold
    /// one): the step fails, which stops the routine with its account.
    private static func refusesNested(_ object: [String: Any], on connection: NWConnection) -> Bool {
        let words = ArisMemoryText.ownWords(object["text"] as? String ?? "")
        guard ArisRoutineWords.mentions(words) else { return false }
        stream(.failure(ArisRoutineCopy.nested(korean: !ArisScheduleCard.isEnglish(words))), on: connection)
        return true
    }

    /// Runs whose connection is gone are dropped (a step that never started because the app had let go).
    private static func prune() {
        lock.withLock {
            running = running.filter { _, value in
                switch value.connection.state {
                case .cancelled, .failed: return false
                default: return true
                }
            }
        }
    }

    // MARK: - Cards

    /// Puts a routine card to the user on this turn's stream; only the Aris app answers it (POST /confirm, ArisMCPCards).
    /// `yes` does the change and gives the line to say; `saving`: which "left as it was" line a no gets.
    private static func ask(_ card: ArisRoutineCard, saving: Bool, korean: Bool, on connection: NWConnection, yes: @escaping () throws -> String) {
        let shown = ArisMCPCards.shared.put(ArisMCPCard(title: card.title, detail: card.detail, full: nil, fields: []),
                                            timeout: ArisCardEdit.questionTimeout) { answer in
            queue.async {
                switch answer {
                case .yes:
                    do { stream(.answer(try yes()), on: connection) } catch {
                        FileHandle.standardError.write(Data("aris-agent: a routine couldn't be saved: \(error.localizedDescription)\n".utf8))
                        stream(.answer(ArisRoutineCopy.saveFailed(korean: korean)), on: connection)
                    }
                case .no: stream(.answer(ArisRoutineCopy.left(unanswered: false, saving: saving, korean: korean)), on: connection)
                case .unanswered: stream(.answer(ArisRoutineCopy.left(unanswered: true, saving: saving, korean: korean)), on: connection)
                }
            }
        }
        stream(.confirm(shown), on: connection)
    }

    /// The card for a new routine (or for replacing the one of that name), after its steps are checked.
    private static func propose(name: String, steps raw: [String], stored: [ArisRoutine], korean: Bool, on connection: NWConnection) {
        let existing = ArisRoutineNames.find(name, in: stored)
        if let problem = ArisRoutineRules.problem(name: name, steps: raw, others: existing == nil ? stored.count : 0) {
            return stream(.answer(ArisRoutineCopy.problem(problem, korean: korean)), on: connection)
        }
        let steps = raw.compactMap(ArisRoutineRules.step)
        ask(ArisRoutineCopy.saveCard(name: name, steps: steps, replacing: existing, korean: korean), saving: true, korean: korean, on: connection) {
            let routine = try ArisRoutineDesk.save(name: existing?.name ?? name, steps: steps, own: true, replacing: existing, home: home)
            return ArisRoutineCopy.saved(routine, korean: korean)
        }
    }

    private static func proposeRecent(name: String?, context: String?, stored: [ArisRoutine], korean: Bool, on connection: NWConnection) {
        let steps = lock.withLock { recent }.steps(context: context, now: Date())
        guard !steps.isEmpty else { return stream(.answer(ArisRoutineCopy.recentNone(korean: korean)), on: connection) }
        guard let name else { return stream(.answer(ArisRoutineCopy.recentNeedsName(steps: steps, korean: korean)), on: connection) }
        propose(name: name, steps: steps, stored: stored, korean: korean, on: connection)
    }

    private static func proposeAdd(_ added: String, to routine: ArisRoutine, korean: Bool, on connection: NWConnection) {
        if let problem = ArisRoutineRules.problem(name: routine.name, steps: routine.steps + [added], others: 0) {
            return stream(.answer(ArisRoutineCopy.problem(problem, korean: korean)), on: connection)
        }
        let steps = routine.steps + [ArisRoutineRules.step(added) ?? added]
        ask(ArisRoutineCopy.changeCard(routine, steps: steps, added: steps.last, removed: nil, korean: korean), saving: false, korean: korean, on: connection) {
            ArisRoutineCopy.changed(try ArisRoutineDesk.change(routine, steps: steps, home: home), korean: korean)
        }
    }

    private static func proposeDrop(_ words: String, from routine: ArisRoutine, korean: Bool, on connection: NWConnection) {
        guard routine.steps.count > 1 else { return stream(.answer(ArisRoutineCopy.onlyStep(routine, korean: korean)), on: connection) }
        let found = ArisRoutineStepPick.matches(of: words, in: routine.steps)
        // Several steps fit their words: they are listed with their numbers; none: the whole routine is.
        guard found.count == 1, let index = found.first else {
            return stream(.answer(found.count > 1 ? ArisRoutineCopy.whichOf(routine, steps: found, korean: korean)
                                                  : ArisRoutineCopy.whichStep(routine, korean: korean)), on: connection)
        }
        let steps = routine.steps.enumerated().filter { $0.offset != index }.map(\.element)
        ask(ArisRoutineCopy.changeCard(routine, steps: steps, added: nil, removed: routine.steps[index], korean: korean), saving: false, korean: korean,
            on: connection) {
            ArisRoutineCopy.changed(try ArisRoutineDesk.change(routine, steps: steps, home: home), korean: korean)
        }
    }

    private static func proposeDelete(_ routine: ArisRoutine, korean: Bool, on connection: NWConnection) {
        let card = ArisRoutineCopy.deleteCard(routine, schedules: ArisRoutineDesk.schedules(running: routine, home: home, korean: korean), korean: korean)
        ask(card, saving: false, korean: korean, on: connection) {
            ArisRoutineCopy.deleted(try ArisRoutineDesk.delete(routine, home: home), korean: korean)
        }
    }

    private static func audit(_ action: String, risk: String) {
        ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["action": action, "risk": risk]), key: "local")
    }
}

/// The changes to the routine store, each after the user's yes on its card, each with its line in actions.log.
enum ArisRoutineDesk {
    /// Saves a routine under `name` (in place of `replacing`, which keeps its id and its first day).
    static func save(name: String, steps: [String], own: Bool, replacing: ArisRoutine?, home: String, now: Date = Date()) throws -> ArisRoutine {
        let routine = ArisRoutine(id: replacing?.id ?? UUID(), name: name, steps: steps, own: own, created: replacing?.created ?? now, changed: now)
        try ArisRoutineStore.save(routine, file: ArisRoutineStore.file(home: home))
        audit("routine: saved \(name) (\(steps.count) steps, \(own ? "their words" : "AI-worded"))")
        return routine
    }

    static func change(_ routine: ArisRoutine, steps: [String], home: String, now: Date = Date()) throws -> ArisRoutine {
        let changed = routine.with(steps: steps, at: now)
        try ArisRoutineStore.save(changed, file: ArisRoutineStore.file(home: home))
        audit("routine: changed \(routine.name) (\(steps.count) steps)")
        return changed
    }

    static func delete(_ routine: ArisRoutine, home: String) throws -> ArisRoutine {
        let removed = try ArisRoutineStore.remove(id: routine.id, file: ArisRoutineStore.file(home: home))
        audit("routine: deleted \(routine.name)")
        return removed
    }

    /// The schedules whose job is to run this routine, as the delete card names them ("출근 루틴 (매일 09:00)").
    static func schedules(running routine: ArisRoutine, home: String, korean: Bool) -> [String] {
        ArisScheduleStore.load(file: ArisScheduleStore.file(home: home))
            .filter { $0.nextRun != nil && ArisRoutineChain.routine(forPrompt: $0.prompt, in: [routine]) != nil }
            .map { "\($0.title) (\(ArisScheduleCard.when($0.rule, english: !korean, calendar: .current)))" }
    }

    private static func audit(_ action: String) {
        ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["action": action, "risk": "asked"]), key: "local")
    }
}
