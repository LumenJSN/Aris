//
//  ArisFieldTargetLive.swift
//  aris-agent
//
//  The live half of ArisFieldWrite: the field a look read kept by its Accessibility element (ArisLook), and the
//  rewrite or draft written into that element when the app sends it back with the look's token (/insert "target"):
//  AXSelectedText set on it, else ⌘V to its app's process while it has that app's focus, else a brief turn in front
//  in a gap in the user's input with that element focused. Never ⌘V to whatever has the keyboard: typing the request into
//  the notch makes that Aris itself (VM run 2, h1).
//

import AppKit
import ApplicationServices
import Carbon
import Foundation

enum ArisFieldTargetLive {
    /// The field the look read (its app's focused element), kept when it takes text; nil for anything else.
    static func capture(field: AXUIElement, pid: Int32, app: String, bundleId: String?) -> ArisFieldTarget? {
        let role = ArisAX.role(field), subrole = ArisAX.string(field, kAXSubroleAttribute as String)
        let secure = role == "AXSecureTextField" || subrole == "AXSecureTextField"
        let takesText = ArisAX.settable(field, kAXSelectedTextAttribute as String) || ArisAX.settable(field, kAXValueAttribute as String)
        guard secure || takesText else { return nil }
        // A password field's selection is never read.
        let selection = secure ? nil : ArisAX.string(field, kAXSelectedTextAttribute as String).flatMap { $0.isEmpty ? nil : $0 }
        let range = ArisAX.selectedRange(field).map { ArisTextRange(location: $0.location, length: $0.length) }
        return ArisFieldTarget(pid: pid, bundleId: bundleId, app: app, window: ArisAX.windowOf(field).flatMap(ArisAX.windowId), element: field,
                               selection: selection, range: range, secure: secure)
    }

    /// Writes `text` into the field kept under `token`, holding the keys and pointer (ArisDesktopLock) while it does.
    /// Off the main thread (a paste waits on the main run loop: ArisNativePaste).
    static func write(_ text: String, token: String) -> ArisFieldWrite.Outcome {
        write(text, token: token, caretOnly: false).outcome
    }

    /// `caretOnly`: only at a caret with nothing selected (ArisFieldWrite.caretRefusal); what it added then comes back as
    /// an undo mark (ArisApps.TextUndo), so "되돌려" takes exactly that text out again (twelfth VM run, S3u).
    static func write(_ text: String, token: String, caretOnly: Bool) -> (outcome: ArisFieldWrite.Outcome, undo: String?, app: String?) {
        guard let target = ArisFieldTargetDesk.shared.take(token) else { return (.refused(ArisFieldWrite.stale), nil, nil) }
        guard AXIsProcessTrusted() else { return (.refused(ArisInsertRefusal.needsAccessibility), nil, nil) }
        if IsSecureEventInputEnabled() { return (.refused(ArisFieldWrite.secureField), nil, nil) }
        let owner = ArisDesktopLock.oneOff("field-write")
        if ArisDesktopLock.shared.take(owner) != nil { return (.refused(ArisDesktopLockWords.insertRefusal), nil, nil) }
        defer { ArisDesktopLock.shared.release(owner) }
        let io = ArisFieldTargetIO(target: target, owner: owner)
        guard caretOnly else { return (ArisFieldWrite.run(text, target: target, io: io), nil, nil) }
        if let refusal = ArisFieldWrite.caretRefusal(target, io: io) { return (.refused(refusal), nil, nil) }
        let before = io.value()
        let outcome = ArisFieldWrite.run(text, target: target, io: io)
        guard outcome.failure == nil, let before, let after = io.value(), let bundle = target.bundleId,
              case .textInserted(_, let element, _)? = ArisApps.TextUndo.recipe(app: target.app, bundle: bundle,
                                                                               role: ArisAX.role(target.element as! AXUIElement), label: "",
                                                                               before: before, after: after) else { return (outcome, nil, nil) }
        return (outcome, element, target.app)
    }
}

/// The kept element, as the write reaches it.
struct ArisFieldTargetIO: ArisFieldWriteIO {
    let target: ArisFieldTarget
    let owner: String
    var began = Date()

    private var element: AXUIElement { ArisAX.timed(target.element as! AXUIElement) }

    var alive: Bool {
        NSRunningApplication(processIdentifier: target.pid) != nil && ArisAX.copy(element, kAXRoleAttribute as String).error == .success
    }

    func value() -> String? { ArisAX.string(element, kAXValueAttribute as String) }

    func selectedRange() -> ArisTextRange? { ArisAX.selectedRange(element).map { ArisTextRange(location: $0.location, length: $0.length) } }

    func selectedText() -> String? { ArisAX.string(element, kAXSelectedTextAttribute as String) }

    func select(_ range: ArisTextRange) -> Bool {
        var raw = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &raw) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success
    }

    var insertable: Bool { ArisAX.settable(element, kAXSelectedTextAttribute as String) }

    func insertSelected(_ text: String) -> Bool {
        AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, ArisPeekabooCommands.composed(text) as CFString) == .success
    }

    var focusedInApp: Bool { ArisAX.focused(pid: target.pid).map { CFEqual($0, element) } ?? false }

    func paste(_ text: String) -> Bool { ArisNativePaste.paste(text, route: .process(target.pid)) }

    func front(_ text: String, range: ArisTextRange?) -> ArisNativeFrontResult {
        let window = target.window.flatMap { ArisAX.window(pid: target.pid, id: $0) } ?? ArisAX.windowOf(element)
        let clock = ArisNativeOwnerClock(owner: owner, began: began)
        // Twice at most: the user's input during the raise gives the front back and the write waits for a gap again.
        for _ in 0..<2 {
            let turn: ArisNativeForeground
            switch ArisNativeForeground.take(pid: target.pid, window: window, clock: clock, job: false) {
            case .failure(.busy(let waited)): return .busy(waited: waited)
            case .failure(.failed): return .failed
            case .success(let made): turn = made
            }
            AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            usleep(150_000)
            guard ArisFrontLive.focusedPid() == target.pid, focusedInApp else {
                turn.restore()
                return .failed
            }
            if let range { _ = select(range) }
            if turn.inputSinceRaise(clock) {
                turn.restore()
                continue
            }
            _ = ArisNativePaste.paste(text, route: .front)
            usleep(150_000)
            // The app he asked about stays in front; only another app than Aris (whose notch he typed in) is given back.
            if !ArisFieldTargetIO.isAris(turn.previousPid) { turn.restore() }
            return .sent
        }
        return .busy(waited: ArisNativeFocusGap.limit)
    }

    func settle() { usleep(120_000) }

    static func isAris(_ pid: Int32?) -> Bool {
        guard let pid, let id = ArisFrontLive.bundleId(pid)?.lowercased() else { return false }
        return ArisInsertRefusal.refusedApps.contains(id)
    }
}
