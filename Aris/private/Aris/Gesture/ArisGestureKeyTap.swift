//
//  ArisGestureKeyTap.swift
//  Aris
//
//  Watches the keyboard (listen only: nothing is changed or swallowed) for ⌥⇧ held alone, the circle gesture's key,
//  and hands each step to ArisController (ArisGestureKey decides). Separate from the right-⌥ dictation tap: right ⌥
//  alone dictates, either ⌥ with ⇧ draws. It hears modifier changes only; other keys only while ⌥⇧ is down. With
//  동그라미로 가리키기 off it does nothing. Needs the Accessibility permission; without it, it looks again after 30 s,
//  backing off to every 5 minutes.
//  A release the tap never heard can't leave the turn on (audit gesture-1): while a press is on, the real keys are
//  looked at every 50 ms, and again the moment a tap the system turned off comes back; keys found up end the turn as
//  the lost release would have (ArisGestureKey.ReleaseWatch decides).
//

import AppKit
import Defaults
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "gesture")

@MainActor
final class ArisGestureKeyTap {
    static let shared = ArisGestureKeyTap()

    private static let otherModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskSecondaryFn]
    /// Modifier changes only, always (never what is typed).
    private var tap: CFMachPort?
    /// Other keys, only while ⌥⇧ is down (ArisGestureKey.watchesKeys), so a key pressed then cancels the press.
    private var keyTap: CFMachPort?
    private var keySource: CFRunLoopSource?
    private var state = ArisGestureKey.State()
    private var debounce: DispatchWorkItem?
    private var attempts = 0
    /// The backstop for a lost release: its timer runs only while a press is on.
    private var releaseWatch = ArisGestureKey.ReleaseWatch()
    private var releaseTimer: DispatchSourceTimer?

    func start() {
        guard tap == nil else { return }
        tap = Self.makeTap(CGEventMask(1 << CGEventType.flagsChanged.rawValue), owner: self)
        guard let tap else {
            let wait = ArisGestureKey.retryDelay(attempt: attempts)
            attempts += 1
            log.error("gesture key: can't watch ⌥⇧ yet (Accessibility); trying again in \(Int(wait.components.seconds), privacy: .public) s")
            Task { try? await Task.sleep(for: wait); start() }
            return
        }
        attempts = 0
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        log.notice("gesture key: hold ⌥⇧ to circle")
    }

    private static func makeTap(_ mask: CGEventMask, owner: ArisGestureKeyTap) -> CFMachPort? {
        CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                          eventsOfInterest: mask, callback: { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<ArisGestureKeyTap>.fromOpaque(info).takeUnretainedValue()
            let flags = event.flags
            // When the key really moved (seconds since boot), however late the main thread hears of it.
            let at = NSEvent(cgEvent: event)?.timestamp ?? ProcessInfo.processInfo.systemUptime
            MainActor.assumeIsolated { me.handle(type, flags: flags, at: at) }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(owner).toOpaque())
    }

    /// Other keys are heard only while ⌥⇧ is down.
    private func watchKeys(_ on: Bool) {
        if on, keyTap == nil {
            guard let made = Self.makeTap(CGEventMask(1 << CGEventType.keyDown.rawValue), owner: self) else {
                // Without it another key can't cancel the press: the gesture isn't armed this time.
                log.error("gesture key: can't watch other keys while ⌥⇧ is down; not arming")
                state = ArisGestureKey.State()
                return
            }
            keyTap = made
            keySource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, made, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), keySource, .commonModes)
            CGEvent.tapEnable(tap: made, enable: true)
        } else if !on, let keyTap {
            CGEvent.tapEnable(tap: keyTap, enable: false)
            if let keySource { CFRunLoopRemoveSource(CFRunLoopGetMain(), keySource, .commonModes) }
            CFMachPortInvalidate(keyTap)
            self.keyTap = nil
            keySource = nil
        }
    }

    private func handle(_ type: CGEventType, flags: CGEventFlags, at seconds: Double) {
        // A tap the system turned off comes back on first, whatever the setting.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            if let keyTap { CGEvent.tapEnable(tap: keyTap, enable: true) }
            // Whatever happened while it was off was never heard: a release among it ends the turn now.
            log.notice("gesture key: the tap was turned off and is back on; reading the keys again")
            lookAtKeys(tapCameBack: true)
            return
        }
        // With 동그라미로 가리키기 off, ⌥⇧ does nothing at all.
        guard ArisGestureKey.listens(circleGesture: Defaults[.arisCircleGesture]) else {
            watchKeys(false)
            return
        }
        let at = seconds * 1000
        let event: ArisGestureKey.Event
        switch type {
        case .flagsChanged:
            let option = flags.contains(.maskAlternate), shift = flags.contains(.maskShift)
            watchKeys(ArisGestureKey.watchesKeys(option: option, shift: shift))
            // The other-keys tap couldn't start: this press isn't armed.
            if ArisGestureKey.watchesKeys(option: option, shift: shift), keyTap == nil { return }
            event = .modifiers(option: option, shift: shift, other: !flags.intersection(Self.otherModifiers).isEmpty, at: at)
        default:
            event = .otherKey(at: at)
        }
        feed(event)
    }

    private func feed(_ event: ArisGestureKey.Event) {
        // While a turn answers, a press waits longer before it counts (a key typed with ⌥⇧ leaves the answer alone).
        let action = state.handle(event, busy: ArisController.shared.gestureWaitsLonger)
        ArisPointerSampler.shared.key(held: state.pressing)
        scheduleDebounce()
        watchRelease(state.pressing)
        switch action {
        case .none: return
        case .start: log.notice("gesture key: ⌥⇧ held, starting")
        case .finish(let ms): log.notice("gesture key: released after \(Int(ms), privacy: .public) ms")
        case .cancel: log.notice("gesture key: another key while held, cancelled")
        case .tap(let ms): log.notice("gesture key: tapped while answering (\(Int(ms), privacy: .public) ms)")
        }
        ArisController.shared.gestureKey(action)
    }

    /// While a press waits out the debounce, a timer ticks it when it's due.
    private func scheduleDebounce() {
        guard let due = state.dueAt else {
            debounce?.cancel()
            debounce = nil
            return
        }
        guard debounce == nil else { return }
        let wait = max(0, due / 1000 - ProcessInfo.processInfo.systemUptime)
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.debounce = nil
                self.feed(.tick(at: max(due, ProcessInfo.processInfo.systemUptime * 1000)))
            }
        }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work)
    }

    // MARK: - A release the tap never heard

    /// The timer that looks at the real keys, on only while a press is on (nothing runs between presses).
    private func watchRelease(_ on: Bool) {
        if on, releaseTimer == nil {
            releaseWatch = ArisGestureKey.ReleaseWatch()
            let timer = DispatchSource.makeTimerSource(queue: .main)
            let interval = ArisGestureKey.ReleaseWatch.intervalMs
            timer.schedule(deadline: .now() + .milliseconds(interval), repeating: .milliseconds(interval), leeway: .milliseconds(10))
            timer.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.lookAtKeys(tapCameBack: false) }
            }
            timer.resume()
            releaseTimer = timer
        } else if !on, let timer = releaseTimer {
            timer.cancel()
            releaseTimer = nil
        }
    }

    /// Reads the keys as they really are now and feeds the release that was lost, if one was. With the setting off it
    /// still runs: a press that is on must end.
    private func lookAtKeys(tapCameBack: Bool) {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let option = flags.contains(.maskAlternate), shift = flags.contains(.maskShift)
        let other = !flags.intersection(Self.otherModifiers).isEmpty
        let at = ProcessInfo.processInfo.systemUptime * 1000
        let lost = tapCameBack
            ? ArisGestureKey.ReleaseWatch.afterTapCameBack(pressing: state.pressing, option: option, shift: shift, other: other, at: at)
            : releaseWatch.look(pressing: state.pressing, option: option, shift: shift, other: other, at: at)
        guard let lost else { return }
        log.notice("gesture key: ⌥⇧ is up but its release was never heard; ending the press")
        watchKeys(false)
        feed(lost)
    }
}
