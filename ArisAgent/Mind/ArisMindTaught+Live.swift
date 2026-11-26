//
//  ArisMindTaught+Live.swift
//  aris-agent
//
//  ArisMindTaught's live parts. In the process that hosts the Mind's loop (`aris-agent mind-brain`): `remote`, which
//  hands a decided `taught_run` call to the helper over POST /mind-call (op "taught", the same door and the same checks
//  of the caller as every other op). In the helper: that op, with the owner's words and the taint of the call's own
//  turn, the cards on that turn's stream (the runner's card path, as the trust gate's cards), the store, and the replay
//  (ArisTeachRunner, exactly as a run by its name: the front app held and given back, the run named for its undo,
//  typing with no undo noted).
//

import Foundation

extension ArisMindTaught {
    /// Where his choice between a lesson and a built-in of the same word is kept: beside taught.json, the same way.
    static func choicesFile(home: String) -> URL { ArisPrivateFile.folder(home: home).appendingPathComponent("taught-choices.json") }

    static func choices(file: URL) -> [String: ArisTaughtClash.Choice] {
        guard let data = ArisPrivateFile.read(file) else { return [:] }
        return (try? JSONDecoder().decode([String: ArisTaughtClash.Choice].self, from: data)) ?? [:]
    }

    static func remember(_ id: UUID, _ choice: ArisTaughtClash.Choice, file: URL) {
        var kept = choices(file: file)
        kept[id.uuidString] = choice
        guard let data = try? JSONEncoder().encode(kept) else { return }
        do { try ArisPrivateFile.write(data, to: file) } catch {
            try? FileHandle.standardError.write(contentsOf: Data("aris-agent: a saved-steps choice couldn't be kept: \(error.localizedDescription)\n".utf8))
        }
    }

    /// The helper's side of op "taught", for a call its gate decided (`arguments`: as decided): the reply's fields.
    /// `session`: the calling conversation's (its outside text is carried to the replay's).
    static func call(_ arguments: [String: Any], runner: ArisAgentRunner, credential: String, session: String) -> [String: Any] {
        let now = runner.messageSnapshot()
        guard now.active else { return ["text": unavailable, "isError": true] }
        // The same rule as a run by its name (ArisTeachTurn). The turn's taint stands for what the owner's path checks
        // at the door: a caller that isn't the app, or text that came with the turn, marks the turn as outside text.
        let may = ArisTeachMay.start(fromApp: true, plain: now.taint != .screenSeen, handsFree: now.handsFree, untrusted: now.taint == .outsideText,
                                     task: runner.isBackgroundTask, scoped: now.scopes != nil, speaker: now.speaker)
        let result = handle(arguments, request: ArisMemoryText.ownWords(now.request), may: may,
                            ports: live(runner: runner, credential: credential, session: session, now: now, clean: may == .run))
        ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["action": "teach: a model's run " + (result.isError ? "didn't finish" : "done"), "risk": "asked"]), key: "local")
        return ["text": String(result.text.prefix(20_000)), "isError": result.isError]
    }

    static func live(runner: ArisAgentRunner, credential: String, session: String, now: ArisMessageSnapshot, clean: Bool, home: String = FileManager.default.homeDirectoryForCurrentUser.path) -> Ports {
        // A Korean request's run is said in Korean, whatever the UI (thirteenth VM run, item 7: "Done: “줄 추가” (2 steps).").
        let english = ArisSkillLanguage.english(for: now.request)
        let choices = choicesFile(home: home)
        let ask = { (card: ArisTeachCopy.Card, fields: [(key: String, value: String)], allow: String?) -> Answer in
            let done = DispatchSemaphore(value: 0)
            let answer = ArisLocked<Answer>(.unanswered)
            var shown = ArisMCPCard(title: card.title, detail: card.detail, full: card.full,
                                    fields: fields.map { ArisMCPCardField(key: $0.key, role: .text, value: $0.value) })
            shown.allow = allow
            runner.mcpAsk(shown, credential: credential) { reply in
                answer.withLock {
                    switch reply {
                    case .yes(let edits): $0 = .yes(edits)
                    case .no: $0 = .no
                    case .unanswered: $0 = .unanswered
                    }
                }
                done.signal()
            }
            _ = done.wait(timeout: .now() + ArisCardEdit.questionTimeout + 30)
            return answer.withLock { $0 }
        }
        // One run's id for its card's plan and its pass; whether the run's one card was shown (its yes is the pass).
        let run = String(UUID().uuidString.prefix(8)).lowercased()
        let once = ArisLocked<Bool>(false)
        // His yes on the card that asked first (a turn that read outside text), which showed every step and value.
        let upFront = ArisLocked<Bool>(false)
        let last = ArisTeachLastValues.file(home: home)
        var ports = Ports(
            isOn: { ArisTeachSwitch.isOn() },
            procedures: { ArisTeachStore.load(file: ArisTeachStore.file(home: home)) },
            remembered: { Self.choices(file: choices)[$0.uuidString] },
            remember: { Self.remember($0, $1, file: choices) },
            ask: ask,
            declined: { ArisMindJudge.shared.noteDeclined(session: session, unanswered: $0) },
            run: { procedure, words, given in
                let hands = ArisAppsBook.hands()
                // While a card waits, the app he had is back in front; a step that needs its app brings it forward itself.
                let card: ArisMindJudge.Card = { gateCard, answer in
                    hands.yieldFront()
                    runner.mcpAsk(ArisMCPCard(title: gateCard.title, detail: gateCard.detail, full: gateCard.full, fields: [],
                                              countdown: gateCard.countdown, spoken: gateCard.spoken), credential: credential) { reply in
                        switch reply {
                        case .yes: answer(true)
                        case .no: answer(false)
                        case .unanswered: answer(nil)
                        }
                    }
                }
                let goOn = { (index: Int, why: String) -> Bool in
                    hands.yieldFront()
                    if case .yes = ask(ArisTeachCopy.goOnCard(procedure, failedAt: index, why: why, english: english), [], ArisTeachCopy.goOnAllow(english: english)) { return true }
                    return false
                }
                hands.beginFrontHold()
                defer { hands.endFrontHold() }
                ArisTeachRunNames.shared.note(session: "teach-" + run, name: procedure.name)
                var replay = ArisTeachRunner()
                let unchecked = ArisTeachRunEnd.Unchecked()
                let placed = ArisTeachRunEnd.Placed()
                let execute = replay.execute
                replay.execute = { item, read, caller in
                    let result = execute(item, read, caller)
                    unchecked.note(call: item.call.name, result: result)
                    placed.note(call: item.call.name, beginsLine: ArisTeachRunEnd.beginsLine(read.arguments), result: result)
                    return result
                }
                // His yes on the run's one card (a clean turn only: `runCard`), for exactly the plan with the values he left there.
                let pass = once.withLock { $0 } ? ArisTeachRunPass(plan: ArisTeachReplay.plan(procedure, given: given, words: words, run: run)) : nil
                // A model started this run: who spoke the turn reaches every step's decision, and what the conversation
                // read is the replay's too. In a clean turn its steps are approved ahead as a run by its name (so a step's
                // own taught words don't rate it as driven by content), and it carries the pass of the run's one card
                // when that card was shown; in a turn that read outside text none is approved ahead and there is no
                // pass: every step that asks gets its own card.
                let ended = replay.run(procedure, words: words, rest: "", answered: given, run: run, card: card,
                                       isCurrent: { runner.messageSnapshot().active }, goOn: goOn, english: english, pass: pass,
                                       speaker: now.speaker, approvesAhead: clean || upFront.withLock { $0 }, carrying: session)
                return Ended(outcome: ended.outcome, unchecked: unchecked.apps, sameLine: placed.sameLine)
            },
            english: english)
        ports.upFrontYes = { upFront.withLock { $0 = true } }
        ports.lastValues = { ArisTeachLastValues.load($0, file: last) }
        ports.noteValues = { ArisTeachLastValues.note($0, values: $1, file: last) }
        // As a run by its name (ArisTeachTurn.replay): asked only when it stands in for at least one step's own card.
        ports.runCard = { procedure, words, given, missing in
            guard clean else { return nil }
            let drafted = ArisTeachReplay.plan(procedure, given: given.merging(Dictionary(uniqueKeysWithValues: missing.map { ($0.key, $0.example) })) { $1 },
                                               words: words, run: run)
            let marks = ArisTeachRunner().marks(drafted)
            guard ArisTeachRunPass.asksOnce(marks) else { return nil }
            once.withLock { $0 = true }
            let whole = ArisTeachCopy.runCard(procedure, plan: drafted, marks: marks, missing: missing, last: ArisTeachLastValues.load(procedure.id, file: last),
                                              english: english)
            return (whole.card, whole.fields)
        }
        return ports
    }
}
