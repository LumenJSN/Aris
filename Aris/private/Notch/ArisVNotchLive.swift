//
//  ArisVNotchLive.swift
//  Aris
//
//  ArisVNotch for the real displays and preferences: what is measured of a display (its camera housing, the strip at
//  its top, its width), whether the closed notch follows ArisVNotch's sizes (it does, unless a height of one's own is
//  set in Settings) and how a closed Aris rests.
//

import AppKit
import Defaults
import SwiftUI

extension ArisVNotch.Display {
    /// The top strip is read as the work area's top (the menu bar's height); a hidden menu bar leaves the
    /// camera housing's own height.
    @MainActor
    init(_ screen: NSScreen?) {
        guard let screen else { self = .plain(width: 0); return }
        let housing = screen.safeAreaInsets.top
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        self.init(hasHousing: housing > 0, topBand: housing > 0 ? max(housing, menuBar) : 0, width: screen.frame.width)
    }
}

extension ArisVNotchRest {
    /// Read each time it is asked: 쉬는 동안 별 보이기 (ArisRestStar), or the hidden arisClosedRest = star.
    static var current: ArisVNotchRest {
        ArisVNotchRest(stored: UserDefaults.standard.string(forKey: preferenceKey), starShown: Defaults[.arisRestStar])
    }
}

extension Defaults.Keys {
    /// 쉬는 동안 별 보이기 (Settings › 노치): on on a fresh install.
    static let arisRestStar = Key<Bool>(ArisRestStar.preferenceKey, default: ArisRestStar.standard)
}

extension ArisNotchModel {
    private var vnotchScreen: NSScreen? {
        screenUUID.flatMap { NSScreen.screen(withUUID: $0) } ?? NSScreen.main
    }

    /// ArisVNotch's sizes on this notch's display.
    var vnotch: ArisVNotch.Metrics { ArisVNotch.metrics(ArisVNotch.Display(vnotchScreen)) }

    /// The closed notch takes ArisVNotch's size while its height is left to the display (the default: the real notch
    /// over a camera housing, the menu bar without one). A height of one's own set in Settings is kept as set.
    var closedFollowsVNotch: Bool {
        hasNotch ? Defaults[.notchHeightMode] == .matchRealNotchSize : Defaults[.nonNotchHeightMode] == .matchMenuBar
    }

    /// The open notch's top band: ArisVNotch's for this display, never shorter than the closed notch.
    var openBandHeight: CGFloat { max(vnotch.band, effectiveClosedNotchHeight) }
}
