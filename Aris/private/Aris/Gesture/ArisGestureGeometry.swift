//
//  ArisGestureGeometry.swift
//  Aris
//
//  Where a circle lands: panel coordinates, the five hit-test samples, which window was circled, the crop and its
//  pixels, the dedup overlap and the badge number. Pure, so the tests run it.
//
//  Coordinate spaces, all in points:
//  - `panelLocal`/`global` convert between Cocoa global (bottom-left origin, `NSEvent.mouseLocation`) and a panel's
//    top-left local space, given the screen's Cocoa frame.
//  - `samplePoints`, `pickWindow` and `crop` take window frames, the gesture bbox and the display bounds in one shared
//    top-left space (Quartz global, as `CGWindowListCopyWindowInfo` and `CGDisplayBounds` give them). `crop` returns a
//    display-local rect, which `pixelRect` maps onto the display's frame image.
//

import CoreGraphics
import Foundation

/// A window under one or more of the hit-test samples (the window list's hits, grouped by window id).
struct ArisWindowHit: Equatable {
    let id: UInt32
    let pid: Int32
    let app: String?
    let title: String?
    let frame: CGRect
    var samples: Int
    var hitCenter: Bool
    /// The owning app's bundle id (nil only when the app can't be resolved), so a private app's window can be
    /// refused (`ArisCaptureRules.isPrivate`). Required, so no caller forgets it.
    let bundleId: String?
}

enum ArisGestureGeometry {
    private typealias R = ArisGestureConstants.Region
    private typealias Shot = ArisGestureConstants.Shot

    // MARK: - Panel coordinates

    /// Cocoa global point → the panel's top-left local point: `x − minX`, `maxY − y`.
    static func panelLocal(_ global: CGPoint, screen: CGRect) -> CGPoint {
        CGPoint(x: global.x - screen.minX, y: screen.maxY - global.y)
    }

    /// The inverse of `panelLocal`.
    static func global(_ local: CGPoint, screen: CGRect) -> CGPoint {
        CGPoint(x: local.x + screen.minX, y: screen.maxY - local.y)
    }

    /// Panel-local → Quartz global (top-left origin, the space of `CGWindowListCopyWindowInfo`), given the display's
    /// `CGDisplayBounds`. Both spaces are top-left, so it is only the display's origin added.
    static func quartz(panelLocal p: CGPoint, displayBounds: CGRect) -> CGPoint {
        CGPoint(x: displayBounds.minX + p.x, y: displayBounds.minY + p.y)
    }

    // MARK: - Hit-test

    /// The bbox centre, then (.24,.24), (.76,.24), (.24,.76), (.76,.76) of it.
    static func samplePoints(in bbox: CGRect) -> [CGPoint] {
        R.sampleFractions.map { CGPoint(x: bbox.minX + bbox.width * $0.x, y: bbox.minY + bbox.height * $0.y) }
    }

    /// One hit (or nil) per sample, in `samplePoints` order → one entry per window id, first-seen order, counting
    /// samples; sample 0 is the centre. Incoming `samples`/`hitCenter` are ignored.
    static func groupHits(_ perSample: [ArisWindowHit?]) -> [ArisWindowHit] {
        var grouped: [ArisWindowHit] = []
        for (index, sample) in perSample.enumerated() {
            guard let sample else { continue }
            let atCentre = index == 0
            if let k = grouped.firstIndex(where: { $0.id == sample.id }) {
                var existing = grouped[k]
                existing.samples += 1
                existing.hitCenter = existing.hitCenter || atCentre
                grouped[k] = existing
            } else {
                var fresh = sample
                fresh.samples = 1
                fresh.hitCenter = atCentre
                grouped.append(fresh)
            }
        }
        return grouped
    }

    /// The window the loop covers most, as a fraction of the window's own area,
    /// so a small window circled on top of a big one wins. Scores within 0.02 tie; a tie goes to more samples, then
    /// to a centre hit. The kept score only rises (`max`).
    static func pickWindow(_ hits: [ArisWindowHit], bbox: CGRect) -> ArisWindowHit? {
        var best: ArisWindowHit?
        var bestScore: CGFloat = -1
        for hit in hits {
            let score = coverage(of: hit.frame, by: bbox)
            let wins: Bool
            if let current = best {
                let tie = abs(score - bestScore) <= R.scoreTie
                wins = tie
                    ? hit.samples > current.samples || (hit.samples == current.samples && hit.hitCenter && !current.hitCenter)
                    : score > bestScore
            } else {
                wins = true
            }
            if wins { best = hit; bestScore = max(bestScore, score) }
        }
        return best
    }

    /// area(window ∩ bbox) / area(window), the area floored at 1.
    private static func coverage(of window: CGRect, by bbox: CGRect) -> CGFloat {
        let w = min(window.maxX, bbox.maxX) - max(window.minX, bbox.minX)
        let h = min(window.maxY, bbox.maxY) - max(window.minY, bbox.minY)
        guard w > 0, h > 0 else { return 0 }
        return w * h / max(1, window.width * window.height)
    }

    // MARK: - Crop

    /// The whole window, or else the bbox padded by `max(140, 0.4·w)` on every side; made display-local and clamped
    /// to the display. Nil when either side is under 60 pt.
    static func crop(window: CGRect?, bbox: CGRect, display: CGRect) -> CGRect? {
        let raw: CGRect
        if let window {
            raw = window.offsetBy(dx: -display.minX, dy: -display.minY)
        } else {
            let local = bbox.offsetBy(dx: -display.minX, dy: -display.minY)
            let pad = max(R.padMin, local.width * R.padFraction)
            raw = CGRect(x: local.minX - pad, y: local.minY - pad, width: local.width + pad * 2, height: local.height + pad * 2)
        }
        let x = max(0, raw.minX), y = max(0, raw.minY)
        let w = min(raw.maxX, display.width) - x, h = min(raw.maxY, display.height) - y
        guard w >= R.minCropPt, h >= R.minCropPt else { return nil }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// The crop in frame pixels: rounded, origin clamped at 0, size clamped to the image. Nil under 8 px.
    /// `pxPerPt` is `image.width / display.width`.
    static func pixelRect(_ pt: CGRect, pxPerPt: CGFloat, image: CGSize) -> CGRect? {
        let x = max(0, (pt.minX * pxPerPt).rounded()), y = max(0, (pt.minY * pxPerPt).rounded())
        let w = min((pt.width * pxPerPt).rounded(), image.width - x)
        let h = min((pt.height * pxPerPt).rounded(), image.height - y)
        guard w >= R.minCropPx, h >= R.minCropPx else { return nil }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// The encoded crop's size: scaled down to a 2560 px long edge, never up.
    static func scaledCropSize(_ px: CGSize) -> CGSize {
        let long = max(px.width, px.height)
        guard long > R.cropMaxLongEdge else { return px }
        let k = R.cropMaxLongEdge / long
        return CGSize(width: (px.width * k).rounded(), height: (px.height * k).rounded())
    }

    // MARK: - Dedup and badges

    /// Intersection over union; 0 for empty, non-finite or non-overlapping rects.
    static func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let values = [a.minX, a.minY, a.width, a.height, b.minX, b.minY, b.width, b.height]
        guard values.allSatisfy(\.isFinite), a.width > 0, a.height > 0, b.width > 0, b.height > 0 else { return 0 }
        let w = min(a.maxX, b.maxX) - max(a.minX, b.minX)
        let h = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        guard w > 0, h > 0 else { return 0 }
        let inter = w * h
        return inter / (a.width * a.height + b.width * b.height - inter)
    }

    /// `max(existing) + 1`: numbers are never reused while a higher one exists.
    static func nextBadge(_ existing: Set<Int>) -> Int {
        (existing.max() ?? 0) + 1
    }

    /// The badge's radius on an image `w` wide: `clamp(round(0.03·w), 13, 44)`.
    static func badgeRadius(imageWidth: CGFloat) -> CGFloat {
        min(Shot.badgeRadiusMax, max(Shot.badgeRadiusMin, (imageWidth * Shot.badgeRadiusFraction).rounded()))
    }
}
