//
//  ArisDictationPillCenter.swift
//  Aris
//
//  The live side of the dictation pill: it reads the dictation (ArisController's stage, ArisDictationState's
//  hands-free, finishing, copied words and error line), the app in front (its screen, whether it is full
//  screen), the lock screen and the setting, turns them into one ArisDictationPillDisplay (ArisDictationPillRules), and
//  keeps the panel on the screen being typed on, at its bottom centre above a showing Dock. The panel takes the pointer
//  only while it is on the pill, so everything around it stays the front app's; with nothing to show for 12 s the panel
//  is parked (ordered out) and nothing watches the pointer. As the reference pill does, the hover follows the pointer
//  at once on the pill and 10 / 6 around it (12 more once grown), then holds 100 ms (ArisDictationPillRules.HoverLock),
//  so an edge that flickers never jolts it; a size change turned back mid-way takes only the share it covered
//  (ArisDictationPillRules.Reversal).
//

import AppKit
import Combine
import Defaults
import os
import SwiftUI

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "dictation-pill")

extension Defaults.Keys {
    /// Settings › 받아쓰기 › 받아쓰기 알약 보이기: dictation shows in the pill at the bottom of the screen (the notch stays
    /// quiet for it). Off: the notch shows it as before.
    static let arisDictationPill = Key<Bool>("arisDictationPill", default: true)
    /// Settings › 받아쓰기 › 쉴 때도 보이기: the idle sliver (and its hover, the click to start) shows between dictations.
    /// Off: the pill shows only while a dictation runs and goes away once it ended.
    static let arisDictationPillIdle = Key<Bool>("arisDictationPillIdle", default: true)
}

/// Whether the pill takes dictation on this Mac now (every macOS the app runs on can dictate: ArisListenEngine).
enum ArisDictationPillGate {
    static var on: Bool { ArisDictationSwitch.pillOn(dictation: Defaults[.arisDictationOn], pill: Defaults[.arisDictationPill]) }
}

@MainActor
final class ArisDictationPillCenter: ObservableObject {
    static let shared = ArisDictationPillCenter()

    @Published private(set) var display = ArisDictationPillDisplay()

    private var panel: ArisDictationPillPanel?
    private var watches: Set<AnyCancellable> = []
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var monitors: [Any] = []
    private var parkTask: Task<Void, Never>?
    private var copyFeedbackTask: Task<Void, Never>?

    /// The pointer on the pill as drawn (the panel takes it; the copied words stay up under it).
    private var hovered = false
    /// The pointer's hover as the pill follows it (at once, then held 100 ms).
    private var hoverLock = ArisDictationPillRules.HoverLock()
    private var hoverWait: Task<Void, Never>?
    /// The size change running now, for a reversal's shortening.
    private var reversal = ArisDictationPillRules.Reversal()
    /// The level's state across redraws: it starts over with each dictation.
    let level = ArisDictationPillLevel()
    private var screenLocked = false
    private var front: (screen: NSScreen?, fullScreen: Bool) = (nil, false)
    /// The screen a running dictation is on: it stays there until it ends.
    private var dictationScreen: NSScreen?
    private var stage = ArisDictationPillRules.Stage.none
    private var dictationCount = 0
    private var recoveredClosed = false
    private var started = false

    private init() {}

    // MARK: - Start

    func start() {
        guard !started else { return }
        started = true
        let aris = ArisController.shared, state = ArisDictationState.shared
        let changes: [AnyPublisher<Void, Never>] = [
            aris.$dictation.map { _ in () }.eraseToAnyPublisher(),
            aris.$session.map { _ in () }.eraseToAnyPublisher(),
            state.$locked.map { _ in () }.eraseToAnyPublisher(),
            state.$finishing.map { _ in () }.eraseToAnyPublisher(),
            state.$copied.map { _ in () }.eraseToAnyPublisher(),
            state.$pillError.map { _ in () }.eraseToAnyPublisher(),
            state.$refusal.map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.arisDictationOn, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.arisDictationPill, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.arisDictationPillIdle, options: []).map { _ in () }.eraseToAnyPublisher(),
        ]
        // After the didSet (the publishers emit on willSet): the values read are the stored ones.
        Publishers.MergeMany(changes).receive(on: DispatchQueue.main)
            .sink { [weak self] in MainActor.assumeIsolated { self?.refresh() } }
            .store(in: &watches)
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { $0.frontChanged() }
        // The front app, the displays and the lock, as ArisWorld hears them (one observer for every feature).
        ArisWorld.shared.subscribe([.frontApp, .displays, .screen]) { [weak self] change, _ in
            switch change {
            case .frontApp, .displays: self?.frontChanged()
            case .screenLocked(let locked): self?.setLocked(locked)
            default: break
            }
        }
        screenLocked = ArisController.screenIsAwayNow()
        frontChanged()
        log.notice("dictation pill: \(ArisDictationPillGate.on ? "on" : "off", privacy: .public)")
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ action: @escaping @MainActor @Sendable (ArisDictationPillCenter) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { action(self) } }
        }
        observers.append((center, token))
    }

    private func setLocked(_ locked: Bool) {
        screenLocked = locked
        refresh()
    }

    // MARK: - The app in front

    /// The front app's frontmost window: its screen and whether it covers it.
    private func frontChanged() {
        let app = NSWorkspace.shared.frontmostApplication
        let own = app?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        let window = own ? nil : app.flatMap { Self.frontWindow(pid: $0.processIdentifier) }
        let screens = NSScreen.screens
        let screen = window.flatMap { ArisDictationPillRules.screenIndex(for: $0, screens: screens.map(\.frame)) }.map { screens[$0] }
            ?? Self.pointerScreen() ?? NSScreen.main
        let full = screen.map { ArisDictationPillRules.isFullScreen(window: window, screen: $0.frame) } ?? false
        // Aris's own windows (Settings) keep the last app's place.
        front = own ? (front.screen ?? screen, front.fullScreen) : (screen, full)
        refresh()
    }

    /// The app's frontmost ordinary window (layer 0) in AppKit's coordinates.
    private static func frontWindow(pid: pid_t) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let primary = NSScreen.screens.first?.frame.height else { return nil }
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? Int).map(pid_t.init) == pid,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let w = bounds["Width"], let h = bounds["Height"], w > 50, h > 50 else { continue }
            let rect = CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: w, height: h)
            return ArisDictationPillRules.appKitRect(cg: rect, primaryHeight: primary)
        }
        return nil
    }

    private static func pointerScreen() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(point) }
    }

    // MARK: - What it shows

    private static func stage(_ dictation: ArisDictationStage?, finishing: Bool) -> ArisDictationPillRules.Stage {
        switch dictation {
        case nil: .none
        case .listening: finishing ? .writing : .listening
        case .cleaning: .cleaning
        case .typed: .typed
        }
    }

    private func refresh() {
        let aris = ArisController.shared, state = ArisDictationState.shared
        let next = Self.stage(aris.dictation, finishing: state.finishing)
        if next != stage { stageChanged(from: stage, to: next) }
        let copiedWords = next == .typed && state.copied && !recoveredClosed ? state.lastText : nil
        let inputs = ArisDictationPillRules.Inputs(
            enabled: ArisDictationPillGate.on, showIdle: Defaults[.arisDictationPillIdle], screenLocked: screenLocked, fullScreen: front.fullScreen, stage: next,
            handsFree: state.locked, hovered: hoverLock.shown, recovered: copiedWords, error: state.pillError ?? state.refusal)
        let phase = ArisDictationPillRules.phase(inputs)
        var shown = display
        // The size's move: 0.1 s, or the share covered when it turns back; set only when the phase changes, so a
        // refresh mid-move keeps it.
        if phase != display.phase {
            reversal = reversal.changing(to: phase, at: Self.clock())
            shown.sizeDuration = reversal.duration
        }
        shown.phase = phase
        if phase.shown { shown.drawn = phase }
        shown.dictation = dictationCount
        shown.pointerOn = hovered
        shown.english = ArisUIWords.english
        shown.light = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .aqua
        let key = ArisDictationKey.Choice.current.name(english: shown.english)
        shown.hint = ArisDictationPillWords.hint(english: shown.english, key: key)
        shown.finishHint = ArisDictationPillWords.finishHint(english: shown.english, key: key)
        // The copied words stay up while the pointer is on them (as the notch's card did).
        if inputs.enabled { state.cardHovered = copiedWords != nil && hovered }
        if shown != display { display = shown }
        apply(phase)
    }

    private func stageChanged(from old: ArisDictationPillRules.Stage, to new: ArisDictationPillRules.Stage) {
        stage = new
        switch new {
        case .listening:
            dictationCount += 1
            level.reset()
            recoveredClosed = false
            dictationScreen = front.screen
        case .none:
            dictationScreen = nil
            if old != .none, ArisDictationState.shared.fromPill { ArisDictationState.shared.fromPill = false }
        case .writing, .cleaning, .typed:
            // Typed: straight back to the sliver, as the reference pill does (copied words show at once).
            break
        }
    }

    // MARK: - The panel

    private func apply(_ phase: ArisDictationPillPhase) {
        if phase.shown {
            parkTask?.cancel()
            parkTask = nil
            let panel = self.panel ?? makePanel()
            place(panel)
            if !panel.isVisible { panel.orderFrontRegardless() }
            startPointerWatch()
            updatePointer()
        } else {
            hovered = false
            clearHover()
            stopPointerWatch()
            panel?.ignoresMouseEvents = true
            guard parkTask == nil, panel?.isVisible == true else { return }
            parkTask = Task { [weak self] in
                try? await Task.sleep(for: ArisDictationPillRules.parkAfter)
                guard !Task.isCancelled, let self, !self.display.phase.shown else { return }
                self.panel?.orderOut(nil)
                self.parkTask = nil
            }
        }
    }

    private func makePanel() -> ArisDictationPillPanel {
        let panel = ArisDictationPillPanel()
        let host = ArisDictationPillHostingView(rootView: ArisDictationPillHost(center: self))
        host.frame = CGRect(origin: .zero, size: ArisDictationPillRules.windowSize)
        panel.contentView = host
        self.panel = panel
        return panel
    }

    private func place(_ panel: ArisDictationPillPanel) {
        guard let screen = dictationScreen ?? front.screen ?? NSScreen.main else { return }
        let frame = ArisDictationPillRules.windowFrame(frame: screen.frame, visible: screen.visibleFrame)
        if panel.frame != frame { panel.setFrame(frame, display: false) }
    }

    // MARK: - The pointer

    private func startPointerWatch() {
        guard monitors.isEmpty else { return }
        let moved: () -> Void = { [weak self] in self?.updatePointer() }
        let kinds: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: kinds, handler: { _ in MainActor.assumeIsolated { moved() } }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: kinds, handler: { event in
            MainActor.assumeIsolated { moved() }
            return event
        }) {
            monitors.append(local)
        }
    }

    private func stopPointerWatch() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }

    /// Seconds on a steady clock (the hover's hold and a reversal's timing).
    private static func clock() -> Double { ProcessInfo.processInfo.systemUptime }

    /// The panel takes the pointer only on the pill. The hover follows the pointer on the pill and around it
    /// (ArisDictationPillRules.pointerRect), held 100 ms after each change.
    private func updatePointer() {
        guard let panel, panel.isVisible else { return }
        let phase = display.phase
        let origin = CGPoint(x: panel.frame.minX, y: panel.frame.minY)
        let rect = ArisDictationPillRules.pillRect(display.size).offsetBy(dx: origin.x, dy: origin.y)
        let on = phase.shown && rect.contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == on { panel.ignoresMouseEvents = !on }
        let zone = ArisDictationPillRules.pointerRect(phase, size: display.size).offsetBy(dx: origin.x, dy: origin.y)
        let wasShown = hoverLock.shown
        point(at: phase.shown && zone.contains(NSEvent.mouseLocation))
        if on != hovered || hoverLock.shown != wasShown {
            hovered = on
            refresh()
        }
    }

    /// Tells the hover where the pointer is, and waits for its hold's end when it has one.
    private func point(at on: Bool) {
        guard on != hoverLock.pointer else { return }
        schedule(hoverLock.point(on, at: Self.clock()))
    }

    private func schedule(_ due: Double?) {
        hoverWait?.cancel()
        hoverWait = nil
        guard let due else { return }
        hoverWait = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, due - Self.clock())))
            guard !Task.isCancelled, let self else { return }
            self.hoverWait = nil
            let was = self.hoverLock.shown
            let next = self.hoverLock.expire(at: Self.clock())
            if self.hoverLock.shown != was { self.refresh() }
            if next != nil { self.schedule(next) }
        }
    }

    /// Nothing to hover (the pill went away): no hold, no hover.
    private func clearHover() {
        hoverWait?.cancel()
        hoverWait = nil
        hoverLock.clear()
    }

    // MARK: - Actions

    var actions: ArisDictationPillActions {
        ArisDictationPillActions(
            start: { ArisController.shared.startDictationFromPill() },
            cancel: { ArisController.shared.cancelDictationFromPill() },
            finish: { ArisController.shared.finishDictationFromPill() },
            copyAgain: { [weak self] in self?.copyAgain() },
            closeRecovered: { [weak self] in self?.closeRecovered() })
    }

    /// Copies the words again; the card's label says so for 1.2 s and the card stays.
    private func copyAgain() {
        let state = ArisDictationState.shared
        guard let text = state.lastText, state.copy(text) else { return }
        display.copiedAgain = true
        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task { [weak self] in
            try? await Task.sleep(for: ArisDictationPillRecoveredLayout.againLinger)
            guard !Task.isCancelled else { return }
            self?.display.copiedAgain = false
        }
    }

    private func closeRecovered() {
        recoveredClosed = true
        ArisDictationState.shared.cardHovered = false
        refresh()
    }
}

/// The panel's view: the pill as the center has it.
struct ArisDictationPillHost: View {
    @ObservedObject var center: ArisDictationPillCenter

    var body: some View {
        ArisDictationPillView(display: center.display, audio: ArisController.shared.audioLevel, level: center.level, actions: center.actions)
    }
}
