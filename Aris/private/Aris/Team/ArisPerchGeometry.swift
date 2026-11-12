//
//  ArisPerchGeometry.swift
//  Aris
//
//  Where a teammate sits on a window. Pure: window frames come in CG coordinates (origin at the top left of the
//  primary screen, y down), screens and the result are AppKit coordinates (origin at the bottom left of the primary
//  screen, y up), the space every NSScreen.frame and overlay panel lives in.
//

import CoreGraphics

enum ArisPerchGeometry {
    /// Along the title bar, from the window's left edge.
    static let alongTitleBar: CGFloat = 0.72
    /// How far the character's centre sits above the window's top edge, as a share of its size, so its feet rest on
    /// the title bar.
    static let aboveTopEdge: CGFloat = 0.32

    /// A CG rect (y down from the primary screen's top) as an AppKit rect (y up from its bottom).
    static func toAppKit(_ cg: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: cg.minX, y: primaryHeight - cg.maxY, width: cg.width, height: cg.height)
    }

    /// Where the character's **centre** goes (not its feet or its corner), in AppKit coordinates, when it sits on the
    /// window's title bar; nil when the window is on no screen. A character of height `size` centred here rests its
    /// lower 18% on the title bar. It stays over the window horizontally and wholly on the screen it sits on.
    static func perchPoint(windowCG: CGRect, screens: [CGRect], primaryHeight: CGFloat, size: CGFloat) -> CGPoint? {
        let window = toAppKit(windowCG, primaryHeight: primaryHeight)
        guard let fallback = screenMostCovering(window, screens: screens) else { return nil }
        let half = size / 2
        let x = window.width <= size
            ? window.midX
            : min(max(window.minX + alongTitleBar * window.width, window.minX + half), window.maxX - half)
        let y = window.maxY + aboveTopEdge * size
        let screen = screenIndex(of: CGPoint(x: x, y: window.maxY), screens: screens).map { screens[$0] } ?? fallback
        return CGPoint(x: clamp(x, screen.minX + half, screen.maxX - half),
                       y: clamp(y, screen.minY + half, screen.maxY - half))
    }

    /// The user's M2 for a window so high (maximised) that the title-bar perch would reach over the menu bar: inside the
    /// window's top-right corner, just under its title bar (mockup 10-bubble.html: a 28-pt title bar, 6 pt clear).
    static let titleBarHeight: CGFloat = 28
    static let underTitleBar: CGFloat = 6

    /// `perchPoint`, never over the menu bar: `visibleFrames` are the screens' `NSScreen.visibleFrame`s, in the same
    /// order. A perch that would reach above its screen's visible top moves inside the window's top-right corner, under
    /// its title bar or toolbar (`titleBarHeight`, from ArisTitleBarProbe when Accessibility can tell, else 28 pt).
    static func perchPoint(windowCG: CGRect, screens: [CGRect], visibleFrames: [CGRect], primaryHeight: CGFloat,
                           size: CGFloat, titleBarHeight: CGFloat = titleBarHeight) -> CGPoint? {
        guard let perch = perchPoint(windowCG: windowCG, screens: screens, primaryHeight: primaryHeight, size: size) else { return nil }
        guard let i = screenIndex(of: perch, screens: screens), visibleFrames.indices.contains(i) else { return perch }
        let visible = visibleFrames[i], half = size / 2
        guard perch.y + half > visible.maxY else { return perch }
        let window = toAppKit(windowCG, primaryHeight: primaryHeight)
        let x = window.width <= 2 * size ? window.midX : window.maxX - size
        let y = min(window.maxY, visible.maxY) - titleBarHeight - underTitleBar - half
        return CGPoint(x: clamp(x, visible.minX + half, visible.maxX - half), y: clamp(y, visible.minY + half, visible.maxY - half))
    }

    /// The first screen containing `p` (left and bottom edges inclusive, right and top exclusive).
    static func screenIndex(of p: CGPoint, screens: [CGRect]) -> Int? {
        screens.firstIndex { $0.contains(p) }
    }

    private static func screenMostCovering(_ rect: CGRect, screens: [CGRect]) -> CGRect? {
        let covered: [(screen: CGRect, area: CGFloat)] = screens.map { screen in
            let overlap = screen.intersection(rect)
            return (screen, overlap.isNull ? 0 : overlap.width * overlap.height)
        }
        return covered.filter { $0.area > 0 }.max { $0.area < $1.area }?.screen
    }

    private static func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        lo > hi ? (lo + hi) / 2 : min(max(v, lo), hi)
    }
}

/// How tall a window's title bar (with its toolbar, if any) is, from what Accessibility shows of it. Pure.
enum ArisTitleBarRules {
    /// What a title bar can plausibly be.
    static let plausible: ClosedRange<CGFloat> = 16...120

    /// From the window's top edge (CG, y down): to the toolbar's bottom when there is one, else twice the close
    /// button's middle (the button sits centred in a plain title bar); nil when neither gives a plausible height.
    static func height(windowTopCG: CGFloat, toolbarBottomCG: CGFloat?, closeButtonMidYCG: CGFloat?) -> CGFloat? {
        if let bottom = toolbarBottomCG, plausible.contains(bottom - windowTopCG) { return bottom - windowTopCG }
        if let mid = closeButtonMidYCG, plausible.contains(2 * (mid - windowTopCG)) { return 2 * (mid - windowTopCG) }
        return nil
    }
}
