//
//  ArisLook.swift
//  aris-agent
//
//  What the user means by "이거": the front app and window, the selected text (and whether it can be
//  replaced), else the browser's front tab, else the front window's text (aris-tools screen, Vision).
//  Gathered here because the notch app is sandboxed. Password apps are never read.
//  A look asks macOS for nothing (VM bug 2): it reads other apps' elements only while aris-agent already has
//  Accessibility, and captures only while it may already record the screen. What it did without is in `needs`, and the
//  lines for the AI are apart from the context (`unread`, `unselected`), for the app to use or leave out: the app knows
//  whether its own picture of the screen goes with the turn (ArisScreenRead, ArisLookContext).
//

import AppKit
import ApplicationServices

struct ArisLook {
    let app: String
    let window: String?
    let selection: String?
    /// The selection is in a text field or editor, so a rewrite can replace it.
    let editable: Bool
    let tab: String?
    let screen: String?
    /// What the mouse is on: the element's own words and the text around it.
    var pointer: String? = nil
    /// Said to the AI when the front window's words didn't come and no picture of the screen goes with the turn.
    var unread: String? = nil
    /// Said to the AI when the request is to change the selection and aris-agent couldn't read one (no Accessibility).
    var unselected: String? = nil
    /// Which of aris-agent's own permissions this look did without: "accessibility", "screen".
    var needs: [String] = []
    /// The window read was still the app's own topmost when the read was over (ArisFrontNow.confirmed).
    var confirmed = true

    static let limit = 4_000
    static let pointerLimit = 1_500
    /// The screen around the pointer read for "이 사람", "이 사진" (points).
    private static let around = CGSize(width: 640, height: 240)
    private static let browsers: Set = ["com.apple.safari", "com.google.chrome", "company.thebrowser.browser", "com.brave.browser", "com.microsoft.edgemac"]
    private static let timeout: TimeInterval = 6

    /// The look in words, for the AI.
    var context: String {
        var lines = ["Front app: \(app)"]
        // First, so no cut of the screen text loses it (ArisLookTrust reads it in the prompt).
        if !confirmed { lines.append(ArisLookTrust.unconfirmedLine) }
        if let pointer { lines.append("Under the pointer (what \"this\" most likely means):\n\(pointer.prefix(Self.pointerLimit))") }
        if let window, !window.isEmpty { lines.append("Window: \(window)") }
        if let selection { lines.append("Selected text:\n\(selection.prefix(Self.limit))") }
        if let tab { lines.append("Browser tab: \(tab.prefix(Self.limit))") }
        if let screen { lines.append("Text in the front window:\n\(screen.prefix(Self.limit))") }
        return lines.joined(separator: "\n")
    }

    /// `aris`: the app that asked (its pid); `told`: the app it says he was in when he asked (its pid; nil: it didn't
    /// say). The look reads that app's topmost window, or with no word from the app the topmost window that is
    /// neither Aris's nor a macOS prompt's (ArisFrontNow.lookTarget): never what NSWorkspace says is in front, which in
    /// this process can be an app he left minutes ago (second upgrade run, bug 1). A look whose window was no longer
    /// that app's topmost when the read was over says so (ArisLookTrust), and teaches no note.
    static func gather(tools: String, environment: [String: String], aris: Int32? = nil, told: Int32? = nil) -> ArisLook {
        let own = ProcessInfo.processInfo.processIdentifier
        let steppedOver = { (pid: Int32) in
            ArisLookTarget.steppedOver(pid: pid, bundleId: ArisFrontLive.bundleId(pid) ?? "", aris: aris, own: own)
        }
        let ordinary = { (pid: Int32) in ArisFrontLive.app(pid)?.ordinary ?? false }
        guard let target = ArisFrontNow.lookTarget(told: told, windows: ArisFrontLive.windows(), steppedOver: steppedOver, ordinary: ordinary),
              let front = ArisFrontLive.app(target.pid) else {
            return ArisLook(app: "?", window: nil, selection: nil, editable: false, tab: nil, screen: nil)
        }
        let id = front.bundleId?.lowercased() ?? ""
        guard !isPrivateApp(id) else {
            return ArisLook(app: front.name, window: nil, selection: nil, editable: false, tab: nil, screen: nil)
        }
        // Asked without a prompt, and as macOS has them now: a switch turned on while the agent runs counts at once.
        let trusted = AXIsProcessTrusted()
        let allowed = ArisScreenAccess.allowed(tools: tools, environment: environment)
        var look = seen(app: front.name, id: id, pid: target.pid, windowId: target.window, trusted: trusted, allowed: allowed, tools: tools, environment: environment)
        look.needs = ArisScreenRead.needs(accessibility: trusted, screen: allowed)
        look.unselected = trusted ? nil : ArisScreenRead.unselectedLine
        look.confirmed = ArisFrontNow.confirmed(target, after: ArisFrontLive.windows(), steppedOver: steppedOver, ordinary: ordinary)
        if !look.confirmed { FileHandle.standardError.write(Data("aris-agent: look: the window read was no longer \(front.name)'s topmost when the read was over\n".utf8)) }
        return look
    }

    /// The look itself: the selection, else the browser's tab, else the front window's words.
    private static func seen(app: String, id: String, pid: pid_t, windowId: Int?, trusted: Bool, allowed: Bool?, tools: String, environment: [String: String]) -> ArisLook {
        let pointer = pointed(tools: tools, environment: environment, trusted: trusted, records: allowed == true)
        guard trusted else { return tabOrWindow(app: app, id: id, pid: pid, windowId: windowId, pointer: pointer, allowed: allowed, tools: tools, environment: environment) }
        let element = AXUIElementCreateApplication(pid)
        let window = string(attribute(element, kAXFocusedWindowAttribute).flatMap { asElement($0) }.map { attribute($0, kAXTitleAttribute) } ?? nil)
        var selection: String?, editable = false
        // The focused element of the app that is read (the same one system-wide when that app is in front).
        if let focused = attribute(element, kAXFocusedUIElementAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID() {
            let field = focused as! AXUIElement
            selection = string(attribute(field, kAXSelectedTextAttribute)).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            var settable: DarwinBoolean = false
            editable = AXUIElementIsAttributeSettable(field, kAXValueAttribute as CFString, &settable) == .success && settable.boolValue
        }
        if selection != nil {
            return ArisLook(app: app, window: window, selection: selection, editable: editable, tab: nil, screen: nil, pointer: pointer)
        }
        return tabOrWindow(app: app, id: id, pid: pid, windowId: windowId, window: window, pointer: pointer, allowed: allowed, tools: tools, environment: environment)
    }

    /// With nothing selected (or no way to tell): the browser's front tab, else the front window's words.
    private static func tabOrWindow(app: String, id: String, pid: pid_t, windowId: Int?, window: String? = nil, pointer: String?, allowed: Bool?, tools: String,
                                   environment: [String: String]) -> ArisLook {
        if browsers.contains(id) {
            return ArisLook(app: app, window: window, selection: nil, editable: false, tab: tool(tools, ArisLookTarget.tabArguments(bundleId: id), environment), screen: nil, pointer: pointer)
        }
        let read = frontWindowText(tools: tools, environment: environment, allowed: allowed, pid: pid, windowId: windowId) { ArisScreenAccess.afterFailure(tools: tools, environment: environment) }
        // The screen couldn't be read because Screen Recording is off: the question this look is for gets the button
        // that opens that list (ArisFixTurns); a look that read fine drops an older note.
        ArisFixTurns.shared.looked(read.outcome == .permissionOff ? .pane(.screen) : nil)
        let list = ArisScreenRead.listName(macOSMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
        return ArisLook(app: app, window: window, selection: nil, editable: false, tab: nil, screen: read.text, pointer: pointer,
                        unread: ArisScreenRead.unreadLine(read.outcome, list: list))
    }

    /// The front window's words (aris-tools screen), and what the read came to: decided by what the capture gave back
    /// (VM bug 1). While aris-agent may not record the screen (`allowed` false or unknown) nothing is tried: a try is
    /// what makes macOS put up its own window in the middle of a question (VM bug 2). After a try that gave nothing,
    /// `fresh` says what macOS says now.
    /// `pid`: the app whose window is read when it isn't the one in front (ArisLookTarget); nil: the front app's.
    /// `windowId`: exactly that window of the app's (the one the look's target is), never another one of it.
    static func frontWindowText(tools: String, environment: [String: String], allowed: Bool?, pid: pid_t? = nil, windowId: Int? = nil,
                                fresh: () -> Bool?) -> (text: String?, outcome: ArisScreenRead.Outcome) {
        guard allowed == true else { return (nil, ArisScreenRead.outcome(captured: nil, allowed: allowed)) }
        // Why a read failed goes into the English note the AI gets (ArisScreenRead.unreadLine): asked for in English.
        let words = ArisLookTarget.screenArguments(pid: pid, window: windowId)
        // A read by pid carries the helper's own mark: aris-tools takes a pid from nobody else (security review 3, L1).
        let environment = environment.merging(ArisLookTarget.screenEnvironment(pid: pid)) { $1 }
        let captured = ran(tools, words, environment.merging([ArisLocalStore.englishLinesKey: "1"]) { $1 })
        if let captured, captured.status != 0 { logFailure(words, captured) }
        var outcome = ArisScreenRead.outcome(captured: captured, allowed: true)
        if case .nothing = outcome { outcome = ArisScreenRead.outcome(captured: captured, allowed: fresh()) }
        guard case .text(let text) = outcome else { return (nil, outcome) }
        return (String(text.prefix(limit)), outcome)
    }

    /// The element under the mouse (its role and words, and its parent's) and the text read around it on screen.
    /// `trusted`: aris-agent has Accessibility; `records`: it may record the screen. Without one, that half is left out.
    private static func pointed(tools: String, environment: [String: String], trusted: Bool, records: Bool) -> String? {
        // Core Graphics gives the pointer in the coordinates Accessibility wants (origin top-left), on any thread.
        guard let mouse = CGEvent(source: nil)?.location else { return nil }
        var lines: [String] = []
        var found: AXUIElement?
        if trusted, AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(mouse.x), Float(mouse.y), &found) == .success, let found {
            // The front app may be fine while the pointer is over a password manager's window.
            var owner: pid_t = 0
            if AXUIElementGetPid(found, &owner) == .success, isPrivate(pid: owner) { return nil }
            var element: AXUIElement? = found
            for _ in 0..<3 {
                guard let current = element else { break }
                let role = string(attribute(current, kAXRoleDescriptionAttribute)) ?? ""
                // A password field's value is never read.
                let secure = [kAXRoleAttribute, kAXSubroleAttribute].contains { string(attribute(current, $0)) == "AXSecureTextField" }
                let words = (secure ? [kAXTitleAttribute, kAXDescriptionAttribute] : [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute, kAXHelpAttribute])
                    .compactMap { string(attribute(current, $0))?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if !words.isEmpty { lines.append("\(role.isEmpty ? "element" : role): \(words.joined(separator: " · "))") }
                element = attribute(current, kAXParentAttribute).flatMap { asElement($0) }
            }
        }
        let x = Int(mouse.x - around.width / 2), y = Int(mouse.y - around.height / 2)
        let capture = CGRect(x: CGFloat(x), y: CGFloat(y), width: around.width, height: around.height)
        if privateWindow(in: capture) { return lines.isEmpty ? nil : lines.joined(separator: "\n") }
        if records, let text = tool(tools, ["screen", "--around", "\(x),\(y),\(Int(around.width)),\(Int(around.height))"], environment) {
            lines.append("Text around the pointer:\n\(text)")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// Password apps are never read (the one list shared with screen capture, `ArisCaptureRules`).
    static func isPrivateApp(_ bundleId: String?) -> Bool { ArisCaptureRules.isPrivate(bundleId) }

    private static func isPrivate(pid: pid_t) -> Bool {
        isPrivateApp(ArisFrontLive.bundleId(pid))
    }

    /// Whether any on-screen window of a private app overlaps this rect (top-left screen coordinates).
    private static func privateWindow(in rect: CGRect) -> Bool {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { window in
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, isPrivate(pid: pid),
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return false }
            return frame.intersects(rect)
        }
    }

    /// The value as an element, when it is one (an app can answer with anything; a wrong cast would crash the agent).
    private static func asElement(_ value: AnyObject) -> AXUIElement? {
        CFGetTypeID(value) == AXUIElementGetTypeID() ? (value as! AXUIElement) : nil
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func string(_ value: AnyObject?) -> String? { value as? String }

    /// The most a card's values may be. A long route's 100 points alone run past the look's 4,000 characters (QA BUG-2:
    /// Orlando to Daytona Beach by car came cut, so no JSON, so no map card); this stays under a pipe's 64 KiB, which
    /// aris-tools fills before it exits.
    static let cardLimit = 60_000

    /// A card's values (POST /weather, /stock, /maps): aris-tools' JSON object whole, never cut; nil when it failed,
    /// said nothing, isn't a JSON object, or is longer than cardLimit.
    static func cardValues(_ tools: String, _ arguments: [String], _ environment: [String: String], timeout: TimeInterval) -> Data? {
        guard let output = dataOutput(tools, arguments, environment, timeout: timeout) else { return nil }
        let data = Data(output.utf8)
        guard (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else { return nil }
        return data
    }

    /// A data fetch's reply (canvas --json, a card's values): whole, never cut to the look's `limit` (a cut reply is no
    /// JSON: QA BUG-2 and its follow-up for Canvas); nil when it failed, said nothing, or is longer than cardLimit.
    static func dataOutput(_ tools: String, _ arguments: [String], _ environment: [String: String], timeout: TimeInterval) -> String? {
        guard let output = tool(tools, arguments, environment, timeout: timeout, longest: cardLimit + 1), output.utf8.count <= cardLimit else { return nil }
        return output
    }

    /// aris-tools' output (cut to `longest` characters, the look's `limit` unless said), or nil when it failed or said nothing.
    static func tool(_ tools: String, _ arguments: [String], _ environment: [String: String], timeout: TimeInterval = timeout,
                     longest: Int = limit) -> String? {
        guard let run = ran(tools, arguments, environment, timeout: timeout) else { return nil }
        guard run.status == 0 else {
            logFailure(arguments, run)
            return nil
        }
        return run.output.isEmpty ? nil : String(run.output.prefix(longest))
    }

    /// Why a read failed, for agent.log (a missing permission, usually); never what was on screen.
    private static func logFailure(_ arguments: [String], _ run: ArisScreenRead.Captured) {
        FileHandle.standardError.write(Data("aris-agent: look \(arguments[0]) failed: \(run.errors.prefix(200))\n".utf8))
    }

    /// One run of aris-tools: how it ended, what it printed (trimmed) and what it complained of; nil when it couldn't
    /// start or ran past `timeout`.
    static func ran(_ tools: String, _ arguments: [String], _ environment: [String: String], timeout: TimeInterval = timeout) -> ArisScreenRead.Captured? {
        let process = ArisExactProcess()
        process.executableURL = URL(fileURLWithPath: ArisAppBundle.executed(tools))
        process.arguments = arguments
        process.environment = environment
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        do { try ArisChildren.run(process) } catch { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { ArisProcessEnd.end(process); return nil }
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        // A run that worked said what it had to on its output: its complaints are left unread, as before.
        let said = process.terminationStatus == 0 ? "" : String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return ArisScreenRead.Captured(status: process.terminationStatus, output: text, errors: said)
    }
}
