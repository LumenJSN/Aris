//
//  ArisQuietOpener.swift
//  aris-agent
//
//  Opens a Claude Code teammate's window without disturbing the user (ArisQuietLaunch.swift has the rules and what was
//  measured). What is live here: the hardware clocks (his last key press and click: they need no permission and
//  never count Aris's own events), the app in front, the terminal's windows, and the files of the launch.
//  - The start waits for a gap in his typing.
//  - The window is asked for without activation; the front app is watched twice a frame for three seconds, and when
//    the terminal took the front although he clicked nothing, the app he was in gets it straight back.
//  - The launch script writes its process id when the terminal really runs it. A Warp that opens the window but
//    never runs the command is not used again by this helper, and the next terminal is taken at once.
//  - The window is known as the one that was not there before (in Terminal, the script reads its own window).
//  And the job's end (ArisQuietSession): the session is ended and its window closes itself, unless he looked at it.
//

import AppKit
import ApplicationServices
import Foundation

enum ArisQuietOpener {
    struct Opened {
        /// The terminal app's process.
        let pid: Int32
        /// What is known of the window: its own number, a tab of a window of the user's, or nothing.
        let window: ArisQuietLaunch.Window
        /// When the launch began, the terminal's app folder, and whether the window's title was read back as this
        /// launch's: what a pid mark and a close are checked against.
        let launchedAt: Date
        let bundle: String
        let titleMatched: Bool
        let pick: ArisQuietPick
        let files: ArisQuietFiles
        /// How long the terminal was in front before the app the user was in had the front again (nil: it never was).
        let lostFront: TimeInterval?
        /// Where the window ended up (Terminal's is minimised by its own script, another terminal's by ArisQuietTuck).
        let place: ArisQuietLaunch.Place

        var terminal: ArisTerminal { pick.terminal }
        /// The window Aris may send the figure to (never a window of the user's that holds the teammate as a tab).
        var windowNumber: Int? { window.number }
    }

    /// The terminal opened a window but never ran the launch script.
    struct NeverStarted: Error {
        let terminal: ArisTerminal
    }

    /// How long a terminal may take to run the script (one that was not running has to start first).
    static let startWait: TimeInterval = 12
    /// Warp runs a Tab Config's command right after its shell is ready, or not at all.
    static let warpStartWait: TimeInterval = 8
    /// How long the new window is looked for once the script runs.
    static let windowWait: TimeInterval = 3
    /// After the script was taken away from a Warp that did not start it: how long a start in that last moment may show.
    static let lateStartWait: TimeInterval = 0.6

    private static let lock = NSLock()
    nonisolated(unsafe) private static var unusable = Set<ArisTerminal>()

    // MARK: - His hands (hardware clocks, no permission)

    static func sinceKey() -> TimeInterval { CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown) }

    /// Seconds since he last pressed a key or a mouse button.
    static func sinceTouch() -> TimeInterval {
        [CGEventType.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
            .map { CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0) }.min() ?? 0
    }

    static func waitForTypingGap() {
        var waited: TimeInterval = 0
        while !ArisQuietLaunch.mayStart(sinceKey: sinceKey(), waited: waited) {
            Thread.sleep(forTimeInterval: ArisQuietLaunch.gapLook)
            waited += ArisQuietLaunch.gapLook
        }
    }

    // MARK: - Opening

    static func open(command: String, title: String?, wish: ArisTerminalWish, english: Bool, home: String,
                     say: @escaping (String) -> Void) throws -> Opened {
        waitForTypingGap()
        for _ in ArisTerminal.allCases {
            let front = ArisTerminal(bundleId: ArisFrontLive.front()?.bundleId)
            let pick = ArisQuietLaunch.pick(ArisTerminalOpener.facts(wish), command: command, front: front, unusable: lock.withLock { unusable })
            do {
                return try open(pick, command: command, title: ArisQuietLaunch.title(title), english: english, home: home, say: say)
            } catch let failed as NeverStarted {
                FileHandle.standardError.write(Data("aris-agent: \(failed.terminal.title) opened a window but never ran the teammate's command\n".utf8))
                lock.withLock { _ = unusable.insert(failed.terminal) }
            }
        }
        throw ArisTeammateLaunchError(message: ArisTerminalWords.notOpened(.terminal))
    }

    private static func open(_ pick: ArisQuietPick, command: String, title: String, english: Bool, home: String,
                             say: (String) -> Void) throws -> Opened {
        let terminal = pick.terminal, folder = ArisTeammateLauncher.launchFolder(home: home)
        guard ArisPrivateFile.prepareFolder(folder), let app = ArisTerminalOpener.appURL(terminal) else {
            throw ArisTeammateLaunchError(message: ArisTerminalWords.notOpened(terminal))
        }
        let id = UUID(), files = ArisQuietLaunch.files(folder: folder.path, id: id), shell = ArisTerminalOpener.loginShell
        let warpFolder = URL(fileURLWithPath: home).appendingPathComponent(".warp/tab_configs")
        let plan = ArisQuietLaunch.plan(terminal, title: title, shell: shell, files: files, warpFolder: warpFolder.path, id: id)
        // A mark that is there before the script ran was planted: the launch stops.
        guard ![files.pid, files.window, files.close].contains(where: { FileManager.default.fileExists(atPath: $0) }) else {
            throw ArisTeammateLaunchError(message: ArisTerminalWords.notOpened(terminal))
        }
        let launchedAt = Date()
        try ArisTerminalOpener.write(ArisQuietLaunch.script(command: command, title: title, terminal: terminal, shell: shell, files: files),
                                     to: files.script, mode: 0o700)
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: terminal.bundleId).first?.processIdentifier
        let before = Set(running.map(ArisWindowLocator.windows(pid:)) ?? [])
        // A terminal that starts cold restores the user's last windows: then no window is named. An instance started
        // for this launch alone has only the launch's own.
        var knownBefore = running != nil
        if case .arguments = plan { knownBefore = true }
        let watch = FrontWatch(terminal: terminal)
        var pid: Int32
        do {
            switch plan {
            case .document:
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                pid = try ArisTerminalOpener.wait(terminal) { done in
                    NSWorkspace.shared.open([URL(fileURLWithPath: files.script)], withApplicationAt: app, configuration: configuration, completionHandler: done)
                }
            case .script(let script):
                // macOS asks once whether Aris may control this terminal: the row says so before the question shows.
                if automationWouldAsk(terminal.bundleId) { say(ArisQuietLaunch.automationLine(terminal, english: english)) }
                try ArisTeammateLauncher.runScript(script)
                guard let found = NSRunningApplication.runningApplications(withBundleIdentifier: terminal.bundleId).first?.processIdentifier else {
                    throw ArisTeammateLaunchError(message: ArisTeammateLauncher.terminalNotFound)
                }
                pid = found
            case .arguments(let arguments):
                pid = try ArisTerminalOpener.start(terminal, arguments: arguments, activates: false)
            case .link(let link, let path, let contents):
                pid = try ArisTerminalOpener.openWarp(link: link, path: path, contents: contents, folder: warpFolder, activates: false)
            }
        } catch {
            _ = watch.finish(early: true)
            ArisTeammateLauncher.remove(URL(fileURLWithPath: files.script))
            throw error
        }
        // The script's process id is the proof that the terminal ran it.
        let ran = { ArisQuietSession.scriptPid(files, launchedAt: launchedAt, terminal: pid, bundle: app.path) != nil }
        var started = waitFor(terminal == .warp ? warpStartWait : startWait, ran)
        if !started, terminal == .warp {
            // The script goes first, so Warp can no longer start it; then one more look: a Warp that started it in
            // this very moment is running the approved command, and no second terminal is opened (review 7, L5).
            ArisTeammateLauncher.remove(URL(fileURLWithPath: files.script))
            started = waitFor(lateStartWait, ran)
        }
        if !started, terminal == .warp {
            _ = watch.finish(early: true)
            // No idle window is left when Aris can close it: only one that is surely the launch's (the one new
            // window of a Warp that was running, showing the launch's own title), by its own button.
            if let stray = ArisQuietLaunch.ownWindow(before: before, after: ArisWindowLocator.windows(pid: pid), knownBefore: knownBefore).number {
                _ = ArisQuietTuck.close(pid: pid, window: stray, title: title)
            }
            throw NeverStarted(terminal: terminal)
        }
        // Terminal's script says which window it is in (or that it is a tab of his); elsewhere it is the one new window.
        var window = ArisQuietLaunch.Window.unknown
        _ = waitFor(windowWait) {
            window = terminal == .terminal ? ArisQuietLaunch.window(mark: ArisQuietSession.text(in: files.window, launchedAt: launchedAt))
                : ArisQuietLaunch.ownWindow(before: before, after: ArisWindowLocator.windows(pid: pid), knownBefore: knownBefore)
            return window != .unknown
        }
        // Counted once more at the end: a second new window that came during the wait means none is named.
        if terminal != .terminal { window = ArisQuietLaunch.ownWindow(before: before, after: ArisWindowLocator.windows(pid: pid), knownBefore: knownBefore) }
        // Terminal's script has minimised its own window; another terminal's is put away through Accessibility,
        // and only when it shows the launch's title.
        var place = ArisQuietLaunch.Place.behind, titleMatched = false
        switch (terminal, window) {
        case (.terminal, .own): (place, titleMatched) = (.docked, true)
        case (.terminal, .tab): place = .tab
        case (_, .own(let number)) where terminal != .terminal: (place, titleMatched) = ArisQuietTuck.putAway(pid: pid, window: number, title: title)
        default: break
        }
        return Opened(pid: pid, window: window, launchedAt: launchedAt, bundle: app.path, titleMatched: titleMatched, pick: pick, files: files,
                      lostFront: watch.finish(early: false), place: place)
    }

    private static func waitFor(_ seconds: TimeInterval, _ found: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if found() { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return found()
    }

    /// Whether macOS would ask the user before a script reaches this app (it has not been asked yet). Asked with
    /// askUserIfNeeded false, which never shows anything; an app that is not running can't be asked about, so the
    /// line is said then too.
    static func automationWouldAsk(_ bundleId: String) -> Bool {
        var target = AEAddressDesc()
        let bytes = Data(bundleId.utf8)
        guard bytes.withUnsafeBytes({ AECreateDesc(typeApplicationBundleID, $0.baseAddress, bytes.count, &target) }) == noErr else { return false }
        defer { AEDisposeDesc(&target) }
        let status = AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, false)
        return status == OSStatus(errAEEventWouldRequireUserConsent) || status == OSStatus(procNotFound)
    }

    // MARK: - The front app

    /// Watches the front app while the window opens, and hands the front back when the terminal took it.
    private final class FrontWatch: @unchecked Sendable {
        private let before: Int32?
        private let bundleId: String
        private let started = Date()
        private let done = DispatchSemaphore(value: 0)
        private let state = NSLock()
        private var stopped = false
        private var lost: TimeInterval?

        init(terminal: ArisTerminal) {
            before = ArisFrontLive.frontPid()
            bundleId = terminal.bundleId
            DispatchQueue.global(qos: .userInteractive).async { [self] in run() }
        }

        private func run() {
            var since: Date?, asked = Date.distantPast
            while Date().timeIntervalSince(started) < ArisQuietLaunch.frontWatch, !state.withLock({ stopped }) {
                // Asked of the window server and Accessibility each time (ArisFrontLive): NSWorkspace's front app never
                // changes in this process (second upgrade run, bug 1), so this watch used to see nothing.
                let front = ArisFrontLive.front()
                let isTerminal = front?.bundleId?.caseInsensitiveCompare(bundleId) == .orderedSame
                if isTerminal, front?.pid != before {
                    since = since ?? Date()
                    let action = ArisQuietLaunch.front(before: before, now: front?.pid, terminal: front?.pid,
                                                       sinceTouch: ArisQuietOpener.sinceTouch(), sinceOpen: Date().timeIntervalSince(started))
                    // Asked again every tenth of a second while the terminal stays in front (macOS may refuse once).
                    if action == .giveBack, Date().timeIntervalSince(asked) > 0.1, let before {
                        asked = Date()
                        NSRunningApplication(processIdentifier: before)?.activate(options: [])
                    }
                } else if let from = since {
                    state.withLock { lost = (lost ?? 0) + Date().timeIntervalSince(from) }
                    since = nil
                }
                Thread.sleep(forTimeInterval: ArisQuietLaunch.frontLook)
            }
            if let from = since { state.withLock { lost = (lost ?? 0) + Date().timeIntervalSince(from) } }
            done.signal()
        }

        /// How long the terminal was in front. `early`: the launch failed, so the watch ends now.
        func finish(early: Bool) -> TimeInterval? {
            if early { state.withLock { stopped = true } }
            done.wait()
            return state.withLock { lost }
        }
    }
}

/// One teammate's session after its window opened: which process it is, whether the user is looking at it, and its end.
enum ArisQuietSession {
    /// How long the script is given to leave after Claude Code was asked to end.
    static let scriptWait: TimeInterval = 3

    /// What the script wrote in one of the launch's marks (umask 077: the user's own, private). Nil for a mark that is
    /// older than the launch: that one was planted, and is never read.
    static func text(in path: String, launchedAt: Date) -> String? {
        var info = stat()
        guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              ArisQuietLaunch.markIsFresh(modified: Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9, launched: launchedAt.timeIntervalSince1970),
              let data = ArisPrivateFile.read(URL(fileURLWithPath: path)), data.count <= 64 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// The launch script's process, when it is still running AND is the script Aris started: it began after the
    /// launch and runs under the terminal the launch opened (ArisQuietLaunch.isOwnScript). A number in the mark that
    /// names any other process is never believed, and so never signalled.
    static func scriptPid(_ files: ArisQuietFiles, launchedAt: Date, terminal: Int32, bundle: String?) -> Int32? {
        guard let pid = text(in: files.pid, launchedAt: launchedAt).flatMap({ Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }), pid > 1,
              kill(pid, 0) == 0, let started = lineage(pid).first?.started,
              ArisQuietLaunch.isOwnScript(started: started, launched: launchedAt.timeIntervalSince1970,
                                          ancestors: lineage(pid).dropFirst().map { ($0.pid, $0.path) }, terminal: terminal, bundle: bundle) else { return nil }
        return pid
    }

    static func scriptPid(_ opened: ArisQuietOpener.Opened) -> Int32? {
        scriptPid(opened.files, launchedAt: opened.launchedAt, terminal: opened.pid, bundle: opened.bundle)
    }

    /// `pid` and the processes above it (its parent first), each with its program and when it started.
    static func lineage(_ pid: Int32) -> [(pid: Int32, path: String, started: TimeInterval)] {
        var found: [(pid: Int32, path: String, started: TimeInterval)] = []
        var next = pid
        while next > 1, found.count < 12 {
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(next, PROC_PIDTBSDINFO, 0, &info, size) == size else { break }
            var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            let path = proc_pidpath(next, &buffer, UInt32(buffer.count)) > 0 ? String(cString: buffer) : ""
            found.append((next, path, Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1e6))
            next = Int32(info.pbi_ppid)
        }
        return found
    }

    /// The script's child that is Claude Code: `claude` is the checked binary's path (nil: the bare `claude`, taken
    /// by its name).
    static func claude(under script: Int32, claude: String?) -> Int32? {
        var pids = [Int32](repeating: 0, count: 64)
        let count = Int(proc_listchildpids(script, &pids, Int32(pids.count * MemoryLayout<Int32>.size)))
        return pids.prefix(max(count, 0)).first { pid in
            var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return false }
            let path = String(cString: buffer)
            return claude.map { $0 == path } ?? path.contains("claude")
        }
    }

    /// Whether the user is looking at the window right now (ArisQuietLaunch.isLooking).
    static func isLooking(_ opened: ArisQuietOpener.Opened, since at: Date) -> Bool {
        let top = ArisWindowLocator.topWindow()
        return ArisQuietLaunch.isLooking(frontPid: ArisFrontLive.frontPid(),
                                         topWindow: top.flatMap { $0.pid == opened.pid ? $0.number : nil },
                                         terminalPid: opened.pid, window: opened.window.looked, sinceOpen: Date().timeIntervalSince(at))
    }

    /// The job is over. A window the user never looked at has its session ended: the close request is left for the
    /// script, then Claude Code is asked to end (SIGTERM: it saves the session and leaves), and the script closes up.
    /// Nothing but that one process is signalled, and nothing of a window he looked at is touched.
    static func end(_ opened: ArisQuietOpener.Opened, seen: Bool, claude: String?) -> ArisQuietLaunch.End {
        let session = scriptPid(opened).flatMap { self.claude(under: $0, claude: claude) }
        let end = ArisQuietLaunch.end(seen: seen, sessionFound: session != nil, terminal: opened.terminal, window: opened.window)
        guard end != .left, let session, let script = scriptPid(opened) else { return .left }
        do {
            try ArisTerminalOpener.write("", to: opened.files.close, mode: 0o600)
        } catch {
            return .left
        }
        kill(session, SIGTERM)
        guard end == .ended else { return end }
        // Warp: its shell can't close the window. Once the script has left, Aris presses the window's close button.
        let limit = Date().addingTimeInterval(scriptWait)
        while kill(script, 0) == 0, Date() < limit { Thread.sleep(forTimeInterval: 0.1) }
        guard ArisQuietLaunch.mayPressClose(seen: seen, scriptGone: kill(script, 0) != 0, window: opened.windowNumber, titleMatched: opened.titleMatched),
              let window = opened.windowNumber, ArisQuietTuck.close(pid: opened.pid, window: window, title: nil) else { return .ended }
        return .closed
    }
}
