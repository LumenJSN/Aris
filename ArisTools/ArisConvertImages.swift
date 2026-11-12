//
//  ArisConvertImages.swift
//  aris-tools
//
//  Pictures for `convert`, `merge` and `compress`, with ImageIO and CoreGraphics only: decode (the first frame, turned
//  the way it is meant to be seen), resize, encode, and pictures as PDF pages. Adapted from the user's Lime (MIT,
//  Engine/ImageIOKit.swift), without its ffmpeg path: WebP is written only when this Mac's ImageIO can.
//

import CoreGraphics
import Foundation
import ImageIO

enum ArisConvertImages {
    /// The type identifiers ImageIO knows each picture format by.
    static let typeIdentifiers: [String: String] = [
        "jpg": "public.jpeg", "png": "public.png", "heic": "public.heic", "tiff": "public.tiff",
        "bmp": "com.microsoft.bmp", "gif": "com.compuserve.gif", "webp": "org.webmproject.webp",
    ]
    /// The largest side Aris draws or makes (pixels).
    static let largestSide = 16_384

    /// Whether this Mac's ImageIO writes `format` (checked, never assumed: WebP is read-only on most).
    static func canWrite(_ format: String) -> Bool {
        guard let identifier = typeIdentifiers[format] else { return false }
        return (CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []).contains(identifier)
    }

    /// The first frame, turned upright, at most `maxSide` on its longer side.
    static func load(_ url: URL, maxSide: Int? = nil) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
            throw ArisConvertError("it isn't a picture Aris can read")
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0, height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        // Never bigger than the picture is (a --max above its size keeps its size).
        let longest = max(width, height, 1)
        let limit = min(maxSide.map { min($0, longest) } ?? longest, largestSide)
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceShouldCacheImmediately: true, kCGImageSourceThumbnailMaxPixelSize: max(1, limit)]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ArisConvertError("it isn't a picture Aris can read")
        }
        return image
    }

    static func context(width: Int, height: Int, opaque: Bool = false) -> CGContext? {
        guard width > 0, height > 0, width <= largestSide, height <= largestSide, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                         bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue)
    }

    /// On white, for formats without transparency (JPEG, BMP).
    static func flattened(_ image: CGImage) -> CGImage {
        guard let context = context(width: image.width, height: image.height, opaque: true) else { return image }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage() ?? image
    }

    /// `percent` of its size (never below one pixel); unchanged without one.
    static func scaled(_ image: CGImage, percent: Int?) -> CGImage {
        guard let percent, percent != 100 else { return image }
        let width = max(1, image.width * percent / 100), height = max(1, image.height * percent / 100)
        guard let context = context(width: width, height: height) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    /// One picture written as `format` (a lossy one at `quality`, 0…1).
    static func write(_ image: CGImage, to url: URL, format: String, quality: Double?) throws {
        guard let identifier = typeIdentifiers[format], canWrite(format),
              let writer = CGImageDestinationCreateWithURL(url as CFURL, identifier as CFString, 1, nil) else {
            throw ArisConvertError("this Mac can't write \(format.uppercased()) pictures")
        }
        let picture = ["jpg", "bmp"].contains(format) ? flattened(image) : image
        var properties: [CFString: Any] = [:]
        if let quality { properties[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(writer, picture, properties as CFDictionary)
        guard CGImageDestinationFinalize(writer) else { throw ArisConvertError("couldn't finish writing the \(format.uppercased()) picture") }
    }

    /// The pixels per inch the picture says it has (72 when it doesn't).
    static func dpi(_ url: URL) -> Double {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return 72 }
        let dpi = properties[kCGImagePropertyDPIWidth] as? Double ?? 72
        return dpi > 0 ? dpi : 72
    }

    /// One page per picture, each the picture's size at its own pixels per inch (as Preview makes them).
    static func writePDF(_ pictures: [(image: CGImage, dpi: Double)], to url: URL) throws {
        guard let consumer = CGDataConsumer(url: url as CFURL), let pdf = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            throw ArisConvertError("couldn't write the PDF")
        }
        for picture in pictures {
            var box = CGRect(x: 0, y: 0, width: Double(picture.image.width) * 72 / picture.dpi, height: Double(picture.image.height) * 72 / picture.dpi)
            pdf.beginPage(mediaBox: &box)
            pdf.draw(picture.image, in: box)
            pdf.endPage()
        }
        pdf.closePDF()
    }
}
