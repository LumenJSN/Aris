//
//  ArisNotchGeometry.swift
//  Aris
//
//  How big the notch is, as plain arithmetic over a description of the displays (so it can be tested without
//  screens): the closed size per display, the real notch and menu-bar heights, and how the stored heights follow
//  the height modes. ArisNotchSizing.swift feeds it the real NSScreens and preferences.
//

import CoreGraphics
import Foundation

/// What the sizing needs to know about one display.
struct ArisScreenMetrics: Equatable {
    var frame: CGRect
    var visibleFrame: CGRect
    /// The top safe-area inset: > 0 on a display with a camera notch.
    var topInset: CGFloat
    var auxiliaryTopLeft: CGRect?
    var auxiliaryTopRight: CGRect?

    var hasNotch: Bool { topInset > 0 }

    /// The space the menu bar takes at the top (0 when it auto-hides).
    var menuBarSpace: CGFloat { frame.maxY - visibleFrame.maxY }
}

/// How a stored notch height follows the display (raw values are the stored preference strings).
enum ArisHeightRule: Equatable {
    case matchRealNotch, matchMenuBar, custom
}

enum ArisNotchGeometry {
    static let openSize = CGSize(width: 640, height: 190)
    static let openMaxHeight: CGFloat = 400
    static let shadowPadding: CGFloat = 20
    /// Aris's 710 pt surface plus room for its shadow.
    static let openContentHeight: CGFloat = 800
    static let windowSize = CGSize(width: openSize.width, height: openContentHeight + shadowPadding)
    static let openRadii: (top: CGFloat, bottom: CGFloat) = (31, 31)
    static let fallbackClosedWidth: CGFloat = 185
    static let fallbackNotchHeight: CGFloat = 38
    /// Non-notch heights between 0 and this are raised to it (0 stays: a flat, nearly invisible notch).
    static let smallestNonNotchHeight: CGFloat = 15

    /// The first display with a notch decides; none → 38.
    static func realNotchHeight(_ screens: [ArisScreenMetrics]) -> CGFloat {
        screens.first(where: \.hasNotch)?.topInset ?? fallbackNotchHeight
    }

    /// The menu bar's usual height: taller on macOS 26 and with a notch.
    static func defaultMenuBarHeight(hasNotch: Bool, osMajor: Int) -> CGFloat {
        osMajor >= 26 ? (hasNotch ? 38 : 29) : (hasNotch ? 43 : 23)
    }

    /// One display's menu-bar height, measured; an auto-hidden menu bar (0) falls back to the default.
    static func menuBarHeight(of screen: ArisScreenMetrics, osMajor: Int) -> CGFloat {
        let measured = max(0, screen.menuBarSpace - 1)
        return measured > 0 ? measured : defaultMenuBarHeight(hasNotch: screen.hasNotch, osMajor: osMajor)
    }

    /// The menu-bar height on the first display with (or without) a notch, else the default.
    static func menuBarHeight(hasNotch: Bool, screens: [ArisScreenMetrics], osMajor: Int) -> CGFloat {
        guard let screen = screens.first(where: { $0.hasNotch == hasNotch }) else {
            return defaultMenuBarHeight(hasNotch: hasNotch, osMajor: osMajor)
        }
        return menuBarHeight(of: screen, osMajor: osMajor)
    }

    /// The closed notch for `screen`. A display without a notch, next to one with a notch, borrows that notch's
    /// size, scaled down by the ratio of its own menu bar to the notch (never up).
    static func closedSize(for screen: ArisScreenMetrics?, screens: [ArisScreenMetrics],
                           notchHeight: CGFloat, nonNotchHeight: CGFloat) -> CGSize {
        var measured = screen
        var scale: CGFloat = 1
        if let own = screen, !own.hasNotch, let notched = screens.first(where: \.hasNotch) {
            if own.menuBarSpace > 0 { scale = min(1, own.menuBarSpace / notched.topInset) }
            measured = notched
        }
        var width = fallbackClosedWidth
        if let measured, let left = measured.auxiliaryTopLeft, let right = measured.auxiliaryTopRight {
            width = measured.frame.width - left.width - right.width + 4
        }
        let height = measured?.hasNotch == true ? notchHeight : nonNotchHeight
        return CGSize(width: (width * scale).rounded(), height: (height * scale).rounded())
    }

    static func migratedNonNotchHeight(_ height: CGFloat) -> CGFloat {
        height > 0 && height < smallestNonNotchHeight ? smallestNonNotchHeight : height
    }

    /// The stored heights after following the modes. A non-notched display can't match a notch: that mode is read
    /// as "match the menu bar" (`nonNotchRule` comes back corrected).
    static func synced(notchRule: ArisHeightRule, nonNotchRule: ArisHeightRule, notchHeight: CGFloat, nonNotchHeight: CGFloat,
                       screens: [ArisScreenMetrics], osMajor: Int)
        -> (notchHeight: CGFloat, nonNotchHeight: CGFloat, nonNotchRule: ArisHeightRule) {
        var notch = notchHeight, flat = nonNotchHeight
        switch notchRule {
        case .matchRealNotch: notch = realNotchHeight(screens)
        case .matchMenuBar: notch = menuBarHeight(hasNotch: true, screens: screens, osMajor: osMajor)
        case .custom: break
        }
        let rule: ArisHeightRule = nonNotchRule == .matchRealNotch ? .matchMenuBar : nonNotchRule
        if rule == .matchMenuBar { flat = menuBarHeight(hasNotch: false, screens: screens, osMajor: osMajor) }
        return (notch, flat, rule)
    }
}
