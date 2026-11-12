//
//  ArisImageBudget.swift
//  Aris
//
//  How big an image sent to the AI may be, and when a capture is too small to be real, for the per-turn screenshot,
//  the drawing reference and the hi-res gesture frame. Pure, so the tests run it.
//

import CoreGraphics
import Foundation

/// A pixel budget: scale down so the long edge fits `maxLongEdge`, but keep the short edge at least `minShortEdge`
/// (text stays readable on a wide display), and never past `hardMaxLongEdge`. Never scales up.
struct ArisImageBudget: Equatable {
    let maxLongEdge: CGFloat
    let minShortEdge: CGFloat
    let hardMaxLongEdge: CGFloat

    /// The per-turn screenshot of the display under the cursor.
    static let cursor = ArisImageBudget(maxLongEdge: 1920, minShortEdge: 800, hardMaxLongEdge: 3072)
    /// The whole-screen drawing reference.
    static let drawing = ArisImageBudget(maxLongEdge: 1280, minShortEdge: 800, hardMaxLongEdge: 3072)
    /// The hi-res frame gesture crops are cut from.
    static let gestureFrame = ArisImageBudget(maxLongEdge: 3072, minShortEdge: 0, hardMaxLongEdge: 3072)
    /// The setup's first capture (ArisFirstCapture): taken only so macOS asks its second question there, and dropped
    /// at once, so it is as small as a frame gets.
    static let consent = ArisImageBudget(maxLongEdge: 64, minShortEdge: 0, hardMaxLongEdge: 64)

    /// `scale = min(1, max(maxLong/long, minShort/short), hardMax/long)`, rounded to whole pixels.
    func fit(_ px: CGSize) -> CGSize {
        guard px.width > 0, px.height > 0 else { return .zero }
        let long = max(px.width, px.height), short = min(px.width, px.height)
        let scale = min(1, max(maxLongEdge / long, minShortEdge / short), hardMaxLongEdge / long)
        return CGSize(width: max(1, (px.width * scale).rounded()), height: max(1, (px.height * scale).rounded()))
    }
}

enum ArisImageFormat: String {
    case png = "image/png", jpeg = "image/jpeg"
}

/// What each image is encoded as: the per-turn screenshot and thumbnails are PNG; a gesture shot is
/// JPEG 0.90 (`gesture-screenshot-N.jpg`); a drawing reference is JPEG 0.80.
enum ArisImageUse {
    case cursor, gestureShot, drawing, thumbnail

    var format: ArisImageFormat {
        switch self {
        case .cursor, .thumbnail: .png
        case .gestureShot, .drawing: .jpeg
        }
    }

    /// The JPEG quality; nil for PNG.
    var quality: CGFloat? {
        switch self {
        case .gestureShot: 0.90
        case .drawing: 0.80
        case .cursor, .thumbnail: nil
        }
    }
}

/// A capture this small is a blank or black frame (a cold start or a missing grant), so it counts as no image.
enum ArisImageFloor {
    static let png = 4_096
    static let jpeg = 6_144

    static func isBlank(bytes: Int, format: ArisImageFormat, pixels: CGSize) -> Bool {
        guard pixels.width > 0, pixels.height > 0 else { return true }
        return bytes < (format == .png ? png : jpeg)
    }
}
