//
//  ArisAccent+Preferences.swift
//  Aris
//
//  The effective accent from the saved preferences, for SwiftUI and AppKit.
//

import AppKit
import Defaults
import SwiftUI

extension NSColor {
    static var effectiveAccent: NSColor {
        ArisAccent.effective(custom: Defaults[.useCustomAccentColor], data: Defaults[.customAccentColorData])
    }

    /// A custom colour gets the system's "disabled" look; the system accent is used at 25 %.
    static var effectiveAccentBackground: NSColor {
        let accent = effectiveAccent
        if Defaults[.useCustomAccentColor], ArisAccent.unarchive(Defaults[.customAccentColorData] ?? Data()) != nil {
            return accent.withSystemEffect(.disabled)
        }
        return accent.withAlphaComponent(ArisAccent.backgroundAlpha)
    }
}

extension Color {
    static var effectiveAccent: Color { Color(nsColor: .effectiveAccent) }
    static var effectiveAccentBackground: Color { Color(nsColor: .effectiveAccentBackground) }
}
