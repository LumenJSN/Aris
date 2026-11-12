//
//  ArisGestureChrome.swift
//  Aris
//
//  The words and the two small pieces of chrome around the ink, drawn with CoreGraphics and CoreText into images:
//  - the hint chip ArisUIWords.text("동그라미로 가리키세요", "Circle what you mean") with Aris's star (the owner's
//    pick B);
//  - the red reject capsule: "8/8" with an image glyph when the 8-shot limit is hit, or
//    ArisUIWords.text("암호 앱은 찍지 않아요", "Password apps are never captured") with a lock when the circled
//    window is a password app's.
//  Nothing numbered is ever drawn on screen: shot numbers live only in the image and the transcript (the owner,
//  2026-11-03). Pure, so the tests run it.
//

import CoreGraphics
import CoreText
import Foundation

enum ArisGestureChrome {
    // MARK: - Words (Aris's own, Korean first)

    static let hintText = ArisUIWords.text("동그라미로 가리키세요", "Circle what you mean")
    static let privateRefusalText = ArisUIWords.text("암호 앱은 찍지 않아요", "Password apps are never captured")
    /// A window whose owner can't be resolved is refused too (fail closed), without claiming it's a password app.
    static let unknownRefusalText = ArisUIWords.text("이 창은 찍지 않아요", "This window is never captured")

    static func limitText(shots: Int, max: Int) -> String { "\(shots)/\(max)" }

    static func refusalText(for hit: ArisWindowHit?) -> String {
        ArisCaptureRules.isPrivate(hit?.bundleId) ? privateRefusalText : unknownRefusalText
    }

    enum Icon: Equatable { case lock, image }

    // MARK: - Type

    /// CSS font-weight 500 and 700 as CoreText weight traits (NSFont.Weight .medium / .bold).
    static let mediumWeight: CGFloat = 0.23
    static let boldWeight: CGFloat = 0.4

    static func font(size: CGFloat, weight: CGFloat, tabular: Bool = false) -> CTFont {
        let base = CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        var attributes: [CFString: Any] = [kCTFontTraitsAttribute: [kCTFontWeightTrait: weight]]
        if tabular {
            attributes[kCTFontFeatureSettingsAttribute] = [[kCTFontFeatureTypeIdentifierKey: kNumberSpacingType,
                                                            kCTFontFeatureSelectorIdentifierKey: kMonospacedNumbersSelector]]
        }
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(base), attributes as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    static func line(_ text: String, font: CTFont, color: CGColor, kern: CGFloat = 0) -> CTLine {
        var attributes: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color]
        if kern != 0 { attributes[kCTKernAttributeName] = kern }
        return CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary))
    }

    // MARK: - Hint chip

    /// `rgba(0,0,0,.75)`, 6 pt radius, padding 5/10, a 13 pt icon, gap 6, 12 pt/500 text at white .9.
    private enum Hint {
        static let height: CGFloat = 24
        static let padX: CGFloat = 10
        static let icon: CGFloat = 13
        static let gap: CGFloat = 6
        static let radius: CGFloat = 6
        static let fontSize: CGFloat = 12
        static let background = CGColor(gray: 0, alpha: 0.75)
        static let text = CGColor(gray: 1, alpha: 0.9)
    }

    static func hintChipSize(text: String = hintText) -> CGSize {
        let width = textWidth(hintLine(text))
        return CGSize(width: (Hint.padX * 2 + Hint.icon + Hint.gap + width).rounded(.up), height: Hint.height)
    }

    /// Where the 13 pt icon sits in the chip (top-left points), for a live icon view laid over the image.
    static func hintIconFrame() -> CGRect {
        CGRect(x: Hint.padX, y: (Hint.height - Hint.icon) / 2, width: Hint.icon, height: Hint.icon)
    }

    /// The chip as an image at `scale`. `icon` is drawn into the icon slot when given (the live app lays Aris's own
    /// star view over the slot instead).
    static func hintChipImage(text: String = hintText, icon: CGImage?, scale: CGFloat) -> CGImage? {
        let size = hintChipSize(text: text)
        return image(size: size, scale: scale) { ctx in
            let rect = CGRect(origin: .zero, size: size)
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: Hint.radius, cornerHeight: Hint.radius, transform: nil))
            ctx.setFillColor(Hint.background)
            ctx.fillPath()
            if let icon { drawImage(ctx, icon, in: hintIconFrame()) }
            drawLine(ctx, hintLine(text), x: Hint.padX + Hint.icon + Hint.gap, midY: size.height / 2)
        }
    }

    private static func hintLine(_ text: String) -> CTLine {
        line(text, font: font(size: Hint.fontSize, weight: mediumWeight), color: Hint.text)
    }

    // MARK: - Permission line (plan D2)

    /// The hint chip's look with the words and an accent "허용하기" (the hint arrow's hsl(214,100%,68%)).
    private enum Permission {
        static let gap: CGFloat = 8
        static let accent = ArisInkRenderer.color(hue: 214, lightness: 0.68)
    }

    static func permissionChipSize(text: String, action: String) -> CGSize {
        let width = textWidth(hintLine(text)) + Permission.gap + textWidth(actionLine(action))
        return CGSize(width: (Hint.padX * 2 + width).rounded(.up), height: Hint.height)
    }

    static func permissionChipImage(text: String, action: String, scale: CGFloat) -> CGImage? {
        let size = permissionChipSize(text: text, action: action)
        return image(size: size, scale: scale) { ctx in
            ctx.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: size), cornerWidth: Hint.radius,
                               cornerHeight: Hint.radius, transform: nil))
            ctx.setFillColor(Hint.background)
            ctx.fillPath()
            let words = hintLine(text)
            drawLine(ctx, words, x: Hint.padX, midY: size.height / 2)
            drawLine(ctx, actionLine(action), x: Hint.padX + textWidth(words) + Permission.gap, midY: size.height / 2)
        }
    }

    private static func actionLine(_ text: String) -> CTLine {
        line(text, font: font(size: Hint.fontSize, weight: 0.3), color: Permission.accent)
    }

    // MARK: - Reject capsule

    /// Padding 5/11/5/9, gap 5, a 12 pt glyph, 12 pt/700 tabular text with .02em tracking, a vertical red gradient,
    /// a full radius, three outer shadows and two inset highlights.
    private enum Capsule {
        static let height: CGFloat = 24
        static let padLeft: CGFloat = 9
        static let padRight: CGFloat = 11
        static let icon: CGFloat = 12
        static let gap: CGFloat = 5
        static let fontSize: CGFloat = 12
        static let kern: CGFloat = 0.24
        /// Room around the pill for its shadows (the widest is 22 pt).
        static let margin: CGFloat = 28
    }

    static var capsuleMargin: CGFloat { Capsule.margin }

    static func capsuleSize(text: String) -> CGSize {
        let width = textWidth(capsuleLine(text))
        return CGSize(width: (Capsule.padLeft + Capsule.icon + Capsule.gap + width + Capsule.padRight).rounded(.up),
                      height: Capsule.height)
    }

    /// The capsule with `capsuleMargin` of shadow room on every side, at `scale`.
    static func capsuleImage(text: String, icon: Icon, scale: CGFloat) -> CGImage? {
        let pill = capsuleSize(text: text), m = Capsule.margin
        let size = CGSize(width: pill.width + m * 2, height: pill.height + m * 2)
        return image(size: size, scale: scale) { ctx in
            let rect = CGRect(x: m, y: m, width: pill.width, height: pill.height)
            let shape = CGPath(roundedRect: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil)
            // box-shadow 0 6px 18px rgba(0,0,0,.32), 0 1px 4px rgba(0,0,0,.25), 0 0 22px hsla(4,100%,58%,.32).
            // Shadow offsets are in the bitmap's base space (y up), so "down" is a negative y, in pixels.
            let shadows: [(CGFloat, CGFloat, CGColor)] = [
                (6, 18, CGColor(gray: 0, alpha: 0.32)), (1, 4, CGColor(gray: 0, alpha: 0.25)),
                (0, 22, ArisInkRenderer.color(hue: 4, lightness: 0.58, alpha: 0.32)),
            ]
            for (dy, blur, color) in shadows {
                ctx.saveGState()
                ctx.setShadow(offset: CGSize(width: 0, height: -dy * scale), blur: blur * scale, color: color)
                ctx.addPath(shape)
                ctx.setFillColor(ArisInkRenderer.color(hue: 2, saturation: 0.86, lightness: 0.52))
                ctx.fillPath()
                ctx.restoreGState()
            }
            // linear-gradient(180deg, hsl(4,92%,62%), hsl(2,86%,52%))
            ctx.saveGState()
            ctx.addPath(shape)
            ctx.clip()
            let colors = [ArisInkRenderer.color(hue: 4, saturation: 0.92, lightness: 0.62),
                          ArisInkRenderer.color(hue: 2, saturation: 0.86, lightness: 0.52)] as CFArray
            if let gradient = CGGradient(colorsSpace: ArisInkRenderer.sRGB, colors: colors, locations: [0, 1]) {
                ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
            }
            // inset 0 1px 0 rgba(255,255,255,.28): a top highlight.
            ctx.addPath(CGPath(roundedRect: rect.offsetBy(dx: 0, dy: 1), cornerWidth: rect.height / 2,
                               cornerHeight: rect.height / 2, transform: nil))
            ctx.addRect(rect.insetBy(dx: -4, dy: -4))
            ctx.setFillColor(CGColor(gray: 1, alpha: 0.28))
            ctx.fillPath(using: .evenOdd)
            ctx.restoreGState()
            // inset 0 0 0 1px rgba(255,255,255,.22): a hairline ring inside the edge.
            ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerWidth: rect.height / 2 - 0.5,
                               cornerHeight: rect.height / 2 - 0.5, transform: nil))
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.22))
            ctx.setLineWidth(1)
            ctx.strokePath()

            let iconRect = CGRect(x: rect.minX + Capsule.padLeft, y: rect.midY - Capsule.icon / 2,
                                  width: Capsule.icon, height: Capsule.icon)
            drawGlyph(ctx, icon, in: iconRect)
            drawLine(ctx, capsuleLine(text), x: iconRect.maxX + Capsule.gap, midY: rect.midY)
        }
    }

    private static func capsuleLine(_ text: String) -> CTLine {
        line(text, font: font(size: Capsule.fontSize, weight: boldWeight, tabular: true),
             color: CGColor(gray: 1, alpha: 1), kern: Capsule.kern)
    }

    // MARK: - Helpers

    /// A transparent bitmap of `size` points at `scale`, handed to `draw` in top-left point space.
    private static func image(size: CGSize, scale: CGFloat, draw: (CGContext) -> Void) -> CGImage? {
        let w = Int((size.width * scale).rounded(.up)), h = Int((size.height * scale).rounded(.up))
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: ArisInkRenderer.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        draw(ctx)
        return ctx.makeImage()
    }

    private static func textWidth(_ line: CTLine) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    /// Draws a line in a top-left context with its glyphs upright, centred on `midY`.
    private static func drawLine(_ ctx: CGContext, _ line: CTLine, x: CGFloat, midY: CGFloat) {
        var ascent: CGFloat = 0, descent: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, &descent, nil)
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: x, y: midY + (ascent - descent) / 2)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    /// Draws an upright image into a top-left context.
    private static func drawImage(_ ctx: CGContext, _ image: CGImage, in rect: CGRect) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }

    /// The capsule's 12 pt glyphs, from 24-unit outlines stroked 2.4 units wide in white, round caps and joins.
    private static func drawGlyph(_ ctx: CGContext, _ icon: Icon, in rect: CGRect) {
        let path = CGMutablePath()
        switch icon {
        case .lock:
            path.addRoundedRect(in: CGRect(x: 5, y: 11, width: 14, height: 9), cornerWidth: 2, cornerHeight: 2)
            path.move(to: CGPoint(x: 8, y: 11))
            path.addLine(to: CGPoint(x: 8, y: 8))
            path.addArc(center: CGPoint(x: 12, y: 8), radius: 4, startAngle: .pi, endAngle: 0, clockwise: false)
            path.addLine(to: CGPoint(x: 16, y: 11))
        case .image:
            path.addRoundedRect(in: CGRect(x: 3, y: 4, width: 18, height: 16), cornerWidth: 3, cornerHeight: 3)
            path.addEllipse(in: CGRect(x: 7, y: 8, width: 4, height: 4))
            path.move(to: CGPoint(x: 21, y: 16))
            path.addLine(to: CGPoint(x: 16, y: 11))
            path.addLine(to: CGPoint(x: 7, y: 20))
        }
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.minY)
        ctx.scaleBy(x: rect.width / 24, y: rect.height / 24)
        ctx.addPath(path)
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
        ctx.setLineWidth(2.4)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()
        ctx.restoreGState()
    }
}
