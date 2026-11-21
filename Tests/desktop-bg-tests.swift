// Tests for desktop-bg (the owner, 2026-11-16: "the background process has to apply to ALL apps; Claude's and Codex's
// computer use work fine, Aris should be better"). Aris's own computer-use engine (ArisNativeRunner and its parts) under
// the unchanged controller and gate; terminals, code editors and AI apps are ordinary apps whose typing and Return go to
// The user's card; the engine choice defaults to Aris's own. Called from main.swift; uses its check(). Nothing here posts
// an event, reads a real window or takes a picture.
import CoreGraphics
import Foundation

private let bgRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private func bgSource(_ path: String) -> String { (try? String(contentsOf: bgRoot.appendingPathComponent(path), encoding: .utf8)) ?? "" }

func runDesktopBackgroundTests() {
    bgCallTests()
    bgReplyTests()
    bgKeyTests()
    bgDisplayTests()
    bgRoleTests()
    bgNeverListTests()
    bgGateTests()
    bgEngineChoiceTests()
    bgWordingTests()
    bgWiringTests()
    bgBenchFixTests()
}

// MARK: - The calls the controller builds, as the engine reads them

private func bgCallTests() {
    let see = ArisNativeCall(ArisPeekabooCommands.see(window: 42))
    check(see.verb == "see" && see.int("--window-id") == 42 && see.has("--tree") && see.value("--path") == nil, "native: a look's window and no picture")
    let shot = ArisNativeCall(ArisPeekabooCommands.see(window: 7, path: "/tmp/x.png", annotate: true))
    check(shot.value("--path") == "/tmp/x.png" && shot.has("--annotate"), "native: a look with a picture, annotated")
    let click = ArisNativeCall(ArisPeekabooCommands.click("elem_12", snapshot: "ps1_" + String(repeating: "a", count: 32), double: true, actionOnly: true))
    check(click.value("--on") == "elem_12" && click.has("--double") && click.value("--input-strategy") == "actionOnly", "native: a click's element and switches")
    let type = ArisNativeCall(ArisPeekabooCommands.type("--not-a-flag \\n 한글", window: 9))
    check(type.value("--text") == ArisPeekabooCommands.literal("--not-a-flag \\n 한글") && type.int("--window-id") == 9, "native: typed text is never read as a flag")
    let press = ArisNativeCall(ArisPeekabooCommands.press(["cmd+a", "delete"], snapshot: "ps1_x"))
    check(press.positional == ["cmd+a", "delete"] && press.value("--snapshot") == "ps1_x", "native: a press's keys are its plain words")
    let at = ArisNativeCall(ArisPeekabooCommands.clickAt(CGPoint(x: 10.4, y: 20.6), snapshot: "ps1_x", window: 3, foreground: false))
    check(at.point("--at") == CGPoint(x: 10, y: 21), "native: a point click's window-relative point")
    let menu = ArisNativeCall(ArisPeekabooCommands.menuClick("File > Export > PDF…", ArisDesktopTarget(name: "T", bundle: "dev.t", pid: 5, known: true, never: false, browser: false, sending: false)))
    check(menu.verb == "menu" && menu.positional == ["click"] && menu.value("--path") == "File > Export > PDF…" && menu.value("--app") == "dev.t", "native: a menu path and its app")
    let window = ArisNativeCall(ArisPeekabooCommands.window("move", window: 4, x: 10, y: 20))
    check(window.positional == ["move"] && window.int("--x") == 10 && window.int("--y") == 20, "native: a window's move")
}

// MARK: - The answer, as the controller reads it

private func bgReplyTests() {
    let done = ArisNativeReply.done(window: 31, pid: 400, extra: ["delivery": "background"])
    let parsed = ArisDesktopEnvelope.parse(done.json())
    check(parsed?.success == true && parsed?.dispatched == true && parsed?.windowId == 31 && parsed?.pid == 400, "native: a done action reads as dispatched, with its window and process")
    check(parsed?.state == "dispatched_unverified" && parsed?.safeToRepeat == false, "native: a dispatched action is never repeated")
    let elsewhere = ArisDesktopEnvelope.parse(ArisNativeReply.failure("FOCUS_ELSEWHERE", "the keyboard focus belongs to a different window", retrySafe: true).json())
    check(elsewhere?.success == false && elsewhere?.focusElsewhere == true && elsewhere?.safeToRepeat == true, "native: focus in another window reads as the controller's focus-elsewhere")
    let none = ArisDesktopEnvelope.parse(ArisNativeReply.failure("NO_ELEMENT", "No pressable accessibility element at that spot", retrySafe: true).json())
    check(none?.nothingPressable == true, "native: nothing pressable reads as such (the controller's pointer click comes next)")
    var look = ArisNativeReply(success: true, data: ["snapshot_id": "ps1_" + String(repeating: "b", count: 32), "window_title": "Untitled",
                                                    "ui_elements": [["id": "elem_1", "role": "textArea", "label": "", "value": "hi", "ax_role": "AXTextArea", "is_actionable": false,
                                                                     "bounds": ["x": 1.0, "y": 2.0, "width": 30.0, "height": 40.0]]],
                                                    "focused_element": ["role": "AXTextArea", "frame": [[1.0, 2.0], [30.0, 40.0]]]], window: 5, pid: 6)
    look.state = nil
    let seen = ArisDesktopEnvelope.parse(look.json())
    check(seen?.snapshotId != nil && seen?.elements.first?.value == "hi" && seen?.elements.first?.axRole == "AXTextArea" && seen?.focusedFrame == CGRect(x: 1, y: 2, width: 30, height: 40),
          "native: a look reads as Peekaboo's did (snapshot, elements, focused frame)")
    let target = ArisDesktopTarget(name: "TextEdit", bundle: "com.apple.TextEdit", pid: 6, known: true, never: false, browser: false, sending: false)
    let observation = seen.flatMap { ArisDesktopObservation.make($0, target: target, window: 5, identity: ArisDesktopIdentity(userName: "u", fullName: "U", home: "/Users/u")) }
    check(observation?.elements.count == 1 && observation?.isFocused(observation!.elements[0]) == true, "native: the observation finds the focused field")
}

// MARK: - Keys and text

private func bgKeyTests() {
    typealias I = ArisNativeInput
    check(I.pieces("hi\\nthere") == [.text("hi"), .key(36), .text("there")], "keys: \\n in typed text is Return, as Peekaboo read it")
    check(I.pieces("a\\\\b") == [.text("a\\b")], "keys: a doubled backslash is one backslash")
    check(I.pieces("x\ty") == [.text("x"), .key(48), .text("y")] && I.pieces("x\ny") == [.text("x"), .key(36), .text("y")], "keys: a real tab or line break is its key")
    let long = String(repeating: "가", count: 40)
    let chunks = I.pieces(long)
    check(chunks.count == 3 && chunks.allSatisfy { if case .text(let t) = $0 { return t.utf16.count <= 16 } else { return false } }, "keys: Korean in chunks of at most 16 units")
    check(chunks.map { if case .text(let t) = $0 { return t } else { return "" } }.joined() == long, "keys: the chunks are the text, in order")
    check(I.pieces("\\e") == [.key(53)] && I.pieces("\\b") == [.key(51)], "keys: \\e escape, \\b delete")
    check(I.chord("return")?.key == 36 && I.chord("enter")?.key == 36 && I.chord("cmd+a")?.flags.contains(.maskCommand) == true, "keys: named keys and chords")
    check(I.chord("shift+tab")?.key == 48 && I.chord("shift+tab")?.flags.contains(.maskShift) == true, "keys: shift+tab")
    check(I.chord("home")?.key == 115 && I.chord("f5")?.key == 96 && I.chord("cmd+pagedown")?.flags == .maskCommand, "keys: the names past ArisKeyChord's")
    check(I.chord("meta+s")?.flags.contains(.maskCommand) == true, "keys: meta is command")
    check(I.chord("hyper+x") == nil && I.chord("nosuchkey") == nil, "keys: an unknown key is no key")
    check(!I.takesBackgroundKeys(bundle: "dev.warp.Warp-Stable", bundleURL: nil), "keys: Warp only takes keys in front (measured in the VM)")
    check(I.takesBackgroundKeys(bundle: "com.apple.TextEdit", bundleURL: nil), "keys: a native app takes them in the background")
    I.learnForeground("dev.test.learned")
    check(!I.takesBackgroundKeys(bundle: "dev.test.learned", bundleURL: nil), "keys: an app a background type missed goes in front after")
}

// MARK: - Displays

private func bgDisplayTests() {
    typealias D = ArisNativeDisplays
    let main = CGRect(x: 0, y: 0, width: 1440, height: 900), side = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
    let onSide = CGRect(x: 1600, y: 100, width: 800, height: 600), onMain = CGRect(x: 100, y: 100, width: 800, height: 600)
    check(D.display(of: onSide, in: [main, side]) == 1 && D.display(of: onMain, in: [main, side]) == 0, "displays: a window's display is where most of it is")
    check(D.isOther(onSide, front: onMain, pointer: CGPoint(x: 500, y: 500), displays: [main, side]), "displays: the target on the other display than the user's pointer")
    check(!D.isOther(onMain, front: onMain, pointer: CGPoint(x: 500, y: 500), displays: [main, side]), "displays: the same display as his pointer")
    check(D.isOther(onSide, front: onMain, pointer: nil, displays: [main, side]), "displays: no pointer: his front window's display")
    check(!D.isOther(onSide, front: onMain, pointer: CGPoint(x: 500, y: 500), displays: [main]), "displays: one display is never another")
    let source = bgSource("ArisAgent/ArisNativeInput.swift")
    check(source.contains("func restore()") && source.contains("made.restore()"), "displays: a turn in front that didn't take puts the front app back too")
}

// MARK: - The tree's roles

private func bgRoleTests() {
    check(ArisAX.shortRole("AXTextField", subrole: nil) == "textField" && ArisAX.shortRole("AXPopUpButton", subrole: nil) == "popUpButton", "roles: the controller's names")
    check(ArisAX.shortRole("AXCheckBox", subrole: "AXSwitch") == "switch" && ArisAX.shortRole("", subrole: nil) == "other", "roles: a switch, and none")
    check(ArisAX.shortRole("AXWebArea", subrole: nil) == "webArea", "roles: a web area as the controller looks for it")
    check(ArisAX.pressActions.contains("AXPress") && ArisAX.pressActions.contains("AXShowMenu"), "roles: the actions that make a control clickable")
    check(!ArisAX.isWebShell(bundleURL: nil) && !ArisAX.isWebShell(bundleURL: URL(fileURLWithPath: "/System/Applications/TextEdit.app")), "roles: a native app isn't a web shell")
}

// MARK: - What is never, and what is a code runner

private func bgNeverListTests() {
    typealias R = ArisRiskPolicy
    for app in ["Terminal", "com.apple.Terminal", "Warp", "iTerm2", "Visual Studio Code", "com.todesktop.230313mzl4w4u92", "Claude", "com.google.antigravity", "Xcode", "ChatGPT"] {
        check(!R.computerUseIsNever([app]), "never-list: \(app) is an ordinary app now")
        check(R.isCodeRunner([app]), "never-list: \(app) is a code runner (its typing goes to the card)")
        check(R.computerUseIsNeverForOthers([app]), "never-list: \(app) stays off limits for Codex's own computer use")
    }
    for app in ["com.apple.installer", "Aris", "com.lumenjsn.aris", "SecurityAgent", "Peekaboo"] {
        check(R.computerUseIsNever([app]), "never-list: \(app) stays never")
    }
    // The user 2026-11-16 ("막지마"): password apps, Keychain Access and System Information are ordinary apps, for Codex's own
    // computer use too (they run no code).
    for app in ["Keychain Access", "1Password", "com.1password.1password", "Passwords", "com.apple.Passwords", "System Information", "com.apple.SystemProfiler"] {
        check(!R.computerUseIsNever([app]) && !R.computerUseIsNeverForOthers([app]) && !R.isCodeRunner([app]), "never-list: \(app) is an ordinary app now")
    }
    check(R.isTerminalApp(["Ghostty"]) && R.isTerminalApp(["dev.warp.Warp-Stable"]) && !R.isTerminalApp(["Visual Studio Code"]), "never-list: the terminals among them")
    check(!R.isCodeRunner(["TextEdit"]) && !R.isCodeRunner(["Notes"]), "never-list: ordinary apps aren't code runners")
}

// MARK: - The gate

private func bgTarget(_ name: String, bundle: String, terminal: Bool) -> ArisDesktopTarget {
    var target = ArisDesktopTarget(name: name, bundle: bundle, pid: 9, known: true, never: false, browser: false, sending: false)
    target.codeRunner = true
    target.terminal = terminal
    return target
}

private func bgGateTests() {
    typealias G = ArisDesktopGate
    let terminal = bgTarget("Terminal", bundle: "com.apple.Terminal", terminal: true)
    let code = bgTarget("Visual Studio Code", bundle: "com.microsoft.VSCode", terminal: false)
    func request(_ verb: ArisDesktopVerb, text: String? = nil, keys: [String] = []) -> ArisDesktopRequest {
        var made = ArisDesktopRequest(verb: verb)
        made.text = text
        made.keys = keys
        made.app = "x"
        return made
    }
    let clean = ArisDesktopContext()
    // Typing and Return in a terminal: the card every time, even with the user's earlier yes for the app.
    check(G.decide(request(.type, text: "ls -la"), target: terminal, context: clean, remembered: true, secureInput: false) == .ask(remember: false),
          "gate: typing into a terminal asks every time (a remembered yes doesn't cover it)")
    check(G.decide(request(.press, keys: ["return"]), target: terminal, context: clean, remembered: true, secureInput: false) == .ask(remember: false),
          "gate: Return in a terminal asks every time")
    check(G.decide(request(.press, keys: ["a"]), target: terminal, context: clean, remembered: true, secureInput: false) == .ask(remember: false),
          "gate: a character key in a terminal asks")
    check(G.decide(request(.setValue, text: "rm"), target: terminal, context: clean, remembered: true, secureInput: false) == .ask(remember: false), "gate: set-value in a terminal asks")
    // Clicks, reads and other keys are ordinary there.
    check(G.decide(request(.see), target: terminal, context: clean, remembered: false, secureInput: false) == .run, "gate: a look at a terminal runs (no longer never)")
    check(G.decide(request(.click), target: terminal, context: clean, remembered: true, secureInput: false) == .run, "gate: a click in a terminal is ordinary (remembered yes)")
    check(G.decide(request(.press, keys: ["cmd+t"]), target: terminal, context: clean, remembered: true, secureInput: false) == .run, "gate: a shortcut that types nothing is ordinary")
    // A paste: only with the clipboard on the card.
    check(G.decide(request(.press, keys: ["cmd+v"]), target: terminal, context: clean, remembered: true, secureInput: false) == .refuse(G.codeRunnerPasteRefusal),
          "gate: a paste into a terminal whose clipboard the card can't show is refused")
    var withClip = clean
    withClip.clipboard = "make test"
    check(G.decide(request(.press, keys: ["cmd+v"]), target: terminal, context: withClip, remembered: true, secureInput: false) == .ask(remember: false),
          "gate: a paste with its text on the card asks")
    // An editor: typing into its editor is ordinary; its terminal (or a field Aris can't tell) asks.
    let editor = ArisDesktopElement(id: "elem_3", role: "textArea", label: "Editor content", axRole: "AXTextArea")
    let console = ArisDesktopElement(id: "elem_4", role: "textArea", label: "Terminal 1, zsh", axRole: "AXTextArea")
    check(G.decide(request(.type, text: "let x = 1"), target: code, context: clean, remembered: true, secureInput: false, element: editor) == .run,
          "gate: typing into an editor's document is ordinary")
    check(G.decide(request(.type, text: "npm test"), target: code, context: clean, remembered: true, secureInput: false, element: console) == .ask(remember: false),
          "gate: typing into an editor's terminal asks every time")
    check(G.decide(request(.type, text: "x"), target: code, context: clean, remembered: true, secureInput: false) == .ask(remember: false),
          "gate: typing into an editor with no field named asks")
    check(G.decide(request(.press, keys: ["return"]), target: code, context: clean, remembered: true, secureInput: false) == .ask(remember: false), "gate: Return in an editor asks")
    // Never stays never; a password store is an ordinary app now (the user 2026-11-16).
    let installer = ArisDesktopTarget(name: "Installer", bundle: "com.apple.installer", pid: 3, known: true, never: true, browser: false, sending: false)
    check(G.decide(request(.see), target: installer, context: clean, remembered: false, secureInput: false) == .refuse(G.neverRefusal), "gate: the installer stays never")
    let vault = ArisDesktopTarget(name: "1Password", bundle: "com.1password.1password", pid: 3, known: true, never: false, browser: false, sending: false)
    check(G.decide(request(.see), target: vault, context: clean, remembered: false, secureInput: false) == .run
          && G.decide(request(.click), target: vault, context: clean, remembered: true, secureInput: false) == .run
          && G.decide(request(.type, text: "x"), target: vault, context: clean, remembered: false, secureInput: true) == .refuse(G.secureRefusal),
          "gate: a password store is ordinary (a look runs, a remembered click runs, a password field still stops typing)")
    check(G.decide(request(.type, text: "x"), target: terminal, context: clean, remembered: false, secureInput: true) == .refuse(G.secureRefusal), "gate: secure input still stops typing")
    check(G.looksLikeTerminal(console) && !G.looksLikeTerminal(editor), "gate: a terminal field by what it says of itself")
}

// MARK: - The engine choice

private func bgEngineChoiceTests() {
    typealias E = ArisComputerEngine
    check(E.named(nil) == .aris && E.named("nonsense") == .aris && E.named("peekaboo") == .peekaboo && E.named("codex") == .codex, "engine: Aris's own unless one is picked")
    check(E.effective(picked: .codex, codexInstalled: false) == .aris && E.effective(picked: .codex, codexInstalled: true) == .codex, "engine: Codex only when it is installed")
    check(E.effective(picked: .peekaboo, codexInstalled: true) == .peekaboo && E.aris.usesPeekaboo == false && E.peekaboo.usesPeekaboo, "engine: Peekaboo only when picked")
    check(E.aris.title == "Aris (기본)" && E.aris.title(english: true) == "Aris (default)", "engine: its name in the settings")
    check(E.allCases.first == .aris, "engine: listed first")
    check(ArisDesktopFallback.next(brain: .claude, engine: .aris) == .lookAndClick, "engine: a poor tree on Aris's engine looks and clicks")
}

// MARK: - The lines

private func bgWordingTests() {
    check(!ArisDesktopGate.neverRefusal.contains("terminals") && !ArisDesktopGate.neverRefusal.contains("password stores")
          && !ArisDesktopGate.neverRefusal.contains("Keychain") && ArisDesktopGate.neverRefusal.contains("the installer"),
          "lines: the never line names neither terminals nor password stores and Keychain (the user 2026-11-16)")
    let note = ArisRefusalWords.neverNote(.computerUse(app: "Installer"), why: "never", tools: "aris-tools") ?? ""
    check(note.contains("Terminals and code editors are ordinary apps") && !note.contains("terminals, code editors, password stores")
          && !note.contains("password stores") && !note.contains("Keychain"), "lines: the brain's refusal says terminals are ordinary now and names no password store")
    let prompt = ArisAgentPrompt.desktopRule("aris-tools", form: .shell)
    check(prompt.contains("Aris works the app in the background") && prompt.contains("always go to the user's card with the exact text"), "lines: every brain's prompt says background and the terminal card")
    check(prompt.contains("VS Code") && prompt.contains("a terminal"), "lines: the prompt names editors and terminals as apps it works")
    // The user 2026-11-16: nothing tells a brain that password managers or Keychain are off limits.
    let whyKo = ArisWhyRules.plain("computer use is never in that app", korean: true)?.why ?? ""
    let whyEn = ArisWhyRules.plain("computer use is never in that app", korean: false)?.why ?? ""
    check(!prompt.contains("password manager") && !prompt.contains("Keychain") && !whyKo.isEmpty && !whyKo.contains("비밀번호") && !whyKo.contains("키체인")
          && !whyEn.isEmpty && !whyEn.contains("password"),
          "lines: the desktop prompt and the plain why name no password manager or Keychain as off limits")
    let session = ArisAgentPrompt.sessionRule("aris-tools", form: .shell)
    check(!session.contains("no desktop, keys or type there") && session.contains("Never desktop typing into a Claude Code session"), "lines: Claude Code sessions still go through the session tool")
    let why = bgSource("ArisAgent/ArisWhyRules.swift")
    check(why.contains("그 앱(설치 프로그램, 로그인·권한 창, Aris 자신)") && !why.contains("그 앱(터미널") && !why.contains("비밀번호 앱, 키체인"),
          "lines: the Korean why line names neither terminals nor password apps and Keychain (the user 2026-11-16)")
}

// MARK: - Bench findings (VM, 2026-11-16)

private func bgBenchFixTests() {
    // A terminal wraps a long typed command at its edge: still read back as typed (it was retyped twice).
    let command = "printf done > /Users/admin/aris-bench/tmp/run/term.txt"
    let field = ArisDesktopElement(id: "elem_2", role: "textArea", label: "shell", value: "x", rawValue: "admin$ printf done > /Users/admin/aris-bench/tmp/\nrun/term.txt")
    let target = ArisDesktopTarget(name: "Terminal", bundle: "com.apple.Terminal", pid: 3, known: true, never: false, browser: false, sending: false)
    let after = ArisDesktopObservation(snapshot: "s1", peekaboo: "ps1_x", target: target, window: 1, title: "t", elements: [field], focused: nil, isDialog: false, hidden: false)
    if case .done = ArisDesktopVerify.typed(command, field: field, after: after, before: "admin$ ") {} else { check(false, "bench: a wrapped command reads back as typed") }
    if case .notSeen = ArisDesktopVerify.typed("echo other thing entirely", field: field, after: after, before: "") {} else { check(false, "bench: other text doesn't") }
    let runner = bgSource("ArisAgent/ArisNativeRunner.swift"), input = bgSource("ArisAgent/ArisNativeInput.swift")
    check(runner.contains("ArisNativeInput.selectOrPressAncestor(element)") && input.contains("kAXSelectedAttribute as CFString, kCFBooleanTrue"),
          "bench: a list row with no action of its own is selected, as a click selects it")
    check(runner.contains("ArisNativeInput.step(element, to: wanted)") && runner.contains("NSNumber(value: $0)"), "bench: a slider's value is set as a number, or stepped to it")
    check(bgSource("ArisAgent/ArisDesktopController.swift").contains("withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])) != nil else { return nil }"),
          "bench: a look's picture folder is made with its parent (no Peekaboo state folder)")
    check(!bgSource("ArisAgent/ArisDesktopActions.swift").contains("Peekaboo said") && !bgSource("ArisAgent/ArisDesktopTextLadder.swift").contains("Peekaboo said"),
          "bench: the engine's words aren't called Peekaboo's")
}

// MARK: - Wiring

private func bgWiringTests() {
    let live = bgSource("ArisAgent/ArisDesktopLive.swift")
    check(live.contains("native: .shared"), "wiring: the agent's engine has Aris's own engine")
    let controller = bgSource("ArisAgent/ArisDesktopController.swift")
    check(controller.contains("engine.native!.run(arguments, context: ArisNativeContext(job: turn.isTask, owner: turn.desktopOwner"), "wiring: every call runs on it, a job's without a turn in front")
    check(controller.contains("if !usesNative, installer.state != .ready"), "wiring: nothing is downloaded for Aris's own engine")
    let runner = bgSource("ArisAgent/ArisNativeRunner.swift")
    check(runner.contains("guard !context.job else"), "wiring: a background job never gets a turn in front")
    check(!runner.contains("CGWarpMouseCursorPosition(") || runner.contains("if let before { CGWarpMouseCursorPosition(before) }"), "wiring: a pointer moved for a drag is put back")
    let input = bgSource("ArisAgent/ArisNativeInput.swift")
    check(input.contains("event.postToPid(pid)") && input.contains("if let before { CGWarpMouseCursorPosition(before) }"), "wiring: keys go to the app's process; a pointer click puts it back")
    let engine = bgSource("ArisAgent/ArisDesktopEngine.swift")
    check(engine.contains("if target.sending || target.codeRunner, ArisDesktopGate.pastes(request) { context.clipboard = apps.clipboardText() }"),
          "wiring: a paste into a code runner reads the clipboard for the card")
}
