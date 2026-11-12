//
//  ArisTabSwap.swift
//  Aris
//
//  What happens when you pick another tab in a side notch (side 3: the user, "it feels like a hard cut"). A plain
//  segmented control is a cut (the segment's colours change in 150 ms, nothing slides, the page under it swaps at
//  once), so the tabs move on two curves:
//    the highlight  slides to the tab in 180 ms on a sliding-indicator curve (0.22, 1, 0.36, 1), under 200 ms for a
//                   control pressed all day. It was a 300 ms spring, which starts slowly and was still gliding when
//                   the page had changed.
//    the page       crossfades in 180 ms on the notch's content reveal (0.22, 0.61, 0.36, 1), the old page blurring
//                   2 points as it goes and the new one clearing from 2.
//                   It was 220 ms on (0.23, 1, 0.32, 1), four fifths done within 70 ms: in the frames that was a cut
//                   with two pages of crisp words printed over each other for a moment, ahead of the highlight.
//  The two share one length, and the highlight's curve is the quicker, so the highlight arrives first and the page
//  follows it. The pages' opacities still add up to one all the way (the panel never dims or flashes). Pages that
//  share a layout (the usage tab's providers) do not swap at all: their values change in place.
//  Nothing moves when the tab was not picked with the pointer (a shortcut, a chip that leads to a tab, a tab turned
//  off in settings): the panel shows the tab at once. With Reduce Motion the highlight jumps and the page only fades.
//

import AppKit
import SwiftUI

enum ArisTabMotion {
    /// The highlight: 180 ms on (0.22, 1, 0.36, 1), the sliding segment indicator's curve.
    static let slide = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.18)
    /// The page, in and out on one curve so the two opacities always sum to one: 180 ms on (0.22, 0.61, 0.36, 1),
    /// the notch's content reveal.
    static let fade = Animation.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.18)
    static let blur: CGFloat = 2

    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}

/// Whether a change of tab is one a press on the tab made (it moves) or one that came some other way (it is shown).
@MainActor
enum ArisTabPress {
    /// Until when a change of tab shows at once.
    private static var quietUntil = Date.distantPast

    /// The tab is about to change without a press on it (a shortcut, a chip, settings): no motion for it.
    static func changedWithoutPress() { quietUntil = Date().addingTimeInterval(0.3) }

    /// A change of tab now is one the pointer made.
    static var pressed: Bool { Date() >= quietUntil }
}

/// Shows `content` for the tab at `index`; a new index swaps the page with the transition above.
struct ArisTabSwap<Content: View>: View {
    let index: Int
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            content
                .id(index)
                .transition(Self.swap)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Out and in alike: fading on the page's curve through a 2-point blur. At once when the tab was not picked with
    /// the pointer; with Reduce Motion, the fade alone.
    private static var swap: AnyTransition {
        guard ArisTabPress.pressed else { return .identity }
        let blur = ArisTabMotion.reduceMotion ? 0 : ArisTabMotion.blur
        return AnyTransition.modifier(active: ArisTabPage(blur: blur, opacity: 0), identity: ArisTabPage(blur: 0, opacity: 1))
            .animation(ArisTabMotion.fade)
    }
}

private struct ArisTabPage: ViewModifier {
    let blur: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content.blur(radius: blur).opacity(opacity)
    }
}
