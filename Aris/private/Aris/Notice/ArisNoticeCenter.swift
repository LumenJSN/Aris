//
//  ArisNoticeCenter.swift
//  Aris
//
//  The live side of the notification cards: the queue (ArisNoticeQueue), the panel under the notch (ArisNoticePanel)
//  on the notch's display, what each button does, and the pointer: the panel takes clicks only while the pointer is
//  on a card, so everything around the cards stays the frontmost app's. The cards step aside while the notch is open
//  or the setup shows and come back as they were. Nothing here decides when a card may come up: ArisController.notify
//  waits for the moment (its turn among Aris's news, a pause) and asks `mayShow` for the rest. Nothing runs while no
//  card is up: no timer, no pointer watch, the panel off screen.
//

import AppKit
import Combine
import os
import SwiftUI

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "notice")

@MainActor
final class ArisNoticeCenter: ObservableObject {
    static let shared = ArisNoticeCenter()

    @Published private(set) var queue = ArisNoticeQueue()
    @Published private(set) var hovered: UUID?
    /// The cards step aside (faded out) while the notch is open or the setup shows.
    @Published private(set) var aside = false
    @Published private(set) var material: ArisNoticeMaterial = .opaque

    private var panel: ArisNoticePanel?
    private var monitors: [Any] = []
    private var watches: Set<AnyCancellable> = []
    /// How many fixes of a problem card were pressed (a line with several lists opens them one after another).
    private var fixPresses: [UUID: Int] = [:]
    /// The notch, as the app's windows tell it (ArisEntry attaches them).
    private var notchOpen: () -> Bool = { false }
    private var notchScreen: () -> NSScreen? = { NSScreen.main }

    private init() {}

    // MARK: - The notch and the setup

    /// The notch's windows: whether one is open, its display, and a signal each time either may have changed.
    func attach(notchOpen: @escaping () -> Bool, screen: @escaping () -> NSScreen?, changes: AnyPublisher<Void, Never>) {
        self.notchOpen = notchOpen
        notchScreen = screen
        watches.removeAll()
        changes.receive(on: DispatchQueue.main)
            .sink { [weak self] in MainActor.assumeIsolated { self?.notchMoved() } }
            .store(in: &watches)
        ArisOnboardingGuide.shared.$phase.receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.notchMoved() } }
            .store(in: &watches)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.placePanel() } }
            .store(in: &watches)
    }

    private var moment: ArisNoticeGate.Moment {
        ArisNoticeGate.Moment(pause: true, onboarding: ArisOnboardingGuide.shared.showing, notchOpen: notchOpen())
    }

    /// Whether a card may come up now, the pause aside (ArisController asks that itself).
    var mayShow: Bool { ArisNoticeGate.mayShow(moment) }

    private func notchMoved() {
        let stepAside = ArisNoticeGate.stepsAside(moment)
        if stepAside != aside { aside = stepAside }
        if stepAside { hovered = nil }
        updatePointer()
    }

    // MARK: - The queue

    /// A new card waits for its moment; true when it replaced a card already up (it is up at once).
    @discardableResult
    func enqueue(_ notice: ArisNotice) -> Bool {
        let replacesShown = notice.key.map { key in queue.shown.contains { $0.key == key } } ?? false
        queue = queue.posting(notice)
        if replacesShown { log.notice("card replaced: \(notice.kind.rawValue, privacy: .public)") }
        return replacesShown
    }

    func isWaiting(_ id: UUID) -> Bool { queue.isWaiting(id) }

    func dropExpired() { queue = queue.dropping(expiredAt: Date()) }

    /// Its moment came: on top of the stack.
    func present(_ id: UUID) {
        queue = queue.presenting(id)
        showPanel()
    }

    /// Never shown after all (its caller was cancelled).
    func withdraw(_ id: UUID) {
        guard queue.isWaiting(id) else { return }
        queue = queue.closing(id)
    }

    /// What `key` stood for is over: its card goes, waiting or up.
    func withdraw(key: String) {
        let next = queue.withdrawing(key: key)
        guard next != queue else { return }
        queue = next
        settle()
    }

    // MARK: - What the cards ask

    var handlers: ArisNoticeHandlers {
        ArisNoticeHandlers(close: { [weak self] in self?.close($0) }, act: { [weak self] in self?.act($0, $1) },
                           expand: { [weak self] in self?.setExpanded(true) }, collapse: { [weak self] in self?.setExpanded(false) },
                           hover: { [weak self] in self?.hover($0) })
    }

    func close(_ id: UUID) {
        queue = queue.closing(id)
        fixPresses[id] = nil
        if hovered == id { hovered = nil }
        settle()
    }

    private func setExpanded(_ on: Bool) {
        queue = on ? queue.expanding() : queue.collapsing()
        updatePointer()
    }

    private func hover(_ id: UUID?) {
        if hovered != id { hovered = id }
    }

    /// A button: what it names, then the card goes (acted on), unless a problem's next fix is still to press.
    func act(_ id: UUID, _ action: ArisNoticeAction) {
        guard let notice = queue.shown.first(where: { $0.id == id }) else { return }
        let english = ArisUIWords.english
        switch action.role {
        case .fixes(let fixes):
            let pressed = fixPresses[id] ?? 0
            guard pressed < fixes.count else { return close(id) }
            ArisFixModel.shared.press(fixes[pressed])
            fixPresses[id] = pressed + 1
            if let next = ArisNoticeRoute.afterFix(notice, pressed: pressed + 1, english: english) {
                queue = queue.replacing(next)
                return
            }
        case .restartHelper:
            ArisAgentMonitor.shared.restart()
        case .openJob(let job):
            ArisController.shared.openDone(id: job)
        case .openFile(let file):
            ArisBoard.shared.read(file: file)
        case .openAnswer(let question, let text):
            ArisBoard.shared.show(ArisReaderDocument.answer(text, question: question))
        case .retryJob(let job):
            ArisController.shared.retryNotDone(job)
        }
        close(id)
    }

    // MARK: - The panel

    private func showPanel() {
        let panel = self.panel ?? makePanel()
        refreshMaterial(panel)
        placePanel()
        if !panel.isVisible { panel.orderFrontRegardless() }
        startPointerWatch()
        notchMoved()
    }

    /// Nothing is up any more: the panel goes off screen and nothing watches the pointer.
    private func settle() {
        guard queue.shown.isEmpty else { return updatePointer() }
        hovered = nil
        stopPointerWatch()
        panel?.ignoresMouseEvents = true
        panel?.orderOut(nil)
    }

    private func makePanel() -> ArisNoticePanel {
        let panel = ArisNoticePanel()
        let host = ArisNoticeHostingView(rootView: ArisNoticeHost(center: self))
        host.frame = CGRect(origin: .zero, size: ArisNoticeLayout.windowSize)
        panel.contentView = host
        self.panel = panel
        return panel
    }

    private func placePanel() {
        guard let panel, let screen = notchScreen() ?? NSScreen.main else { return }
        panel.place(on: screen)
    }

    /// Glass only on macOS 26 with every private part of the notch's glass taking and the panel's active look forced
    /// (with Reduce Transparency it is drawn solid); otherwise the opaque card.
    private func refreshMaterial(_ panel: ArisNoticePanel) {
        var glassView = false
        if #available(macOS 26.0, *) { glassView = true }
        var chosen = ArisNoticeMaterial.choose(glassView: glassView, privateGlass: ArisGlassFallback.decide(ArisGlassHealth.shared.parts).privateGlass)
        if chosen == .glass, !ArisGlassPrivate.forceActiveAppearance(panel, on: true) {
            ArisGlassPrivate.forceActiveAppearance(panel, on: false)
            ArisGlassHealth.shared.failed(\.activeAppearance)
            chosen = .opaque
        }
        if chosen != material {
            material = chosen
            log.notice("cards: \(chosen == .glass ? "glass" : "opaque", privacy: .public)")
        }
    }

    // MARK: - The pointer

    private func startPointerWatch() {
        guard monitors.isEmpty else { return }
        let moved: () -> Void = { [weak self] in self?.updatePointer() }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { _ in MainActor.assumeIsolated { moved() } }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { event in
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

    /// The panel takes the pointer only on a card (with its close corner), a peeking layer or the "+N" row; while the
    /// cards step aside it takes nothing.
    private func updatePointer() {
        guard let panel, panel.isVisible else { return }
        let stack = ArisNoticeLayout.stack(queue.shown.map(ArisNoticeLayout.height), expanded: queue.expanded)
        let point = panel.cardsPoint(NSEvent.mouseLocation)
        let onCards = !aside && ArisNoticeLayout.hitRects(stack).contains { $0.contains(point) }
        if panel.ignoresMouseEvents == onCards { panel.ignoresMouseEvents = !onCards }
        if !onCards, hovered != nil { hovered = nil }
    }
}

/// The panel's view: the stack as the center has it.
struct ArisNoticeHost: View {
    @ObservedObject var center: ArisNoticeCenter

    var body: some View {
        ArisNoticeStackView(queue: center.queue, hovered: center.hovered, material: center.material, english: ArisUIWords.english,
                            aside: center.aside, handlers: center.handlers)
    }
}
