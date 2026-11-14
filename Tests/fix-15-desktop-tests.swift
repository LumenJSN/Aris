// Tests for fix-15, the desktop parts (the eleventh VM pass on 2566d52a), on desktop-v2-tests' rig (fake
// Peekaboo, recorded fixtures) with TextEdit's shape: three windows, the document's text view named by what it holds.
// `aris-tools type '둘' --app TextEdit --title noteC.txt --at end` types only "둘", in the window it names, at the end;
// the '둘' desktop-path recipe (click the text, ⌘↓, type) replays after the text changed; and a replay asks as many
// cards as the live run did for the same step (the pass-11 tool-path replay asked one where the live run asked none).
// Nothing touches a real app or the screen. Called from main.swift; uses its check().
import CoreGraphics
import Foundation

func runFix15DesktopTests() {
    fix15FlagsThroughEngineTests()
    fix15ToolPathCardTests()
    fix15NeverFewerCardsTests()
    fix15ContentClickReplayTests()
}

private let f15Edit = ArisDesktopTarget(name: "TextEdit", bundle: "com.apple.TextEdit", pid: 4242, known: true, never: false, browser: false, sending: false,
                                        appleSigned: true)
private let f15Frame = CGRect(x: 80, y: 329, width: 1040, height: 720)
/// noteC.txt is the window the fixture's look is of (9189); two more TextEdit windows, as in the VM.
private let f15Windows = [ArisDesktopWindow(id: 9189, frame: f15Frame, title: "noteC.txt"), ArisDesktopWindow(id: 9190, frame: f15Frame, title: "noteD.txt"),
                          ArisDesktopWindow(id: 9191, frame: f15Frame, title: "Untitled")]

private func f15Rig() -> V2Rig {
    let rig = V2Rig()
    rig.apps.apps["textedit"] = f15Edit
    rig.apps.apps["com.apple.textedit"] = f15Edit
    rig.windows.byPid[4242] = f15Windows
    return rig
}

/// One desktop call on `rig` for any turn (V2Rig.run takes its own turn only).
private func f15Run(_ rig: V2Rig, _ words: [String], text: String? = nil, turn: ArisDesktopTurn) -> ArisMCPOutcome {
    let box = V2Box()
    let done = DispatchSemaphore(value: 0)
    DispatchQueue.global().async { rig.engine.handle(words, text: text, turn: turn) { box.set($0); done.signal() } }
    _ = done.wait(timeout: .now() + 60)
    return box.value ?? .failed("no answer")
}

/// What the rig's Peekaboo answers to a look once its queue of looks is empty.
private func f15Default(_ rig: V2Rig, see: Data) {
    let folder = rig.installer.stateFolder.appendingPathComponent("replies")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try? see.write(to: folder.appendingPathComponent("see.json"))
}

/// see-chat as TextEdit's noteC.txt: its text view (elem_59) holds `value` and is named by it, the caret at `caret`, the
/// keyboard focus on it.
private func f15Doc(_ value: String, caret: Int, title: String = "noteC.txt", focused: Bool = true) -> Data {
    guard var object = (try? JSONSerialization.jsonObject(with: v2pb("see-chat"))) as? [String: Any], var data = object["data"] as? [String: Any] else { return Data() }
    data["application_name"] = "TextEdit"
    data["window_title"] = title
    // Unfocused: the keyboard focus on the search field (elem_27) instead.
    data["focused_element"] = focused ? ["frame": [[461, 1015], [586, 24]], "processIdentifier": 4242, "role": "AXTextField", "windowID": 9189]
        : data["focused_element"] ?? NSNull()
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

/// A turn on a clean conversation that isn't a critical one (V2Turn's is, by the protocol's default): a live turn
/// (both taints none), or a saved-steps replay's as the agent's own (ArisSavedStepsTurn: the recipe's taint and the
/// conversation's, the step's taint for its app from ArisSavedStepsReplay.stepTaint). Cards answered yes, steps noted.
private final class F15Turn: ArisDesktopTurn {
    let brain: ArisBrain = .claude
    let ledger = ArisComputerUseLedger()
    var brainName: String { "saved-steps" }
    var handsFree = false
    var isTask = false
    var screen = false
    var relayed = false
    var request = ""
    var critical: Bool { false }
    let learned: ArisTaint
    let conversation: ArisTaint
    private let lock = NSLock()
    private var read: Set<String> = []
    private var _cards: [ArisMCPCard] = []
    private var _audits: [String] = []
    private var _notes: [Result<ArisSavedStep, ArisSavedStepsRefusal>] = []
    private var steps = 0
    init(learned: ArisTaint = .none, conversation: ArisTaint = .none) {
        self.learned = learned
        self.conversation = conversation
    }
    var cards: [ArisMCPCard] { lock.withLock { _cards } }
    var audits: [String] { lock.withLock { _audits } }
    var notes: [Result<ArisSavedStep, ArisSavedStepsRefusal>] { lock.withLock { _notes } }
    var live: Bool { true }
    var taint: ArisTaint { lock.withLock { read.isEmpty ? learned : .outsideText } }
    func taint(forApp app: String) -> ArisTaint {
        let clean = ledger.replayStepClean
        return lock.withLock {
            ArisSavedStepsReplay.stepTaint(learned: learned, conversation: conversation, stepClean: clean, readOther: !read.subtracting([app]).isEmpty)
        }
    }
    func markAppRead(_ app: String) { lock.withLock { _ = read.insert(app) } }
    func takeOutsideText() {}
    func ask(_ card: ArisMCPCard, answer done: @escaping (ArisMCPAnswer) -> Void) {
        lock.withLock { _cards.append(card) }
        done(.yes([:]))
    }
    /// A live turn's read judge allows; a replay has none (it can't decide).
    var judgeAllows = false
    func judgeRead(_ call: ArisReadCall, done: @escaping (ArisReadVerdict) -> Void) { done(judgeAllows ? .ok : .blocked(.undecided)) }
    func quiet(_ status: String) {}
    func audit(_ fields: [String: String]) { lock.withLock { _audits.append(fields["answer"] ?? "") } }
    func operating(_ target: ArisOperatingTarget) {}
    func desktopStep() -> Int { lock.withLock { steps += 1; return steps } }
    func noteDesktopAction(_ note: Result<ArisSavedStep, ArisSavedStepsRefusal>) { lock.withLock { _notes.append(note) } }
}

/// The replay's turn for `recipe` on a clean conversation, as the agent makes it (main.swift's replaySaved).
private func f15Replay(_ recipe: ArisSavedRecipe, request: String) -> F15Turn {
    let turn = F15Turn(learned: ArisSavedStepsReplay.startTaint(recipe, sawScreen: false, sawOutside: false),
                             conversation: ArisSavedStepsReplay.conversationTaint(sawScreen: false, sawOutside: false))
    turn.request = request
    return turn
}

// MARK: - 1. The VM's exact call through the engine

private func fix15FlagsThroughEngineTests() {
    guard case .success(let call) = ArisTypeRequest.call(["둘", "--app", "TextEdit", "--title", "noteC.txt", "--at", "end"], keyboardApp: nil) else {
        return check(false, "fix-15 flags: the VM's call is read")
    }
    // The user's words name the window and the end, as in the VM.
    let rig = f15Rig()
    let turn = V2Turn()
    turn.request = "TextEdit의 noteC.txt 창 끝에 '둘' 입력해 줘"
    rig.queueData([("see", f15Doc("note C", caret: 0)), ("see", f15Doc("note C", caret: 0)), ("press", v2pb("press-return")),
                   ("see", f15Doc("note C", caret: 6)), ("type", v2pb("type-unverified")), ("see", f15Doc("note C둘", caret: 7))])
    let done = rig.run(call.words, text: call.text, turn: turn)
    let calls = rig.calls
    let typed = calls.filter { $0.hasPrefix("type") }
    check(done.status == 0 && typed.count == 1 && typed[0].hasPrefix("type --text=둘 ") && !calls.contains { $0.contains("--title") && $0.hasPrefix("type") },
          "fix-15 flags: `aris-tools type '둘' --app TextEdit --title noteC.txt --at end` types only 둘, once (\(typed), \(done.output.prefix(160)))")
    check(done.output.contains(ArisDesktopCaret.Landing.there.line(.end)) && turn.cards.count == 1 && turn.cards.allSatisfy { !$0.detail.contains("--") && $0.detail.contains("둘") },
          "fix-15 flags: at the end, and no card shows a flag as text (\(turn.cards.map(\.detail)))")
    // The user's words say neither the window nor the place: --title aims the look, --at puts the caret.
    let named = f15Rig()
    let quiet = V2Turn()
    quiet.request = "TextEdit에 '둘' 입력해 줘"
    named.queueData([("see", f15Doc("note C", caret: 0)), ("see", f15Doc("note C", caret: 0)), ("press", v2pb("press-return")),
                     ("see", f15Doc("note C", caret: 6)), ("type", v2pb("type-unverified")), ("see", f15Doc("note C둘", caret: 7))])
    let aimed = named.run(call.words, text: call.text, turn: quiet)
    let first = named.calls.first ?? ""
    check(aimed.status == 0 && first.hasPrefix("see") && first.contains("9189") && named.calls.contains { $0.hasPrefix("press cmd+down") }
          && aimed.output.contains(ArisDesktopCaret.Landing.there.line(.end)),
          "fix-15 flags: with the user's words silent, --title noteC.txt aims the look at that window and --at end puts the caret at the end (\(named.calls.prefix(3)), \(aimed.output.prefix(120)))")
    // His words win over the brain's --at.
    guard case .success(let start) = ArisTypeRequest.call(["둘", "--app", "TextEdit", "--title", "noteC.txt", "--at", "start"], keyboardApp: nil) else {
        return check(false, "fix-15 flags: --at start is read")
    }
    let words = f15Rig()
    let said = V2Turn()
    said.request = "TextEdit의 noteC.txt 창 끝에 '둘' 입력해 줘"
    words.queueData([("see", f15Doc("note C", caret: 0)), ("see", f15Doc("note C", caret: 0)), ("press", v2pb("press-return")),
                     ("see", f15Doc("note C", caret: 6)), ("type", v2pb("type-unverified")), ("see", f15Doc("note C둘", caret: 7))])
    let won = words.run(start.words, text: start.text, turn: said)
    check(won.status == 0 && words.calls.contains { $0.hasPrefix("press cmd+down") } && !words.calls.contains { $0.hasPrefix("press cmd+up") },
          "fix-15 flags: the user's \"끝에\" wins over a brain's --at start (\(words.calls))")
}

// MARK: - 2. The tool path's replay asks the live run's cards (pass 11: 1 where the live run asked 0)

/// The tool path's live type of 셋 at the end of noteC (its text "note C둘"), on `turn`: what it answered.
private func f15LiveToolType(_ turn: F15Turn) -> ArisMCPOutcome {
    guard case .success(let call) = ArisTypeRequest.call(["셋", "--app", "TextEdit"], keyboardApp: nil) else { return .failed("the call") }
    let live = f15Rig()
    live.queueData([("see", f15Doc("note C둘", caret: 0)), ("see", f15Doc("note C둘", caret: 0)), ("press", v2pb("press-return")),
                    ("see", f15Doc("note C둘", caret: 7)), ("type", v2pb("type-unverified")), ("see", f15Doc("note C둘셋", caret: 8))])
    return f15Run(live, call.words, text: call.text, turn: turn)
}

/// A replay of `recipe` on `turn` with the document reading "note C둘셋", the caret at the start: the outcome and the
/// type calls made.
private func f15ReplayToolType(_ recipe: ArisSavedRecipe, turn: F15Turn) -> (ArisSavedStepsReplay.Outcome, Int) {
    let again = f15Rig()
    again.queueData([("see", f15Doc("note C둘셋", caret: 0)), ("see", f15Doc("note C둘셋", caret: 0)), ("press", v2pb("press-return")),
                     ("see", f15Doc("note C둘셋", caret: 8)), ("type", v2pb("type-unverified")), ("see", f15Doc("note C둘셋셋", caret: 9))])
    let outcome = ArisSavedStepsReplay.run(recipe, request: turn.request, engine: again.engine, turn: turn)
    return (outcome, again.calls.filter { $0.hasPrefix("type") }.count)
}

private func fix15ToolPathCardTests() {
    let request = "TextEdit의 noteC.txt 창 끝에 '셋' 입력해 줘"
    let turn = F15Turn()
    turn.request = request
    let done = f15LiveToolType(turn)
    guard done.status == 0, turn.cards.isEmpty else {
        return check(false, "fix-15 cards: the live type of the user's words into TextEdit, its window named, runs at once (\(turn.cards.count) cards, \(done.output.prefix(160)))")
    }
    // The runner's rule: the turn read TextEdit's window, so the recipe is kept as learned with outside text.
    guard let recipe = ArisSavedSteps.turnRecipe(key: ArisShortcuts.key(for: request), request: request, notes: turn.notes, notDone: 0, otherTools: false,
                                                 reply: "noteC.txt 창 끝에 '셋'을 입력했어요.", outside: true) else {
        return check(false, "fix-15 cards: the turn makes a recipe (\(turn.notes))")
    }
    check(recipe.steps.count == 1 && recipe.steps[0].appClean == true && recipe.steps[0].afterYes == nil,
          "fix-15 cards: its one step is kept as done with no outside text for TextEdit (only its own window read), on no yes (\(recipe.steps))")
    let replay = f15Replay(recipe, request: request)
    let (outcome, types) = f15ReplayToolType(recipe, turn: replay)
    check(outcome == .done(steps: 1) && replay.cards.count == turn.cards.count && types == 1,
          "fix-15 cards: the replay asks as many cards as the live run (\(replay.cards.count) vs \(turn.cards.count), \(outcome), \(replay.audits.suffix(4)))")
    check(replay.audits.contains("typed (end: there)"), "fix-15 cards: and types at the end, checked (\(replay.audits.suffix(3)))")
    // The same recipe from before this was kept (no appClean): as tainted as the turn it was learned on, its card back.
    let old = ArisSavedRecipe(key: recipe.key, request: recipe.request, steps: recipe.steps.map { step in var kept = step; kept.appClean = nil; return kept },
                              saved: recipe.saved, outside: true)
    let oldTurn = f15Replay(old, request: request)
    let (oldOutcome, _) = f15ReplayToolType(old, turn: oldTurn)
    check(oldOutcome == .done(steps: 1) && oldTurn.cards.count == 1,
          "fix-15 cards: a step saved before (no word on its taint) still replays under the recipe's taint, with its card (\(oldTurn.cards.count), \(oldOutcome))")
    // A clean step replayed after outside text came into the conversation: the conversation's taint, its card, as the
    // live run would ask now.
    let tainted = F15Turn(learned: ArisSavedStepsReplay.startTaint(recipe, sawScreen: false, sawOutside: true),
                          conversation: ArisSavedStepsReplay.conversationTaint(sawScreen: false, sawOutside: true))
    tainted.request = request
    let (nowOutcome, _) = f15ReplayToolType(recipe, turn: tainted)
    check(nowOutcome == .done(steps: 1) && tainted.cards.count == 1,
          "fix-15 cards: a clean step replayed once the conversation has outside text asks its card (\(tainted.cards.count), \(nowOutcome))")
}

// MARK: - 3. Never fewer cards than the live run

private func fix15NeverFewerCardsTests() {
    let request = "TextEdit의 noteC.txt 창 끝에 '셋' 입력해 줘"
    // The live turn had read another app's window first: outside text for TextEdit, so its look was judged and the type asked.
    let turn = F15Turn()
    turn.request = request
    turn.markAppRead("com.example.elsewhere")
    turn.judgeAllows = true
    let done = f15LiveToolType(turn)
    guard done.status == 0, turn.cards.count == 1,
          let recipe = ArisSavedSteps.turnRecipe(key: ArisShortcuts.key(for: request), request: request, notes: turn.notes, notDone: 0, otherTools: false,
                                                 reply: "입력했어요.", outside: true) else {
        return check(false, "fix-15 fewer: the tainted live type asked one card and made a recipe (\(turn.cards.count), \(done.output.prefix(120)), \(turn.notes))")
    }
    check(recipe.steps[0].appClean == nil, "fix-15 fewer: a step done with outside text for its app is not kept as clean")
    // Its replay can't decide the judged look (no AI): handed over before any step or card, nothing typed.
    let replay = f15Replay(recipe, request: request)
    let (outcome, types) = f15ReplayToolType(recipe, turn: replay)
    check(outcome == .handOver(done: [], why: .judged) && replay.cards.isEmpty && types == 0,
          "fix-15 fewer: its replay hands the request to the AI before acting (\(outcome))")
    // Were that look not judged, the step would still ask its card under the recipe's taint.
    let unjudged = ArisSavedRecipe(key: recipe.key, request: request, steps: recipe.steps.map { step in var kept = step; kept.lookJudged = false; return kept },
                                   saved: recipe.saved, outside: true)
    let second = f15Replay(unjudged, request: request)
    let (secondOutcome, _) = f15ReplayToolType(unjudged, turn: second)
    check(secondOutcome == .done(steps: 1) && second.cards.count == 1, "fix-15 fewer: a step not kept as clean asks its card in the replay too (\(second.cards.count), \(secondOutcome))")
}

// MARK: - 4. The '둘' desktop-path recipe replays after the text changed

private func fix15ContentClickReplayTests() {
    let request = "TextEdit의 noteC.txt 창 끝에 '둘' 입력해 줘"
    let live = f15Rig()
    let turn = F15Turn()
    turn.request = request
    // The brain's look, its click on the text view (named "note C" by what it holds), ⌘↓, another look, then its type.
    // Any look the steps take in between reads the document as it is (caret at its end).
    // The text view hasn't the keyboard focus until the click.
    f15Default(live, see: f15Doc("note C", caret: 6))
    live.queueData([("see", f15Doc("note C", caret: 0, focused: false))])
    let look = f15Run(live, ["see", "--app", "TextEdit", "--title", "noteC.txt"], turn: turn)
    guard let field = live.ref("note C", in: look.output) else { return check(false, "fix-15 click: the text view's ref (\(look.output.prefix(300)))") }
    live.queueData([("see", f15Doc("note C", caret: 0, focused: false)), ("click", v2pb("click-field"))])
    let clicked = f15Run(live, ["click", field], turn: turn)
    live.queueData([("press", v2pb("press-return"))])
    let pressed = f15Run(live, ["press", "cmd+down", "--app", "TextEdit", "--title", "noteC.txt"], turn: turn)
    let relook = f15Run(live, ["see", "--app", "TextEdit", "--title", "noteC.txt"], turn: turn)
    guard let again = live.ref("note C", in: relook.output) else { return check(false, "fix-15 click: the second look's ref") }
    live.queueData([("see", f15Doc("note C", caret: 6)), ("type", v2pb("type-unverified")), ("see", f15Doc("note C둘", caret: 7))])
    let typed = f15Run(live, ["type", again, "--stdin"], text: "둘", turn: turn)
    guard clicked.status == 0, pressed.status == 0, typed.status == 0 else {
        return check(false, "fix-15 click: the live run is done (\(clicked.status) \(clicked.output.prefix(700)) | \(pressed.status) \(pressed.output.suffix(160)) | \(typed.status) \(typed.output.suffix(160)) | \(live.calls))")
    }
    guard let recipe = ArisSavedSteps.turnRecipe(key: ArisShortcuts.key(for: request), request: request, notes: turn.notes, notDone: 0, otherTools: false,
                                                 reply: "noteC.txt 창 끝에 '둘'을 입력했어요.", outside: true) else {
        return check(false, "fix-15 click: the turn makes a recipe (\(turn.notes))")
    }
    let steps = recipe.steps
    check(steps.count == 3 && steps[0].action == .click && steps[0].contentLabel == true && steps[0].label == nil
          && steps[2].action == .type && steps[2].contentLabel == true,
          "fix-15 click: the click on the text view is saved by its place, like the type, never under the text it held (\(steps.map { "\($0.action) \($0.label ?? "-") \($0.contentLabel ?? false)" }))")
    check(ArisSavedSteps.describe(steps[0], english: false).contains("글 칸") && !ArisSavedSteps.describe(steps[0], english: false).contains("note C"),
          "fix-15 click: Settings names it as the text, not by what it held")
    guard steps.count == 3 else { return }
    // The document reads "note C둘" now. The replay finds the same text view by its place, with the live run's cards.
    // (Run as its click and ⌘↓, then its type, on the one replay turn, so the type's read-back can be queued after them.)
    let rig = f15Rig()
    let replay = f15Replay(recipe, request: request)
    f15Default(rig, see: f15Doc("note C둘", caret: 7))
    rig.queueData([("see", f15Doc("note C둘", caret: 0, focused: false)), ("see", f15Doc("note C둘", caret: 0, focused: false)), ("click", v2pb("click-field")),
                   ("press", v2pb("press-return"))])
    let head = ArisSavedRecipe(key: recipe.key, request: request, steps: Array(steps.prefix(2)), saved: recipe.saved, outside: recipe.outside)
    let first = ArisSavedStepsReplay.run(head, request: request, engine: rig.engine, turn: replay)
    rig.queueData([("see", f15Doc("note C둘", caret: 7)), ("see", f15Doc("note C둘", caret: 7)), ("type", v2pb("type-unverified")), ("see", f15Doc("note C둘둘", caret: 8))])
    let tail = ArisSavedRecipe(key: recipe.key, request: request, steps: [steps[2]], saved: recipe.saved, outside: recipe.outside)
    let second = ArisSavedStepsReplay.run(tail, request: request, engine: rig.engine, turn: replay)
    check(first == .done(steps: 2) && second == .done(steps: 1) && replay.cards.count == turn.cards.count && rig.calls.filter { $0.hasPrefix("type") }.count == 1,
          "fix-15 click: the '둘' recipe replays after the text changed, with as many cards as the live run (\(first), \(second), \(replay.cards.count) vs \(turn.cards.count), \(rig.calls))")
    // The click saved before this (under the text it held) is found only while the text is the same, as before.
    let before = ArisSavedStep(action: .click, bundle: "com.apple.TextEdit", app: "TextEdit", window: "noteC.txt", role: steps[0].role, label: "note C",
                               path: steps[0].path, lookJudged: false)
    check(ArisSavedSteps.replayable(before, request: request) && ArisSavedSteps.replayable(steps[0], request: request),
          "fix-15 click: both a click saved by its place and one saved by a name may be replayed")
}
