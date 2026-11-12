//
//  ArisGestureShot.swift
//  Aris
//
//  What a circle becomes: the circled window cut from the display's clean frame, scaled to a 2560 px long edge,
//  with the pointer's last 3 s inked on and the shot's number in the corner, as JPEG 0.90; a small PNG thumbnail
//  without the number for the transcript chip; and, per drawn display, the whole screen with everything drawn blended
//  at 0.55 as a JPEG 0.80 drawing reference. Everything stays in memory. Pure, so the tests run it.
//

import CoreGraphics
import Foundation
import ImageIO

/// One kept shot, in memory until the turn is sent.
struct ArisGestureShot: Equatable {
    let badge: Int
    /// The circled window's app and title (other people's words; the agent cleans and caps them).
    let app: String?
    let title: String?
    /// What the model sees: `gesture-screenshot-N.jpg`.
    let jpeg: Data
    /// For the transcript chip only: no number on it.
    let thumb: Data
    let voicedMsAtCapture: Double
    let capturedAtMs: Double
    let display: UInt32
}

/// A finished drawing session, parked for the turn that collects it.
struct ArisGestureResult {
    let shots: [ArisGestureShot]
    /// One `drawing-reference-K.jpg` per drawn display.
    let references: [Data]
    /// The turn's speech window and voiced total, for `ArisGestureMarkers.insert` (nil: no markers).
    let speech: (startedAtMs: Double, endedAtMs: Double, totalVoicedMs: Double)?
    let handsFree: Bool

    /// Gesture shots by badge, then the references. Never a cursor screenshot: a drawing replaces it.
    func images() -> [ArisTurnImage] {
        let gestures = shots.sorted { $0.badge < $1.badge }.map {
            ArisTurnImage(kind: .gesture, name: "gesture-screenshot-\($0.badge).jpg", format: .jpeg, data: $0.jpeg,
                          badge: $0.badge, app: $0.app, title: $0.title)
        }
        let drawings = references.prefix(ArisTurnImage.maxDrawing).enumerated().map { index, data in
            ArisTurnImage(kind: .drawing, name: "drawing-reference-\(index + 1).jpg", format: .jpeg, data: data,
                          badge: nil, app: nil, title: nil)
        }
        return gestures + drawings
    }
}

enum ArisGestureShots {
    private typealias Shot = ArisGestureConstants.Shot

    /// The crop in frame pixels (nil under 8 px).
    static func cropPixels(_ cropPt: CGRect, pxPerPt: CGFloat, frame: CGSize) -> CGRect? {
        ArisGestureGeometry.pixelRect(cropPt, pxPerPt: pxPerPt, image: frame)
    }

    /// Scaled down to a 2560 px long edge, never up.
    static func outputSize(_ px: CGSize) -> CGSize {
        ArisGestureGeometry.scaledCropSize(px)
    }

    /// The shot and its thumbnail, or nil when the crop is too small or the JPEG is under the blank floor.
    /// `cropPt` is display-local points; `strokes` are the display's persistent strokes in the same space;
    /// ink is drawn for `after ≤ t ≤ through`.
    static func compose(frame: CGImage, cropPt: CGRect, pxPerPt: CGFloat, strokes: [[ArisGesturePoint]],
                        after: Double, through: Double, badge: Int) -> (jpeg: Data, thumb: Data)? {
        guard let px = cropPixels(cropPt, pxPerPt: pxPerPt, frame: CGSize(width: frame.width, height: frame.height)),
              let cut = ArisImageCodec.cropped(frame, toPixels: px) else { return nil }
        // The bare crop is encoded as JPEG 92 before compositing; its blank floor is what tells a
        // black or empty frame from a real one (the badge alone would lift a black crop over it).
        guard let bare = ArisImageCodec.jpeg(cut, quality: ArisGestureConstants.Region.cropJPEGQuality),
              !ArisImageFloor.isBlank(bytes: bare.count, format: .jpeg, pixels: CGSize(width: cut.width, height: cut.height))
        else { return nil }
        let size = outputSize(CGSize(width: cut.width, height: cut.height))
        let scale = pxPerPt * size.width / CGFloat(cut.width)
        guard let full = draw(cut, size: size, { ctx in
            ArisInkRenderer.drawRecencyInk(ctx, strokes: strokes, after: after, through: through, crop: cropPt,
                                           scale: scale, pixelSize: size)
            ArisInkRenderer.drawBadge(ctx, imageSize: size, number: badge)
        }), let jpeg = ArisImageCodec.jpeg(full, quality: ArisImageUse.gestureShot.quality ?? 0.9),
              !ArisImageFloor.isBlank(bytes: jpeg.count, format: .jpeg, pixels: size) else { return nil }

        // The thumb: ≤ 640 wide, the same path 2 px per 320 px of width, no badge (nothing the user sees is numbered).
        let thumbWidth = min(Shot.thumbMaxWidth, size.width)
        let thumbSize = CGSize(width: thumbWidth.rounded(), height: (size.height * thumbWidth / size.width).rounded())
        let thumbScale = pxPerPt * thumbSize.width / CGFloat(cut.width)
        let pathPx = Shot.thumbPathWidthPer320 * thumbSize.width / 320
        guard let small = draw(cut, size: thumbSize, { ctx in
            ArisInkRenderer.drawRecencyInk(ctx, strokes: strokes, after: after, through: through, crop: cropPt,
                                           scale: thumbScale, pixelSize: thumbSize, widthPt: pathPx / thumbScale)
        }), let thumb = ArisImageCodec.png(small) else { return nil }
        return (jpeg, thumb)
    }

    /// The display at the drawing budget (1280/800/3072) with every stroke on it blended at 0.55, as JPEG 0.80; nil
    /// under the blank floor. `displaySize` is the display in points (the strokes' space).
    static func reference(frame: CGImage, displaySize: CGSize, strokes: [[ArisGesturePoint]]) -> Data? {
        guard displaySize.width > 0 else { return nil }
        let size = ArisImageBudget.drawing.fit(CGSize(width: frame.width, height: frame.height))
        guard size != .zero else { return nil }
        let ink = strokes.isEmpty ? nil
            : ArisInkRenderer.exportInk(strokes: strokes, size: displaySize, scale: size.width / displaySize.width)
        guard let image = draw(frame, size: size, { ctx in
            guard let ink else { return }
            ctx.setAlpha(Shot.drawingInkOpacity)
            ctx.draw(ink, in: CGRect(origin: .zero, size: size))
        }), let jpeg = ArisImageCodec.jpeg(image, quality: ArisImageUse.drawing.quality ?? 0.8),
              !ArisImageFloor.isBlank(bytes: jpeg.count, format: .jpeg, pixels: size) else { return nil }
        return jpeg
    }

    /// `image` drawn at `size` (sRGB, high quality), then `overlay` in the same raw pixel space (identity CTM).
    private static func draw(_ image: CGImage, size: CGSize, _ overlay: (CGContext) -> Void) -> CGImage? {
        let w = Int(size.width), h = Int(size.height)
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: ArisInkRenderer.sRGB,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        overlay(ctx)
        return ctx.makeImage()
    }
}
