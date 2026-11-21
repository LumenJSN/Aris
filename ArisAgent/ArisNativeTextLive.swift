//
//  ArisNativeTextLive.swift
//  aris-agent
//
//  The live half of ArisNativeTextLadder: the focused field of one window of one app read by Accessibility (its value,
//  whether it is a password field, whether its selected text can be set), the text inserted there, sent as key events
//  to the app's process, pasted through the pasteboard (a lazy item, ⌘V by the key that types "v" on the layout in use,
//  The user's clipboard back at once: ArisPasteSession), or typed for real after a brief turn in front in a gap in the user's
//  input (ArisNativeFocusGap), his front app and window given back after.
//

import AppKit
import ApplicationServices
import Foundation

struct ArisNativeTextLive: ArisNativeTextIO {
    let pid: Int32
    let window: Int
    let context: ArisNativeContext
    /// The field a click focused in the background, focused again once the app is in front (an Electron app doesn't
    /// keep a background focus).
    let pendingFocus: () -> AXUIElement?

    /// The app's focused element, when it is in the target window.
    private func focused() -> AXUIElement? {
        guard let element = ArisAX.focused(pid: pid) else { return nil }
        guard let owner = ArisAX.windowOf(element).flatMap(ArisAX.windowId) else { return ArisAX.focusedWindowId(pid: pid) == window ? element : nil }
        return owner == window ? element : nil
    }

    func read() -> ArisNativeFieldRead {
        guard let element = focused() else { return .notFocused }
        if ArisAX.string(element, kAXSubroleAttribute as String) == "AXSecureTextField" || ArisAX.role(element) == "AXSecureTextField" { return .secure }
        if let text = ArisAX.string(element, kAXValueAttribute as String) { return .value(text) }
        return .unreadable
    }

    var insertable: Bool { focused().map { ArisAX.settable($0, kAXSelectedTextAttribute as String) } ?? false }

    func insertSelected(_ text: String) -> Bool {
        guard let element = focused() else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, ArisPeekabooCommands.composed(text) as CFString) == .success
    }

    func postBackground(_ pieces: [ArisNativeInput.Piece]) { ArisNativeInput.send(pieces, route: .process(pid)) }

    func paste(_ text: String) -> Bool { ArisNativePaste.paste(text, route: .process(pid)) }

    func front(_ pieces: [ArisNativeInput.Piece], paste: String?) -> ArisNativeFrontResult {
        let target = ArisAX.window(pid: pid, id: window)
        let clock = ArisNativeOwnerClock(owner: context.owner, began: context.began)
        // Twice at most: the user's input during the raise gives the front back and the step waits for a gap again.
        for _ in 0..<2 {
            let turn: ArisNativeForeground
            switch ArisNativeForeground.take(pid: pid, window: target, clock: clock, job: context.job) {
            case .failure(.busy(let waited)): return .busy(waited: waited)
            case .failure(.failed): return .failed
            case .success(let made): turn = made
            }
            if let pending = pendingFocus() {
                AXUIElementSetAttributeValue(pending, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                usleep(150_000)
            }
            let now = ArisAX.focusedWindowId(pid: pid)
            guard now == nil || now == window else {
                turn.restore()
                return .failed
            }
            if turn.inputSinceRaise(clock) {
                turn.restore()
                continue
            }
            if let paste {
                _ = ArisNativePaste.paste(paste, route: .front)
            } else {
                ArisNativeInput.send(pieces, route: .front)
            }
            usleep(150_000)
            turn.restore()
            return .sent
        }
        return .busy(waited: ArisNativeFocusGap.limit)
    }

    func settle() { usleep(120_000) }
}

/// The pasteboard way in: the text as a lazy item on the general pasteboard, ⌘V (by the key that types "v" with ⌘ on
/// the layout in use) to the app's process or the front, and the user's clipboard back at once. The pasteboard serves the
/// item through the main run loop (ArisPasteSession), so this waits for it off the main thread.
enum ArisNativePaste {
    /// Quick: an app that reads it does so at once, and an unread item never stays on the user's clipboard for long.
    static let timing = ArisPasteSession.Timing(confirmWindow: 1.2, confirmedRestore: 0.4, unconfirmedRestore: 0.2, poll: 0.02)

    /// True when the app read the item (it pasted).
    static func paste(_ text: String, route: ArisNativeInput.Route) -> Bool {
        guard !Thread.isMainThread else { return false }
        let key = ArisNativeInput.chord("cmd+v")?.key ?? 9
        let done = DispatchSemaphore(value: 0)
        let box = ArisNativePasteBox()
        DispatchQueue.main.async {
            ArisPasteSession.start(text: ArisPeekabooCommands.composed(text), html: nil, timing: timing, press: {
                ArisNativeInput.press(key, flags: .maskCommand, route: route)
            }, confirmed: { read in
                box.read = read
                done.signal()
            })
        }
        _ = done.wait(timeout: .now() + timing.confirmWindow + 1)
        return box.read
    }
}

private final class ArisNativePasteBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false
    var read: Bool {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
