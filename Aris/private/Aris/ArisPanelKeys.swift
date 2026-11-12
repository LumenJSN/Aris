//
//  ArisPanelKeys.swift
//  Aris
//
//  The keyboard for a text field in one of Aris's non-activating panels (the notch: the composer, a card's editor
//  fields, Claude's "Other…"; the side panels: the to-do composer and its notes, the clipboard search). A panel that is
//  key without Aris being the active app shows a caret while what is typed goes to the app in front (QA BUG-22: a
//  to-do typed into WeChat, where Return sends). So a press on a field brings Aris forward and makes its panel key,
//  remembering the app the user was in; when the field lets go, or the panel is put away, that app gets the keyboard back.
//  Only a press (or the keyboard paths that open a panel to type: the clipboard's hotkey, files dropped on the composer)
//  takes it: a field that becomes first responder on its own loses its caret instead. Hovering takes nothing.
//  The press is seen by a local leftMouseDown monitor before AppKit hands it on. Aris is brought forward with
//  activate(ignoringOtherApps:): the cooperative activate() is refused while another app (Finder) is in front, and the
//  old same-moment "not key, no caret" check then ended the edit before the click landed (QA BUG-22 reopened, and the
//  drop path of BUG-24a). The pressed field gets the keyboard once the panel is key; a panel still not key after
//  keyCheckDelay shows no caret. ArisPanelFocus is the pure half (tested).
//

import AppKit
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "keys")

/// Who has the keyboard for a panel's field, and what to do next. Pure.
struct ArisPanelFocus: Equatable {
    enum Action: Equatable {
        case none
        /// Bring Aris forward and make the panel key.
        case takeKey
        /// Editing ended: give the keyboard back to this app (nil: Aris had it already).
        case giveBack(pid_t?)
        /// Editing ended where the owner chose (another app): nothing to give back.
        case forget
        /// A field became first responder with no press on it: it takes nothing, and its caret goes (follow-up M7).
        case dropCaret
        /// A field let go right after a press beside the fields: the field that press opens takes the keyboard over
        /// (ArisPanelKeys asks again after its hand-over wait, and gives the keyboard back only if no field has it by then).
        case awaitField
    }

    /// A field of a panel has the keyboard.
    private(set) var editing = false
    /// The app that had the keyboard before.
    private(set) var previous: pid_t?

    /// The pointer over a field: never takes the keyboard.
    func hovered() -> Action { .none }

    /// A press in a panel: on a field it takes the keyboard (the first one remembers the app in front); elsewhere nothing.
    mutating func pressed(onField: Bool, frontmost: pid_t?, own: pid_t) -> Action {
        guard onField else { return .none }
        if !editing { previous = frontmost == own ? nil : frontmost }
        editing = true
        return .takeKey
    }

    /// The panel's first responder changed: a field after a press keeps the keyboard; a field a press just opened (the
    /// to-do editor after +, a card's row after a click on its text: `pressedJustNow`) takes it as that press's; a field
    /// focused on its own (no press) takes nothing and drops its caret (follow-up M7); a field letting go right after a
    /// press beside the fields (`opening`: a press on no field, which may be opening one) waits for the field that press
    /// opens (the pencil on a sent request: the composer steps aside a moment before the request's editor is there; the
    /// second upgrade VM run, B12, where the keyboard went back to the app the user was in on the way); anything else ends
    /// editing and gives the keyboard back.
    mutating func responder(takesKeys: Bool, frontmost: pid_t? = nil, own: pid_t = 0, pressedJustNow: Bool = false,
                            opening: Bool = false) -> Action {
        if takesKeys {
            if editing { return .none }
            return pressedJustNow ? pressed(onField: true, frontmost: frontmost, own: own) : .dropCaret
        }
        guard editing else { return .none }
        if opening { return .awaitField }
        return finish(giveBack: true)
    }

    /// The panel was put away (or lost the keyboard): back to the app the user was in only while Aris still has it.
    mutating func closed(arisActive: Bool) -> Action {
        guard editing else { return .none }
        return finish(giveBack: arisActive)
    }

    /// The panel may be key: for a card's keys (armed) or a field being typed in.
    func canBecomeKey(armed: Bool) -> Bool { armed || editing }

    /// A caret only where the keys land.
    func caretAllowed(panelIsKey: Bool) -> Bool { editing && panelIsKey }

    private mutating func finish(giveBack: Bool) -> Action {
        let app = previous
        editing = false
        previous = nil
        return giveBack ? .giveBack(app) : .forget
    }
}

/// The last press seen in a panel, for a tap that follows it (the composer's pill): whose panel, and whether the
/// hardware made it. A tap takes the keyboard only after the user's own press in that panel: a click another process
/// posted takes nothing by the tap either, as it takes nothing by the press (security review 3, L3). Pure.
struct ArisPanelPress: Equatable {
    let window: ObjectIdentifier
    let hardware: Bool

    static func tapTakesKeyboard(_ last: ArisPanelPress?, in window: ObjectIdentifier) -> Bool {
        last.map { $0.window == window && $0.hardware } ?? false
    }
}

/// Keys typed into a panel in the moment after a press beside its fields (the pencil on a sent request: the composer
/// steps aside and the request's editor isn't first responder yet), held and given to the field that then has the
/// keyboard, in order (the third VM run: a key sent in the same instant as the pencil press was lost 3 of 4 times).
/// Held whatever had the keyboard before the press: the fourth VM run lost 5 of 7 such keys when no field of the panel
/// was being typed in (right after an answer, after Esc). Only keys Aris's own panel received are ever held (keys typed
/// into another app never reach Aris); keys no field takes by the end of the wait are dropped, never sent anywhere
/// else. Pure (tested).
struct ArisKeyHold<Key> {
    private(set) var until: TimeInterval?
    private(set) var held: [Key] = []
    /// The most keys held (a burst, not a paste).
    static var most: Int { 64 }

    var waiting: Bool { until != nil }

    /// A press beside the fields while one was being typed in: hold the keys for `length`.
    mutating func begin(now: TimeInterval, length: TimeInterval) {
        until = now + length
        held = []
    }

    /// A key typed now: true when it is held (it goes nowhere yet), false when it goes on as typed.
    mutating func take(_ key: Key, inPanel: Bool, now: TimeInterval) -> Bool {
        guard let until, inPanel else { return false }
        guard now <= until else {
            self.until = nil
            return false
        }
        guard held.count < Self.most else { return true }
        held.append(key)
        return true
    }

    /// A field has the keyboard (or the wait is over): the held keys, oldest first, and nothing is held any more.
    mutating func release() -> [Key] {
        let keys = held
        until = nil
        held = []
        return keys
    }
}

/// When ArisKeyHold holds keys, and what becomes of them. Pure (tested).
enum ArisKeyHoldRules {
    enum Outcome: Equatable {
        /// No field has the keyboard yet: keep holding.
        case wait
        /// A field of the panel has it: the held keys go to it.
        case send
        /// The wait is over with no field: they go nowhere.
        case drop
    }

    /// A press beside the panel's fields may open one (the pencil, a card's text): the keys typed in that moment wait
    /// for it, whether or not a field was being typed in before.
    static func holdsAfterPress(onField: Bool) -> Bool { !onField }

    /// Text keys are held; Esc, Return, Tab and ⌘ or ⌃ shortcuts go on as typed (they close, send or work the panel
    /// itself, and a held one would be lost when the press opens no field).
    static func holdable(keyCode: UInt16, command: Bool, control: Bool) -> Bool {
        !command && !control && ![53, 36, 76, 48].contains(keyCode)
    }

    /// `fieldReady`: the panel is key and a field of it is first responder. `final`: the wait is over.
    static func outcome(fieldReady: Bool, final: Bool) -> Outcome { fieldReady ? .send : final ? .drop : .wait }
}

/// A window whose fields take the keyboard through ArisPanelKeys (the notch, the side panels).
protocol ArisKeyPanel: NSWindow {}

/// The panels' side of it: the press monitor, and ArisNotchPanel and ArisSideWindow's makeFirstResponder and resignKey.
@MainActor
enum ArisPanelKeys {
    private(set) static var focus = ArisPanelFocus()
    private static var watching: NSObjectProtocol?
    private static var pressMonitor: Any?
    private static var keyMonitor: Any?
    /// Keys typed in the moment after a press beside the fields, for the field that press opens (ArisKeyHold).
    private static var keyHold = ArisKeyHold<NSEvent>()
    /// The last press in a panel: which window, and when (a field it opens takes the keyboard as its own).
    private static var lastPress: (window: ObjectIdentifier, at: TimeInterval, onField: Bool)?
    /// The last press in any panel, hardware or posted (ArisPanelPress).
    private static var lastPressSeen: ArisPanelPress?
    /// How long after a press a field it opened counts as pressed.
    static let pressOpensField: TimeInterval = 1.5
    /// How long a press waits for its panel to be key before its caret goes.
    static let keyCheckDelay: TimeInterval = 0.4
    /// How long a field that lets go right after a press in its panel waits for the field that press opens to take the
    /// keyboard over (the request editor after its pencil, while the composer steps aside) before giving it back.
    static let handOver: TimeInterval = 0.3
    /// Brings Aris forward (a seam for the tests). Never the cooperative activate(): refused while another app is in front.
    static var activate: @MainActor () -> Void = { NSApp.activate(ignoringOtherApps: true) }

    static func canBecomeKey(armed: Bool) -> Bool { focus.canBecomeKey(armed: armed) }

    /// Watches presses in Aris's panels (once, at launch): each is seen before AppKit hands it to the window.
    static func installPressMonitor() {
        guard pressMonitor == nil else { return }
        // Keys typed into a panel while a press hands the keyboard to the field it opens are held for that field.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                let flags = event.modifierFlags
                let holdable = ArisKeyHoldRules.holdable(keyCode: event.keyCode, command: flags.contains(.command), control: flags.contains(.control))
                return keyHold.take(event, inPanel: event.window is ArisKeyPanel && holdable, now: ProcessInfo.processInfo.systemUptime) ? nil : event
            }
        }
        pressMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            MainActor.assumeIsolated {
                guard let window = event.window, window is ArisKeyPanel else { return }
                // Only the user's own press: a click another process posted (a brain's click-at landing on the notch) takes
                // nothing (security review).
                let users = isUserPress(event)
                lastPressSeen = ArisPanelPress(window: ObjectIdentifier(window), hardware: users)
                guard users else {
                    log.notice("panel press posted by pid \(sourcePid(event), privacy: .public) ignored")
                    return
                }
                press(event, in: window)
            }
            return event
        }
    }

    /// The process that posted an event: 0 for the hardware (the window server stamps a posting process's pid).
    static func sourcePid(_ event: NSEvent) -> Int64 { event.cgEvent?.getIntegerValueField(.eventSourceUnixProcessID) ?? -1 }

    /// A press from the hardware, not posted by a process.
    nonisolated static func fromHardware(sourcePid: Int64) -> Bool { sourcePid == 0 }

    /// Whether a press is the user's (a seam for the tests, whose presses are posted).
    static var isUserPress: @MainActor (NSEvent) -> Bool = { fromHardware(sourcePid: sourcePid($0)) }

    /// A press in a panel, before AppKit hands it on: on a field, Aris comes forward and the panel becomes key first.
    static func press(_ event: NSEvent, in window: NSWindow) {
        guard event.type == .leftMouseDown, let content = window.contentView else { return }
        // hitTest takes the point in the content view's superview (the window's frame view: window coordinates).
        let hit = content.hitTest(content.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow)
        let field = fieldView(hit)
        lastPress = (ObjectIdentifier(window), ProcessInfo.processInfo.systemUptime, field != nil)
        // A press beside the fields (the pencil), whatever had the keyboard before: keys typed meanwhile wait for the
        // field it opens.
        if ArisKeyHoldRules.holdsAfterPress(onField: field != nil) {
            keyHold.begin(now: ProcessInfo.processInfo.systemUptime, length: handOver + keyHoldMargin)
            DispatchQueue.main.asyncAfter(deadline: .now() + handOver + keyHoldMargin) {
                MainActor.assumeIsolated { releaseHeldKeys(into: window, final: true) }
            }
        }
        perform(focus.pressed(onField: field != nil, frontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                              own: ProcessInfo.processInfo.processIdentifier), window: window, field: field)
    }

    /// A tap in a panel (the composer's pill) may take the keyboard: only when the press it ends was the user's own.
    static func tapTakesKeyboard(in window: NSWindow) -> Bool {
        let takes = ArisPanelPress.tapTakesKeyboard(lastPressSeen, in: ObjectIdentifier(window))
        if !takes { log.notice("a tap in a panel with no press of the user's before it takes no keyboard") }
        return takes
    }

    /// The keyboard opened a panel for typing (the clipboard's hotkey): as a press on a field.
    static func take(_ window: NSWindow) {
        perform(focus.pressed(onField: true, frontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                              own: ProcessInfo.processInfo.processIdentifier), window: window)
    }

    /// A little past the hand-over: the field the press opens has had its time to take the keyboard.
    static let keyHoldMargin: TimeInterval = 0.2

    /// The held keys go to the field of this panel that has the keyboard now, in order. With none yet they wait, and
    /// at the end of the wait (`final`) they go nowhere: only ever into this panel, which received them.
    private static func releaseHeldKeys(into window: NSWindow, final: Bool) {
        guard keyHold.waiting else { return }
        let ready = window.isKeyWindow && (KeyboardTextInput.takesKeys(window.firstResponder) || isField(window.firstResponder as? NSView))
        switch ArisKeyHoldRules.outcome(fieldReady: ready, final: final) {
        case .wait:
            return
        case .send:
            keyHold.release().forEach(window.sendEvent)
        case .drop:
            let keys = keyHold.release()
            if !keys.isEmpty { log.notice("\(keys.count, privacy: .public) keys typed during a hand-over found no field") }
        }
    }

    /// The panel's first responder changed.
    static func responderChanged(_ responder: NSResponder?, in window: NSWindow) {
        // A field took the keyboard while keys were held for it: they go to it once the change settles.
        if keyHold.waiting, KeyboardTextInput.takesKeys(responder) || isField(responder as? NSView) {
            DispatchQueue.main.async { MainActor.assumeIsolated { releaseHeldKeys(into: window, final: false) } }
        }
        let pressed = pressedJustNow(in: window), opening = pressed && lastPress?.onField == false
        perform(focus.responder(takesKeys: KeyboardTextInput.takesKeys(responder) || isField(responder as? NSView),
                                frontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                                own: ProcessInfo.processInfo.processIdentifier, pressedJustNow: pressed, opening: opening), window: window)
    }

    /// The panel lost the keyboard to something the owner chose (another app or window): nothing is taken back from it.
    static func lostKey(_ window: NSWindow) {
        perform(focus.closed(arisActive: false), window: window)
    }

    /// Aris put the panel away (the notch closed, a side panel collapsed): the caret goes, and so does the keyboard.
    static func closed(_ window: NSWindow?) {
        if focus.editing, let window, KeyboardTextInput.takesKeys(window.firstResponder) { _ = window.makeFirstResponder(nil) }
        perform(focus.closed(arisActive: NSApp.isActive), window: window)
    }

    /// Whether a view (or one it sits in) is an editable text field or text view.
    static func isField(_ view: NSView?) -> Bool { fieldView(view) != nil }

    /// The editable text field or text view a view is (or sits in).
    static func fieldView(_ view: NSView?) -> NSView? {
        var current = view
        while let view = current {
            if let text = view as? NSTextView { return text.isEditable ? text : nil }
            if let field = view as? NSTextField { return field.isEditable ? field : nil }
            current = view.superview
        }
        return nil
    }

    private static func perform(_ action: ArisPanelFocus.Action, window: NSWindow?, field: NSView? = nil) {
        switch action {
        case .none, .forget:
            return
        case .awaitField:
            // Once the field the press opened has had time to take the keyboard: given back only if none has it.
            DispatchQueue.main.asyncAfter(deadline: .now() + handOver) {
                MainActor.assumeIsolated {
                    guard let window else { return }
                    let responder = window.firstResponder
                    perform(focus.responder(takesKeys: KeyboardTextInput.takesKeys(responder) || isField(responder as? NSView)), window: window)
                }
            }
        case .dropCaret:
            // Once the change settles (never inside makeFirstResponder): no press came, so no caret.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let window, !focus.editing, KeyboardTextInput.takesKeys(window.firstResponder) else { return }
                    _ = window.makeFirstResponder(nil)
                }
            }
        case .takeKey:
            watchEditing()
            if !NSApp.isActive { activate() }
            window?.makeKey()
            guard let window else { return }
            // Once AppKit has handled the press: the pressed field has the keyboard (a SwiftUI field in a panel that
            // wasn't key can miss the first click).
            if let field {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard focus.editing, window.isKeyWindow, !owns(window.firstResponder, field) else { return }
                        _ = window.makeFirstResponder(field)
                    }
                }
            }
            // Activation takes a moment: only a panel still not key then loses the caret (the keys wouldn't land there).
            DispatchQueue.main.asyncAfter(deadline: .now() + keyCheckDelay) {
                MainActor.assumeIsolated {
                    guard focus.editing, !focus.caretAllowed(panelIsKey: window.isKeyWindow) else { return }
                    // One more try now that Aris had time to come forward.
                    window.makeKey()
                    guard !window.isKeyWindow else { return }
                    if KeyboardTextInput.takesKeys(window.firstResponder) { _ = window.makeFirstResponder(nil) }
                    focus = ArisPanelFocus()
                }
            }
        case .giveBack(let app):
            giveBack(app)
        }
    }

    /// Gives the keyboard back to the app the user was in (a seam for the tests, which count it), only while Aris has it.
    static var giveBack: @MainActor (pid_t?) -> Void = { app in
        guard let app, NSApp.isActive, let running = NSRunningApplication(processIdentifier: app), !running.isTerminated else { return }
        running.activate()
    }

    /// The responder is the field or its field editor.
    private static func owns(_ responder: NSResponder?, _ field: NSView) -> Bool {
        guard let responder else { return false }
        if responder === field { return true }
        if let editor = responder as? NSTextView, editor.isFieldEditor, editor.delegate as? NSView === field { return true }
        return false
    }

    /// A press in this window a moment ago (a field it opens takes the keyboard as that press's).
    private static func pressedJustNow(in window: NSWindow) -> Bool {
        lastPress.map { $0.window == ObjectIdentifier(window) && ProcessInfo.processInfo.systemUptime - $0.at < pressOpensField } ?? false
    }

    /// A field that ends editing without the window's first responder being set (it was removed, Esc): checked once
    /// the change settles, so moving to the next field keeps the keyboard.
    private static func watchEditing() {
        guard watching == nil else { return }
        watching = NotificationCenter.default.addObserver(forName: NSText.didEndEditingNotification, object: nil, queue: .main) { note in
            let window = (note.object as? NSView)?.window
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard focus.editing, let window else { return }
                    responderChanged(window.firstResponder, in: window)
                }
            }
        }
    }
}
