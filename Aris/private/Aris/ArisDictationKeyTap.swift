//
//  ArisDictationKeyTap.swift
//  Aris
//
//  Watches the keyboard (listen only: nothing is changed or swallowed) for the right ⌥ and Esc, and hands each press,
//  with its time, to ArisDictationKey; at the double-tap window's end it delivers the tick. Its actions go to
//  ArisController. While hands-free is locked, and only then, a second, narrow tap takes Esc (down and up) so it
//  cancels the dictation without reaching the front app; every other key passes untouched. Also registers ⌃⌘V (paste
//  the last dictation, rebindable). Needs the Accessibility permission the app already uses for media keys; without
//  it, it looks again every 30 s.
//

import AppKit
import KeyboardShortcuts
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "dictation")

@MainActor
final class ArisDictationKeyTap {
    static let shared = ArisDictationKeyTap()

    private static let retry: Duration = .seconds(30)
    /// While Settings records a new dictation key, presses are the recorder's: nothing dictates.
    static var paused = false

    /// The modifiers that aren't the dictation key's own kind: one of them held with it means a shortcut, not dictation.
    private static func otherModifiers(_ key: ArisDictationKey.Choice) -> CGEventFlags {
        var all: CGEventFlags = [.maskCommand, .maskControl, .maskShift, .maskAlternate, .maskSecondaryFn]
        switch key.kind {
        case .option: all.remove(.maskAlternate)
        case .command: all.remove(.maskCommand)
        case .control: all.remove(.maskControl)
        case .shift: all.remove(.maskShift)
        case .function: all.remove(.maskSecondaryFn)
        }
        return all
    }
    private var tap: CFMachPort?
    private var state = ArisDictationKey.State()
    private var tick: Task<Void, Never>?
    /// The Esc-only tap, while hands-free is locked.
    private var escapeTap: CFMachPort?
    private var escapeSource: CFRunLoopSource?
    /// The Esc it took went down: its release is taken too, then the tap goes.
    private var escapeUpPending = false
    private var pasteLastRegistered = false

    func start() {
        registerPasteLast()
        guard tap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue) | CGEventMask(1 << CGEventType.keyDown.rawValue)
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                eventsOfInterest: mask, callback: { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<ArisDictationKeyTap>.fromOpaque(info).takeUnretainedValue()
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags
            let repeated = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            MainActor.assumeIsolated { me.handle(type, keyCode: keyCode, flags: flags, repeated: repeated) }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else {
            log.error("can't watch the right ⌥ yet (Accessibility); trying again in 30 s")
            Task { try? await Task.sleep(for: Self.retry); start() }
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        log.notice("dictation: hold \(ArisDictationKey.Choice.current.name(english: true), privacy: .public), tap twice for hands-free")
    }

    /// The app ended the dictation itself (the 20-minute cap): the next press starts fresh.
    func reset() {
        tick?.cancel()
        state.reset()
        updateEscapeTap()
    }

    /// A dictation started from the pill: hands-free, as after a double tap (the key's next press puts it in, Esc
    /// cancels).
    func lockFromPill() {
        tick?.cancel()
        state.lockFromPill(at: .now)
        updateEscapeTap()
    }

    /// The dictation is over, however it ended (the notch was clicked, it failed): Esc goes back to the apps.
    func dictationEnded() {
        guard ArisController.shared.dictation != .listening else { return }
        escapeUpPending = false
        // A press waiting for the last words keeps its place (its release still has to reach the queue).
        if !state.isIdle, !ArisController.shared.dictationQueue.waiting { reset() } else { updateEscapeTap() }
    }

    private func registerPasteLast() {
        guard !pasteLastRegistered else { return }
        pasteLastRegistered = true
        KeyboardShortcuts.onKeyUp(for: .pasteLastDictation) { ArisController.shared.pasteLastDictation() }
    }

    private func handle(_ type: CGEventType, keyCode: UInt16, flags: CGEventFlags, repeated: Bool) {
        let event: ArisDictationKey.Event
        // The key that dictates: the right ⌥, or the one picked in Settings.
        let key = ArisDictationKey.Choice.current
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        case .flagsChanged where keyCode == key.keyCode:
            if flags.rawValue & key.flag != 0 {
                event = .down(alone: flags.intersection(Self.otherModifiers(key)).isEmpty)
            } else {
                event = .up
            }
        case .keyDown where keyCode == ArisDictationKey.escapeKeyCode:
            event = .escape
        case .keyDown where repeated:
            return
        default:
            event = .otherKey
        }
        if Self.paused { return }
        // A press while the app isn't dictating any more (it was cancelled from the notch) starts fresh.
        if case .down = event, !state.isIdle, ArisController.shared.dictation != .listening { state.reset() }
        deliver(state.handle(event, at: .now))
    }

    private func deliver(_ action: ArisDictationKey.Action) {
        scheduleTick()
        updateEscapeTap()
        guard action != .none else { return }
        // Not inside the tap's callback: while the Esc tap is armed every keystroke waits on it, and a slow cancel
        // would get the tap disabled (bug hunt 11-06 #14). The take-or-pass answer above is already decided.
        DispatchQueue.main.async { ArisController.shared.dictationKey(action) }
    }

    private func scheduleTick() {
        tick?.cancel()
        guard let deadline = state.deadline else { return }
        tick = Task { [weak self] in
            try? await Task.sleep(until: deadline, clock: .continuous)
            guard !Task.isCancelled, let self else { return }
            self.deliver(self.state.handle(.tick, at: .now))
        }
    }

    // MARK: - Esc while hands-free

    private func updateEscapeTap() {
        let wanted = state.isLocked && ArisController.shared.dictation == .listening
        if wanted, escapeTap == nil {
            addEscapeTap()
        } else if !wanted, escapeTap != nil, !escapeUpPending {
            // Not from inside the tap's own callback.
            DispatchQueue.main.async { [self] in
                if !(state.isLocked && ArisController.shared.dictation == .listening) { removeEscapeTap() }
            }
        }
    }

    private func addEscapeTap() {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        escapeTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                      eventsOfInterest: mask, callback: { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<ArisDictationKeyTap>.fromOpaque(info).takeUnretainedValue()
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let taken = MainActor.assumeIsolated { me.escape(type, keyCode: keyCode) }
            return taken ? nil : Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let escapeTap else {
            log.error("dictation: can't hold Esc back (Accessibility); it also reaches the app")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, escapeTap, 0)
        escapeSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: escapeTap, enable: true)
    }

    private func removeEscapeTap() {
        if let escapeTap { CGEvent.tapEnable(tap: escapeTap, enable: false) }
        if let escapeSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), escapeSource, .commonModes) }
        escapeTap = nil
        escapeSource = nil
        escapeUpPending = false
    }

    /// Whether this event is the Esc that hands-free takes.
    private func escape(_ type: CGEventType, keyCode: UInt16) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let escapeTap { CGEvent.tapEnable(tap: escapeTap, enable: true) }
            return false
        case .keyDown where keyCode == ArisDictationKey.escapeKeyCode:
            guard state.isLocked, ArisController.shared.dictation == .listening else {
                updateEscapeTap()
                return false
            }
            escapeUpPending = true
            deliver(state.handle(.escape, at: .now))
            return true
        case .keyUp where keyCode == ArisDictationKey.escapeKeyCode && escapeUpPending:
            escapeUpPending = false
            updateEscapeTap()
            return true
        default:
            return false
        }
    }
}
