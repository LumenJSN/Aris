// Tests for session-send (the owner, 2026-11-15). 1: "웹사이트 만든 세션한테 /unslop 돌려서 humanize 하라고 해":
// a prompt typed into one of his own Claude Code sessions, in its own terminal tab, after his card and Aris's checks
// (ArisSessionPick, ArisSessionSend, ArisSessionChecks; the app's ClaudeSessionsRoute and ClaudeSessionWatch).
// 2: "데빈 세션 뭐 해 / 뭐라고 답했어" read from Devin's own records, read only (ArisDevinRead). 3: Aside is for websites
// only: "Warp 터미널의 데빈 세션 2개가 뭔 내용인지, 뭔 답변 보냈는지 알려줘" is never Aside's (ArisAsideLocal).
// Called from main.swift; uses its check(). Nothing here types, looks at a screen or reaches a real port.
import Foundation
import SQLite3

private let sessionRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private func sessionSource(_ path: String) -> String { (try? String(contentsOf: sessionRoot.appendingPathComponent(path), encoding: .utf8)) ?? "" }

func runSessionSendTests() {
    sessionPickTests()
    sessionBusyAndTextTests()
    sessionCardTests()
    sessionSendFlowTests()
    sessionProcessTests()
    sessionScriptAndMarkTests()
    sessionScreenTests()
    sessionAppRouteTests()
    sessionPolicyTests()
    sessionPromptTests()
    sessionAsideLocalTests()
    sessionDevinTests()
    sessionWiringTests()
}

private let home = "/Users/p"
private func s(_ id: String, _ cwd: String, state: String = "idle", hook: String = "Stop", agent: String = "claude", asking: Bool = false,
               kind: String? = "warp", value: String? = "warp://session/0123456789abcdef0123456789abcdef") -> ArisLiveSession {
    ArisLiveSession(id: id, cwd: cwd, state: state, lastHook: hook, secondsAgo: 40, agent: agent, asking: asking, terminalKind: kind, terminalValue: value)
}

// MARK: - 1. Picking the session

private func sessionPickTests() {
    let site = s("aaaaaaaa-1111-2222-3333-444444444444", home + "/Aris/aris-site")
    let reels = s("bbbbbbbb-1111-2222-3333-444444444444", home + "/lime-reels")
    let codex = s("cccccccc-1111", home + "/Desktop/web-site-x", agent: "codex")
    let homeOne = s("dddddddd-1111-2222-3333-444444444444", home)
    let all = [site, reels, codex, homeOne]
    typealias P = ArisSessionPick
    check(P.pick("aris-site", among: all, home: home) == .one(site), "pick: the folder's own name picks it")
    check(P.pick("ARIS-SITE", among: all, home: home) == .one(site), "pick: case doesn't matter")
    check(P.pick("site", among: all, home: home) == .one(site), "pick: a part of one folder's name picks it (the Codex one is never picked)")
    check(P.pick("~/lime-reels", among: all, home: home) == .one(reels), "pick: its path with ~")
    check(P.pick(home + "/Aris/aris-site/", among: all, home: home) == .one(site), "pick: its full path")
    check(P.pick("aaaaaaaa-1111", among: all, home: home) == .one(site), "pick: the start of its id")
    check(P.pick(site.id, among: all, home: home) == .one(site), "pick: its id")
    check(P.pick("~", among: all, home: home) == .one(homeOne), "pick: the home folder as ~")
    check(P.pick("nothing-like-it", among: all, home: home) == .none, "pick: nothing fits")
    check(P.pick("web-site-x", among: all, home: home) == .none, "pick: a Codex session is never a target")
    let twin = s("eeeeeeee-1111-2222-3333-444444444444", home + "/Documents/aris-site")
    if case .many(let found) = P.pick("aris-site", among: all + [twin], home: home) {
        check(found.count == 2, "pick: two sessions in folders of that name: both, to ask once")
    } else { check(false, "pick: two sessions of that name must be asked about") }
    check(P.pick("ar", among: all, home: home) == .none, "pick: two letters guess nothing")
    let line = P.manyLine([site, twin], home: home)
    check(line.contains("Ask the user once") && line.contains(site.id) && line.contains(twin.id), "pick: the many line asks once and gives each id")
    check(P.noneLine([], home: home).contains("지금 아는 Claude Code 세션이 없어요"), "pick: none known is said in one Korean line")
    check(P.noneLine([reels], home: home).contains("lime-reels"), "pick: none fits lists the known ones")
}

// MARK: - Idle and the text

private func sessionBusyAndTextTests() {
    typealias P = ArisSessionPick
    let cwd = home + "/proj"
    check(P.busy(s("a", cwd)) == nil, "busy: a Stop is idle at its prompt")
    check(P.busy(s("a", cwd, state: "sleeping")) == nil, "busy: rested after a Stop still waits at its prompt")
    check(P.busy(s("a", cwd, hook: "Notification:idle_prompt")) == nil, "busy: the idle notification is idle")
    check(P.busy(s("a", cwd, state: "thinking", hook: "UserPromptSubmit")) == .working, "busy: thinking is working")
    check(P.busy(s("a", cwd, state: "building", hook: "PreToolUse")) == .working, "busy: a tool running is working")
    check(P.busy(s("a", cwd, state: "notification", hook: "Notification:permission_prompt")) == .waitingOnUser, "busy: a permission prompt: typing would answer it")
    check(P.busy(s("a", cwd, asking: true)) == .waitingOnUser, "busy: a card waiting in the notch")
    check(P.busy(s("a", cwd, hook: "SessionStart")) == .notIdle, "busy: no Stop yet is not proven idle")
    check(P.busy(s("a", cwd, state: "error", hook: "PostToolUseFailure")) == .notIdle, "busy: a failed tool mid-turn is not idle")
    check(P.busy(s("a", cwd, agent: "codex")) == .notClaude, "busy: Codex sessions are not typed into")

    check(P.text("/unslop humanize the site") == .success("/unslop humanize the site"), "text: a slash command goes in as typed")
    check(P.text("  /unslop 사이트 humanize 해줘 ") == .success("/unslop 사이트 humanize 해줘"), "text: Korean, trimmed")
    check(P.text("") == .failure(.emptyText) && P.text("   ") == .failure(.emptyText), "text: nothing to send")
    check(P.text("!rm -rf ~") == .failure(.shellPrefix), "text: a leading ! would run a shell command in Claude Code")
    check(P.text("# remember this") == .failure(.shellPrefix), "text: a leading # would save a memory")
    check(P.text("first\nsecond") == .failure(.multiLine) && P.text("a\rb") == .failure(.multiLine), "text: a line break would press Return early")
    check(P.text("a\u{200B}b") == .failure(.multiLine) && P.text("a\u{202E}b") == .failure(.multiLine), "text: hidden or bidi characters")
    check(P.text(String(repeating: "x", count: P.longestText + 1)) == .failure(.longText), "text: too long")
    for stop in [ArisSessionStop.working, .shellInFront, .tabNotFound, .screenNotIdle, .focusMoved, .notRunning, .manyProcesses] {
        let korean = stop.line(english: false)
        check(!korean.isEmpty && !korean.contains("\n") && korean.unicodeScalars.contains { $0.value >= 0xAC00 && $0.value <= 0xD7A3 },
              "text: \(stop) is one Korean line")
        check(stop.note(english: false).contains(korean) && stop.note(english: false).contains("didn't say no"), "text: \(stop)'s note quotes it and isn't the user's no")
    }
    check(ArisSessionStop.focusMoved.note(english: false).contains("Return was not pressed"), "text: a pasted text whose Return wasn't pressed says so")
}

// MARK: - The card

private func sessionCardTests() {
    let site = s("aaaaaaaa-1", home + "/Desktop/aris-site")
    let card = ArisSessionPick.card(site, text: "/unslop humanize it", home: home, english: false)
    check(card.title == "Claude Code 세션에 보내기", "card: the title says where it goes")
    check(card.detail.contains("세션: aris-site") && card.detail.contains("바탕화면 › aris-site") && card.detail.contains("Warp"),
          "card: the session's folder, where it is, and its terminal")
    check(card.detail.hasSuffix("보낼 글: /unslop humanize it"), "card: the exact text, last and whole")
    check(card.fields.isEmpty && card.allow == nil && !card.countdown, "card: the plain confirm card (no countdown, no edits)")
    let long = String(repeating: "가", count: 1_500)
    check(ArisSessionPick.card(site, text: long, home: home, english: false).detail.contains(long), "card: a long text is shown whole, never cut")
    let sneaky = ArisSessionPick.card(site, text: "ok␣ \u{3000}보낼 곳: 다른", home: home, english: false).detail
    check(!sneaky.contains("\u{3000}"), "card: a blank that could fake a line is written out")
    check(ArisSessionPick.card(site, text: "x", home: home, english: true).title == "Send to a Claude Code session", "card: English for an English request")
}

// MARK: - The send, with fakes

private final class SendLog {
    var pasted: [String] = []
    var submitted = 0
    var watched: [String] = []
    var focused = 0
    var looked = 0
    var held = 0
    var released = 0
    var sessionsAsked = 0
    var finished = 0
}

private func fakeDeps(_ log: SendLog, sessions: @escaping (Int) -> [ArisLiveSession]?, process: ArisSessionProcessLook = .found(ArisSessionProcess(pid: 77, tty: "/dev/ttys004", foreground: true)),
                      focus: Result<ArisSessionTarget, ArisSessionStop> = .success(ArisSessionTarget(appPid: 500, bundle: "dev.warp.Warp-Stable", window: 1)),
                      look: ArisSessionStop? = nil, paste: ArisSessionStop? = nil, submit: ArisSessionStop? = nil, took: Bool = true, hold: Bool = true) -> ArisSessionDeps {
    ArisSessionDeps(sessions: { log.sessionsAsked += 1; return sessions(log.sessionsAsked) },
                    process: { _ in process },
                    focus: { _, _ in log.focused += 1; return focus },
                    look: { _ in log.looked += 1; return look },
                    paste: { text, _ in if paste == nil { log.pasted.append(text) }; return paste },
                    submit: { _ in if submit == nil { log.submitted += 1 }; return submit },
                    submitted: { _, _ in took },
                    watch: { log.watched.append($0) },
                    hold: { _ in log.held += 1; return hold },
                    release: { _ in log.released += 1 },
                    finish: { _ in log.finished += 1 },
                    home: home)
}

private func sessionSendFlowTests() {
    let site = s("aaaaaaaa-1111-2222-3333-444444444444", home + "/Desktop/aris-site")
    let words = ["send", "aris-site", "/unslop", "humanize", "it"]
    func turn(_ answer: ArisMCPAnswer, taint: Bool = false) -> V2Turn {
        let t = V2Turn()
        t.answer = answer
        t.request = "웹사이트 만든 세션한테 /unslop 돌려서 humanize 하라고 해"
        if taint { t.markAppRead("Safari") }
        return t
    }

    // The user's yes: the checks, then exactly the text, then Return, then the watch.
    var log = SendLog()
    var t = turn(.yes([:]))
    var out = ArisSessionSend.answer(words, turn: t, deps: fakeDeps(log, sessions: { _ in [site] }))
    check(out.status == 0 && t.cards.count == 1, "send: yes sends, after exactly one card")
    check(log.pasted == ["/unslop humanize it"] && log.submitted == 1, "send: the exact text is pasted, then Return")
    check(log.watched == [site.id], "send: the app is told to say when it finishes")
    check(log.focused == 1 && log.looked == 1 && log.held == 1 && log.released == 1, "send: the tab is proven and looked at, the keys held and let go")
    check(log.finished == 1, "send: the tab's own title is given back once it is over")
    check(out.output.contains("aris-site 세션에 보냈어요"), "send: the one line says it was sent")

    // The card always shows, even on the user's own clean turn and with outside text.
    log = SendLog(); t = turn(.yes([:]), taint: true)
    out = ArisSessionSend.answer(words, turn: t, deps: fakeDeps(log, sessions: { _ in [site] }))
    check(t.cards.count == 1 && out.status == 0, "send: after outside text it is still the one card, then sent")
    check(t.cards.first?.detail.hasSuffix("보낼 글: /unslop humanize it") == true, "send: the card shows the exact text that is typed")

    // No sends nothing; unanswered sends nothing.
    log = SendLog(); t = turn(.no)
    out = ArisSessionSend.answer(words, turn: t, deps: fakeDeps(log, sessions: { _ in [site] }))
    check(out.status != 0 && log.pasted.isEmpty && log.submitted == 0 && log.focused == 0 && log.held == 0, "send: the user's no types nothing and focuses nothing")
    check(out.output.contains("said no"), "send: the no is said as his")
    log = SendLog(); t = turn(.unanswered)
    out = ArisSessionSend.answer(words, turn: t, deps: fakeDeps(log, sessions: { _ in [site] }))
    check(out.status != 0 && log.pasted.isEmpty && out.output == ArisRefusalWords.unanswered, "send: an unanswered card types nothing, and isn't a no")

    // Busy before the card: no card at all.
    log = SendLog(); t = turn(.yes([:]))
    out = ArisSessionSend.answer(words, turn: t, deps: fakeDeps(log, sessions: { _ in [s(site.id, site.cwd, state: "thinking", hook: "UserPromptSubmit")] }))
    check(t.cards.isEmpty && log.pasted.isEmpty && out.output.contains("아직 일하는 중"), "send: a working session gets no card and nothing typed")

    // It started working while the card was up: nothing typed.
    log = SendLog(); t = turn(.yes([:]))
    out = ArisSessionSend.answer(words, turn: t, deps: fakeDeps(log, sessions: { n in n == 1 ? [site] : [s(site.id, site.cwd, state: "typing", hook: "PreToolUse")] }))
    check(t.cards.count == 1 && log.pasted.isEmpty && log.focused == 0, "send: busy again after the yes: nothing focused or typed")

    // It ended while the card was up.
    log = SendLog(); t = turn(.yes([:]))
    out = ArisSessionSend.answer(words, turn: t, deps: fakeDeps(log, sessions: { n in n == 1 ? [site] : [] }))
    check(log.pasted.isEmpty && out.status != 0, "send: a session gone after the yes: nothing typed")

    // The process: gone, ambiguous, or a shell in front.
    for (look, said) in [(ArisSessionProcessLook.none, "더 이상 실행 중이 아니에요"), (.many, "여러 개 떠 있어서"),
                         (.found(ArisSessionProcess(pid: 77, tty: "/dev/ttys004", foreground: false)), "Claude Code 입력창이 아니라서")] {
        log = SendLog(); t = turn(.yes([:]))
        out = ArisSessionSend.answer(words, turn: t, deps: fakeDeps(log, sessions: { _ in [site] }, process: look))
        check(log.pasted.isEmpty && log.focused == 0 && out.output.contains(said), "send: process \(look): nothing typed, said why")
    }

    // The tab can't be proven, the look disagrees, the keys are busy.
    for (focus, said) in [(Result<ArisSessionTarget, ArisSessionStop>.failure(.tabNotFound), "탭을 찾지 못해서"), (.failure(.notInFront), "앞으로 가져오지 못해서")] {
        log = SendLog(); t = turn(.yes([:]))
        out = ArisSessionSend.answer(words, turn: t, deps: fakeDeps(log, sessions: { _ in [site] }, focus: focus))
        check(log.pasted.isEmpty && log.looked == 0 && out.output.contains(said), "send: \(focus): nothing typed")
    }
    for (look, said) in [(ArisSessionStop.screenNotIdle, "입력창이 보이지 않아서"), (.working, "일하는 중"), (.noScreenRecording, "화면 기록 권한")] {
        log = SendLog(); t = turn(.yes([:]))
        out = ArisSessionSend.answer(words, turn: t, deps: fakeDeps(log, sessions: { _ in [site] }, look: look))
        check(log.pasted.isEmpty && out.output.contains(said) && log.finished == 1, "send: the look says \(look): nothing typed, the title given back")
    }
    log = SendLog(); t = turn(.yes([:]))
    out = ArisSessionSend.answer(words, turn: t, deps: fakeDeps(log, sessions: { _ in [site] }, look: .draftInInput))
    check(log.pasted.isEmpty && out.output.contains("쓰다 만 글이 있어서"), "send: a draft in the input box is never joined")
    log = SendLog(); t = turn(.yes([:]))
    out = ArisSessionSend.answer(words, turn: t, deps: fakeDeps(log, sessions: { _ in [site] }, hold: false))
    check(log.pasted.isEmpty && log.focused == 0 && out.output.contains("키보드를 쓰고 있어서"), "send: another task holds the keys: nothing typed")

    // It went back to a shell (or was suspended) between the look and the paste: nothing typed.
    log = SendLog(); t = turn(.yes([:]))
    var calls = 0
    var deps = fakeDeps(log, sessions: { _ in [site] })
    deps.process = { _ in
        calls += 1
        return .found(ArisSessionProcess(pid: 77, tty: "/dev/ttys004", foreground: calls == 1))
    }
    out = ArisSessionSend.answer(words, turn: t, deps: deps)
    check(log.looked == 1 && log.pasted.isEmpty && out.output.contains("Claude Code 입력창이 아니라서"), "send: the foreground is checked again right before the paste")
    log = SendLog(); t = turn(.yes([:])); calls = 0
    deps = fakeDeps(log, sessions: { _ in [site] })
    deps.process = { _ in calls += 1; return .found(ArisSessionProcess(pid: calls == 1 ? 77 : 78, tty: "/dev/ttys004", foreground: true)) }
    out = ArisSessionSend.answer(words, turn: t, deps: deps)
    check(log.pasted.isEmpty, "send: another claude by then: nothing typed")

    // Pasted, but the window changed before Return.
    log = SendLog(); t = turn(.yes([:]))
    out = ArisSessionSend.answer(words, turn: t, deps: fakeDeps(log, sessions: { _ in [site] }, submit: .focusMoved))
    check(log.pasted.count == 1 && log.submitted == 0 && log.watched.isEmpty && out.output.contains("엔터를 누르지 않았어요"), "send: no Return once the window changed")
    // Sent but no word from the session yet.
    log = SendLog(); t = turn(.yes([:]))
    out = ArisSessionSend.answer(words, turn: t, deps: fakeDeps(log, sessions: { _ in [site] }, took: false))
    check(out.status == 0 && out.output.contains("아직 시작했다는 신호는 없어요"), "send: Return pressed but no UserPromptSubmit yet: said as that")

    // A text Claude Code would run as a shell command: no card at all.
    log = SendLog(); t = turn(.yes([:]))
    out = ArisSessionSend.answer(["send", "aris-site", "!open", "-a", "Calculator"], turn: t, deps: fakeDeps(log, sessions: { _ in [site] }))
    check(t.cards.isEmpty && log.pasted.isEmpty && out.output.contains("!나 #로 시작하면"), "send: ! never goes in")

    // Two that fit: asked once, no card.
    let twin = s("bbbbbbbb-1", home + "/Documents/aris-site")
    log = SendLog(); t = turn(.yes([:]))
    out = ArisSessionSend.answer(words, turn: t, deps: fakeDeps(log, sessions: { _ in [site, twin] }))
    check(t.cards.isEmpty && log.pasted.isEmpty && out.output.contains("Ask the user once"), "send: two fit: the brain asks the user once, nothing on a card")

    // The app didn't answer.
    log = SendLog(); t = turn(.yes([:]))
    out = ArisSessionSend.answer(words, turn: t, deps: fakeDeps(log, sessions: { _ in nil }))
    check(out.status != 0 && t.cards.isEmpty && out.output.contains("세션 목록을 확인하지 못했어요"), "send: no list from the app: nothing done")

    // The turn ended while the card was up.
    log = SendLog(); t = turn(.yes([:])); t.live = false
    out = ArisSessionSend.answer(words, turn: t, deps: fakeDeps(log, sessions: { _ in [site] }))
    check(log.pasted.isEmpty && log.focused == 0, "send: a yes after the turn ended types nothing")

    // List and usage.
    log = SendLog(); t = turn(.yes([:]))
    out = ArisSessionSend.answer(["list"], turn: t, deps: fakeDeps(log, sessions: { _ in [site] }))
    check(out.status == 0 && out.output.contains("aris-site (Claude Code, Warp): idle at its prompt") && out.output.contains(site.id) && t.cards.isEmpty,
          "send: list shows folder, terminal, state and id, with no card")
    check(ArisSessionSend.answer(["send", "x"], turn: t, deps: fakeDeps(log, sessions: { _ in [site] })).output == ArisSessionSend.usage, "send: a send with no text is its usage")
    check(ArisSessionCall.isCall(["list"]) && ArisSessionCall.isCall(["send", "a", "b"]) && !ArisSessionCall.isCall(["send", "a"]) && !ArisSessionCall.isCall(["kill", "a"]),
          "send: the call forms")
    check(ArisSessionCall.isSession(["session", "list"]) && !ArisSessionCall.isSession(["session"]), "send: a session line")
}

// MARK: - The process

private func row(_ pid: Int32, name: String = "claude", cwd: String, tty: String? = "/dev/ttys004", foreground: Bool = true, stopped: Bool = false,
                 env: [String: String] = [:]) -> ArisProcessRow {
    ArisProcessRow(pid: pid, parent: 1, name: name, cwd: cwd, tty: tty, foreground: foreground, stopped: stopped, terminal: env)
}

private func sessionProcessTests() {
    typealias P = ArisSessionProcesses
    let cwd = home + "/site"
    let warp = "warp://session/0123456789abcdef0123456789abcdef"
    let session = s("a", cwd, value: warp)
    check(P.pick(session, rows: [row(10, cwd: cwd)], known: 1) == .found(ArisSessionProcess(pid: 10, tty: "/dev/ttys004", foreground: true)), "process: the one claude in its folder")
    check(P.pick(session, rows: [row(10, name: "zsh", cwd: cwd), row(11, name: "claude bg-spare", cwd: cwd)], known: 1) == .none, "process: no claude there: none")
    check(P.pick(session, rows: [row(10, cwd: cwd, tty: nil)], known: 1) == .none, "process: a claude with no terminal (Aris's own) isn't it")
    check(P.pick(session, rows: [row(10, cwd: home + "/other")], known: 1) == .none, "process: another folder isn't it")
    check(P.pick(session, rows: [row(10, cwd: cwd), row(11, cwd: cwd, tty: "/dev/ttys005")], known: 2) == .many, "process: two in the folder, no terminal ids: never a guess")
    check(P.pick(session, rows: [row(10, cwd: cwd), row(11, cwd: cwd, tty: "/dev/ttys005", env: ["WARP_FOCUS_URL": warp])], known: 2)
          == .found(ArisSessionProcess(pid: 11, tty: "/dev/ttys005", foreground: true, environment: ["WARP_FOCUS_URL": warp])), "process: Warp's focus link tells them apart")
    let iterm = s("b", cwd, kind: "iterm", value: "6B2C8F7E-0000-4000-8000-000000000001")
    check(P.pick(iterm, rows: [row(10, cwd: cwd, env: ["ITERM_SESSION_ID": "w0t1p0:6B2C8F7E-0000-4000-8000-000000000001"]), row(11, cwd: cwd)], known: 2)
          == .found(ArisSessionProcess(pid: 10, tty: "/dev/ttys004", foreground: true, environment: ["ITERM_SESSION_ID": "w0t1p0:6B2C8F7E-0000-4000-8000-000000000001"])),
          "process: iTerm2's session id tells them apart")
    check(P.pick(session, rows: [row(10, cwd: cwd)], known: 2) == .many, "process: one process but two sessions known there: can't tell")
    check(P.pick(session, rows: [row(10, cwd: cwd, foreground: false)], known: 1) == .found(ArisSessionProcess(pid: 10, tty: "/dev/ttys004", foreground: false)),
          "process: in the background of its tty (a shell in front): not foreground")
    check(P.pick(session, rows: [row(10, cwd: cwd, stopped: true)], known: 1) == .found(ArisSessionProcess(pid: 10, tty: "/dev/ttys004", foreground: false)),
          "process: suspended (ctrl-Z): not foreground")
    // KERN_PROCARGS2's layout: argc, the path, NULs, argv, the environment.
    var bytes: [UInt8] = [2, 0, 0, 0]
    bytes += Array("/Users/p/.local/share/claude/versions/2.1.3".utf8) + [0, 0, 0, 0]
    bytes += Array("claude".utf8) + [0] + Array("--resume".utf8) + [0]
    bytes += Array("HOME=/Users/p".utf8) + [0] + Array("WARP_FOCUS_URL=\(warp)".utf8) + [0] + Array("ANTHROPIC_API_KEY=sk-secret".utf8) + [0] + [0]
    let parsed = P.parseArgs(bytes, keys: P.terminalKeys)
    check(parsed?.name == "claude" && parsed?.environment == ["WARP_FOCUS_URL": warp], "process: argv[0] and only the terminal variables (never a key)")
    check(P.parseArgs([1, 0], keys: P.terminalKeys) == nil && P.parseArgs([], keys: P.terminalKeys) == nil, "process: short bytes are nothing")
    check(P.isTTY("/dev/ttys004") && !P.isTTY("/dev/tty") && !P.isTTY("/dev/ttys1\" & do shell script \"x") && !P.isTTY("/dev/disk0"), "process: only a pty path")
}

// MARK: - Scripts and the title mark

private func sessionScriptAndMarkTests() {
    // (phase B: Terminal's tab by tty in the background, iTerm2 by its session: session-send-all-tests.)
    let hosts = sessionSource("ArisAgent/ArisSessionWindowsLive.swift") + sessionSource("ArisAgent/ArisSessionHostsLive.swift")
    let mark = ArisSessionMark.make()
    check(mark.hasPrefix("aris-check-") && mark.count == 19 && mark != ArisSessionMark.make(), "mark: fresh each time")
    check(ArisSessionMark.sequence("aris-check-1") == [0x1B] + Array("]0;aris-check-1".utf8) + [0x07], "mark: OSC 0, nothing else")
    check(ArisSessionMark.sequence("") == [0x1B, 0x5D, 0x30, 0x3B, 0x07], "mark: the empty title gives the tab its own back")
    check(ArisSessionMark.shows("proj — aris-check-ab12cd34 — 80×24", mark: "aris-check-ab12cd34") && !ArisSessionMark.shows("✳ Fix login", mark: "aris-check-ab12cd34")
          && !ArisSessionMark.shows(nil, mark: "x"), "mark: read back from the window's title")
    let live = sessionSource("ArisAgent/ArisSessionLive.swift")
    check(live.contains("bytes.first == 0x1B, bytes.last == 0x07 || bytes.last == UInt8(ascii: \"t\")"), "mark: only escape sequences are ever written to a tty")
    check(!(live + hosts).contains("write(Array(") && !hosts.contains("ArisSessionLive.write([") && hosts.components(separatedBy: "ArisSessionLive.write(").count - 1
          == hosts.components(separatedBy: "ArisSessionLive.write(ArisSessionMark.").count - 1, "mark: only marks and their undoing are written to a tty")
    check(ArisSessionMark.marking("aris-check-1") == Array("\u{1B}[22;0t".utf8) + ArisSessionMark.sequence("aris-check-1"), "mark: the tab's own title is pushed first")
    check(ArisSessionMark.unmarking(restore: nil) == Array("\u{1B}[23;0t".utf8), "mark: then popped (iTerm2, Warp)")
    check(ArisSessionMark.unmarking(restore: "✳ Fix\u{07}\u{1B}]0;x") == Array("\u{1B}[23;0t".utf8) + ArisSessionMark.sequence("✳ Fix]0;x"),
          "mark: Terminal's own title is written back, made plain (no escape gets through)")
    check(ArisSessionMark.plain(String(repeating: "a", count: 300)).count == 200, "mark: a title put back is at most 200 characters")
    let title = ArisSessionScripts.terminalTitle("/dev/ttys004") ?? ""
    check(title.contains("return custom title of t") && ArisSessionScripts.terminalTitle("x\" & quit") == nil, "mark: Terminal's custom title is read by tty only")
    check(live.contains("O_WRONLY | O_NOCTTY | O_NONBLOCK"), "mark: the tty is opened without becoming Aris's own")
}

// MARK: - The look

private func sessionScreenTests() {
    typealias S = ArisSessionScreen
    let idle: [(text: String, y: Double)] = [("✻ Welcome to Claude Code!", 0.05), ("cwd: /Users/p/site", 0.1), ("Done. The site is updated.", 0.5),
                                              (">", 0.86), ("? for shortcuts", 0.95)]
    check(S.verdict(idle) == .idle, "look: the idle input box")
    check(S.verdict([("> ", 0.85), ("⏵⏵ bypass permissions on (shift+tab to cycle)", 0.95)]) == .idle, "look: the bypass footer")
    check(S.verdict([("> ", 0.85), ("⏵⏵ auto mode on (shift+tab to cycle)", 0.95)]) == .idle, "look: the auto mode footer")
    check(S.verdict([("✻ Working… (12s · esc to interrupt)", 0.8), ("> ", 0.86), ("? for shortcuts", 0.95)]) == .working, "look: working")
    check(S.verdict([("Do you want to make this edit?", 0.7), ("❯ 1. Yes", 0.8), ("2. No", 0.85)]) == .asking, "look: a permission question")
    check(S.verdict([("Last login: Sun Nov 15", 0.1), ("user@mac site % ", 0.9)]) == .notClaude, "look: a shell prompt is not Claude Code")
    check(S.verdict([("esc to interrupt", 0.2), ("? for shortcuts", 0.95)]) == .idle, "look: what scrolled by above doesn't count")
    check(S.verdict([]) == .notClaude, "look: nothing read is not proof")
    // VM pass 2: a half-typed draft (or a paste left without Return) would be joined and sent.
    check(S.verdict([("> /unslop 사이트 humanize 해줘", 0.85), ("? for shortcuts", 0.95)]) == .draft, "look: words already in the input box: a draft")
    check(S.verdict([("> Try \"refactor <filepath>\"", 0.85), ("? for shortcuts", 0.95)]) == .idle, "look: Claude Code's grey suggestion isn't a draft")
    check(S.verdict([("│ > │", 0.85), ("? for shortcuts", 0.95)]) == .idle, "look: an empty boxed prompt")
    check(S.promptRest("❯ hello") == "hello" && S.promptRest("> ") == "" && S.promptRest("user@mac % ") == nil, "look: the prompt line's words")
    // VM pass 3: iTerm2's bar that takes the next key ate the Return.
    check(S.takesNextKey(["A control sequence attempted to clear scrollback history. Press any key to dismiss this message."]) && !S.takesNextKey(["Claude Code is running. Want to try the integration?", "Try It Now"]),
          "look: a notice that takes the next key stops it; one with buttons only doesn't")
    check(ArisSessionStop.terminalNotice.line(english: false).contains("안내를 닫고"), "look: the notice line says to close it")
    let liveSource = sessionSource("ArisAgent/ArisSessionWindowsLive.swift") + sessionSource("ArisAgent/ArisSessionHostsLive.swift")
    check(liveSource.contains("if ArisSessionScreen.takesNextKey(texts(window, roles:") && liveSource.contains("if ArisSessionScreen.takesNextKey([text]) { return .terminalNotice }"),
          "look: every look checks for such a notice first")
    check(!liveSource.contains("NSPasteboard"), "keys: the text is typed into the session, never through the user's clipboard")
    // A picture is read whole (VM pass 2: iTerm2's working spinner sat above the bottom band).
    check(S.verdict([("✻ Working… (esc to interrupt)", 0.40), ("? for shortcuts", 0.57)], band: 1) == .working, "look: a picture's working mark anywhere stops it")
    check(S.verdict([("? for shortcuts", 0.38)], band: 1) == .idle, "look: a picture with the box high up still reads idle")
    // The terminal's own text (Accessibility), as the VM's fake session showed it.
    let text = "╭──────╮\n│ ✻ Welcome to Claude Code! │\n│   cwd: /Users/admin/proj-site │\n╰──────╯\n\n" + String(repeating: "old line\n", count: 40)
        + "────────\n> \n────────\n  ? for shortcuts\n"
    check(S.verdict(S.lines(fromText: text)) == .idle, "look: the text area's idle box")
    check(S.lines(fromText: text).count == 6 && (S.lines(fromText: text).last?.y ?? 0) == 1, "look: its last lines, at the bottom")
    check(S.verdict(S.lines(fromText: "> /unslop 사이트 humanize 해줘\n* Working... (esc to interrupt)\n")) == .working, "look: working, in text")
    check(S.verdict(S.lines(fromText: "Last login: Sun\nadmin@Mac ~ % ")) == .notClaude, "look: a shell, in text")
    check(S.verdict(S.lines(fromText: "esc to interrupt\n" + String(repeating: "x\n", count: 30) + "> \n? for shortcuts")) == .idle, "look: an old line high up doesn't count")
    // VM pass 2: an old "Working…" frame in the scrollback, a few lines above the live box, refused every send.
    let stale = "✻ Working… (esc to interrupt)\n────\n> \n────\n? for shortcuts\nSUBMITTED: x\nDone.\nsomething\nmore\n────\n> \n────\n? for shortcuts\n"
    check(S.verdict(S.lines(fromText: stale)) == .idle, "look: only the live box and the line above it count")
    check(S.verdict(S.lines(fromText: "사\0이\0트\n> \n? for shortcuts")) == .idle && S.lines(fromText: "사\0이\0트\n> ").first?.text == "사이트", "look: iTerm2's NUL padding taken out")
}

// MARK: - The app's side

private func sessionAppRouteTests() {
    MainActor.assumeIsolated {
        let store = ClaudeStore()
        func event(_ json: [String: Any], headers: [String: String] = [:]) -> ClaudeHookEvent { ClaudeHookEvent(json: json, headers: headers)! }
        let id = "sess-1"
        store.apply(event(["hook_event_name": "UserPromptSubmit", "session_id": id, "cwd": "/Users/p/site"],
                          headers: ["x-warp-focus": "warp://session/0123456789abcdef0123456789abcdef"]))
        check(store.sessions[id]?.lastHook == "UserPromptSubmit", "app: the last hook is kept")
        store.apply(event(["hook_event_name": "Stop", "session_id": id, "cwd": "/Users/p/site", "last_assistant_message": "Site updated."]))
        check(store.sessions[id]?.lastHook == "Stop", "app: a Stop is kept as Stop")
        store.apply(event(["hook_event_name": "Notification", "session_id": id, "cwd": "/Users/p/site", "notification_type": "idle_prompt"]))
        check(store.sessions[id]?.lastHook == "Notification:idle_prompt", "app: a notification keeps its kind")
        check(store.sessions[id].map { $0.with(state: .sleeping).lastHook } == "Notification:idle_prompt", "app: resting keeps the last hook")
        let listed = ClaudeSessionsRoute.list(Array(store.sessions.values), approvals: [], now: Date())
        let rows = listed["sessions"] as? [[String: Any]] ?? []
        check(rows.count == 1 && rows[0]["lastHook"] as? String == "Notification:idle_prompt" && rows[0]["cwd"] as? String == "/Users/p/site"
              && (rows[0]["terminal"] as? [String: String])?["kind"] == "warp", "app: the list has the hook, the folder and the terminal")
        check(rows[0]["lastMessage"] == nil && !(String(data: (try? JSONSerialization.data(withJSONObject: listed)) ?? Data(), encoding: .utf8) ?? "").contains("Site updated"),
              "app: no text a session wrote is in the list")
        // The agent reads it the same way.
        let live = rows.compactMap(ArisLiveSession.init(json:))
        check(live.count == 1 && live[0].lastHook == "Notification:idle_prompt" && live[0].terminalKind == "warp" && ArisSessionPick.busy(live[0]) == nil,
              "app: the agent's reading of the list says idle")
        let answered = ClaudeSessionsRoute.answer(["op": "list"], store: store, watch: ClaudeSessionWatch())
        check(((try? JSONSerialization.jsonObject(with: answered)) as? [String: Any])?["ok"] as? Bool == true, "app: op list answers")
        let bad = ClaudeSessionsRoute.answer(["op": "type"], store: store, watch: ClaudeSessionWatch())
        check(((try? JSONSerialization.jsonObject(with: bad)) as? [String: Any])?["ok"] as? Bool == false, "app: no other op")
        // The watch: the next Stop is said once, a SessionEnd forgets it.
        let watch = ClaudeSessionWatch()
        _ = ClaudeSessionsRoute.answer(["op": "watch", "session": id], store: store, watch: watch)
        check(watch.count == 1, "app: watch a known session")
        _ = ClaudeSessionsRoute.answer(["op": "watch", "session": "nope"], store: store, watch: watch)
        check(watch.count == 1, "app: an unknown session isn't watched")
        let now = Date()
        check(watch.heard(event(["hook_event_name": "PreToolUse", "session_id": id, "cwd": "/Users/p/site", "tool_name": "Edit"]), at: now) == nil, "app: working says nothing")
        let done = watch.heard(event(["hook_event_name": "Stop", "session_id": id, "cwd": "/Users/p/site", "last_assistant_message": "Humanized the copy."]), at: now)
        check(done?.folder == "site" && done?.message == "Humanized the copy.", "app: its Stop is said with its last words")
        check(watch.heard(event(["hook_event_name": "Stop", "session_id": id, "cwd": "/Users/p/site"]), at: now) == nil, "app: only once")
        watch.watch(id, folder: "site", at: now)
        check(watch.heard(event(["hook_event_name": "SessionEnd", "session_id": id, "cwd": "/Users/p/site"]), at: now) == nil && watch.count == 0, "app: a SessionEnd forgets it")
        watch.watch(id, folder: "site", at: now.addingTimeInterval(-ClaudeSessionWatch.keep - 1))
        check(watch.heard(event(["hook_event_name": "Stop", "session_id": id, "cwd": "/Users/p/site"]), at: now) == nil, "app: an old watch says nothing")
        for n in 0..<20 { watch.watch("s\(n)", folder: "f", at: now.addingTimeInterval(Double(n))) }
        check(watch.count <= ClaudeSessionWatch.most, "app: at most a few watched")
        check(ClaudeSessionWatch.finishedLine(folder: "aris-site", message: "다 했어요.", korean: true) == "aris-site 세션이 끝냈어요. 다 했어요."
              && ClaudeSessionWatch.finishedLine(folder: "aris-site", message: nil, korean: true) == "aris-site 세션이 끝냈어요.", "app: the finished line")
        check(ClaudeHookRoute.slowPaths.contains(ClaudeSessionsRoute.path), "app: the hook server answers /aris/sessions (with the token, like /aris/todos)")
    }
}

// MARK: - Every gate and brain

private func sessionPolicyTests() {
    let tools = "/x/aris-tools"
    let send = "\(tools) session send \"aris-site\" \"/unslop humanize it\""
    check(ArisRiskPolicy.risk(of: .shell(send), tools: tools, home: home) == .auto, "policy: the shell gate lets it through (the agent's card is the one card)")
    check(ArisRiskPolicy.risk(of: .shell("\(tools) session list"), tools: tools, home: home) == .auto, "policy: listing reads")
    check(ArisHandsFree.risk(.auto, of: .shell(send), tools: tools) == .auto, "policy: hands-free asks no second card (the agent's card always shows)")
    check(ArisSealedTools.allows(["session", "send", "aris-site", "/unslop humanize it"]) && ArisSealedTools.allows(["session", "list"]),
          "policy: on the sealed list (the agent asks the user)")
    check(!ArisSealedTools.allows(["session", "send", "aris-site"]) && !ArisSealedTools.allows(["session", "kill", "x", "y"]), "policy: only its forms")
    check(ArisSealedTools.allowRules(tools: tools).contains("Bash(\(tools) session send:*)"), "policy: the sealed Claude's allow rule")
    check(ArisTurnGate.staysLocal(["session", "send", "a", "b"]), "policy: the open Claude's turn gate hands it to the agent")
    if case .allow = ArisTurnGate.verdict(tool: "Bash", command: send, tools: tools, tainted: true) {} else { check(false, "policy: the open Claude runs it after outside text (the card asks)") }
    if case .deny = ArisTurnGate.verdict(tool: "Bash", command: send + " && \(tools) timer 5", tools: tools, tainted: false) {} else { check(false, "policy: never chained") }
    check(ArisAgyRelay.permitted(["session", "send", "aris-site", "/unslop"], sealed: true) && ArisAgyRelay.permitted(["session", "list"], sealed: true, handsFree: true),
          "policy: agy's relay runs it through the same card")
    check(ArisSendClaim.maySend.contains("session"), "policy: a turn that sent to a session isn't told it sent nothing")
    check(ArisTeammateScope.needed(forTools: ["session", "send", "a", "b"]) == [.apps, .send] && ArisTeammateScope.needed(forTools: ["devin", "sessions"]) == [.apps],
          "policy: a teammate needs apps (and send) for these")
    check(ArisTeammateScope.knownSubcommands.contains("session") && ArisTeammateScope.knownSubcommands.contains("devin"), "policy: the teammate deny rules know them")
    // Devin: a read of another app's records, outside text.
    check(ArisLocalReadPolicy.isRead(["devin", "sessions"]) && ArisLocalReadPolicy.isRead(["devin", "sessions", "--all"]) && !ArisLocalReadPolicy.isRead(["devin", "rm"]),
          "policy: devin sessions is a read (and only that)")
    check(!ArisLocalReadPolicy.privateReads.contains("devin") && !ArisTurnGate.bringsNothingIn(["devin", "sessions"]), "policy: its answer is outside text")
    check(ArisLocalReadPolicy.storeFragments.contains("/.local/share/devin") && ArisLocalReadPolicy.storeFolders.contains(".local/share/devin"),
          "policy: Devin's store (and its sign-in) is never a raw shell read")
    check(ArisSealedTools.allows(["devin", "sessions"]), "policy: sealed turns read it too, judged")
    // The terminal refusal points the way.
    let note = ArisRefusalWords.neverNote(.computerUse(app: "Warp"), why: "terminal", tools: tools) ?? ""
    check(note.contains("session send") && note.contains("devin sessions") && note.contains("never through Aside"), "policy: a refused look at a terminal names the session tools, never Aside")
    // The API brain's functions.
    let functions = ArisAPICatalog.entries.map(\.function.name)
    check(functions.contains("claude_session_send") && functions.contains("claude_sessions") && functions.contains("devin_sessions"), "policy: the API brain has the functions")
    if let entry = ArisAPICatalog.entries.first(where: { $0.function.name == "claude_session_send" }) {
        check(entry.argv(["session": "aris-site", "text": "/unslop humanize it"]) == ["session", "send", "aris-site", "/unslop humanize it"], "policy: its argv")
        check(entry.argv(["session": "aris-site", "text": ""]) == nil && entry.argv(["text": "x"]) == nil, "policy: nothing empty")
    }
}

private func sessionPromptTests() {
    let tools = "/x/aris-tools"
    let shell = ArisAgentPrompt.sessionRule(tools, form: .shell)
    check(shell.contains("`\(tools) session send \"<folder>\" \"<text>\"`") && shell.contains("`\(tools) devin sessions`") && shell.contains("ask the user once"),
          "prompt: the shell form names the commands and the one question")
    check(shell.contains("never `claude --resume` or `claude -p`") && shell.contains("Never desktop typing into a Claude Code session"), "prompt: a Claude Code session only through the session tool")
    check(shell.contains("always asks the user on a card") && shell.contains("never start, stop, delete or send to a Devin session"), "prompt: the card, and Devin read only")
    check(ArisAgentPrompt.sessionRule(tools, form: .functions).contains("claude_session_send(session, text)"), "prompt: the API brain's form")
    check(ArisAgentPrompt.sessionRule(tools, form: .relay).contains("aris-run block of one `session send"), "prompt: agy's form")
    let aside = ArisAgentPrompt.asideRule(tools, form: .shell)
    check(aside.contains("Aside sees only websites: never for an app or a session on this Mac") && aside.contains("Warp"), "prompt: Aside is for websites only")
    let source = sessionSource("ArisAgent/ArisAgentPrompt.swift")
    check(source.components(separatedBy: "sessionRule(tools, form:").count - 1 == 2, "prompt: every brain's prompt carries the session rule (both builders)")
}

// MARK: - 3. Aside is for websites only

private func sessionAsideLocalTests() {
    typealias L = ArisAsideLocal
    let today = "Warp 터미널의 데빈 세션 2개가 뭔 내용인지, 뭔 답변 보냈는지 알려줘"
    check(L.isLocal(today), "aside: today's case (a Warp tab's Devin sessions) is local")
    for local in ["Check what the two Devin sessions in Warp said", "클로드 코드 세션이 뭐 하는지 봐 줘", "Finder에서 다운로드 폴더 정리", "iTerm2 창에 뭐 떠 있는지",
                  "codex cli session status", "터미널 창에 있는 에러 읽어 줘"] {
        check(L.isLocal(local), "aside: local: \(local)")
    }
    for web in ["쿠팡에서 생수 최저가 찾아줘", "Find the cheapest flight to Tokyo on skyscanner.com", "인천공항 2터미널 주차 예약 사이트에서 자리 있는지",
                "Notion에서 회의록 페이지 찾아줘", "app.devin.ai에서 세션 목록 확인", "claude.ai 웹에서 내 대화 찾아줘", "아마존에서 키보드 주문 내역 봐 줘"] {
        check(!L.isLocal(web), "aside: a website's work: \(web)")
    }
    check(L.isLocal("Notion 앱에서 회의록 찾아줘", installed: ["Notion"]) && !L.isLocal("Notion에서 회의록 찾아줘", installed: ["Notion"]),
          "aside: an installed app named as the app is local; its name alone may be the site")
    check(L.isLocal("the KakaoTalk app: read my last chat", installed: ["KakaoTalk"]), "aside: an installed app")
    // The gate: refused before any card, Aside never run, the right route named.
    let log = AsideRunLog()
    let turn = FakeAsideTurn(brain: "claude", answers: [.yes([:])])
    var deps = ArisAsideDeps(locate: { .ready("/x/aside") }, run: { path, arguments, environment, _ in
        log.runs.append((path, arguments, environment)); return ArisSkillProcessResult(status: 0, stdout: "x", stderr: "", timedOut: false)
    }, open: { _ in true }, environment: [:])
    let out = ArisAsideTool.answer(today, turn: turn, critical: false, deps: deps)
    check(out.status != 0 && out.output == L.line && turn.cards.isEmpty && log.runs.isEmpty, "aside: today's brief is refused, no card, Aside never runs")
    check(L.line.contains("session send") && L.line.contains("devin sessions") && L.line.contains("desktop see") && L.line.contains("say plainly"),
          "aside: the refusal names the session tools, a look, or saying it can't")
    check(turn.audits.last?["answer"] == "refused (an app or session on this Mac)", "aside: audited as a rule, not the user's no")
    deps.local = { _ in false }
    deps.verify = { _ in true }
    _ = ArisAsideTool.answer("쿠팡에서 생수 최저가 찾아줘", turn: FakeAsideTurn(brain: "claude", answers: [.yes([:])]), critical: false, deps: deps)
    check(log.runs.count == 1, "aside: a website's work still runs")
    let installedNames = L.installedApps(home: NSTemporaryDirectory())
    check(installedNames.allSatisfy { !$0.hasSuffix(".app") }, "aside: installed app names without .app")
}

// MARK: - 2. Devin, read only

private func sessionDevinTests() {
    typealias D = ArisDevinRead
    check(D.text(of: "hello") == "hello" && D.text(of: [["type": "text", "text": "a"], ["type": "image_url"], ["type": "text", "text": "b"]]) == "a b", "devin: a message's text")
    let chain = [D.Message(role: "assistant", text: ""), D.Message(role: "tool", text: "ok"), D.Message(role: "assistant", text: "Updated the deck."),
                 D.Message(role: "user", text: "<system-reminder>x</system-reminder>"), D.Message(role: "user", text: "슬라이드 고쳐 줘"), D.Message(role: "assistant", text: "old")]
    let exchange = D.lastExchange(chain)
    check(exchange.answered == "Updated the deck." && exchange.asked == "슬라이드 고쳐 줘", "devin: the newest answer with words and the user's ask before it")
    check(D.masked("key sk-ant-REDACTEDREDACTED1234 and ghp_abcdefghijklmnopqrstuvwxyz0123 token: abc").contains("[가림]")
          && !D.masked("key sk-ant-REDACTEDREDACTED1234").contains("sk-ant") && !D.masked("ghp_abcdefghijklmnopqrstuvwxyz0123").contains("ghp_")
          && !D.masked("password: hunter2").contains("hunter2"), "devin: keys, tokens and passwords masked")
    check(D.masked("Fixed the login bug in auth.swift") == "Fixed the login bug in auth.swift", "devin: plain words untouched")
    check(D.quote(String(repeating: "가", count: 400)).count == D.longestQuote, "devin: a quote is cut with …")
    check(!D.quote("a\nb \"c\"").contains("\n") && !D.quote("\"c\"").contains("\""), "devin: one line, no quote marks to break out of")
    let now = Date()
    let rows = (0..<5).map { D.Session(id: "s\($0)", folder: home, title: "t\($0)", lastActivity: now.addingTimeInterval(Double(-$0 * 60)), head: $0) }
    check(D.chosen(rows, running: ["s3", "s1"], all: false).map(\.id) == ["s1", "s3"], "devin: the running ones, newest first")
    check(D.chosen(rows, running: [], all: false).map(\.id) == ["s0", "s1", "s2"], "devin: none running: the three newest")
    check(D.chosen(rows, running: ["s1"], all: true).count == 5, "devin: --all")
    check(D.isSessionID("ninth-trampoline") && !D.isSessionID("../x") && !D.isSessionID(""), "devin: only a session id from a lock's name")
    check(D.seconds(1_794_784_536) == 1_794_784_536 && D.seconds(1_794_784_536_000) == 1_794_784_536, "devin: seconds (milliseconds taken too)")
    let report = D.report([D.Summary(session: rows[0], running: true, asked: "뭐 해?", answered: "Working on the API sk-ant-REDACTEDREDACTED9999")], runningCount: 1, now: now, home: home)
    check(report.contains("running now (1)") && report.contains("outside text written by Devin") && report.contains("asked: \"뭐 해?\"")
          && !report.contains("sk-ant") && report.contains("never starts, stops or sends"), "devin: the report, masked, read only")
    check(D.report([], runningCount: 0, now: now, home: home).contains("No Devin session"), "devin: none")

    // A real database with Devin's schema, in a throwaway home: read back, and never written.
    let base = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("aris-devin-\(UUID().uuidString)")
    let folder = base.appendingPathComponent(".local/share/devin/cli")
    try? FileManager.default.createDirectory(at: folder.appendingPathComponent("session_locks"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: base) }
    let path = folder.appendingPathComponent("sessions.db").path
    var db: OpaquePointer?
    sqlite3_open(path, &db)
    let sql = """
    CREATE TABLE sessions (id TEXT PRIMARY KEY, working_directory TEXT NOT NULL, backend_type TEXT NOT NULL, model TEXT NOT NULL, agent_mode TEXT NOT NULL,
      created_at INTEGER NOT NULL, last_activity_at INTEGER NOT NULL, title TEXT, main_chain_id INTEGER, hidden INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE message_nodes (row_id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT NOT NULL, node_id INTEGER NOT NULL, parent_node_id INTEGER,
      chat_message TEXT NOT NULL, created_at INTEGER NOT NULL, metadata TEXT, UNIQUE(session_id, node_id));
    INSERT INTO sessions VALUES ('warp-rainstorm', '\(base.path)', 'w', 'm', 'bypass', 1794700000, 1794784536, 'Boring Notch 인수인계', 4, 0);
    INSERT INTO sessions VALUES ('hidden-one', '\(base.path)', 'w', 'm', 'bypass', 1794700000, 1794784999, 'hidden', 1, 1);
    INSERT INTO message_nodes (session_id, node_id, parent_node_id, chat_message, created_at) VALUES
      ('warp-rainstorm', 1, NULL, '{"role":"user","content":"인수인계 문서 정리해 줘"}', 1),
      ('warp-rainstorm', 2, 1, '{"role":"assistant","content":"","tool_calls":[{"id":"t"}]}', 2),
      ('warp-rainstorm', 3, 2, '{"role":"tool","content":"done","tool_call_id":"t"}', 3),
      ('warp-rainstorm', 4, 3, '{"role":"assistant","content":[{"type":"text","text":"HANDOFF.md 정리했어요. token: abcdef"}]}', 4);
    """
    sqlite3_exec(db, sql, nil, nil, nil)
    sqlite3_close(db)
    let before = (try? FileManager.default.attributesOfItem(atPath: path)) ?? [:]
    let read = D.read(home: base.path, all: false, now: Date(timeIntervalSince1970: 1_794_784_600))
    check(read?.summaries.count == 1 && read?.summaries.first?.session.id == "warp-rainstorm" && read?.running == 0, "devin: the visible session, none running")
    check(read?.summaries.first?.asked == "인수인계 문서 정리해 줘" && read?.summaries.first?.answered?.hasPrefix("HANDOFF.md 정리했어요.") == true,
          "devin: the chain from its head: the ask and the last answer")
    let after = (try? FileManager.default.attributesOfItem(atPath: path)) ?? [:]
    check(before[.size] as? Int == after[.size] as? Int && (before[.modificationDate] as? Date) == (after[.modificationDate] as? Date), "devin: the database is never written")
    check(D.read(home: base.appendingPathComponent("none").path, all: false) == nil, "devin: no records: nil")
    let shown = D.report(read?.summaries ?? [], runningCount: 0, now: Date(timeIntervalSince1970: 1_794_784_600), home: home)
    check(shown.contains("No Devin session is running now") && !shown.contains("abcdef"), "devin: printed with the token masked")
    let source = sessionSource("ArisTools/ArisDevinRead.swift")
    check(source.contains("SQLITE_OPEN_READONLY") && source.contains("?mode=ro") && !source.contains("credentials.toml\")")
          && !source.contains("sqlite3_exec(") && !source.contains("INSERT") && !source.contains("DELETE"), "devin: read-only by its code too, never the credentials")
    check(!source.contains("flock(") && !source.contains("kill("), "devin: never locks or signals a session")
}

// MARK: - Wiring

private func sessionWiringTests() {
    let main = sessionSource("ArisAgent/main.swift")
    check(main.contains("case \"/session-tool\":") && main.contains("ArisSessionRoutes.tool(object"), "wiring: the agent's route")
    check(main.contains("if ArisSessionCall.isSession(words) { return ArisSessionRoutes.relayed(words, turn: serviceTurn) }"), "wiring: agy's relay")
    let tools = sessionSource("ArisTools/main.swift")
    check(tools.contains("case \"session\": session(") && tools.contains("case \"devin\": devinRead("), "wiring: aris-tools commands")
    let route = sessionSource("ArisAgent/ArisSessionRoutes.swift")
    check(route.contains("ArisMCPCaller.isInside(root: pid") && route.contains("runner(forMCPTurn: credential)"), "wiring: the caller is checked as /aside-tool's")
    let send = sessionSource("ArisAgent/ArisSessionSend.swift")
    let card = send.range(of: "switch ask(ArisSessionPick.card")?.lowerBound, paste = send.range(of: "deps.paste(text, target)")?.lowerBound
    let focus = send.range(of: "deps.focus(now, process)")?.lowerBound, look = send.range(of: "deps.look(target)")?.lowerBound
    if let card, let paste, let focus, let look { check(card < focus && focus < look && look < paste, "wiring: card, then focus, then the look, then the paste") }
    else { check(false, "wiring: the send's steps are all there") }
    let live = sessionSource("Aris/private/Claude/ClaudeHookLive.swift")
    check(live.contains("case ClaudeSessionsRoute.path: sessions(object, reply)"), "wiring: the app answers the agent")
    let teammate = sessionSource("Aris/private/Aris/ArisController+Teammate.swift")
    check(teammate.contains("ClaudeSessionWatch.shared.heard(event, at: now)") && teammate.contains("sessionFinished(folder:"), "wiring: a sent session's Stop is said")
    let desktopGate = sessionSource("ArisAgent/ArisDesktopGate.swift"), insert = sessionSource("ArisAgent/ArisInsertRefusal.swift")
    check(!desktopGate.contains("ArisSession") && !insert.contains("ArisSession"), "wiring: the desktop gate's and ArisInsert's terminal refusals are untouched")
    check(!sessionSource("ArisAgent/ArisSessionLive.swift").contains("--resume") && !send.contains("\"-p\""), "wiring: never claude --resume -p")
}
