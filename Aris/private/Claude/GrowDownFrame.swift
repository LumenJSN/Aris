//
//  GrowDownFrame.swift
//  Aris
//
//  A height frame that is at least `minHeight` but grows to the content's
//  natural height (up to `maxHeight`), so a tall Claude card extends the
//  open notch downward instead of overflowing above it. Inactive, it just
//  passes the proposal through, so the wrapped view keeps its identity.
//

import SwiftUI

struct GrowDownFrame: Layout {
    let active: Bool
    let minHeight: CGFloat
    let maxHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        guard active else { return child.sizeThatFits(proposal) }
        let natural = child.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        // The content's own width: taking the whole proposal pinned narrower pages to the left of the window.
        return CGSize(width: natural.width, height: Self.height(natural: natural.height, min: minHeight, max: maxHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        guard active else { return child.place(at: bounds.origin, proposal: proposal) }
        // At its natural height the child is placed with the proposal it was measured with, so the measurement is
        // reused instead of laying the whole page out a second time every pass (it showed up while the notch opens).
        // Held to the minimum or cut at the maximum, it gets that height.
        let measured = ProposedViewSize(width: proposal.width, height: nil)
        let natural = child.sizeThatFits(measured).height
        child.place(at: bounds.origin, proposal: Self.height(natural: natural, min: minHeight, max: maxHeight) == natural
                    ? measured : ProposedViewSize(bounds.size))
    }

    static func height(natural: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.min(Swift.max(natural, min), max)
    }
}
