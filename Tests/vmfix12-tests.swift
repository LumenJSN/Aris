// Tests for jv-vmfix12, the ninth VM run (aris-vmcheck notes9/*, cap9/*): the parts of its defects that live in
// the helper and the app (the pure ones are in Tests/ArisCoreTests/ArisTeachVM9Tests and ArisReplayUnansweredTests).
// Each check is tied to what the VM recorded.
// Called from main.swift; uses its check().
import Foundation

private let vmfix12Root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private func vmfix12Source(_ path: String) -> String { (try? String(contentsOf: vmfix12Root.appendingPathComponent(path), encoding: .utf8)) ?? "" }

func runVmfix12Tests() {
    vmfix12WindowOrderTests()
    vmfix12CardDrawnTests()
    vmfix12WordingTests()
    vmfix12UnansweredTests()
    vmfix12DailyUseTests()
}

// MARK: - 2: the window order he had comes back when his app has no key window

private func vmfix12WindowOrderTests() {
    typealias Place = ArisAppsWindowPlace
    typealias Order = ArisAppsWindowOrder
    let selectAll: ArisApps.JSON = .object(["app": .string("TextEdit"), "command": .string("=Edit › Select All [cmd+a]")])
    // cap9/F1-order-quad.jpg: Finder active with only the desktop focused; two Finder windows lay over TextEdit's
    // document. After the step TextEdit's window stayed above both (raiseMainWindow found no main or focused window).
    let finderFront = Place(pid: 501, x: 80, y: 120, width: 900, height: 420), finderBack = Place(pid: 501, x: 50, y: 90, width: 900, height: 420)
    let document = Place(pid: 701, x: 20, y: 60, width: 980, height: 600), safariBehind = Place(pid: 601, x: 0, y: 40, width: 1200, height: 800)
    let before = [finderFront, finderBack, document, safariBehind]
    check(Order.toRaise(before: before, brought: [701], skip: []) == [finderBack, finderFront],
          "vmfix12 2: the windows that lay over the app brought forward are raised again, the backmost first (\(Order.toRaise(before: before, brought: [701], skip: [])))")
    check(Order.toRaise(before: [document, finderFront], brought: [701], skip: []).isEmpty, "vmfix12 2: an app whose window was on top already has nothing over it to put back")
    check(Order.toRaise(before: [Place(pid: 900, x: 0, y: 0, width: 600, height: 300), finderFront, document], brought: [701], skip: [900]) == [finderFront],
          "vmfix12 2: a window of Aris itself is never raised")
    check(Order.toRaise(before: [finderFront, finderBack], brought: [701], skip: []) == [finderBack, finderFront],
          "vmfix12 2: an app that had no window on screen leaves every window that was there over it")
    let many = (0..<30).map { Place(pid: 501, x: Double($0), y: 0, width: 300, height: 300) }
    check(Order.toRaise(before: many + [document], brought: [701], skip: []) == Array(many.prefix(Order.most).reversed()), "vmfix12 2: no more than the frontmost \(Order.most) are raised")
    do {
        let (hands, system) = v10Hands()
        system.order = before
        hands.beginFrontHold()
        _ = hands.call("app.do", selectAll)
        // The step raised TextEdit; the list now reads otherwise, and must not be what is put back.
        system.order = [document, finderFront, finderBack, safariBehind]
        system.switchTo(system.aris.pid)
        hands.yieldFront()
        check(system.raisedWindows == [[finderBack, finderFront]], "vmfix12 2: his windows as they were before the step are raised again (\(system.raisedWindows))")
        check(system.moves == ["activate \(system.editor.pid)", "raise", "activate \(system.finder.pid)"],
              "vmfix12 2: they are raised before his app is made active, so it keeps the focus it had (\(system.moves))")
        hands.endFrontHold()
        check(system.raisedWindows.count == 1, "vmfix12 2: nothing is raised again when nothing was brought forward since")
    }
    // He switched himself meanwhile: no window of anyone is moved.
    do {
        let (hands, system) = v10Hands()
        system.order = before
        hands.beginFrontHold()
        _ = hands.call("app.do", selectAll)
        system.switchTo(system.safari.pid)
        hands.endFrontHold()
        check(system.raisedWindows.isEmpty && system.raised.isEmpty, "vmfix12 2: an app he went to himself keeps its place")
    }
    let live = vmfix12Source("ArisAgent/Apps/ArisAppsLive+WindowOrder.swift")
    check(live.contains("kAXRaiseAction") && !live.contains("CGEvent") && !live.contains("CGWarpMouse") && !live.contains("CGWindowListCreateImage") && !live.contains("kCGWindowName"),
          "vmfix12 2: wiring: windows are raised by Accessibility alone: no pointer or key event, no picture, no window title")
}

// MARK: - 4: the hold counts from the first frame the button is drawn

private func vmfix12CardDrawnTests() {
    typealias H = ArisCardHold
    // notes9/H6-clk.txt, stage S3 (the step-3 card, which comes whole as the notch grows): the last sample without the
    // yes label at 01:44:35.636, the first with it at 35.671, the press at 36.624 (953 ms) ACCEPTED. notes9/H8c-clk.txt:
    // the same card, a press at 991 ms accepted. The hold had been counted from when the card was laid out, a frame or
    // two before its pixels were on the screen.
    // Laid out three 60 Hz frames before it was seen (the layout is no later than the last sample without the label).
    let firstSeen = 35.671, laidOut = firstSeen - 0.05
    check(H().shown("step3", at: laidOut).clickCounts(card: "step3", at: firstSeen + 0.953),
          "vmfix12 4: (counted from the layout alone, the VM's press at 953 ms is taken: what the VM showed)")
    let waiting = H().shown("step3", at: laidOut).undrawn()
    check(!waiting.clickCounts(card: "step3", at: laidOut + H.hold) && !waiting.clickCounts(card: "step3", at: laidOut + 60) && waiting.readyAt == nil,
          "vmfix12 4: a card whose pixels aren't known to be on screen takes no click-yes, however long it has been laid out")
    let drawn = waiting.drawn(card: "step3", at: firstSeen)
    // (jv-safe10 merge: the hold is the owner's 0.5 s since jv-quick; the VM's two presses came 47 and 9 ms before the
    // 1 s hold of that run ended, and the same distances before today's hold are still not taken.)
    check(!drawn.clickCounts(card: "step3", at: firstSeen + H.hold - 0.047) && !drawn.clickCounts(card: "step3", at: firstSeen + H.hold - 0.009)
          && !drawn.clickCounts(card: "step3", at: firstSeen + H.hold - 0.001) && drawn.clickCounts(card: "step3", at: firstSeen + H.hold),
          "vmfix12 4: the presses of the VM at 953 and 991 ms after the button was first seen are not taken; one full hold after it is")
    check(drawn.readyAt == firstSeen + H.hold && abs(drawn.remaining(at: firstSeen + 0.25) - (H.hold - 0.25)) < 1e-9, "vmfix12 4: the hold's line under the button fills over that same hold")
    check(H.hold == 0.5, "vmfix12 4: the hold's length is the owner's (half a second, jv-quick), unchanged here")
    // Every way a card can come: fading in (its hold already counts from the end of the fade), the notch growing or
    // the card replacing another (its frame changes): each is held from its own drawn frame, never earlier.
    let fading = H().shown("a", at: 10).entering(card: "a", at: 10.01).undrawn().drawn(card: "a", at: 10.06)
    check(fading.readyAt == 10.01 + H.entry + H.hold, "vmfix12 4: a card that fades in is still held from the end of its fade (\(String(describing: fading.readyAt)))")
    let frame = CGRect(x: 0, y: 0, width: 400, height: 200), grown = CGRect(x: 0, y: 0, width: 400, height: 320)
    let growing = H().shown("a", at: 10).undrawn().drawn(card: "a", at: 10.05).framed(card: "a", frame, at: 10.1).undrawn().framed(card: "a", grown, at: 10.4).undrawn()
    check(!growing.clickCounts(card: "a", at: 20) && growing.drawn(card: "a", at: 10.47).readyAt == 10.47 + H.hold,
          "vmfix12 4: a card that grew is held again from the frame its new size was drawn in")
    check(waiting.drawn(card: "other", at: 40) == waiting, "vmfix12 4: another card's frame is not this card's")
    check(waiting.refused(card: "step3", at: 36).drawn(card: "step3", at: 36.1).clickCounts(card: "step3", at: 36.1 + H.hold - 0.1) == false
          && waiting.refused(card: "step3", at: 36).clickCounts(card: "step3", at: 99) == false,
          "vmfix12 4: a press that came early is noted, never kept: it changes nothing of when the button wakes")
    check(H.drawFrames >= 3 && H.frame >= 1.0 / 60, "vmfix12 4: the drawn frame is waited for over several display frames")
    // Wiring: every change of the live hold waits for its frames again, and only that wait wakes the button.
    let still = vmfix12Source("Aris/private/Aris/Home/ArisCardStill.swift")
    check(still.contains("let next = drawn ? next : next.undrawn()") && still.contains("apply(self.hold.drawn(card: card, at: Self.now), drawn: true)")
          && still.contains("for _ in 0..<ArisCardHold.drawFrames"),
          "vmfix12 4: wiring: shown, entering and every frame change start the wait for the drawn frame again")
    check(vmfix12Source("Aris/private/Aris/ArisController.swift").contains("ArisCardStill.shared.refusedClick(card: question.id)\n            return"),
          "vmfix12 4: wiring: an early press is still dropped where it is refused, never queued")
}

// MARK: - 6: wording and polish

private func vmfix12WordingTests() {
    typealias T = ArisTagProgress
    // cap9/D6-todo-after.jpg: the chip "Waiting for Reminders access ✓" under "Added to your to-dos".
    for english in [true, false] {
        let step = ArisPermissionNotice.waitingStep(.reminders, english: english)
        let done = T.settled(step, failed: false), missed = T.settled(step, failed: true)
        check(done != step && missed != step && done != missed && !done.contains("Waiting") && !done.contains("기다리는 중") && !missed.contains("Waiting") && !missed.contains("기다리는 중"),
              "vmfix12 6: once it is settled the permission wait's tag no longer says waiting (\(step) → \(done) / \(missed))")
    }
    check(T.settled("Waiting for Reminders access", failed: false) == "Asked for Reminders access" && T.settled("미리 알림 허용 기다리는 중", failed: false) == "미리 알림 허용 물어봤어요",
          "vmfix12 6: it says the access was asked for, in both languages")
    check(T.settled("Waiting for its turn", failed: false) == "Waiting for its turn", "vmfix12 6: another waiting line is left as it is")
    // cap9/U3b-after-14s.jpg: the red line about an old ‘aris-agent’ row on a Mac that never had the old helper.
    check(ArisUninstallReply.leftLines(failedRows: ["sandbox"], titles: [], oldHelper: false).isEmpty
          && ArisUninstallReply.leftLines(failedRows: ["sandbox"], titles: [], oldHelper: true) == [ArisUninstallReply.oldRowsLine]
          && ArisUninstallReply.leftLines(failedRows: ["permissions"], titles: [], oldHelper: false) == [ArisUninstallReply.permissionsLine],
          "vmfix12 6: the old helper's rows are named only on a Mac that had the old helper")
    let name = "aris-vmfix12-old-rows-\(UUID().uuidString)"
    if let defaults = UserDefaults(suiteName: testSuiteName(name)) {
        check(!ArisUninstallReply.hadOldHelper(defaults), "vmfix12 6: a fresh install never had the old helper")
        defaults.set(true, forKey: ArisHelperInstallWords.oldRowsDueKey)
        check(ArisUninstallReply.hadOldHelper(defaults), "vmfix12 6: a Mac whose old rows became due had it")
        defaults.set(false, forKey: ArisHelperInstallWords.oldRowsDueKey)
        defaults.set(true, forKey: ArisHelperInstallWords.oldRowsSaidKey)
        check(ArisUninstallReply.hadOldHelper(defaults), "vmfix12 6: also once the line about them was said")
        defaults.removePersistentDomain(forName: testSuiteName(name))
    }
    let model = vmfix12Source("Aris/private/Aris/ArisDataModel.swift")
    let read = model.range(of: "let oldHelper = ArisUninstallReply.hadOldHelper(UserDefaults.standard)"), asked = model.range(of: "let reply = await actions.uninstall(")
    check(read != nil && asked != nil && read!.upperBound < asked!.lowerBound, "vmfix12 6: wiring: it is read before anything is removed")
    // cap9/W2-burst-montage.jpg (01:31:24.040): between the failed step and the go-on card the notch stood at "Close".
    let turn = vmfix12Source("ArisAgent/Teach/ArisTeachTurn.swift")
    if let goOn = turn.range(of: "let goOn = { (index: Int, why: String) -> Bool in"), let card = turn.range(of: "stream(.confirm(shown), on: connection)\n                _ = answered.wait") {
        let body = String(turn[goOn.upperBound..<card.lowerBound])
        let yield = body.range(of: "hands.yieldFront()"), said = body.range(of: "for reply in ArisTeachTurnReplies.failed(")
        check(yield != nil && said != nil && yield!.upperBound < said!.lowerBound && body.components(separatedBy: "hands.yieldFront()").count == 2,
              "vmfix12 6: wiring: his app goes back before the failure is said, so the card follows the sentence at once")
    } else {
        check(false, "vmfix12 6: the go-on question is where it was")
    }
    // notes9/W4ko-record.jsonl: "did":"that menu item isn't there now (TextEdit shows ‘Wrap to Window’ instead)" in the Korean UI.
    let failed = #"{"did":"that menu item isn't there now (TextEdit shows ‘Wrap to Window’ instead)","effect":"change-reversible","ok":false,"verified":false}"#
    let korean = ArisJournalWords.failure(failed, english: false)
    check(korean.contains("그 메뉴 항목이 지금은 없어요 (앱에는 ‘Wrap to Window’ 항목이 있어요)") && !korean.contains("isn't there") && korean.contains(#""ok":false"#) && korean.contains(#""effect":"change-reversible""#),
          "vmfix12 6: a failed step's record line says why in Korean in the Korean UI, the rest as it was (\(korean))")
    check(ArisJournalWords.failure(failed, english: true) == failed, "vmfix12 6: in the English UI it is as the app layer wrote it")
    check(ArisJournalWords.failure("not json", english: false) == "not json" && ArisJournalWords.failure(#"{"did":"something new and odd","ok":false}"#, english: false) == #"{"did":"something new and odd","ok":false}"#,
          "vmfix12 6: a result that isn't the app layer's, or a reason with no Korean, is kept as it is")
    check(ArisTeachReplay.failure(korean).contains("그 메뉴 항목이 지금은 없어요"), "vmfix12 6: the line still reads as a failure's reason")
    check(vmfix12Source("ArisAgent/Mind/ArisMindJudge.swift").contains("result.isError ? ArisJournalWords.failure(result.text, english: ArisSkillLanguage.english) : result.text"),
          "vmfix12 6: wiring: the record's line of a failed call is written through it")
}

// MARK: - 3: a card nobody answered (the helper's part)

private func vmfix12UnansweredTests() {
    // notes9/H1-timeout-record.jsonl: {"answer":"unanswered", …, "result":"답이 없었어요 (no answer in time)"} in the English UI.
    let gate = vmfix12Source("ArisAgent/Trust/ArisTrustGate.swift")
    check(gate.contains("none ? ArisJournalWords.unanswered(english: ArisSkillLanguage.english) : ArisJournalWords.declined(english: ArisSkillLanguage.english)") && !gate.contains("no answer in time"),
          "vmfix12 3: wiring: the record's line of an unanswered card is in the UI's language, and never the line of a no")
    let judge = vmfix12Source("ArisAgent/Mind/ArisMindJudge.swift")
    check(judge.contains("if answer == nil { lock.withLock { silent.formUnion(answered.refused.map { key(session, $0) }) } }") && judge.contains("unanswered: { [self] call in unanswered(session: session, call: call) }"),
          "vmfix12 3: wiring: the judge keeps which calls nobody answered and its ports say so")
    check(ArisMindStep.unansweredText.contains("not a no") && ArisMindStep.unansweredText != ArisMindStep.declinedText, "vmfix12 3: the model is told there was no answer, not that he said no")
}

// MARK: - 7: daily use

private func vmfix12DailyUseTests() {
    typealias N = ArisNotch
    // cap9/D7-undo-reply.jpg, K1ko-undo-reply.jpg: an undo's one line, gone a few seconds after it came.
    let undone = "I took back the to-do “run9 물 사기”."
    check(N.endWait(handedOff: false, dictation: false, reply: undone, undo: true) == N.undoStay && N.undoStay > N.readingTime(for: undone)
          && N.endWait(handedOff: false, dictation: false, reply: undone) == N.readingTime(for: undone),
          "vmfix12 7: an undo's answer stays up at least \(N.undoStay), any other answer its reading time as before")
    let long = String(repeating: "되돌릴 수 없는 이유를 길게 말하는 문장이에요. ", count: 8)
    check(N.endWait(handedOff: false, dictation: false, reply: long, undo: true) == N.readingTime(for: long) && N.readingTime(for: long) > N.undoStay,
          "vmfix12 7: a long one keeps its own longer reading time")
    check(N.endWait(handedOff: true, dictation: false, reply: undone, undo: true) == .zero, "vmfix12 7: a hand-off still closes at once")
    let controller = vmfix12Source("Aris/private/Aris/ArisController.swift"), runs = vmfix12Source("Aris/private/Aris/Routing/ArisController+TurnRuns.swift")
    check(runs.contains("answeredUndo = true\n            return await undoLast(") && controller.contains("handedOff = false\n                answeredUndo = false")
          && vmfix12Source("Aris/private/Notch/ArisNotchRoot+Behaviour.swift").contains("undo: controller.answeredUndo))"),
          "vmfix12 7: wiring: the undo turn marks its answer, the next turn clears it, and the notch's end waits by it")
    // cap9/s15-notch.jpg: the notch Aris opened after the setup stood over the desktop whatever was clicked.
    let P = ArisFirstTriesPlan.self
    check(P.closesItself(offered: true, open: true, inTurn: false, pointerOnNotch: false) && !P.closesItself(offered: true, open: true, inTurn: false, pointerOnNotch: true)
          && !P.closesItself(offered: true, open: true, inTurn: true, pointerOnNotch: false) && !P.closesItself(offered: false, open: true, inTurn: false, pointerOnNotch: false),
          "vmfix12 7: the notch Aris opened closes when nobody is on it and no turn has it, never otherwise")
    let tries = vmfix12Source("Aris/private/Aris/Onboarding/ArisFirstTries.swift")
    check(tries.contains("outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in\n            MainActor.assumeIsolated { ArisFirstTries.shared.closeIfLeftAlone() }")
          && tries.contains("if host.notchState != .open { stopWatchingClicks() }") && tries.contains("clocks = []\n        stopWatchingClicks()"),
          "vmfix12 7: wiring: a click in another app closes it by that same rule, and the watch ends with the notch or the offer")
}
