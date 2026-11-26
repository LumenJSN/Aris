//
//  ArisClipboardThumbnail.swift
//  Aris
//
//  The 클립보드 list's image thumbnails: read by ImageIO straight at the size the row draws them (20 points tall, in
//  pixels for a Retina screen), never decoded whole. NSImage(data:) decoded a copied screenshot at full size for a
//  20-point chip (a 3024 × 1964 one is 24 MB) and did it again each time the row was drawn. Only the small ones are
//  kept, by item, at most one per item the history keeps.
//

import AppKit
import ImageIO

enum ArisClipboardThumbnail {
    /// The row's thumbnail height, in points (ArisClipboardView).
    static let heightPoints: CGFloat = 20
    /// Pixels per point it is read at: a Retina screen's.
    static let scale: CGFloat = 2
    /// A very wide copy (a panorama) is read at most this many pixels along its long edge.
    static let maxLongEdge = 1_024

    /// The long edge, in pixels, to read an image of `width` × `height` pixels at, so it is `heightPoints` tall at
    /// `scale`; never more than the image has or `maxLongEdge`. Nil for an empty size.
    static func maxPixelSize(width: Int, height: Int, heightPoints: CGFloat = heightPoints, scale: CGFloat = scale) -> Int? {
        guard width > 0, height > 0 else { return nil }
        let factor = min(1, heightPoints * scale / CGFloat(height))
        let long = Int((CGFloat(max(width, height)) * factor).rounded(.up))
        return min(max(1, long), maxLongEdge, max(width, height))
    }

    /// The image in `data` (PNG, TIFF, JPEG, HEIC) read small enough for the row; nil when it isn't an image.
    static func make(from data: Data, heightPoints: CGFloat = heightPoints, scale: CGFloat = scale) -> CGImage? {
        let noCache = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, noCache),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, noCache) as? [CFString: Any],
              var width = properties[kCGImagePropertyPixelWidth] as? Int,
              var height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        // Orientations 5–8 turn it a quarter: the row shows it upright (the thumbnail's transform), so its height is
        // the stored width.
        if let orientation = properties[kCGImagePropertyOrientation] as? Int, orientation >= 5 { swap(&width, &height) }
        guard let long = maxPixelSize(width: width, height: height, heightPoints: heightPoints, scale: scale) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceShouldCacheImmediately: true, kCGImageSourceThumbnailMaxPixelSize: long]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// The thumbnails the list has read, by item: one read per item, not one per draw.
@MainActor
final class ArisClipboardThumbnails {
    static let shared = ArisClipboardThumbnails()

    /// A read that found no image is remembered too, so it isn't tried on every draw.
    private final class Entry {
        let image: NSImage?
        init(_ image: NSImage?) { self.image = image }
    }

    private let cache = NSCache<NSUUID, Entry>()

    init(countLimit: Int = ArisClipboard.limit) {
        cache.countLimit = countLimit
    }

    /// The row's thumbnail for `item`: its first image, read small (ArisClipboardThumbnail); nil when it has none.
    func image(for item: ArisClipboard.Item) -> NSImage? {
        let key = item.id as NSUUID
        if let entry = cache.object(forKey: key) { return entry.image }
        let thumb = item.contents.first { ArisClipboard.imageTypes.contains($0.type) }
            .flatMap { ArisClipboardThumbnail.make(from: $0.data) }
            .map { NSImage(cgImage: $0, size: NSSize(width: CGFloat($0.width) / ArisClipboardThumbnail.scale,
                                                    height: CGFloat($0.height) / ArisClipboardThumbnail.scale)) }
        cache.setObject(Entry(thumb), forKey: key)
        return thumb
    }
}
