// Tests for jv-vmfix11, the eighth VM run (aris-vmcheck notes8/*, cap8/*): the parts of its defects that live in
// the helper and the app (the pure ones are in Tests/ArisCoreTests/ArisTeachVM8Tests; the drawn cards in
// card-text-render/check.sh). Each check is tied to what the VM recorded.
// Called from main.swift; uses its check().
import Foundation

private let vmfix11Root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private func vmfix11Source(_ path: String) -> String { (try? String(contentsOf: vmfix11Root.appendingPathComponent(path), encoding: .utf8)) ?? "" }

func runVmfix11Tests() {
    vmfix11CardHoldTests()
    vmfix11PromptCardTests()
    vmfix11WindowOrderTests()
    vmfix11WordingTests()
    vmfix11UninstallTests()
}

// MARK: - 6: wording

private func vmfix11WordingTests() {
    typealias T = ArisTagProgress
    // cap8/W1-after-Continue.jpg, W2-burst-montage.jpg: "Doing “랩 메모” ✓" after the job, "Doing “랩 메모” !" after a failure.
    check(T.settled("Doing “랩 메모”", failed: false) == "Finished “랩 메모”" && T.settled("Doing “랩 메모”", failed: true) == "“랩 메모” didn't finish",
          "vmfix11 6: a settled tag of saved steps says finished or didn't finish, never Doing (English)")
    check(T.settled("‘랩 메모’ 하는 중", failed: false) == "‘랩 메모’ 했어요" && T.settled("‘랩 메모’ 하는 중", failed: true) == "‘랩 메모’ 못 끝냈어요",
          "vmfix11 6: the same in Korean")
    check(T.settled("Typing", failed: false) == "Typing" && T.settled("날씨 보는 중", failed: true) == "날씨 보는 중", "vmfix11 6: any other status is left as it is")
    // The tag as the app has it after a run: its status in the UI's language, its count split off.
    for english in [true, false] {
        let words = T.split(ArisUIWords.status(ArisRoutineProgress.line(step: 3, total: 3, text: "‘랩 메모’ 하는 중"), english: english)).words
        check(!T.settled(words, failed: false).contains("Doing") && !T.settled(words, failed: false).contains("하는 중") && T.settled(words, failed: false) != words,
              "vmfix11 6: the run's own status line settles into finished wording (\(T.settled(words, failed: false)))")
    }
    check(vmfix11Source("Aris/private/Aris/Home/ArisActivityTag.swift").contains("if settled { return ArisTagProgress.settled(status.words, failed: failed) }"),
          "vmfix11 6: wiring: the tag draws a settled step with its settled words")
    // cap8/D6-undoA-done.jpg: "Undid “run8 물 사기” (To-do added)."
    check(ArisUndoWords.doneLine("할 일 추가: run8 물 사기", korean: false) == "I took back the to-do “run8 물 사기”."
          && ArisUndoWords.doneLine("할 일 추가: run8 물 사기", korean: true) == "‘run8 물 사기’ 할 일을 되돌렸어요.",
          "vmfix11 6: an undo's reply reads as a sentence in English (\(ArisUndoWords.doneLine("할 일 추가: run8 물 사기", korean: false)))")
    check(ArisActivityWords.kinds.allSatisfy { kind in ArisUndoWords.englishNouns[String(ArisActivityWords.english(kind + ": x").dropLast(3))] != nil },
          "vmfix11 6: every kind the log writes has its English name for that sentence")
    // The undo card of a replace (cap8/O1-undo-card.jpg): named as a replace, in both languages.
    check(ArisUndoWords.whole("앱의 글 바꿈: TextEdit", korean: false) == "Replaced text in an app: TextEdit" && ArisUndoWords.whole("앱의 글 바꿈: TextEdit", korean: true) == "앱의 글 바꿈: TextEdit",
          "vmfix11 6: a replace's line on the undo card says it was a replace")
    // notes8/R1u-record.jsonl: {"kind":"undone", …, "result":"TextEdit에 입력한 글을 지웠어요"} in the English UI, the lesson not named.
    let names = ArisTeachRunNames()
    names.note(session: "teach-9821def6", name: "줄 추가")
    let recipe = ArisUndoRecipe.textInserted(app: "TextEdit", element: "{}", before: "")
    let step = ArisRecordEntry.call(at: Date(), session: "teach-9821def6", task: nil, capability: "app.type", effect: .changeReversible, provenance: .content(ArisContentSource(kind: "app", source: "TextEdit")),
                                    decision: .runWithUndo(announce: true), arguments: [ArisKeyArgument(kind: .app, value: "TextEdit")], result: "{}", ok: true, undo: recipe)
    check(ArisRecord.journalLine("TextEdit에 입력한 글을 지웠어요", entry: step, recipe: recipe, english: true, names: names) == "Removed the text I typed in TextEdit for “줄 추가”"
          && ArisRecord.journalLine("TextEdit에 입력한 글을 지웠어요", entry: step, recipe: recipe, english: false, names: names) == "‘줄 추가’에서 TextEdit에 입력한 글을 지웠어요",
          "vmfix11 6: the journal's undo line follows the UI's language and names the lesson")
    check(ArisRecord.journalLine("a.txt 휴지통으로 옮겼어요", entry: step, recipe: .fileCreated(path: "/Users/x/a.txt"), english: true, names: names) == "a.txt 휴지통으로 옮겼어요",
          "vmfix11 6: any other undo's line is as its recipe says it")
    check(vmfix11Source("ArisAgent/Trust/ArisTrustGate.swift").contains("ArisJournalWords.declined(english: ArisSkillLanguage.english)") && !vmfix11Source("ArisAgent/Trust/ArisTrustGate.swift").contains("주인이 거절")
          && vmfix11Source("ArisAgent/Record/ArisRecord.swift").contains("write(.undone(entry.id, at: now, result: journalLine(line, entry: entry, recipe: recipe)), home: home)"),
          "vmfix11 6: wiring: a declined call and an undo are written to the journal in the UI's language")
}

// MARK: - 9: the uninstall sheet says the sandbox folder's note once

private func vmfix11UninstallTests() {
    // cap8/U3b-after-14s.jpg: the sandbox row's own line ("macOS가 지켜서 …", 직접 지워요) and the same again in red under the list.
    let lines = ArisUninstallReply.leftLines(failedRows: ["sandbox"], titles: [], oldHelper: true)
    check(!lines.contains(ArisUninstallReply.sandboxLine) && !lines.contains { $0.contains("Containers") } && lines == [ArisUninstallReply.oldRowsLine],
          "vmfix11 9: the sandbox folder is said once, in its own row (\(lines))")
    check(ArisUninstallReply.notRemovable.contains("sandbox") && ArisUninstallReply.mark("sandbox", index: 7, done: 8, kept: false, failed: ["sandbox"]) == .byHand
          && ArisUninstallReply.sandboxBefore.contains("~/Library/Containers/com.lumenjsn.aris"),
          "vmfix11 9: its row still says it can't be removed and what to do")
    check(ArisUninstallReply.leftLines(failedRows: ["permissions"], titles: [], oldHelper: true).contains(ArisUninstallReply.permissionsLine), "vmfix11 9: a row that failed still gets its line")
}

// MARK: - 3: a card doesn't wait behind Aris's own voice

private func vmfix11PromptCardTests() {
    // notes8/W2-full.log: "speaking" at 23:04:42.087 (the failed step's sentence), "spoke" at 51.992, and only then
    // "asking you": the go-on card came up ten seconds after the failure was on screen.
    check(ArisCardWait.upWhileSpeaking(countdown: false) && !ArisCardWait.upWhileSpeaking(countdown: true),
          "vmfix11 3: a card comes up while Aris finishes its sentence; a dictated message's countdown still says its line first")
    let controller = vmfix11Source("Aris/private/Aris/ArisController.swift"), tasks = vmfix11Source("Aris/private/Aris/ArisController+Tasks.swift")
    check(controller.contains("let said = ArisCardWait.upWhileSpeaking(countdown: ask.countdown) ? speaking : nil\n                if said == nil, let speaking { await speak { await speaking.value } }")
          && controller.contains("await askUser(ask, handsFree: turnHandsFree, waiter: true, ownerContent: ownerContent, after: said)"),
          "vmfix11 3: wiring: the turn hands what is still being said to the card instead of waiting for it")
    let shown = tasks.range(of: "setSession(session.asking(ask))\n        // Its click hold starts now"), finished = tasks.range(of: "await speak { await after.value }")
    let question = tasks.range(of: "await speak { await self.speaker.speak(ArisConfirmReply.question(for: ask")
    check(shown != nil && finished != nil && question != nil && shown!.upperBound < finished!.lowerBound && finished!.upperBound < question!.lowerBound,
          "vmfix11 3: wiring: the card is up (its hold running) before the sentence is finished, and its question is read after")
    let between = finished.flatMap { from in question.map { String(tasks[from.upperBound..<$0.lowerBound]) } } ?? ""
    check(between.contains("kernel.takeOutcome(key)") && between.contains("if let answered = settled(during) { return answered }") && between.contains("guard cardUp(ask) else { return covered() }"),
          "vmfix11 3: wiring: an answer given while the sentence is read is taken then, and a covered or ended card answers nothing")
}

// MARK: - 5: his app's window is on top again

private func vmfix11WindowOrderTests() {
    let selectAll: ArisApps.JSON = .object(["app": .string("TextEdit"), "command": .string("=Edit › Select All [cmd+a]")])
    // cap8/F1-flicker.jpg: Finder in front, Select All brought TextEdit forward, Finder was made active again, and
    // TextEdit's window stayed above Finder's.
    do {
        let (hands, system) = v10Hands()
        hands.beginFrontHold()
        _ = hands.call("app.do", selectAll)
        system.switchTo(system.aris.pid)
        hands.yieldFront()
        check(system.activated == [system.editor.pid, system.finder.pid] && system.raised == [system.finder.pid],
              "vmfix11 5: when his app goes back in front, its own window is raised too (activated \(system.activated), raised \(system.raised))")
        hands.endFrontHold()
        check(system.raised == [system.finder.pid], "vmfix11 5: nothing is raised again when nothing was brought forward since")
    }
    // He switched himself, or nothing was brought forward: no window of anyone is raised.
    do {
        let (hands, system) = v10Hands()
        hands.beginFrontHold()
        _ = hands.call("app.do", selectAll)
        system.switchTo(system.safari.pid)
        hands.endFrontHold()
        let (idle, idleSystem) = v10Hands()
        idle.beginFrontHold()
        idle.yieldFront()
        idle.endFrontHold()
        check(system.raised.isEmpty && idleSystem.raised.isEmpty, "vmfix11 5: an app he went to himself keeps its place, and with nothing brought forward nothing is raised")
    }
    let live = vmfix11Source("ArisAgent/Apps/ArisAppsLive.swift")
    check(live.contains("func raiseMainWindow(pid: Int32)") && live.contains("kAXRaiseAction") && !live.contains("CGEvent"),
          "vmfix11 5: the raise is Accessibility's own (no pointer or key event, no new permission)")
}

// MARK: - 2: the card's hold counts from when the card is drawn, and a press during it is answered, never kept

private func vmfix11CardHoldTests() {
    typealias H = ArisCardHold
    check(H.hold == 0.5, "vmfix11 2: the hold is half a second (the owner's say of 2026-11-19) (\(H.hold))")
    // notes8/T3-aris.log and T3-watch.txt: the card was asked at 23:17:26.371 (its hold started there, at its layout),
    // its label was first on screen at 26.637, and the button woke at about 27.48: 0.85 s of a one-second guard.
    let asked = 26.371, labelSeen = 26.637
    let laidOut = H().shown("step2", at: asked).framed(card: "step2", CGRect(x: 4, y: 60, width: 432, height: 140), at: asked + 0.01)
    let entering = laidOut.entering(card: "step2", at: asked + 0.01)
    check((entering.readyAt ?? 0) - labelSeen >= H.hold,
          "vmfix11 2: a card that fades in is held for the whole hold after it was seen (ready \(entering.readyAt ?? 0), label seen \(labelSeen))")
    check(!entering.clickCounts(card: "step2", at: labelSeen + H.hold - 0.01) && !entering.clickCounts(card: "step2", at: asked + H.hold),
          "vmfix11 2: a press sooner than one hold after the label appeared is not taken")
    check(entering.clickCounts(card: "step2", at: asked + 0.01 + H.entry + H.hold), "vmfix11 2: it counts one hold after the card was fully drawn")
    // The view's first layout measured after it came in doesn't pull the hold earlier; entering twice doesn't either.
    let measured = H().shown("a", at: 10).entering(card: "a", at: 10).framed(card: "a", CGRect(x: 0, y: 0, width: 10, height: 10), at: 10.05)
    check(measured.readyAt == 10 + H.entry + H.hold && measured.entering(card: "a", at: 10.1).readyAt == 10.1 + H.entry + H.hold
          && measured.entering(card: "other", at: 50) == measured,
          "vmfix11 2: a layout during the fade-in starts the hold no earlier; another card's view changes nothing")
    // A card that moves later is held again from then, as before.
    check(measured.framed(card: "a", CGRect(x: 0, y: 40, width: 10, height: 10), at: 30).readyAt == 30 + H.hold, "vmfix11 2: a card that moved is held again")
    // A press during the hold: not taken, not kept, the hold unchanged; the card says so until a moment after the hold.
    let pressed = entering.refused(card: "step2", at: labelSeen + 0.3)
    check(pressed.readyAt == entering.readyAt && !pressed.clickCounts(card: "step2", at: labelSeen + 0.31),
          "vmfix11 2: a press during the hold neither shortens nor answers it")
    check(pressed.noteShows(card: "step2", at: labelSeen + 0.31) && pressed.noteShows(card: "step2", at: (pressed.readyAt ?? 0) + H.noteStay - 0.01)
          && !pressed.noteShows(card: "step2", at: (pressed.readyAt ?? 0) + H.noteStay + 0.01) && !pressed.noteShows(card: "other", at: labelSeen + 0.31)
          && !entering.noteShows(card: "step2", at: labelSeen + 0.31),
          "vmfix11 2: the not-taken note shows from the press until a moment after the hold, for that card only")
    check(pressed.shown("step3", at: 40).noteUntil(card: "step3") == nil, "vmfix11 2: the next card starts with no note")
    let controller = vmfix11Source("Aris/private/Aris/ArisController.swift")
    let ignored = controller.range(of: "ArisCardStill.shared.refusedClick(card: question.id)\n            return")
    let taken = controller.range(of: "kernel.answerCard(question.id, allow: allow)")
    let still = vmfix11Source("Aris/private/Aris/Home/ArisCardStill.swift")
    check(ignored != nil && taken != nil && ignored!.upperBound < taken!.lowerBound && !still.contains("answerQuestion") && !still.contains("answerCard"),
          "vmfix11 2: wiring: the early press returns before the answer is taken, and nothing in the hold ever answers a card")
    check(still.contains(".onAppear { ArisCardStill.shared.entering(card: id) }"), "vmfix11 2: wiring: every card's view tells its hold when it comes in")
    let card = vmfix11Source("Aris/private/Aris/Home/ArisConfirmCard.swift"), countdown = vmfix11Source("Aris/private/Aris/Home/ArisConfirmCard+Countdown.swift")
    let stopped = vmfix11Source("Aris/private/Aris/Home/ArisStoppedCard.swift")
    check(card.contains(".easeOut(duration: ArisCardHold.entry)"), "vmfix11 2: the card's fade-in is as long as the hold takes it to be")
    check(card.contains(".background(HeldGlass(held: held))") && countdown.contains(".background(HeldGlass(held: held))") && card.contains("static let heldOpacity: Double = 0.5")
          && card.contains("ArisDarkGlassButton().opacity(held ? 0 : 1)"),
          "vmfix11 2: a held yes has no glass and half-strength words (cap8/T1-pair.jpg: at 0.75 with its glass it read as ready)")
    check(card.contains("notTakenNote(english: english)") && countdown.contains("notTakenNote(english: countdownEnglish)") && stopped.contains("ArisConfirmWords.notYet(english: english)"),
          "vmfix11 2: each card's footer shows the not-taken note")
    check([card, countdown, stopped, still].allSatisfy { !$0.contains("repeatForever") && !$0.contains("autoreverses") }, "vmfix11 2: nothing blinks or pulses")
    check(ArisConfirmWords.notYet(english: true) == "Not taken yet. Press again in a moment." && ArisConfirmWords.notYet(english: false) == "아직 안 눌렸어요. 잠시 뒤 다시 눌러 주세요.",
          "vmfix11 2: the note's words, both languages")
}
