//
//  ArisWindowPickShot.swift
//  Aris
//
//  A picked window as the model sees it: the window alone (captured on its own, nothing over it), scaled to a
//  2560 px long edge, with its number in the corner as a circled shot has it, as JPEG 0.90; and a PNG thumb at most
//  640 wide without the number for the question's chip. In memory only. Pure, so the tests run it.
//

import CoreGraphics
import Foundation

enum ArisWindowPickShots {
    static func compose(window: CGImage, badge: Int) -> (jpeg: Data, thumb: Data)? {
        let px = CGSize(width: window.width, height: window.height)
        let size = ArisGestureGeometry.scaledCropSize(px)
        guard let bare = ArisImageCodec.jpeg(window, quality: ArisGestureConstants.Region.cropJPEGQuality),
              !ArisImageFloor.isBlank(bytes: bare.count, format: .jpeg, pixels: px),
              let full = draw(window, size: size, { ArisInkRenderer.drawBadge($0, imageSize: size, number: badge) }),
              let jpeg = ArisImageCodec.jpeg(full, quality: ArisImageUse.gestureShot.quality ?? 0.9),
              !ArisImageFloor.isBlank(bytes: jpeg.count, format: .jpeg, pixels: size) else { return nil }
        let thumbWidth = min(ArisGestureConstants.Shot.thumbMaxWidth, size.width)
        let thumbSize = CGSize(width: thumbWidth.rounded(), height: (size.height * thumbWidth / size.width).rounded())
        guard let small = draw(window, size: thumbSize, { _ in }), let thumb = ArisImageCodec.png(small) else { return nil }
        return (jpeg, thumb)
    }

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
