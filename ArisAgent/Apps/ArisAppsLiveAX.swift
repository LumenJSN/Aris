//
//  ArisAppsLiveAX.swift
//  aris-agent (Core 2 app layer, jv-apps)
//
//  An app's menu bar through Accessibility: read whole (title, enabled, checkmark, key equivalent and modifiers of
//  every item), and an item pressed by AXPress while the app stays in the background. A menu an app builds only when
//  it opens (Electron, some Catalyst apps) is opened by AXPress on its title, read, and closed again with AXCancel.
//  Also a window's full screen (AXFullScreen). Uses the engine's window-id lookup (ArisAX, read-only use).
//

import ApplicationServices
import Foundation

final class ArisAppsLiveAccessibility: ArisAppsAccessibility {
    /// The most items read from one menu bar, and how deep.
    static let mostItems = 2_500
    static let deepest = 5

    private static func value(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] { value(element, kAXChildrenAttribute as String) as? [AXUIElement] ?? [] }
    private static func string(_ element: AXUIElement, _ name: String) -> String? { value(element, name) as? String }
    private static func role(_ element: AXUIElement) -> String { string(element, kAXRoleAttribute as String) ?? "" }

    private static func app(_ pid: Int32) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 2)
        return app
    }

    private static func bar(_ pid: Int32) -> AXUIElement? {
        guard let found = value(app(pid), kAXMenuBarAttribute as String), CFGetTypeID(found) == AXUIElementGetTypeID() else { return nil }
        return (found as! AXUIElement)
    }

    private static func submenu(_ element: AXUIElement) -> AXUIElement? { children(element).first { role($0) == kAXMenuRole as String } }

    private static func item(_ element: AXUIElement, depth: Int, budget: inout Int) -> ArisApps.MenuItem? {
        let title = string(element, kAXTitleAttribute as String) ?? ""
        guard !title.isEmpty, budget > 0 else { return nil }
        budget -= 1
        var item = ArisApps.MenuItem(title: title)
        item.enabled = (value(element, kAXEnabledAttribute as String) as? NSNumber)?.boolValue ?? true
        item.checked = !(string(element, kAXMenuItemMarkCharAttribute as String) ?? "").isEmpty
        if let key = string(element, kAXMenuItemCmdCharAttribute as String), !key.isEmpty {
            item.key = key
            item.modifiers = (value(element, kAXMenuItemCmdModifiersAttribute as String) as? NSNumber)?.intValue ?? 0
        }
        if depth < deepest, let menu = submenu(element) {
            let items = children(menu).compactMap { child in Self.item(child, depth: depth + 1, budget: &budget) }
            if !items.isEmpty { item.items = items }
        }
        return item
    }

    func menuBar(pid: Int32) -> ArisApps.MenuBar? {
        guard let bar = Self.bar(pid) else { return nil }
        var budget = Self.mostItems
        let menus = Self.children(bar).compactMap { top -> ArisApps.MenuItem? in
            let title = Self.string(top, kAXTitleAttribute as String) ?? ""
            guard !title.isEmpty, title != "Apple" else { return nil }
            var menu = ArisApps.MenuItem(title: title)
            if let submenu = Self.submenu(top) { menu.items = Self.children(submenu).compactMap { Self.item($0, depth: 1, budget: &budget) } }
            return menu
        }
        return ArisApps.MenuBar(menus: menus)
    }

    func pressMenu(pid: Int32, path: [String]) -> (ok: Bool, message: String) {
        guard let bar = Self.bar(pid) else { return (false, "no menu bar for that app (Accessibility shows none)") }
        guard !path.isEmpty else { return (false, "an empty menu path") }
        var holder = bar
        var opened: AXUIElement?
        defer { if let opened { AXUIElementPerformAction(opened, kAXCancelAction as CFString) } }
        for (index, step) in path.enumerated() {
            let wanted = ArisApps.MenuBar.titleKey(step)
            func find(_ in: AXUIElement) -> AXUIElement? {
                Self.children(`in`).first { ArisApps.MenuBar.titleKey(Self.string($0, kAXTitleAttribute as String) ?? "") == wanted }
            }
            var found = find(holder)
            // A menu built only when it opens: opened once, read, closed again after the press.
            if found == nil, index > 0, opened == nil, let top = Self.children(bar).first(where: {
                ArisApps.MenuBar.titleKey(Self.string($0, kAXTitleAttribute as String) ?? "") == ArisApps.MenuBar.titleKey(path[0])
            }) {
                AXUIElementPerformAction(top, kAXPressAction as CFString)
                opened = Self.submenu(top)
                usleep(250_000)
                found = find(holder)
            }
            guard let element = found else { return (false, "no menu item “\(step)”" + (index > 0 ? " under “\(path[index - 1])”" : "")) }
            if index == path.count - 1 {
                guard (Self.value(element, kAXEnabledAttribute as String) as? NSNumber)?.boolValue != false else {
                    return (false, "“\(step)” is greyed out right now")
                }
                let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
                opened = nil
                return result == .success ? (true, "pressed") : (false, "the menu item didn't take the press (\(result.rawValue))")
            }
            guard let submenu = Self.submenu(element) else { return (false, "“\(step)” has no submenu") }
            holder = submenu
        }
        return (false, "no such menu item")
    }

    func focusedRole(pid: Int32) -> String? {
        guard let found = Self.value(Self.app(pid), kAXFocusedUIElementAttribute as String), CFGetTypeID(found) == AXUIElementGetTypeID() else { return nil }
        let role = Self.role(found as! AXUIElement)
        guard role.hasPrefix("AX"), role.count > 2 else { return nil }
        let rest = role.dropFirst(2)
        return rest.prefix(1).lowercased() + rest.dropFirst()
    }

    /// The roles a text can go into: a field, a text area (also a web page's), a combo box's field.
    static let textRoles: Set<String> = [kAXTextFieldRole as String, kAXTextAreaRole as String, kAXComboBoxRole as String]

    func caretToEnd(pid: Int32, at point: (x: Double, y: Double)?) -> ArisApps.CaretEnd {
        let app = Self.app(pid)
        let element = { (value: AnyObject?) -> AXUIElement? in
            guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return (value as! AXUIElement)
        }
        let focused = element(Self.value(app, kAXFocusedUIElementAttribute as String))
        var target: AXUIElement?
        if let point {
            var found: AXUIElement?
            if AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &found) == .success { target = found }
            // The point can land on a part of the text view: its text element is at most two levels up.
            for _ in 0..<2 where target.map({ !Self.textRoles.contains(Self.role($0)) }) == true {
                target = target.flatMap { element(Self.value($0, kAXParentAttribute as String)) }
            }
        } else {
            target = focused
        }
        guard let text = target, Self.textRoles.contains(Self.role(text)),
              Self.string(text, kAXSubroleAttribute as String) != kAXSecureTextFieldSubrole as String else { return .notText }
        let isFocused = focused.map { CFEqual($0, text) } ?? false
        let length = (Self.value(text, kAXNumberOfCharactersAttribute as String) as? NSNumber)?.intValue
            ?? Self.string(text, kAXValueAttribute as String).map { $0.utf16.count }
        guard let length else { return .refused(focused: isFocused) }
        var range = CFRange(location: length, length: 0)
        guard let wanted = AXValueCreate(.cfRange, &range),
              AXUIElementSetAttributeValue(text, kAXSelectedTextRangeAttribute as CFString, wanted) == .success else { return .refused(focused: isFocused) }
        // Read back: the caret is where it was put.
        var now = CFRange(location: -1, length: -1)
        if let back = Self.value(text, kAXSelectedTextRangeAttribute as String), CFGetTypeID(back) == AXValueGetTypeID() {
            AXValueGetValue(back as! AXValue, .cfRange, &now)
        }
        return now.location == length && now.length == 0 ? .moved : .refused(focused: isFocused)
    }

    func setFullScreen(pid: Int32, window: Int, on: Bool) -> Bool {
        let windows = Self.value(Self.app(pid), kAXWindowsAttribute as String) as? [AXUIElement] ?? []
        guard let target = windows.first(where: { ArisAX.windowId($0) == window }) else { return false }
        return AXUIElementSetAttributeValue(target, "AXFullScreen" as CFString, on ? kCFBooleanTrue : kCFBooleanFalse) == .success
    }
}
