//
//  ArisBandBody.swift
//  Aris
//
//  The closed band's body width, handed down from the notch to whatever draws a band in it (ArisBandRow, the music
//  pill), so every band on one display is the same width: 270 scaled with the display (ArisVNotch), wider
//  while the pointer rests on it.
//

import SwiftUI

private struct ArisBandBodyKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    /// The closed band's body width on this notch's display (ArisVNotch's, grown under the pointer). Nil outside a
    /// notch: the band is then sized from the camera's width, as before.
    var arisBandBody: CGFloat? {
        get { self[ArisBandBodyKey.self] }
        set { self[ArisBandBodyKey.self] = newValue }
    }
}
