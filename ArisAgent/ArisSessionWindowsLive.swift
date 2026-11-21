//
//  ArisSessionWindowsLive.swift
//  aris-agent
//
//  The ways into a session that go through a terminal's window (ArisSessionHostsLive's other half): the tab is proven
//  by a title mark written to the session's tty and read back from the host's window by Accessibility, without the
//  window coming forward where the host takes keys in the background (Terminal, Ghostty, any native terminal: keys
//  posted to its process), or with a brief turn in front where it doesn't (Warp, an editor's terminal). Whatever was
//  changed comes back in `finish`: the tab or window the host had selected, the tab's own title, and the app in front.
//

import AppKit
import ApplicationServices
import Foundation

enum ArisSessionWindowsLive {
    // MARK: - Shared parts

    /// The host app's process: the first ordinary app among the session's parents, else the bundle's running one.
    static func hostPid(_ process: ArisSessionProcess, bundle: String) -> Int32? {
        if let app = ArisSessionLive.hostApp(of: process.pid), app.bundleIdentifier == bundle { return app.processIdentifier }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundle)
        return running.count == 1 ? running[0].processIdentifier : nil
    }

    static func windows(_ pid: Int32) -> [AXUIElement] { ArisAX.value(ArisAX.app(pid), kAXWindowsAttribute as String) as? [AXUIElement] ?? [] }

    /// The app's window whose title shows the mark (polled a moment: the terminal redraws its title).
    static func markedWindow(_ pid: Int32, mark: String, wait: TimeInterval = 1.5) -> AXUIElement? {
        let deadline = Date().addingTimeInterval(wait)
        repeat {
            let found = windows(pid).filter { ArisSessionMark.shows(ArisAX.string($0, kAXTitleAttribute as String), mark: mark) }
            if found.count == 1 { return found[0] }
            if found.count > 1 { return nil }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline
        return nil
    }

    /// The app's focused window shows the mark (the keys go there).
    static func focusedShows(_ pid: Int32, mark: String) -> Bool {
        ArisSessionMark.shows(ArisAX.element(ArisAX.app(pid), kAXFocusedWindowAttribute as String).flatMap { ArisAX.string($0, kAXTitleAttribute as String) }, mark: mark)
    }

    /// A window made its app's main (keyboard) window while the app stays behind: raised within its app and made main
    /// (AXMain alone didn't take with two Terminal windows: VM, 2026-11-16). The front app doesn't change.
    static func makeMain(_ window: AXUIElement) {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        Thread.sleep(forTimeInterval: 0.2)
    }

    /// The text of a window's elements of these roles, a few levels down.
    static func texts(_ root: AXUIElement, roles: Set<String> = [kAXTextAreaRole as String]) -> [String] {
        var texts: [String] = []
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var index = 0
        while index < queue.count, index < 600 {
            let (element, depth) = queue[index]
            index += 1
            if roles.contains(ArisAX.role(element)), let value = ArisAX.string(element, kAXValueAttribute as String), !value.isEmpty { texts.append(value) }
            if depth < 9 { queue += ArisAX.children(element).map { ($0, depth + 1) } }
        }
        return texts
    }

    /// The look at a window: its terminal text by Accessibility (exact), else one picture of it (or of `crop`, global
    /// points) read whole with Vision.
    static func lookAt(window: AXUIElement, crop: CGRect? = nil) -> ArisSessionStop? {
        if crop == nil, let text = texts(window).max(by: { $0.count < $1.count }), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if ArisSessionScreen.takesNextKey(texts(window, roles: [kAXTextAreaRole as String, kAXStaticTextRole as String, kAXButtonRole as String])) { return .terminalNotice }
            return ArisSessionHostsLive.lookAt(String(text.suffix(20_000)))
        }
        // As macOS has it now (this process's own preflight answer is kept from when it started: stale after a grant).
        guard ArisScreenAccess.nowAsAgent() else { return .noScreenRecording }
        guard let id = ArisAX.windowId(window), let frame = ArisAX.frame(window) else { return .screenNotIdle }
        let file = NSTemporaryDirectory() + "aris-session-look-\(UUID().uuidString.prefix(8)).png"
        defer { try? FileManager.default.removeItem(atPath: file) }
        guard ArisNativeShot.capture(window: id, to: file), var image = NSImage(contentsOfFile: file)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            // The capture failed: asked again (a grant taken back since is noticed now).
            if ArisScreenAccess.afterFailureAsAgent() == false { return .noScreenRecording }
            return .screenNotIdle
        }
        if let crop, frame.width > 0 {
            let scale = CGFloat(image.width) / frame.width
            let rect = CGRect(x: (crop.minX - frame.minX) * scale, y: (crop.minY - frame.minY) * scale, width: crop.width * scale, height: crop.height * scale)
            guard let cut = image.cropping(to: rect.integral) else { return .screenNotIdle }
            image = cut
        }
        switch ArisSessionScreen.verdict(ArisSessionLive.read(image), band: 1) {
        case .idle: return nil
        case .working: return .working
        case .asking: return .waitingOnUser
        case .notClaude: return .screenNotIdle
        case .draft: return .draftInInput
        }
    }

    /// The mark on the tty, its title pushed first; `restore` written back for a host that can't pop (Terminal).
    static func mark(_ tty: String, restore: String? = nil) -> (mark: String, undo: () -> Void)? {
        let mark = ArisSessionMark.make()
        guard ArisSessionLive.write(ArisSessionMark.marking(mark), tty: tty) else { return nil }
        return (mark, { _ = ArisSessionLive.write(ArisSessionMark.unmarking(restore: restore), tty: tty) })
    }

    // MARK: - Any terminal app by its window (Ghostty, Alacritty, Hyper, Tabby, kitty or WezTerm without their tools…)

    static func window(bundle: String, process: ArisSessionProcess) -> Result<ArisSessionReach, ArisSessionStop> {
        let name = ArisSessionHost.window(bundle: bundle).name
        guard AXIsProcessTrusted() else { return .failure(.noAccessibility) }
        guard let pid = hostPid(process, bundle: bundle), let (mark, undo) = mark(process.tty) else { return .failure(.hostNotProven(name)) }
        var kept = false
        defer { if !kept { undo() } }
        guard let window = markedWindow(pid, mark: mark) else { return .failure(.hostNotProven(name)) }
        let app = ArisAX.app(pid)
        let previous = ArisAX.element(app, kAXFocusedWindowAttribute as String)
        // The marked window made the app's main one (a native tab is its own window: this selects it), in the background.
        if !focusedShows(pid, mark: mark) {
            makeMain(window)
        }
        let running = NSRunningApplication(processIdentifier: pid)
        let background = ArisNativeInput.takesBackgroundKeys(bundle: bundle, bundleURL: running?.bundleURL)
        var front: ArisNativeForeground?
        if !background {
            // Only in a gap in the user's typing and clicking (ArisNativeFocusGap), as every engine step.
            guard case .success(let borrowed) = ArisNativeForeground.take(pid: pid, window: window, clock: ArisNativeOwnerClock(), job: false) else { return .failure(.notInFront) }
            front = borrowed
        }
        guard focusedShows(pid, mark: mark) else {
            front?.restore()
            if let previous { makeMain(previous) }
            return .failure(.hostNotProven(name))
        }
        kept = true
        let route: ArisNativeInput.Route = background ? .process(pid) : .front
        let reach = ArisSessionReach(host: .window(bundle: bundle), tty: process.tty, pid: process.pid)
        reach.look = { focusedShows(pid, mark: mark) ? lookAt(window: window) : .focusMoved }
        reach.type = { text in
            guard focusedShows(pid, mark: mark), background || ArisFrontLive.frontPid() == pid else { return .focusMoved }
            ArisNativeInput.type(ArisPeekabooCommands.literal(text), route: route)
            return nil
        }
        reach.submit = {
            guard focusedShows(pid, mark: mark), background || ArisFrontLive.frontPid() == pid else { return .focusMoved }
            ArisNativeInput.press(36, route: route)
            return nil
        }
        reach.escape = {
            guard focusedShows(pid, mark: mark), background || ArisFrontLive.frontPid() == pid else { return .focusMoved }
            ArisNativeInput.press(53, route: route)
            return nil
        }
        reach.finish = {
            undo()
            if let previous, !CFEqual(previous, window) { makeMain(previous) }
            front?.restore()
        }
        return .success(reach)
    }

    // MARK: - Terminal (its tab by tty, selected in the background; keys to its process)

    static func terminal(process: ArisSessionProcess) -> Result<ArisSessionReach, ArisSessionStop> {
        guard AXIsProcessTrusted() else { return .failure(.noAccessibility) }
        let bundle = "com.apple.Terminal"
        guard let pid = hostPid(process, bundle: bundle), let script = ArisSessionScripts.terminalTab(process.tty),
              let found = ArisSessionHostsLive.osascript(script), found.hasPrefix("ok|") else { return .failure(.tabNotFound) }
        // "ok|<the tab that was selected in its window: its tty>"
        let wasSelected = String(found.dropFirst(3))
        let restoreTitle = ArisSessionScripts.terminalTitle(process.tty).flatMap(ArisSessionHostsLive.osascript)
        guard let (mark, undo) = mark(process.tty, restore: restoreTitle) else { return .failure(.tabNotFound) }
        var kept = false
        defer { if !kept { undo() } }
        guard let window = markedWindow(pid, mark: mark) else { return .failure(.notInFront) }
        let app = ArisAX.app(pid)
        let previous = ArisAX.element(app, kAXFocusedWindowAttribute as String)
        if !focusedShows(pid, mark: mark) {
            makeMain(window)
        }
        guard focusedShows(pid, mark: mark) else {
            if let previous { makeMain(previous) }
            return .failure(.notInFront)
        }
        kept = true
        let reach = ArisSessionReach(host: .terminalApp, tty: process.tty, pid: process.pid)
        reach.look = { focusedShows(pid, mark: mark) ? lookAt(window: window) : .focusMoved }
        reach.type = { text in
            guard focusedShows(pid, mark: mark) else { return .focusMoved }
            ArisNativeInput.type(ArisPeekabooCommands.literal(text), route: .process(pid))
            return nil
        }
        reach.submit = {
            guard focusedShows(pid, mark: mark) else { return .focusMoved }
            ArisNativeInput.press(36, route: .process(pid))
            return nil
        }
        reach.escape = {
            guard focusedShows(pid, mark: mark) else { return .focusMoved }
            ArisNativeInput.press(53, route: .process(pid))
            return nil
        }
        reach.finish = {
            undo()
            if ArisSessionProcesses.isTTY(wasSelected), wasSelected != process.tty, let back = ArisSessionScripts.terminalTab(wasSelected) {
                _ = ArisSessionHostsLive.osascript(back)
            }
            if let previous, !CFEqual(previous, window) { makeMain(previous) }
        }
        return .success(reach)
    }

    // MARK: - Warp (its focus link; keys only in front)

    /// Warp's tabs now: each tty under Warp with its focus link (its shell's or program's WARP_FOCUS_URL).
    static func warpTabs(pid: Int32) -> [String: String] {
        var tabs: [String: String] = [:]
        for row in ArisSessionLive.processRows() where row.tty != nil {
            guard let link = row.terminal["WARP_FOCUS_URL"].flatMap(ArisSessionHost.warpLink), let tty = row.tty,
                  ArisSessionLive.hostApp(of: row.pid)?.processIdentifier == pid else { continue }
            tabs[tty] = link
        }
        return tabs
    }

    static func warp(focus: String?, process: ArisSessionProcess) -> Result<ArisSessionReach, ArisSessionStop> {
        guard AXIsProcessTrusted() else { return .failure(.noAccessibility) }
        let bundle = ["dev.warp.Warp-Stable", "dev.warp.Warp-Preview", "dev.warp.Warp"].first { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }
        guard let bundle, let pid = hostPid(process, bundle: bundle), let focus, let link = URL(string: focus) else { return .failure(.hostNotProven("Warp")) }
        // Which tab Warp shows now (to put it back): every tab marked, the focused window's title read.
        let tabs = warpTabs(pid: pid)
        var marks: [String: String] = [:]
        for tty in tabs.keys where tty != process.tty {
            let mark = ArisSessionMark.make()
            if ArisSessionLive.write(ArisSessionMark.marking(mark), tty: tty) { marks[tty] = mark }
        }
        Thread.sleep(forTimeInterval: 0.3)
        let shown = ArisAX.element(ArisAX.app(pid), kAXFocusedWindowAttribute as String).flatMap { ArisAX.string($0, kAXTitleAttribute as String) }
        let original = marks.first { ArisSessionMark.shows(shown, mark: $0.value) }?.key
        for tty in marks.keys { _ = ArisSessionLive.write(ArisSessionMark.unmarking(restore: nil), tty: tty) }
        guard let (mark, undo) = mark(process.tty) else { return .failure(.tabNotFound) }
        var kept = false
        defer { if !kept { undo() } }
        let previousFront = ArisFrontLive.frontPid()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(link, configuration: configuration, completionHandler: nil)
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline, !(ArisFrontLive.frontPid() == pid && focusedShows(pid, mark: mark)) { Thread.sleep(forTimeInterval: 0.05) }
        let turn = ArisNativeForeground(previousPid: previousFront, previousWindow: nil, targetPid: pid, otherDisplay: false)
        func putBack() {
            if let original, original != process.tty, let back = tabs[original].flatMap(URL.init(string:)) {
                NSWorkspace.shared.open(back)
                Thread.sleep(forTimeInterval: 0.4)
            }
            turn.restore()
        }
        guard ArisFrontLive.frontPid() == pid, focusedShows(pid, mark: mark), let window = ArisAX.element(ArisAX.app(pid), kAXFocusedWindowAttribute as String) else {
            putBack()
            return .failure(.notInFront)
        }
        kept = true
        let reach = ArisSessionReach(host: .warp(focus: focus), tty: process.tty, pid: process.pid)
        let ready = { ArisFrontLive.frontPid() == pid && focusedShows(pid, mark: mark) }
        reach.look = { ready() ? lookAt(window: window) : .focusMoved }
        reach.type = { text in
            guard ready() else { return .focusMoved }
            ArisNativeInput.type(ArisPeekabooCommands.literal(text), route: .front)
            return nil
        }
        reach.submit = {
            guard ready() else { return .focusMoved }
            ArisNativeInput.press(36, route: .front)
            return nil
        }
        reach.escape = {
            guard ready() else { return .focusMoved }
            ArisNativeInput.press(53, route: .front)
            return nil
        }
        reach.finish = {
            undo()
            putBack()
        }
        return .success(reach)
    }

    // MARK: - An editor's terminal (VS Code, Cursor, Antigravity, Windsurf/Devin)

    /// The element whose own text is the mark (an editor's terminal tab shows its title).
    static func markedElement(_ root: AXUIElement, mark: String) -> AXUIElement? {
        var queue = [root]
        var index = 0
        while index < queue.count, index < 4_000 {
            let element = queue[index]
            index += 1
            for name in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
                if let text = ArisAX.string(element, name as String), ArisSessionMark.shows(text, mark: mark) { return element }
            }
            queue += ArisAX.children(element)
        }
        return nil
    }

    /// The text input (an editor's terminal input) whose description carries the mark.
    static func markedInput(_ root: AXUIElement, mark: String) -> AXUIElement? {
        var queue = [root]
        var index = 0
        while index < queue.count, index < 8_000 {
            let element = queue[index]
            index += 1
            if [kAXTextFieldRole as String, kAXTextAreaRole as String].contains(ArisAX.role(element)),
               ArisSessionMark.shows(ArisAX.string(element, kAXDescriptionAttribute as String), mark: mark) { return element }
            queue += ArisAX.children(element)
        }
        return nil
    }

    static func editor(bundle: String, process: ArisSessionProcess, session: ArisLiveSession) -> Result<ArisSessionReach, ArisSessionStop> {
        let name = ArisSessionHost.editor(bundle: bundle).name
        guard AXIsProcessTrusted() else { return .failure(.noAccessibility) }
        guard let pid = hostPid(process, bundle: bundle) else { return .failure(.hostNotProven(name)) }
        let running = NSRunningApplication(processIdentifier: pid)
        if ArisAX.enableWebTree(pid: pid, bundleURL: running?.bundleURL) { Thread.sleep(forTimeInterval: 1.0) }
        // The terminal the user had active (to put back): the one whose input the editor shows ("Terminal N, …").
        let original = activeTerminalNumber(pid: pid)
        // An editor's terminal can't pop a title: its own comes back by an empty one (it shows its program's name).
        guard let (mark, undo) = mark(process.tty, restore: "") else { return .failure(.hostNotProven(name)) }
        var kept = false
        defer { if !kept { undo() } }
        Thread.sleep(forTimeInterval: 0.4)
        // The one window holding the terminal input whose own description carries the mark (VS Code names its terminal's
        // input "Terminal N, <its title> …": measured in the VM, 2026-11-16).
        // A terminal that isn't the active one shows only its tab ("Terminal N <its title>"): with the editor in front,
        // that tab is pressed first (pressed in the background, an editor raised its window: VM, 2026-11-16).
        let holders = windows(pid).filter { markedElement($0, mark: mark) != nil }
        guard holders.count == 1, let window = holders.first else { return .failure(.hostNotProven(name)) }
        guard case .success(let turn) = ArisNativeForeground.take(pid: pid, window: window, clock: ArisNativeOwnerClock(), job: false) else { return .failure(.notInFront) }
        var found = markedInput(window, mark: mark)
        if found == nil, let row = element(in: window, descriptionContaining: mark) {
            _ = ArisNativeInput.axPress(row)
            let deadline = Date().addingTimeInterval(1.5)
            while found == nil, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
                found = markedInput(window, mark: mark)
            }
        }
        guard let input = found else {
            turn.restore()
            return .failure(.hostNotProven(name))
        }
        // The keyboard put in that terminal's own input (the app is in front now, so it keeps the focus).
        AXUIElementSetAttributeValue(input, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        Thread.sleep(forTimeInterval: 0.3)
        /// The keyboard is in the marked terminal's input, the app in front.
        func terminalFocused() -> Bool {
            guard ArisFrontLive.frontPid() == pid, let focused = ArisAX.focused(pid: pid) else { return false }
            return ArisSessionMark.shows(ArisAX.string(focused, kAXDescriptionAttribute as String), mark: mark)
        }
        guard terminalFocused() else {
            turn.restore()
            return .failure(.hostNotProven(name))
        }
        kept = true
        let area: CGRect? = {
            var current: AXUIElement? = input
            for _ in 0..<10 {
                guard let element = current else { return nil }
                if let frame = ArisAX.frame(element), frame.height > 90, frame.width > 200 { return frame }
                current = ArisAX.element(element, kAXParentAttribute as String)
            }
            return nil
        }()
        let reach = ArisSessionReach(host: .editor(bundle: bundle), tty: process.tty, pid: process.pid)
        reach.look = { terminalFocused() ? (area.map { lookAt(window: window, crop: $0) } ?? .screenNotIdle) : .focusMoved }
        reach.type = { text in
            guard terminalFocused() else { return .focusMoved }
            ArisNativeInput.type(ArisPeekabooCommands.literal(text), route: .front)
            return nil
        }
        reach.submit = {
            guard terminalFocused() else { return .focusMoved }
            ArisNativeInput.press(36, route: .front)
            return nil
        }
        reach.escape = {
            guard terminalFocused() else { return .focusMoved }
            ArisNativeInput.press(53, route: .front)
            return nil
        }
        reach.finish = {
            undo()
            // Its own terminal tab pressed again when another one was active before ("Terminal N" in the tabs list).
            if let original, original != terminalNumber(ArisAX.string(input, kAXDescriptionAttribute as String)),
               let row = element(in: window, descriptionPrefix: "Terminal \(original) ") {
                _ = ArisNativeInput.axPress(row)
                Thread.sleep(forTimeInterval: 0.2)
            }
            turn.restore()
        }
        return .success(reach)
    }

    /// "Terminal 3, zsh …" → 3: the number an editor gives a terminal's input.
    static func terminalNumber(_ description: String?) -> Int? {
        guard let description, let match = description.range(of: #"^Terminal ([0-9]{1,3}),"#, options: .regularExpression) else { return nil }
        return Int(description[match].dropFirst("Terminal ".count).dropLast())
    }

    /// The editor's active terminal now: the one terminal input it shows, by its number; nil when it can't be told.
    static func activeTerminalNumber(pid: Int32) -> Int? {
        var numbers: Set<Int> = []
        for window in windows(pid) {
            var queue = [window]
            var index = 0
            while index < queue.count, index < 8_000 {
                let element = queue[index]
                index += 1
                if [kAXTextFieldRole as String, kAXTextAreaRole as String].contains(ArisAX.role(element)),
                   let number = terminalNumber(ArisAX.string(element, kAXDescriptionAttribute as String)) { numbers.insert(number) }
                queue += ArisAX.children(element)
            }
        }
        return numbers.count == 1 ? numbers.first : nil
    }

    /// The first element under `root` whose own description carries `text` (an editor's terminal tab).
    static func element(in root: AXUIElement, descriptionContaining text: String) -> AXUIElement? {
        var queue = [root]
        var index = 0
        while index < queue.count, index < 8_000 {
            let element = queue[index]
            index += 1
            if (ArisAX.string(element, kAXDescriptionAttribute as String) ?? "").contains(text) { return element }
            queue += ArisAX.children(element)
        }
        return nil
    }

    /// The first element under `root` whose description starts with `prefix`.
    static func element(in root: AXUIElement, descriptionPrefix prefix: String) -> AXUIElement? {
        var queue = [root]
        var index = 0
        while index < queue.count, index < 8_000 {
            let element = queue[index]
            index += 1
            if (ArisAX.string(element, kAXDescriptionAttribute as String) ?? "").hasPrefix(prefix) { return element }
            queue += ArisAX.children(element)
        }
        return nil
    }
}
