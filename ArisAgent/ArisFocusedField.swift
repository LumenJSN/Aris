//
//  ArisFocusedField.swift
//  aris-agent
//
//  The text field that has the keyboard in the front app, read through Accessibility for dictation's caret context
//  and its edit watch. Never a password field (AXSecureTextField, or secure input on), never a password app, never a
//  terminal, never Aris itself. Every call has a 0.25 s messaging timeout, so a hung app can't hold the agent.
//

import AppKit
import ApplicationServices
import Carbon

struct ArisFocusedField {
    private static let messagingTimeout: Float = 0.25
    /// Longer than this, the field isn't read (a whole document).
    static let valueLimit = 50_000

    let element: AXUIElement
    let pid: pid_t
    let bundleId: String?

    /// Why the front app's fields are off limits now, or nil when one may be read. `front`: the app that has the
    /// keyboard now (ArisFrontLive: NSWorkspace's front app goes stale in this process, second upgrade run, bug 1).
    static func refusal(front: ArisFrontLive.App? = ArisFrontLive.front()) -> String? {
        guard AXIsProcessTrusted() else { return "no Accessibility" }
        guard !IsSecureEventInputEnabled() else { return "secure input" }
        let id = front?.bundleId
        if ArisCaptureRules.isPrivate(id) { return "password app" }
        if ArisWritingStyles.isTerminal(id) { return "terminal" }
        if id?.lowercased().hasPrefix("com.lumenjsn.aris") == true { return "Aris" }
        return nil
    }

    /// The focused field of the front app, when it may be read.
    static func current() -> ArisFocusedField? {
        let front = ArisFrontLive.front()
        guard refusal(front: front) == nil, let front else { return nil }
        let app = AXUIElementCreateApplication(front.pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        guard let focused = attribute(app, kAXFocusedUIElementAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        var owner: pid_t = 0
        guard AXUIElementGetPid(element, &owner) == .success, owner == front.pid else { return nil }
        let field = ArisFocusedField(element: element, pid: owner, bundleId: front.bundleId)
        return field.isSecure ? nil : field
    }

    var isSecure: Bool {
        [kAXRoleAttribute, kAXSubroleAttribute].contains { Self.attribute(element, $0) as? String == "AXSecureTextField" }
    }

    /// The field's text, or nil (not text, too long, or it can't be read).
    var value: String? {
        guard let text = Self.attribute(element, kAXValueAttribute) as? String, text.utf16.count <= Self.valueLimit else { return nil }
        return text
    }

    /// The caret (and selection length), in UTF-16 units.
    var selection: CFRange? {
        guard let raw = Self.attribute(element, kAXSelectedTextRangeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        return AXValueGetValue(raw as! AXValue, .cfRange, &range) ? range : nil
    }

    /// Still the field the user is typing in: the same app in front, the same element focused, not secure.
    var stillFocused: Bool {
        let front = ArisFrontLive.front()
        guard Self.refusal(front: front) == nil, front?.pid == pid else { return false }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)
        guard let focused = Self.attribute(app, kAXFocusedUIElementAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
        return CFEqual(focused, element) && !isSecure
    }

    /// The words around the caret for polish, or nil when the field can't or mustn't be read.
    static func caretContext() -> (before: String, after: String)? {
        guard let field = current(), let value = field.value, let selection = field.selection else { return nil }
        return ArisCaretContext.slice(value, caret: selection.location, selected: selection.length)
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
}
