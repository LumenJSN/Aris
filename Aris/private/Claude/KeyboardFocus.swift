//
//  KeyboardFocus.swift
//  Aris
//
//  Lets the keyboard answer an approval card (Y/N; 1–9, arrows, Return, Esc on questions) or
//  Aris's confirm card (Y/N),
//  but only while it is armed: pointer on the card, or the answer hotkey pressed. The notch
//  window takes key focus then and gives it back afterwards, and the key monitor exists
//  only for that time, so typing elsewhere never reaches the card.
//  Keys are matched by physical key code so they work under any input source (e.g. Korean).
//

import AppKit

@MainActor
enum KeyboardFocus {
    private static var monitor: Any?

    private enum KeyCode {
        static let y: UInt16 = 16
        static let n: UInt16 = 45
        static let escape: UInt16 = 53
        static let enter: UInt16 = 36
    }
    /// Armed for an Aris card that waits for a yes or no (askUser): Y or N answers it without hovering or taking key
    /// focus. A session event tap sees each key before the front app and lets ArisCardKeys decide: Y and N only for a
    /// fresh card after a quiet keyboard, each only when it stands alone (held back 250 ms, then passed on with what
    /// followed if the user was typing); every other key goes on untouched. Without Accessibility there is no tap: the
    /// card's buttons and hover still answer.
    private static var cardTap: CFMachPort?
    private static var cardSource: CFRunLoopSource?
    private static var cardKeys: ArisCardKeys?
    /// The Y or N held back, to send on if it turns out to be typing.
    private static var heldKey: CGEvent?
    /// Marks the keys Aris sends on itself, so its own tap lets them through.
    private static let resent: Int64 = 0x4172_6973

    private static var now: Double { ProcessInfo.processInfo.systemUptime }

    /// A hardware event: no process posted it (its source pid is 0), as ArisPanelKeys checks a panel press.
    nonisolated static func fromHardware(_ event: CGEvent) -> Bool {
        ArisPanelKeys.fromHardware(sourcePid: event.getIntegerValueField(.eventSourceUnixProcessID))
    }

    static func armForCard() {
        guard cardTap == nil else { return }
        // The key tap needs Accessibility; creating it without that asks macOS (QA BUG-55: the first card's Y popped the
        // prompt). Without it the card's buttons and typed answers still work; nothing is asked here.
        guard AXIsProcessTrusted() else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
                                          callback: { _, type, event, _ in
            guard type == .keyDown else {
                // Disabled by a timeout: on again (the card still waits).
                if type == .tapDisabledByTimeout, let tap = KeyboardFocus.cardTapUnsafe { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            guard event.getIntegerValueField(.eventSourceUserData) != KeyboardFocus.resent else { return Unmanaged.passUnretained(event) }
            // Only a key from the keyboard answers a card, the same source check as the panel press: a key another
            // process posted (a brain's `keys`, any synthetic event) passes through untouched (security review of batch 3).
            guard KeyboardFocus.fromHardware(event) else { return Unmanaged.passUnretained(event) }
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let plain = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty
            let repeated = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            let taken = MainActor.assumeIsolated { KeyboardFocus.cardKey(event, keyCode: keyCode, plain: plain, repeated: repeated) }
            return taken ? nil : Unmanaged.passUnretained(event)
        }, userInfo: nil) else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        cardTap = tap
        cardSource = source
        cardTapUnsafe = tap
        // Typing just before the card came counts toward the quiet the keyboard needs.
        let sinceKey = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        cardKeys = ArisCardKeys(presentedAt: now, lastKeyAt: sinceKey.isFinite ? now - sinceKey : nil)
    }

    static func releaseCard() {
        guard let tap = cardTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let cardSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), cardSource, .commonModes) }
        CFMachPortInvalidate(tap)
        cardTap = nil
        cardSource = nil
        cardTapUnsafe = nil
        cardKeys = nil
        // A Y or N still held when the card went: it was a letter after all.
        if let held = heldKey { resend([held]) }
        heldKey = nil
    }

    /// The tap's port for its own callback (which runs on the main run loop, outside the actor's view).
    nonisolated(unsafe) private static var cardTapUnsafe: CFMachPort?

    /// A key while the card's arm is on: true when it was taken (held, or it answered the card).
    static func cardKey(_ event: CGEvent, keyCode: UInt16, plain: Bool, repeated: Bool) -> Bool {
        let aris = ArisController.shared
        guard let keys = cardKeys, aris.session.question != nil, aris.session.question?.countdown != true,
              // Typing in a field of Aris's own card (the owner's ②A): Y and N are letters there.
              !KeyboardTextInput.takesKeys(NSApp.keyWindow?.firstResponder) else { return false }
        let key: ArisCardKeys.Key = !plain || repeated ? .other : keyCode == KeyCode.y ? .y : keyCode == KeyCode.n ? .n : .other
        let (next, decision) = keys.key(key, at: now)
        cardKeys = next
        switch decision {
        case .pass:
            return false
        case .holdYes, .holdNo:
            heldKey = event.copy()
            DispatchQueue.main.asyncAfter(deadline: .now() + ArisCardKeys.lone) {
                MainActor.assumeIsolated { answerIfAlone() }
            }
            return true
        case .passHeldThenThis:
            // The user is typing: the held key and this one go on to their app, in order.
            let held = heldKey
            heldKey = nil
            resend([held, event.copy()].compactMap { $0 })
            return true
        }
    }

    /// The held Y or N stood alone: it answers the card (a Y approves, an N declines).
    private static func answerIfAlone() {
        guard let keys = cardKeys else { return }
        let (next, answer) = keys.due(at: now)
        cardKeys = next
        guard let answer else { return }
        heldKey = nil
        if ArisController.shared.session.question != nil { ArisController.shared.answerQuestion(answer, source: .key) }
    }

    private static func resend(_ events: [CGEvent]) {
        for event in events {
            event.setIntegerValueField(.eventSourceUserData, value: resent)
            event.post(tap: .cgSessionEventTap)
        }
    }

    /// The app the answer hotkey brought Aris forward from, given the keyboard back when the arm goes.
    private static var activatedFrom: pid_t?

    /// `byHotkey`: the user's answer hotkey, which may bring Aris forward; a hover never does (KeyboardTextInput.arm).
    static func arm(_ armed: Bool, byHotkey: Bool = false) {
        ClaudeStore.keyboardArmed = armed
        // The notches and the side panels.
        let windows = NSApp.windows.filter { $0 is ArisNotchPanel || $0 is ArisSideWindow }
        // The window under the pointer first; armed by the hotkey the pointer may be anywhere, so fall back to the main screen's.
        let pointed: NSWindow? = windows.first { $0.frame.contains(NSEvent.mouseLocation) }
        let key: NSWindow? = windows.first { $0.isKeyWindow }
        let main: NSWindow? = windows.first { $0.screen == NSScreen.main && $0 is ArisNotchPanel }
        let window = pointed ?? key ?? main ?? windows.first
        if armed {
            let how = KeyboardTextInput.arm(byHotkey: byHotkey, arisActive: NSApp.isActive)
            if how.activate, !NSApp.isActive {
                activatedFrom = NSWorkspace.shared.frontmostApplication?.processIdentifier
                NSApp.activate()
            }
            if how.makeKey { window?.makeKey() }
        } else {
            // A field being typed in keeps its keyboard (ArisPanelKeys); otherwise the panel lets go, and the app the
            // hotkey came from gets it back.
            if !ArisPanelKeys.focus.editing { window?.resignKey() }
            if let app = activatedFrom.flatMap({ NSRunningApplication(processIdentifier: $0) }), NSApp.isActive, !ArisPanelKeys.focus.editing {
                app.activate()
            }
            activatedFrom = nil
        }
        setMonitor(armed)
    }

    private static func setMonitor(_ on: Bool) {
        if let existing = monitor { NSEvent.removeMonitor(existing); monitor = nil }
        guard on else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Only while Aris is the active app do keys reach a card (the follow-up's LOW): never a guess behind another app.
            guard KeyboardTextInput.answersCardKey(arisActive: NSApp.isActive),
                  event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
                  !event.isARepeat,
                  // Typing an "Other…" answer: keys belong to the text field. The read-only answer, selected, doesn't
                  // take them (KeyboardTextInput).
                  !KeyboardTextInput.takesKeys(event.window?.firstResponder) else { return event }
            // A dictated message counting down: esc stops it, ↩ sends it now.
            if ArisController.shared.session.question?.countdown == true, [KeyCode.escape, KeyCode.enter].contains(event.keyCode) {
                ArisController.shared.answerQuestion(event.keyCode == KeyCode.enter, source: .key)
                return nil
            }
            // The automatic check's stopped card: ↩ (its default) and esc are 하지 않기; Y and N as on any card below.
            if ArisController.shared.session.question?.stopped == true, [KeyCode.escape, KeyCode.enter].contains(event.keyCode) {
                ArisController.shared.answerQuestion(false, source: .key)
                return nil
            }
            // Aris asking before its AI acts comes first: Y allows, N declines.
            if ArisController.shared.session.question != nil, [KeyCode.y, KeyCode.n].contains(event.keyCode) {
                ArisController.shared.answerQuestion(event.keyCode == KeyCode.y, source: .key)
                return nil
            }
            // A Claude card answers only from its own page: on Aris's (the composer) it waits out of sight (QA BUG-22).
            guard KeyboardTextInput.claudeCardTakesKeys(claudePageShown: ArisNotchNavigation.shared.currentView == .claude,
                                                        responder: event.window?.firstResponder) else { return event }
            if ClaudeStore.shared.handleQuestionKey(event.keyCode) { return nil }
            guard let answer = answer(for: event.keyCode) else { return event }
            return ClaudeStore.shared.decideFirstTool(answer) ? nil : event
        }
    }

    static func answer(for keyCode: UInt16) -> ClaudeDecision? {
        switch keyCode {
        case KeyCode.y: return .allow
        case KeyCode.n: return .deny
        default: return nil
        }
    }
}
