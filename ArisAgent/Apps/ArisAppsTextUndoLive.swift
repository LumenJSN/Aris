//
//  ArisAppsTextUndoLive.swift
//  aris-agent (Core 2 app layer)
//
//  Takes back text app.type put in (ArisApps.TextUndo, third VM run, D3): the app's text element that holds exactly
//  what app.type left (its whole value as read back right after) is found again through Accessibility, and only the
//  inserted range is selected and removed, so the rest of the document and its formatting stay; a replace's element
//  gets back the whole text it held, from its kept copy. When no element holds that any more (he edited it since, the
//  window is closed), nothing is touched and the undo says exactly why (fourth VM run, D7: it failed with no reason).
//

import AppKit
import ApplicationServices
import Foundation

enum ArisAppsTextUndoLive {
    /// Puts the performer into ArisUndoHands.live (once is enough; again changes nothing).
    static func install() {
        ArisUndoHands.live.setText = { app, element, value in try remove(app: app, element: element, restoring: value) }
    }

    static let textRoles: Set<String> = [kAXTextAreaRole as String, kAXTextFieldRole as String, "AXComboBox", "AXSearchField"]
    static let mostNodes = 8_000

    /// `restoring`: for a replace, the text the field held (from its kept copy); unused for an insertion.
    static func remove(app name: String, element: String, restoring: String = "") throws {
        guard let mark = ArisApps.TextUndo.mark(element) else { throw ArisUndoError(message: "that text change isn't one Aris can take back") }
        guard AXIsProcessTrusted() else { throw ArisUndoError(message: "Aris needs Accessibility to take the text back") }
        guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: mark.bundle).first else {
            throw ArisUndoError(message: "\(name) isn't open any more, so its text was left as it is")
        }
        let replace = mark.erased != nil
        let application = AXUIElementCreateApplication(running.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 1)
        var found: [(AXUIElement, NSRange)] = []
        var states: [ArisApps.TextUndo.Found] = []
        var queue: [AXUIElement] = attribute(application, kAXWindowsAttribute) as? [AXUIElement] ?? []
        var index = 0
        while index < queue.count, index < mostNodes {
            let next = queue[index]
            index += 1
            let role = attribute(next, kAXRoleAttribute) as? String ?? ""
            if textRoles.contains(role), attribute(next, kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole as String,
               let value = attribute(next, kAXValueAttribute) as? String ?? (role == kAXTextAreaRole as String ? "" : nil) {
                let state = ArisApps.TextUndo.find(in: value, mark: mark)
                states.append(state)
                if case .range(let range) = state { found.append((next, range)) }
                continue
            }
            queue += attribute(next, kAXChildrenAttribute) as? [AXUIElement] ?? []
        }
        guard found.count == 1, let (text, range) = found.first else {
            throw ArisUndoError(message: found.isEmpty ? ArisApps.TextUndo.refusal(states, app: name, replace: replace)
                                                       : "more than one place in \(name) holds that text, so it was left as it is")
        }
        if replace {
            guard AXUIElementSetAttributeValue(text, kAXValueAttribute as CFString, restoring as CFString) == .success else {
                throw ArisUndoError(message: "\(name) didn't let Aris put its text back")
            }
            if let value = attribute(text, kAXValueAttribute) as? String, value != restoring {
                throw ArisUndoError(message: "\(name) changed the text differently than asked; check it")
            }
            return
        }
        var selection = CFRange(location: range.location, length: range.length)
        guard let wanted = AXValueCreate(.cfRange, &selection),
              AXUIElementSetAttributeValue(text, kAXSelectedTextRangeAttribute as CFString, wanted) == .success,
              AXUIElementSetAttributeValue(text, kAXSelectedTextAttribute as CFString, "" as CFString) == .success else {
            throw ArisUndoError(message: "\(name) didn't let Aris remove the text it typed")
        }
        // Read back: what was there before is all that is left.
        if let value = attribute(text, kAXValueAttribute) as? String, value.utf16.count != mark.beforeLength {
            throw ArisUndoError(message: "\(name) changed the text differently than asked; check it")
        }
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
}
