import CoreGraphics
import CryptoKit
import Foundation
import SwiftUI
import BotAvatarsKit
import ImageIO

/// The backdrop a comparison still is laid on.
public enum StillScheme: String, Sendable {
    case dark, light
    /// sRGB 0–255, the same as the web harness's page background.
    public var backdrop: (r: Double, g: Double, b: Double) { self == .dark ? (17, 17, 19) : (245, 245, 247) }
}

/// Renders a still avatar offscreen, for the tests, the comparison harness
/// and the bench. Not part of the library product.
public enum StillRenderer {
    /// A paused avatar in its rest pose (or `pose`), drawn into a canvas
    /// `box × OVERSCAN` points square at `scale`, as `BotAvatar` draws it.
    @MainActor
    public static func render(_ cfg: BotAvatarDrawConfig, box: Double, scale: Double, pose: BotAvatarPose? = nil, state: BotAvatarRenderState = BotAvatarRenderState()) -> CGImage? {
        let full = box * BOT_AVATAR_OVERSCAN
        let p = pose ?? BotAvatarPose.rest(.default)
        let view = Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { ctx, _ in
            drawBotAvatarFrame(&ctx, box: box, pose: p, cfg: cfg, state: state)
        }
        .frame(width: full, height: full)
        /* drawn by Core Graphics into a bitmap of our own: the same pixels
           every time (the renderer's own images vary by a unit here and
           there with what it drew before) */
        let px = Int((full * scale).rounded())
        guard let g = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: px * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let r = ImageRenderer(content: view)
        r.render(rasterizationScale: scale) { _, draw in
            g.scaleBy(x: scale, y: scale)
            draw(g)
        }
        return g.makeImage()
    }

    /// The image's pixels as 8-bit premultiplied RGBA in sRGB, row by row.
    public static func rgba(_ img: CGImage) -> (bytes: [UInt8], width: Int, height: Int) {
        let w = img.width, h = img.height
        var out = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        out.withUnsafeMutableBytes { buf in
            let g = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            g.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return (out, w, h)
    }

    /// SHA-256 of the image's RGBA bytes, hex.
    public static func hash(_ img: CGImage) -> String {
        SHA256.hash(data: Data(rgba(img).bytes)).map { String(format: "%02x", $0) }.joined()
    }

    /// The image laid over the scheme's backdrop, opaque.
    public static func onBackdrop(_ img: CGImage, _ scheme: StillScheme) -> CGImage? {
        let w = img.width, h = img.height
        guard let g = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let b = scheme.backdrop
        g.setFillColor(red: b.r / 255, green: b.g / 255, blue: b.b / 255, alpha: 1)
        g.fill(CGRect(x: 0, y: 0, width: w, height: h))
        g.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return g.makeImage()
    }

    /// Write the image as a PNG.
    public static func writePNG(_ img: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(dest, img, nil)
        if !CGImageDestinationFinalize(dest) { throw CocoaError(.fileWriteUnknown) }
    }
}
