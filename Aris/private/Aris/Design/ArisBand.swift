//
//  ArisBand.swift
//  Aris
//
//  The closed notch's band while Aris listens: the rim along the notch's outline. The band's numbers are in
//  ArisBandMetrics.swift (ArisBand), its row (a mark each side of the camera) in ArisBandRow.swift.
//

import SwiftUI

/// While Aris listens: a faint hairline along the notch's whole outline, shoulder tip to shoulder tip (never along the
/// screen's top edge, ArisRimOutline), with a soft reflection gliding left to right along it, a long tail behind (the user's
/// pick "A 유리 반사", 2026-11-02). Each pass runs from the left tip until its tail has left the right one (ArisRimSweep);
/// only the last 4 points at each tip fade. A louder voice brightens it (the waveform's smoothing), and it draws
/// at the display's rate.
struct ArisListeningRim: View {
    let shape: NotchShape
    /// Between turns of a conversation: drawn still, as under Reduce Motion (no sweep, nothing redrawn each frame).
    var calm = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var voice = ArisRimVoice()
    @State private var geometry = ArisRimGeometry()
    /// When this rim appeared (it's inserted while listening), so every listen starts with a fresh pass.
    @State private var startedAt = Date()

    private static let pad: CGFloat = 6
    /// sRGB white and sky (160, 214, 255).
    private static let white = (red: 1.0, green: 1.0, blue: 1.0)
    private static let sky = (red: 160 / 255.0, green: 214 / 255.0, blue: 1.0)
    /// Bloom, halo, core: (stroke, gain, colour).
    private static let passes = [(6, 0.07, sky), (3, 0.16, sky), (1.1, 1, white)]
        .map { (StrokeStyle(lineWidth: $0.0, lineCap: .round), $0.1, $0.2) }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion || calm)) { context in
            Canvas { canvas, size in
                let rim = geometry.rim(shape: shape, size: size, pad: Self.pad)
                guard !rim.segments.isEmpty else { return }
                let loud = voice.step(level: ArisController.shared.level)
                let head = reduceMotion || calm ? rim.total / 2
                    : ArisRimSweep.head(at: context.date.timeIntervalSince(startedAt), total: rim.total)
                let lift = 0.75 + 0.6 * min(1, loud * 2.4)
                for (style, gain, color) in Self.passes {
                    for segment in rim.segments {
                        let behind = head - segment.middle
                        let glow = behind >= 0 ? exp(-behind / ArisRimSweep.tail) : exp(-(behind * behind) / 40)
                        let alpha = segment.endFade * (0.09 + 0.85 * glow * lift) * gain
                        guard alpha > 0.004 else { continue }
                        canvas.stroke(segment.path, with: .color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: alpha),
                                      style: style)
                    }
                }
            }
            .padding(-Self.pad)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}

/// The rim's segments for one notch shape and size, built once and reused every frame: each 1.5-point piece of the U
/// as a path, with where its middle sits along the U and how much the ends' 16-point fade dims it.
final class ArisRimGeometry {
    struct Segment {
        let path: Path
        let middle: Double
        let endFade: Double
    }

    struct Rim {
        var segments: [Segment] = []
        var total = 0.0
    }

    private var key: (shape: NotchShape, size: CGSize)?
    private var cached = Rim()

    func rim(shape: NotchShape, size: CGSize, pad: CGFloat) -> Rim {
        if let key, key.shape == shape, key.size == size { return cached }
        let rect = CGRect(x: pad, y: pad, width: size.width - 2 * pad, height: size.height - 2 * pad)
        let points = shape.outlinePoints(in: rect)
        var rim = Rim()
        if points.count > 1 {
            var lengths = [0.0]
            for i in 1..<points.count {
                lengths.append(lengths[i - 1] + Double(hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)))
            }
            rim.total = lengths[points.count - 1]
            rim.segments = (1..<points.count).map { i in
                var path = Path()
                path.move(to: points[i - 1])
                path.addLine(to: points[i])
                let middle = (lengths[i] + lengths[i - 1]) / 2
                return Segment(path: path, middle: middle, endFade: ArisRimOutline.endFade(middle, total: rim.total))
            }
        }
        key = (shape, size)
        cached = rim
        return rim
    }

}

/// The voice's loudness as the waveform smooths it: ignores the room below 0.012, square-root, a soft knee
/// under 0.08, rising at 0.45 and falling at 0.14 of the gap per frame.
final class ArisRimVoice {
    private var smooth = 0.0

    func step(level: Float) -> Double {
        let raw = Double(level) / 8  // ours is RMS × 8
        let above = max(0, raw - 0.012)
        let root = above > 0 ? above.squareRoot() : 0
        let target = root < 0.08 ? root * root / 0.08 : root
        smooth += (target - smooth) * (target > smooth ? 0.45 : 0.14)
        return smooth
    }
}
