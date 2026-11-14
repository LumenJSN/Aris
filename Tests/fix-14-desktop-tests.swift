// Tests for fix-14, the desktop parts (the tenth VM pass on 551a585f): the "끝에 '둘'" turn typed through
// `aris-tools type` is saved and replays with as many cards as the live run, the end checked; a typing step paused for
// a password dialog finishes by itself once the dialog is gone, even when the brain looked at the window again while
// it waited (the VM's case: the resumed step met "That ref is from an older look" and the AI typed again on a second
// card). On desktop-v2-tests' rig (fake Peekaboo, recorded fixtures); nothing touches a real app or the screen.
// Called from main.swift; uses its check().
import CoreGraphics
import Foundation

func runFix14DesktopTests() {
    fix14SavedToolTypeTests()
    fix14ResumedTypeTests()
    fix14ResumedNoteTests()
}

/// see-chat with its Message field (elem_59) holding `value`, named by what it holds (TextEdit's text view), the caret at
/// `caret`, the keyboard focus on it.
private func f14Field(_ value: String, caret: Int) -> Data {
    guard var object = (try? JSONSerialization.jsonObject(with: v2pb("see-chat"))) as? [String: Any], var data = object["data"] as? [String: Any] else { return Data() }
    data["focused_element"] = ["frame": [[461, 1015], [586, 24]], "processIdentifier": 4242, "role": "AXTextField", "windowID": 9189]
    var list = data["ui_elements"] as? [[String: Any]] ?? []
    for index in list.indices where list[index]["id"] as? String == "elem_59" {
        list[index]["value"] = value
        list[index]["label"] = value
        list[index]["description"] = value
        list[index]["selected_text_range"] = ["location": caret, "length": 0]
    }
    data["ui_elements"] = list
    object["data"] = data
    return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
}

/// A replay's turn: no AI behind it (the read judge can't decide), cards answered yes, the audit kept.
private final class F14Turn: ArisDesktopTurn {
    let brain: ArisBrain = .claude
    let ledger = ArisComputerUseLedger()
    var brainName: String { "claude" }
    var handsFree = false
    var isTask = false
    var screen = false
    var relayed = false
    var request = ""
    private let lock = NSLock()
    private var read: Set<String> = []
    private var _cards: [ArisMCPCard] = []
    private var _audits: [String] = []
    private var _judged = 0
    private var steps = 0
    var cards: [ArisMCPCard] { lock.withLock { _cards } }
    var audits: [String] { lock.withLock { _audits } }
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
        done(.blocked(.undecided))
    }
    func quiet(_ status: String) {}
    func audit(_ fields: [String: String]) { lock.withLock { _audits.append(fields["answer"] ?? "") } }
    func operating(_ target: ArisOperatingTarget) {}
    func desktopStep() -> Int { lock.withLock { steps += 1; return steps } }
    func noteDesktopAction(_ note: Result<ArisSavedStep, ArisSavedStepsRefusal>) {}
}

// MARK: - 1. The tool path's turn is saved, and replays

private func fix14SavedToolTypeTests() {
    let tools = "/tools/aris-tools"
    let live = V2Rig()
    let turn = V2Turn()
    turn.request = "Aris Testbench 창 끝에 '둘' 입력해 줘"
    guard case .success(let call) = ArisTypeRequest.call(["둘", "--app", "Aris Testbench"], keyboardApp: nil) else { return check(false, "fix-14 saved: the call") }
    // The caret at the start: ⌘↓ first, then the keys, then the read-back at the end.
    live.queueData([("see", f14Field("note C", caret: 0)), ("see", f14Field("note C", caret: 0)), ("press", v2pb("press-return")),
                    ("see", f14Field("note C", caret: 6)), ("type", v2pb("type-unverified")), ("see", f14Field("note C둘", caret: 7))])
    let done = live.run(call.words, text: call.text, turn: turn)
    guard done.status == 0, done.output.contains(ArisDesktopCaret.Landing.there.line(.end)) else {
        return check(false, "fix-14 saved: the live type is done at the end (\(done.output.prefix(140)))")
    }
    // The runner's rule for the turn: the brain's one shell line was `aris-tools type`, a desktop call.
    let otherTools = !ArisDesktopHonesty.isDesktopCommand("\(tools) type '둘' --app 'Aris Testbench'", tools: tools)
    guard let recipe = ArisSavedSteps.turnRecipe(key: ArisShortcuts.key(for: turn.request), request: turn.request, notes: turn.notes, notDone: 0,
                                                 otherTools: otherTools, reply: "창 끝에 '둘'을 입력했어요.", outside: true) else {
        return check(false, "fix-14 saved: the turn typed through `aris-tools type` makes a recipe (\(turn.notes), other tools \(otherTools))")
    }
    check(recipe.steps.count == 1 && recipe.steps[0].action == .type && recipe.steps[0].text == "둘" && recipe.steps[0].contentLabel == true,
          "fix-14 saved: its one step is the type of '둘' into the field found by its place")
    // The replay: no AI, as tainted as the turn it was learned on; the caret at the start again.
    let again = V2Rig()
    let replay = F14Turn()
    replay.request = turn.request
    replay.markAppRead("com.example.elsewhere")
    again.queueData([("see", f14Field("note C둘", caret: 0)), ("see", f14Field("note C둘", caret: 0)), ("press", v2pb("press-return")),
                     ("see", f14Field("note C둘", caret: 7)), ("type", v2pb("type-unverified")), ("see", f14Field("note C둘둘", caret: 8))])
    let outcome = ArisSavedStepsReplay.run(recipe, request: replay.request, engine: again.engine, turn: replay)
    let calls = again.calls
    let pressAt = calls.firstIndex { $0.hasPrefix("press cmd+down") }, typeAt = calls.firstIndex { $0.hasPrefix("type --text=둘") }
    check(outcome == .done(steps: 1) && replay.cards.count == turn.cards.count && replay.judged == 0,
          "fix-14 saved: it replays with no AI and as many cards as the live run (\(outcome), \(replay.cards.count) vs \(turn.cards.count))")
    check(pressAt != nil && typeAt != nil && pressAt! < typeAt! && calls.filter { $0.hasPrefix("type") }.count == 1 && replay.audits.contains("typed (end: there)"),
          "fix-14 saved: the replay puts the caret at the end, types once and checks the end (\(replay.audits.suffix(3)))")
}

// MARK: - 2. A paused type finishes by itself, the brain's look in between

private func fix14ResumedTypeTests() {
    guard case .success(let call) = ArisTypeRequest.call(["넷", "--app", "Aris Testbench"], keyboardApp: nil) else { return check(false, "fix-14 resume: the call") }
    let request = "Aris Testbench의 noteD 창 끝에 '넷' 입력해 줘"
    // The same type with no dialog: how many cards it asks.
    let plain = V2Rig()
    let calm = V2Turn()
    calm.request = request
    // As TextEdit's type ran in the VM: no card of its own (here, the user's yes for the app earlier in the conversation), so
    // no card's yes re-finds the control after a newer look.
    calm.ledger.remember(v2Bench.memoryKey ?? "", tainted: false)
    plain.queueData([("see", f14Field("note D", caret: 6)), ("see", f14Field("note D", caret: 6)), ("type", v2pb("type-unverified")), ("see", f14Field("note D넷", caret: 7))])
    let baseline = plain.run(call.words, text: call.text, turn: calm)

    let lock = ArisDesktopLock(waitLimit: 5, idleHold: 30, poll: 0.02)
    let rig = V2Rig(lock: lock, pause: ArisDesktopPause.Policy(limit: 5, poll: 0.1))
    rig.apps.secureInput = true
    rig.apps.secureOwner = 777
    let turn = V2Turn()
    turn.request = request
    turn.ledger.remember(v2Bench.memoryKey ?? "", tainted: false)
    // The engine's look, the brain's own look while the step waits, then the resumed step's look, the keys, the read-back.
    rig.queueData([("see", f14Field("note D", caret: 6)), ("see", f14Field("note D", caret: 6)), ("see", f14Field("note D", caret: 6)),
                   ("type", v2pb("type-unverified")), ("see", f14Field("note D넷", caret: 7))])
    let brainLook = V2Box()
    let typedWhileUp = V2Box()
    // Once the step has paused (its line in the notch): the brain's look, then the dialog goes.
    DispatchQueue.global().async {
        let until = Date().addingTimeInterval(10)
        while !turn.quiet.contains(ArisDesktopPause.line(.secureInput, english: false)), Date() < until { Thread.sleep(forTimeInterval: 0.02) }
        brainLook.set(rig.run(["see", "--app", "Aris Testbench"], turn: turn))
        Thread.sleep(forTimeInterval: 0.3)
        typedWhileUp.set(ArisMCPOutcome(status: rig.calls.contains { $0.hasPrefix("type") } ? 1 : 0, output: ""))
        rig.apps.secureInput = false
    }
    let outcome = rig.run(call.words, text: call.text, turn: turn)
    check(brainLook.value?.status == 0 && typedWhileUp.value?.status == 0,
          "fix-14 resume: the brain looked at the window while the step waited, and nothing was typed while the dialog was up (\(brainLook.value?.output.prefix(60) ?? "no look"))")
    check(outcome.status == 0 && outcome.output.contains("Aris paused") && outcome.output.contains("did the step from its start")
          && outcome.output.contains(ArisDesktopCaret.Landing.there.line(.end)) && !outcome.output.contains(ArisDesktopSession.notTypedLead)
          && rig.calls.filter { $0.hasPrefix("type") }.count == 1,
          "fix-14 resume: once the dialog is gone the step finishes by itself, once, at the end, though a newer look of the window was taken meanwhile (\(outcome.output.prefix(160)))")
    check(baseline.status == 0 && turn.cards.count == calm.cards.count && turn.cards.isEmpty && !lock.state.paused,
          "fix-14 resume: on the original yes, with no card more than the same type without a dialog (\(turn.cards.count) vs \(calm.cards.count))")
    // A ref from an older look is still refused when nothing paused (the brain must look again).
    let stale = V2Rig()
    let other = V2Turn()
    other.request = request
    other.ledger.remember(v2Bench.memoryKey ?? "", tainted: false)
    stale.queueData([("see", f14Field("note D", caret: 6)), ("see", f14Field("note D", caret: 6)), ("see", f14Field("note D", caret: 6))])
    let first = stale.run(["see", "--app", "Aris Testbench"], turn: other)
    guard let ref = first.output.split(separator: "\n").first(where: { $0.hasPrefix("@") && $0.contains("note D") })?.split(separator: " ").first.map(String.init) else {
        return check(false, "fix-14 resume: the field's ref (\(first.output.prefix(200)))")
    }
    _ = stale.run(["see", "--app", "Aris Testbench"], turn: other)
    let refused = stale.run(["type", ref, "--stdin"], text: "넷", turn: other)
    check(refused.status == 1 && refused.output.contains("older look") && !stale.calls.contains { $0.hasPrefix("type") },
          "fix-14 resume: without a pause a ref from an older look is still refused, nothing typed (\(refused.output.suffix(300)))")
}

// MARK: - 2b. The note says what happened

private func fix14ResumedNoteTests() {
    let done = ArisDesktopPause.resumedNote(waited: 33), failed = ArisDesktopPause.resumedNote(waited: 33, done: false)
    check(done.contains("did the step from its start") && done.contains("Nothing was typed into that window") && done.contains("Aris paused"),
          "fix-14 note: a resumed step that was done says it did the step")
    check(!failed.contains("did the step") && failed.contains("tried the step again") && failed.contains("wasn't done") && failed.contains("Aris paused")
          && failed.contains("Nothing was typed into that window"),
          "fix-14 note: one that wasn't done never says it did it")
}
