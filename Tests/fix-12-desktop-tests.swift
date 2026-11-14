// Tests for fix-12, the desktop parts (the eighth VM pass on 7a0a7b60): while an action's card waits (a job's
// parked in 확인 대기 too) no second card goes up for that app and no new look is taken there, and the yes acts on its
// control found again in a fresh look; a password dialog of another process pauses a step instead of ending it, and an
// element click checks for a sign-in or permission prompt first; "끝에" puts the caret at the end before typing; a
// saved-steps replay never asks more cards than the live run did. On desktop-v2-tests' rig (fake Peekaboo, recorded
// fixtures); nothing touches a real app or the screen. Called from main.swift; uses its check().
import CoreGraphics
import Foundation

func runFix12DesktopTests() {
    fix12OneCardTests()
    fix12RefindTests()
    fix12ParkedAnswerTests()
    fix12SecurePauseTests()
    fix12PromptClickTests()
    fix12CaretTests()
    fix12ReplayCardsTests()
}

/// see-chat with the focus on its Message field (elem_59), holding `value` with the caret at `caret`.
private func fix12Chat(_ value: String, caret: Int) -> Data {
    guard var object = (try? JSONSerialization.jsonObject(with: v2pb("see-chat"))) as? [String: Any], var data = object["data"] as? [String: Any] else { return Data() }
    data["focused_element"] = ["frame": [[461, 1015], [586, 24]], "processIdentifier": 4242, "role": "AXTextField", "windowID": 9189]
    var list = data["ui_elements"] as? [[String: Any]] ?? []
    for index in list.indices where list[index]["id"] as? String == "elem_59" {
        list[index]["value"] = value
        list[index]["selected_text_range"] = ["location": caret, "length": 0]
    }
    data["ui_elements"] = list
    object["data"] = data
    return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
}

/// A job that looked at the bench and clicked its 엄마 row: the click's card is parked. The rig, the job, the row's ref.
private func fix12Parked(lock: ArisDesktopLock? = nil, looksTwice: Bool = false) -> (V2Rig, V2Turn, String, V2Box, DispatchSemaphore)? {
    let rig = V2Rig(lock: lock)
    let job = V2Turn()
    job.isTask = true
    job.parks = true
    job.request = "백그라운드로 Aris Testbench에서 엄마 눌러 줘"
    rig.queue([("see", "see-messenger")])
    guard let row = rig.ref("엄마", in: rig.run(["see", "--app", "Aris Testbench"], turn: job).output) else { return nil }
    if looksTwice {
        // A newer look of the same window before the card went up: the row's ref is no longer its window's latest.
        rig.queue([("see", "see-messenger")])
        _ = rig.run(["see", "--app", "Aris Testbench"], turn: job)
    }
    let box = V2Box()
    let finished = DispatchSemaphore(value: 0)
    DispatchQueue.global().async { rig.engine.handle(["click", row], text: nil, turn: job) { box.set($0); finished.signal() } }
    let deadline = Date().addingTimeInterval(10)
    while !job.isParked && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
    return job.isParked ? (rig, job, row, box, finished) : nil
}

// MARK: - 2. One action, one card

private func fix12OneCardTests() {
    guard let (rig, job, row, box, finished) = fix12Parked() else { return check(false, "fix-12 one card: the job's click parks its card") }
    check(job.ledger.cardWaits(v2Bench.readKey) && job.ledger.anyCardWaits, "fix-12 one card: the ledger knows a card waits for the bench")
    let looks = rig.calls.filter { $0.hasPrefix("see") }.count
    // The job brain looks again while its card waits (the API brain gave up after 130 s): no new look is taken.
    let again = rig.run(["see", "--app", "Aris Testbench"], turn: job)
    check(again.status != 0 && again.output == ArisDesktopEngine.cardWaitingLine(app: "Aris Testbench") && again.output.contains("do not retry")
          && rig.calls.filter { $0.hasPrefix("see") }.count == looks,
          "fix-12 one card: a look at the app while its card waits is answered 'waiting for the owner's answer — do not retry', nothing looked at")
    // And clicks again: no second card for the same pending action (it showed two).
    let twice = rig.run(["click", row], turn: job)
    check(twice.status != 0 && twice.output.contains("do not retry") && job.cards.count == 1 && !rig.calls.contains { $0.hasPrefix("click") },
          "fix-12 one card: a second click while the card waits shows no second card and does nothing")
    // Another conversation's own look at the app isn't held up by this job's card.
    let chat = V2Turn()
    rig.queue([("see", "see-messenger")])
    check(rig.run(["see", "--app", "Aris Testbench"], turn: chat).status == 0, "fix-12 one card: only the turn whose card waits holds back (another turn looks as usual)")
    // The yes: the click runs once, and the app is the job's again.
    rig.queue([("see", "see-messenger"), ("click", "click-row"), ("see", "see-chat")])
    job.answerParked(.yes([:]))
    _ = finished.wait(timeout: .now() + 20)
    check(box.value?.status == 0 && rig.calls.filter { $0.hasPrefix("click") }.count == 1 && !job.ledger.cardWaits(v2Bench.readKey),
          "fix-12 one card: the yes to the parked card does the click, once (\(box.value?.output.prefix(100) ?? "no answer"))")
}

// MARK: - 2. The yes acts on its control found again

private func fix12RefindTests() {
    guard let (rig, job, _, box, finished) = fix12Parked(looksTwice: true) else { return check(false, "fix-12 refind: the job's click parks its card") }
    rig.queue([("see", "see-messenger"), ("click", "click-row"), ("see", "see-chat")])
    job.answerParked(.yes([:]))
    _ = finished.wait(timeout: .now() + 20)
    let outcome = box.value
    check(outcome?.status == 0 && outcome?.output.contains("older look") == false && rig.calls.contains { $0.hasPrefix("click --on elem_32") },
          "fix-12 refind: the user's yes acts on the row found again (role, label, containers) in a fresh look, not 'That ref is from an older look' (\(outcome?.output.prefix(100) ?? "none"))")
    // The same with nothing to find: nothing done, said plainly.
    guard let (gone, goneJob, _, goneBox, goneDone) = fix12Parked(looksTwice: true) else { return check(false, "fix-12 refind: the second job parks") }
    gone.queue([("see", "see-form")])
    goneJob.answerParked(.yes([:]))
    _ = goneDone.wait(timeout: .now() + 20)
    check(goneBox.value?.status == 1 && goneBox.value?.output.contains("isn't there any more") == true && !gone.calls.contains { $0.hasPrefix("click") },
          "fix-12 refind: a control that isn't in the fresh look any more is not clicked")
    // Without a card of its own (a ref used stale by the brain), the stale guard holds as before.
    let plain = V2Rig()
    let turn = V2Turn()
    turn.request = "Aris Testbench에서 엄마 눌러 줘"
    plain.queue([("see", "see-messenger")])
    guard let row = plain.ref("엄마", in: plain.run(["see", "--app", "Aris Testbench"], turn: turn).output) else { return check(false, "fix-12 refind: the plain row") }
    turn.ledger.remember(v2Bench.memoryKey ?? "", tainted: false)
    plain.queue([("see", "see-messenger")])
    _ = plain.run(["see", "--app", "Aris Testbench"], turn: turn)
    plain.queue([("see", "see-messenger")])
    let stale = plain.run(["click", row], turn: turn)
    check(stale.status == 1 && stale.output.contains("older look") && turn.cards.isEmpty, "fix-12 refind: a stale ref with no card of its own is still refused")
}

// MARK: - 2. A no or a timeout tells the job plainly

private func fix12ParkedAnswerTests() {
    for (answer, line) in [(ArisMCPAnswer.no, ArisDesktopEngine.noLine), (.unanswered, ArisDesktopEngine.unansweredLine)] {
        guard let (rig, job, _, box, finished) = fix12Parked() else { return check(false, "fix-12 parked: the job parks") }
        job.answerParked(answer)
        _ = finished.wait(timeout: .now() + 10)
        check(box.value?.status == 1 && box.value?.output == line && !rig.calls.contains { $0.hasPrefix("click") } && !job.ledger.anyCardWaits,
              "fix-12 parked: \(answer == .no ? "a no" : "no answer in time") tells the job plainly, nothing done, and the app is free again")
        rig.queue([("see", "see-messenger")])
        check(rig.run(["see", "--app", "Aris Testbench"], turn: job).status == 0, "fix-12 parked: after the answer the job may look again")
    }
}

// MARK: - 4a. A password dialog of another process pauses the step

private func fix12SecurePauseTests() {
    typealias P = ArisDesktopPause
    check(P.secureElsewhere(secure: true, owner: 777, target: 4242, prompt: nil, aimedAtSecret: false)
          && P.secureElsewhere(secure: true, owner: nil, target: 4242, prompt: "SecurityAgent", aimedAtSecret: false)
          && !P.secureElsewhere(secure: true, owner: 4242, target: 4242, prompt: nil, aimedAtSecret: false)
          && !P.secureElsewhere(secure: true, owner: nil, target: 4242, prompt: nil, aimedAtSecret: false)
          && !P.secureElsewhere(secure: true, owner: 777, target: 4242, prompt: nil, aimedAtSecret: true)
          && !P.secureElsewhere(secure: false, owner: 777, target: 4242, prompt: nil, aimedAtSecret: false),
          "fix-12 secure pause: secure input counts as elsewhere when its field is another process's (or a system auth prompt is up), never for a step aimed at a password field")
    let lock = ArisDesktopLock(waitLimit: 5, idleHold: 30, poll: 0.02)
    let rig = V2Rig(lock: lock, pause: ArisDesktopPause.Policy(limit: 5, poll: 0.1))
    rig.apps.secureInput = true
    rig.apps.secureOwner = 777
    let turn = V2Turn()
    turn.request = "Aris Testbench에서 탭 눌러 줘"
    rig.queueData([("see", v2pb("see-before-export")), ("press", v2pb("press-return")), ("see", v2pb("see-after-press"))])
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) { rig.apps.secureInput = false }
    let pressed = rig.run(["press", "tab", "--app", "Aris Testbench"], turn: turn)
    check(turn.quiet.contains("로그인/권한 창을 처리해 주세요 — 끝나면 이어서 할게요") && pressed.status == 0 && pressed.output.contains("Aris paused")
          && rig.calls.filter { $0.hasPrefix("press") }.count == 1 && !lock.state.paused,
          "fix-12 secure pause: a system password dialog up pauses the step (the line in the notch), then it runs once it is gone (\(pressed.output.prefix(90)))")
    // The target's own password field: refused as before, nothing pressed.
    let own = V2Rig(lock: ArisDesktopLock(waitLimit: 5, idleHold: 30, poll: 0.02), pause: ArisDesktopPause.Policy(limit: 5, poll: 0.1))
    own.apps.secureInput = true
    own.apps.secureOwner = 4242
    let refused = own.run(["press", "tab", "--app", "Aris Testbench"], turn: V2Turn())
    check(refused.status == 1 && refused.output.contains(ArisDesktopGate.secureRefusal) && !own.calls.contains { $0.hasPrefix("press") },
          "fix-12 secure pause: secure input from the target app itself still refuses at once")
}

// MARK: - 4b. An element click checks for a prompt first

private func fix12PromptClickTests() {
    let lock = ArisDesktopLock(waitLimit: 5, idleHold: 30, poll: 0.02)
    let rig = V2Rig(lock: lock, pause: ArisDesktopPause.Policy(limit: 5, poll: 0.1))
    let turn = V2Turn()
    turn.request = "Aris Testbench에서 엄마 눌러 줘"
    rig.queue([("see", "see-messenger")])
    guard let row = rig.ref("엄마", in: rig.run(["see", "--app", "Aris Testbench"], turn: turn).output) else { return check(false, "fix-12 prompt click: the row") }
    // Gatekeeper's "Not Opened" is up for the first few looks at the screen, then answered.
    rig.windows.prompt = { $0 <= 4 ? "CoreServicesUIAgent" : nil }
    rig.queue([("see", "see-messenger"), ("click", "click-row"), ("see", "see-chat")])
    let clicked = rig.run(["click", row], turn: turn)
    check(turn.quiet.contains("로그인/권한 창을 처리해 주세요 — 끝나면 이어서 할게요") && clicked.output.contains("Aris paused")
          && rig.calls.filter { $0.hasPrefix("click") }.count == 1,
          "fix-12 prompt click: an element click with a permission prompt up pauses, then clicks once (it ran with Gatekeeper's prompt up)")
    let plain = V2Rig()
    let pt = V2Turn()
    plain.queue([("see", "see-messenger")])
    guard let plainRow = plain.ref("엄마", in: plain.run(["see", "--app", "Aris Testbench"], turn: pt).output) else { return check(false, "fix-12 prompt click: the plain row") }
    plain.windows.prompt = { _ in "CoreServicesUIAgent" }
    let refused = plain.run(["click", plainRow], turn: pt)
    check(refused.output.contains(ArisDesktopSession.promptLine) && !plain.calls.contains { $0.hasPrefix("click") },
          "fix-12 prompt click: with no pause, an element click is refused while a prompt is up")
}

// MARK: - 5a. "끝에": the caret at the end before typing

private func fix12CaretTests() {
    typealias C = ArisDesktopCaret
    check(C.place(in: "TextEdit의 noteB.txt 창 끝에 셋 이라고 입력해 줘") == .end && C.place(in: "메모 맨 뒤에 넷 써 줘") == .end
          && C.place(in: "type 'four' at the end of the note") == .end && C.place(in: "메모 맨 앞에 하나 입력해 줘") == .start
          && C.place(in: "put 'one' at the start of the field") == .start && C.place(in: "type 'one' at the beginning") == .start
          && C.place(in: "TextEdit에 셋 입력해 줘") == nil && C.place(in: "맨 앞에 쓰고 끝에도 써 줘") == nil,
          "fix-12 caret: 끝에 / 맨 뒤 / at the end and 맨 앞 / at the start are read from the request; neither, or both, leaves the caret alone")
    let field = ArisDesktopElement(id: "e", role: "textField", label: "Message", rawValue: "note B")
    var atEnd = field
    atEnd.selectedRange = ArisTextRange(location: 6, length: 0)
    var atStart = field
    atStart.selectedRange = ArisTextRange(location: 0, length: 0)
    check(C.isAt(.end, atEnd) == true && C.isAt(.end, atStart) == false && C.isAt(.start, atStart) == true && C.isAt(.end, field) == nil
          && C.keys(.end) == "cmd+down" && C.keys(.start) == "cmd+up",
          "fix-12 caret: where the caret is, when the field says so; ⌘↓ for the end, ⌘↑ for the start")

    func typed(_ request: String, moved: Bool = true) -> (V2Rig, ArisMCPOutcome) {
        let rig = V2Rig()
        let turn = V2Turn()
        turn.request = request
        rig.queue([("see", "see-chat")])
        let field = rig.ref("Message", in: rig.run(["see", "--app", "Aris Testbench"], turn: turn).output) ?? "@none:e1"
        rig.queueData([("see", v2pb("see-chat")), ("click", v2pb("click-field")), ("see", fix12Chat("note B", caret: 0)), ("press", v2pb("press-return")),
                       ("see", fix12Chat("note B", caret: moved ? 6 : 0)), ("type", v2pb("type-unverified")), ("see", fix12Chat("note B셋", caret: 7))])
        return (rig, rig.run(["type", field, "--stdin"], text: "셋", turn: turn))
    }
    let (end, endOutcome) = typed("Aris Testbench의 Message 칸 끝에 셋 입력해 줘")
    let pressAt = end.calls.firstIndex { $0.hasPrefix("press cmd+down --snapshot") }, typeAt = end.calls.firstIndex { $0.hasPrefix("type --text=셋") }
    check(endOutcome.status == 0 && pressAt != nil && typeAt != nil && pressAt! < typeAt!,
          "fix-12 caret: \"끝에\" moves the caret to the end (⌘↓) before typing (it typed at the start: \"셋note B\") (\(endOutcome.output.prefix(80)))")
    let (stuck, stuckOutcome) = typed("Aris Testbench의 Message 칸 끝에 셋 입력해 줘", moved: false)
    check(stuckOutcome.status == 1 && stuckOutcome.output.contains("caret") && !stuck.calls.contains { $0.hasPrefix("type") },
          "fix-12 caret: a caret that didn't get to the end types nothing")
    let (plain, _) = typed("Aris Testbench의 Message 칸에 셋 입력해 줘")
    check(!plain.calls.contains { $0.hasPrefix("press") } && plain.calls.contains { $0.hasPrefix("type --text=셋") },
          "fix-12 caret: with no such words the caret is left where it is")
}

// MARK: - 5d. A replay never asks more cards than the live run

private func fix12ReplayCardsTests() {
    // The live run: the row's card (the user's yes for the app), then a key pressed on that yes with no card of its own.
    let rig = V2Rig()
    let turn = V2Turn()
    turn.request = "Aris Testbench에서 엄마 열고 탭 눌러 줘"
    rig.queue([("see", "see-messenger")])
    guard let row = rig.ref("엄마", in: rig.run(["see", "--app", "Aris Testbench"], turn: turn).output) else { return check(false, "fix-12 replay: the row") }
    rig.queue([("see", "see-messenger"), ("click", "click-row"), ("see", "see-chat")])
    _ = rig.run(["click", row], turn: turn)
    rig.queue([("see", "see-before-export"), ("press", "press-return"), ("see", "see-after-press")])
    _ = rig.run(["press", "tab", "--app", "Aris Testbench"], turn: turn)
    guard turn.notes.count == 2, case .success(let click) = turn.notes[0], case .success(let press) = turn.notes[1] else {
        return check(false, "fix-12 replay: both live steps are noted (\(turn.notes))")
    }
    check(turn.cards.count == 1 && click.afterYes != true && press.afterYes == true,
          "fix-12 replay: the live run asked one card, and its key step is noted as done on the app's yes")
    guard let recipe = ArisSavedSteps.recipe(key: ArisShortcuts.key(for: turn.request), request: turn.request, notes: turn.notes, outside: true) else {
        return check(false, "fix-12 replay: the turn makes a recipe")
    }
    // The replay starts as tainted as the turn it was learned on: no yes from before it counts.
    let again = V2Rig()
    let replay = V2Turn()
    replay.request = turn.request
    replay.markAppRead("com.example.elsewhere")
    again.queue([("see", "see-messenger"), ("see", "see-messenger"), ("click", "click-row"), ("see", "see-chat"),
                 ("see", "see-before-export"), ("press", "press-return"), ("see", "see-after-press")])
    let outcome = ArisSavedStepsReplay.run(recipe, request: replay.request, engine: again.engine, turn: replay)
    check(outcome == .done(steps: 2) && replay.cards.count == 1 && again.calls.filter { $0.hasPrefix("press tab") }.count == 1,
          "fix-12 replay: the replay asks one card like the live run (its yes covers the key step the live yes covered), not two (\(outcome), \(replay.cards.count) cards)")
    // A key step the live run asked about on its own card asks in the replay too.
    let asked = ArisSavedRecipe(key: recipe.key, request: recipe.request, steps: [click, ArisSavedStep(action: .press, bundle: press.bundle, app: press.app, window: press.window, keys: press.keys)],
                                saved: recipe.saved, outside: true)
    let third = V2Rig()
    let separately = V2Turn()
    separately.request = turn.request
    separately.markAppRead("com.example.elsewhere")
    third.queue([("see", "see-messenger"), ("see", "see-messenger"), ("click", "click-row"), ("see", "see-chat"),
                 ("see", "see-before-export"), ("press", "press-return"), ("see", "see-after-press")])
    check(ArisSavedStepsReplay.run(asked, request: separately.request, engine: third.engine, turn: separately) == .done(steps: 2) && separately.cards.count == 2,
          "fix-12 replay: a step the live run carded on its own is carded in the replay too")
    check(!replay.ledger.replayCovers(v2Bench.memoryKey ?? ""), "fix-12 replay: the replay's grouping ends with its step")
}
