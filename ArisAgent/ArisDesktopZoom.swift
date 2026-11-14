//
//  ArisDesktopZoom.swift
//  aris-agent
//
//  Zoom then point, for click-at on a small drawn target: when the vision brain's first point is unsure, or what it
//  points at is small, a second look at a cropped, enlarged part of the same picture around that point (the same
//  picture: what the privacy filter painted out stays painted out), and its point mapped back into the window's
//  pixels. One extra vision call at most, and only then. The maths is pure; the crop is CoreGraphics.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The vision brain's answer with how sure it is and whether what it found is small.
struct ArisDesktopVisionAnswer: Equatable {
    let pick: ArisDesktopPick
    /// The brain said it isn't sure (nil: it said nothing either way).
    var sure: Bool? = nil
    /// The brain said what it found is small (a few pixels across).
    var small: Bool? = nil
}

enum ArisDesktopZoom {
    /// Half the crop's side, in the picture's pixels, around the first point.
    static let radius: CGFloat = 90
    /// How many times the crop is enlarged (at most `maxSide` pixels a side).
    static let factor: CGFloat = 3
    static let maxSide: CGFloat = 900
    /// A control this small (points, both sides: an icon) is a small target.
    static let smallSide: CGFloat = 24

    /// Whether the first point gets a second, closer look: the brain was unsure, or said it's small, or the accessibility
    /// control under the point is an icon-sized one (`under`: the smallest control there; text read off the screen
    /// doesn't count, its lines are short by nature).
    static func needed(_ answer: ArisDesktopVisionAnswer, under: CGRect?) -> Bool {
        guard case .point = answer.pick else { return false }
        if answer.sure == false || answer.small == true { return true }
        if let under, under.width > 0, under.height > 0, max(under.width, under.height) < smallSide { return true }
        return false
    }

    /// The part of the picture (`width`×`height` pixels) around `point`, a square of `2·radius` kept inside it.
    static func crop(around point: CGPoint, width: Int, height: Int, radius: CGFloat = radius) -> CGRect {
        let w = CGFloat(width), h = CGFloat(height)
        let side = min(2 * radius, w, h)
        let x = min(max(0, (point.x - side / 2).rounded(.down)), w - side)
        let y = min(max(0, (point.y - side / 2).rounded(.down)), h - side)
        return CGRect(x: x, y: y, width: side, height: side)
    }

    /// How many times the crop is enlarged.
    static func scale(for crop: CGRect) -> CGFloat {
        guard crop.width > 0, crop.height > 0 else { return 1 }
        return max(1, min(factor, maxSide / max(crop.width, crop.height)))
    }

    /// A point in the enlarged crop, back in the whole picture's pixels (nil when it falls outside the crop).
    static func mapBack(_ zoomed: CGPoint, crop: CGRect, scale: CGFloat) -> CGPoint? {
        guard scale > 0 else { return nil }
        let x = zoomed.x / scale, y = zoomed.y / scale
        guard x >= 0, y >= 0, x <= crop.width, y <= crop.height else { return nil }
        return CGPoint(x: crop.minX + x, y: crop.minY + y)
    }

    /// The crop of `png` enlarged by `scale`, as a PNG; nil when it can't be made.
    static func enlarged(_ png: Data, crop: CGRect, scale: CGFloat) -> Data? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let part = image.cropping(to: crop.integral) else { return nil }
        let width = Int((CGFloat(part.width) * scale).rounded()), height = Int((CGFloat(part.height) * scale).rounded())
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .none
        context.draw(part, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let made = context.makeImage() else { return nil }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, made, nil)
        return CGImageDestinationFinalize(destination) ? out as Data : nil
    }

    /// What the second look is asked: the same target, in an enlarged part of the window.
    static func question(_ target: String, scale: CGFloat) -> String {
        "\(target) (this picture is a part of the window enlarged \(Int(scale.rounded()))×: answer with a point in this picture)"
    }

    /// The first point, refined: when `needed`, one more look at the enlarged crop (`look` asks the vision brain about
    /// a picture of the given size) and its point mapped back; else, or when that look finds nothing, the first point.
    static func refine(_ first: ArisDesktopVisionAnswer, png: Data, width: Int, height: Int, target: String, under: CGRect?,
                       look: (_ png: Data, _ width: Int, _ height: Int, _ target: String) -> ArisDesktopPick?) -> (point: CGPoint, zoomed: Bool)? {
        guard case .point(let point) = first.pick else { return nil }
        guard needed(first, under: under) else { return (point, false) }
        let part = crop(around: point, width: width, height: height)
        let times = scale(for: part)
        guard let picture = enlarged(png, crop: part, scale: times) else { return (point, false) }
        let side = (Int((part.width * times).rounded()), Int((part.height * times).rounded()))
        guard case .point(let closer)? = look(picture, side.0, side.1, question(target, scale: times)),
              let back = mapBack(closer, crop: part, scale: times) else { return (point, false) }
        return (back, true)
    }
}
