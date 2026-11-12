//
//  ArisQuietLaunch.swift
//  Aris (also built into aris-agent)
//
//  A Claude Code teammate starts without disturbing the user ("제대로 구현했으면 내가 신경 쓰이지 않게 동작하겠지"): its
//  window opens without coming to the front, the keyboard stays where he is typing, and the window ends up out of the
//  way. Measured on macOS 27.2.1 (November 2026), with Aside or Warp in front:
//  - Terminal: the launch script is opened as a document of Terminal, not activated. No Apple event leaves Aris, so
//    macOS never asks "Aris wants to control Terminal". The script, running inside Terminal, asks Terminal to name
//    and minimise its own window (an app scripting itself is not asked about either): the front app never changed,
//    and the window was in the Dock about a second after it appeared. When Aris ends the session the script closes
//    its own window.
//  - Warp: a Tab Config opened by its link, not activated. Warp has no scripting and cannot be minimised or closed
//    from outside without Accessibility; if it comes forward anyway, the front goes straight back to the app he was in.
//  - iTerm2: the same AppleScript as before without `activate`. Ghostty, kitty, WezTerm, Alacritty: a new instance,
//    not activated.
//  Never in the middle of his typing: the start waits for a gap of 0.4 s, at most 3 s. Never in the terminal he is
//  in right now: its new window would take his keys inside that app, so the next terminal is used and the job's
//  first line says so.
//  Foundation only: every rule, script and argument list here is tested.
//

import Foundation

/// The files of one launch, all in Aris's launch folder (~/.config/aris/aris/launch, 0700: a place no AI writes or
/// reads without a card, unlike the work folder beside it) under the launch's id.
struct ArisQuietFiles: Equatable {
    /// The launch script (0700): it deletes itself when it starts.
    let script: String
    /// The script's own process id, written when it starts: proof that the terminal really ran it.
    let pid: String
    /// Terminal only: the number of the window the script found itself in.
    let window: String
    /// Written by Aris when the job is over and the window was never looked at: the script then closes up.
    let close: String
}

/// How one terminal is asked to open the teammate's window without coming forward.
enum ArisQuietPlan: Equatable {
    /// Terminal: the launch script is opened as a document of the app.
    case document
    /// iTerm2: AppleScript on osascript's stdin, with no `activate`.
    case script(String)
    /// A new instance of the app with these arguments.
    case arguments([String])
    /// Warp: a Tab Config written to `path`, then this link opened.
    case link(String, path: String, contents: String)
}

/// Which terminal a quiet launch uses, and what was passed over for it.
struct ArisQuietPick: Equatable {
    let terminal: ArisTerminal
    /// A terminal that came first but can't be handed a command.
    var passedOver: ArisTerminal?
    /// The terminal that came first but is the app the user is in right now.
    var inFront: ArisTerminal?
}

enum ArisQuietLaunch {
    // MARK: - When to start

    /// The launch starts in a gap of his typing at least this long…
    static let typingGap: TimeInterval = 0.4
    /// …and waits for one no longer than this.
    static let longestWait: TimeInterval = 3
    /// How often the gap is looked for.
    static let gapLook: TimeInterval = 0.05

    /// `sinceKey`: seconds since his last real key press (the hardware clock, which Aris's own events never touch).
    static func mayStart(sinceKey: TimeInterval, waited: TimeInterval) -> Bool {
        sinceKey >= typingGap || waited >= longestWait
    }

    // MARK: - The front app

    /// How long the front app is watched after the window was asked for (a terminal raises itself a moment later).
    static let frontWatch: TimeInterval = 3
    /// How often: twice a frame.
    static let frontLook: TimeInterval = 0.008

    enum Front: Equatable {
        case leave, giveBack
    }

    /// Whether the app the user was in gets the front back. Only when the teammate's terminal took it, they was somewhere
    /// else before, and he has not clicked or pressed a key since the launch began (then he chose where he is).
    static func front(before: Int32?, now: Int32?, terminal: Int32?, sinceTouch: TimeInterval, sinceOpen: TimeInterval) -> Front {
        guard let before, let now, let terminal, now == terminal, before != terminal, before > 0 else { return .leave }
        return sinceTouch > sinceOpen ? .giveBack : .leave
    }

    // MARK: - Which terminal

    /// ArisTerminalChoice's order, without the terminals that did not run a command earlier (`unusable`) and, when
    /// another one can be used, without the one the user is in right now (`front`).
    static func pick(_ facts: ArisTerminalChoice.Facts, command: String, front: ArisTerminal?, unusable: Set<ArisTerminal>) -> ArisQuietPick {
        var passedOver: ArisTerminal?
        var usable: [ArisTerminal] = []
        for terminal in ArisTerminalChoice.order(facts) {
            if unusable.contains(terminal) || (terminal == .warp && !(facts.warpReady && ArisWarpLaunch.canRun(command))) {
                passedOver = passedOver ?? terminal
                continue
            }
            usable.append(terminal)
        }
        guard let first = usable.first else { return ArisQuietPick(terminal: .terminal, passedOver: passedOver) }
        guard first == front, let other = usable.dropFirst().first else { return ArisQuietPick(terminal: first, passedOver: passedOver) }
        return ArisQuietPick(terminal: other, passedOver: passedOver, inFront: first)
    }

    /// What the job's row says once the window is open somewhere else than in the terminal that came first.
    static func note(_ pick: ArisQuietPick, english: Bool) -> String? {
        if let busy = pick.inFront {
            return english ? "Claude Code at work · you are in \(busy.title), so it opened in \(pick.terminal.title)"
                : "Claude Code 작업 중 · \(busy.title)를 쓰고 계셔서 \(pick.terminal.title)에서 열었어요"
        }
        return pick.passedOver.map { ArisTerminalWords.passedOver($0, openedIn: pick.terminal, english: english) }
    }

    // MARK: - The window's name

    static let titleLimit = 40

    /// "Aris · <job>": letters, digits, spaces and a few plain marks only, so the same text is safe in a shell
    /// string, an AppleScript string and a TOML string.
    static func title(_ job: String?) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_.,()"))
        let kept = String(String.UnicodeScalarView((job ?? "").unicodeScalars.filter { allowed.contains($0) }))
        let words = kept.split(separator: " ").joined(separator: " ")
        let short = String(words.prefix(titleLimit)).trimmingCharacters(in: .whitespaces)
        return "Aris · " + (short.isEmpty ? "Claude Code" : short)
    }

    // MARK: - The launch script

    static func files(folder: String, id: UUID) -> ArisQuietFiles {
        let stem = folder + "/cc-" + id.uuidString.lowercased()
        return ArisQuietFiles(script: stem + ".command", pid: stem + ".pid", window: stem + ".window", close: stem + ".close")
    }

    /// The names of a launch's files, for the daily sweep of the launch folder.
    static let filePattern = #"^cc-[0-9a-f-]{36}\.(command|pid|window|close)$"#

    /// What the script exits with when Aris asked it to close up: the line that called it then leaves its shell.
    static let closeStatus = 75

    /// The script stays as a shell in its window when Claude Code ends by itself (as before); in Warp and iTerm2
    /// the shell that called it is already there.
    static func keepsShell(_ terminal: ArisTerminal) -> Bool { terminal != .warp && terminal != .iTerm }

    /// One teammate's session, as a POSIX script every terminal runs the same way. It deletes itself, names its
    /// window, writes its process id (so Aris knows the terminal ran it and which session is this job's), and in
    /// Terminal asks Terminal to minimise the window it is in (the window's number is read first and the window
    /// then spoken to by that number: "window 2" is another window once one has gone to the Dock; on the test Mac
    /// the number came back as a neighbour's). Then the command, as it was typed before. Afterwards:
    /// when Aris left the close file, it closes up (in Terminal, its own window); otherwise a shell stays.
    /// `title`: ArisQuietLaunch.title's. `command`: ArisClaudeLaunch.command's.
    static func script(command: String, title: String, terminal: ArisTerminal, shell: String, files: ArisQuietFiles) -> String {
        let q = ArisClaudeLaunch.shellQuoted
        // set -C: a mark is only ever a new file. A name that is already there was planted: the script stops before
        // the command, and nothing is written through it (security review 7, M1).
        var lines = ["#!/bin/sh", "umask 077", "set -C", "rm -f -- \(q(files.script))", "printf '\\033]0;%s\\007' \(q(title))",
                     "echo $$ > \(q(files.pid)) || exit 1"]
        if terminal == .terminal {
            // Only a window of its own (exactly one tab) is named and minimised. Opened as a tab of the user's window
            // (his tabbing setting, or his Terminal in full screen), the script touches nothing and says "tab <window>".
            lines += ["ARIS_TTY=$(tty)",
                      "ARIS_WINDOW=$(/usr/bin/osascript -e 'tell application id \"com.apple.Terminal\"' -e 'repeat with w in windows' "
                          + "-e 'if (tty of selected tab of w) is \"'\"$ARIS_TTY\"'\" then' -e 'set n to id of w' "
                          + "-e 'if (count of tabs of w) is not 1 then return \"tab \" & n' "
                          + "-e 'set custom title of selected tab of w to \"\(title)\"' -e 'set miniaturized of window id n to true' -e 'return n' "
                          + "-e 'end if' -e 'end repeat' -e 'end tell' 2>/dev/null)",
                      "echo \"$ARIS_WINDOW\" > \(q(files.window)) || exit 1"]
        }
        // Claude Code would rename the window after the conversation; it keeps the name that says whose it is.
        lines += ["export CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1", command, "if [ -e \(q(files.close)) ]; then",
                  "    rm -f -- \(q(files.close)) \(q(files.pid)) \(q(files.window))"]
        if terminal == .terminal {
            // Only a plain window number is ever closed (never "tab …"), only while that window still has one tab,
            // and after this script and its shell are gone, so Terminal has nothing running to ask about.
            lines.append("    case \"$ARIS_WINDOW\" in ''|*[!0-9]*) ;; *) ( sleep 1; /usr/bin/osascript -e 'tell application id \"com.apple.Terminal\"' "
                + "-e 'repeat with w in windows' -e 'if (id of w) is '\"$ARIS_WINDOW\"' and (count of tabs of w) is 1 then' -e 'close w' -e 'return' "
                + "-e 'end if' -e 'end repeat' -e 'end tell' ) > /dev/null 2>&1 < /dev/null & ;; esac")
        }
        lines += ["    exit \(closeStatus)", "fi", "rm -f -- \(q(files.pid)) \(q(files.window))",
                  keepsShell(terminal) ? "exec \(q(shell)) -l -i" : "exit 0"]
        return lines.joined(separator: "\n") + "\n"
    }

    /// The line a terminal's own shell is given: the script, and when it says "close up", the shell leaves too.
    static func line(_ files: ArisQuietFiles) -> String { "\(ArisClaudeLaunch.shellQuoted(files.script)) || exit" }

    /// Warp's Tab Config: the tab is named, and its one pane runs the line. No `[params]`: nothing is asked.
    static func tabConfig(title: String, files: ArisQuietFiles) -> String {
        """
        name = \(ArisWarpLaunch.tomlString(title))
        title = \(ArisWarpLaunch.tomlString(title))

        [[panes]]
        id = "main"
        type = "terminal"
        commands = [\(ArisWarpLaunch.tomlString(line(files)))]

        """
    }

    /// How `terminal` is asked for the window. `shell`: ArisTerminalLaunch.shell's; `warpFolder`: Warp's tab_configs.
    static func plan(_ terminal: ArisTerminal, title: String, shell: String, files: ArisQuietFiles, warpFolder: String, id: UUID) -> ArisQuietPlan {
        // The account's shell, as a login and interactive one (its PATH is the one the user's own windows have), hands
        // over to the script at once.
        let run = [shell, "-l", "-i", "-c", "exec " + ArisClaudeLaunch.shellQuoted(files.script)]
        switch terminal {
        case .terminal: return .document
        case .iTerm:
            return .script("""
                tell application id "\(ArisTerminal.iTerm.bundleId)"
                    set newWindow to (create window with default profile)
                    tell current session of newWindow to write text \(ArisClaudeLaunch.appleScriptString(line(files)))
                end tell
                """)
        case .warp:
            let name = ArisWarpLaunch.configName(id)
            return .link(ArisWarpLaunch.link(name), path: warpFolder + "/" + name + ".toml", contents: tabConfig(title: title, files: files))
        case .ghostty: return .arguments(["--window-save-state=never", "-e"] + run)
        case .kitty: return .arguments(run)
        case .wezterm: return .arguments(["start", "--always-new-process", "--"] + run)
        case .alacritty: return .arguments(["-e"] + run)
        }
    }

    // MARK: - Whose window

    /// The teammate's window: the first of the terminal's windows now (`after`, front to back) that was not there
    /// before the launch. Never "the terminal's front window": that one is the user's own while the new one is opening.
    static func newWindow(before: Set<Int>, after: [Int]) -> Int? {
        after.first { !before.contains($0) }
    }

    /// What is known of a teammate's window.
    enum Window: Equatable {
        /// A window of its own, by its number.
        case own(Int)
        /// Terminal opened it as a tab of a window of the user's (`host`): that window is never minimised, named or closed.
        case tab(host: Int)
        /// Not known: it could be any window of the terminal.
        case unknown

        /// The window Aris may put away, close, or send the figure to.
        var number: Int? {
            if case .own(let number) = self { return number }
            return nil
        }

        /// The window whose being in front counts as his look (a tab's is the whole window it sits in).
        var looked: Int? {
            switch self {
            case .own(let number), .tab(let number): return number
            case .unknown: return nil
            }
        }
    }

    /// The teammate's own window in a terminal Aris does not script: named only when the terminal was running
    /// before the launch (`knownBefore`: one that starts cold restores the user's last windows, all of them "new"; a
    /// new instance started for this launch alone counts as known) and exactly one window is new since. Two new
    /// windows mean one may be his (he opened it meanwhile): then none is named (security review 7, M3).
    static func ownWindow(before: Set<Int>, after: [Int], knownBefore: Bool) -> Window {
        let new = after.filter { !before.contains($0) }
        guard knownBefore, new.count == 1 else { return .unknown }
        return .own(new[0])
    }

    /// What Terminal's script wrote about the window it found itself in: its number, "tab <number>" when it is a
    /// tab of a window with other tabs, or nothing readable.
    static func window(mark: String?) -> Window {
        let words = (mark ?? "").split(whereSeparator: { $0 == " " || $0.isNewline }).map(String.init)
        if words.count == 1, let number = Int(words[0]), number > 0 { return .own(number) }
        if words.count == 2, words[0] == "tab", let number = Int(words[1]), number > 0 { return .tab(host: number) }
        return .unknown
    }

    /// Whether the title read back from a window (through Accessibility) is the one this launch gave it. Without
    /// that the window is not Aris's to minimise or close.
    static func titleMatches(read: String?, expected: String) -> Bool {
        guard let read, !expected.isEmpty else { return false }
        return read.contains(expected)
    }

    // MARK: - Whose process

    /// How much a clock reading may lag the launch.
    static let clockSlack: TimeInterval = 1

    /// Whether a mark file was written by this launch: not older than the launch (one that was there before is
    /// someone else's and is never read).
    static func markIsFresh(modified: TimeInterval, launched: TimeInterval) -> Bool { modified >= launched - clockSlack }

    /// Whether the process named in the pid mark is the script Aris started: it began after the launch, and it runs
    /// under the terminal the launch opened (`terminal`: that app's process; `bundle`: its app folder, for a
    /// terminal whose shells hang off a helper of its own). Anything else is never signalled.
    static func isOwnScript(started: TimeInterval, launched: TimeInterval, ancestors: [(pid: Int32, path: String)], terminal: Int32, bundle: String?) -> Bool {
        guard started >= launched - clockSlack else { return false }
        let root = bundle.flatMap { $0.isEmpty ? nil : $0 + "/" }
        return ancestors.contains { above in above.pid == terminal || (root.map { above.path.hasPrefix($0) } ?? false) }
    }

    // MARK: - Where the window ended up

    enum Place: String, Equatable {
        /// Minimised into the Dock (Terminal by its own script, another terminal through Accessibility).
        case docked
        /// Moved to the display the user's front window is not on.
        case otherDisplay
        /// Where it opened: behind the app he is in.
        case behind
        /// Terminal opened it as a tab of a window of his.
        case tab
    }

    /// How far from a display's corner a moved window is put.
    static let displayInset: CGFloat = 40

    /// The display a window that could not be minimised is moved to: one that does not hold the user's front window.
    /// Nil with one display, with no front window known, or when the window is already off his display.
    /// Frames are window-server coordinates (y down). A window is on the display that holds its top-left corner.
    static func otherDisplay(window: CGRect, front: CGRect?, displays: [CGRect]) -> CGRect? {
        func home(_ frame: CGRect) -> CGRect? { displays.first { $0.contains(CGPoint(x: frame.minX + 1, y: frame.minY + 1)) } }
        guard displays.count > 1, let front, let his = home(front), home(window) == his else { return nil }
        return displays.first { $0 != his }
    }

    /// The job's row while it works: it says where the teammate's window is, so he knows something is running.
    static func placeWords(_ place: Place, terminal: ArisTerminal, english: Bool) -> String {
        switch place {
        case .docked: return english ? "Claude Code at work · its \(terminal.title) window is in the Dock" : "Claude Code 작업 중 · \(terminal.title) 창은 Dock에 접어 뒀어요"
        case .otherDisplay: return english ? "Claude Code at work · its \(terminal.title) window is on the other display" : "Claude Code 작업 중 · \(terminal.title) 창은 다른 화면에 뒀어요"
        case .behind: return english ? "Claude Code at work · its \(terminal.title) window is behind your windows" : "Claude Code 작업 중 · \(terminal.title) 창은 다른 창 뒤에 있어요"
        case .tab: return english ? "Claude Code at work · it opened as a tab of your \(terminal.title) window" : "Claude Code 작업 중 · 쓰시던 \(terminal.title) 창의 탭으로 열렸어요"
        }
    }

    // MARK: - The job's end

    /// The launch itself may show the window for a moment: looks are counted only after this long.
    static let settle: TimeInterval = 4

    /// Whether the user is looking at the teammate's window: it is the front window of the front app.
    static func isLooking(frontPid: Int32?, topWindow: Int?, terminalPid: Int32, window: Int?, sinceOpen: TimeInterval) -> Bool {
        guard sinceOpen >= settle, let window, frontPid == terminalPid else { return false }
        return topWindow == window
    }

    enum End: String, Equatable {
        /// The session was ended and its window closes by itself.
        case closed
        /// The session was ended; this terminal's window can't be closed from outside and stays.
        case ended
        /// The user looked at the window, the window is not known, or the session could not be found: nothing was touched.
        case left
        /// It was a tab of a window of his: the session was ended, and the tab and its window were left alone.
        case tab
    }

    /// What happens to a window whose job is over. One he looked at is his and is left alone; one he never saw has
    /// its session ended, and closes where the terminal lets its own shell close it (Warp keeps the window).
    /// A window Aris does not know (`.unknown`) counts as one he may be in: nothing is ended or closed (review 7, L4).
    static func end(seen: Bool, sessionFound: Bool, terminal: ArisTerminal, window: Window) -> End {
        guard !seen, sessionFound, window != .unknown else { return .left }
        if case .tab = window { return .tab }
        return terminal == .warp ? .ended : .closed
    }

    /// Warp's window, whose shell can't close it: Aris presses its close button only when the user never looked at it and
    /// the teammate's script has left (nothing is running in it that Warp would ask about).
    /// And only a window whose title was read back as this launch's when it opened (`titleMatched`).
    static func mayPressClose(seen: Bool, scriptGone: Bool, window: Int?, titleMatched: Bool) -> Bool { !seen && scriptGone && window != nil && titleMatched }

    /// The sentence added to the job's last line, in the job's language; nil when the window closed by itself.
    static func endWords(_ end: End, korean: Bool) -> String? {
        switch end {
        case .closed: return nil
        case .ended: return korean ? "터미널 창은 닫지 못해서 그대로 있어요." : "I couldn't close the terminal window, so it is still there."
        case .left: return korean ? "터미널은 그대로 뒀어요." : "I left the terminal as it is."
        case .tab: return korean ? "터미널 탭은 그대로 뒀어요." : "I left the terminal tab as it is."
        }
    }

    // MARK: - macOS's question about controlling a terminal

    /// What the job's row says before a script is sent to a terminal macOS has not been asked about yet, so the
    /// system's question does not come from nowhere. Only iTerm2 is scripted from outside now.
    static func automationLine(_ terminal: ArisTerminal, english: Bool) -> String {
        english ? "macOS may ask whether Aris may control \(terminal.title) · press Allow so the teammate can start"
            : "macOS가 Aris의 \(terminal.title) 제어를 물어볼 수 있어요 · 허용을 누르면 팀원이 시작해요"
    }
}
