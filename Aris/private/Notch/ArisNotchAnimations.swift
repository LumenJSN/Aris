//
//  ArisNotchAnimations.swift
//  Aris
//
//  The notch's shared curves. Opening: cubic (0.2, 0.8, 0.2, 1) over 280 ms; closing: cubic (0.45, 0, 0.55, 1) over
//  200 ms — both divided by the animation-speed setting, and instant when notch animation is off. Plus the
//  interactive spring for hover and gestures and the shelf's bouncy insertion.
//

import Defaults
import SwiftUI

enum StandardAnimations {
    static var open: Animation { timed(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.28 / speed)) }
    static var close: Animation { timed(.timingCurve(0.45, 0, 0.55, 1, duration: 0.2 / speed)) }
    static let interactive = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.8)
    static let bouncy = Animation.bouncy(duration: 0.4)
    static let smooth = Animation.smooth
    static let timingCurve = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.7)

    private static var speed: Double {
        let multiplier = Defaults[.animationSpeedMultiplier]
        return multiplier > 0 ? multiplier : 1
    }

    private static func timed(_ curve: Animation) -> Animation {
        Defaults[.enableOpeningAnimation] ? curve : .linear(duration: 0)
    }
}
