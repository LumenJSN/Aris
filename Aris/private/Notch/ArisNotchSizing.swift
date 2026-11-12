//
//  ArisNotchSizing.swift
//  Aris
//
//  The notch sizes for the real displays and preferences, under the names the notch views and windows use
//  (cleanroom-specs/04 and 00-hub-interfaces). The arithmetic is in ArisNotchGeometry.swift.
//

import AppKit
import Defaults
import Foundation

let openNotchSize = ArisNotchGeometry.openSize
let openNotchMaxHeight = ArisNotchGeometry.openMaxHeight
let shadowPadding = ArisNotchGeometry.shadowPadding
let windowSize = ArisNotchGeometry.windowSize
let cornerRadiusInsets: (opened: (top: CGFloat, bottom: CGFloat), closed: (top: CGFloat, bottom: CGFloat)) =
    (opened: ArisNotchGeometry.openRadii, closed: (top: ArisBand.radius, bottom: ArisBand.radius))

extension ArisScreenMetrics {
    @MainActor
    init(_ screen: NSScreen) {
        self.init(frame: screen.frame, visibleFrame: screen.visibleFrame, topInset: screen.safeAreaInsets.top,
                  auxiliaryTopLeft: screen.auxiliaryTopLeftArea, auxiliaryTopRight: screen.auxiliaryTopRightArea)
    }
}

extension ArisHeightRule {
    init(_ mode: WindowHeightMode) {
        switch mode {
        case .matchRealNotchSize: self = .matchRealNotch
        case .matchMenuBar: self = .matchMenuBar
        case .custom: self = .custom
        }
    }

    var mode: WindowHeightMode {
        switch self {
        case .matchRealNotch: .matchRealNotchSize
        case .matchMenuBar: .matchMenuBar
        case .custom: .custom
        }
    }
}

private var osMajor: Int { ProcessInfo.processInfo.operatingSystemVersion.majorVersion }

@MainActor private var allScreenMetrics: [ArisScreenMetrics] { NSScreen.screens.map(ArisScreenMetrics.init) }

/// The display with this UUID, or the main display; nil when there is none.
@MainActor
private func screen(for uuid: String?) -> NSScreen? {
    if let uuid, let screen = NSScreen.screen(withUUID: uuid) { return screen }
    return NSScreen.main
}

@MainActor
func getScreenFrame(_ screenUUID: String? = nil) -> CGRect? {
    if let screenUUID { return NSScreen.screen(withUUID: screenUUID)?.frame }
    return NSScreen.main?.frame
}

@MainActor
func getClosedNotchSize(screenUUID: String? = nil) -> CGSize {
    ArisNotchGeometry.closedSize(for: screen(for: screenUUID).map(ArisScreenMetrics.init), screens: allScreenMetrics,
                                 notchHeight: Defaults[.notchHeight], nonNotchHeight: Defaults[.nonNotchHeight])
}

@MainActor
func getRealNotchHeight() -> CGFloat {
    ArisNotchGeometry.realNotchHeight(allScreenMetrics)
}

@MainActor
func getMenuBarHeight(for screen: NSScreen?) -> CGFloat {
    guard let screen else { return ArisNotchGeometry.defaultMenuBarHeight(hasNotch: false, osMajor: osMajor) }
    return ArisNotchGeometry.menuBarHeight(of: ArisScreenMetrics(screen), osMajor: osMajor)
}

@MainActor
func getMenuBarHeight(hasNotch: Bool) -> CGFloat {
    ArisNotchGeometry.menuBarHeight(hasNotch: hasNotch, screens: allScreenMetrics, osMajor: osMajor)
}

/// Makes the stored heights follow their modes (at launch and when the displays change); posts
/// "notch height changed" when one moved.
@MainActor
func syncNotchHeightIfNeeded() {
    let result = ArisNotchGeometry.synced(
        notchRule: ArisHeightRule(Defaults[.notchHeightMode]), nonNotchRule: ArisHeightRule(Defaults[.nonNotchHeightMode]),
        notchHeight: Defaults[.notchHeight], nonNotchHeight: Defaults[.nonNotchHeight], screens: allScreenMetrics, osMajor: osMajor)
    if result.nonNotchRule.mode != Defaults[.nonNotchHeightMode] { Defaults[.nonNotchHeightMode] = result.nonNotchRule.mode }
    var changed = false
    if result.notchHeight != Defaults[.notchHeight] { Defaults[.notchHeight] = result.notchHeight; changed = true }
    if result.nonNotchHeight != Defaults[.nonNotchHeight] { Defaults[.nonNotchHeight] = result.nonNotchHeight; changed = true }
    if changed { NotificationCenter.default.post(name: .notchHeightChanged, object: nil) }
}

/// Raises an old, too-small non-notch height (0 < h < 15) to 15 before anything reads the sizes.
enum LegacyNonNotchHeightMigration {
    static func migratedHeight(_ height: CGFloat) -> CGFloat { ArisNotchGeometry.migratedNonNotchHeight(height) }

    static func applyIfNeeded() {
        let stored = Defaults[.nonNotchHeight]
        let migrated = migratedHeight(stored)
        if migrated != stored { Defaults[.nonNotchHeight] = migrated }
    }
}

/// How tall Aris's surface may grow on the notch's display (the user's budget of its visible height).
@MainActor
func arisSurfaceMax(screenUUID: String?) -> CGFloat {
    guard let screen = screen(for: screenUUID) else { return ArisAnswerBudget.surfaceCap }
    return ArisAnswerBudget.surfaceMax(visibleHeight: screen.visibleFrame.height)
}
