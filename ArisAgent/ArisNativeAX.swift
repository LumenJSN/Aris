//
//  ArisNativeAX.swift
//  aris-agent
//
//  Aris's own computer-use engine (ArisNativeRunner), its Accessibility half: an app's windows by their window-server
//  id, a window's tree read without bringing it forward, each element as the controller reads it (Peekaboo's shape:
//  role, label, value, bounds, whether it acts, its AX role…), the focused element, and the tree of an Electron or
//  Chromium app switched on (AXManualAccessibility, else AXEnhancedUserInterface: without it such an app shows almost
//  nothing). Reads only; ArisNativeInput acts.
//

import AppKit
import ApplicationServices
import Foundation

/// The window server's id of an Accessibility window (HIServices; no public equivalent).
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

enum ArisAX {
    // MARK: - Attributes

    static func value(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    static func string(_ element: AXUIElement, _ name: String) -> String? { value(element, name) as? String }

    static func bool(_ element: AXUIElement, _ name: String) -> Bool? { (value(element, name) as? NSNumber)?.boolValue }

    /// A value with the call's own error (a timeout is kAXErrorCannotComplete).
    static func copy(_ element: AXUIElement, _ name: String) -> (value: AnyObject?, error: AXError) {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return (error == .success ? value : nil, error)
    }

    /// Each element Aris reaches answers within `ArisAXBudget.perCall` (a messaging timeout is the element's own:
    /// one set on the app's element doesn't carry to its children, which waited the system's six seconds each).
    @discardableResult
    static func timed(_ element: AXUIElement) -> AXUIElement {
        AXUIElementSetMessagingTimeout(element, ArisAXBudget.perCall)
        return element
    }

    static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let found = value(element, name), CFGetTypeID(found) == AXUIElementGetTypeID() else { return nil }
        return timed(found as! AXUIElement)
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] { (value(element, kAXChildrenAttribute as String) as? [AXUIElement] ?? []).map(timed) }

    static func role(_ element: AXUIElement) -> String { string(element, kAXRoleAttribute as String) ?? "" }

    /// The app doesn't answer Accessibility at all now (its role asked with a short timeout timed out).
    static func unresponsive(pid: Int32) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, ArisAXBudget.probe)
        return copy(app, kAXRoleAttribute as String).error == .cannotComplete
    }

    static func actions(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
        return names as? [String] ?? []
    }

    static func settable(_ element: AXUIElement, _ name: String) -> Bool {
        var result = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, name as CFString, &result) == .success && result.boolValue
    }

    /// An element's frame in global points (top-left origin), when it has one.
    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = value(element, kAXPositionAttribute as String), let size = value(element, kAXSizeAttribute as String),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin), AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: origin, size: dimensions)
    }

    /// A text control's caret or selection.
    static func selectedRange(_ element: AXUIElement) -> CFRange? {
        guard let raw = value(element, kAXSelectedTextRangeAttribute as String), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        return AXValueGetValue(raw as! AXValue, .cfRange, &range) ? range : nil
    }

    static func windowId(_ window: AXUIElement) -> Int? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(window, &id) == .success && id != 0 ? Int(id) : nil
    }

    static func app(_ pid: Int32) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 2)
        return app
    }

    /// The app's windows as Accessibility lists them (on this Space, minimized and hidden ones too), each timed.
    static func windows(pid: Int32) -> [AXUIElement] { (value(app(pid), kAXWindowsAttribute as String) as? [AXUIElement] ?? []).map(timed) }

    /// The app's window with this window-server id (its windows, then its focused and main one, then, for a window on
    /// another Space that Accessibility doesn't list, the app's elements by their remote token: ArisAXRemote).
    static func window(pid: Int32, id: Int) -> AXUIElement? {
        let app = app(pid)
        let listed = windows(pid: pid)
        let extra = [element(app, kAXFocusedWindowAttribute as String), element(app, kAXMainWindowAttribute as String)].compactMap { $0 }
        return (listed + extra).first { windowId($0) == id } ?? ArisAXRemote.window(pid: pid, id: id)
    }

    /// The window an element sits in.
    static func windowOf(_ element: AXUIElement) -> AXUIElement? {
        if let window = Self.element(element, kAXWindowAttribute as String) { return window }
        var current = element
        for _ in 0..<60 {
            if role(current) == kAXWindowRole as String { return current }
            guard let parent = Self.element(current, kAXParentAttribute as String) else { return nil }
            current = parent
        }
        return nil
    }

    static func focused(pid: Int32) -> AXUIElement? { element(app(pid), kAXFocusedUIElementAttribute as String) }

    static func focusedWindowId(pid: Int32) -> Int? { element(app(pid), kAXFocusedWindowAttribute as String).flatMap(windowId) }

    // MARK: - Web apps

    /// Electron and Chromium apps keep their tree off until an assistive app asks for it: the bundle carries Electron's
    /// or Chromium's framework.
    static func isWebShell(bundleURL: URL?) -> Bool {
        guard let frameworks = bundleURL?.appendingPathComponent("Contents/Frameworks") else { return false }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: frameworks.path)) ?? []
        return names.contains { $0.hasPrefix("Electron Framework") || $0.contains("Chromium Embedded") || $0.hasSuffix("Framework.framework") && $0.contains("Chrom") }
    }

    private static let webLock = NSLock()
    nonisolated(unsafe) private static var webOn: [Int32: Date] = [:]
    nonisolated(unsafe) private static var sweeping = false
    /// How long an app's web tree stays on after Aris last used it. It is switched off again after that: an app that
    /// sees an assistive app (VS Code: "Screen reader usage detected", its screen-reader mode) goes back to normal
    /// (measured in the VM, 2026-11-16).
    static let webLease: TimeInterval = 45

    /// Switches the app's web tree on (AXManualAccessibility, the Electron way; AXEnhancedUserInterface when that isn't
    /// taken) for a while, or keeps it on. True when it was switched on now (the tree takes a moment to fill).
    @discardableResult
    static func enableWebTree(pid: Int32, bundleURL: URL?) -> Bool {
        guard isWebShell(bundleURL: bundleURL) else { return false }
        let (first, sweep) = webLock.withLock { () -> (Bool, Bool) in
            let first = webOn.updateValue(Date(), forKey: pid) == nil
            let sweep = !sweeping
            sweeping = true
            return (first, sweep)
        }
        if sweep { scheduleSweep() }
        guard first else { return false }
        let app = app(pid)
        if AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue) != .success {
            AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
        return true
    }

    /// The trees not used for `webLease` are switched off again.
    private static func scheduleSweep() {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 15) {
            let now = Date()
            let (stale, more) = webLock.withLock { () -> ([Int32], Bool) in
                let stale = webOn.filter { now.timeIntervalSince($0.value) > webLease }.map(\.key)
                stale.forEach { webOn[$0] = nil }
                sweeping = !webOn.isEmpty
                return (stale, sweeping)
            }
            for pid in stale {
                let app = app(pid)
                AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanFalse)
                AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
            }
            if more { scheduleSweep() }
        }
    }

    // MARK: - Roles

    /// The controller's role names: the AX role without its "AX", its first letter lowercased (AXTextField → textField),
    /// a switch for a checkbox that is one, "other" when there is none.
    static func shortRole(_ role: String, subrole: String?) -> String {
        if role == "AXCheckBox", subrole == "AXSwitch" { return "switch" }
        guard role.hasPrefix("AX"), role.count > 2 else { return role.isEmpty ? "other" : role }
        let rest = role.dropFirst(2)
        return rest.prefix(1).lowercased() + rest.dropFirst()
    }

    /// The actions that make an element one a click acts on.
    static let pressActions: Set<String> = ["AXPress", "AXConfirm", "AXPick", "AXOpen", "AXShowMenu"]
}

/// One look's elements: the controller's dictionaries (Peekaboo's `ui_elements`) and the live elements behind their ids.
struct ArisNativeTree {
    var elements: [[String: Any]] = []
    var live: [String: AXUIElement] = [:]
    var truncated = false
    var focusedFrame: CGRect?
    var focusedRole: String?

    /// The most elements one look keeps, and how deep it goes.
    static let maxElements = 1_500
    static let maxDepth = 48
    /// Containers walked through but not listed when they have nothing of their own to say.
    static let silent: Set<String> = ["AXGroup", "AXSplitGroup", "AXScrollArea", "AXLayoutArea", "AXLayoutItem", "AXUnknown", "AXSplitter"]

    /// The window's tree, breadth first, every element with a frame inside the window (or none) kept, within `budget`:
    /// each element's role is asked first, and one that times out is skipped with its subtree (a hung app answers
    /// nothing, and every further question would wait); a few timeouts in a row end the walk as "not responding".
    static func read(window: AXUIElement, pid: Int32, budget: ArisAXBudget = ArisAXBudget(limit: ArisAXBudget.lookLimit)) -> ArisNativeTree {
        var tree = ArisNativeTree()
        ArisAX.timed(window)
        let focused = ArisAX.focused(pid: pid)
        if let focused {
            tree.focusedFrame = ArisAX.frame(focused)
            tree.focusedRole = ArisAX.role(focused)
        }
        let top = ArisAX.copy(window, kAXChildrenAttribute as String)
        budget.record(top.error)
        var queue: [(AXUIElement, Int)] = ((top.value as? [AXUIElement]) ?? []).map { (ArisAX.timed($0), 1) }
        var index = 0
        var visited = 0
        while index < queue.count, visited < maxElements * 4 {
            if budget.exhausted {
                tree.truncated = true
                break
            }
            let (element, depth) = queue[index]
            index += 1
            visited += 1
            let asked = ArisAX.copy(element, kAXRoleAttribute as String)
            budget.record(asked.error)
            if asked.error == .cannotComplete { continue }
            let role = asked.value as? String ?? ""
            if let entry = entry(element, role: role, id: "elem_\(tree.elements.count + 1)") {
                if tree.elements.count >= maxElements {
                    tree.truncated = true
                    break
                }
                tree.elements.append(entry)
                tree.live[entry["id"] as! String] = element
            }
            if depth < maxDepth, role != "AXMenuBar" { queue += ArisAX.children(element).map { ($0, depth + 1) } }
        }
        return tree
    }

    /// One element in the controller's shape; nil for an empty container.
    static func entry(_ element: AXUIElement, role: String, id: String) -> [String: Any]? {
        let subrole = ArisAX.string(element, kAXSubroleAttribute as String)
        let title = ArisAX.string(element, kAXTitleAttribute as String) ?? ""
        let description = ArisAX.string(element, kAXDescriptionAttribute as String) ?? ""
        let help = ArisAX.string(element, kAXHelpAttribute as String) ?? ""
        let placeholder = ArisAX.string(element, kAXPlaceholderValueAttribute as String) ?? ""
        let raw = ArisAX.value(element, kAXValueAttribute as String)
        let value: String? = (raw as? String) ?? (raw as? NSNumber)?.stringValue
        let actions = ArisAX.actions(element)
        let label = [title, description, placeholder, help].first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        let acts = !ArisAX.pressActions.isDisjoint(with: actions)
        if silent.contains(role), label.isEmpty, (value ?? "").isEmpty, !acts { return nil }
        if role == "AXStaticText", label.isEmpty, (value ?? "").isEmpty { return nil }
        var entry: [String: Any] = ["id": id, "role": ArisAX.shortRole(role, subrole: subrole), "label": label, "ax_role": role,
                                    "is_enabled": ArisAX.bool(element, kAXEnabledAttribute as String) ?? true, "is_actionable": acts]
        // A static text's words are its value: shown as its label, as Peekaboo does.
        if role == "AXStaticText", label.isEmpty, let value { entry["label"] = String(value.prefix(400)) }
        else if let value { entry["value"] = value }
        if let frame = ArisAX.frame(element) {
            entry["bounds"] = ["x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height]
        }
        if let description = ArisAX.string(element, kAXRoleDescriptionAttribute as String) { entry["role_description"] = description }
        if let identifier = ArisAX.string(element, kAXIdentifierAttribute as String), !identifier.isEmpty { entry["identifier"] = identifier }
        if ArisAX.bool(element, kAXSelectedAttribute as String) == true { entry["is_selected"] = true }
        if let range = ArisAX.selectedRange(element), range.location >= 0, range.length >= 0 {
            entry["selected_text_range"] = ["location": range.location, "length": range.length]
        }
        return entry
    }
}
