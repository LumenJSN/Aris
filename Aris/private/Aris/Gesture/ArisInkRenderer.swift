//
//  ArisInkRenderer.swift
//  Aris
//
//  Every stroke of gesture ink, drawn with CoreGraphics only (no AppKit), so the tests paint it into bitmaps:
//  - the live stroke, the sealed loop and the red re-ink of a refused loop in the owner's pick E, the highlighter
//    (mockups/ink-styles.html; the smoothing is ArisInkSmoothing);
//  - the persistent strokes exported for the drawing reference (`exportInk`);
//  - the recency ink and the badge drawn onto a shot (`drawRecencyInk`, `drawBadge`).
//
//  Coordinates: the overlay functions (`cometPath`, `loopPath`, `drawComet`, `drawSeal`, `drawRejectLoop`) work in
//  the caller's point space, top-left (a flipped NSView). `exportInk` takes top-left points and returns an upright
//  image. `drawRecencyInk` and `drawBadge` draw into a shot's bitmap in its raw pixel space (identity CTM,
//  bottom-left origin), the way P1.8's composite holds it.
//

import CoreGraphics
import CoreText
import Foundation

enum ArisInkRenderer {
    private typealias Ink = ArisGestureConstants.Ink
    private typealias Shot = ArisGestureConstants.Shot

    /// The export's two passes: a 0.25 glow, width 20, dot r10, under an opaque core, width 8, dot r7.
    private static let exportGlowAlpha: CGFloat = 0.25
    private static let exportGlowDot: CGFloat = 10
    /// Shot ink is drawn as straight 5-stop gradients over sub-segments.
    private static let recencyStops = 5

    // MARK: - Colour

    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// `hsl(h, s, l)` with alpha, in sRGB. Ink blue is hue 214, the reject red hue 4, both at 100 % / 60 %.
    static func color(hue: CGFloat, saturation: CGFloat = 1, lightness: CGFloat = 0.6, alpha: CGFloat = 1) -> CGColor {
        let c = rgb(hue: hue, saturation: saturation, lightness: lightness)
        return CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: alpha)
    }

    static func rgb(hue: CGFloat, saturation s: CGFloat, lightness l: CGFloat) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let chroma = (1 - abs(2 * l - 1)) * s
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let x = chroma * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let m = l - chroma / 2
        let (r, g, b): (CGFloat, CGFloat, CGFloat)
        switch h {
        case ..<1: (r, g, b) = (chroma, x, 0)
        case ..<2: (r, g, b) = (x, chroma, 0)
        case ..<3: (r, g, b) = (0, chroma, x)
        case ..<4: (r, g, b) = (0, x, chroma)
        case ..<5: (r, g, b) = (x, 0, chroma)
        default: (r, g, b) = (chroma, 0, x)
        }
        return (r + m, g + m, b + m)
    }

    // MARK: - Live overlay (the owner's pick E, 마커 하이라이트)

    /// rgb(255, 214, 10): the highlighter's yellow, and rgb(255, 69, 58) for a refused loop (mockup E).
    static let markerColor = CGColor(srgbRed: 1, green: 214 / 255, blue: 10 / 255, alpha: 1)
    static let rejectColor = CGColor(srgbRed: 1, green: 69 / 255, blue: 58 / 255, alpha: 1)

    /// The live stroke as one shape: `points` already dropped and filtered (`ArisInkSmoothing.Stroke`), curved and
    /// resampled here, those under 900 ms old kept, each tapered by its age and, near the head, its distance from it.
    /// Nil when nothing is left to draw.
    static func cometPath(_ points: [ArisGesturePoint], now: Double) -> CGPath? {
        comet(ArisInkSmoothing.catmullRom(points), now: now)
    }

    /// The live stroke as it is drawn: its settled curve, which never moves, and its open tail (ArisInkSmoothing.Stroke).
    static func cometPath(_ stroke: ArisInkSmoothing.Stroke, now: Double) -> CGPath? {
        comet(stroke.curve, now: now)
    }

    private static func comet(_ curve: [ArisGesturePoint], now: Double) -> CGPath? {
        let life = Ink.markerLifeMs
        let dense = curve.filter { now - $0.t < life }
        guard !dense.isEmpty else { return nil }
        let xy = dense.map { CGPoint(x: $0.x, y: $0.y) }
        let heads = ArisInkSmoothing.headDistances(xy)
        let widths = dense.indices.map {
            ArisInkSmoothing.taper(ageMs: now - dense[$0].t, lifeMs: life, head: heads[$0], base: Ink.markerWidth)
        }
        return ArisInkSmoothing.ribbonPath(xy, widths: widths, closed: false)
    }

    /// A finished loop or scribble as one shape at the full width: smoothed like the live stroke; a circle is one lap,
    /// closed.
    static func loopPath(_ points: [ArisGesturePoint], closed: Bool) -> CGPath {
        var xy = ArisInkSmoothing.smooth(points).map { CGPoint(x: $0.x, y: $0.y) }
        if closed { xy = ArisInkSmoothing.oneLap(xy) }
        return ArisInkSmoothing.ribbonPath(xy, widths: Array(repeating: Ink.markerWidth, count: xy.count), closed: closed)
    }

    /// Fills `path` once in `color` at `alpha`: every pixel covered once, so crossings never darken.
    static func fill(_ ctx: CGContext, _ path: CGPath, color: CGColor, alpha: CGFloat) {
        guard alpha > 0 else { return }
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setFillColor(color.copy(alpha: alpha) ?? color)
        ctx.fillPath(using: .winding)
        ctx.restoreGState()
    }

    /// The live stroke from raw points (offscreen renders and tests; the app keeps the filter running as points come).
    static func drawComet(_ ctx: CGContext, trail: [ArisGesturePoint], now: Double) {
        guard let path = cometPath(ArisInkSmoothing.oneEuro(ArisInkSmoothing.dedupe(trail)), now: now) else { return }
        fill(ctx, path, color: markerColor, alpha: Ink.markerAlpha)
    }

    /// The seal: the loop in the highlighter at `sealStrength` of its alpha (fading out over 600 ms), times `fade` for
    /// one withdrawn early (its capture failed). Nothing once it has ended.
    static func drawSeal(_ ctx: CGContext, points: [ArisGesturePoint], closed: Bool, ageMs: Double, fade: CGFloat = 1) {
        guard let strength = ArisGestureMotion.sealStrength(ageMs: ageMs), points.count >= 2, fade > 0 else { return }
        fill(ctx, loopPath(points, closed: closed), color: markerColor, alpha: Ink.markerAlpha * strength * min(1, fade))
    }

    /// A refused loop, re-inked red at the highlighter's alpha (the shake and fade run on its layer).
    static func drawRejectLoop(_ ctx: CGContext, points: [ArisGesturePoint], closed: Bool) {
        guard points.count >= 2 else { return }
        fill(ctx, loopPath(points, closed: closed), color: rejectColor, alpha: Ink.markerAlpha)
    }

    // MARK: - Drawing reference

    /// Every persistent stroke on one display, as a transparent image at `scale`: all glows
    /// (α0.25, width 20, dot r10), then all cores (opaque, width 8, dot r7), straight segments. P1.8 blends it over the
    /// frame at 0.55, which lands the glow at 0.14 and the core at 0.55 like the live trail.
    static func exportInk(strokes: [[ArisGesturePoint]], size: CGSize, scale: CGFloat) -> CGImage? {
        let w = Int((size.width * scale).rounded()), h = Int((size.height * scale).rounded())
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        let passes = [(color(hue: Ink.hue, alpha: exportGlowAlpha), Ink.glowWidth, exportGlowDot),
                      (color(hue: Ink.hue), Ink.coreWidth, Ink.dotRadius)]
        for (paint, width, dot) in passes {
            for stroke in strokes {
                guard let first = stroke.first else { continue }
                if stroke.count == 1 {
                    ctx.setFillColor(paint)
                    ctx.fillEllipse(in: CGRect(x: first.x - dot, y: first.y - dot, width: dot * 2, height: dot * 2))
                    continue
                }
                let path = CGMutablePath()
                path.addLines(between: stroke.map { CGPoint(x: $0.x, y: $0.y) })
                self.stroke(ctx, path, color: paint, width: width)
            }
        }
        return ctx.makeImage()
    }

    // MARK: - Shot ink and badge

    /// `clamp01(1 − age/3 s)³`: most of the blue is in the last ~0.75 s.
    static func recencyStrength(ageMs: Double) -> CGFloat {
        let recent = min(1, max(0, 1 - ageMs / Shot.captureTrailMs))
        return CGFloat(pow(recent, Shot.trailStrengthPower))
    }

    /// The cursor path drawn onto a shot: points with `after ≤ t ≤ through`, smoothed,
    /// split where a segment's control polygon is > 1.1× its chord (depth 6), stroked `widthPt` wide into a grey mask
    /// with `lighten` (the most recent movement wins at crossings), then that mask filled with ink blue. `crop` is the
    /// shot's rect in the strokes' point space and `scale` its pixels per point. `ctx` is the shot bitmap in raw pixel
    /// space (identity CTM).
    static func drawRecencyInk(_ ctx: CGContext, strokes: [[ArisGesturePoint]], after: Double, through: Double,
                               crop: CGRect, scale: CGFloat, pixelSize: CGSize,
                               widthPt: CGFloat = ArisGestureConstants.Shot.pathCoreWidth) {
        let w = Int(pixelSize.width.rounded()), h = Int(pixelSize.height.rounded())
        guard w > 0, h > 0,
              let mask = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                   space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return }
        mask.setFillColor(CGColor(gray: 0, alpha: 1))
        mask.fill(CGRect(x: 0, y: 0, width: w, height: h))
        mask.translateBy(x: 0, y: CGFloat(h))
        mask.scaleBy(x: scale, y: -scale)
        mask.translateBy(x: -crop.minX, y: -crop.minY)
        mask.setBlendMode(.lighten)
        mask.setLineWidth(widthPt)
        mask.setLineCap(.round)
        mask.setLineJoin(.round)
        var painted = false
        for stroke in strokes {
            let pts = stroke.filter { $0.t >= after && $0.t <= through }
            for segment in segments(pts) where segment.t1 >= through - Shot.captureTrailMs {
                for piece in subdivide(segment, depth: 0) {
                    paintRecency(mask, piece, through: through, width: widthPt)
                    painted = true
                }
            }
        }
        guard painted, let maskImage = mask.makeImage() else { return }
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.saveGState()
        ctx.clip(to: rect, mask: maskImage)
        ctx.setFillColor(color(hue: Ink.hue))
        ctx.fill(rect)
        ctx.restoreGState()
    }

    /// The shot's number: a solid ink-blue circle r = clamp(round(0.03·w), 13, 44) at
    /// the top-left corner, inset 0.9r, over a 0.35 black shadow blurred 0.6r, with the number in white bold
    /// round(1.15r), centred 0.06r low. Only on the image the model sees: nothing numbered is drawn on screen.
    static func drawBadge(_ ctx: CGContext, imageSize: CGSize, number: Int) {
        let r = ArisGestureGeometry.badgeRadius(imageWidth: imageSize.width)
        let inset = (r * Shot.badgeInset).rounded() + r
        let center = CGPoint(x: inset, y: imageSize.height - inset)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: r * Shot.badgeShadowBlur, color: CGColor(gray: 0, alpha: Shot.badgeShadowAlpha))
        ctx.setFillColor(color(hue: Ink.hue))
        ctx.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        ctx.restoreGState()

        let font = ArisGestureChrome.font(size: (r * Shot.badgeFontScale).rounded(), weight: ArisGestureChrome.boldWeight)
        let line = ArisGestureChrome.line(String(number), font: font, color: CGColor(gray: 1, alpha: 1))
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        // The text's middle at (cx, cy + 0.06r), y down; here y is up.
        let middle = center.y - r * Shot.badgeFontYOffset
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: center.x - width / 2, y: middle - (ascent - descent) / 2)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    // MARK: - Helpers

    private struct Segment {
        var start, control, end: CGPoint
        var t0, t1: Double
    }

    /// The smoothed path as quadratic pieces, each with the times of its two anchors. The final straight line is a
    /// quadratic whose control is its midpoint.
    private static func segments(_ pts: [ArisGesturePoint]) -> [Segment] {
        guard pts.count >= 2 else {
            guard let p = pts.first else { return [] }
            let c = CGPoint(x: p.x, y: p.y)
            return [Segment(start: c, control: c, end: c, t0: p.t, t1: p.t)]
        }
        let point = { (i: Int) in CGPoint(x: pts[i].x, y: pts[i].y) }
        var out: [Segment] = []
        var anchor = point(0), anchorT = pts[0].t
        for i in 1..<(pts.count - 1) {
            let end = mid(point(i), point(i + 1)), endT = (pts[i].t + pts[i + 1].t) / 2
            out.append(Segment(start: anchor, control: point(i), end: end, t0: anchorT, t1: endT))
            anchor = end
            anchorT = endT
        }
        let last = point(pts.count - 1)
        out.append(Segment(start: anchor, control: mid(anchor, last), end: last, t0: anchorT, t1: pts[pts.count - 1].t))
        return out
    }

    /// Splits a segment in half (de Casteljau) while its control polygon is > 1.1× its chord, to depth 6, so a tight
    /// reversal keeps a correct gradient.
    private static func subdivide(_ s: Segment, depth: Int) -> [Segment] {
        let polygon = distance(s.start, s.control) + distance(s.control, s.end)
        guard depth < Shot.subdivideDepth, polygon > Shot.subdivideRatio * distance(s.start, s.end) else { return [s] }
        let a = mid(s.start, s.control), b = mid(s.control, s.end), m = mid(a, b), tm = (s.t0 + s.t1) / 2
        return subdivide(Segment(start: s.start, control: a, end: m, t0: s.t0, t1: tm), depth: depth + 1)
            + subdivide(Segment(start: m, control: b, end: s.end, t0: tm, t1: s.t1), depth: depth + 1)
    }

    /// One piece into the grey mask: a straight gradient start → end whose grey is the recency strength at 5 stops.
    private static func paintRecency(_ mask: CGContext, _ s: Segment, through: Double, width: CGFloat) {
        let levels = (0..<recencyStops).map { i -> CGFloat in
            let f = Double(i) / Double(recencyStops - 1)
            return recencyStrength(ageMs: through - (s.t0 + (s.t1 - s.t0) * f))
        }
        guard levels.contains(where: { $0 > 0 }) else { return }
        let path = CGMutablePath()
        path.move(to: s.start)
        path.addQuadCurve(to: s.end, control: s.control)
        mask.saveGState()
        if s.start == s.end {
            mask.setFillColor(CGColor(gray: levels[0], alpha: 1))
            let r = width / 2 // a lone point: its round cap
            mask.fillEllipse(in: CGRect(x: s.start.x - r, y: s.start.y - r, width: r * 2, height: r * 2))
            mask.restoreGState()
            return
        }
        mask.addPath(path)
        mask.replacePathWithStrokedPath()
        mask.clip()
        let components: [CGFloat] = levels.flatMap { [$0, 1] }
        let locations = (0..<recencyStops).map { CGFloat($0) / CGFloat(recencyStops - 1) }
        if let gradient = CGGradient(colorSpace: CGColorSpaceCreateDeviceGray(), colorComponents: components,
                                     locations: locations, count: recencyStops) {
            mask.drawLinearGradient(gradient, start: s.start, end: s.end,
                                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        mask.restoreGState()
    }

    private static func stroke(_ ctx: CGContext, _ path: CGPath, color: CGColor, width: CGFloat) {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
}
