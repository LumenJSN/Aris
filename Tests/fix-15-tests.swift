// Tests for fix-15 (the eleventh VM pass on 2566d52a), the parts off the desktop rig: `aris-tools type` reads its
// flags strictly (the card offered to type "둘 --title noteC.txt --at end"), the engine takes --title and --at on the
// focused type, and a replay's step runs under the taint its live run had for its app. Called from main.swift; uses its
// check().
import Foundation

func runFix15Tests() {
    fix15TypeFlagsTests()
    fix15EngineWordsTests()
    fix15ReplayTaintTests()
}

private func fix15Source(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

// MARK: - 1. aris-tools type: known flags, the text from one argument

private func fix15TypeFlagsTests() {
    // The VM's exact call (eleventh pass): the flags are read, never typed.
    let vm = ArisTypeRequest.call(["둘", "--app", "TextEdit", "--title", "noteC.txt", "--at", "end"], keyboardApp: nil)
    guard case .success(let call) = vm else { return check(false, "fix-15 type: the VM's call `type '둘' --app TextEdit --title noteC.txt --at end` is read (\(vm))") }
    check(call.text == "둘" && call.words == ["type", "--focused", "--app", "TextEdit", "--title", "noteC.txt", "--at", "end", "--stdin"],
          "fix-15 type: its text is 둘 alone; --title and --at go to the engine as the window and the caret's place (\(call))")
    func refusal(_ args: [String]) -> String? {
        if case .failure(let why) = ArisTypeRequest.call(args, keyboardApp: "com.apple.TextEdit") { return why.line }
        return nil
    }
    let unknown = [["둘", "--window", "3"], ["둘", "--foo"], ["둘", "-x"], ["--focused", "둘"], ["둘", "--stdin"], ["둘", "--times", "2"]]
    let notRefused = unknown.filter { args in
        guard let line = refusal(args), let flag = args.first(where: { $0.hasPrefix("-") }) else { return true }
        return !line.contains(flag) || !line.contains(ArisTypeRequest.usage)
    }
    check(notRefused.isEmpty, "fix-15 type: an unknown flag is refused with the usage line, naming it, before anything is sent (\(notRefused))")
    let bad = [["둘", "--at", "middle"], ["둘", "--at"], ["둘", "--title"], ["둘", "--title", "--at", "end"], ["둘", "--app"],
               ["둘", "--title", "a", "--title", "b"], ["둘", "--at", "end", "--at", "start"], ["둘", "--app", "TextEdit", "--app", "Notes"]]
    check(bad.allSatisfy { refusal($0) == ArisTypeRequest.usage }, "fix-15 type: a flag with no value, a bad --at, or a flag twice is refused (\(bad.filter { refusal($0) != ArisTypeRequest.usage }))")
    check(refusal(["둘", "넷"]) == ArisTypeRequest.oneTextLine && refusal(["--app", "TextEdit"]) == ArisTypeRequest.usage && refusal([]) == ArisTypeRequest.usage,
          "fix-15 type: the text is one argument (two words are refused: quote them), and some text there must be")
    let dashed = ArisTypeRequest.call(["--app", "TextEdit", "--", "--title 둘"], keyboardApp: nil)
    let minus = ArisTypeRequest.call(["-5도", "--app", "TextEdit"], keyboardApp: nil)
    let spaced = ArisTypeRequest.call(["- 항목", "--app", "TextEdit"], keyboardApp: nil)
    if case .success(let a) = dashed, case .success(let b) = minus, case .success(let c) = spaced {
        check(a.text == "--title 둘" && b.text == "-5도" && c.text == "- 항목",
              "fix-15 type: after `--` the text may start like a flag; a minus before a digit or a space is text")
    } else {
        check(false, "fix-15 type: `--`, -5도 and \"- 항목\" are text (\(dashed), \(minus), \(spaced))")
    }
    check(ArisTypeRequest.usage.contains("--title") && ArisTypeRequest.usage.contains("--at end|start"), "fix-15 type: the usage line lists the flags")
    let tools = fix15Source("ArisTools/main.swift")
    check(tools.contains("type '<text>' [--app X] [--title <window>] [--at end|start]"), "fix-15 type: aris-tools' own usage says the same")
}

// MARK: - 2. The engine's words

private func fix15EngineWordsTests() {
    let parse = { (words: [String], text: String?) in try? ArisDesktopWords.parse(words, text: text).get() }
    let focused = parse(["type", "--focused", "--app", "TextEdit", "--title", "noteC.txt", "--at", "end", "--stdin"], "둘")
    check(focused?.focused == true && focused?.app == "TextEdit" && focused?.title == "noteC.txt" && focused?.at == .end && focused?.text == "둘",
          "fix-15 words: `type --focused` takes --title (the window to look at) and --at end|start (the caret's place)")
    let onRef = parse(["type", "@s8f3k2:e3", "--at", "start", "--stdin"], "하나")
    check(onRef?.at == .start && parse(["type", "@s8f3k2:e3", "--title", "x", "--stdin"], "하나") == nil
          && parse(["type", "--focused", "--app", "TextEdit", "--at", "middle", "--stdin"], "둘") == nil
          && parse(["press", "cmd+down", "--app", "TextEdit", "--at", "end"], nil) == nil && parse(["set-value", "@s8f3k2:e3", "--at", "end", "--stdin"], "x") == nil,
          "fix-15 words: --at only on a type (end or start), --title on the focused type only (a ref has its window)")
    // The user's words first, then the brain's --at; neither: the caret stays.
    check(ArisDesktopCaret.place(said: "창 끝에 둘 입력해 줘", asked: .start) == .end && ArisDesktopCaret.place(said: "둘 입력해 줘", asked: .start) == .start
          && ArisDesktopCaret.place(said: "둘 입력해 줘", asked: nil) == nil,
          "fix-15 words: the user's \"끝에\" or \"맨 앞\" wins; with neither, the brain's --at; else the caret stays where it is")
    // A saved type keeps the place it was typed at, and its replay asks for it again.
    let step = ArisSavedStep(action: .type, bundle: "com.apple.TextEdit", app: "TextEdit", window: "noteC.txt", role: "textField", path: [], text: "둘",
                             lookJudged: false, contentLabel: true, at: "end")
    check(ArisSavedSteps.words(step, ref: "@s1:e2")?.words == ["type", "@s1:e2", "--at", "end", "--stdin"] && ArisSavedSteps.replayable(step, request: "noteC에 '둘' 입력해 줘"),
          "fix-15 words: a saved type with its place replays with --at")
    var odd = step
    odd.at = "middle"
    check(!ArisSavedSteps.replayable(odd, request: "noteC에 '둘' 입력해 줘"), "fix-15 words: a place that isn't end or start (a changed file) is never replayed")
}

// MARK: - 3. A replay's step: the taint its live run had for its app

private func fix15ReplayTaintTests() {
    typealias R = ArisSavedStepsReplay
    check(R.stepTaint(learned: .outsideText, conversation: .none, stepClean: true, readOther: false) == .none
          && R.stepTaint(learned: .outsideText, conversation: .screenSeen, stepClean: true, readOther: false) == .screenSeen,
          "fix-15 taint: a step its live run did with no outside text for its app runs under the conversation's own taint only")
    check(R.stepTaint(learned: .outsideText, conversation: .none, stepClean: false, readOther: false) == .outsideText
          && R.stepTaint(learned: .none, conversation: .none, stepClean: true, readOther: true) == .outsideText,
          "fix-15 taint: any other step under the recipe's (review 10 L2), and another app's window read in the replay is outside text")
    let ledger = ArisComputerUseLedger()
    ledger.replayStep(afterYes: false, clean: true)
    let during = ledger.replayStepClean
    ledger.replayStep(afterYes: false)
    check(during && !ledger.replayStepClean, "fix-15 taint: the replay says which step is clean, and only while it runs")
    let main = fix15Source("ArisAgent/main.swift"), live = fix15Source("ArisAgent/ArisSavedStepsLive.swift")
    check(main.contains("taint: ArisSavedStepsReplay.startTaint(recipe, sawScreen: sawScreen, sawOutside: sawOutside)")
          && main.contains("conversation: ArisSavedStepsReplay.conversationTaint(sawScreen: sawScreen, sawOutside: sawOutside)")
          && live.contains("ArisSavedStepsReplay.stepTaint(learned: current, conversation: conversation, stepClean: clean"),
          "fix-15 taint: wiring: the agent's replay turn starts with both and reads each step's taint by that rule")
    let engine = fix15Source("ArisAgent/ArisDesktopEngine.swift")
    check(engine.contains("step.appClean = true"), "fix-15 taint: wiring: a live step done with no outside text for its app is kept so")
}

// MARK: - The AppKit key-panel harnesses, robust to another suite running at once

/// The file every suite's key-panel harnesses take their turn on: there is one key window on the Mac, so two test runs
/// (two worktrees at once) took it from each other and BUG-22, vm2 B12 and vm4 4 failed (twice, 2026-11-13).
let keyPanelLockPath = NSTemporaryDirectory() + "aris-tests-appkit-key-panels.lock"
/// How many times a harness runs before its failures count: another process (an older suite, any app coming forward)
/// can still take the key window for a moment.
let keyPanelAttempts = 3

/// `body` (a harness that makes a panel key and checks it), with this Mac's key window to itself among the suites: it
/// waits for the lock file, runs, and runs again (up to keyPanelAttempts) while any of its checks failed; the checks of
/// the last run are the ones told, so both runs of a suite list the same checks. A code fault fails every attempt.
@MainActor func keyPanelHarness(_ name: String, _ body: () -> Void) {
    let descriptor = open(keyPanelLockPath, O_CREAT | O_RDWR, 0o600)
    let locked = descriptor >= 0 && flock(descriptor, LOCK_EX) == 0
    if !locked { print("note: \(name): couldn't take \(keyPanelLockPath); running anyway") }
    defer {
        if descriptor >= 0 {
            flock(descriptor, LOCK_UN)
            close(descriptor)
        }
    }
    var results: [(ok: Bool, name: String, line: Int)] = []
    for attempt in 1...keyPanelAttempts {
        checkHeld = []
        body()
        results = checkHeld ?? []
        checkHeld = nil
        let failed = results.filter { !$0.ok }.count
        if failed == 0 { break }
        if attempt < keyPanelAttempts {
            print("note: \(name): \(failed) AppKit check(s) failed on attempt \(attempt) (the key window taken elsewhere?); running it again")
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        }
    }
    for result in results { check(result.ok, result.name, line: result.line) }
}
