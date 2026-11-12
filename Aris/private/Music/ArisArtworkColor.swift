//
//  ArisArtworkColor.swift
//  Aris
//
//  The artwork's colour for the bars and the peek: the mean of a small copy of the image, lifted so that dark
//  artwork still gives a visible tint; and a helper that sets a colour's perceived brightness.
//

import AppKit
import SwiftUI

enum ArisArtworkColor {
    /// The small copy's longer side, in pixels.
    static let sampleSide = 64

    /// The mean colour of `image` (nil if it has no bitmap). Transparent pixels count as black.
    static func average(of image: CGImage) -> NSColor? {
        let longer = max(image.width, image.height)
        guard longer > 0 else { return nil }
        let scale = min(1, Double(sampleSide) / Double(longer))
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let pixels = context.data else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytes = pixels.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var sums = (r: 0.0, g: 0.0, b: 0.0)
        for i in 0..<(width * height) {
            sums.r += Double(bytes[i * 4])
            sums.g += Double(bytes[i * 4 + 1])
            sums.b += Double(bytes[i * 4 + 2])
        }
        let count = Double(width * height) * 255
        let lifted = lift(r: sums.r / count, g: sums.g / count, b: sums.b / count)
        return NSColor(red: lifted.r, green: lifted.g, blue: lifted.b, alpha: 1)
    }

    /// Near-black becomes mid grey; a colour whose strongest channel is under 0.5 is raised evenly until it is 0.5.
    static func lift(r: Double, g: Double, b: Double) -> (r: Double, g: Double, b: Double) {
        if r < 0.03, g < 0.03, b < 0.03 { return (0.5, 0.5, 0.5) }
        let top = max(r, g, b)
        guard top < 0.5 else { return (r, g, b) }
        let raise = 0.5 - top
        return (r + raise, g + raise, b + raise)
    }

    /// Scales a colour so its perceived luminance (Rec. 709 weights on the encoded sRGB values) is `factor`, each
    /// channel capped at 1. Black becomes grey at `factor`. A factor outside 0…1 leaves the colour as it is.
    static func withLuminance(r: Double, g: Double, b: Double, factor: Double) -> (r: Double, g: Double, b: Double) {
        let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
        guard y > 0 else { return (factor, factor, factor) }
        let k = factor / y
        return (min(r * k, 1), min(g * k, 1), min(b * k, 1))
    }
}

extension NSImage {
    /// The artwork's mean colour, computed off the main actor; nil if the image has no bitmap.
    func averageColor() async -> NSColor? {
        guard let image = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return await Task.detached(priority: .utility) { ArisArtworkColor.average(of: image) }.value
    }
}

extension Color {
    func ensureMinimumBrightness(factor: CGFloat) -> Color {
        guard (0...1).contains(factor), let rgb = NSColor(self).usingColorSpace(.sRGB) else { return self }
        let c = ArisArtworkColor.withLuminance(r: rgb.redComponent, g: rgb.greenComponent, b: rgb.blueComponent, factor: factor)
        return Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: rgb.alphaComponent)
    }
}
