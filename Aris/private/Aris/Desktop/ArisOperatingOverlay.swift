//
//  ArisOperatingOverlay.swift
//  Aris
//
//  The "working on this window" overlay: one borderless, click-through panel ordered just above the window computer use
//  is working in (re-ordered as that window moves in the stack), following its frame across displays, and taken down
//  when the work stops (ArisOperatingState). Only the window's number, pid and bounds are read (ArisWindowLocator), never
//  its title or contents. The look is ArisOperatingIndicator's.
//

import AppKit
import SwiftUI

@MainActor
final class ArisOperatingOverlay {
    static let shared = ArisOperatingOverlay()

    private var state = ArisOperatingState()
    private var panel: NSPanel?
    private var host: NSHostingView<ArisOperatingIndicator>?
    private var timer: Timer?
    /// How often the window's frame and place in the stack are read again.
    static let tick: TimeInterval = 0.2

    private init() {}

    /// A desktop call is under way in this window. `owner`: the background job doing it (nil: the conversation's turn).
    func show(_ target: ArisOperatingTarget, owner: UUID? = nil) {
        state.heard(target, at: Date(), owner: owner)
        if timer == nil {
            let timer = Timer(timeInterval: Self.tick, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.follow() } }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        follow()
    }

    /// The answer came, or the turn ended: down at once. Only `owner`'s own window: a job that ends leaves the overlay of
    /// another job (or the turn) still at work where it is (audit imp-5).
    func end(owner: UUID? = nil) {
        state.finished(owner: owner)
        follow()
    }

    private func follow() {
        guard let target = state.current(at: Date()) else { return takeDown() }
        guard let window = ArisOperatingPlacement.window(for: target, named: { ArisWindowLocator.frame(pid: $0, windowNumber: $1) },
                                                         front: { ArisWindowLocator.frontWindow(pid: $0) }),
              let primary = NSScreen.screens.first,
              let frame = ArisOperatingPlacement.frame(windowCG: window.frame, primaryHeight: primary.frame.height) else {
            panel?.orderOut(nil)
            return
        }
        let panel = self.panel ?? makePanel()
        if host?.rootView.target != target { host?.rootView = ArisOperatingIndicator(target: target) }
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        panel.order(.above, relativeTo: window.number)
    }

    private func takeDown() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        host = nil
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.level = .normal
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        panel.ignoresMouseEvents = true
        panel.sharingType = .none
        panel.hasShadow = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        let host = NSHostingView(rootView: ArisOperatingIndicator(target: state.current(at: Date()) ?? ArisOperatingTarget(app: "", pid: 1, window: nil, line: "")))
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        self.panel = panel
        self.host = host
        return panel
    }
}
