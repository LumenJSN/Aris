//
//  ArisImageCodec.swift
//  Aris
//
//  Encoding, scaling and cropping images in memory (ImageIO and CoreGraphics only; nothing is written to disk),
//  and reading an image's format and pixel size without decoding it. Pure, so the tests run it.
//

import CoreGraphics
import Foundation
import ImageIO

enum ArisImageCodec {
    private static let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    private static let jpegMagic: [UInt8] = [0xFF, 0xD8, 0xFF]

    static func png(_ image: CGImage) -> Data? {
        encode(image, type: "public.png", properties: [:])
    }

    static func jpeg(_ image: CGImage, quality: CGFloat) -> Data? {
        encode(image, type: "public.jpeg", properties: [kCGImageDestinationLossyCompressionQuality: min(1, max(0, quality))])
    }

    /// Encodes with the format and quality that use calls for.
    static func encode(_ image: CGImage, for use: ArisImageUse) -> Data? {
        switch use.format {
        case .png: png(image)
        case .jpeg: jpeg(image, quality: use.quality ?? 0.9)
        }
    }

    /// The frame scaled to the budget and encoded for that use, or nil when it's under the blank floor.
    static func budgeted(_ frame: CGImage, budget: ArisImageBudget, for use: ArisImageUse) -> (data: Data, pixels: CGSize)? {
        let native = CGSize(width: frame.width, height: frame.height)
        let target = budget.fit(native)
        guard let image = target == native ? frame : scaled(frame, to: target), let data = encode(image, for: use) else { return nil }
        let pixels = CGSize(width: image.width, height: image.height)
        return ArisImageFloor.isBlank(bytes: data.count, format: use.format, pixels: pixels) ? nil : (data, pixels)
    }

    /// The image redrawn at exactly `px` (whole pixels), in sRGB with high-quality interpolation.
    static func scaled(_ image: CGImage, to px: CGSize) -> CGImage? {
        let width = Int(px.width.rounded()), height = Int(px.height.rounded())
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    /// The part of the image inside `rect` (pixels, top-left origin), rounded out to whole pixels and clamped to
    /// the image; nil when nothing is left.
    static func cropped(_ image: CGImage, toPixels rect: CGRect) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let clamped = rect.integral.intersection(bounds)
        guard !clamped.isNull, clamped.width >= 1, clamped.height >= 1 else { return nil }
        return image.cropping(to: clamped)
    }

    /// The pixel size from the header, without decoding the image.
    static func pixelSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    /// PNG or JPEG by magic bytes; nil for anything else.
    static func format(of data: Data) -> ArisImageFormat? {
        if data.starts(with: pngMagic) { return .png }
        if data.starts(with: jpegMagic) { return .jpeg }
        return nil
    }

    private static func encode(_ image: CGImage, type: String, properties: [CFString: Any]) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, type as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
