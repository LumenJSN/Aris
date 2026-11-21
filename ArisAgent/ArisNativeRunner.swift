//
//  ArisNativeRunner.swift
//  aris-agent
//
//  Aris's own computer-use engine, in the agent's process, behind the same seam Peekaboo had (ArisDesktopRunning): the
//  controller builds the same calls (ArisPeekabooCommands) and reads the same answers (ArisDesktopEnvelope), so the gate,
//  the cards, the stale-look guard and every read-back stay exactly as they were. Underneath, every call names its app's
//  process and window:
//  - a look reads the window's Accessibility tree without bringing it forward (an Electron or Chromium app's tree
//    switched on first), and, when asked, a picture of that window alone (ArisNativeShot);
//  - a click is the element's own action (AXPress), a field is focused by Accessibility, a value is set by it;
//  - keys and text go to the app's process (CGEventPostToPid); an app measured not to take them in the background
//    (Chromium, Electron, Warp) gets a brief turn in front, and the app and window the user had in front come back after;
//  - the user's pointer never moves, except for the real click the controller asks for with --foreground (put back at once).
//  A background job never gets a turn in front (`job`): the call says so instead.
//

import AppKit
import ApplicationServices
import Carbon
import Foundation

/// One call's circumstances the argv doesn't carry.
struct ArisNativeContext {
    /// A background job: it waits longer for a gap in the user's input before a brief turn in front (ArisNativeFocusGap),
    /// and never brings a window forward on its own (`--foreground`, a drag, a file panel's folder).
    var job = false
    /// The turn's desktop-lock owner: its own synthetic input never counts as the user's.
    var owner: String? = nil
    /// When the call began.
    var began = Date()
    /// A mail, chat or call app: text never goes in by Accessibility there (ArisNativeLadder).
    var sending = false
    /// How long the call may take in all (Accessibility on an app that doesn't answer: ArisAXBudget).
    var timeout: TimeInterval = ArisDesktopEngine.runTimeout
}

final class ArisNativeRunner: ArisDesktopRunning {
    static let shared = ArisNativeRunner()

    /// One look's live elements, by its snapshot id (`ps1_` and 32 hex digits, as Peekaboo's).
    struct Snapshot {
        let pid: Int32
        let window: Int
        let windowElement: AXUIElement
        let live: [String: AXUIElement]
        let taken: Date
    }

    private let lock = NSLock()
    private var snapshots: [String: Snapshot] = [:]
    /// A field a click focused in an app that takes keys only in front: focused again when it comes forward for them.
    private var pendingFocus: [Int32: (element: AXUIElement, window: Int)] = [:]
    private var order: [String] = []
    /// The most looks kept (the oldest go first; the controller asks again for a stale one).
    static let keep = 96

    func run(_ binary: URL, _ arguments: [String], stateFolder: URL, timeout: TimeInterval) -> (status: Int32, output: Data) {
        run(arguments, context: ArisNativeContext(timeout: timeout))
    }

    func run(_ arguments: [String], context: ArisNativeContext) -> (status: Int32, output: Data) {
        let call = ArisNativeCall(arguments)
        // An app that doesn't answer Accessibility at all is said so at once, before any tree walk or key (it could
        // hold every call for the default six seconds each).
        if let pid = Self.pid(of: call), ArisAX.unresponsive(pid: pid) {
            let reply = ArisNativeReply.failure(ArisAXBudget.notRespondingCode, ArisAXBudget.notRespondingLine, retrySafe: true)
            return (1, reply.json())
        }
        let reply: ArisNativeReply
        switch (call.verb, call.positional.first) {
        case ("see", _): reply = see(call, context: context)
        case ("click", _): reply = click(call, context: context)
        case ("type", _): reply = type(call, context: context)
        case ("set-value", _): reply = setValue(call)
        case ("press", _): reply = press(call, context: context)
        case ("scroll", _): reply = scroll(call)
        case ("drag", _): reply = drag(call, context: context)
        case ("menu", "list"): reply = ArisNativeApps.menuList(call)
        case ("menu", "click"): reply = ArisNativeApps.menuClick(call)
        case ("dialog", "list"): reply = ArisNativeApps.dialogList(call)
        case ("dialog", "click"): reply = ArisNativeApps.dialogClick(call)
        case ("dialog", "input"): reply = ArisNativeApps.dialogInput(call)
        case ("dialog", "file"): reply = ArisNativeApps.dialogFile(call, context: context, runner: self)
        case ("window", "list"): reply = ArisNativeApps.windowList(call)
        case ("window", _): reply = ArisNativeApps.window(call, context: context)
        case ("app", _): reply = ArisNativeApps.app(call, context: context)
        case ("dock", "list"): reply = ArisNativeApps.dockList()
        default: reply = .failure("UNSUPPORTED", "Aris's engine doesn't know `\(call.verb)`")
        }
        return (reply.success ? 0 : 1, reply.json())
    }

    // MARK: - Snapshots

    func keep(_ snapshot: Snapshot) -> String {
        let id = "ps1_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        lock.withLock {
            snapshots[id] = snapshot
            order.append(id)
            while order.count > Self.keep { snapshots[order.removeFirst()] = nil }
        }
        return id
    }

    func snapshot(_ id: String?) -> Snapshot? {
        guard let id else { return nil }
        return lock.withLock { snapshots[id] }
    }

    /// A snapshot's element by its id, with its snapshot.
    func element(_ call: ArisNativeCall, key: String = "--on") -> (Snapshot, AXUIElement)? {
        guard let snapshot = snapshot(call.value("--snapshot")), let id = call.value(key), let element = snapshot.live[id] else { return nil }
        return (snapshot, element)
    }

    // MARK: - Look

    /// The process a call is for (its window's, its snapshot's or its --app's), for the responsiveness check.
    static func pid(of call: ArisNativeCall) -> Int32? {
        if let window = call.int("--window-id") { return ArisNativeApps.owner(ofWindow: window) }
        if let snapshot = shared.snapshot(call.value("--snapshot")) { return snapshot.pid }
        return ArisNativeApps.pid(call)
    }

    func see(_ call: ArisNativeCall, context: ArisNativeContext) -> ArisNativeReply {
        guard AXIsProcessTrusted() else { return .failure("PERMISSION_DENIED", "Accessibility isn't granted") }
        guard let id = call.int("--window-id"), let pid = ArisNativeApps.owner(ofWindow: id) else { return .failure("WINDOW_NOT_FOUND", "no such window") }
        let app = NSRunningApplication(processIdentifier: pid)
        if ArisAX.enableWebTree(pid: pid, bundleURL: app?.bundleURL) { usleep(700_000) }
        guard let window = ArisAX.window(pid: pid, id: id) else { return .failure("WINDOW_NOT_FOUND", "the window isn't one Accessibility shows") }
        // The walk has a budget: each element answers within ArisAXBudget.perCall, the whole look within its share of
        // the call's time, and an app that stops answering ends it with a clear reason (never a hang).
        let budget = ArisAXBudget(limit: min(ArisAXBudget.lookLimit, context.timeout))
        var tree = ArisNativeTree.read(window: window, pid: pid, budget: budget)
        // A web app's tree can still be filling the first time: once more after a moment when it came back nearly empty.
        if tree.elements.count < 4, !budget.unresponsive, ArisAX.isWebShell(bundleURL: app?.bundleURL) {
            usleep(800_000)
            tree = ArisNativeTree.read(window: window, pid: pid, budget: ArisAXBudget(limit: min(ArisAXBudget.lookLimit, context.timeout)))
        }
        if budget.unresponsive, tree.elements.isEmpty {
            return .failure(ArisAXBudget.notRespondingCode, ArisAXBudget.notRespondingLine, retrySafe: true)
        }
        let snapshotId = keep(Snapshot(pid: pid, window: id, windowElement: window, live: tree.live, taken: Date()))
        let subrole = ArisAX.string(window, kAXSubroleAttribute as String) ?? ""
        var data: [String: Any] = ["snapshot_id": snapshotId, "application_name": app?.localizedName ?? "", "window_title": ArisAX.string(window, kAXTitleAttribute as String) ?? "",
                                   "is_dialog": ["AXDialog", "AXSystemDialog", "AXFloatingWindow"].contains(subrole), "ui_elements": tree.elements,
                                   "engine": "aris"]
        if let frame = tree.focusedFrame {
            data["focused_element"] = ["role": tree.focusedRole ?? "", "frame": [[frame.minX, frame.minY], [frame.width, frame.height]]]
        } else if let role = tree.focusedRole {
            data["focused_element"] = ["role": role]
        }
        if tree.truncated || budget.exhausted { data["truncated"] = true }
        if let path = call.value("--path") {
            guard ArisNativeShot.capture(window: id, to: path) else { return .failure(ArisNativeShot.failedCode, "the window's picture couldn't be taken") }
            data["screenshot_raw"] = path
            if call.has("--annotate"), let frame = ArisAX.frame(window) {
                let annotated = (path as NSString).deletingPathExtension + "-annotated.png"
                let boxes: [(number: Int, box: CGRect)] = tree.elements.compactMap { entry in
                    guard let id = entry["id"] as? String, let number = Int(id.dropFirst(5)), let bounds = entry["bounds"] as? [String: CGFloat],
                          entry["is_actionable"] as? Bool == true || ["textField", "textArea"].contains(entry["role"] as? String ?? "") else { return nil }
                    return (number, CGRect(x: bounds["x"] ?? 0, y: bounds["y"] ?? 0, width: bounds["width"] ?? 0, height: bounds["height"] ?? 0))
                }
                if ArisNativeShot.annotate(source: path, to: annotated, frame: frame, elements: boxes) { data["screenshot_annotated"] = annotated }
            }
        }
        return ArisNativeReply(success: true, data: data, window: id, pid: pid)
    }

    // MARK: - Clicks

    func click(_ call: ArisNativeCall, context: ArisNativeContext) -> ArisNativeReply {
        let double = call.has("--double"), right = call.has("--right"), foreground = call.has("--foreground")
        if let at = call.point("--at") { return clickAt(at, call: call, double: double, right: right, foreground: foreground, context: context) }
        guard let (snapshot, element) = element(call) else { return .failure("SNAPSHOT_NOT_FOUND", "that element's look is gone; look again", retrySafe: true) }
        let window = snapshot.window, pid = snapshot.pid
        let role = ArisAX.role(element)
        if foreground {
            guard !context.job else { return .failure("FOREGROUND_REFUSED", "a background job never brings a window forward", retrySafe: true) }
            guard let frame = ArisAX.frame(element) else { return .failure("NO_FRAME", "the element has no place on screen", retrySafe: true) }
            let turn: ArisNativeForeground
            switch front(pid: pid, window: snapshot.windowElement, context: context) {
            case .failure(let refused): return refused
            case .success(let made): turn = made
            }
            ArisNativeInput.pointerClick(at: CGPoint(x: frame.midX, y: frame.midY), double: double, right: right)
            usleep(120_000)
            turn.restore()
            return .done(window: window, pid: pid, extra: ["delivery": "foreground", "other_display": turn.otherDisplay])
        }
        // The next way after an Accessibility press that changed nothing: a click posted to the process, nothing else.
        if call.value("--input-strategy") == ArisPeekabooCommands.postedStrategy {
            guard let frame = ArisAX.frame(element), frame.width > 0 else { return .failure("NO_FRAME", "the element has no place on screen", retrySafe: true) }
            ArisNativeInput.postClick(pid: pid, at: CGPoint(x: frame.midX, y: frame.midY), window: window, double: double, right: right)
            return .done(window: window, pid: pid, extra: ["delivery": "posted-click"])
        }
        // A field: focused by Accessibility (a click's effect on it), in the background.
        if !right, !double, ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"].contains(role), ArisAX.settable(element, kAXFocusedAttribute as String) {
            if AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success {
                // An app that takes keys only in front (Electron, Chromium) doesn't keep a background focus: the field is
                // focused again once it is in front for the keys (VM bench vscode_edit: the text went to the chat box).
                let app = NSRunningApplication(processIdentifier: pid)
                if !ArisNativeInput.takesBackgroundKeys(bundle: app?.bundleIdentifier, bundleURL: app?.bundleURL) {
                    lock.withLock { pendingFocus[pid] = (element, window) }
                }
                return .done(window: window, pid: pid, extra: ["delivery": "ax-focus"])
            }
        }
        if right, ArisAX.actions(element).contains("AXShowMenu"), AXUIElementPerformAction(element, "AXShowMenu" as CFString) == .success {
            return .done(window: window, pid: pid, extra: ["delivery": "ax-showmenu"])
        }
        if !right, !double, ArisNativeInput.axPress(element) { return .done(window: window, pid: pid, extra: ["delivery": "ax-press"]) }
        // A list row (or the text, image or cell inside one): selected by Accessibility, as a click on it selects it
        // (VM bench, 2026-11-16: SwiftUI rows and their text have no action of their own).
        if !right, let delivery = ArisNativeInput.selectOrPressAncestor(element) {
            return .done(window: window, pid: pid, extra: ["delivery": delivery])
        }
        if call.value("--input-strategy") == "actionOnly" {
            return .failure("NO_ACTION", "No pressable accessibility element: the control has no action of its own", retrySafe: true)
        }
        guard let frame = ArisAX.frame(element), frame.width > 0 else { return .failure("NO_FRAME", "No pressable accessibility element there", retrySafe: true) }
        ArisNativeInput.postClick(pid: pid, at: CGPoint(x: frame.midX, y: frame.midY), window: window, double: double, right: right)
        return .done(window: window, pid: pid, extra: ["delivery": "posted-click"])
    }

    /// `--at x,y`: a point inside the window (window-relative); in the background the element there is pressed, or
    /// (with --foreground) a real pointer click is made there and the pointer put back.
    private func clickAt(_ point: CGPoint, call: ArisNativeCall, double: Bool, right: Bool, foreground: Bool, context: ArisNativeContext) -> ArisNativeReply {
        let snapshot = snapshot(call.value("--snapshot"))
        guard let windowId = call.int("--window-id") ?? snapshot?.window, let pid = snapshot?.pid ?? ArisNativeApps.owner(ofWindow: windowId),
              let window = snapshot?.windowElement ?? ArisAX.window(pid: pid, id: windowId), let frame = ArisAX.frame(window) else {
            return .failure("WINDOW_NOT_FOUND", "no such window", retrySafe: true)
        }
        let global = CGPoint(x: frame.minX + point.x, y: frame.minY + point.y)
        if foreground {
            guard !context.job else { return .failure("FOREGROUND_REFUSED", "a background job never brings a window forward", retrySafe: true) }
            let turn: ArisNativeForeground
            switch front(pid: pid, window: window, context: context) {
            case .failure(let refused): return refused
            case .success(let made): turn = made
            }
            ArisNativeInput.pointerClick(at: global, double: double, right: right)
            usleep(120_000)
            turn.restore()
            return .done(window: windowId, pid: pid, extra: ["delivery": "foreground"])
        }
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(ArisAX.app(pid), Float(global.x), Float(global.y), &hit) == .success, let hit else {
            return .failure("NO_ELEMENT", "No pressable accessibility element at that spot", retrySafe: true)
        }
        // The element there, or the nearest of its parents that acts.
        var current: AXUIElement? = hit
        for _ in 0..<6 {
            guard let element = current else { break }
            if !double, !right, ArisNativeInput.axPress(element) { return .done(window: windowId, pid: pid, extra: ["delivery": "ax-press"]) }
            current = ArisAX.element(element, kAXParentAttribute as String)
        }
        return .failure("NO_ELEMENT", "No pressable accessibility element at that spot", retrySafe: true)
    }

    // MARK: - Keys and text

    /// A brief turn in front for `pid`, only in a gap in the user's input (ArisNativeFocusGap); else why not, as the
    /// controller reads it (nothing was sent: safe to try again).
    func front(pid: Int32, window: AXUIElement?, context: ArisNativeContext) -> Result<ArisNativeForeground, ArisNativeReply> {
        switch ArisNativeForeground.take(pid: pid, window: window, clock: ArisNativeOwnerClock(owner: context.owner, began: context.began), job: context.job) {
        case .success(let turn): return .success(turn)
        case .failure(.busy(let waited)): return .failure(.failure(ArisNativeFocusGap.busyCode, ArisNativeFocusGap.busyLine(waited: waited), retrySafe: true))
        case .failure(.failed): return .failure(.failure("FOREGROUND_FAILED", "the window couldn't be brought forward", retrySafe: true))
        }
    }

    /// The keyboard focus of `pid` is in its window `window` (or can't be told while the app is in front): background
    /// keys reach it.
    static func focusIn(pid: Int32, window: Int) -> Bool {
        let focusedWindow = ArisAX.focusedWindowId(pid: pid)
        return focusedWindow == window || focusedWindow == nil && ArisFrontLive.frontPid() == pid
    }

    /// Where keys for `pid`'s window `window` go now: its process (background), or after a brief turn in front in a gap
    /// in the user's input (a job too: it waits longer for the gap, ArisNativeFocusGap). `send` gets the route.
    private func deliver(pid: Int32, window: Int, windowElement: AXUIElement?, forceFront: Bool, context: ArisNativeContext,
                         _ send: (ArisNativeInput.Route) -> Void) -> ArisNativeReply {
        let app = NSRunningApplication(processIdentifier: pid)
        let background = !forceFront && ArisNativeInput.takesBackgroundKeys(bundle: app?.bundleIdentifier, bundleURL: app?.bundleURL)
        if background, Self.focusIn(pid: pid, window: window) {
            send(.process(pid))
            return .done(window: window, pid: pid, extra: ["delivery": "background"])
        }
        let target = windowElement ?? ArisAX.window(pid: pid, id: window)
        let clock = ArisNativeOwnerClock(owner: context.owner, began: context.began)
        // Twice at most: the user's input during the raise gives the front back, and the step waits for a gap again.
        for _ in 0..<2 {
            let turn: ArisNativeForeground
            switch front(pid: pid, window: target, context: context) {
            case .failure(let refused): return refused
            case .success(let made): turn = made
            }
            // In front now: the field a click focused in the background gets the keyboard again (only in that window).
            if let pending = lock.withLock({ pendingFocus.removeValue(forKey: pid) }), pending.window == window {
                AXUIElementSetAttributeValue(pending.element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                usleep(150_000)
            }
            // The window that has the keyboard must be the one meant.
            let now = ArisAX.focusedWindowId(pid: pid)
            guard now == nil || now == window else {
                turn.restore()
                return .failure("FOCUS_ELSEWHERE", "the keyboard focus belongs to a different window (a panel or sheet does not hold it)", retrySafe: true)
            }
            if turn.inputSinceRaise(clock) {
                turn.restore()
                continue
            }
            send(.front)
            usleep(150_000)
            turn.restore()
            return .done(window: window, pid: pid, extra: ["delivery": "foreground", "other_display": turn.otherDisplay])
        }
        return .failure(ArisNativeFocusGap.busyCode, ArisNativeFocusGap.busyLine(waited: ArisNativeFocusGap.limit), retrySafe: true)
    }

    /// Text into the focused field of the window, by the ladder (ArisNativeLadder): Accessibility, background keys, the
    /// pasteboard, then a brief turn in front; each rung read back before the next, what an app ignored remembered.
    func type(_ call: ArisNativeCall, context: ArisNativeContext) -> ArisNativeReply {
        guard let text = call.value("--text"), let window = call.int("--window-id"), let pid = ArisNativeApps.owner(ofWindow: window) else {
            return .failure("WINDOW_NOT_FOUND", "no such window", retrySafe: true)
        }
        if IsSecureEventInputEnabled() { return .failure("SECURE_INPUT", "secure input is on", retrySafe: true) }
        let app = NSRunningApplication(processIdentifier: pid)
        let bundle = app?.bundleIdentifier
        let pieces = ArisNativeInput.pieces(text)
        let measured = !ArisNativeInput.takesBackgroundKeys(bundle: bundle, bundleURL: app?.bundleURL, memory: memory)
        let profile = ArisNativeLadder.Profile(bundle: bundle, dropsBackgroundKeys: measured, inputMethod: !ArisKeyMethod.unicodeEventsTypeText(ArisKeyboardLive.state()),
                                               sending: context.sending, focusElsewhere: !Self.focusIn(pid: pid, window: window), frontAllowed: true)
        let rungs: [ArisNativeRung] = call.has("--foreground") ? [.front] : ArisNativeLadder.plan(pieces, profile: profile, learned: memory.failed(bundle))
        let io = ArisNativeTextLive(pid: pid, window: window, context: context, pendingFocus: { [weak self] in
            guard let self else { return nil }
            return self.lock.withLock { () -> AXUIElement? in
                guard let pending = self.pendingFocus[pid], pending.window == window else { return nil }
                self.pendingFocus[pid] = nil
                return pending.element
            }
        })
        let outcome = ArisNativeLadder.run(pieces, rungs: rungs, io: io, memory: memory, bundle: bundle, profile: profile)
        return ArisNativeLadder.reply(outcome, window: window, pid: pid)
    }

    /// The ladder's memory of what each app ignored (a seam for the tests).
    var memory = ArisNativeInputMemory.shared

    func press(_ call: ArisNativeCall, context: ArisNativeContext) -> ArisNativeReply {
        let keyboard = ArisKeyboardLive.state()
        let chords = call.positional.compactMap { ArisNativeInput.chord($0, keyboard: keyboard) }
        guard !chords.isEmpty, chords.count == call.positional.count else { return .failure("INVALID_KEY", "a key it doesn't know", retrySafe: true) }
        let snapshot = snapshot(call.value("--snapshot"))
        guard let window = call.int("--window-id") ?? snapshot?.window, let pid = snapshot?.pid ?? ArisNativeApps.owner(ofWindow: window) else {
            return .failure("WINDOW_NOT_FOUND", "no such window", retrySafe: true)
        }
        // A character key alone would be composed by an input method: pressed with the ASCII-capable source selected.
        let composes = chords.contains { ArisKeyMethod.needsASCIISource(character: $0.character, flags: $0.flags, keyboard: keyboard) }
        return deliver(pid: pid, window: window, windowElement: snapshot?.windowElement, forceFront: call.has("--foreground"), context: context) { route in
            let keys = { for chord in chords { ArisNativeInput.press(chord.key, flags: chord.flags, route: route) } }
            if composes { ArisNativeKeyboardSwitch.withASCII(keys) } else { keys() }
        }
    }

    func setValue(_ call: ArisNativeCall) -> ArisNativeReply {
        guard let (snapshot, element) = element(call), let value = call.value("--value") else {
            return .failure("SNAPSHOT_NOT_FOUND", "that element's look is gone; look again", retrySafe: true)
        }
        // A number for a control whose value is one (a slider, a stepper): set as a number.
        let current = ArisAX.value(element, kAXValueAttribute as String)
        let typed: CFTypeRef = current is NSNumber && !(current is String) ? (Double(value.trimmingCharacters(in: .whitespaces)).map { NSNumber(value: $0) } ?? value as NSString) : value as NSString
        var result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, typed)
        // A slider that refuses a value is stepped to it by its own increment and decrement actions.
        if result != .success, let wanted = (typed as? NSNumber)?.doubleValue, ArisAX.actions(element).contains("AXIncrement") {
            result = ArisNativeInput.step(element, to: wanted) ? .success : result
        }
        guard result == .success || ArisAX.settable(element, kAXValueAttribute as String) else {
            return .failure("NOT_SETTABLE", "that control's value can't be set", retrySafe: true)
        }
        guard result == .success else { return .failure("SET_FAILED", "the app refused the value (\(result.rawValue))", retrySafe: true) }
        return .done(window: snapshot.window, pid: snapshot.pid, extra: ["delivery": "ax-value"])
    }

    // MARK: - Scroll and drag

    func scroll(_ call: ArisNativeCall) -> ArisNativeReply {
        guard let (snapshot, element) = element(call) else { return .failure("SNAPSHOT_NOT_FOUND", "that element's look is gone; look again", retrySafe: true) }
        let direction = call.value("--direction") ?? "down"
        let amount = Int32(max(1, min(50, call.int("--amount") ?? 5)))
        // A scroll bar of its own (or of the scroll area it sits in): moved by Accessibility.
        if ArisNativeApps.scrollByBar(element, direction: direction, lines: Int(amount)) {
            return .done(window: snapshot.window, pid: snapshot.pid, extra: ["delivery": "ax-scrollbar"])
        }
        guard let frame = ArisAX.frame(element) else { return .failure("NO_FRAME", "the element has no place on screen", retrySafe: true) }
        let dy: Int32 = direction == "up" ? amount : direction == "down" ? -amount : 0
        let dx: Int32 = direction == "left" ? amount : direction == "right" ? -amount : 0
        ArisNativeInput.postScroll(pid: snapshot.pid, at: CGPoint(x: frame.midX, y: frame.midY), dx: dx, dy: dy)
        return .done(window: snapshot.window, pid: snapshot.pid, extra: ["delivery": "posted-scroll"])
    }

    func drag(_ call: ArisNativeCall, context: ArisNativeContext) -> ArisNativeReply {
        guard let (snapshot, from) = element(call, key: "--from"), let to = snapshot.live[call.value("--to") ?? ""],
              let start = ArisAX.frame(from), let end = ArisAX.frame(to) else { return .failure("SNAPSHOT_NOT_FOUND", "that element's look is gone; look again", retrySafe: true) }
        guard !context.job else { return .failure("FOREGROUND_REFUSED", "a drag needs the window in front, and a background job never brings one forward", retrySafe: true) }
        let turn: ArisNativeForeground
        switch front(pid: snapshot.pid, window: snapshot.windowElement, context: context) {
        case .failure(let refused): return refused
        case .success(let made): turn = made
        }
        defer { turn.restore() }
        let before = CGEvent(source: nil)?.location
        let source = CGEventSource(stateID: .privateState)
        let a = CGPoint(x: start.midX, y: start.midY), b = CGPoint(x: end.midX, y: end.midY)
        CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: a, mouseButton: .left)?.post(tap: .cghidEventTap)
        for step in 1...12 {
            let t = CGFloat(step) / 12
            CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), mouseButton: .left)?
                .post(tap: .cghidEventTap)
            usleep(16_000)
        }
        CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: b, mouseButton: .left)?.post(tap: .cghidEventTap)
        if let before { CGWarpMouseCursorPosition(before) }
        return .done(window: snapshot.window, pid: snapshot.pid, extra: ["delivery": "foreground"])
    }
}

/// One call's words: the verb, its plain words, and its flags (`--flag value` and `--flag=value` alike). Pure.
struct ArisNativeCall {
    let verb: String
    let positional: [String]
    private let flags: [String: String]
    private let switches: Set<String>

    static let valued: Set<String> = ["--window-id", "--path", "--on", "--snapshot", "--at", "--input-strategy", "--text", "--value", "--direction",
                                      "--amount", "--from", "--to", "--app", "--button", "--field", "--name", "--select", "--x", "--y", "--width",
                                      "--height", "--bundle-id"]

    init(_ arguments: [String]) {
        verb = arguments.first ?? ""
        var positional: [String] = [], flags: [String: String] = [:], switches: Set<String> = []
        var index = 1
        var plain = false
        while index < arguments.count {
            let word = arguments[index]
            // `--`: every word after it is a plain word, never a flag (a caller's keys can't aim the call elsewhere).
            if plain {
                positional.append(word)
                index += 1
                continue
            }
            if word == "--" {
                plain = true
                index += 1
                continue
            }
            if word.hasPrefix("--"), let equals = word.firstIndex(of: "=") {
                flags[String(word[..<equals])] = String(word[word.index(after: equals)...])
            } else if Self.valued.contains(word), index + 1 < arguments.count {
                flags[word] = arguments[index + 1]
                index += 1
            } else if word.hasPrefix("--") {
                switches.insert(word)
            } else {
                positional.append(word)
            }
            index += 1
        }
        self.positional = positional
        self.flags = flags
        self.switches = switches
    }

    func value(_ flag: String) -> String? { flags[flag] }
    func int(_ flag: String) -> Int? { flags[flag].flatMap { Int($0) } }
    func has(_ flag: String) -> Bool { switches.contains(flag) }

    /// "x,y".
    func point(_ flag: String) -> CGPoint? {
        let parts = (flags[flag] ?? "").split(separator: ",").compactMap { Double($0) }
        return parts.count == 2 ? CGPoint(x: parts[0], y: parts[1]) : nil
    }
}

/// One answer, printed as Peekaboo's JSON envelope (what ArisDesktopEnvelope reads).
/// Also the refusal a step's inner part hands back (a Result's failure).
struct ArisNativeReply: Error {
    var success: Bool
    var data: [String: Any] = [:]
    var code: String? = nil
    var message: String? = nil
    var window: Int? = nil
    var pid: Int32? = nil
    var dispatched = false
    var retrySafe = false
    var state: String? = nil

    static func failure(_ code: String, _ message: String, retrySafe: Bool = false) -> ArisNativeReply {
        ArisNativeReply(success: false, code: code, message: message, retrySafe: retrySafe, state: "refused")
    }

    static func done(window: Int?, pid: Int32?, extra: [String: Any] = [:]) -> ArisNativeReply {
        ArisNativeReply(success: true, data: extra.merging(["engine": "aris"]) { $1 }, window: window, pid: pid, dispatched: true, state: "dispatched_unverified")
    }

    func json() -> Data {
        var object: [String: Any] = ["success": success, "data": data]
        if let code { object["error"] = ["code": code, "message": message ?? "", "mutation_dispatched": dispatched, "retry_safe": retrySafe] }
        var outcome: [String: Any] = ["mutation_dispatched": dispatched, "retry_safe": retrySafe]
        if let state { outcome["state"] = state }
        if !success, let message { outcome["refusal_reason"] = message }
        object["outcome"] = outcome
        var receipt: [String: Any] = [:]
        if let window { receipt["window_id"] = window }
        if let pid { receipt["pid"] = pid }
        if !receipt.isEmpty { object["target_receipt"] = receipt }
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data(#"{"success":false}"#.utf8)
    }
}
