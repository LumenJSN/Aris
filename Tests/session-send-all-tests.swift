// Tests for phase B of desktop-bg (the owner, 2026-11-16: "Not just Warp, everything else has to work too"): a prompt
// typed into one of his Claude Code sessions wherever it lives: which process is the session (Claude Code's own list),
// which host it is in (tmux, screen, WezTerm, kitty, iTerm2, Terminal, Warp, an editor's terminal, any terminal app, the
// Claude app's Code tab), refused and named where the place can't be proven. Called from main.swift; uses its check().
// Nothing here runs a host's tool, writes to a tty or posts a key.
import Foundation

private let allRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private func allSource(_ path: String) -> String { (try? String(contentsOf: allRoot.appendingPathComponent(path), encoding: .utf8)) ?? "" }

func runSessionSendAllTests() {
    sessionAgentsTests()
    sessionHostTests()
    sessionHostLineTests()
    sessionHostScriptTests()
    sessionDesktopTests()
    sessionAllWiringTests()
}

// MARK: - Which process is the session

private func sessionAgentsTests() {
    let json = #"""
    [{"pid":6116,"id":"15c44bcc","cwd":"/Users/p/a","kind":"background","sessionId":"15c44bcc-892f-421d-8df6-68f698ff751e","name":"x","status":"idle"},
     {"pid":85595,"cwd":"/Users/p/b","kind":"interactive","sessionId":"de729d67-1f93-4d0c-b55c-032162c1d54a","name":"y","status":"idle"},
     {"pid":"bad","sessionId":"zz"},
     {"pid":57418,"cwd":"/Users/p/c","kind":"interactive","sessionId":"63e66725-3ec0-4349-8405-fba8d380f0c9"}]
    """#
    let entries = ArisSessionAgents.parse(Data(json.utf8)) ?? []
    check(entries.count == 3, "agents: each live session with its process (a malformed one left out)")
    check(ArisSessionAgents.entry(for: "de729d67-1f93-4d0c-b55c-032162c1d54a", in: entries)?.pid == 85595, "agents: the session's own process, by its id")
    check(ArisSessionAgents.entry(for: "15c44bcc-892f-421d-8df6-68f698ff751e", in: entries)?.background == true, "agents: a background session says so")
    check(ArisSessionAgents.entry(for: "nope", in: entries) == nil && ArisSessionAgents.parse(Data("{}".utf8)) == nil, "agents: none, or not a list")
    let twice = entries + [ArisSessionAgents.Entry(sessionId: entries[1].sessionId, pid: 9, background: false, cwd: "")]
    check(ArisSessionAgents.entry(for: entries[1].sessionId, in: twice) == nil, "agents: two processes with one id: neither (never a guess)")
    check(ArisSessionProcesses.terminalKeys.isSuperset(of: ["TMUX", "TMUX_PANE", "STY", "WINDOW", "KITTY_WINDOW_ID", "KITTY_LISTEN_ON", "WEZTERM_PANE",
                                                           "WEZTERM_UNIX_SOCKET", "__CFBundleIdentifier", "CLAUDE_CODE_ENTRYPOINT", "TERM_SESSION_ID"]),
          "agents: the terminal variables read from the process (only these: never a key)")
    check(!ArisSessionProcesses.terminalKeys.contains("ANTHROPIC_API_KEY") && !ArisSessionProcesses.terminalKeys.contains { $0.contains("TOKEN") || $0.contains("KEY") && $0 != "KITTY_WINDOW_ID" },
          "agents: no secret is ever read")
}

// MARK: - Which host

private func sessionHostTests() {
    typealias H = ArisSessionHost
    let tty = "/dev/ttys004"
    func host(_ env: [String: String], tty: String? = "/dev/ttys004", bundle: String? = nil, background: Bool = false) -> H {
        H.classify(environment: env, tty: tty, hostBundle: bundle, hostName: nil, background: background)
    }
    check(host(["TMUX": "/private/tmp/tmux-501/default,123,0", "TMUX_PANE": "%7", "TERM_PROGRAM": "WarpTerminal"]) == .tmux(socket: "/private/tmp/tmux-501/default", pane: "%7"),
          "host: tmux first, inside any terminal (exact by its pane)")
    check(host(["TMUX": "relative,1,0", "TMUX_PANE": "%7", "TERM_PROGRAM": "Apple_Terminal"]) == .terminalApp, "host: a tmux socket that isn't a path is ignored")
    check(host(["TMUX": "/tmp/t,1,0", "TMUX_PANE": "%7; rm"]) != .tmux(socket: "/tmp/t", pane: "%7; rm"), "host: a pane that isn't one is ignored")
    check(host(["STY": "4242.ttys004.mac", "WINDOW": "2"]) == .screen(session: "4242.ttys004.mac", window: "2"), "host: screen by its session and window")
    check(host(["WEZTERM_PANE": "3", "WEZTERM_UNIX_SOCKET": "/Users/p/.local/share/wezterm/gui-sock-1"]) == .wezterm(pane: "3", socket: "/Users/p/.local/share/wezterm/gui-sock-1"),
          "host: WezTerm by its pane id")
    check(host(["KITTY_WINDOW_ID": "4", "KITTY_LISTEN_ON": "unix:/tmp/kitty"]) == .kitty(socket: "unix:/tmp/kitty", window: "4"), "host: kitty by its window id when it listens")
    check(host(["KITTY_WINDOW_ID": "4", "TERM_PROGRAM": "xterm-kitty"], bundle: "net.kovidgoyal.kitty") == .window(bundle: "net.kovidgoyal.kitty"),
          "host: kitty that doesn't listen: its window, by the mark")
    check(host(["ITERM_SESSION_ID": "w0t1p0:6B2C8F7E-0000-4000-8000-000000000001"]) == .iterm(session: "6B2C8F7E-0000-4000-8000-000000000001"), "host: iTerm2 by its session id")
    check(host(["TERM_PROGRAM": "Apple_Terminal"]) == .terminalApp, "host: Terminal")
    check(host(["TERM_PROGRAM": "WarpTerminal", "WARP_FOCUS_URL": "warp://session/0123456789abcdef0123456789abcdef"]) == .warp(focus: "warp://session/0123456789abcdef0123456789abcdef"),
          "host: Warp with its focus link")
    check(host(["TERM_PROGRAM": "WarpTerminal", "WARP_FOCUS_URL": "warp://evil"]) == .warp(focus: nil), "host: a focus link that isn't one is dropped")
    check(host(["TERM_PROGRAM": "vscode", "__CFBundleIdentifier": "com.todesktop.230313mzl4w4u92"]) == .editor(bundle: "com.todesktop.230313mzl4w4u92"), "host: Cursor's terminal")
    check(host(["TERM_PROGRAM": "vscode", "__CFBundleIdentifier": "com.google.antigravity"]) == .editor(bundle: "com.google.antigravity"), "host: Antigravity's terminal")
    check(host(["TERM_PROGRAM": "vscode"], bundle: "com.exafunction.windsurf") == .editor(bundle: "com.exafunction.windsurf"), "host: Devin (Windsurf)'s terminal")
    check(host(["TERM_PROGRAM": "ghostty", "__CFBundleIdentifier": "com.mitchellh.ghostty"]) == .window(bundle: "com.mitchellh.ghostty"), "host: Ghostty by its window")
    check(host([:], bundle: "org.alacritty") == .window(bundle: "org.alacritty"), "host: Alacritty by its window")
    check(host(["TERM_PROGRAM": "Hyper"], bundle: "co.zeit.hyper") == .window(bundle: "co.zeit.hyper"), "host: Hyper by its window")
    check(host(["CLAUDE_CODE_ENTRYPOINT": "claude-desktop", "__CFBundleIdentifier": "com.anthropic.claudefordesktop"], tty: nil) == .claudeDesktop, "host: the Claude app's Code tab")
    check(host(["CLAUDE_CODE_ENTRYPOINT": "claude-vscode"], tty: nil, bundle: "com.microsoft.VSCode") == .editorPanel(bundle: "com.microsoft.VSCode"), "host: an editor's Claude Code panel")
    check(host([:], tty: tty, background: true) == .background, "host: a background session")
    check(host(["__CFBundleIdentifier": "com.apple.dt.Xcode"], tty: nil) == .unsupported(app: "Xcode"), "host: an app with no terminal is named")
    check(H.tmuxSocket("/tmp/../etc,1,0") == nil && H.tmuxSocket("/private/tmp/tmux-501/default,1,0") == "/private/tmp/tmux-501/default", "host: the tmux socket path")
}

// MARK: - The lines

private func sessionHostLineTests() {
    for stop in [ArisSessionStop.hostNotSupported("Xcode"), .hostNotProven("Ghostty"), .backgroundSession] {
        let korean = stop.line(english: false)
        check(!korean.contains("\n") && korean.unicodeScalars.contains { $0.value >= 0xAC00 && $0.value <= 0xD7A3 }, "lines: \(stop) is one Korean line")
        check(stop.note(english: false).contains(korean), "lines: \(stop)'s note quotes it")
    }
    check(ArisSessionStop.hostNotSupported("Xcode").line(english: false).contains("Xcode") && ArisSessionStop.hostNotProven("Ghostty").line(english: false).contains("Ghostty"),
          "lines: the host is named")
    check(ArisSessionStop.backgroundSession.line(english: false).contains("claude attach"), "lines: a background session says how to open it")
    check(ArisSessionHost.editor(bundle: "com.todesktop.230313mzl4w4u92").name == "Cursor" && ArisSessionHost.window(bundle: "com.mitchellh.ghostty").name == "Ghostty"
          && ArisSessionHost.editor(bundle: "com.exafunction.windsurf").name == "Devin", "lines: hosts by the names a person uses")
}

// MARK: - Scripts

private func sessionHostScriptTests() {
    let tab = ArisSessionScripts.terminalTab("/dev/ttys004") ?? ""
    check(tab.contains("if tty of t is \"/dev/ttys004\"") && tab.contains("set selected of t to true") && tab.contains("return \"ok|\" & was"),
          "scripts: Terminal's tab selected by its tty, the tab it had said back")
    check(!tab.contains("activate") && !tab.contains("set index"), "scripts: Terminal is never brought forward nor its window raised")
    check(ArisSessionScripts.terminalTab("/dev/ttys1\" & do shell script \"x") == nil, "scripts: nothing but a tty goes in")
    let iterm = ArisSessionHostsLive.itermScript("6B2C8F7E-0000-4000-8000-000000000001", "return tty") ?? ""
    check(iterm.contains("if unique id of s is \"6B2C8F7E-0000-4000-8000-000000000001\"") && !iterm.contains("activate"), "scripts: iTerm2 by its session, never brought forward")
    check(ArisSessionHostsLive.itermScript("x\" & quit", "return tty") == nil, "scripts: only a session id goes in")
    check(ArisSessionHostsLive.quoted("say \"hi\" \\ there") == "\"say \\\"hi\\\" \\\\ there\"", "scripts: the text is one AppleScript string")
}

// MARK: - The Claude app

private func sessionDesktopTests() {
    typealias D = ArisSessionDesktopLive
    let records: [(file: String, data: Data)] = [
        ("a", Data(#"{"sessionId":"local_aaaa-1","cliSessionId":"cli-1","isArchived":false}"#.utf8)),
        ("b", Data(#"{"sessionId":"local_bbbb-2","cliSessionId":"cli-2","isArchived":true}"#.utf8)),
        ("c", Data(#"{"sessionId":"evil\"id","cliSessionId":"cli-3"}"#.utf8)),
    ]
    check(D.localId(for: "cli-1", records: records) == "local_aaaa-1", "claude app: the app's own id for the CLI session")
    check(D.localId(for: "cli-2", records: records) == nil && D.localId(for: "cli-3", records: records) == nil, "claude app: archived or malformed: none")
    check(D.link("local_aaaa-1")?.absoluteString == "claude://code/continue?session=local_aaaa-1&source=aris" && D.link("local_x&y") == nil, "claude app: the app's own link, by a checked id")
    check(D.shown(in: "https://claude.ai/epitaxy/local_aaaa-1") == "local_aaaa-1" && D.shown(in: "https://claude.ai/new") == nil, "claude app: the session its window shows")
}

// MARK: - Wiring

private func sessionAllWiringTests() {
    let live = allSource("ArisAgent/ArisSessionLive.swift")
    check(live.contains("ArisSessionHostsLive.reach(") && live.contains("\"agents\", \"--json\""), "wiring: the process by Claude Code's own list, the place by its host")
    let hosts = allSource("ArisAgent/ArisSessionHostsLive.swift")
    check(hosts.contains("\"paste-buffer\", \"-p\", \"-d\"") && hosts.contains("\"send-keys\", \"-t\", pane, \"Enter\""), "wiring: tmux pastes then presses Enter in that pane")
    check(hosts.contains("#{pane_tty}|#{pane_in_mode}|#{pane_dead}"), "wiring: tmux's pane is that tty, alive and not in copy mode, before each step")
    let windows = allSource("ArisAgent/ArisSessionWindowsLive.swift")
    check(windows.contains("reach.finish = {") && windows.contains("turn.restore()") && windows.contains("putBack()"), "wiring: every turn in front is put back")
    check(windows.contains("NSWorkspace.shared.open(back)"), "wiring: Warp's own tab comes back")
    // An editor's terminal (VM, 2026-11-16): its input is named "Terminal N, <title> …", the proof and the way back.
    check(ArisSessionWindowsLive.terminalNumber("Terminal 2, zsh Use ⌥F1 for terminal accessibility help") == 2
          && ArisSessionWindowsLive.terminalNumber("Terminal input") == nil && ArisSessionWindowsLive.terminalNumber("Terminal 1 claude") == nil,
          "wiring: an editor's terminal by its number")
    check(windows.contains("ArisSessionMark.shows(ArisAX.string(focused, kAXDescriptionAttribute as String), mark: mark)"),
          "wiring: an editor's keys go only while its marked terminal input has the keyboard")
    check(windows.contains("func makeMain(_ window: AXUIElement)") && !windows.contains("activate()") && !windows.contains("set index"),
          "wiring: a host's window is made its main one without the host coming forward")
    let hostsSource = allSource("ArisAgent/ArisSessionHostsLive.swift")
    check(hostsSource.contains("\"stuff\", \"\\r\"") && hostsSource.contains("String(decoding: data, as: UTF8.self)"), "wiring: screen's Return is a real carriage return; its copy read leniently")
    let liveCode = allSource("ArisAgent/ArisSessionLive.swift")
    check(liveCode.contains("guard let reached = reach(target) else { return .focusMoved }") && !liveCode.contains("?.look() ?? .focusMoved"),
          "wiring: a reach's own ready (nil) is never turned into a stop")
    let send = allSource("ArisAgent/ArisSessionSend.swift")
    check(send.contains("defer { deps.finish(target) }"), "wiring: whatever was changed is put back whether sent or stopped")
}
