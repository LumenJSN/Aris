// jv-cctab: the user's three reports on the Claude tab (2026-11-19, evidence/cc-question-clipped-1119.png).
//  1. A question card fits the notch: the notch opens to the card's height up to the screen's safe maximum, the step
//     chips and the footer (Terminal, Submit) always show, the question is whole, and a body taller than the room
//     scrolls (ClaudeCardFit). Measured on the real QuestionCard and PlanCard in the tab's frame (cctab-render/scene.swift).
//  2. Go to the terminal: what is tried for each terminal, in what order, and the line said when it lands short
//     (TerminalJump); the asking session comes to the front of the tab, so Open terminal is the asking one's.
//  3. The orange dot on </>: a card waiting in the notch. It goes when the question is answered in the terminal, when
//     the session goes back to its prompt or ends, and when its process is gone; hovering says who and why.
import AppKit
import SwiftUI

private func cctabSource(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("..").standardized
    return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

@MainActor
func runCctabTests() {
    cctabFitTests()
    cctabTerminalTests()
    cctabBadgeTests()
}

// MARK: - 1. The card fits

@MainActor
private func cctabFitTests() {
    // The Claude tab grows to the screen's safe maximum like Aris's pages; the shelf keeps the fixed cap.
    let smallest = ArisAnswerBudget.surfaceMax(visibleHeight: 600)   // a 1024×640 display less its menu bar
    check(smallest == 580 && ArisAnswerBudget.surfaceMax(visibleHeight: 1100) == 710, "cctab fit: the safe maximum is 580 on the smallest screen, 710 on the user's")
    check(ArisNotchDecisions.growMax(surfacePage: false, claudePage: true, surfaceMax: smallest, fixedMax: 400) == smallest
          && ArisNotchDecisions.growMax(surfacePage: true, claudePage: false, surfaceMax: 710, fixedMax: 400) == 710
          && ArisNotchDecisions.growMax(surfacePage: false, claudePage: false, surfaceMax: 710, fixedMax: 400) == 400,
          "cctab fit: the Claude tab opens up to the screen's safe maximum, not the fixed 400 (the shelf keeps 400)")
    check(cctabSource("Aris/private/Notch/ArisNotchRoot.swift").contains("claudePage: navigation.currentView == .claude"),
          "cctab fit: the notch asks growMax with the Claude page")

    // The user's card: four questions, the first 300 characters with four options of two-line descriptions.
    check(CCTabScene.longQuestion.count == 300 && CCTabScene.questions.count == 4, "cctab fit: the fixture is the user's card, its question 300 characters")
    let flow = QuestionFlow(questions: CCTabScene.questions)
    let width: CGFloat = 342   // 540 − 4·2 − 150 − 12 − 14·2
    let questionText = NSHostingView(rootView: Text(CCTabScene.longQuestion).font(.system(size: 14, weight: .semibold))
        .frame(width: width, alignment: .leading).fixedSize(horizontal: false, vertical: true)).fittingSize.height

    for (name, max) in [("smallest screen", smallest), ("the user's screen", CGFloat(710)), ("the old 400 cap", CGFloat(400))] {
        let m = CCTabScene.measure(QuestionCard(id: UUID(), flow: flow), maxHeight: max)
        let notch = m.height - 8
        check(notch <= max + 0.5, "cctab fit (\(name)): the notch is \(Int(notch)) tall, within its \(Int(max))")
        check(!m.footer.isNull && m.footer.minY > 0 && m.footer.maxY <= notch + 0.5,
              "cctab fit (\(name)): Terminal and Submit (\(Int(m.footer.minY))–\(Int(m.footer.maxY))) are inside the notch")
        // The body is never cut: whole when it fits, else scrolling at its full height (the question's every line in it).
        check(m.scrolls != nil && m.bodyHeight >= questionText + 4 * 40,
              "cctab fit (\(name)): the question (\(Int(questionText)) tall) and the options are whole (\(Int(m.bodyHeight)) tall, \(m.scrolls == true ? "scrolling" : "no scroll"))")
    }
    let roomy = CCTabScene.measure(QuestionCard(id: UUID(), flow: flow), maxHeight: 710)
    check(roomy.scrolls == false && roomy.height - 8 < 710, "cctab fit: on the user's screen the card fits whole, no scroll")
    let tight = CCTabScene.measure(QuestionCard(id: UUID(), flow: flow), maxHeight: 400)
    check(tight.scrolls == true && tight.height - 8 == 400, "cctab fit: under 400 the notch stops at 400 and the body scrolls")
    check(questionText > 5 * 17, "cctab fit: the 300-character question takes more than three lines (it was cut at three)")
    let views = cctabSource("Aris/private/Claude/ClaudeAnswerViews.swift")
    let questionLine = views.range(of: "Text(question.question)").map { String(views[$0.upperBound...].prefix(260)) } ?? ""
    check(!questionLine.contains("lineLimit") && !views.contains(".lineLimit(2)") && !views.contains(".lineLimit(14)"),
          "cctab fit: the question, the options' descriptions, a preview and the plan have no line limit (they scroll instead)")

    // A plan far longer than the notch: the notch stops at the maximum, the plan scrolls, its button shows.
    let plan = (1...60).map { "\($0). 단계 \($0): 카드를 노치에 맞춰요." }.joined(separator: "\n")
    let planned = CCTabScene.measure(PlanCard(plan: plan) { _ in }, maxHeight: smallest)
    check(planned.scrolls == true && planned.height - 8 <= smallest + 0.5 && planned.footer.maxY <= planned.height - 8 + 0.5,
          "cctab fit: a long plan scrolls and Approve in terminal stays inside the notch")

    // Plain options too long for one row of pills fall back to rows (they were cut at the card's edge).
    let pills = CCTabScene.measure(QuestionCard(id: UUID(), flow: QuestionFlow(questions: [CCTabScene.pillsQuestion])), maxHeight: smallest)
    check(pills.scrolls == false && pills.bodyHeight > 5 * 30, "cctab fit: five long plain options are rows, not a cut row of pills")
    let short = CCTabScene.measure(QuestionCard(id: UUID(), flow: QuestionFlow(questions: [single])), maxHeight: smallest)
    check(short.scrolls == false && short.height - 8 >= CCTabScene.minHeight && short.height - 8 < 300, "cctab fit: a short question keeps the small notch")
    check(cctabSource("Aris/private/Claude/ClaudeTabView.swift").contains("ClaudeCardFit(spacing: 8)"),
          "cctab fit: the permission card is fitted the same way")
}

// MARK: - 2. Go to the terminal

@MainActor
private func cctabTerminalTests() {
    typealias J = TerminalJump
    let warp = URL(string: "warp://session/724db74117fa4b86b5fc3e08ebb80bd2")!
    let iterm = "6F3C9B2E-1A2B-4C3D-8E9F-0123456789AB"
    let some: Set<String> = ["com.apple.finder", "com.apple.Terminal", "dev.warp.Warp-Stable", "com.googlecode.iterm2",
                             "com.mitchellh.ghostty", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92"]
    // Each terminal handled: its tab first when it can say where, then its app, then another terminal, then the folder.
    check(J.steps(for: .warp(warp), running: some, cwd: "/p", folderExists: true)
          == [.warp(warp, bundle: "dev.warp.Warp-Stable"), .app("dev.warp.Warp-Stable"), .otherTerminal("com.mitchellh.ghostty"), .folder("/p")],
          "cctab terminal: Warp — its tab by the focus link, then Warp, then another terminal, then the folder")
    check(J.steps(for: .warp(warp), running: ["dev.warp.Warp-Preview"], cwd: "/p", folderExists: false)
          == [.warp(warp, bundle: "dev.warp.Warp-Preview"), .app("dev.warp.Warp-Preview")], "cctab terminal: Warp Preview is Warp too")
    check(J.steps(for: .iterm(iterm), running: some, cwd: "/p", folderExists: false).prefix(2) == [.iterm(iterm), .app("com.googlecode.iterm2")],
          "cctab terminal: iTerm2 — its session by id, then iTerm2")
    check(J.steps(for: .app("com.apple.Terminal"), running: some, cwd: "/p", folderExists: false).first == .app("com.apple.Terminal"),
          "cctab terminal: Terminal — the app")
    check(J.steps(for: .app("com.mitchellh.ghostty"), running: some, cwd: "/p", folderExists: false)
          == [.app("com.mitchellh.ghostty"), .otherTerminal("com.googlecode.iterm2")], "cctab terminal: Ghostty — the app, never twice")
    check(J.steps(for: .app("com.microsoft.VSCode"), running: some, cwd: "/p", folderExists: false).first == .app("com.microsoft.VSCode")
          && J.steps(for: .app("com.todesktop.230313mzl4w4u92"), running: some, cwd: "/p", folderExists: false).first == .app("com.todesktop.230313mzl4w4u92"),
          "cctab terminal: VS Code and Cursor's integrated terminal — the editor")
    check(J.steps(for: .warp(warp), running: ["com.apple.Terminal"], cwd: "/p", folderExists: true) == [.otherTerminal("com.apple.Terminal"), .folder("/p")],
          "cctab terminal: Warp not running — its session is gone, another terminal comes forward")
    check(J.steps(for: nil, running: ["com.apple.finder"], cwd: "/p", folderExists: true) == [.folder("/p")]
          && J.steps(for: nil, running: [], cwd: "/gone", folderExists: false).isEmpty,
          "cctab terminal: no terminal known or running — its folder in Terminal, else nothing to try")
    check(J.Step.iterm(iterm).bundle == "com.googlecode.iterm2" && J.Step.warp(warp, bundle: "dev.warp.Warp-Stable").bundle == "dev.warp.Warp-Stable"
          && J.Step.folder("/p").bundle == nil, "cctab terminal: every step names the app it hands the front to")

    // The one line when it lands short of the tab (none when it reached it).
    let name: (String) -> String = { J.knownName($0) ?? $0 }
    check(J.note(reached: .warp(warp, bundle: "dev.warp.Warp-Stable"), wanted: .warp(warp), english: false, name: name) == nil
          && J.note(reached: .iterm(iterm), wanted: .iterm(iterm), english: false, name: name) == nil, "cctab terminal: the exact tab says nothing")
    check(J.note(reached: .app("dev.warp.Warp-Stable"), wanted: .warp(warp), english: false, name: name) == "Warp 창만 앞으로 가져왔어요. 세션의 탭은 찾지 못했어요.",
          "cctab terminal: Warp forward without its tab says so")
    check(J.note(reached: .app("com.googlecode.iterm2"), wanted: .iterm(iterm), refused: true, english: false, name: name)?.contains("자동화") == true
          && J.note(reached: .app("com.googlecode.iterm2"), wanted: .iterm(iterm), refused: true, english: true, name: name)?.contains("Automation") == true,
          "cctab terminal: iTerm2 refused for Automation says where to turn it on")
    check(J.note(reached: .app("com.apple.Terminal"), wanted: .app("com.apple.Terminal"), english: false, name: name)?.hasPrefix("Terminal 창을 앞으로") == true,
          "cctab terminal: Terminal (no tab to find) says the app came forward")
    check(J.note(reached: .otherTerminal("com.mitchellh.ghostty"), wanted: nil, english: true, name: name)
          == "This session didn't say which terminal it's in, so Ghostty came forward."
          && J.note(reached: .otherTerminal("com.mitchellh.ghostty"), wanted: .warp(warp), english: false, name: name)?.contains("실행 중이 아니라서") == true,
          "cctab terminal: another terminal says why")
    check(J.note(reached: .folder("/p"), wanted: nil, english: false, name: name)?.contains("폴더") == true
          && J.note(reached: nil, wanted: .warp(warp), english: false, name: name) == "세션의 터미널을 찾지 못했어요.",
          "cctab terminal: the folder, or nothing at all, is said")
    check(J.knownName("com.todesktop.230313mzl4w4u92") == "Cursor" && J.knownName("dev.warp.Warp-Preview") == "Warp" && J.knownName("x.y") == nil,
          "cctab terminal: terminals by name")

    // The live half hands the front over before every step (a click in the notch leaves Aris inactive).
    let focus = cctabSource("Aris/private/Claude/TerminalFocus.swift")
    check(focus.contains("NSApp.yieldActivation(toApplicationWithBundleIdentifier: bundle)") && focus.contains("NSApp.activate(ignoringOtherApps: true)")
          && focus.contains("TerminalJump.steps(") && focus.contains("ArisController.shared.notify("),
          "cctab terminal: Aris takes the front for the click and yields it to the terminal; a short landing is said")

    // The card's session comes to the front of the tab: Open terminal is the asking session's, not one picked before.
    let store = ClaudeStore()
    store.apply(event(["hook_event_name": "SessionStart", "session_id": "notch", "cwd": "/p/boring.notch"]))
    store.apply(ClaudeHookEvent(json: ["hook_event_name": "UserPromptSubmit", "session_id": "home", "cwd": "/Users/p"], headers: ["x-warp-focus": warp.absoluteString])!)
    store.focus("notch")
    check(store.focusedSession?.id == "notch", "cctab terminal: a picked session is in front")
    store.requestApproval(ClaudeApproval(id: UUID(), sessionId: "home", cwd: "/Users/p", toolName: "ExitPlanMode", summary: "", kind: .plan("p"))) { _ in }
    check(store.focusedSession?.id == "home" && store.focusedSession?.terminal == .warp(warp),
          "cctab terminal: a plan card brings its own session (and its Warp tab) to the front")
}

// MARK: - 3. The dot on </>

@MainActor
private func cctabBadgeTests() {
    func card(_ session: String, _ tool: String = "AskUserQuestion", kind: ClaudeApproval.Kind = .question([single]),
              input: [String: Any] = [:]) -> ClaudeApproval {
        ClaudeApproval(id: UUID(), sessionId: session, cwd: "/p/\(session)", toolName: tool, summary: "", kind: kind, toolInput: input as NSDictionary)
    }
    func hook(_ store: ClaudeStore, _ name: String, _ session: String, _ extra: [String: Any] = [:], headers: [String: String] = [:]) {
        store.apply(ClaudeHookEvent(json: ["hook_event_name": name, "session_id": session, "cwd": "/p/\(session)"].merging(extra) { _, new in new },
                                    headers: headers)!)
    }
    let asked: [String: Any] = ["questions": [["question": "월 예산", "options": [["label": "$760"]]]]]

    // Two sessions, one waiting: the dot is that one's card, and the tip names it and why.
    let store = ClaudeStore()
    hook(store, "UserPromptSubmit", "jdoe")
    hook(store, "UserPromptSubmit", "boring.notch")
    hook(store, "PermissionRequest", "jdoe", ["tool_name": "AskUserQuestion", "tool_input": asked])
    var dropped = 0
    let question = card("jdoe", input: asked)
    store.requestApproval(question, resolve: { _ in }, onDrop: { dropped += 1 })
    check(!store.approvals.isEmpty && store.attention == [ClaudeAttention.Need(session: "jdoe", why: .question)],
          "cctab dot: two sessions, one asking: the dot is on, for jdoe's question only")
    check(ClaudeAttention.help(store.attention, english: false) == "코딩 세션\njdoe: 질문에 답을 기다려요"
          && ClaudeAttention.line(store.attention[0], english: true) == "jdoe: waiting for your answer",
          "cctab dot: hovering </> says whose and why")
    let header = cctabSource("Aris/private/Aris/Home/ArisNotchHeader.swift")
    check(header.contains("badge: !claude.approvals.isEmpty") && header.contains("ArisHoverTip(text: lines.joined"),
          "cctab dot: the dot is the waiting cards, and the notch's own tip under </> lists them")

    // Answered in the terminal: the tool's result clears the card, and the dot.
    hook(store, "PostToolUse", "jdoe", ["tool_name": "AskUserQuestion", "tool_input": asked.merging(["answers": ["월 예산": "$760"]]) { _, new in new }])
    check(store.approvals.isEmpty && store.attention.isEmpty && dropped == 1, "cctab dot: answered in the terminal, the card and the dot go")

    // Back at its prompt (a terminal "No" that ended the turn without a Stop): a new prompt or the idle nudge clears it.
    store.requestApproval(card("jdoe"), resolve: { _ in }, onDrop: { dropped += 1 })
    hook(store, "UserPromptSubmit", "boring.notch")
    check(store.approvals.count == 1, "cctab dot: another session's prompt leaves the card")
    hook(store, "UserPromptSubmit", "jdoe")
    check(store.approvals.isEmpty && dropped == 2, "cctab dot: a new prompt in the asking session clears its card")
    store.requestApproval(card("jdoe"), resolve: { _ in }, onDrop: { dropped += 1 })
    hook(store, "Notification", "jdoe", ["notification_type": "idle_prompt"])
    check(store.approvals.isEmpty && dropped == 3, "cctab dot: 'waiting for your input' clears the session's card")

    // The session ends while it asks: its card goes with it.
    store.requestApproval(card("jdoe", "ExitPlanMode", kind: .plan("p")), resolve: { _ in }, onDrop: { dropped += 1 })
    hook(store, "SessionEnd", "jdoe")
    check(store.approvals.isEmpty && dropped == 4 && store.sessions["jdoe"] == nil, "cctab dot: SessionEnd takes the session's card down")

    // Its process is gone (killed while it asked, no SessionEnd): the sweep drops the session and its card.
    let swept = ClaudeStore()
    var alive: Set<Int32> = [4242, 5151]
    swept.processAlive = { alive.contains($0) }
    hook(swept, "SessionStart", "dead", headers: ["x-claude-pid": "4242"])
    hook(swept, "PreToolUse", "dead", ["tool_name": "Bash"])
    hook(swept, "SessionStart", "live", headers: ["x-claude-pid": "5151"])
    check(swept.sessions["dead"]?.pid == 4242, "cctab dot: the session keeps its agent's pid through events that don't send it")
    hook(swept, "PermissionRequest", "dead", ["tool_name": "Bash", "tool_input": ["command": "make"]])
    var sweptDrops = 0
    swept.requestApproval(card("dead", "Bash", kind: .tool, input: ["command": "make"]), resolve: { _ in }, onDrop: { sweptDrops += 1 })
    swept.sweep()
    check(swept.sessions["dead"] != nil && swept.approvals.count == 1, "cctab dot: a live process keeps its session and card")
    alive.remove(4242)
    swept.sweep()
    check(swept.sessions["dead"] == nil && swept.sessions["live"] != nil && swept.approvals.isEmpty && sweptDrops == 1,
          "cctab dot: the process gone, the sweep drops its session and its card (the dot goes)")
    check(ClaudeSessionSweep.swept(["x": ClaudeSession(id: "x", cwd: "/p", state: .notification, lastEvent: Date(), pid: 77)], now: Date(),
                                   runningApps: nil, alive: { _ in false }).sessions.isEmpty
          && ClaudeSessionSweep.swept(["x": ClaudeSession(id: "x", cwd: "/p", state: .notification, lastEvent: Date())], now: Date(),
                                      runningApps: nil, alive: { _ in false }).sessions.count == 1,
          "cctab dot: only a session whose hooks sent a pid is dropped for its process")

    // The client went away (Esc in the terminal): the card goes and the session isn't left "needs you".
    let gone = ClaudeStore()
    hook(gone, "PermissionRequest", "s", ["tool_name": "Bash"])
    let held = card("s", "Bash", kind: .tool)
    gone.requestApproval(held) { _ in }
    check(gone.sessions["s"]?.state == .notification, "cctab dot: asking, the session waits")
    gone.cancelApproval(held.id, clientGone: true)
    check(gone.approvals.isEmpty && gone.sessions["s"]?.state == .idle && gone.attention.isEmpty, "cctab dot: its agent stopped waiting, it rests")
    hook(gone, "Notification", "s", ["notification_type": "permission_prompt"])
    check(gone.attention == [ClaudeAttention.Need(session: "s", why: .terminal)]
          && ClaudeAttention.line(gone.attention[0], english: false) == "s: 터미널에서 기다려요",
          "cctab dot: a session asking in its own terminal is named too")

    // The pid header: digits only.
    check(ClaudeHookEvent.pid("4242") == 4242 && ClaudeHookEvent.pid("1") == nil && ClaudeHookEvent.pid("") == nil
          && ClaudeHookEvent.pid("12; rm") == nil && ClaudeHookEvent.pid(nil) == nil && ClaudeHookEvent.pid("99999999999") == nil,
          "cctab dot: the pid header is a plain number above 1")
    let script = cctabSource("Aris/private/Claude/aris-claude-hook.sh")
    check(script.contains("-H \"X-Claude-Pid: ${agent_pid:-}\"") && script.contains("ps -o comm= -p \"$agent_pid\""),
          "cctab dot: the hook script sends its agent's pid")
}
