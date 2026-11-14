//
//  ArisDictationPillCenter.swift
//  Aris
//
//  The live side of the dictation pill: it reads the dictation (ArisController's stage, ArisDictationState's
//  hands-free, finishing, copied words and error line), the app in front (its screen, whether it is full screen, its
//  icon), the lock screen and the setting, turns them into one ArisDictationPillDisplay (ArisDictationPillRules), and
//  keeps the panel on the screen being typed on, at its bottom centre above a showing Dock. The panel takes the pointer
//  only while it is on the pill, so everything around it stays the front app's; with nothing to show for 12 s the panel
//  is parked (ordered out) and nothing watches the pointer.
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
    static var on: Bool { Defaults[.arisDictationPill] }
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
    private var typedHoldTask: Task<Void, Never>?
    private var copyFeedbackTask: Task<Void, Never>?

    private var hovered = false
    private var screenLocked = false
    private var front: (screen: NSScreen?, fullScreen: Bool, icon: NSImage?) = (nil, false, nil)
    /// The screen a running dictation is on: it stays there until it ends.
    private var dictationScreen: NSScreen?
    private var stage = ArisDictationPillRules.Stage.none
    private var listeningSince: ContinuousClock.Instant?
    private var recordingSeconds = 0.0
    private var dictationCount = 0
    private var typedHold = false
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
            state.$fromPill.map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.arisDictationPill, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.arisDictationPillIdle, options: []).map { _ in () }.eraseToAnyPublisher(),
        ]
        // After the didSet (the publishers emit on willSet): the values read are the stored ones.
        Publishers.MergeMany(changes).receive(on: DispatchQueue.main)
            .sink { [weak self] in MainActor.assumeIsolated { self?.refresh() } }
            .store(in: &watches)
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { $0.frontChanged() }
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { $0.frontChanged() }
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { $0.frontChanged() }
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.setLocked(true) }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.setLocked(false) }
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

    /// The front app's frontmost window: its screen, whether it covers it, and the app's icon.
    private func frontChanged() {
        let app = NSWorkspace.shared.frontmostApplication
        let own = app?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        let window = own ? nil : app.flatMap { Self.frontWindow(pid: $0.processIdentifier) }
        let screens = NSScreen.screens
        let screen = window.flatMap { ArisDictationPillRules.screenIndex(for: $0, screens: screens.map(\.frame)) }.map { screens[$0] }
            ?? Self.pointerScreen() ?? NSScreen.main
        let full = screen.map { ArisDictationPillRules.isFullScreen(window: window, screen: $0.frame) } ?? false
        // Aris's own windows (Settings) keep the last app's place and icon.
        front = own ? (front.screen ?? screen, front.fullScreen, front.icon) : (screen, full, app?.icon)
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
            handsFree: state.locked, hovered: hovered, recovered: copiedWords, error: state.pillError ?? state.refusal,
            typedHold: typedHold)
        let phase = ArisDictationPillRules.phase(inputs)
        var shown = display
        shown.phase = phase
        if phase.shown { shown.drawn = phase }
        shown.appIcon = front.icon
        shown.fromPill = state.fromPill
        shown.recordingSeconds = recordingSeconds
        shown.dictation = dictationCount
        shown.english = ArisUIWords.english
        let key = ArisDictationKey.Choice.current.name(english: shown.english)
        shown.hint = ArisDictationPillWords.hint(english: shown.english, key: key)
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
            listeningSince = .now
            recordingSeconds = 0
            recoveredClosed = false
            dictationScreen = front.screen
        case .writing:
            if let since = listeningSince { recordingSeconds = Double((ContinuousClock.now - since) / .milliseconds(1)) / 1000 }
        case .typed:
            // The ring fills and holds 100 ms, then the pill goes back to the sliver (copied words show at once).
            typedHold = true
            typedHoldTask?.cancel()
            typedHoldTask = Task { [weak self] in
                try? await Task.sleep(for: ArisDictationPillRing.completeHold)
                guard !Task.isCancelled, let self else { return }
                self.typedHold = false
                self.refresh()
            }
        case .none:
            typedHold = false
            dictationScreen = nil
            listeningSince = nil
            if old != .none, ArisDictationState.shared.fromPill { ArisDictationState.shared.fromPill = false }
        case .cleaning:
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

    /// The panel takes the pointer only on the pill (with the recovered words' corner close).
    private func updatePointer() {
        guard let panel, panel.isVisible else { return }
        let phase = display.phase
        var rect = ArisDictationPillRules.pillRect(ArisDictationPillRules.size(phase)).offsetBy(dx: panel.frame.minX, dy: panel.frame.minY)
        if case .recovered = phase { rect = rect.insetBy(dx: -6, dy: -6) }
        let on = phase.shown && rect.contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == on { panel.ignoresMouseEvents = !on }
        if on != hovered {
            hovered = on
            refresh()
        }
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

    private func copyAgain() {
        let state = ArisDictationState.shared
        guard let text = state.lastText, state.copy(text) else { return }
        display.copiedAgain = true
        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task { [weak self] in
            try? await Task.sleep(for: ArisDictationCopy.feedback)
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
        ArisDictationPillView(display: center.display, audio: ArisController.shared.audioLevel, actions: center.actions)
    }
}
