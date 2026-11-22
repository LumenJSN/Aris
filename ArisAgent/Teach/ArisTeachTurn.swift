//
//  ArisTeachTurn.swift
//  aris-agent
//
//  "Show it once" inside POST /ask (main.swift's handleAsk calls `takes` once, beside the routines' hook), with
//  `arisTeach` and `arisCore2` on. Only the owner's own words from the Aris app, typed or spoken with the key (never
//  hands-free, never a model's words or a turn about the screen):
//  - "지금부터 하는 거 출근 준비라고 해" starts watching (ArisTeachDesk); while it watches, every turn of his is the
//    lesson's: "다 했어" ends it, "배우기 취소" drops it, anything else is answered with how to end it, and Aris does
//    nothing in apps meanwhile (so nothing Aris does is taken for what he showed);
//  - at "다 했어" the steps are read back on a card in plain Korean, and saved only on their yes;
//  - "출근 준비 해 줘, 제목은 월간 보고" replays it (ArisTeachRunner, off the server queue: a card waits for him), each
//    step's status in the notch with its count, the trust gate's cards on this turn's stream, and one account at the
//    end;
//  - "배운 거 보여 줘", "출근 준비 어떻게 해" answer at once; renaming and deleting ask on a card first.
//  Everything here answers with no AI, in the UI's language (the request's "lang"), never the request's.
//

import Foundation
import Network

enum ArisTeachTurn {
    private static var home: String { FileManager.default.homeDirectoryForCurrentUser.path }
    private static var file: URL { ArisTeachStore.file(home: home) }

    /// True when the words were about taught procedures and are answered here. `fromApp`: the caller is the Aris app
    /// itself; `plain`: no screen came with the turn.
    static func takes(_ object: [String: Any], request: String, fromApp: Bool, handsFree: Bool, plain: Bool, on connection: NWConnection) -> Bool {
        guard ArisTeachSwitch.isOn() else { return false }
        let words = ArisMemoryText.ownWords(request).trimmingCharacters(in: .whitespacesAndNewlines)
        // Aris's own words follow the request's language, the UI's when it shows none (the app says it with every request,
        // "lang"): thirteenth VM run, item 7, in place of third VM run D4's UI language; his names and values stay as written.
        ArisSkillLanguage.heard(object["lang"])
        let english = ArisSkillLanguage.english(for: words)
        let desk = ArisTeachDesk.shared
        if let name = desk.recording {
            // While Aris watches, no turn acts in an app: the owner's words end or drop the lesson, anything else waits.
            let intent = fromApp && !handsFree && object["untrusted"] as? Bool != true ? ArisTeachIntent.parse(words, procedures: [], recording: true) : nil
            stream(.helperAnswers, on: connection)
            switch intent {
            case .stop?: finish(english: english, on: connection)
            case .cancel?:
                desk.cancel()
                audit("teach: cancelled \(name)")
                stream(.answer(ArisTeachCopy.cancelled(name, english: english)), on: connection)
            case .start?, .startUnnamed?: stream(.answer(ArisTeachCopy.alreadyWatching(name, english: english)), on: connection)
            default: stream(.answer(ArisTeachCopy.busyWatching(name, english: english)), on: connection)
            }
            return true
        }
        // The one rule for who may start a run, shared with a model's call (ArisTeachMay): here only a plain turn of his.
        guard ArisTeachMay.start(fromApp: fromApp, plain: plain, handsFree: handsFree, untrusted: object["untrusted"] as? Bool == true,
                                 task: object["task"] as? Bool == true, scoped: false, speaker: .notChecked) == .run else { return false }
        let expired = desk.takeExpired()
        let stored = ArisTeachStore.load(file: file)
        guard let intent = ArisTeachIntent.parse(words, procedures: stored, recording: false) else {
            if let expired, ArisTeachIntent.normalised(words).range(of: ArisTeachIntent.stopPattern, options: [.regularExpression, .caseInsensitive]) != nil {
                stream(.helperAnswers, on: connection)
                stream(.answer(ArisTeachCopy.expired(expired, english: english)), on: connection)
                return true
            }
            return false
        }
        stream(.helperAnswers, on: connection)
        switch intent {
        case .start(let name): start(name, english: english, on: connection)
        case .startUnnamed: stream(.answer(ArisTeachCopy.needsName(english: english)), on: connection)
        case .stop, .cancel: stream(.answer(ArisTeachCopy.notWatching(english: english)), on: connection)
        case .list: stream(.answer(ArisTeachCopy.list(stored, english: english)), on: connection)
        case .show(let procedure): stream(.answer(ArisTeachCopy.show(procedure, english: english)), on: connection)
        case .rename(let procedure, let name): rename(procedure, to: name, stored: stored, english: english, on: connection)
        case .delete(let procedure): delete(procedure, english: english, on: connection)
        case .run(let procedure, let rest): replay(procedure, words: words, rest: rest, english: english, on: connection)
        }
        return true
    }

    // MARK: - Watching

    private static func start(_ name: String, english: Bool, on connection: NWConnection) {
        let routines = ArisRoutineStore.load(file: ArisRoutineStore.file(home: home))
        if ArisRoutineNames.find(name, in: routines) != nil { return stream(.answer(ArisTeachCopy.nameTaken(name, english: english)), on: connection) }
        switch ArisTeachDesk.shared.start(name: name) {
        case .started:
            audit("teach: watching \(name)")
            stream(.answer(ArisTeachCopy.started(name, english: english)), on: connection)
        case .already(let current): stream(.answer(ArisTeachCopy.alreadyWatching(current, english: english)), on: connection)
        case .cannot: stream(.answer(ArisTeachCopy.cannotWatch(english: english)), on: connection)
        }
    }

    /// "다 했어": the lesson made into steps, read back on a card, saved on their yes.
    private static func finish(english: Bool, on connection: NWConnection) {
        guard let lesson = ArisTeachDesk.shared.stop() else { return stream(.answer(ArisTeachCopy.notWatching(english: english)), on: connection) }
        audit("teach: \(lesson.name) shown (\(lesson.events.count) events, \(lesson.skipped) secret left out) [\(ArisTeachGeneralise.shape(lesson.events))]")
        let leftOut = ArisTeachGeneralise.leftOut(lesson.events)
        let existing = ArisTeachNames.find(lesson.name, in: ArisTeachStore.load(file: file))
        switch ArisTeachGeneralise.procedure(lesson, id: existing?.id ?? UUID()) {
        case .failure(.nothing):
            stream(.answer(ArisTeachCopy.nothingSaved(lesson.name, leftOut: leftOut, english: english)), on: connection)
        case .failure(.tooLong(let count)): stream(.answer(ArisTeachCopy.tooLong(count, english: english)), on: connection)
        case .success(let made):
            let procedure = existing.map { ArisTeachProcedure(id: $0.id, name: $0.name, steps: made.steps, parameters: made.parameters, skipped: made.skipped,
                                                               created: $0.created, changed: made.created) } ?? made
            ask(ArisTeachCopy.saveCard(procedure, replacing: existing != nil, leftOut: leftOut, english: english), saving: true, english: english, on: connection) {
                try ArisTeachStore.save(procedure, file: file)
                audit("teach: saved \(procedure.name) (\(procedure.steps.count) steps, \(procedure.parameters.count) values)")
                return ArisTeachCopy.saved(procedure, english: english)
            }
        }
    }

    // MARK: - Changing

    private static func rename(_ procedure: ArisTeachProcedure, to name: String, stored: [ArisTeachProcedure], english: Bool, on connection: NWConnection) {
        let routines = ArisRoutineStore.load(file: ArisRoutineStore.file(home: home))
        let taken = stored.contains { $0.id != procedure.id && ArisTeachNames.key($0.name) == ArisTeachNames.key(name) }
        if taken || ArisRoutineNames.find(name, in: routines) != nil { return stream(.answer(ArisTeachCopy.nameTaken(name, english: english)), on: connection) }
        ask(ArisTeachCopy.renameCard(procedure, to: name, english: english), saving: false, english: english, on: connection) {
            let renamed = procedure.renamed(name, at: Date())
            try ArisTeachStore.save(renamed, file: file)
            audit("teach: renamed \(procedure.name) to \(name)")
            return ArisTeachCopy.renamed(renamed, english: english)
        }
    }

    private static func delete(_ procedure: ArisTeachProcedure, english: Bool, on connection: NWConnection) {
        ask(ArisTeachCopy.deleteCard(procedure, english: english), saving: false, english: english, on: connection) {
            let removed = try ArisTeachStore.remove(id: procedure.id, file: file)
            audit("teach: deleted \(removed.name)")
            return ArisTeachCopy.deleted(removed, english: english)
        }
    }

    /// The owner's card on this turn's stream; `yes` runs only after their yes.
    private static func ask(_ card: ArisTeachCopy.Card, saving: Bool, english: Bool, on connection: NWConnection, yes: @escaping () throws -> String) {
        let shown = ArisMCPCards.shared.put(ArisMCPCard(title: card.title, detail: card.detail, full: card.full, fields: []),
                                            timeout: ArisCardEdit.questionTimeout) { answer in
            queue.async {
                switch answer {
                case .yes:
                    do { stream(.answer(try yes()), on: connection) } catch {
                        FileHandle.standardError.write(Data("aris-agent: a taught procedure couldn't be saved: \(error.localizedDescription)\n".utf8))
                        stream(.answer(ArisTeachCopy.saveFailed(english: english)), on: connection)
                    }
                case .no: stream(.answer(saving ? ArisTeachCopy.notSaved(unanswered: false, english: english) : ArisTeachCopy.left(unanswered: false, english: english)), on: connection)
                case .unanswered: stream(.answer(saving ? ArisTeachCopy.notSaved(unanswered: true, english: english) : ArisTeachCopy.left(unanswered: true, english: english)), on: connection)
                }
            }
        }
        stream(.confirm(shown), on: connection)
    }

    // MARK: - Replaying

    private static func replay(_ procedure: ArisTeachProcedure, words: String, rest: String, english: Bool, on connection: NWConnection) {
        audit("teach: run \(procedure.name) (\(procedure.steps.count) steps) by its name in his own words: no card first, steps decided with what was read")
        let status = ArisTeachCopy.running(procedure, english: english)
        DispatchQueue.global(qos: .userInitiated).async {
            let hands = ArisAppsBook.hands()
            let card: ArisMindJudge.Card = { gateCard, answer in
                // While a step's card waits, the app he had is back in front (seventh VM run, item 8); a step that needs
                // its app in front brings it forward again itself.
                hands.yieldFront()
                let shown = ArisMCPCards.shared.put(ArisMCPCard(title: gateCard.title, detail: gateCard.detail, full: gateCard.full, fields: [],
                                                                countdown: gateCard.countdown, spoken: gateCard.spoken),
                                                    timeout: ArisCardEdit.questionTimeout) { reply in
                    switch reply {
                    case .yes: answer(true)
                    case .no: answer(false)
                    case .unanswered: answer(nil)
                    }
                }
                stream(.confirm(shown), on: connection)
            }
            let isCurrent = { () -> Bool in
                if case .ready = connection.state { return true }
                return false
            }
            // A step that didn't work with steps left: it is said, then his card asks whether to go on with them (계속 /
            // 멈추기), and the run goes on only on their yes (fifth VM run, D7: it used to stop there in silence).
            let goOn = { (index: Int, why: String) -> Bool in
                // His app goes back in front first: it takes a moment, and nothing may come between the sentence and the
                // card (ninth VM run, item 6, cap9/W2-burst-montage.jpg: for 0.3 s the notch stood closed down to the
                // answer's "Close", the tag gone and the sentence not yet drawn, before the card grew).
                hands.yieldFront()
                // The step's tag is marked failed before the sentence, so it is never ticked (seventh VM run, item 2).
                for reply in ArisTeachTurnReplies.failed(procedure, at: index, why: why, english: english) { stream(reply, on: connection) }
                let asked = ArisTeachCopy.goOnCard(procedure, failedAt: index, why: why, english: english)
                let answered = DispatchSemaphore(value: 0)
                let yes = ArisTeachAnswer()
                let shown = ArisMCPCards.shared.put(ArisMCPCard(title: asked.title, detail: asked.detail, full: asked.full, fields: [],
                                                                allow: ArisTeachCopy.goOnAllow(english: english)),
                                                    timeout: ArisCardEdit.questionTimeout) { reply in
                    if case .yes = reply { yes.set(true) }
                    answered.signal()
                }
                stream(.confirm(shown), on: connection)
                _ = answered.wait(timeout: .now() + ArisCardEdit.questionTimeout + 5)
                return yes.get()
            }
            // A value their words didn't give is asked first, last time's value offered on the card; nothing runs on a no.
            // When the run would ask on a card for a step the one card may cover, that first card is the run's one card
            // (ArisTeachRunPass): every step on it, and their yes there a pass for exactly that plan.
            var answered: [String: String] = [:]
            var pass: ArisTeachRunPass?
            let run = String(UUID().uuidString.prefix(8)).lowercased()
            var runner = ArisTeachRunner()
            let given = ArisTeachMatch.values(procedure, words: rest)
            let missing = ArisTeachReplay.missing(procedure, given: given)
            // The plan the card shows: a value asked on it counts as his (he gives it there).
            let drafted = ArisTeachReplay.plan(procedure, given: given.merging(Dictionary(uniqueKeysWithValues: missing.map { ($0.key, $0.example) })) { $1 },
                                               words: words, run: run)
            let marks = runner.marks(drafted)
            let once = ArisTeachRunPass.asksOnce(marks)
            if once || !missing.isEmpty {
                // Last time's values as the suggestion (twelfth VM run: the taught example was offered instead).
                let last = ArisTeachLastValues.load(procedure.id, file: ArisTeachLastValues.file(home: home))
                let whole = once ? ArisTeachCopy.runCard(procedure, plan: drafted, marks: marks, missing: missing, last: last, english: english) : nil
                let asked = whole.map { (card: $0.card, fields: $0.fields) } ?? ArisTeachCopy.valuesCard(procedure, missing: missing, last: last, english: english)
                let fields = asked.fields.map { ArisMCPCardField(key: $0.key, role: .text, value: $0.value) }
                let done = DispatchSemaphore(value: 0)
                let reply = ArisTeachValues()
                let shown = ArisMCPCards.shared.put(ArisMCPCard(title: asked.card.title, detail: asked.card.detail, full: asked.card.full, fields: fields,
                                                                spoken: whole?.spoken),
                                                    timeout: ArisCardEdit.questionTimeout) { answer in
                    reply.set(answer)
                    done.signal()
                }
                stream(.confirm(shown), on: connection)
                _ = done.wait(timeout: .now() + ArisCardEdit.questionTimeout + 5)
                guard case .yes(let edits)? = reply.get() else {
                    audit("teach: \(procedure.name) not run (\(once ? "no to the run's card" : "no values"))")
                    let unanswered = reply.get().map { $0 == .unanswered } ?? true
                    return stream(.answer(ArisTeachCopy.notRun(procedure, unanswered: unanswered, english: english)), on: connection)
                }
                answered = ArisTeachReplay.answered(missing, edits: edits)
                // The pass is for the plan with the values he left on the card: the run makes its calls anew, and each
                // must be exactly this plan's.
                if once {
                    let allowed = ArisTeachRunPass(plan: ArisTeachReplay.plan(procedure, given: given.merging(answered) { $1 }, words: words, run: run))
                    audit("teach: \(procedure.name) allowed on one card (plan \(allowed.hash), \(marks.filter { $0 == .covered }.count) of \(marks.count) steps covered)")
                    pass = allowed
                }
            }
            // An app a step brought forward stays in front for the steps after it, and the app he had goes back once
            // the run ends, however it ends (sixth VM run, item 4), or while the run waits on a card (item 8 above).
            hands.beginFrontHold()
            // The run's record session names the lesson, for the undo's reply (seventh VM run, item 5).
            ArisTeachRunNames.shared.note(session: "teach-" + run, name: procedure.name)
            let unchecked = ArisTeachRunEnd.Unchecked()
            let placed = ArisTeachRunEnd.Placed()
            let execute = runner.execute
            runner.execute = { item, read, caller in
                let result = execute(item, read, caller)
                unchecked.note(call: item.call.name, result: result)
                placed.note(call: item.call.name, beginsLine: ArisTeachRunEnd.beginsLine(read.arguments), result: result)
                return result
            }
            // No card comes first here even when a conversation read outside text before (eleventh VM run, item 4, T5),
            // and that is decided, not left open: this path is reached only by the owner's own words from the app
            // (typed, or spoken with the key held: ArisTeachMay), matched to his lesson's exact name by code, with no
            // model between; its values are spans of those same words or what he writes on the run's card. Nothing
            // Aris read can start it or fill it. A model's call for a lesson is different (what it read may be why it
            // calls), and that asks first (ArisTaughtClash). What was read still reaches every step's decision
            // (`carryingAll`), a recorded value is still the app's content, and a step that erases, sends or pays still
            // asks at the moment it runs.
            let ended = runner.run(procedure, words: words, rest: rest, answered: answered, run: run, card: card, isCurrent: isCurrent, progress: { index, total in
                stream(.status(ArisRoutineProgress.line(step: index + 1, total: total, text: status)), on: connection)
            }, goOn: goOn, english: english, pass: pass, carryingAll: true)
            hands.endFrontHold()
            audit("teach: \(procedure.name) ended \(ended.outcome)")
            if ArisTeachRunEnd.completed(ended.outcome) {
                ArisTeachLastValues.note(procedure.id, values: given.merging(answered) { $1 }, file: ArisTeachLastValues.file(home: home))
            }
            // A run that didn't do every step doesn't leave its tag ticked (sixth VM run, item 6a).
            if ArisTeachRunEnd.marksTagFailed(ended.outcome) { stream(.stepFailed(nil), on: connection) }
            // A line-starting text that read back on the same line is said, never "done" (item 2, T1).
            let account = ArisTeachRunEnd.withPlace(ArisTeachCopy.account(procedure, outcome: ended.outcome, english: english), procedure: procedure,
                                                    outcome: ended.outcome, sameLine: placed.sameLine, english: english)
            // Typing that went in but couldn't be checked has no undo: said, so "되돌려" saying so later is no surprise (item 1).
            stream(.answer(ArisTeachRunEnd.withUnchecked(account, apps: unchecked.apps, english: english)), on: connection)
        }
    }

    private static func audit(_ action: String) {
        ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["action": action, "risk": "asked"]), key: "local")
    }
}

/// The owner's answer to a run's "go on?" card, read after the wait.
private final class ArisTeachAnswer: @unchecked Sendable {
    private let lock = NSLock()
    private var yes = false
    func set(_ value: Bool) { lock.withLock { yes = value } }
    func get() -> Bool { lock.withLock { yes } }
}

/// The owner's answer to a run's values card, read after the wait.
private final class ArisTeachValues: @unchecked Sendable {
    private let lock = NSLock()
    private var answer: ArisMCPAnswer?
    func set(_ value: ArisMCPAnswer) { lock.withLock { answer = value } }
    func get() -> ArisMCPAnswer? { lock.withLock { answer } }
}
