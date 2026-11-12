//
//  ArisNotchGlassGeometry.swift
//  Aris
//
//  One frame of the notch for AppKit's glass (ArisNotchGlass), as numbers: the outline as a CGPath in the glass
//  view's own coordinates, where the black gradient ends, and the shadow. The glass view fills a fixed area (the
//  notch window's content) and is given the outline as its path: only the path moves while the notch opens, closes
//  or grows, never the view.
//
//  Per frame of a morph: width, height and radius each go linearly from where they were to where they are going, by
//  the eased progress of the same cubic-bezier and duration as the content. That sample becomes one CGPath, set as
//  the glass's `_setPath:` and as the path of the shape layer that masks the gradient. The gradient layer gets
//  startPoint (0.5, 1) and endPoint (0.5, 1 − g / H), H the layer's height and g = max(height,
//  safeAreaInsets.top / 0.53). All of it goes in one CATransaction with actions disabled. SwiftUI's animation
//  supplies the eased sample (the same transaction that moves the content), so the glass and the content are on
//  one clock by construction. CoreGraphics and the outline's shape only (tested).
//

import CoreGraphics
import SwiftUI

/// The notch at one instant: its outline's size and corner radii, and how open it is (0 closed, 1 open).
struct ArisNotchGlassSample: Equatable {
    var width: CGFloat
    var height: CGFloat
    var top: CGFloat
    var bottom: CGFloat
    var openness: CGFloat
}

enum ArisNotchGlassGeometry {
    /// The silhouette starts one point above the window's top, so no hairline shows under the screen's edge.
    static let overTop: CGFloat = 1
    /// The drop shadow, closed and open (ArisGlassSurface's: 0 2 6 at .25 idle, 0 5 12 at .28 active), and the cool
    /// rim's strength when open.
    static let shadowClosed = (opacity: 0.25, radius: 6.0, drop: 2.0)
    static let shadowOpen = (opacity: 0.28, radius: 12.0, drop: 5.0)
    static let rimOpacity = 0.22
    static let rimRadius = 0.9

    /// Where the notch sits in a canvas of `size`: centred, hanging from the top (y measured down from the top).
    static func rect(_ sample: ArisNotchGlassSample, canvas size: CGSize) -> CGRect {
        CGRect(x: (size.width - sample.width) / 2, y: 0, width: max(0, sample.width), height: max(0, sample.height))
    }

    /// The outline in an AppKit view of `size` (y up, origin bottom-left): the notch's own shape (NotchShape, with
    /// quarter-circle corners) closed, plus a one-point strip above the top. Always the same elements.
    static func outline(_ sample: ArisNotchGlassSample, canvas size: CGSize) -> CGPath {
        let place = rect(sample, canvas: size)
        let shape = NotchShape(topCornerRadius: sample.top, bottomCornerRadius: sample.bottom, circular: 1)
        var flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: size.height)
        let path = CGMutablePath()
        if let turned = shape.path(in: place).cgPath.copy(using: &flip) { path.addPath(turned) }
        path.closeSubpath()
        path.addRect(CGRect(x: place.minX, y: size.height, width: place.width, height: overTop))
        return path
    }

    /// Everything but the outline, for a layer that may only show outside it (the shadow): even-odd with `outline`.
    static func outside(_ outline: CGPath, canvas size: CGSize, reach: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addRect(CGRect(origin: .zero, size: size).insetBy(dx: -reach, dy: -reach))
        path.addPath(outline)
        return path
    }

    /// The gradient layer's end point's y (unit coordinates, 1 at the top): 1 − g / H.
    static func gradientEnd(height: CGFloat, safeTop: CGFloat, canvasHeight: CGFloat) -> CGFloat {
        guard canvasHeight > 0 else { return 0 }
        return 1 - CGFloat(ArisGlassLook.privateGlass.span(height: Double(height), safeTop: Double(safeTop))) / canvasHeight
    }

    /// The drop shadow `openness` of the way from closed to open.
    static func shadow(openness: CGFloat) -> (opacity: CGFloat, radius: CGFloat, drop: CGFloat) {
        let t = min(1, max(0, openness))
        func mix(_ a: Double, _ b: Double) -> CGFloat { CGFloat(a) + (CGFloat(b) - CGFloat(a)) * t }
        return (mix(shadowClosed.opacity, shadowOpen.opacity), mix(shadowClosed.radius, shadowOpen.radius), mix(shadowClosed.drop, shadowOpen.drop))
    }
}
