//
//  ArisBandMetrics.swift
//  Aris
//
//  The closed notch's band in numbers, the compact band, for every activity (Aris, music, Claude, a timer,
//  background tasks): one width, 13-point quarter-circle shoulders and corners, and a mark each side of the camera
//  centred 23 points in from the band's edge (a 28-point box at 9). The band is 270 wide on a 1512-point display
//  (camera 185) and scales with the display, so the width here follows the camera's.
//  CoreGraphics only, so the regions built on it are tested (ArisClosedBand). The band's views are in ArisBand.swift.
//

import CoreGraphics

enum ArisBand {
    static let radius: CGFloat = 13
    static let markCenter: CGFloat = 23
    private static let compactWidth: CGFloat = 270
    private static let referenceCamera: CGFloat = 185

    static func bodyWidth(notchWidth: CGFloat) -> CGFloat {
        ((notchWidth - 4) * compactWidth / referenceCamera).rounded()
    }

    static func earWidth(notchWidth: CGFloat) -> CGFloat {
        max(0, (bodyWidth(notchWidth: notchWidth) - notchWidth) / 2)
    }

    /// The ear in a band `body` wide (the band on the notch's display, ArisVNotch); nil: from the camera's width.
    static func earWidth(notchWidth: CGFloat, body: CGFloat?) -> CGFloat {
        guard let body else { return earWidth(notchWidth: notchWidth) }
        return max(0, (body - notchWidth) / 2)
    }
}
