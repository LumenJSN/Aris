// Tests for fix-13, the desktop parts (the ninth VM pass on f8981de4): `aris-tools type` goes the desktop engine's one
// typing way (a look first, the focused field, the caret where 끝에 / 맨 앞 put it, the read-back of where it landed, the
// pause for a password dialog of another process); a saved-steps replay decides its look as the live run's was (and a
// recipe whose look needed the read judge hands over before any card); a background job's launch of an app that already
// runs is done as it is. On desktop-v2-tests' rig (fake Peekaboo, recorded fixtures); nothing touches a real app or the
// screen. Called from main.swift; uses its check().
import CoreGraphics
import Foundation

func runFix13DesktopTests() {
    fix13WordsTests()
    fix13ToolPathTests()
    fix13StartTests()
    fix13NoFieldTests()
    fix13SecurePauseTests()
    fix13ReplayTests()
    fix13JobLaunchTests()
}

/// see-chat with its Message field (elem_59) holding `value`, the caret at `caret` (nil: not told), named `label`
/// (nil: "Message"), and the keyboard focus on it unless `focused` is false (then on nothing).
private func f13Chat(_ value: String, caret: Int?, label: String? = nil, focused: Bool = true) -> Data {
    guard var object = (try? JSONSerialization.jsonObject(with: v2pb("see-chat"))) as? [String: Any], var data = object["data"] as? [String: Any] else { return Data() }
    if focused {
        data["focused_element"] = ["frame": [[461, 1015], [586, 24]], "processIdentifier": 4242, "role": "AXTextField", "windowID": 9189]
    } else {
        data["focused_element"] = NSNull()
    }
    var list = data["ui_elements"] as? [[String: Any]] ?? []
    for index in list.indices where list[index]["id"] as? String == "elem_59" {
        list[index]["value"] = value
        if let label {
            list[index]["label"] = label
            list[index]["description"] = label
        }
        if let caret { list[index]["selected_text_range"] = ["location": caret, "length": 0] }
    }
    data["ui_elements"] = list
    object["data"] = data
    return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
}

/// A turn like V2Turn whose read judge answers `verdict` (a replay has no AI: undecided) and counts how often it is asked.
private final class F13Turn: ArisDesktopTurn {
    let brain: ArisBrain = .claude
    let ledger = ArisComputerUseLedger()
    var brainName: String { "claude" }
    var handsFree = false
    var isTask = false
    var screen = false
    var relayed = false
    var request = ""
    var verdict: ArisReadVerdict = .blocked(.undecided)
    private let lock = NSLock()
    private var read: Set<String> = []
    private var _cards: [ArisMCPCard] = []
    private var _judged = 0
    private var _notes: [Result<ArisSavedStep, ArisSavedStepsRefusal>] = []
    private var steps = 0
    var cards: [ArisMCPCard] { lock.withLock { _cards } }
    var judged: Int { lock.withLock { _judged } }
    var live: Bool { true }
    var taint: ArisTaint { lock.withLock { read.isEmpty ? .none : .outsideText } }
    func taint(forApp app: String) -> ArisTaint { lock.withLock { read.subtracting([app]).isEmpty ? .none : .outsideText } }
    func markAppRead(_ app: String) { lock.withLock { _ = read.insert(app) } }
    func takeOutsideText() {}
    func ask(_ card: ArisMCPCard, answer done: @escaping (ArisMCPAnswer) -> Void) {
        lock.withLock { _cards.append(card) }
        done(.yes([:]))
    }
    func judgeRead(_ call: ArisReadCall, done: @escaping (ArisReadVerdict) -> Void) {
        lock.withLock { _judged += 1 }
        done(verdict)
    }
    func quiet(_ status: String) {}
    func audit(_ fields: [String: String]) {}
    func operating(_ target: ArisOperatingTarget) {}
    func desktopStep() -> Int { lock.withLock { steps += 1; return steps } }
    func noteDesktopAction(_ note: Result<ArisSavedStep, ArisSavedStepsRefusal>) { lock.withLock { _notes.append(note) } }
}

private func f13Run(_ rig: V2Rig, _ words: [String], text: String?, turn: ArisDesktopTurn) -> ArisMCPOutcome {
    let box = V2Box()
    let done = DispatchSemaphore(value: 0)
    DispatchQueue.global().async { rig.engine.handle(words, text: text, turn: turn) { box.set($0); done.signal() } }
    _ = done.wait(timeout: .now() + 60)
    return box.value ?? .failed("no answer")
}

// MARK: - 1. The words

private func fix13WordsTests() {
    let parsed: ArisDesktopRequest? = try? ArisDesktopWords.parse(["type", "--focused", "--app", "TextEdit", "--stdin"], text: "셋").get()
    let fits = parsed.map { request -> Bool in request.focused && request.ref == nil && request.app == "TextEdit" && request.text == "셋" } ?? false
    check(fits, "fix-13 words: `type --focused --app X --stdin` is the engine's type into the focused field (no ref)")
    let noApp: ArisDesktopRequest? = try? ArisDesktopWords.parse(["type", "--focused", "--stdin"], text: "셋").get()
    let noRef: ArisDesktopRequest? = try? ArisDesktopWords.parse(["type", "--app", "TextEdit", "--stdin"], text: "셋").get()
    check(noApp == nil && noRef == nil,
          "fix-13 words: --focused needs --app, and a type with neither a ref nor --focused is still refused")
    guard case .success(let call) = ArisTypeRequest.call(["셋", "--app", "TextEdit"], keyboardApp: "com.apple.Safari") else {
        return check(false, "fix-13 words: aris-tools type makes a call")
    }
    check(call.words == ["type", "--focused", "--app", "TextEdit", "--stdin"] && call.text == "셋",
          "fix-13 words: `aris-tools type '셋' --app TextEdit` is handed to the engine as `desktop type --focused`, the text on stdin")
    guard case .success(let front) = ArisTypeRequest.call(["둘 넷"], keyboardApp: "com.apple.TextEdit") else { return check(false, "fix-13 words: no --app") }
    check(front.words == ["type", "--focused", "--app", "com.apple.TextEdit", "--stdin"] && front.text == "둘 넷",
          "fix-13 words: with no --app the app that has the keyboard is named (never brought forward by aris-tools)")
    func refusal(_ args: [String]) -> String? {
        if case .failure(let why) = ArisTypeRequest.call(args, keyboardApp: nil) { return why.line }
        return nil
    }
    check(refusal(["셋"]) == ArisTypeRequest.noAppLine && refusal(["--app", "TextEdit"]) == ArisTypeRequest.usage,
          "fix-13 words: no app and no text are refused before anything is sent")
    typealias C = ArisDesktopCaret
    let cases: [(C.Place, String, String?, String?, C.Landing)] = [
        (.end, "셋", "note C", "note C셋", .there), (.end, "셋", "note C", "셋note C", .elsewhere),
        (.start, "하나", "셋note C", "하나셋note C", .there), (.start, "하나", "note C", "note C하나", .elsewhere),
        (.end, "셋", nil, "note C셋", .unchecked), (.end, "셋", "note C", nil, .unchecked), (.end, "셋", "", "셋", .there),
        (.end, "셋".decomposedStringWithCanonicalMapping, "a", "a셋", .there),
    ]
    let wrong = cases.filter { C.landing($0.0, text: $0.1, before: $0.2, after: $0.3) != $0.4 }
    check(wrong.isEmpty,
          "fix-13 caret: where the text landed is told from the field before and after (end: what it held, then the text; start: the text, then what it held); unknown is unchecked (\(wrong.map { $0.3 ?? "nil" }))")
}

// MARK: - 2. The pass-9 case through the brain's tool path

private func fix13ToolPathTests() {
    let rig = V2Rig()
    let turn = V2Turn()
    turn.request = "Aris Testbench의 Message 칸 끝에 '셋' 입력해 줘"
    guard case .success(let call) = ArisTypeRequest.call(["셋", "--app", "Aris Testbench"], keyboardApp: nil) else { return check(false, "fix-13 tool path: the call") }
    // The engine's own look, then the type: a fresh look, ⌘↓ (the caret at the start), a look, the keys, the read-back.
    rig.queueData([("see", f13Chat("note B", caret: 0)), ("see", f13Chat("note B", caret: 0)), ("press", v2pb("press-return")),
                   ("see", f13Chat("note B", caret: 6)), ("type", v2pb("type-unverified")), ("see", f13Chat("note B셋", caret: 7))])
    let outcome = rig.run(call.words, text: call.text, turn: turn)
    let calls = rig.calls
    let pressAt = calls.firstIndex { $0.hasPrefix("press cmd+down") }, typeAt = calls.firstIndex { $0.hasPrefix("type --text=셋") }
    check(outcome.status == 0 && pressAt != nil && typeAt != nil && pressAt! < typeAt! && calls.filter { $0.hasPrefix("type") }.count == 1,
          "fix-13 tool path: \"…끝에 '셋' 입력해 줘\" through `aris-tools type` puts the caret at the end before the keys (it typed \"셋note C\") (\(outcome.output.prefix(120)))")
    check(outcome.output.contains(ArisDesktopCaret.Landing.there.line(.end)) && turn.cards.count == 1,
          "fix-13 tool path: the answer says the end was checked, and the type asked one card (the engine's, with the exact text; no second one from the shell gate)")
    // The keys went in, but the field shows them at its start: no success, and never "at the end".
    let wrong = V2Rig()
    let again = V2Turn()
    again.request = turn.request
    wrong.queueData([("see", f13Chat("note B", caret: nil)), ("see", f13Chat("note B", caret: nil)), ("press", v2pb("press-return")),
                     ("see", f13Chat("note B", caret: nil)), ("type", v2pb("type-unverified")), ("see", f13Chat("셋note B", caret: nil))])
    let misplaced = wrong.run(call.words, text: call.text, turn: again)
    check(misplaced.status == 1 && misplaced.output.contains(ArisDesktopCaret.misplacedLead) && !misplaced.output.contains("Checked:")
          && !misplaced.output.contains(ArisDesktopSession.notTypedLead) && wrong.calls.filter { $0.hasPrefix("type") }.count == 1,
          "fix-13 tool path: text that landed at the start after 끝에 is not done, said as typed in the wrong place, never typed again (\(misplaced.output.prefix(120)))")
    // A field that doesn't give its whole text: typed, the place said as unchecked.
    check(ArisDesktopCaret.Landing.unchecked.line(.end).contains("don't say it is at the end"), "fix-13 tool path: an unchecked place is never claimed")
}

// MARK: - 2b. 맨 앞에

private func fix13StartTests() {
    let rig = V2Rig()
    let turn = V2Turn()
    turn.request = "Aris Testbench의 Message 칸 맨 앞에 '하나' 입력해 줘"
    rig.queueData([("see", f13Chat("note B", caret: 6)), ("see", f13Chat("note B", caret: 6)), ("press", v2pb("press-return")),
                   ("see", f13Chat("note B", caret: 0)), ("type", v2pb("type-unverified")), ("see", f13Chat("하나note B", caret: 2))])
    let outcome = rig.run(["type", "--focused", "--app", "Aris Testbench", "--stdin"], text: "하나", turn: turn)
    check(outcome.status == 0 && rig.calls.contains { $0.hasPrefix("press cmd+up") } && outcome.output.contains(ArisDesktopCaret.Landing.there.line(.start)),
          "fix-13 start: 맨 앞에 puts the caret at the start (⌘↑) and the answer says the start was checked (\(outcome.output.prefix(100)))")
}

// MARK: - 2c. No focused field

private func fix13NoFieldTests() {
    let rig = V2Rig()
    let turn = V2Turn()
    turn.request = "Aris Testbench에 셋 입력해 줘"
    rig.queueData([("see", f13Chat("note B", caret: 0, focused: false))])
    let outcome = rig.run(["type", "--focused", "--app", "Aris Testbench", "--stdin"], text: "셋", turn: turn)
    check(outcome.status == 1 && outcome.output.hasPrefix(ArisDesktopEngine.noFocusedFieldLine) && !rig.calls.contains { $0.hasPrefix("type") || $0.hasPrefix("click") }
          && turn.cards.isEmpty,
          "fix-13 no field: with no text field focused nothing is typed or clicked, no card, and the brain is told to type by a ref")
}

// MARK: - 3. A password dialog of another process: pause, nothing typed, then the type

private func fix13SecurePauseTests() {
    let lock = ArisDesktopLock(waitLimit: 5, idleHold: 30, poll: 0.02)
    let rig = V2Rig(lock: lock, pause: ArisDesktopPause.Policy(limit: 5, poll: 0.1))
    rig.apps.secureInput = true
    rig.apps.secureOwner = 777
    let turn = V2Turn()
    turn.request = "Aris Testbench의 Message 칸 끝에 '넷' 입력해 줘"
    rig.queueData([("see", f13Chat("note D", caret: 6)), ("see", f13Chat("note D", caret: 6)), ("type", v2pb("type-unverified")), ("see", f13Chat("note D넷", caret: 7))])
    let typedWhileUp = V2Box()
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) {
        typedWhileUp.set(ArisMCPOutcome(status: rig.calls.contains { $0.hasPrefix("type") } ? 1 : 0, output: ""))
        rig.apps.secureInput = false
    }
    guard case .success(let call) = ArisTypeRequest.call(["넷", "--app", "Aris Testbench"], keyboardApp: nil) else { return check(false, "fix-13 pause: the call") }
    let outcome = rig.run(call.words, text: call.text, turn: turn)
    check(typedWhileUp.value?.status == 0 && turn.quiet.contains("로그인/권한 창을 처리해 주세요 — 끝나면 이어서 할게요")
          && outcome.status == 0 && outcome.output.contains("Aris paused") && rig.calls.filter { $0.hasPrefix("type") }.count == 1 && !lock.state.paused,
          "fix-13 pause: `aris-tools type` with a SecurityAgent-style password field up pauses (the line in the notch), types nothing while it is up, then types once (\(outcome.output.prefix(90)))")
    // Still up at the limit: refused, nothing typed anywhere.
    let stuck = V2Rig(lock: ArisDesktopLock(waitLimit: 5, idleHold: 30, poll: 0.02), pause: ArisDesktopPause.Policy(limit: 0.5, poll: 0.1))
    stuck.apps.secureInput = true
    stuck.apps.secureOwner = 777
    let held = V2Turn()
    held.request = turn.request
    stuck.queueData([("see", f13Chat("note D", caret: 6))])
    let refused = stuck.run(call.words, text: call.text, turn: held)
    check(refused.status == 1 && !stuck.calls.contains { $0.hasPrefix("type") },
          "fix-13 pause: a password dialog that stays up ends the step with nothing typed")
}

// MARK: - 4. A replay decides its look as the live run did

private func fix13ReplayTests() {
    // Live: TextEdit-like field named by what it holds; the look ran without the read judge.
    let live = V2Rig()
    let turn = V2Turn()
    turn.request = "Aris Testbench 창 끝에 '둘' 입력해 줘"
    live.queueData([("see", f13Chat("note B", caret: 6, label: "note B")), ("see", f13Chat("note B", caret: 6, label: "note B")),
                    ("type", v2pb("type-unverified")), ("see", f13Chat("note B둘", caret: 7, label: "note B둘"))])
    let done = live.run(["type", "--focused", "--app", "Aris Testbench", "--stdin"], text: "둘", turn: turn)
    guard done.status == 0, turn.notes.count == 1, case .success(let step) = turn.notes[0] else {
        return check(false, "fix-13 replay: the live type is done and noted (\(done.output.prefix(100)), \(turn.notes))")
    }
    check(step.action == .type && step.lookJudged == false && step.contentLabel == true && step.label == nil,
          "fix-13 replay: the step keeps how its look was decided (without the judge) and keeps no window text as its field's name")
    guard let recipe = ArisSavedSteps.recipe(key: ArisShortcuts.key(for: turn.request), request: turn.request, notes: turn.notes, outside: true) else {
        return check(false, "fix-13 replay: the live run makes a recipe")
    }
    // The replay: no AI (the judge can't decide), as tainted as the turn it was learned on.
    let again = V2Rig()
    let replay = F13Turn()
    replay.request = turn.request
    replay.markAppRead("com.example.elsewhere")
    again.queueData([("see", f13Chat("note B둘", caret: 7, label: "note B둘")), ("see", f13Chat("note B둘", caret: 7, label: "note B둘")),
                     ("type", v2pb("type-unverified")), ("see", f13Chat("note B둘둘", caret: 8, label: "note B둘둘"))])
    let outcome = ArisSavedStepsReplay.run(recipe, request: replay.request, engine: again.engine, turn: replay)
    check(outcome == .done(steps: 1) && replay.judged == 0 && replay.cards.count == turn.cards.count,
          "fix-13 replay: \"끝에 '둘'\" replays with its look decided as live (no judge) and as many cards as the live run (\(outcome), \(replay.cards.count) vs \(turn.cards.count), judged \(replay.judged))")
    // The pass-9 recipe (saved before looks were recorded): handed over before any step, no card, nothing looked at.
    let old = ArisSavedRecipe(key: recipe.key, request: recipe.request, steps: [
        ArisSavedStep(action: .press, bundle: v2Bench.bundle ?? "", app: v2Bench.name, window: "Aris Testbench", keys: ["cmd+down"]),
        ArisSavedStep(action: .type, bundle: v2Bench.bundle ?? "", app: v2Bench.name, window: "Aris Testbench", role: "textField", label: "note B", path: [],
                      text: "둘", afterYes: true),
    ], saved: recipe.saved, outside: true)
    let third = V2Rig()
    let pass9 = F13Turn()
    pass9.request = turn.request
    check(ArisSavedStepsReplay.run(old, request: pass9.request, engine: third.engine, turn: pass9) == .handOver(done: [], why: .judged)
          && pass9.cards.isEmpty && third.calls.isEmpty,
          "fix-13 replay: a recipe whose look needed (or may have needed) the read judge hands over before acting, without a card")
    // A step done on a look the judge had to allow is saved as such.
    let careful = V2Rig()
    let tainted = V2Turn()
    tainted.request = turn.request
    tainted.markAppRead("com.example.elsewhere")
    careful.queueData([("see", f13Chat("note B", caret: 6, label: "note B")), ("see", f13Chat("note B", caret: 6, label: "note B")),
                       ("type", v2pb("type-unverified")), ("see", f13Chat("note B둘", caret: 7, label: "note B둘"))])
    _ = careful.run(["type", "--focused", "--app", "Aris Testbench", "--stdin"], text: "둘", turn: tainted)
    if case .success(let judgedStep)? = tainted.notes.first {
        check(judgedStep.lookJudged == true, "fix-13 replay: a step whose look the read judge allowed is saved as needing it")
    } else {
        check(false, "fix-13 replay: the careful turn's step is noted (\(tainted.notes))")
    }
    // A content-named field is found again whatever it holds now; a named one only by its name.
    let content = ArisSavedStep(action: .type, bundle: "b", app: "A", role: "textField", path: [], text: "둘", contentLabel: true)
    check(ArisSavedSteps.replayable(content, request: turn.request) && !ArisSavedSteps.replayable(ArisSavedStep(action: .type, bundle: "b", app: "A", role: "textField", text: "둘"), request: turn.request),
          "fix-13 replay: a content-named field's step replays with no name kept; any other still needs its name")
}

// MARK: - 5. A job's launch of an app that already runs

private func fix13JobLaunchTests() {
    let rig = V2Rig()
    let job = V2Turn()
    job.isTask = true
    job.request = "백그라운드로 Aris Testbench에서 9 버튼 눌러 줘"
    let launched = rig.run(["app", "launch", "Aris Testbench"], turn: job)
    check(launched.status == 0 && launched.output.contains("already running") && launched.output.contains("desktop see --app \"Aris Testbench\"")
          && !rig.calls.contains { $0.hasPrefix("app") } && job.cards.isEmpty,
          "fix-13 job launch: a background job's launch of an app that runs is a done no-op (nothing launched or brought forward), telling it to look at the window (\(launched.output.prefix(90)))")
    rig.queue([("see", "see-messenger")])
    check(rig.run(["see", "--app", "Aris Testbench"], turn: job).status == 0, "fix-13 job launch: the job then looks at the app's window")
    check(ArisDesktopGate.jobRefusal.contains("in the background") && ArisDesktopGate.jobRefusal.contains("report"),
          "fix-13 job launch: a launch that would bring a window forward stays refused, telling the job to work in the background or say so")
    let chat = V2Turn()
    chat.request = "Aris Testbench 열어 줘"
    _ = rig.run(["app", "launch", "Aris Testbench"], turn: chat)
    check(chat.cards.count == 1, "fix-13 job launch: a conversation's launch still asks as before")
}
