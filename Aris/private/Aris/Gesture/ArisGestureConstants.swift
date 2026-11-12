//
//  ArisGestureConstants.swift
//  Aris
//
//  Every number the circle gesture uses. Image budgets, formats and blank floors are not repeated here: they live
//  in See/ArisImageBudget.swift. Pure, so the tests run it.
//
//  Left out on purpose:
//  - a separate 500 ms tap window: Aris keeps its own 350 ms tap limit (ArisTalkKey), plan D5.
//  - settle and hide delays around a capture, and a spotlight scrim: Aris filters its own windows out of the
//    capture (plan D1).
//

import CoreGraphics
import Foundation

enum ArisGestureConstants {
    /// The drawing session: when it commits, how the pointer arms it, how many displays and shots.
    enum Session {
        static let commitWindowMs = 200.0
        static let screenshotDeferMs = 1500.0
        static let cursorPumpIntervalMs = 8.0
        static let armDebounceMs = 700.0
        static let armDeliberateTravel: CGFloat = 32
        static let armTravel: CGFloat = 12
        static let phantomArmTravel: CGFloat = 4       // phantom-move guard
        static let bootSampleCap = 240
        static let bootRecencyMs = 800.0
        static let bootMaxGapMs = 150.0
        static let displayWatchIntervalMs = 60.0
        static let maxDrawnDisplays = 3
        static let overlayLevelOffset = 13             // statusBar + 13
        static let hintLevelOffset = 14                // statusBar + 14
        static let strokesKept = 8                     // the stroke 8 back is deleted
        static let maxShots = 8
        static let dedupIoU: CGFloat = 0.45            // regions overlapping this much are one
        static let shotWaitMs = 1500.0
        static let frameHeldMaxAgeMs = 4000.0
        static let frameHandsFreeMaxAgeMs = 1500.0
        static let collectMaxAgeMs = 30_000.0
        static let collectWaitMs = 2500.0
    }

    /// The loop and scribble detector.
    enum Detector {
        static let windowMs = 5000.0
        static let decimate: CGFloat = 3
        static let cooldownMs = 900.0
        static let diagMin: CGFloat = 36
        static let minPoints = 12
        static let maxPoints = 1600
        static let closeRad = 5.9
        static let closeTolMin: CGFloat = 26
        static let closeTolFrac: CGFloat = 0.14
        static let closeTolMax: CGFloat = 110
        static let lapCap = 2 * Double.pi + 0.5
        static let strokeMaxGap: CGFloat = 140
        static let seamSeal: CGFloat = 1.5             // seam sealed within 1.5 x tol
        static let sharpRad = 2.1
        static let sharpMin = 4
        static let ratioMin: CGFloat = 2.2
        static let scribbleWindowMs = 2200.0
        static let scribblePathMin: CGFloat = 110
        static let headingMinSegment = 1.0             // segments < 1 px keep the previous heading
    }

    /// The on-screen ink (the owner's pick E, the highlighter) and the blue strokes drawn into images for the model.
    enum Ink {
        static let markerWidth: CGFloat = 12           // mockup E's 16 pt × 0.75 (the owner: "조금 더 얇게")
        static let markerAlpha: CGFloat = 0.34         // mockup E, applied once over the whole ribbon
        static let markerLifeMs = 900.0                // mockup E's life
        static let hue: CGFloat = 214                  // hsl(214,100%,60%)
        static let saturation: CGFloat = 1.0           // hsl(214,100%,60%)
        static let lightness: CGFloat = 0.60           // hsl(214,100%,60%)
        static let glowWidth: CGFloat = 20             // trail glow width
        static let coreWidth: CGFloat = 8              // trail core width
        static let dotRadius: CGFloat = 7              // a single point is a dot
        static let dirtyRectPad: CGFloat = 14          // trail dirty-rect pad
        static let maxBackingScale: CGFloat = 2        // backing scale min(screen scale, 2)
        static let tagFadeTravel: CGFloat = 220
        static let hintSize = CGSize(width: 280, height: 48)      // hint window
        static let hintOffset = CGSize(width: 18, height: 20)     // hint offset
    }

    /// The circled-window hit-test and the crop.
    enum Region {
        /// Bbox fractions sampled for the window under the loop: centre first.
        static let sampleFractions: [CGPoint] = [
            CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.24, y: 0.24), CGPoint(x: 0.76, y: 0.24),
            CGPoint(x: 0.24, y: 0.76), CGPoint(x: 0.76, y: 0.76),
        ]
        static let scoreTie: CGFloat = 0.02            // score tie band
        static let padMin: CGFloat = 140               // pad max(140, ...)
        static let padFraction: CGFloat = 0.4          // pad max(..., 0.4 w)
        static let minCropPt: CGFloat = 60
        static let minCropPx: CGFloat = 8              // a crop under 8 px is refused
        static let hiresMaxLongEdge: CGFloat = 3072
        static let cropMaxLongEdge: CGFloat = 2560
        static let cropJPEGQuality: CGFloat = 0.92     // crop JPEG 92 before compositing
    }

    /// Ink and badge drawn onto a shot, and the 8/8 reject.
    enum Shot {
        static let captureTrailMs = 3000.0
        static let trailStrengthPower = 3.0            // strength = clamp01(1 - age/3 s)^3
        static let pathCoreWidth: CGFloat = 4          // shot path core 4 px x scale
        static let subdivideRatio: CGFloat = 1.1       // subdivide when polygon > 1.1 x chord
        static let subdivideDepth = 6                  // subdivision depth
        static let thumbMaxWidth: CGFloat = 640        // thumb PNG <= 640 w
        static let thumbPathWidthPer320: CGFloat = 2   // thumb path 2 px per 320 px
        static let badgeRadiusFraction: CGFloat = 0.03 // badge r = clamp(round(0.03 w), 13, 44)
        static let badgeRadiusMin: CGFloat = 13
        static let badgeRadiusMax: CGFloat = 44
        static let badgeInset: CGFloat = 0.9           // inset 0.9 r
        static let badgeShadowAlpha: CGFloat = 0.35    // rgba(0,0,0,.35)
        static let badgeShadowBlur: CGFloat = 0.6      // blur 0.6 r
        static let badgeFontScale: CGFloat = 1.15      // bold round(1.15 r) px
        static let badgeFontYOffset: CGFloat = 0.06    // +0.06 r y
        static let rejectHue: CGFloat = 4              // hsl(4,100%,60%)
        static let rejectPad: CGFloat = 26             // reject loop pad
        static let rejectShakeMs = 380.0               // reject shake
        static let rejectFadeMs = 850.0                // reject fade
        static let rejectRemoveMs = 1250.0             // reject removal
        static let drawingInkOpacity: CGFloat = 0.55
    }

    /// Voiced time and the `[img N]` markers.
    enum Speech {
        static let rmsThresholdInt16: Float = 380      // on Int16 samples
        static let sampleRate = 16_000.0
        static let minVoicedTotalMs = 500.0
    }
}
