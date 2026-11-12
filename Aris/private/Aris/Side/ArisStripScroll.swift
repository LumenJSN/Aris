//
//  ArisStripScroll.swift
//  Aris
//
//  A row that scrolls sideways like a calendar strip (the 한 일 tab's teammates): native momentum from a trackpad or
//  a mouse wheel, a wheel's up and down turned into left and right, no scroll bar, and the 22-point edge fades of
//  ArisFadingScroll laid sideways, only where there's more to see (ArisScrollEdges). A new `focus` (a tab picked, by a
//  click or by the app) is brought fully into view, clear of the fade, on the opening clock (280 ms, 0.2 0.8 0.2 1).
//  SwiftUI's own ScrollView on macOS 14 can neither turn the wheel nor scroll on a curve, hence the NSScrollView.
//

import AppKit
import SwiftUI

/// What a strip keeps in view: `key` changes when another tab is picked; `start` and `width` are where it ends up.
struct ArisStripFocus: Equatable {
    let key: Int
    let start: CGFloat
    let width: CGFloat
}

struct ArisStripScroll<Content: View>: View {
    let contentWidth: CGFloat
    let height: CGFloat
    let focus: ArisStripFocus?
    @ViewBuilder let content: () -> Content
    @State private var edges = ArisScrollEdges()
    @State private var width: CGFloat = 0

    var body: some View {
        StripScroller(contentWidth: contentWidth, height: height, focus: focus, content: content(), onEdges: { next in
            if next != edges { edges = next }
        })
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .mask {
            // Leading and trailing for ArisScrollEdges' top and bottom; swapped at once, never animated.
            Group {
                let stops = edges.stops(height: width)
                if stops.isEmpty {
                    Color.black
                } else {
                    LinearGradient(stops: stops.map { Gradient.Stop(color: $0.opaque ? .black : .clear, location: $0.location) },
                                   startPoint: .leading, endPoint: .trailing)
                }
            }
            .transaction { $0.animation = nil }
        }
    }
}

private struct StripScroller<Content: View>: NSViewRepresentable {
    let contentWidth: CGFloat
    let height: CGFloat
    let focus: ArisStripFocus?
    let content: Content
    let onEdges: (ArisScrollEdges) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SidewaysScrollView {
        let scroll = SidewaysScrollView()
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.verticalScrollElasticity = .none
        scroll.horizontalScrollElasticity = .automatic
        scroll.contentView.drawsBackground = false
        let host = NSHostingView(rootView: content)
        // Sized by hand (the row's width), not by its own constraints.
        host.sizingOptions = []
        host.frame = CGRect(x: 0, y: 0, width: contentWidth, height: height)
        scroll.documentView = host
        scroll.contentView.postsBoundsChangedNotifications = true
        context.coordinator.attach(scroll, host: host)
        return scroll
    }

    func updateNSView(_ scroll: SidewaysScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onEdges = onEdges
        coordinator.host?.rootView = content
        coordinator.host?.frame = CGRect(x: 0, y: 0, width: max(contentWidth, 1), height: height)
        if let focus, focus != coordinator.focus {
            // The first focus is where the strip opens: no motion. Later ones are a pick: brought in on the clock.
            coordinator.bring(focus, contentWidth: contentWidth, animated: coordinator.focus != nil && !ArisTabMotion.reduceMotion)
            coordinator.focus = focus
        }
        DispatchQueue.main.async { coordinator.report() }
    }

    static func dismantleNSView(_ scroll: SidewaysScrollView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject {
        weak var scroll: NSScrollView?
        var host: NSHostingView<Content>?
        var focus: ArisStripFocus?
        var onEdges: ((ArisScrollEdges) -> Void)?
        private var observer: NSObjectProtocol?

        func attach(_ scroll: NSScrollView, host: NSHostingView<Content>) {
            self.scroll = scroll
            self.host = host
            observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView,
                                                              queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.report() }
            }
        }

        func detach() {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
        }

        /// Which sides have more to scroll, told to the SwiftUI side only when it changes there.
        func report() {
            guard let scroll, let host else { return }
            let clip = scroll.contentView.bounds
            onEdges?(ArisScrollEdges.at(offset: clip.origin.x, visible: clip.width, content: host.frame.width))
        }

        func bring(_ focus: ArisStripFocus, contentWidth: CGFloat, animated: Bool) {
            guard let scroll else { return }
            let clip = scroll.contentView
            let target = ArisSlidingTabsGeometry.scrollTarget(start: focus.start, width: focus.width, viewport: clip.bounds.width,
                                                              offset: clip.bounds.origin.x, content: contentWidth, inset: ArisScrollEdges.ramp)
            guard abs(target - clip.bounds.origin.x) > 0.5 else { return }
            let point = NSPoint(x: target, y: clip.bounds.origin.y)
            guard animated else {
                clip.setBoundsOrigin(point)
                scroll.reflectScrolledClipView(clip)
                return
            }
            NSAnimationContext.runAnimationGroup { context in
                // Notch-open 280ms (0.2, 0.8, 0.2, 1), ArisGlass.opening.
                context.duration = 0.28
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
                context.allowsImplicitAnimation = true
                clip.animator().setBoundsOrigin(point)
            } completionHandler: {
                MainActor.assumeIsolated { scroll.reflectScrolledClipView(clip) }
            }
        }
    }
}

/// Scrolls sideways only: a wheel turned up or down (no sideways part) scrolls left or right instead, with its phases
/// and momentum kept, so a mouse wheel and a trackpad both move the strip.
final class SidewaysScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        guard event.scrollingDeltaX == 0, event.scrollingDeltaY != 0, let turned = Self.sideways(event) else {
            return super.scrollWheel(with: event)
        }
        super.scrollWheel(with: turned)
    }

    /// The same event with its vertical deltas moved to the horizontal axis.
    private static func sideways(_ event: NSEvent) -> NSEvent? {
        guard let copy = event.cgEvent?.copy() else { return nil }
        let pairs: [(CGEventField, CGEventField)] = [
            (.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2),
            (.scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2),
        ]
        for (vertical, horizontal) in pairs {
            copy.setIntegerValueField(horizontal, value: copy.getIntegerValueField(vertical))
            copy.setIntegerValueField(vertical, value: 0)
        }
        copy.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: copy.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1))
        copy.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0)
        return NSEvent(cgEvent: copy)
    }
}
