// Tests for a Claude Code teammate that starts without disturbing (team-quiet): when the launch may start
// (ArisQuietLaunch.mayStart), whether the front app is handed back, which terminal is used, the window's name, the
// launch script and each terminal's plan word for word, whose window it is, and what happens to it when the job is
// over. Called from main.swift; uses its check(). Pure rules and source reads only: no terminal is opened, no
// process is started, nothing is asked of macOS.
import CoreGraphics
import Foundation

func runTeamQuietTests() {
    teamQuietStartTests()
    teamQuietFrontTests()
    teamQuietPickTests()
    teamQuietTitleTests()
    teamQuietScriptTests()
    teamQuietPlanTests()
    teamQuietWindowTests()
    teamQuietEndTests()
    teamQuietWiringTests()
    teamQuietReview7Tests()
}

private func teamQuietSource(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("..")
    return (try? String(contentsOf: root.appendingPathComponent(path).standardized, encoding: .utf8)) ?? ""
}

private let quietId = UUID(uuidString: "0A1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9")!
private let quietWork = "/Users/p/.config/aris/aris/work"
private var quietFiles: ArisQuietFiles { ArisQuietLaunch.files(folder: quietWork, id: quietId) }

private func teamQuietStartTests() {
    typealias Q = ArisQuietLaunch
    check(!Q.mayStart(sinceKey: 0.05, waited: 0) && !Q.mayStart(sinceKey: 0.39, waited: 2.9), "quiet: the window never starts while he is in the middle of typing")
    check(Q.mayStart(sinceKey: 0.4, waited: 0) && Q.mayStart(sinceKey: 30, waited: 0), "quiet: it starts in a gap of 0.4 s in his typing")
    check(Q.mayStart(sinceKey: 0.01, waited: 3) && !Q.mayStart(sinceKey: 0.01, waited: 2.95), "quiet: it waits for a gap for 3 s at most, then starts anyway")
    check(Q.typingGap == 0.4 && Q.longestWait == 3 && Q.gapLook <= 0.05, "quiet: the gap is 0.4 s, the longest wait 3 s, looked for every 50 ms")
}

private func teamQuietFrontTests() {
    typealias Q = ArisQuietLaunch
    check(Q.front(before: 10, now: 77, terminal: 77, sinceTouch: 40, sinceOpen: 0.3) == .giveBack,
          "quiet: a terminal that came forward by itself gives the front straight back to the app he was in")
    check(Q.front(before: 10, now: 77, terminal: 77, sinceTouch: 0.1, sinceOpen: 0.3) == .leave,
          "quiet: once he has clicked or pressed a key since the launch began, the front is his choice and stays")
    check(Q.front(before: 77, now: 77, terminal: 77, sinceTouch: 40, sinceOpen: 0.3) == .leave, "quiet: he was in that terminal already: nothing is taken from it")
    check(Q.front(before: 10, now: 10, terminal: 77, sinceTouch: 40, sinceOpen: 0.3) == .leave && Q.front(before: 10, now: 55, terminal: 77, sinceTouch: 40, sinceOpen: 0.3) == .leave,
          "quiet: the front is only handed back from the teammate's terminal, never from another app he went to")
    check(Q.front(before: nil, now: 77, terminal: 77, sinceTouch: 40, sinceOpen: 0.3) == .leave && Q.front(before: 10, now: nil, terminal: 77, sinceTouch: 40, sinceOpen: 0.3) == .leave
          && Q.front(before: 10, now: 77, terminal: nil, sinceTouch: 40, sinceOpen: 0.3) == .leave, "quiet: with nothing known about the front, nothing is activated")
    check(Q.frontLook <= 0.0084 && Q.frontWatch >= 2, "quiet: the front app is looked at at least once a frame, for at least two seconds after the window was asked for")
}

private func teamQuietPickTests() {
    typealias Q = ArisQuietLaunch
    typealias F = ArisTerminalChoice.Facts
    let his = F(pinned: nil, lastUsed: nil, installed: [.terminal, .warp], running: [.warp], warpReady: true)
    check(Q.pick(his, command: "x", front: nil, unusable: []) == ArisQuietPick(terminal: .warp), "quiet: with Aside in front, the terminal he uses (Warp) is still the one")
    check(Q.pick(his, command: "x", front: .warp, unusable: []) == ArisQuietPick(terminal: .terminal, inFront: .warp),
          "quiet: a teammate never opens in the terminal he is typing in right now: the next one is taken")
    check(Q.pick(F(pinned: "warp", installed: [.terminal, .warp], running: [.warp], warpReady: true), command: "x", front: .warp, unusable: []).terminal == .terminal,
          "quiet: that holds for a pinned terminal too")
    check(Q.pick(F(installed: [.terminal], running: [.terminal]), command: "x", front: .terminal, unusable: []) == ArisQuietPick(terminal: .terminal),
          "quiet: with only the terminal he is in, that one is used (its window puts itself away)")
    check(Q.pick(his, command: "x", front: nil, unusable: [.warp]) == ArisQuietPick(terminal: .terminal, passedOver: .warp),
          "quiet: a Warp that opened a window but never ran the command is not used again")
    check(Q.pick(F(installed: [.terminal, .warp], running: [.warp], warpReady: false), command: "x", front: nil, unusable: []) == ArisQuietPick(terminal: .terminal, passedOver: .warp)
          && Q.pick(his, command: "echo {{x}}", front: nil, unusable: []).passedOver == .warp, "quiet: an older Warp, or a command Warp would ask about, is passed over as before")
    check(Q.note(ArisQuietPick(terminal: .terminal, inFront: .warp), english: false) == "Claude Code 작업 중 · Warp를 쓰고 계셔서 Terminal에서 열었어요"
          && Q.note(ArisQuietPick(terminal: .terminal, inFront: .warp), english: true) == "Claude Code at work · you are in Warp, so it opened in Terminal",
          "quiet: the job's first line says why the window is not in his terminal")
    check(Q.note(ArisQuietPick(terminal: .terminal, passedOver: .warp), english: false) == ArisTerminalWords.passedOver(.warp, openedIn: .terminal, english: false)
          && Q.note(ArisQuietPick(terminal: .warp), english: false) == nil, "quiet: a passed-over terminal is named as before; the usual case says nothing extra")
}

private func teamQuietTitleTests() {
    typealias Q = ArisQuietLaunch
    check(Q.title("로그인 버그 고치기") == "Aris · 로그인 버그 고치기" && Q.title("Fix the login bug") == "Aris · Fix the login bug", "quiet: the window is named Aris · <job>")
    check(Q.title(nil) == "Aris · Claude Code" && Q.title("  ") == "Aris · Claude Code" && Q.title("\"'`$\\") == "Aris · Claude Code", "quiet: a job with no usable name is Aris · Claude Code")
    let hostile = Q.title("it's \"x\" $(rm -rf ~) `id` \\ ; & | \n\u{1B}]0;evil\u{07} 끝")
    check(hostile == "Aris · its x (rm -rf ) id 0evil 끝", "quiet: quotes, backslashes, shell marks, line breaks and control characters never reach the name: \(hostile)")
    check(!hostile.contains("'") && !hostile.contains("\"") && !hostile.contains("\\") && !hostile.contains("$") && !hostile.contains("`") && !hostile.contains("\n"),
          "quiet: the name is safe inside a shell string, an AppleScript string and a TOML string")
    check(Q.title(String(repeating: "가", count: 90)) == "Aris · " + String(repeating: "가", count: 40), "quiet: the name is 40 characters at most")
}

private func teamQuietScriptTests() {
    typealias Q = ArisQuietLaunch
    let files = quietFiles
    check(files == ArisQuietFiles(script: quietWork + "/cc-0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9.command", pid: quietWork + "/cc-0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9.pid",
                                  window: quietWork + "/cc-0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9.window", close: quietWork + "/cc-0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9.close"),
          "quiet: a launch's four files sit beside the prompt file, under the launch's id")
    for path in [files.script, files.pid, files.window, files.close] {
        check((path as NSString).lastPathComponent.range(of: Q.filePattern, options: .regularExpression) != nil, "quiet: \((path as NSString).pathExtension) is swept after a day like the prompt files")
    }
    check("cc-0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9.txt".range(of: Q.filePattern, options: .regularExpression) == nil
          && "notes.command".range(of: Q.filePattern, options: .regularExpression) == nil, "quiet: the sweep takes only a launch's own files")
    let command = ArisClaudeLaunch.command(promptFile: quietWork + "/cc-x.txt", cwd: "/Users/p/it's \"q\" $(rm) proj", claude: "/Users/p/.local/bin/claude")
    let terminal = Q.script(command: command, title: "Aris · 버그 고치기", terminal: .terminal, shell: "/bin/zsh", files: files)
    let expected = """
        #!/bin/sh
        umask 077
        set -C
        rm -f -- '\(files.script)'
        printf '\\033]0;%s\\007' 'Aris · 버그 고치기'
        echo $$ > '\(files.pid)' || exit 1
        ARIS_TTY=$(tty)
        ARIS_WINDOW=$(/usr/bin/osascript -e 'tell application id "com.apple.Terminal"' -e 'repeat with w in windows' -e 'if (tty of selected tab of w) is "'"$ARIS_TTY"'" then' -e 'set n to id of w' -e 'if (count of tabs of w) is not 1 then return "tab " & n' -e 'set custom title of selected tab of w to "Aris · 버그 고치기"' -e 'set miniaturized of window id n to true' -e 'return n' -e 'end if' -e 'end repeat' -e 'end tell' 2>/dev/null)
        echo "$ARIS_WINDOW" > '\(files.window)' || exit 1
        export CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1
        \(command)
        if [ -e '\(files.close)' ]; then
            rm -f -- '\(files.close)' '\(files.pid)' '\(files.window)'
            case "$ARIS_WINDOW" in ''|*[!0-9]*) ;; *) ( sleep 1; /usr/bin/osascript -e 'tell application id "com.apple.Terminal"' -e 'repeat with w in windows' -e 'if (id of w) is '"$ARIS_WINDOW"' and (count of tabs of w) is 1 then' -e 'close w' -e 'return' -e 'end if' -e 'end repeat' -e 'end tell' ) > /dev/null 2>&1 < /dev/null & ;; esac
            exit 75
        fi
        rm -f -- '\(files.pid)' '\(files.window)'
        exec '/bin/zsh' -l -i

        """
    check(terminal == expected, "quiet: Terminal's launch script, word for word (names and minimises its own window, runs the command, closes up when asked, else leaves a shell)")
    check(!terminal.contains("activate") && !terminal.contains("set miniaturized of w "), "quiet: the script never brings Terminal forward, and speaks to its window by number, not by place")
    check(terminal.contains("\n\(command)\n"), "quiet: the command is the one that was typed before, unchanged (no flag that loosens Claude Code's own questions)")
    let warp = Q.script(command: command, title: "Aris · x", terminal: .warp, shell: "/bin/zsh", files: files)
    check(!warp.contains("osascript") && !warp.contains("ARIS_WINDOW") && warp.hasSuffix("rm -f -- '\(files.pid)' '\(files.window)'\nexit 0\n") && warp.contains("    exit 75\nfi\n"),
          "quiet: in Warp the script scripts nothing and hands back to Warp's own shell (0: stay, 75: leave)")
    for other in [ArisTerminal.ghostty, .kitty, .wezterm, .alacritty] {
        let text = Q.script(command: command, title: "Aris · x", terminal: other, shell: "/opt/homebrew/bin/fish", files: files)
        check(!text.contains("osascript") && text.hasSuffix("exec '/opt/homebrew/bin/fish' -l -i\n") && text.hasPrefix("#!/bin/sh\numask 077\n"),
              "quiet: \(other.title) runs the same POSIX script and keeps the account's shell open afterwards")
    }
    check(Q.keepsShell(.terminal) && !Q.keepsShell(.warp) && !Q.keepsShell(.iTerm) && Q.closeStatus == 75, "quiet: Warp and iTerm2 already have their own shell under the script")
    check(Q.line(files) == "'\(files.script)' || exit", "quiet: the line given to a terminal's own shell runs the script and leaves when it says to close up")
}

private func teamQuietPlanTests() {
    typealias Q = ArisQuietLaunch
    let files = quietFiles, warpFolder = "/Users/p/.warp/tab_configs"
    let plan = { (terminal: ArisTerminal) in Q.plan(terminal, title: "Aris · 버그", shell: "/bin/zsh", files: files, warpFolder: warpFolder, id: quietId) }
    check(plan(.terminal) == .document, "quiet: Terminal opens the script as a document: no Apple event leaves Aris, so macOS has nothing to ask")
    check(plan(.iTerm) == .script("tell application id \"com.googlecode.iterm2\"\n    set newWindow to (create window with default profile)\n    tell current session of newWindow to write text \"'\(files.script)' || exit\"\nend tell"),
          "quiet: iTerm2's script, word for word, with no activate")
    let run = ["/bin/zsh", "-l", "-i", "-c", "exec '\(files.script)'"]
    check(plan(.ghostty) == .arguments(["--window-save-state=never", "-e"] + run) && plan(.kitty) == .arguments(run)
          && plan(.wezterm) == .arguments(["start", "--always-new-process", "--"] + run) && plan(.alacritty) == .arguments(["-e"] + run),
          "quiet: Ghostty, kitty, WezTerm and Alacritty start the account's login shell, which hands over to the script")
    let config = "name = \"Aris · 버그\"\ntitle = \"Aris · 버그\"\n\n[[panes]]\nid = \"main\"\ntype = \"terminal\"\ncommands = [\"'\(files.script)' || exit\"]\n"
    check(plan(.warp) == .link("warp://tab_config/aris_teammate_0a1b2c3d4e5f60718293a4b5c6d7e8f9?new_window=true",
                               path: warpFolder + "/aris_teammate_0a1b2c3d4e5f60718293a4b5c6d7e8f9.toml", contents: config),
          "quiet: Warp's Tab Config, word for word: the tab is named and its one pane runs the line")
    check(!config.contains("[params") && ArisWarpLaunch.canRun(Q.line(files)), "quiet: nothing in Warp's Tab Config is a blank to fill in")
    for terminal in ArisTerminal.allCases {
        check(!"\(plan(terminal))".contains("activate"), "quiet: \(terminal.title) is never told to come forward")
    }
}

private func teamQuietWindowTests() {
    typealias Q = ArisQuietLaunch
    check(Q.newWindow(before: [1289, 1290], after: [1290, 17279, 1289]) == 17279, "quiet: the teammate's window is the one that was not there before, not the terminal's front window (his own)")
    check(Q.newWindow(before: [1289, 1290], after: [1290, 1289]) == nil && Q.newWindow(before: [], after: []) == nil, "quiet: with no new window yet, none is named")
    check(Q.newWindow(before: [], after: [17116, 17114]) == 17116, "quiet: a terminal that just started has only new windows: the front one")
    func entry(_ number: Int, pid: Int, on: Bool, layer: Int = 0, w: Int = 900) -> [String: Any] {
        [kCGWindowNumber as String: number, kCGWindowOwnerPID as String: Int32(pid), kCGWindowLayer as String: layer, kCGWindowIsOnscreen as String: on,
         kCGWindowBounds as String: ["X": 0, "Y": 0, "Width": w, "Height": 500] as [String: Any]]
    }
    let onScreen = [entry(5, pid: 9, on: true), entry(3, pid: 7, on: true), entry(4, pid: 7, on: true)]
    let all = [entry(4, pid: 7, on: true), entry(8, pid: 7, on: false), entry(3, pid: 7, on: true), entry(9, pid: 7, on: false, layer: 25), entry(6, pid: 7, on: false, w: 20), entry(5, pid: 9, on: true)]
    check(ArisWindowLocator.windows(onScreen: onScreen, all: all, pid: 7) == [3, 4, 8],
          "quiet: a terminal's windows are read front to back, then the ones out of sight (minimised), without helpers and other apps' windows")
    check(Q.isLooking(frontPid: 7, topWindow: 17231, terminalPid: 7, window: 17231, sinceOpen: 10), "quiet: the window in front of everything, in the front app, is one he is looking at")
    check(!Q.isLooking(frontPid: 7, topWindow: 17114, terminalPid: 7, window: 17231, sinceOpen: 10) && !Q.isLooking(frontPid: 3, topWindow: 17231, terminalPid: 7, window: 17231, sinceOpen: 10)
          && !Q.isLooking(frontPid: 7, topWindow: nil, terminalPid: 7, window: 17231, sinceOpen: 10) && !Q.isLooking(frontPid: 7, topWindow: 5, terminalPid: 7, window: nil, sinceOpen: 10),
          "quiet: another window of the terminal, another app in front, or a window still in the Dock is not a look")
    check(!Q.isLooking(frontPid: 7, topWindow: 17231, terminalPid: 7, window: 17231, sinceOpen: 1), "quiet: the launch's own first seconds never count as his look")
    // Recorded on the test Mac: the built-in display below, an external one above and to the right.
    let builtIn = CGRect(x: 0, y: 0, width: 1800, height: 1169), external = CGRect(x: 1512, y: -1440, width: 2560, height: 1440)
    let aside = CGRect(x: 0, y: 39, width: 1800, height: 1063), warpNew = CGRect(x: 1742, y: -1410, width: 1786, height: 1410), terminalNew = CGRect(x: 217, y: 167, width: 914, height: 506)
    check(Q.otherDisplay(window: terminalNew, front: aside, displays: [builtIn, external]) == external, "quiet: a window that can't be minimised goes to the display his front window is not on")
    check(Q.otherDisplay(window: warpNew, front: aside, displays: [builtIn, external]) == nil, "quiet: a window already on the other display is not moved")
    check(Q.otherDisplay(window: terminalNew, front: aside, displays: [builtIn]) == nil && Q.otherDisplay(window: terminalNew, front: nil, displays: [builtIn, external]) == nil
          && Q.otherDisplay(window: terminalNew, front: aside, displays: []) == nil, "quiet: with one display, or no front window known, nothing is moved")
    check(Q.placeWords(.docked, terminal: .warp, english: false) == "Claude Code 작업 중 · Warp 창은 Dock에 접어 뒀어요" && Q.placeWords(.otherDisplay, terminal: .warp, english: false) == "Claude Code 작업 중 · Warp 창은 다른 화면에 뒀어요"
          && Q.placeWords(.behind, terminal: .warp, english: false) == "Claude Code 작업 중 · Warp 창은 다른 창 뒤에 있어요" && Q.placeWords(.docked, terminal: .terminal, english: true) == "Claude Code at work · its Terminal window is in the Dock",
          "quiet: the job's row says where the teammate's window is")
}

private func teamQuietEndTests() {
    typealias Q = ArisQuietLaunch
    check(Q.end(seen: false, sessionFound: true, terminal: .terminal, window: .own(7)) == .closed && Q.end(seen: false, sessionFound: true, terminal: .ghostty, window: .own(7)) == .closed,
          "quiet: a finished job's window that he never looked at is closed, not left lying around")
    check(Q.end(seen: true, sessionFound: true, terminal: .terminal, window: .own(7)) == .left && Q.end(seen: true, sessionFound: true, terminal: .warp, window: .own(7)) == .left,
          "quiet: a window he looked at is his: nothing of it is ended or closed")
    check(Q.end(seen: false, sessionFound: false, terminal: .terminal, window: .own(7)) == .left, "quiet: when the session can't be found, nothing is signalled")
    check(Q.end(seen: false, sessionFound: true, terminal: .warp, window: .own(7)) == .ended, "quiet: Warp's session is ended; its window stays unless Aris may press its close button")
    check(Q.mayPressClose(seen: false, scriptGone: true, window: 17279, titleMatched: true) && !Q.mayPressClose(seen: true, scriptGone: true, window: 17279, titleMatched: true)
          && !Q.mayPressClose(seen: false, scriptGone: false, window: 17279, titleMatched: true) && !Q.mayPressClose(seen: false, scriptGone: true, window: nil, titleMatched: true)
          && !Q.mayPressClose(seen: false, scriptGone: true, window: 17279, titleMatched: false),
          "quiet: Warp's close button is pressed only for a known window he never looked at whose script has left")
    check(Q.endWords(.closed, korean: true) == nil && Q.endWords(.left, korean: true) == "터미널은 그대로 뒀어요." && Q.endWords(.ended, korean: true) == "터미널 창은 닫지 못해서 그대로 있어요."
          && Q.endWords(.left, korean: false) == "I left the terminal as it is." && Q.endWords(.ended, korean: false) == "I couldn't close the terminal window, so it is still there.",
          "quiet: a window that is still there is said in the job's last line; one that closed is not mentioned")
    check(Q.End(rawValue: "closed") == .closed && Q.End(rawValue: "ended") == .ended && Q.End(rawValue: "left") == .left && Q.End(rawValue: "") == nil, "quiet: the agent's word for the window is read back by the app")
    check(Q.automationLine(.iTerm, english: false) == "macOS가 Aris의 iTerm2 제어를 물어볼 수 있어요 · 허용을 누르면 팀원이 시작해요"
          && Q.automationLine(.iTerm, english: true).contains("control iTerm2"), "quiet: macOS's question about controlling a terminal is announced in the job's row first")
}

private func teamQuietWiringTests() {
    let opener = teamQuietSource("ArisAgent/ArisQuietOpener.swift"), desk = teamQuietSource("ArisAgent/ArisTeammateDesk.swift")
    let tuck = teamQuietSource("ArisAgent/ArisQuietTuck.swift"), main = teamQuietSource("ArisAgent/main.swift")
    let controller = teamQuietSource("Aris/private/Aris/ArisController+Teammate.swift")
    check(opener.contains("waitForTypingGap()") && opener.contains(".hidSystemState") && !opener.contains(".combinedSessionState"),
          "quiet wiring: the typing gap is read from the hardware clock, which Aris's own events never reset")
    check(opener.contains("configuration.activates = false") && opener.contains("activates: false") && !opener.contains("activates = true") && !opener.contains("activate(ignoringOtherApps"),
          "quiet wiring: every terminal is opened without activation")
    check(opener.contains("ArisQuietLaunch.front(before:") && opener.contains("NSRunningApplication(processIdentifier: before)?.activate(options: [])"),
          "quiet wiring: the front goes back to the app he was in, by the rule")
    check(opener.contains("throw NeverStarted(terminal: terminal)") && opener.contains("unusable.insert(failed.terminal)"),
          "quiet wiring: a terminal that never ran the script is passed over, at once and for the rest of this run of the helper")
    check(opener.contains("AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, false)") && opener.contains("say(ArisQuietLaunch.automationLine(terminal, english: english))"),
          "quiet wiring: whether macOS would ask is found out without asking, and the row says so first")
    check(opener.contains("kill(session, SIGTERM)") && !opener.contains("SIGKILL") && !opener.contains("killpg"), "quiet wiring: at the job's end only that job's Claude Code is asked to end")
    let tuckCode = tuck.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
    check(tuckCode.contains("guard AXIsProcessTrusted()") && !tuckCode.contains("AXIsProcessTrustedWithOptions") && tuckCode.contains("_AXUIElementGetWindow(element, &id) == .success && Int(id) == window"),
          "quiet wiring: Accessibility is used only when Aris already has it, never asked for, and only on the window with the launch's own number")
    check(!tuckCode.contains("kAXRaiseAction") && !tuckCode.contains("kAXMainAttribute") && !tuckCode.contains("kAXFocused") && !tuckCode.contains("activate(") && tuckCode.contains("AXUIElementSetMessagingTimeout(app, callTimeout)"),
          "quiet wiring: putting a window away never raises, focuses or activates anything, and every call is time-boxed")
    check(tuckCode.contains("wait({ flag(element, kAXMinimizedAttribute) == true })") && tuckCode.contains("return wait { self.element(pid: pid, window: window) == nil }"),
          "quiet wiring: the Dock is believed only when the window reads as minimised, and closed only when it is gone")
    check(opener.contains("ArisQuietTuck.close(pid: pid, window: stray, title: title)") && opener.contains("ArisQuietLaunch.mayPressClose(seen: seen, scriptGone: kill(script, 0) != 0, window: opened.windowNumber, titleMatched: opened.titleMatched)"),
          "quiet wiring: a Warp window whose command never started is closed, and a finished one only by the rule")
    check(!teamQuietSource("ArisAgent/ArisTerminalOpener.swift").contains("ArisWindowLocator.frontWindow(pid: pid)") && !controller.contains("ArisWindowLocator.frontWindow(pid: launch.pid)"),
          "quiet wiring: neither the helper nor the app ever takes the terminal's front window (his own) for the teammate's")
    check(desk.contains("ArisTeammateLauncher.launchQuietly(command: command, title: title, wish: wish, english: english)") && !desk.contains("ArisTeammateLauncher.launch(command:"),
          "quiet wiring: the desk opens a teammate's window the quiet way")
    check(desk.contains("ArisQuietSession.isLooking(opened, since: state.openedAt)") && desk.contains("ArisQuietSession.end(opened, seen: seen, claude: claude)")
          && desk.contains("?? ArisQuietLaunch.placeWords(window.place, terminal: window.terminal, english: state.english)"),
          "quiet wiring: the desk notes his look once a second and settles the window when the job is over")
    check(main.contains(#"if object["done"] as? Bool == true {"#) && main.contains("ArisTeammateDesk.shared.finished(job: job) { end in"),
          "quiet wiring: the app's word that the session finished reaches the desk (a dropped stream alone closes nothing)")
    check(controller.contains("ArisAgentClient.teammateFinished(job: job.id)") && controller.contains("title: job.title"),
          "quiet wiring: the app names the window after the job and says when its session finished")
    check(teamQuietSource("ArisAgent/ArisTeamExtrasRoute+Live.swift").contains("ArisTeammateLauncher.launch(command: command)"),
          "quiet wiring: an AI's login, which he asked to type into, still opens in front as before")
    check(ArisTeammateSilence.nudgeAfter == 45 && ArisTeammateSilence.nudgeStep(korean: true).contains("‘Aris’ 터미널 창"),
          "quiet wiring: a session not heard after 45 s (Claude Code asking about the folder, out of sight) says which window to look for")
}

// MARK: - Security review 7 (M1, M2, M3, L4, L5)

/// Runs `script` with /bin/sh in a throwaway folder; its exit status.
private func quietRun(_ script: String) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = [script]
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return -1 }
    process.waitUntilExit()
    return process.terminationStatus
}

private func teamQuietReview7Tests() {
    typealias Q = ArisQuietLaunch
    let home = "/Users/me", tools = "/Users/me/.config/aris/aris-tools"
    // M1: where the launch files are, and that an AI cannot write or read there without a card.
    let launch = ArisTeammateLauncher.launchFolder(home: home).path
    check(launch == "/Users/me/.config/aris/aris/launch" && launch != ArisRiskPolicy.workFolder(home: home),
          "review-7 M1: a launch's files are in their own folder beside the work folder, not in it")
    let target = launch + "/cc-0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9.command"
    for command in ["cp /Users/me/.config/aris/aris/work/x.sh \(target)", "mv /Users/me/.config/aris/aris/work/x.sh \(target)", "touch \(launch)/cc-x.pid",
                    "mkdir \(launch)/x", "cp \(target) /Users/me/.config/aris/aris/work/copy", "cat \(launch)/cc-x.txt", "ls \(launch)"] {
        check(ArisRiskPolicy.risk(of: .shell(command), tools: tools, home: home) != .auto, "review-7 M1: `\(command.prefix(40))…` into or out of the launch folder never runs without asking")
    }
    check(ArisRiskPolicy.risk(of: .shell("cp /Users/me/.config/aris/aris/work/a /Users/me/.config/aris/aris/work/b"), tools: tools, home: home) == .auto,
          "review-7 M1: the work folder itself is as before (the launch files are simply no longer in it)")
    check(ArisRiskPolicy.files([target], home: home) != .auto && ArisRiskPolicy.files([launch + "/cc-x.txt"], home: home) != .auto
          && ArisRiskPolicy.risk(of: .fileChange([target]), tools: tools, home: home) != .auto, "review-7 M1: a file change in the launch folder is never made on its own")
    let desk = teamQuietSource("ArisAgent/ArisTeammateDesk.swift"), opener = teamQuietSource("ArisAgent/ArisQuietOpener.swift"), agent = teamQuietSource("ArisAgent/main.swift")
    check(desk.contains("in: ArisTeammateLauncher.launchFolder(home: home)") && opener.contains("folder = ArisTeammateLauncher.launchFolder(home: home)")
          && teamQuietSource("ArisAgent/ArisTerminalOpener.swift").contains("let folder = ArisTeammateLauncher.launchFolder(home: home)")
          && !desk.contains("workFolder") && !opener.contains("workFolder"), "review-7 M1: the prompt, the script and its marks all go to the launch folder")
    check(agent.contains("ArisTeammateLauncher.sweep(ArisTeammateLauncher.launchFolder(home:"), "review-7 M1: the launch folder is swept like the work folder was")
    // The script itself, run for real in a throwaway folder (a terminal that scripts nothing; the command is a stand-in).
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-quiet-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: folder) }
    func files(_ id: UUID = UUID()) -> ArisQuietFiles { Q.files(folder: folder.path, id: id) }
    func write(_ f: ArisQuietFiles, command: String) {
        try? Q.script(command: command, title: "Aris · x", terminal: .kitty, shell: "/usr/bin/true", files: f).write(toFile: f.script, atomically: true, encoding: .utf8)
    }
    func read(_ path: String) -> String? { try? String(contentsOfFile: path, encoding: .utf8) }
    let clean = files(), out = folder.path + "/out-clean"
    write(clean, command: "cat '\(clean.pid)' > '\(out)'")
    let cleanStatus = quietRun(clean.script)
    check(cleanStatus == 0 && Int32(read(out)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").map { $0 > 1 } == true,
          "review-7 M1: the script writes its own process id as a new file before the command runs (status \(cleanStatus))")
    check(!FileManager.default.fileExists(atPath: clean.script) && !FileManager.default.fileExists(atPath: clean.pid), "review-7 M1: it deletes itself, and its mark when it ends")
    let planted = files(), plantedOut = folder.path + "/out-planted"
    try? "1\n".write(toFile: planted.pid, atomically: true, encoding: .utf8)
    write(planted, command: "echo ran > '\(plantedOut)'")
    let plantedStatus = quietRun(planted.script)
    check(plantedStatus == 1 && read(planted.pid) == "1\n" && !FileManager.default.fileExists(atPath: plantedOut),
          "review-7 M1: a pid mark that is already there is never written through, and the command does not run (status \(plantedStatus))")
    let closing = files()
    write(closing, command: "true")
    FileManager.default.createFile(atPath: closing.close, contents: Data())
    check(quietRun(closing.script) == 75 && !FileManager.default.fileExists(atPath: closing.close) && !FileManager.default.fileExists(atPath: closing.pid),
          "review-7 M1: asked to close up, the script removes its marks and says so to the shell that ran it")
    // A mark from before the launch is never read; a pid that is not the script Aris started is never believed.
    check(Q.markIsFresh(modified: 1000, launched: 1000.5) && !Q.markIsFresh(modified: 990, launched: 1000), "review-7 M1: a mark older than the launch was planted")
    let mark = files()
    try? "\(ProcessInfo.processInfo.processIdentifier)\n".write(toFile: mark.pid, atomically: true, encoding: .utf8)
    chmod(mark.pid, 0o600)
    let parent = getppid()
    check(ArisQuietSession.text(in: mark.pid, launchedAt: Date().addingTimeInterval(-60)) != nil && ArisQuietSession.text(in: mark.pid, launchedAt: Date().addingTimeInterval(60)) == nil,
          "review-7 M1: a mark is read only when it was written after the launch began")
    check(ArisQuietSession.scriptPid(mark, launchedAt: .distantPast, terminal: parent, bundle: nil) == ProcessInfo.processInfo.processIdentifier,
          "review-7 M1: a process that began after the launch, under the launch's terminal, is the script")
    check(ArisQuietSession.scriptPid(mark, launchedAt: Date().addingTimeInterval(-0.5), terminal: parent, bundle: nil) == nil,
          "review-7 M1: a forged pid naming a process that was already running before the launch is not believed (so never signalled)")
    check(ArisQuietSession.scriptPid(mark, launchedAt: .distantPast, terminal: 99_999_999, bundle: "/Applications/Nope.app") == nil,
          "review-7 M1: a forged pid naming a process outside the launch's terminal is not believed")
    let chain: [(pid: Int32, path: String)] = [(700, "/bin/zsh"), (650, "/Applications/Warp.app/Contents/MacOS/stable"), (1, "/sbin/launchd")]
    check(Q.isOwnScript(started: 100, launched: 99.5, ancestors: chain, terminal: 650, bundle: nil) && Q.isOwnScript(started: 100, launched: 99.5, ancestors: chain, terminal: 5, bundle: "/Applications/Warp.app")
          && !Q.isOwnScript(started: 90, launched: 99.5, ancestors: chain, terminal: 650, bundle: nil) && !Q.isOwnScript(started: 100, launched: 99.5, ancestors: chain, terminal: 5, bundle: "/Applications/War")
          && !Q.isOwnScript(started: 100, launched: 99.5, ancestors: chain, terminal: 5, bundle: ""), "review-7 M1: the script is known by when it began and whose shell it runs under")
    check(opener.contains("guard ![files.pid, files.window, files.close].contains(where: { FileManager.default.fileExists(atPath: $0) })") && opener.contains("scriptPid(opened).flatMap { self.claude(under: $0, claude: claude) }"),
          "review-7 M1: a launch whose marks are already there stops, and only a verified script's Claude Code is ever signalled")
    // M2: Terminal opened it as a tab of his window.
    let terminal = Q.script(command: "true", title: "Aris · x", terminal: .terminal, shell: "/bin/zsh", files: files())
    let find = terminal.components(separatedBy: "\n").first { $0.hasPrefix("ARIS_WINDOW=") } ?? "", close = terminal.components(separatedBy: "\n").first { $0.contains("close w") } ?? ""
    let order = ["set n to id of w", "if (count of tabs of w) is not 1 then return \"tab \" & n", "set custom title of selected tab of w", "set miniaturized of window id n to true"].map { find.range(of: $0)?.lowerBound }
    check(!order.contains(nil) && order.compactMap { $0 } == order.compactMap { $0 }.sorted(), "review-7 M2: in a window with more than one tab the script returns before it names or minimises anything")
    check(close.contains("case \"$ARIS_WINDOW\" in ''|*[!0-9]*) ;;") && close.contains("and (count of tabs of w) is 1 then") && !terminal.contains("close (every window"),
          "review-7 M2: only a plain window number is closed, and only while that window still has exactly one tab")
    check(Q.window(mark: "17231\n") == .own(17231) && Q.window(mark: "tab 16781\n") == .tab(host: 16781), "review-7 M2: the script's word for its window: its own, or a tab of his")
    for bad in [nil, "", "\n", "0", "-4", "tab", "tab x", "17231 9", "tab 1 2", "window 5", "1e3"] as [String?] {
        check(Q.window(mark: bad) == .unknown, "review-7 M2: an unreadable window mark (\(bad ?? "none")) names no window")
    }
    check(Q.Window.tab(host: 16781).number == nil && Q.Window.tab(host: 16781).looked == 16781 && Q.Window.own(5).number == 5 && Q.Window.unknown.looked == nil,
          "review-7 M2: his window that holds the tab is watched for his look, and never put away, closed or perched on")
    check(Q.end(seen: false, sessionFound: true, terminal: .terminal, window: .tab(host: 16781)) == .tab && Q.end(seen: true, sessionFound: true, terminal: .terminal, window: .tab(host: 16781)) == .left
          && Q.endWords(.tab, korean: true) == "터미널 탭은 그대로 뒀어요." && Q.endWords(.tab, korean: false) == "I left the terminal tab as it is." && Q.End(rawValue: "tab") == .tab,
          "review-7 M2: a tab's session is ended by its own shell leaving; the tab and his window stay, and the last line says so")
    check(Q.placeWords(.tab, terminal: .terminal, english: false) == "Claude Code 작업 중 · 쓰시던 Terminal 창의 탭으로 열렸어요", "review-7 M2: the row says the teammate is a tab of his window")
    // M3: whose window, over recorded window lists.
    check(Q.ownWindow(before: [1289, 1290], after: [1290, 17279, 1289], knownBefore: true) == .own(17279), "review-7 M3: one new window of a terminal that was running is the launch's (recorded: Warp, launch 5)")
    check(Q.ownWindow(before: [], after: [17116, 17114], knownBefore: false) == .unknown && Q.ownWindow(before: [], after: [17116], knownBefore: false) == .unknown,
          "review-7 M3: a terminal that was not running restores his windows: none is named (recorded: Terminal's cold start, launch 3)")
    check(Q.ownWindow(before: [1289, 1290], after: [19130, 19108, 1290, 1289], knownBefore: true) == .unknown, "review-7 M3: two new windows mean one may be his: none is named")
    check(Q.ownWindow(before: [1289, 1290], after: [1290, 1289], knownBefore: true) == .unknown && Q.ownWindow(before: [], after: [77], knownBefore: true) == .own(77),
          "review-7 M3: no new window names none; an instance started for this launch alone has only its own")
    check(Q.titleMatches(read: "Aris · 버그 고치기", expected: "Aris · 버그 고치기") && Q.titleMatches(read: "Aris · 버그 고치기 — zsh", expected: "Aris · 버그 고치기")
          && !Q.titleMatches(read: "~/proj — zsh", expected: "Aris · 버그 고치기") && !Q.titleMatches(read: nil, expected: "Aris · x") && !Q.titleMatches(read: "anything", expected: ""),
          "review-7 M3: a window is the launch's only when the title the launch gave it is read back from it")
    let tuck = teamQuietSource("ArisAgent/ArisQuietTuck.swift")
    check(tuck.contains("ArisQuietLaunch.titleMatches(read: text(element, kAXTitleAttribute), expected: title) else { return (.behind, false) }")
          && tuck.contains("if let title, !ArisQuietLaunch.titleMatches(read: text(element, kAXTitleAttribute), expected: title) { return false }"),
          "review-7 M3: nothing is minimised, moved or closed through Accessibility before the title matched")
    check(opener.contains("ArisQuietLaunch.ownWindow(before: before, after: ArisWindowLocator.windows(pid: pid), knownBefore: knownBefore).number {") && !opener.contains("ArisQuietLaunch.newWindow("),
          "review-7 M3: the window that is closed when the command never started is found by the same strict rule")
    // L4: a window Aris does not know may be the one he is in.
    check(Q.end(seen: false, sessionFound: true, terminal: .warp, window: .unknown) == .left && Q.end(seen: false, sessionFound: true, terminal: .terminal, window: .unknown) == .left,
          "review-7 L4: with the window unknown, the session is never ended and nothing is closed")
    check(!Q.isLooking(frontPid: 7, topWindow: 9, terminalPid: 7, window: nil, sinceOpen: 30) && opener.contains("window: opened.window.looked"),
          "review-7 L4: an unknown window can't be seen being looked at, which is why its end is 'left'")
    // L5: the approved command never runs twice.
    let removal = opener.range(of: "ArisTeammateLauncher.remove(URL(fileURLWithPath: files.script))\n            started = waitFor(lateStartWait, ran)")
    let fallback = opener.range(of: "throw NeverStarted(terminal: terminal)")
    check(removal != nil && fallback != nil && removal!.lowerBound < fallback!.lowerBound && ArisQuietOpener.lateStartWait >= 0.5,
          "review-7 L5: the script is taken away first, then the mark is looked for once more, and only then is another terminal opened")
}
