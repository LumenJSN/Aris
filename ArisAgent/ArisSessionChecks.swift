//
//  ArisSessionChecks.swift
//  aris-agent
//
//  The pure halves of the checks before a prompt is typed into a Claude Code session's tab (ArisSessionSend): which
//  `claude` process is the session's, the AppleScript that selects a Terminal or iTerm2 tab by its tty, the title mark
//  written to the tty, and what the look at the window must show. The live halves are ArisSessionLive. Pure.
//

import Foundation

/// The session's process, as the process table shows it.
struct ArisSessionProcess: Equatable {
    let pid: Int32
    /// "/dev/ttysNNN".
    let tty: String
    /// It is the foreground job of its tty (its process group is the terminal's).
    let foreground: Bool
    /// Its TERM_PROGRAM ("Apple_Terminal", "iTerm.app", "WarpTerminal"), when it has one: the terminal when no app is
    /// found among its parents (iTerm2's sessions hang off a server process).
    var program: String? = nil
    /// Its terminal variables (ArisSessionProcesses.terminalKeys only): which host it is in (ArisSessionHost).
    var environment: [String: String] = [:]
    /// Claude Code's own list says it is a background session (no input box to type into).
    var background = false
}

enum ArisSessionProcessLook: Equatable {
    case found(ArisSessionProcess)
    case none
    case many
}

/// The tab, once it is in front and proven: the terminal app's pid, and a token for the window that was proven (the
/// paste and Return go only while that window still has the keyboard).
struct ArisSessionTarget: Equatable {
    let appPid: Int32
    let bundle: String
    let window: Int
}

/// One process as the table shows it: what the session check needs, and only the terminal variables of its
/// environment (never anything else is read out of it).
struct ArisProcessRow: Equatable {
    let pid: Int32
    let parent: Int32
    /// The name it runs as (argv[0]'s last part: "claude").
    let name: String
    let cwd: String
    /// "/dev/ttysNNN", or nil when it has no terminal.
    let tty: String?
    let foreground: Bool
    let stopped: Bool
    let terminal: [String: String]
}

enum ArisSessionProcesses {
    /// The environment variables read from a process (to tell two sessions in one folder apart): the terminal's own ids.
    static let terminalKeys: Set<String> = ["WARP_FOCUS_URL", "ITERM_SESSION_ID", "TERM_SESSION_ID", "TERM_PROGRAM", "TMUX", "TMUX_PANE", "STY", "WINDOW",
                                            "KITTY_WINDOW_ID", "KITTY_LISTEN_ON", "WEZTERM_PANE", "WEZTERM_UNIX_SOCKET", "__CFBundleIdentifier",
                                            "CLAUDE_CODE_ENTRYPOINT"]

    /// The session's process among `rows`: a `claude` with a terminal, in the session's folder. Several there: the one
    /// whose terminal ids match the session's (Warp's focus link, iTerm2's session id); else `many` (never a guess).
    /// `known`: how many sessions the app knows in that folder (more processes than sessions: one isn't the app's, and
    /// it can't be told which is which).
    static func pick(_ session: ArisLiveSession, rows: [ArisProcessRow], known: Int) -> ArisSessionProcessLook {
        let folder = (session.cwd as NSString).standardizingPath
        let mine = rows.filter { $0.name == "claude" && $0.tty != nil && ($0.cwd as NSString).standardizingPath == folder }
        guard !mine.isEmpty else { return .none }
        if let value = session.terminalValue, !value.isEmpty {
            let matched = mine.filter { row in
                switch session.terminalKind {
                case "warp": return row.terminal["WARP_FOCUS_URL"] == value
                case "iterm": return row.terminal["ITERM_SESSION_ID"].map { $0.hasSuffix(value) } ?? false
                default: return false
                }
            }
            if matched.count == 1 { return .found(process(matched[0])) }
        }
        guard mine.count == 1, known <= 1 else { return .many }
        return .found(process(mine[0]))
    }

    /// A row as the send's process: no terminal (the Claude app's sessions) is no shell in front of it.
    static func process(_ row: ArisProcessRow, background: Bool = false) -> ArisSessionProcess {
        ArisSessionProcess(pid: row.pid, tty: row.tty ?? "", foreground: row.tty == nil ? !row.stopped : row.foreground && !row.stopped,
                           program: row.terminal["TERM_PROGRAM"], environment: row.terminal, background: background)
    }

    /// argv[0]'s last part, from KERN_PROCARGS2's bytes; and the wanted environment variables. The layout: argc (4
    /// bytes), the executable's path, NULs, argc arguments, then the environment, each NUL-ended.
    static func parseArgs(_ bytes: [UInt8], keys: Set<String>) -> (name: String, environment: [String: String])? {
        guard bytes.count > 4 else { return nil }
        let argc = Int(Int32(littleEndian: bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }))
        guard argc >= 1, argc < 4_096 else { return nil }
        var index = 4
        func next() -> String? {
            guard index < bytes.count else { return nil }
            let start = index
            while index < bytes.count, bytes[index] != 0 { index += 1 }
            let word = String(decoding: bytes[start..<index], as: UTF8.self)
            index += 1
            return word
        }
        guard next() != nil else { return nil }
        while index < bytes.count, bytes[index] == 0 { index += 1 }
        var arguments: [String] = []
        for _ in 0..<argc {
            guard let word = next() else { return nil }
            arguments.append(word)
        }
        var environment: [String: String] = [:]
        while let entry = next(), !entry.isEmpty {
            guard let equals = entry.firstIndex(of: "=") else { continue }
            let key = String(entry[..<equals])
            if keys.contains(key) { environment[key] = String(entry[entry.index(after: equals)...].prefix(300)) }
        }
        guard let first = arguments.first else { return nil }
        return ((first as NSString).lastPathComponent, environment)
    }

    /// TERM_PROGRAM's terminals by bundle id.
    static let programs = ["Apple_Terminal": "com.apple.Terminal", "iTerm.app": "com.googlecode.iterm2", "WarpTerminal": "dev.warp.Warp-Stable",
                           "ghostty": "com.mitchellh.ghostty", "WezTerm": "com.github.wez.wezterm"]

    /// A tty path as the checks accept it.
    static func isTTY(_ path: String) -> Bool { path.range(of: "^/dev/ttys[0-9]{1,4}$", options: .regularExpression) != nil }
}

enum ArisSessionScripts {
    /// Terminal: selects the tab whose tty is `tty` inside its own window, in the background (never activated, its window
    /// never raised); "ok|<the tty of the tab that window had selected>" or "none". `tty` must pass isTTY.
    static func terminalTab(_ tty: String) -> String? {
        guard ArisSessionProcesses.isTTY(tty) else { return nil }
        return """
        tell application id "com.apple.Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(tty)" then
                        set was to tty of selected tab of w
                        set selected of t to true
                        return "ok|" & was
                    end if
                end repeat
            end repeat
        end tell
        return "none"
        """
    }

    /// Terminal: the custom title of the tab whose tty is `tty` (the program's own title), to put back after the mark.
    static func terminalTitle(_ tty: String) -> String? {
        guard ArisSessionProcesses.isTTY(tty) else { return nil }
        return """
        tell application id "com.apple.Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(tty)" then return custom title of t
                end repeat
            end repeat
        end tell
        return ""
        """
    }
}

enum ArisSessionMark {
    /// A fresh mark: nothing a program would set as its own title.
    static func make() -> String { "aris-check-" + String(UUID().uuidString.prefix(8)).lowercased() }

    /// The bytes that set a terminal's title (OSC 0: the window's and the tab's) to `title`; the empty one gives the tab
    /// its own title back. Only marks and the empty title are ever written.
    static func sequence(_ title: String) -> [UInt8] {
        Array("\u{1B}]0;\(title)\u{07}".utf8)
    }

    /// The mark, after the tab's own title is pushed (CSI 22;0t: iTerm2 and Warp keep it; Terminal ignores it).
    static func marking(_ mark: String) -> [UInt8] { Array("\u{1B}[22;0t".utf8) + sequence(mark) }

    /// The tab's own title back: popped (iTerm2, Warp), and for Terminal, which can't pop, `restore` (its custom title
    /// as Terminal read it out) written again, made plain first.
    static func unmarking(restore: String?) -> [UInt8] {
        let pop = Array("\u{1B}[23;0t".utf8)
        guard let restore else { return pop }
        return pop + sequence(plain(restore))
    }

    /// A title made safe to write back: no control or hidden characters, at most 200 characters.
    static func plain(_ title: String) -> String {
        String(String.UnicodeScalarView(title.unicodeScalars.filter { scalar in
            let kind = scalar.properties.generalCategory
            return kind != .control && kind != .format && kind != .lineSeparator && kind != .paragraphSeparator
        }).prefix(200))
    }

    /// Whether the window's title shows the mark.
    static func shows(_ title: String?, mark: String) -> Bool { title?.contains(mark) ?? false }
}

/// What the look at the session's window must show: Claude Code's input box, idle. Lines are the text Vision read, with
/// how far down the window each one is (0 top, 1 bottom); only the bottom part counts (what scrolled by above may
/// quote anything).
enum ArisSessionScreen {
    enum Verdict: Equatable { case idle, working, asking, notClaude, draft }

    /// The bottom share of the window that is read.
    static let bottom = 0.45

    /// Claude Code's own footer and prompt lines while it waits.
    private static let idleMarks = ["for shortcuts", "shift+tab to cycle", "bypass permissions", "accept edits on", "plan mode on", "auto mode",
                                    "auto-accept", "esc to undo"]
    /// While it works.
    private static let workingMarks = ["esc to interrupt", "to interrupt)"]
    /// A permission or a question it waits on (typing would answer it).
    private static let askingMarks = ["do you want to", "❯ 1.", "> 1. yes", "1. yes", "enter to select", "to navigate"]

    /// A window's text as Accessibility gives it (the terminal's own text area: exact, unlike a picture's), as lines
    /// placed like a picture's: the last `kept` lines with words, spread over the bottom of the window.
    /// The text area holds the scrollback too (VM pass 2: an old "esc to interrupt" frame above the live box refused
    /// sends): only from a few lines above the last prompt line on (the spinner's line sits just above the box), else the
    /// last `kept`. iTerm2 pads wide characters with NULs: taken out.
    static func lines(fromText text: String, kept: Int = 16) -> [(text: String, y: Double)] {
        let all = text.replacingOccurrences(of: "\0", with: "").components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let start = all.lastIndex(where: { promptRest($0) != nil }).map { max(0, $0 - 3) } ?? max(0, all.count - kept)
        let rows = all[start...].suffix(kept)
        let count = Double(rows.count)
        return rows.enumerated().map { index, row in (row, 1 - bottom + bottom * (Double(index) + 1) / max(count, 1)) }
    }

    /// A prompt line's text after its glyph ("> …", "❯ …", inside the box's │ or not), or nil when it isn't one.
    static func promptRest(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: CharacterSet(charactersIn: " │|\u{00A0}"))
        for glyph in [">", "❯"] where trimmed == glyph || trimmed.hasPrefix(glyph + " ") || trimmed.hasPrefix(glyph + "\u{00A0}") {
            return String(trimmed.dropFirst(glyph.count)).trimmingCharacters(in: CharacterSet(charactersIn: " │|\u{00A0}"))
        }
        return nil
    }

    /// Whether the last prompt line already holds words (the user's half-typed draft, or a paste that wasn't sent): a send
    /// would join them. Claude Code's own grey suggestion ("Try \"…\"") is not a draft.
    static func hasDraft(_ lines: [(text: String, y: Double)]) -> Bool {
        guard let rest = lines.sorted(by: { $0.y < $1.y }).last(where: { promptRest($0.text) != nil }).flatMap({ promptRest($0.text) }) else { return false }
        return !rest.isEmpty && !rest.hasPrefix("Try \"") && !rest.hasPrefix("Try “")
    }

    /// A terminal's own notice that takes the next key for itself (VM pass 3: iTerm2's "Press any key to dismiss this
    /// message" bar ate the Return, and the prompt stayed in the box unsent).
    static func takesNextKey(_ texts: [String]) -> Bool {
        texts.contains { text in
            let lowered = text.lowercased()
            return lowered.contains("press any key") || lowered.contains("아무 키나")
        }
    }

    /// `band`: the bottom share that is read (a picture is read whole: 1).
    static func verdict(_ lines: [(text: String, y: Double)], band: Double = bottom) -> Verdict {
        let low = lines.filter { $0.y >= 1 - band }.map { $0.text.lowercased() }
        if low.contains(where: { line in workingMarks.contains { line.contains($0) } }) { return .working }
        if low.contains(where: { line in askingMarks.contains { line.contains($0) } }) { return .asking }
        let footer = low.contains { line in idleMarks.contains { line.contains($0) } }
        let prompt = low.contains { promptRest($0) != nil }
        guard footer || prompt else { return .notClaude }
        return hasDraft(lines.filter { $0.y >= 1 - band }) ? .draft : .idle
    }
}
