//
//  ArisNativeApps.swift
//  aris-agent
//
//  Aris's own engine: everything around a window's tree. Menus (read and pressed by Accessibility, the app left where
//  it is), a dialog's buttons and fields, a file panel, an app's windows (listed, moved, sized, minimized, closed,
//  brought forward), the app itself (opened, brought forward, hidden, asked to quit) and the Dock's items.
//

import AppKit
import ApplicationServices
import Foundation

enum ArisNativeApps {
    // MARK: - Whose window

    /// The process that owns a window-server window.
    static func owner(ofWindow id: Int) -> Int32? {
        let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(id)) as? [[String: Any]] ?? []
        return list.first?[kCGWindowOwnerPID as String] as? Int32
    }

    /// `--app`: a bundle id, or `PID:<n>`.
    static func pid(_ call: ArisNativeCall) -> Int32? {
        guard let app = call.value("--app") else { return nil }
        if app.hasPrefix("PID:") { return Int32(app.dropFirst(4)) }
        return NSRunningApplication.runningApplications(withBundleIdentifier: app).first { !$0.isTerminated }?.processIdentifier
    }

    // MARK: - Menus

    static func menuList(_ call: ArisNativeCall) -> ArisNativeReply {
        guard let pid = pid(call), let bar = ArisAX.element(ArisAX.app(pid), kAXMenuBarAttribute as String) else {
            return .failure("APP_NOT_FOUND", "no menu bar for that app")
        }
        func items(_ menu: AXUIElement, depth: Int) -> [[String: Any]] {
            ArisAX.children(menu).compactMap { item -> [String: Any]? in
                let title = ArisAX.string(item, kAXTitleAttribute as String) ?? ""
                guard !title.isEmpty else { return nil }
                var entry: [String: Any] = ["title": title]
                if ArisAX.bool(item, kAXEnabledAttribute as String) == false { entry["enabled"] = false }
                if let key = ArisAX.string(item, kAXMenuItemCmdCharAttribute as String), !key.isEmpty { entry["shortcut"] = "⌘" + key }
                if depth < 3, let submenu = ArisAX.children(item).first(where: { ArisAX.role($0) == kAXMenuRole as String }) {
                    let sub = items(submenu, depth: depth + 1)
                    if !sub.isEmpty { entry["items"] = sub }
                }
                return entry
            }
        }
        let structure = ArisAX.children(bar).compactMap { top -> [String: Any]? in
            let title = ArisAX.string(top, kAXTitleAttribute as String) ?? ""
            guard !title.isEmpty, title != "Apple" else { return nil }
            let menu = ArisAX.children(top).first { ArisAX.role($0) == kAXMenuRole as String }
            return ["title": title, "items": menu.map { items($0, depth: 1) } ?? []]
        }
        return ArisNativeReply(success: true, data: ["menu_structure": structure, "engine": "aris"], pid: pid)
    }

    /// "File > Save As…" (› or > between the steps): each step found by its title (any case), the last one pressed.
    static func menuClick(_ call: ArisNativeCall) -> ArisNativeReply {
        guard let pid = pid(call), let bar = ArisAX.element(ArisAX.app(pid), kAXMenuBarAttribute as String) else {
            return .failure("APP_NOT_FOUND", "no menu bar for that app")
        }
        let steps = (call.value("--path") ?? "").components(separatedBy: CharacterSet(charactersIn: ">›")).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !steps.isEmpty else { return .failure("MENU_ITEM_NOT_FOUND", "an empty menu path") }
        var current = bar
        for (index, step) in steps.enumerated() {
            var holder = current
            if ArisAX.role(holder) != kAXMenuBarRole as String, let menu = ArisAX.children(holder).first(where: { ArisAX.role($0) == kAXMenuRole as String }) {
                holder = menu
            }
            let wanted = step.lowercased().replacingOccurrences(of: "...", with: "…")
            guard let found = ArisAX.children(holder).first(where: {
                (ArisAX.string($0, kAXTitleAttribute as String) ?? "").lowercased().replacingOccurrences(of: "...", with: "…") == wanted
            }) else {
                return .failure("MENU_ITEM_NOT_FOUND", "MenuItemNotFound: \(step)")
            }
            if index == steps.count - 1 {
                guard ArisAX.bool(found, kAXEnabledAttribute as String) != false else { return .failure("MENU_ITEM_DISABLED", "that menu item is disabled") }
                guard AXUIElementPerformAction(found, kAXPressAction as CFString) == .success else {
                    return ArisNativeReply(success: false, code: "MENU_PRESS_FAILED", message: "the menu item didn't take the press", pid: pid, state: "partial")
                }
                return .done(window: nil, pid: pid, extra: ["delivery": "ax-menu"])
            }
            current = found
        }
        return .failure("MENU_ITEM_NOT_FOUND", "MenuItemNotFound")
    }

    // MARK: - Dialogs

    /// The app's dialog: a sheet on its front window, or a dialog window of its own.
    static func dialog(pid: Int32) -> AXUIElement? {
        let app = ArisAX.app(pid)
        let windows = (ArisAX.value(app, kAXWindowsAttribute as String) as? [AXUIElement] ?? [])
        for window in windows {
            if let sheet = ArisAX.children(window).first(where: { ArisAX.role($0) == kAXSheetRole as String }) { return sheet }
        }
        return windows.first { ["AXDialog", "AXSystemDialog"].contains(ArisAX.string($0, kAXSubroleAttribute as String) ?? "") }
    }

    private static func descendants(_ root: AXUIElement, limit: Int = 600) -> [AXUIElement] {
        var queue = [root], found: [AXUIElement] = []
        var index = 0
        while index < queue.count, found.count < limit {
            let element = queue[index]
            index += 1
            found.append(element)
            queue += ArisAX.children(element)
        }
        return found
    }

    static func dialogList(_ call: ArisNativeCall) -> ArisNativeReply {
        guard let pid = pid(call), let dialog = dialog(pid: pid) else { return .failure("NO_DIALOG", "no dialog is open") }
        var buttons: [String] = [], fields: [[String: Any]] = [], texts: [String] = []
        for element in descendants(dialog) {
            let role = ArisAX.role(element)
            let title = ArisAX.string(element, kAXTitleAttribute as String) ?? ArisAX.string(element, kAXDescriptionAttribute as String) ?? ""
            switch role {
            case kAXButtonRole as String where !title.isEmpty: buttons.append(title)
            case kAXTextFieldRole as String, kAXTextAreaRole as String:
                var field: [String: Any] = ["label": title]
                if ArisAX.string(element, kAXSubroleAttribute as String) != "AXSecureTextField" { field["value"] = ArisAX.string(element, kAXValueAttribute as String) ?? "" }
                fields.append(field)
            case kAXStaticTextRole as String:
                if let text = ArisAX.string(element, kAXValueAttribute as String), !text.isEmpty { texts.append(String(text.prefix(400))) }
            default: break
            }
        }
        return ArisNativeReply(success: true, data: ["title": ArisAX.string(dialog, kAXTitleAttribute as String) ?? "", "buttons": buttons, "text_fields": fields,
                                                     "texts": texts, "engine": "aris"], pid: pid)
    }

    static func dialogClick(_ call: ArisNativeCall) -> ArisNativeReply {
        guard let pid = pid(call), let dialog = dialog(pid: pid) else { return .failure("NO_DIALOG", "no dialog is open") }
        let wanted = (call.value("--button") ?? "").lowercased()
        guard let button = descendants(dialog).first(where: {
            ArisAX.role($0) == kAXButtonRole as String && (ArisAX.string($0, kAXTitleAttribute as String) ?? ArisAX.string($0, kAXDescriptionAttribute as String) ?? "").lowercased() == wanted
        }) else { return .failure("BUTTON_NOT_FOUND", "no such button in the dialog") }
        guard ArisNativeInput.axPress(button) else { return .failure("PRESS_FAILED", "the button didn't take the press") }
        return .done(window: nil, pid: pid, extra: ["delivery": "ax-press"])
    }

    static func dialogInput(_ call: ArisNativeCall) -> ArisNativeReply {
        guard let pid = pid(call), let dialog = dialog(pid: pid), let text = call.value("--text") else { return .failure("NO_DIALOG", "no dialog is open") }
        let fields = descendants(dialog).filter { [kAXTextFieldRole as String, kAXTextAreaRole as String].contains(ArisAX.role($0)) }
        let wanted = call.value("--field")?.lowercased()
        let field = wanted.flatMap { name in fields.first { (ArisAX.string($0, kAXTitleAttribute as String) ?? ArisAX.string($0, kAXDescriptionAttribute as String) ?? ArisAX.string($0, kAXPlaceholderValueAttribute as String) ?? "").lowercased() == name } }
            ?? (fields.count == 1 ? fields.first : nil)
        guard let field else { return .failure("FIELD_NOT_FOUND", "the dialog's field couldn't be told") }
        guard ArisAX.string(field, kAXSubroleAttribute as String) != "AXSecureTextField" else { return .failure("SECURE_FIELD", "a password field") }
        guard AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, text as CFString) == .success else { return .failure("SET_FAILED", "the field refused the text") }
        return .done(window: nil, pid: pid, extra: ["delivery": "ax-value"])
    }

    /// A file panel: its name field set by Accessibility, its folder typed into the go-to sheet (the panel in front for a
    /// moment), then its button pressed.
    static func dialogFile(_ call: ArisNativeCall, context: ArisNativeContext, runner: ArisNativeRunner) -> ArisNativeReply {
        guard let pid = pid(call), let panel = dialog(pid: pid) ?? ArisAX.element(ArisAX.app(pid), kAXFocusedWindowAttribute as String) else {
            return .failure("NO_DIALOG", "no file panel is open")
        }
        let all = descendants(panel)
        if let name = call.value("--name") {
            let field = all.first { ArisAX.string($0, kAXIdentifierAttribute as String) == "saveAsNameTextField" }
                ?? all.first { ArisAX.role($0) == kAXTextFieldRole as String && ArisAX.settable($0, kAXValueAttribute as String) }
            guard let field, AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, name as CFString) == .success else {
                return .failure("FIELD_NOT_FOUND", "the panel's name field couldn't be set")
            }
        }
        if let path = call.value("--path") {
            guard !context.job else { return .failure("FOREGROUND_REFUSED", "a background job never brings a window forward") }
            let window = ArisAX.windowOf(panel) ?? panel
            let turn: ArisNativeForeground
            switch runner.front(pid: pid, window: window, context: context) {
            case .failure(let refused): return refused
            case .success(let made): turn = made
            }
            // ⌘⇧G by the key that types "g" on the layout in use (key 5 is its US place only).
            ArisNativeInput.press(ArisNativeInput.chord("cmd+shift+g")?.key ?? 5, flags: [.maskCommand, .maskShift], route: .front)
            usleep(500_000)
            // With an input method on, the folder's path is pasted (it would be composed from the key codes).
            if ArisKeyMethod.unicodeEventsTypeText(ArisKeyboardLive.state()) {
                ArisNativeInput.type(path.replacingOccurrences(of: "\\", with: "\\\\"), route: .front)
            } else {
                _ = ArisNativePaste.paste(path, route: .front)
            }
            usleep(200_000)
            ArisNativeInput.press(36, route: .front)
            usleep(500_000)
            turn.restore()
        }
        let wanted = call.value("--select")?.lowercased()
        let buttons = descendants(panel).filter { ArisAX.role($0) == kAXButtonRole as String }
        let button = wanted.flatMap { name in buttons.first { (ArisAX.string($0, kAXTitleAttribute as String) ?? "").lowercased() == name } }
            ?? ArisAX.element(panel, kAXDefaultButtonAttribute as String)
            ?? buttons.first { ["save", "open", "저장", "열기"].contains((ArisAX.string($0, kAXTitleAttribute as String) ?? "").lowercased()) }
        guard let button, ArisNativeInput.axPress(button) else { return .failure("BUTTON_NOT_FOUND", "the panel's button couldn't be pressed") }
        return .done(window: nil, pid: pid, extra: ["delivery": "ax-press"])
    }

    // MARK: - Windows

    static func windowList(_ call: ArisNativeCall) -> ArisNativeReply {
        guard let pid = pid(call) else { return .failure("APP_NOT_FOUND", "that app isn't running") }
        let focused = ArisAX.focusedWindowId(pid: pid)
        // Every window of the app: on screen, minimized, hidden or on another Space (ArisDesktopWindowMerge).
        let list = ArisDesktopWindowMerge.live(pid: pid).map { window -> [String: Any] in
            var entry: [String: Any] = ["window_id": window.id, "window_title": window.title ?? "", "is_frontmost": window.id == focused,
                                        "bounds": ["x": window.frame.minX, "y": window.frame.minY, "width": window.frame.width, "height": window.frame.height],
                                        "on_screen": window.onScreen]
            if window.minimized { entry["minimized"] = true }
            return entry
        }
        return ArisNativeReply(success: true, data: ["windows": list, "engine": "aris"], pid: pid)
    }

    static func window(_ call: ArisNativeCall, context: ArisNativeContext) -> ArisNativeReply {
        let operation = call.positional.first ?? "focus"
        guard let id = call.int("--window-id"), let pid = owner(ofWindow: id), let window = ArisAX.window(pid: pid, id: id) else {
            return .failure("WINDOW_NOT_FOUND", "no such window")
        }
        func setPoint(_ name: String, _ point: CGPoint) -> Bool {
            var value = point
            guard let ax = AXValueCreate(.cgPoint, &value) else { return false }
            return AXUIElementSetAttributeValue(window, name as CFString, ax) == .success
        }
        func setSize(_ size: CGSize) -> Bool {
            var value = size
            guard let ax = AXValueCreate(.cgSize, &value) else { return false }
            return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, ax) == .success
        }
        var ok = false
        switch operation {
        case "focus":
            guard !context.job else { return .failure("FOREGROUND_REFUSED", "a background job never brings a window forward") }
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
            ok = AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success
            AXUIElementSetAttributeValue(ArisAX.app(pid), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            NSRunningApplication(processIdentifier: pid)?.activate()
        case "close":
            if let button = ArisAX.element(window, kAXCloseButtonAttribute as String) { ok = ArisNativeInput.axPress(button) }
        case "minimize":
            ok = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success
        case "restore":
            ok = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse) == .success
        case "maximize":
            let frame = ArisAX.frame(window) ?? .zero
            let screen = ArisNativeDisplays.frames.first { $0.intersects(frame) } ?? ArisNativeDisplays.frames.first ?? .zero
            let visible = NSScreen.screens.first { CGRect(x: $0.frame.minX, y: 0, width: $0.frame.width, height: $0.frame.height).intersects(CGRect(x: screen.minX, y: 0, width: screen.width, height: screen.height)) }
            let top = screen.minY + (visible.map { $0.frame.maxY - $0.visibleFrame.maxY } ?? 25)
            ok = setPoint(kAXPositionAttribute as String, CGPoint(x: screen.minX, y: top)) && setSize(CGSize(width: screen.width, height: screen.maxY - top))
        case "move":
            guard let x = call.int("--x"), let y = call.int("--y") else { return .failure("BAD_ARGUMENTS", "move needs --x and --y") }
            ok = setPoint(kAXPositionAttribute as String, CGPoint(x: x, y: y))
        case "resize":
            guard let width = call.int("--width"), let height = call.int("--height") else { return .failure("BAD_ARGUMENTS", "resize needs --width and --height") }
            ok = setSize(CGSize(width: width, height: height))
        default:
            return .failure("BAD_ARGUMENTS", "no such window operation")
        }
        return ok ? .done(window: id, pid: pid, extra: ["delivery": "ax-window"]) : .failure("WINDOW_ACTION_FAILED", "the window didn't take it")
    }

    // MARK: - Apps and the Dock

    static func app(_ call: ArisNativeCall, context: ArisNativeContext) -> ArisNativeReply {
        let operation = call.positional.first ?? "focus"
        if operation == "launch" {
            guard let bundle = call.value("--bundle-id"), let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else {
                return .failure("APP_NOT_FOUND", "no app with that bundle id")
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = call.has("--foreground") && !context.job
            let done = DispatchSemaphore(value: 0)
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in done.signal() }
            _ = done.wait(timeout: .now() + 15)
            // --wait-for-window: up to ten seconds for a window of it.
            let deadline = Date().addingTimeInterval(call.has("--wait-for-window") ? 10 : 0)
            var pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first?.processIdentifier
            while Date() < deadline {
                pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first?.processIdentifier
                if let pid, !(ArisAX.value(ArisAX.app(pid), kAXWindowsAttribute as String) as? [AXUIElement] ?? []).isEmpty { break }
                usleep(200_000)
            }
            return pid.map { .done(window: nil, pid: $0, extra: ["delivery": "launch"]) } ?? .failure("LAUNCH_FAILED", "it didn't start")
        }
        guard let pid = pid(call), let running = NSRunningApplication(processIdentifier: pid) else { return .failure("APP_NOT_FOUND", "that app isn't running") }
        switch operation {
        case "focus":
            guard !context.job else { return .failure("FOREGROUND_REFUSED", "a background job never brings an app forward") }
            AXUIElementSetAttributeValue(ArisAX.app(pid), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            running.activate()
        case "hide": running.hide()
        case "quit": running.terminate()
        default: return .failure("BAD_ARGUMENTS", "no such app operation")
        }
        return .done(window: nil, pid: pid, extra: ["delivery": "app"])
    }

    static func dockList() -> ArisNativeReply {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return .failure("APP_NOT_FOUND", "no Dock") }
        let items = descendants(ArisAX.app(dock.processIdentifier), limit: 400).filter { ArisAX.role($0) == "AXDockItem" }.compactMap { item -> [String: Any]? in
            guard let title = ArisAX.string(item, kAXTitleAttribute as String), !title.isEmpty else { return nil }
            var entry: [String: Any] = ["title": title, "kind": ArisAX.string(item, kAXSubroleAttribute as String) ?? ""]
            if let running = ArisAX.bool(item, "AXIsApplicationRunning") { entry["running"] = running }
            return entry
        }
        return ArisNativeReply(success: true, data: ["dock_items": items, "engine": "aris"])
    }

    // MARK: - Scrolling by a scroll bar

    /// Moves the scroll bar of the element (or of the scroll area holding it) by about `lines` lines; false when there is
    /// none or it doesn't move.
    static func scrollByBar(_ element: AXUIElement, direction: String, lines: Int) -> Bool {
        var area: AXUIElement? = element
        for _ in 0..<8 {
            guard let current = area else { return false }
            if ArisAX.role(current) == kAXScrollAreaRole as String { break }
            area = ArisAX.element(current, kAXParentAttribute as String)
        }
        guard let area, ArisAX.role(area) == kAXScrollAreaRole as String else { return false }
        let vertical = direction == "up" || direction == "down"
        guard let bar = ArisAX.element(area, vertical ? kAXVerticalScrollBarAttribute as String : kAXHorizontalScrollBarAttribute as String),
              let now = (ArisAX.value(bar, kAXValueAttribute as String) as? NSNumber)?.doubleValue, ArisAX.settable(bar, kAXValueAttribute as String) else { return false }
        let step = 0.04 * Double(lines) / 5
        let next = min(1, max(0, now + ((direction == "down" || direction == "right") ? step : -step)))
        guard next != now else { return false }
        return AXUIElementSetAttributeValue(bar, kAXValueAttribute as CFString, NSNumber(value: next)) == .success
    }
}
