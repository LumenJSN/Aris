//
//  ArisFold.swift
//  Aris
//
//  A row leaving a list folds away: its height closes to nothing (the part folded away is clipped) while it fades,
//  so the rows below move up into space it gives back instead of sliding over it.
//

import SwiftUI

extension AnyTransition {
    /// Appears at once; leaves by folding shut as it fades.
    static var arisFold: AnyTransition {
        .asymmetric(insertion: .identity, removal: .modifier(active: ArisFoldModifier(progress: 0), identity: ArisFoldModifier(progress: 1)))
    }
}

private struct ArisFoldModifier: ViewModifier, Animatable {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        ArisFoldLayout(progress: progress) { content }
            .clipped()
            .opacity(Double(progress))
    }
}

/// Reports its content's height scaled by `progress` and pins the content to the top.
private struct ArisFoldLayout: Layout {
    var progress: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews.first?.sizeThatFits(proposal) ?? .zero
        return CGSize(width: size.width, height: size.height * max(0, min(1, progress)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: nil))
    }
}
