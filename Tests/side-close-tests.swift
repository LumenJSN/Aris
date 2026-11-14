// Tests for the side notch's silver flash on close (2026-11-13): the glass under the wash was given the outline on
// screen a frame earlier, so while the panel shrank the bare glass stood outside the wash. ArisSideMorph samples the
// render server's own morph for the frame being shown (a frame on while shrinking). Called from main.swift; uses check().
import CoreGraphics
import Foundation

func runSideCloseTests() {
    morphSampleTests()
    glassInsideWashTests()
    sideCloseWiringTests()
}

/// A polygon of `count` points on a w × h box from (0, top) — the same count in every state, as the outline's is.
private func box(width: CGFloat, height: CGFloat, top: CGFloat, count: Int = 44) -> CGPath {
    let corners = [CGPoint(x: 0, y: top), CGPoint(x: width, y: top), CGPoint(x: width, y: top + height), CGPoint(x: 0, y: top + height)]
    var points: [CGPoint] = []
    for i in 0..<count {
        let side = i * 4 / count, along = CGFloat(i * 4 % count) / CGFloat(count)
        let a = corners[side], b = corners[(side + 1) % 4]
        points.append(CGPoint(x: a.x + (b.x - a.x) * along, y: a.y + (b.y - a.y) * along))
    }
    let path = CGMutablePath()
    path.addLines(between: points)
    path.closeSubpath()
    return path
}

private let openPanel = box(width: 232, height: 580, top: 0)
private let hidden = box(width: 0, height: 48, top: 266)

private func morphSampleTests() {
    guard let close = ArisSideMorph(from: openPanel, to: hidden, begin: 10, timing: ArisSideLook.closing) else {
        return check(false, "side close: a morph between two outlines of the same count is made")
    }
    check(close.points(at: 9) == ArisSideMorph.points(of: openPanel) && close.points(at: 10.2) == ArisSideMorph.points(of: hidden)
          && close.end == 10.2 && close.shrinks,
          "side close: the morph starts at the open panel, ends at the hidden outline, 200 ms, and shrinks")
    let half = close.points(at: 10.1)
    let expected = CGFloat(232 * (1 - ArisSideLook.eased(0.5, ArisSideLook.closing)))
    check(abs((half.map(\.x).max() ?? 0) - expected) < 0.001, "side close: halfway, every point is where the eased (0.45, 0, 0.55, 1) curve puts it")
    let open = ArisSideMorph(from: hidden, to: openPanel, begin: 0, timing: ArisSideLook.opening)
    check(open?.shrinks == false && open?.glassTime(shown: 1, frame: 0.016) == 1 && abs(close.glassTime(shown: 10.1, frame: 0.016) - 10.148) < 1e-9,
          "side close: opening, the glass is the frame's own outline; closing, three frames on (fix-17)")
    check(ArisSideMorph(from: openPanel, to: box(width: 10, height: 10, top: 0, count: 12), begin: 0, timing: ArisSideLook.closing) == nil,
          "side close: outlines that don't match point for point make no morph (the glass then takes the wash's)")
}

/// For each frame shown during the close, how far the glass reaches past the wash's right edge.
private func overhang(_ close: ArisSideMorph, frame: Double, glassAt: (Double) -> Double) -> CGFloat {
    var worst: CGFloat = 0
    var shown = close.begin
    while shown <= close.end + frame {
        let wash = close.points(at: shown).map(\.x).max() ?? 0
        let glass = close.points(at: glassAt(shown)).map(\.x).max() ?? 0
        worst = max(worst, glass - wash)
        shown += frame
    }
    return worst
}

private func glassInsideWashTests() {
    guard let close = ArisSideMorph(from: openPanel, to: hidden, begin: 0, timing: ArisSideLook.closing) else { return }
    for frame in [1.0 / 60, 1.0 / 120] {
        let before = overhang(close, frame: frame) { $0 - frame }
        let after = overhang(close, frame: frame) { close.glassTime(shown: $0, frame: frame) }
        check(before > (frame > 0.01 ? 30 : 15) && after <= 0,
              "side close: at \(Int(1 / frame)) Hz the glass stood up to \(Int(before)) pt outside the wash (the silver flash); now it never does")
    }
}

private func sideCloseWiringTests() {
    let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../Aris/private/Aris/Side/ArisSideLayers.swift").standardized
    let layers = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
    check(!layers.contains("setGlassOutline(fill.presentation()") && layers.contains("glassPath(shown: link.targetTimestamp")
          && layers.contains("animation.beginTime = layer.convertTime(begin, from: nil)"),
          "side close: the glass follows the morph's clock for the frame being shown, never the frame already on screen")
    check(layers.contains("rim.shadowColor = .white") && layers.contains("rim.shadowRadius = ArisSideLook.rimRadius")
          && abs(ArisSideLook.rimOpacity(width: 16) - 0.12) < 1e-9 && ArisSideLook.rimOpacity(width: 232) == 0,
          "side close: the measured rim stays (white, radius 2, .12 on the sliver, none open)")
}
