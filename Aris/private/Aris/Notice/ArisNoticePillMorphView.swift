//
//  ArisNoticePillMorphView.swift
//  Aris
//
//  How the notice pill moves between its line and its card: one animatable progress (sprung by ArisNoticePillView)
//  drives a layout that measures the card's own height and sizes the pill between the two as real numbers, so the
//  height and the corner (ArisDictationPillShape reads it from the size) interpolate instead of jumping to the card's
//  intrinsic size; and the layers' crossfade, blur and rise come from the same progress (ArisNoticePillMorph). Also the
//  press feedback of the card's buttons. No timer, no loop: it moves only while the spring runs.
//

import SwiftUI

/// The pill's content at one instant of the morph: `arrival` 0 → 1 from the bar, `progress` 0 the line → 1 the card.
/// Both are animated by SwiftUI (a spring retargets from where it is, at its speed, when the pointer turns back).
struct ArisNoticePillMorphing<Content: View>: View, Animatable {
    var arrival: Double
    var progress: Double
    let collapsedWidth: CGFloat
    @ViewBuilder let content: (ArisNoticePillMorph) -> Content

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(arrival, progress) }
        set { arrival = newValue.first; progress = newValue.second }
    }

    var body: some View {
        ArisNoticePillMorphLayout(arrival: arrival, progress: progress, collapsedWidth: collapsedWidth) {
            content(ArisNoticePillMorph(progress: progress))
        }
    }
}

/// Marks the card layer, the one the layout measures (364 wide, as tall as its text).
struct ArisNoticePillCardKey: LayoutValueKey {
    static let defaultValue = false
}

/// Lays every layer at the top left at its own size, and is itself the morph's size: the line's width × 38 at 0, the
/// card's 364 × measured height at 1, from the 36 × 8 bar while it arrives.
struct ArisNoticePillMorphLayout: Layout {
    let arrival: Double
    let progress: Double
    let collapsedWidth: CGFloat

    private func proposal(_ subview: LayoutSubview) -> ProposedViewSize {
        subview[ArisNoticePillCardKey.self] ? ProposedViewSize(width: ArisNoticePillLayout.expandedWidth, height: nil) : .unspecified
    }

    func sizeThatFits(proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let card = subviews.first { $0[ArisNoticePillCardKey.self] }.map { $0.sizeThatFits(proposal($0)).height } ?? ArisNoticePillLayout.height
        return ArisNoticePillMorph(progress: progress).size(collapsed: collapsedWidth, card: card, arrival: arrival)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, anchor: .topLeading, proposal: proposal(subview))
        }
    }
}

/// A pressable on the card: 0.97 while held, back in 120 ms; with Reduce Motion it dims instead of moving.
struct ArisNoticePillPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .scaleEffect(pressed && !reduceMotion ? ArisNoticePillLayout.pressScale : 1)
            .opacity(pressed && reduceMotion ? ArisNoticePillLayout.pressDim : 1)
            .animation(.easeOut(duration: ArisNoticePillLayout.press), value: pressed)
    }
}
