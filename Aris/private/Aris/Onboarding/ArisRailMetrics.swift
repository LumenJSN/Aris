//
//  ArisRailMetrics.swift
//  Aris
//
//  The setup window's progress rail as numbers (the owner's pick 6, 2026-11-11: one bar): its height, inset, colours,
//  fade and timing. ArisSetupRail draws it. Pure, so the tests hold each number.
//

import Foundation

/// The onboarding rail as numbers: a single metallic rail with a clean blue-to-silver fill and a soft leading fade.
/// Measurements and curves only; the fill is drawn here from its stops, never from an image.
enum ArisRailMetrics {
    /// The track: 11 high, fully round.
    static let height: Double = 11
    /// The inset from the window's sides and top.
    static let inset: Double = 24
    /// The track's gradient, top to bottom: #fbfcfd, #eceef1 at 54%, #f6f7f8.
    static let track: [(hex: UInt32, at: Double)] = [(0xfbfcfd, 0), (0xeceef1, 0.54), (0xf6f7f8, 1)]
    /// The track's inner shadow: rgba(15, 23, 42, .07), 1 down, blur 2 (a soft dark lip under its top edge).
    static let lip = (hex: UInt32(0x0f172a), alpha: 0.07, y: 1.0, blur: 2.0)
    /// The track's inner line: white at .94, 1 up, no blur (a hard white line along its bottom edge).
    static let shine = (alpha: 0.94, y: 1.0)
    /// The fill's gradient at 96°: #1684e5, #3d9ded 21%, #72b7ee 41%, #b6d7ef 59%, #edf3f7 73%, #9fc7eb 87%,
    /// #2b8de5.
    static let fill: [(hex: UInt32, at: Double)] = [(0x1684e5, 0), (0x3d9ded, 0.21), (0x72b7ee, 0.41), (0xb6d7ef, 0.59), (0xedf3f7, 0.73),
                                                    (0x9fc7eb, 0.87), (0x2b8de5, 1)]
    static let fillDegrees: Double = 96
    /// The fill's mask: whole up to 48 from its end, .72 at 27 from its end, clear at the end.
    static let fadeFrom: Double = 48
    static let fadeMid: Double = 27
    static let fadeMidAlpha = 0.72
    /// The fill's width moves over 500 ms (.4, 0, .2, 1).
    static let widthSeconds = 0.5
    static let widthCurve = (0.4, 0.0, 0.2, 1.0)
    /// The fill's opacity moves over 180 ms ease; the fill is hidden at nothing.
    static let opacitySeconds = 0.18

    /// The fill's mask along its width, as (alpha, place 0…1): the soft leading fade over its last 48 points; none
    /// once it is full.
    static func mask(width: Double, complete: Bool) -> [(alpha: Double, at: Double)] {
        guard !complete, width > 0 else { return [(1, 0), (1, 1)] }
        return [(1, 0), (1, max(0, 1 - fadeFrom / width)), (fadeMidAlpha, max(0, 1 - fadeMid / width)), (0, 1)]
    }

    /// CSS's gradient line for `degrees` (0 up, clockwise) across a box, as unit points of that box: the line runs
    /// through the centre and is as long as the box's corners reach along it.
    static func gradientLine(width: Double, height: Double, degrees: Double = fillDegrees) -> (start: (x: Double, y: Double), end: (x: Double, y: Double)) {
        guard width > 0, height > 0 else { return ((0, 0.5), (1, 0.5)) }
        let angle = degrees * .pi / 180
        let dx = sin(angle), dy = -cos(angle)
        let half = (abs(width * dx) + abs(height * dy)) / 2
        return ((0.5 - dx * half / width, 0.5 - dy * half / height), (0.5 + dx * half / width, 0.5 + dy * half / height))
    }
}
