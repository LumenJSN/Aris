//
//  ArisFadingScroll.swift
//  Aris
//
//  The answer's scroll view: one scroller from the first token, never swapped for plain text, as tall as its content
//  up to `budget` and growing on the opening clock (280 ms, 0.2 0.8 0.2 1). Hidden indicators, no bounce while it
//  fits, native momentum, pinned to the top (no auto-scroll). Its edges fade 22 points only where there's more to
//  scroll (ArisScrollEdges), swapped at once.
//

import SwiftUI

struct ArisFadingScroll<Content: View>: View {
    let budget: CGFloat
    /// Told the scroller's offset, how much of it shows and its content's whole height, as each changes (the confirm
    /// card's "read to its end", ArisCardRead).
    var onScroll: ((_ offset: CGFloat, _ visible: CGFloat, _ content: CGFloat) -> Void)? = nil
    @ViewBuilder let content: () -> Content

    @State private var contentHeight: CGFloat = 0
    @State private var edges = ArisScrollEdges()
    /// The scroll offset, kept out of the view's state so scrolling doesn't re-render it; only `edges` changes it.
    @State private var position = ArisScrollPosition()

    private static var space: String { "ArisFadingScroll" }

    var body: some View {
        let visible = min(contentHeight, budget)
        ScrollView(.vertical) {
            content()
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { frame in
                    if frame.height != contentHeight {
                        withAnimation(ArisGlass.opening) { contentHeight = frame.height }
                    }
                    // macOS 14 has no scroll geometry: the content's place in the scroller is the offset.
                    if !position.native { position.offset = -frame.minY }
                    updateEdges()
                }
        }
        .coordinateSpace(.named(Self.space))
        // Never, not hidden: `.hidden` still shows AppKit's legacy scroller whenever a mouse is connected, and that
        // 15-point bar narrowed the text (it re-wrapped as the answer grew past it) and sat over the confirm card.
        .scrollIndicators(.never)
        .scrollBounceBehavior(.basedOnSize)
        .modifier(ArisScrollOffsetReader { offset in
            position.native = true
            position.offset = offset
            updateEdges()
        })
        .frame(height: visible)
        .mask { ArisEdgeFadeMask(stops: edges.stops(height: visible)) }
        .onChange(of: budget) { updateEdges() }
    }

    /// From the content's own height and the budget (the targets, not the frame mid-growth), so a line being eased in
    /// never flashes the bottom fade.
    private func updateEdges() {
        let next = ArisScrollEdges.at(offset: position.offset, visible: min(contentHeight, budget), content: contentHeight)
        if next != edges { edges = next }
        onScroll?(position.offset, min(contentHeight, budget), contentHeight)
    }
}

/// The last scroll offset seen. A class, so writing it doesn't invalidate the view.
private final class ArisScrollPosition {
    var offset: CGFloat = 0
    /// Offsets come from the scroller itself (macOS 15 and later).
    var native = false
}

/// The scroller's vertical offset on every scroll, where the system reports it (macOS 15 and later).
private struct ArisScrollOffsetReader: ViewModifier {
    let action: (CGFloat) -> Void

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
                action(offset)
            }
        } else {
            content
        }
    }
}

/// Opaque where the content shows, clear over the faded edges; no stops means no fade. Never animated: the fades
/// swap at once.
private struct ArisEdgeFadeMask: View {
    let stops: [ArisScrollEdges.Stop]

    var body: some View {
        Group {
            if stops.isEmpty {
                Color.black
            } else {
                LinearGradient(stops: stops.map { Gradient.Stop(color: $0.opaque ? .black : .clear, location: $0.location) },
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .transaction { $0.animation = nil }
    }
}
