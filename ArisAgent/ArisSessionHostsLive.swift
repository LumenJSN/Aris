//
//  ArisSessionHostsLive.swift
//  aris-agent
//
//  The live ways into a Claude Code session, one per host (ArisSessionHost), each behind the same four steps the send
//  takes after the user's yes: reach (find the exact place and prove it), look (Claude Code's input box idle and empty),
//  type the text, press Return; and `finish`, which puts back whatever was changed (the host's tab or window, a title,
//  the front app). The user's front app and pointer stay put wherever the host takes input in the background (measured in
//  the VM: tmux, screen, WezTerm and kitty by their own command line; iTerm2 by AppleScript into the session; Terminal,
//  Ghostty and other native terminals by keys posted to their process); Warp, editors' terminals and the Claude app
//  get a brief turn in front, and the app and tab the user had come back. Anything that can't be proven stops it, with the
//  host named.
//

import AppKit
import ApplicationServices
import Foundation

/// One reached session: how to look at it, type into it, press Return, and what to put back.
final class ArisSessionReach {
    let host: ArisSessionHost
    let tty: String
    let pid: Int32
    var look: () -> ArisSessionStop? = { .screenNotIdle }
    var type: (String) -> ArisSessionStop? = { _ in .typingFailed }
    var submit: () -> ArisSessionStop? = { .typingFailed }
    var finish: () -> Void = {}

    init(host: ArisSessionHost, tty: String, pid: Int32) {
        self.host = host
        self.tty = tty
        self.pid = pid
    }
}

enum ArisSessionHostsLive {
    // MARK: - Running a host's own tool

    /// A tool's output (stdout), or nil when it failed. The environment is only what the tool needs.
    static func tool(_ path: String, _ arguments: [String], environment: [String: String] = [:], timeout: TimeInterval = 6) -> String? {
        let base = ["PATH": "/usr/bin:/bin:/usr/sbin:/opt/homebrew/bin:/usr/local/bin", "HOME": NSHomeDirectory(), "LANG": "en_US.UTF-8"]
        let result = ArisSkillProcess.run(path, arguments, environment: base.merging(environment) { $1 }, timeout: timeout, maxOutput: 512 * 1_024)
        return result.ok ? result.stdout : nil
    }

    /// The first of these files that exists and runs.
    static func executable(_ candidates: [String?]) -> String? {
        candidates.compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func path(ofPid pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    /// The look at text a host's own tool gave (tmux, screen, WezTerm, kitty, iTerm2: exact, the pane alone).
    static func lookAt(_ text: String?) -> ArisSessionStop? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .screenNotIdle }
        if ArisSessionScreen.takesNextKey([text]) { return .terminalNotice }
        switch ArisSessionScreen.verdict(ArisSessionScreen.lines(fromText: text)) {
        case .idle: return nil
        case .working: return .working
        case .asking: return .waitingOnUser
        case .notClaude: return .screenNotIdle
        case .draft: return .draftInInput
        }
    }

    // MARK: - Reach

    static func reach(_ host: ArisSessionHost, process: ArisSessionProcess, session: ArisLiveSession, environment: [String: String])
        -> Result<ArisSessionReach, ArisSessionStop> {
        switch host {
        case .tmux(let socket, let pane): return tmux(socket: socket, pane: pane, process: process, environment: environment)
        case .screen(let name, let window): return screen(session: name, window: window, process: process)
        case .wezterm(let pane, let socket): return wezterm(pane: pane, socket: socket, process: process, environment: environment, session: session)
        case .kitty(let socket, let window): return kitty(socket: socket, window: window, process: process, environment: environment, session: session)
        case .iterm(let id): return iterm(session: id, process: process)
        case .terminalApp: return ArisSessionWindowsLive.terminal(process: process)
        case .warp(let focus): return ArisSessionWindowsLive.warp(focus: focus, process: process)
        case .editor(let bundle): return ArisSessionWindowsLive.editor(bundle: bundle, process: process, session: session)
        case .window(let bundle): return ArisSessionWindowsLive.window(bundle: bundle, process: process)
        case .claudeDesktop: return ArisSessionDesktopLive.reach(process: process, session: session)
        case .editorPanel: return .failure(.hostNotSupported(host.name + "의 Claude Code 패널"))
        case .background: return .failure(.backgroundSession)
        case .unsupported(let app): return .failure(.hostNotSupported(app))
        }
    }

    // MARK: - tmux (exact, no window touched)

    static func tmux(socket: String, pane: String, process: ArisSessionProcess, environment: [String: String]) -> Result<ArisSessionReach, ArisSessionStop> {
        let server = environment["TMUX"].flatMap { $0.split(separator: ",").dropFirst().first }.flatMap { Int32($0) }
        guard let binary = executable([server.flatMap(path(ofPid:)), "/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]) else {
            return .failure(.hostNotProven("tmux"))
        }
        func run(_ arguments: [String]) -> String? { tool(binary, ["-S", socket] + arguments) }
        /// The pane is still that tty, alive, and not in a mode that would take the keys (copy mode).
        func proven() -> Bool {
            guard let line = run(["display-message", "-p", "-t", pane, "#{pane_tty}|#{pane_in_mode}|#{pane_dead}"])?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
            return line == "\(process.tty)|0|0"
        }
        guard proven() else { return .failure(.hostNotProven("tmux")) }
        let reach = ArisSessionReach(host: .tmux(socket: socket, pane: pane), tty: process.tty, pid: process.pid)
        reach.look = { proven() ? lookAt(run(["capture-pane", "-p", "-t", pane])) : .focusMoved }
        reach.type = { text in
            guard proven() else { return .focusMoved }
            let buffer = "aris-send-" + UUID().uuidString.prefix(8).lowercased()
            guard run(["set-buffer", "-b", buffer, "--", text]) != nil else { return .typingFailed }
            // -p: as a paste when the program asked for bracketed paste (Claude Code does); -d: the buffer goes after.
            guard run(["paste-buffer", "-p", "-d", "-r", "-b", buffer, "-t", pane]) != nil else {
                _ = run(["delete-buffer", "-b", buffer])
                return .typingFailed
            }
            return nil
        }
        reach.submit = { proven() && run(["send-keys", "-t", pane, "Enter"]) != nil ? nil : .focusMoved }
        return .success(reach)
    }

    // MARK: - screen

    static func screen(session name: String, window: String, process: ArisSessionProcess) -> Result<ArisSessionReach, ArisSessionStop> {
        guard let binary = executable(["/opt/homebrew/bin/screen", "/usr/local/bin/screen", "/usr/bin/screen"]),
              let server = Int32(name.split(separator: ".").first ?? ""), ArisSessionHostsLive.isAncestor(server, of: process.pid) else {
            return .failure(.hostNotProven("screen"))
        }
        func run(_ arguments: [String]) -> String? { tool(binary, ["-S", name, "-p", window] + arguments) }
        let reach = ArisSessionReach(host: .screen(session: name, window: window), tty: process.tty, pid: process.pid)
        reach.look = {
            let file = NSTemporaryDirectory() + "aris-screen-\(UUID().uuidString.prefix(8)).txt"
            defer { try? FileManager.default.removeItem(atPath: file) }
            guard run(["-X", "hardcopy", file]) != nil else { return .screenNotIdle }
            Thread.sleep(forTimeInterval: 0.2)
            // screen's copy can carry NULs and bytes that aren't UTF-8 (its older builds): read leniently.
            guard let data = FileManager.default.contents(atPath: file) else { return .screenNotIdle }
            return lookAt(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\0", with: ""))
        }
        // screen reads ^ and \ in what it stuffs: both are escaped.
        reach.type = { text in run(["-X", "stuff", text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "^", with: "\\^")]) != nil ? nil : .typingFailed }
        // The carriage return itself (screen took "^M" in an argument as those two characters: VM, 2026-11-16).
        reach.submit = { run(["-X", "stuff", "\r"]) != nil ? nil : .typingFailed }
        return .success(reach)
    }

    static func isAncestor(_ ancestor: Int32, of pid: Int32) -> Bool {
        var current = pid
        for _ in 0..<24 {
            if current == ancestor { return true }
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.stride
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, current]
            guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return false }
            let parent = info.kp_eproc.e_ppid
            guard parent > 1, parent != current else { return false }
            current = parent
        }
        return false
    }

    // MARK: - WezTerm

    static func wezterm(pane: String, socket: String?, process: ArisSessionProcess, environment: [String: String], session: ArisLiveSession)
        -> Result<ArisSessionReach, ArisSessionStop> {
        let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.github.wez.wezterm").first?.bundleURL?.appendingPathComponent("Contents/MacOS/wezterm").path
        guard let binary = executable([app, "/Applications/WezTerm.app/Contents/MacOS/wezterm", "/opt/homebrew/bin/wezterm"]) else {
            return ArisSessionWindowsLive.window(bundle: "com.github.wez.wezterm", process: process)
        }
        let env = socket.map { ["WEZTERM_UNIX_SOCKET": $0] } ?? [:]
        func run(_ arguments: [String]) -> String? { tool(binary, ["cli"] + arguments, environment: env) }
        func proven() -> Bool {
            guard let data = run(["list", "--format", "json"])?.data(using: .utf8), let panes = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return false }
            return panes.contains { "\($0["pane_id"] ?? "")" == pane && ($0["tty_name"] as? String) == process.tty }
        }
        // Its command line answers only for the instance it was told of: else the window way, by the title mark.
        guard proven() else { return ArisSessionWindowsLive.window(bundle: "com.github.wez.wezterm", process: process) }
        let reach = ArisSessionReach(host: .wezterm(pane: pane, socket: socket), tty: process.tty, pid: process.pid)
        reach.look = { proven() ? lookAt(run(["get-text", "--pane-id", pane])) : .focusMoved }
        reach.type = { text in proven() && run(["send-text", "--pane-id", pane, "--", text]) != nil ? nil : .typingFailed }
        reach.submit = { run(["send-text", "--pane-id", pane, "--no-paste", "\r"]) != nil ? nil : .typingFailed }
        return .success(reach)
    }

    // MARK: - kitty (its remote control, when it listens)

    static func kitty(socket: String, window: String, process: ArisSessionProcess, environment: [String: String], session: ArisLiveSession)
        -> Result<ArisSessionReach, ArisSessionStop> {
        let app = NSRunningApplication.runningApplications(withBundleIdentifier: "net.kovidgoyal.kitty").first?.bundleURL?.appendingPathComponent("Contents/MacOS/kitten").path
        guard let binary = executable([app, "/Applications/kitty.app/Contents/MacOS/kitten", "/opt/homebrew/bin/kitten"]) else {
            return ArisSessionWindowsLive.window(bundle: "net.kovidgoyal.kitty", process: process)
        }
        func run(_ arguments: [String]) -> String? { tool(binary, ["@", "--to", socket] + arguments) }
        func proven() -> Bool {
            guard let data = run(["ls"])?.data(using: .utf8), let osWindows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return false }
            for osWindow in osWindows {
                for tab in osWindow["tabs"] as? [[String: Any]] ?? [] {
                    for item in tab["windows"] as? [[String: Any]] ?? [] where "\(item["id"] ?? "")" == window {
                        let pids = (item["foreground_processes"] as? [[String: Any]] ?? []).compactMap { ($0["pid"] as? NSNumber)?.int32Value }
                        return pids.contains(process.pid)
                    }
                }
            }
            return false
        }
        guard proven() else { return ArisSessionWindowsLive.window(bundle: "net.kovidgoyal.kitty", process: process) }
        let match = "id:" + window
        let reach = ArisSessionReach(host: .kitty(socket: socket, window: window), tty: process.tty, pid: process.pid)
        reach.look = { proven() ? lookAt(run(["get-text", "--match", match])) : .focusMoved }
        reach.type = { text in proven() && run(["send-text", "--match", match, "--bracketed-paste=auto", "--", text]) != nil ? nil : .typingFailed }
        reach.submit = { run(["send-key", "--match", match, "enter"]) != nil ? nil : .typingFailed }
        return .success(reach)
    }

    // MARK: - iTerm2 (AppleScript into the session itself)

    /// An AppleScript string literal of `text` (its quotes and backslashes escaped; the text has no line breaks).
    static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func itermScript(_ id: String, _ body: String) -> String? {
        guard UUID(uuidString: id) != nil else { return nil }
        return """
        tell application id "com.googlecode.iterm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if unique id of s is "\(id)" then
                            tell s
                                \(body)
                            end tell
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return "none"
        """
    }

    static func osascript(_ source: String) -> String? {
        tool("/usr/bin/osascript", ["-e", source], timeout: 8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func iterm(session id: String, process: ArisSessionProcess) -> Result<ArisSessionReach, ArisSessionStop> {
        func proven() -> Bool { itermScript(id, "return tty").flatMap(osascript) == process.tty }
        guard proven() else { return ArisSessionWindowsLive.window(bundle: "com.googlecode.iterm2", process: process) }
        let reach = ArisSessionReach(host: .iterm(session: id), tty: process.tty, pid: process.pid)
        reach.look = { proven() ? lookAt(itermScript(id, "return contents").flatMap(osascript)) : .focusMoved }
        reach.type = { text in
            guard proven(), let script = itermScript(id, "write text \(quoted(text)) newline no\nreturn \"ok\"") else { return .focusMoved }
            return osascript(script) == "ok" ? nil : .typingFailed
        }
        // Return as the key itself (a carriage return), into the same session.
        reach.submit = {
            guard proven(), let script = itermScript(id, "write text (ASCII character 13) newline no\nreturn \"ok\"") else { return .focusMoved }
            return osascript(script) == "ok" ? nil : .typingFailed
        }
        return .success(reach)
    }
}
