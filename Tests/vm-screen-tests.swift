// Tests for the two defects the VM run of 10–11 Nov 2026 found in screen questions (qa/vm-run-1110/REPORT.md, bugs 1
// and 2). Bug 1: once aris-agent was given Screen Recording while it ran, every answer about the screen still ended
// with "Screen Recording isn't allowed", because the agent asked its own process, whose answer never changes after it
// starts. Bug 2: the first screen questions on an upgraded Mac raised three macOS prompts for "aris-agent", in the
// middle of the question and behind the open notch. Pinned here: what the reply says for each of "the capture gave a
// picture or words / gave nothing / the permission is known to be off", that a look asks macOS for nothing, and that
// the app's own picture is the screen read when it is there. Called from main.swift; uses its check().
import Foundation

func runVMScreenTests() {
    vmScreenOutcomeTests()
    vmScreenLineTests()
    vmScreenReplyTests()
    vmScreenAccessTests()
    vmScreenToolTests()
    MainActor.assumeIsolated { vmScreenPictureTests() }
    vmScreenSourceTests()
    vmScreenRestartTests()
}

private typealias Read = ArisScreenRead

private func source(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("..")
    return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

/// The lines of a source file that are code (a comment may name what the code no longer does).
private func code(_ path: String) -> String {
    source(path).split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
}

/// The Screen Recording list's name on the VM's macOS (26).
private let list = Read.listName(macOSMajor: 26)
private let noGrantWords = "화면을 읽으려면 aris-agent에 화면 기록 권한이 필요한데, 지금 꺼져 있어요."
private let noWindowWords = "Finder의 창이 화면에 없어서 읽지 못했어요."

// MARK: - Bug 1: what a read of the front window came to

private func vmScreenOutcomeTests() {
    let words = "Finder — Desktop\nqanote.txt\nreport.txt"
    let read = Read.Captured(status: 0, output: words + "\n", errors: "")
    check([true, false, nil].allSatisfy { Read.outcome(captured: read, allowed: $0) == .text(words) },
          "vm bug 1: a capture that came back with the window's words is the screen read, whatever any permission check says")
    let failed = Read.Captured(status: 1, output: "", errors: "could not create image from window\n\(noGrantWords)\n")
    check(Read.outcome(captured: failed, allowed: false) == .permissionOff && Read.outcome(captured: nil, allowed: false) == .permissionOff,
          "vm bug 1: nothing came back and macOS says aris-agent may not record: the permission is the reason, tried or not")
    let windowless = Read.Captured(status: 1, output: "", errors: noWindowWords + "\n")
    check(Read.outcome(captured: windowless, allowed: true) == .nothing(noWindowWords)
          && Read.outcome(captured: failed, allowed: nil) == .nothing(noGrantWords)
          && Read.outcome(captured: nil, allowed: true) == .nothing(nil) && Read.outcome(captured: nil, allowed: nil) == .nothing(nil),
          "vm bug 1: nothing came back while the permission is on or unknown: no permission is blamed, the tool's own reason is kept")
    check(Read.outcome(captured: Read.Captured(status: 0, output: " \n", errors: ""), allowed: true) == .nothing(nil)
          && Read.outcome(captured: Read.Captured(status: 0, output: " \n", errors: ""), allowed: false) == .permissionOff,
          "vm bug 1: a run that printed nothing is no read")
    check(Read.outcome(captured: Read.Captured(status: 1, output: "", errors: String(repeating: "x", count: 900)), allowed: true)
          == .nothing(String(repeating: "x", count: Read.reasonLimit)),
          "vm bug 1: a long complaint is cut before it reaches the AI")
}

// MARK: - Bug 1: what the AI is told when the window's words didn't come

private func vmScreenLineTests() {
    let off = Read.unreadLine(.permissionOff, list: list) ?? ""
    check(off.contains("\"Aris\"") && off.contains("System Settings › Privacy & Security › Screen & System Audio Recording") && off.contains("ask again"),
          "vm bug 1: with the permission really off the line names the row to switch on as System Settings shows it (Aris: the helper is inside the app), where it is, and what to do next")
    check(off.contains("press +") && off.contains("Applications") && !off.contains("⌘⇧G") && !off.contains("~/.config") && !off.contains("aris-agent"),
          "one row: the line says how to add Aris when the list doesn't hold it yet, and never names the helper's file")
    check(Read.row == "Aris" && !off.contains("not the \"Aris\" row"), "one row: there is one row, and the line sends the user to it")
    check(Read.listName(macOSMajor: 14) == "Screen Recording" && Read.listName(macOSMajor: 15) == "Screen & System Audio Recording"
          && (Read.unreadLine(.permissionOff, list: Read.listName(macOSMajor: 14)) ?? "").contains("Privacy & Security › Screen Recording, "),
          "vm bug 1: the list is called what this macOS calls it")
    check(Read.unreadLine(.text("Finder — Desktop"), list: list) == nil, "vm bug 1: a read that worked earns no line about permissions at all")
    let windowless = Read.unreadLine(.nothing(noWindowWords), list: list) ?? ""
    let unknown = Read.unreadLine(.nothing(nil), list: list) ?? ""
    check(windowless.contains(noWindowWords) && !windowless.contains("\"Aris\"") && !windowless.contains("Screen") && !windowless.contains("System Settings")
          && unknown.contains("could not be read") && !unknown.contains("Screen") && !unknown.contains("System Settings"),
          "vm bug 1: a read that failed for another reason says so with that reason, and blames no permission")
    check([off, windowless, unknown].allSatisfy { $0.hasPrefix("(") && $0.hasSuffix(")") && $0.contains("guess") },
          "vm bug 1: each line is an aside for the AI that also tells it not to guess what is on the screen")
    let selection = Read.unselectedLine
    check(selection.contains("\"Aris\"") && selection.contains("System Settings › Privacy & Security › Accessibility")
          && !selection.contains("aris-agent") && !selection.contains("~/.config") && selection.contains("in your answer"),
          "vm bug 2: a selection that couldn't be read names Aris's Accessibility row (one row), and the new text still comes in the answer")
}

// MARK: - Bugs 1 and 2: what goes to the AI with the question, for each combination

private func vmScreenReplyTests() {
    let context = "Front app: Finder\nWindow: Desktop"
    let off = Read.unreadLine(.permissionOff, list: list), none = Read.unreadLine(.nothing(noWindowWords), list: list)
    func words(_ unread: String?, pictured: Bool, rewrite: Bool = false, unselected: String? = nil) -> String {
        ArisLookContext.words(context: context, unread: unread, unselected: unselected, pictured: pictured, rewrite: rewrite)
    }
    // The capture returned a picture: the app's screenshot goes with the question.
    check(words(off, pictured: true) == context && words(none, pictured: true) == context && words(nil, pictured: true) == context,
          "vm bug 1: with the app's picture of the screen in hand the reply is never told the screen couldn't be read, whatever aris-agent itself may do")
    // The capture returned nothing and the permission is known off.
    let told = words(off, pictured: false)
    check(told.hasPrefix(context + "\n") && told.contains("\"Aris\"") && !told.contains("aris-agent") && told.contains("Screen & System Audio Recording"),
          "vm bug 1: with no picture and Screen Recording off for aris-agent the reply is told which row to switch on")
    // The capture returned nothing though the permission is on.
    let failed = words(none, pictured: false)
    check(failed.contains(noWindowWords) && !failed.contains("Screen") && !failed.contains("aris-agent"),
          "vm bug 1: with no picture and the permission on, the reply says the window couldn't be read and names no permission")
    // The window's words came (they are in the context itself).
    check(words(nil, pictured: false) == context, "vm bug 1: when the window's words came nothing is added")
    check(words("", pictured: false) == context, "vm bug 1: an empty line from an older agent adds nothing")
    // Accessibility off for aris-agent: said only when the words ask to change what is selected.
    let line = Read.unselectedLine
    check(words(nil, pictured: true, rewrite: true, unselected: line) == context + "\n" + line
          && words(nil, pictured: true, rewrite: false, unselected: line) == context
          && words(nil, pictured: true, rewrite: true, unselected: nil) == context,
          "vm bug 2: aris-agent's missing Accessibility is said only for a request to change the selection, never under every answer")
    check(ArisLookContext.lacks(["accessibility", "screen"]) == " (the helper lacks: accessibility, screen)" && ArisLookContext.lacks([]) == "",
          "vm bug 2: the log names what aris-agent lacked for a look")
}

// MARK: - Bug 1: a grant given while the agent runs is seen at once

private func vmScreenAccessTests() {
    var asked = 0
    check(Read.allowed(known: true) { asked += 1; return false } == true && asked == 0,
          "vm bug 1: an agent that already saw the permission on asks nobody")
    check(Read.allowed(known: false) { asked += 1; return true } == true && asked == 1,
          "vm bug 1: an agent that started without the permission asks macOS anew each time, so a grant given while it runs counts at once (no restart)")
    check(Read.allowed(known: false) { false } == false && Read.allowed(known: false) { nil } == nil,
          "vm bug 1: off is off, and an answer that couldn't be had is unknown, never off")
    check(Read.needs(accessibility: false, screen: false) == ["accessibility", "screen"] && Read.needs(accessibility: true, screen: false) == ["screen"]
          && Read.needs(accessibility: false, screen: true) == ["accessibility"] && Read.needs(accessibility: true, screen: true).isEmpty
          && Read.needs(accessibility: true, screen: nil).isEmpty,
          "vm bug 2: a look reports which of aris-agent's own permissions it had to do without")
    check(ArisScreenAccess.parse("on") == true && ArisScreenAccess.parse("off") == false && ArisScreenAccess.parse(nil) == nil
          && ArisScreenAccess.parse("Finder — Desktop") == nil && ArisScreenAccess.parse("") == nil,
          "vm bug 1: the fresh check's answer is on, off, or not an answer")
}

// MARK: - Bugs 1 and 2: the agent's own read, with a stand-in for aris-tools

/// A folder with stand-ins for aris-tools; removed by the caller.
private struct FakeTools {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-vm-screen-\(UUID().uuidString)")

    init() { try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }

    /// A shell script named `name`; every run adds its words to `<name>.ran`.
    func script(_ name: String, _ body: String) -> String {
        let file = folder.appendingPathComponent(name)
        let text = "#!/bin/sh\necho \"$*\" >> \"\(file.path).ran\"\n\(body)\n"
        try? text.write(to: file, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file.path
    }

    func runs(of tool: String) -> [String] {
        ((try? String(contentsOfFile: tool + ".ran", encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    }
}

private func vmScreenToolTests() {
    let fake = FakeTools()
    defer { try? FileManager.default.removeItem(at: fake.folder) }
    let environment = ["PATH": "/usr/bin:/bin"]

    // The fresh check: a new process answers, so the answer is today's.
    let on = fake.script("on", #"[ "$1 $2" = "screen --access" ] && echo on"#)
    let off = fake.script("off", #"[ "$1 $2" = "screen --access" ] && echo off"#)
    let old = fake.script("old", #"echo "Finder — Desktop"; echo "qanote.txt""#)
    check(ArisScreenAccess.fresh(tools: on, environment: environment) == true && ArisScreenAccess.fresh(tools: off, environment: environment) == false
          && fake.runs(of: on) == ["screen --access"],
          "vm bug 1: whether aris-agent may record the screen is asked of a new aris-tools process (screen --access)")
    check(ArisScreenAccess.fresh(tools: old, environment: environment) == nil
          && ArisScreenAccess.fresh(tools: fake.folder.appendingPathComponent("missing").path, environment: environment) == nil,
          "vm bug 1: a tool that can't say is unknown, never off")

    // Reading the front window.
    let reads = fake.script("reads", #"echo "Finder — Desktop"; echo "qanote.txt""#)
    let read = ArisLook.frontWindowText(tools: reads, environment: environment, allowed: true, fresh: { false })
    check(read.text == "Finder — Desktop\nqanote.txt" && read.outcome == .text("Finder — Desktop\nqanote.txt") && fake.runs(of: reads) == ["screen"],
          "vm bug 1: the window's words that came back are the read (a check that still says off changes nothing)")

    let untried = fake.script("untried", "echo should-not-run")
    let denied = ArisLook.frontWindowText(tools: untried, environment: environment, allowed: false, fresh: { false })
    let unknown = ArisLook.frontWindowText(tools: untried, environment: environment, allowed: nil, fresh: { nil })
    check(denied.text == nil && denied.outcome == .permissionOff && unknown.text == nil && unknown.outcome == .nothing(nil) && fake.runs(of: untried).isEmpty,
          "vm bug 2: while aris-agent may not record the screen no capture is even tried, so macOS has nothing to ask in the middle of a question")

    let fails = fake.script("fails", "echo 'could not create image from window' >&2; echo '\(noGrantWords)' >&2; exit 1")
    var freshAsks = 0
    let revoked = ArisLook.frontWindowText(tools: fails, environment: environment, allowed: true, fresh: { freshAsks += 1; return false })
    check(revoked.text == nil && revoked.outcome == .permissionOff && freshAsks == 1,
          "vm bug 1: a capture that failed is checked anew: the permission was switched off since the agent last saw it on")
    let hiccup = ArisLook.frontWindowText(tools: fails, environment: environment, allowed: true, fresh: { true })
    check(hiccup.text == nil && hiccup.outcome == .nothing(noGrantWords),
          "vm bug 1: a capture that failed while the permission is on blames no permission")

    let ran = ArisLook.ran(fails, ["screen"], environment)
    check(ran?.status == 1 && ran?.output == "" && ran?.errors.contains("could not create image") == true
          && ArisLook.ran(fake.folder.appendingPathComponent("missing").path, ["screen"], environment) == nil,
          "vm bug 1: a run of aris-tools comes back with how it ended and what it complained of; a tool that can't start is no run")
    check(ArisLook.tool(reads, ["screen"], environment) == "Finder — Desktop\nqanote.txt" && ArisLook.tool(fails, ["screen"], environment) == nil,
          "vm bug 1: the look's other reads work as before (words on success, nothing on failure)")
}

// MARK: - Bug 1: whether the app's own picture goes with the turn

@MainActor private func vmScreenPictureTests() {
    func spin(_ seconds: Double = 3, until done: () -> Bool) {
        let deadline = Date().addingTimeInterval(seconds)
        while !done(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
    }
    var granted = true, gives = true
    var shotDelay: Duration = .zero
    let png = Data([0x89, 0x50, 0x4E, 0x47]) + Data(repeating: 7, count: 5000)
    func make() -> ArisTurnCapture {
        ArisTurnCapture(dependencies: .init(
            shoot: { try? await Task.sleep(for: shotDelay); return gives ? ArisTurnCapture.Shot(png: png, ms: 42, retried: false) : nil },
            enabled: { true }, permission: { granted }, nextNotice: { nil }, notify: { _ in },
            waitAtSend: .milliseconds(300), keepFor: .seconds(30)))
    }
    func inHand(_ capture: ArisTurnCapture) -> Bool {
        var got: Bool?
        Task { @MainActor in got = await capture.inHand() }
        spin { got != nil }
        return got ?? false
    }
    func take(_ capture: ArisTurnCapture) -> ArisTurnCapture.Taken? {
        var got: ArisTurnCapture.Taken??
        Task { @MainActor in got = .some(await capture.image()) }
        spin { got != nil }
        return got ?? nil
    }

    let pictured = make()
    pictured.began(notchShowsAnswer: false)
    _ = pictured.heard("what's on my screen")
    let has = inHand(pictured), again = inHand(pictured)
    check(has && again && take(pictured)?.image.data == png,
          "vm bug 1: the turn's screenshot is in hand once it arrived, and looking for it takes nothing: the ask still gets it")

    let plain = make()
    plain.began(notchShowsAnswer: false)
    _ = plain.heard("what is the capital of france")
    let asked = Date()
    check(!inHand(plain) && Date().timeIntervalSince(asked) < 0.2, "vm bug 1: a turn that shot nothing has no picture, and nothing is waited for")

    granted = false
    let ungranted = make()
    ungranted.began(notchShowsAnswer: false)
    _ = ungranted.heard("what's on my screen")
    check(!inHand(ungranted), "vm bug 1: without Aris's own Screen Recording there is no picture")
    granted = true

    gives = false
    let blank = make()
    blank.began(notchShowsAnswer: false)
    _ = blank.heard("what's on my screen")
    check(!inHand(blank), "vm bug 1: a capture that gave nothing is no picture")
    gives = true

    shotDelay = .seconds(2)
    let slow = make()
    slow.began(notchShowsAnswer: false)
    _ = slow.heard("what's on my screen")
    let sent = Date()
    let slowHas = inHand(slow)
    check(!slowHas && Date().timeIntervalSince(sent) < 1.0, "vm bug 1: a capture still running is waited for only its limit, then counts as no picture")
    shotDelay = .zero

    let replaced = make()
    replaced.began(notchShowsAnswer: false)
    _ = replaced.heard("what's on my screen")
    spin(0.1) { false }
    replaced.began(notchShowsAnswer: false)
    check(!inHand(replaced), "vm bug 1: an earlier turn's screenshot is never this turn's picture")
}

// MARK: - Where the rules are used

private func vmScreenSourceTests() {
    let look = code("ArisAgent/ArisLook.swift")
    check(!look.contains("CGPreflightScreenCaptureAccess") && !look.contains("isn't allowed for Aris") && look.contains("ArisScreenAccess.allowed(tools: tools, environment: environment)"),
          "vm bug 1: the look no longer asks the agent's own process whether it may record, and no longer says “isn't allowed for Aris”")
    check(look.contains("let trusted = AXIsProcessTrusted()") && look.contains("guard trusted else") && look.contains("if trusted, AXUIElementCopyElementAtPosition")
          && !look.contains("AXIsProcessTrustedWithOptions"),
          "vm bug 2: the look reads other apps' elements only while aris-agent already has Accessibility, and never asks macOS for it")
    check(look.contains("if records, let text = tool(tools, [\"screen\", \"--around\""),
          "vm bug 2: the pointer's surroundings are captured only while aris-agent may record the screen")
    let access = code("ArisAgent/ArisScreenAccess.swift")
    check(access.contains("ArisScreenRead.allowed(known:") && access.contains("[\"screen\", \"--access\"]"),
          "vm bug 1: the agent's one answer about Screen Recording goes through the fresh check")
    let live = code("ArisAgent/ArisScreenAccess+Live.swift")
    check(live.contains("extension ArisWidgetPick.Access") && live.contains("screen: ArisScreenAccess.now") && !live.contains("CGPreflightScreenCaptureAccess")
          && !code("ArisAgent/ArisWidgetPick.swift").contains("CGPreflightScreenCaptureAccess"),
          "vm bug 1: the “Screen Recording is off” card under an answer goes once the permission is on, without a restart")
    let desktop = code("ArisAgent/ArisDesktopLive.swift")
    check(desktop.contains("var screenRecording: Bool { ArisScreenAccess.now }") && !desktop.contains("CGPreflightScreenCaptureAccess"),
          "vm bug 1: computer use (--ocr, click-at) sees a grant given while the agent runs")
    let tools = source("ArisTools/ArisScreen.swift")
    let probe = tools.range(of: "if args.first == \"--access\" { return print(CGPreflightScreenCaptureAccess() ? \"on\" : \"off\") }")
    let body = tools.range(of: "func screenText(_ args: [String]) {")
    // (vm3n bug 1: the app read may be named by its pid; the front app otherwise.)
    let front = tools.range(of: "guard let app = named ?? ArisFrontLive.frontPid().flatMap({ NSRunningApplication(processIdentifier: $0) }) else { fail(\"no app in front\") }")
    check(probe != nil && body != nil && front != nil && body!.upperBound < probe!.lowerBound && probe!.upperBound < front!.lowerBound,
          "vm bug 1: `aris-tools screen --access` answers before anything is looked at or captured")
    let agent = source("ArisAgent/main.swift")
    check(agent.contains("\"unread\": look.unread ?? \"\"") && agent.contains("\"unselected\": look.unselected ?? \"\"") && agent.contains("\"needs\": look.needs"),
          "vm bugs 1 and 2: /look hands the app the lines and what aris-agent lacked, for the app to use or leave out")
    let controller = code("Aris/private/Aris/ArisController+Look.swift")
    check(controller.contains("await ArisTurnCapture.shared.inHand()") && controller.contains("ArisLookContext.words(context: look.context, unread: look.unread, unselected: look.unselected,"),
          "vm bug 1: the app decides what the AI is told from whether its own picture is in hand this turn")
    let client = code("Aris/private/Aris/ArisAgentClient.swift")
    check(client.contains("unread: line(\"unread\")") && client.contains("unselected: line(\"unselected\")") && client.contains("needs: body[\"needs\"] as? [String] ?? []"),
          "vm bugs 1 and 2: the app reads the look's lines and needs")
}

// MARK: - Bug 1: “Restart Aris” restarts all of Aris

/// The tester restarted Aris from the ✦ menu and aris-agent kept running (its pid stayed), so whatever the agent held
/// from its start stayed too. The jobs it runs end with the app anyway (ArisJobLedger), so nothing more is lost.
private func vmScreenRestartTests() {
    let menu = code("Aris/private/Aris/ArisStatusItem.swift")
    let helper = menu.range(of: "_ = await ArisHelperClient.shared.restartArisAgent()")
    let relaunch = menu.range(of: "ApplicationRelauncher.restart()")
    check(helper != nil && relaunch != nil && helper!.upperBound < relaunch!.lowerBound && menu.components(separatedBy: "ApplicationRelauncher.restart()").count == 2,
          "vm bug 1: “Restart Aris” restarts aris-agent first, then the app, whatever the helper answers")
    check(source("Aris/private/Aris/Team/ArisJobLedger.swift").contains("The agent ends a job's AI when the app's"),
          "vm bug 1: a relaunch already ends the agent's jobs, so restarting the agent with it loses nothing more")
}
