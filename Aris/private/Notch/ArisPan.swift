//
//  ArisPan.swift
//  Aris
//
//  Directional swipes on the notch: two-finger trackpad scrolls and mouse drags. The action always gets a distance
//  along its own direction (never negative). Scrolls: movement toward the direction adds up, against it starts over;
//  .began at the threshold, then .changed, then .ended with the total (scroll "ended" phase or 0.3 s of silence).
//  Drags: .changed with the distance while it is toward the direction and past the threshold, .ended with 0 on
//  release. Scrolls are watched, never swallowed, so pages keep scrolling, and only in the view's own window.
//

import AppKit
import Defaults
import SwiftUI

@MainActor
final class ArisPanHandler: ObservableObject {
    static let quietEnd: TimeInterval = 0.3

    var direction: PanDirection = .down
    var threshold: CGFloat = 4
    var action: (CGFloat, NSEvent.Phase) -> Void = { _, _ in }
    weak var window: NSWindow?

    private var tracker = ArisPanTracker(direction: .down, threshold: 4)
    private var monitor: Any?
    private var quiet: DispatchWorkItem?
    private var dragging = false

    func configure(direction: PanDirection, threshold: CGFloat, action: @escaping (CGFloat, NSEvent.Phase) -> Void) {
        self.action = action
        if direction != self.direction || threshold != self.threshold, !tracker.began {
            tracker = ArisPanTracker(direction: direction, threshold: threshold)
        }
        self.direction = direction
        self.threshold = threshold
    }

    func setEnabled(_ enabled: Bool) {
        if enabled { start() } else { stop() }
    }

    private func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated { self?.scrolled(event) }
            return event
        }
    }

    /// Stops watching; a swipe in progress still gets its end.
    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        finish()
        dragEnded()
    }

    private func scrolled(_ event: NSEvent) {
        guard let window, event.window === window else { return }
        if let delta = ArisPanTracker.scrollDelta(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY,
                                                  precise: event.hasPreciseScrollingDeltas,
                                                  invertedFromDevice: event.isDirectionInvertedFromDevice,
                                                  normalize: Defaults[.normalizeGestureDirection], vertical: direction.isVertical) {
            report(tracker.move(delta))
        }
        if event.phase == .ended || event.phase == .cancelled || event.momentumPhase == .ended {
            finish()
        } else {
            scheduleQuietEnd()
        }
    }

    func dragChanged(_ translation: CGSize) {
        dragging = true
        let along = direction.isVertical ? translation.height : translation.width
        if let distance = ArisPanTracker.dragDistance(along, direction: direction, threshold: threshold) {
            action(distance, .changed)
        }
    }

    func dragEnded() {
        guard dragging else { return }
        dragging = false
        action(0, .ended)
    }

    private func scheduleQuietEnd() {
        quiet?.cancel()
        let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.finish() } }
        quiet = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.quietEnd, execute: item)
    }

    private func finish() {
        quiet?.cancel()
        quiet = nil
        report(tracker.end())
    }

    private func report(_ output: (CGFloat, NSEvent.Phase)?) {
        guard let (value, phase) = output else { return }
        action(value, phase)
    }
}

/// Tells the handler which window the view is in.
private struct ArisPanWindowReader: NSViewRepresentable {
    let handler: ArisPanHandler

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in handler.window = view?.window }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        if handler.window !== view.window { handler.window = view.window }
    }
}

private struct ArisPanModifier: ViewModifier {
    let direction: PanDirection
    let threshold: CGFloat
    let enabled: Bool
    let action: (CGFloat, NSEvent.Phase) -> Void
    @StateObject private var handler = ArisPanHandler()

    func body(content: Content) -> some View {
        let _ = handler.configure(direction: direction, threshold: threshold, action: action)
        content
            .background(ArisPanWindowReader(handler: handler))
            .simultaneousGesture(DragGesture(minimumDistance: threshold)
                .onChanged { handler.dragChanged($0.translation) }
                .onEnded { _ in handler.dragEnded() },
                     including: enabled ? .all : .subviews)
            .onAppear { handler.setEnabled(enabled) }
            .onDisappear { handler.stop() }
            .onChange(of: enabled) { _, on in handler.setEnabled(on) }
    }
}

extension View {
    /// A swipe toward `direction` (see ArisPan.swift). Disabled, it neither watches nor blocks anything.
    func panGesture(direction: PanDirection, threshold: CGFloat = 4, enabled: Bool = true,
                    action: @escaping (CGFloat, NSEvent.Phase) -> Void) -> some View {
        modifier(ArisPanModifier(direction: direction, threshold: threshold, enabled: enabled, action: action))
    }

    /// Applies `transform` only when `condition` holds.
    @ViewBuilder
    func conditionalModifier(_ condition: Bool, transform: (Self) -> some View) -> some View {
        if condition { transform(self) } else { self }
    }
}
