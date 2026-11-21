//
//  ArisDesktopVisionScale.swift
//  aris-agent
//
//  The size the look-and-click picture goes to the vision brain at. A Retina window's screenshot is two pixels a point
//  (a full-screen window is 2880×1800 and more); the models that look at it work on about 1.15 megapixels with a long
//  side of at most 1568 pixels and shrink anything bigger themselves, so the full picture only cost upload time and
//  tokens. It is scaled down to that (never up), the brain answers in the sent picture's pixels, and the point is
//  mapped back to the full picture's pixels (for the zoom's closer look, which crops the full one) and to the window's
//  points exactly. The maths is pure (tested); the scaling is CoreGraphics.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ArisDesktopVisionFrame: Equatable {
    /// The longest side and the most pixels a picture is sent with.
    static let maxSide: CGFloat = 1568
    static let maxPixels: CGFloat = 1_150_000

    /// The screenshot's own pixels, the picture sent, and the window it shows (global points).
    let full: CGSize
    let sent: CGSize
    let window: CGRect

    init(full: CGSize, window: CGRect) {
        self.full = full
        self.window = window
        sent = Self.sentSize(full)
    }

    /// The size a picture of `full` pixels is sent at: scaled to fit both limits, aspect kept, never enlarged.
    static func sentSize(_ full: CGSize) -> CGSize {
        guard full.width > 0, full.height > 0 else { return full }
        let side = maxSide / max(full.width, full.height)
        let area = (maxPixels / (full.width * full.height)).squareRoot()
        let scale = min(1, side, area)
        guard scale < 1 else { return full }
        return CGSize(width: max(1, (full.width * scale).rounded(.down)), height: max(1, (full.height * scale).rounded(.down)))
    }

    var scaled: Bool { sent != full }

    /// A point in the sent picture's pixels, in the full picture's.
    func fullPixel(_ sentPoint: CGPoint) -> CGPoint {
        guard sent.width > 0, sent.height > 0 else { return sentPoint }
        return CGPoint(x: sentPoint.x * full.width / sent.width, y: sentPoint.y * full.height / sent.height)
    }

    /// A point in the full picture's pixels, in the window's global points.
    func windowPoint(full fullPoint: CGPoint) -> CGPoint {
        guard full.width > 0, full.height > 0 else { return window.origin }
        return CGPoint(x: window.minX + fullPoint.x * window.width / full.width, y: window.minY + fullPoint.y * window.height / full.height)
    }

    /// A point in the sent picture's pixels, in the window's global points.
    func windowPoint(sent sentPoint: CGPoint) -> CGPoint { windowPoint(full: fullPixel(sentPoint)) }

    /// `png` drawn at `size` (high-quality interpolation), as a PNG; nil when it can't be made.
    static func scaled(_ png: Data, to size: CGSize) -> Data? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let width = Int(size.width), height = Int(size.height)
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let made = context.makeImage() else { return nil }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, made, nil)
        return CGImageDestinationFinalize(destination) ? out as Data : nil
    }
}
