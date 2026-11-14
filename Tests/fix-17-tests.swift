// Tests for fix-17 (the thirteenth VM pass on 1787033b, qa/vm-run-1111/NOTES-thirteenth-raw.txt): on macOS 26 the
// app icon still had the star (the Icon Composer file, which wins there, kept its star group); the Settings sidebar's end
// never faded (the list's frame never reached the scroller); and closing the right side notch, the glass kept the open
// outline for two frames while the wash already shrank. Called from main.swift; uses its check().
import CoreGraphics
import Foundation

private let fix17Root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private func fix17Source(_ path: String) -> String { (try? String(contentsOf: fix17Root.appendingPathComponent(path), encoding: .utf8)) ?? "" }

func runFix17Tests() {
    fix17IconTests()
    fix17SidebarWatchTests()
    fix17SideCloseLatencyTests()
}

// MARK: - 1. The icon on macOS 26 (AppIcon.icon) has no star and the A in the middle

private func fix17IconTests() {
    let folder = fix17Root.appendingPathComponent("Aris/private/App/AppIcon.icon")
    let json = (try? Data(contentsOf: folder.appendingPathComponent("icon.json"))).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
    let groups = (json?["groups"] as? [[String: Any]]) ?? []
    let images = groups.flatMap { ($0["layers"] as? [[String: Any]]) ?? [] }.compactMap { $0["image-name"] as? String }
    check(groups.map { $0["name"] as? String } == ["A"] && images == ["A.svg"],
          "fix-17 icon: the Icon Composer icon is the A alone (no star group): \(groups.map { $0["name"] as? String ?? "?" })")
    check(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("Assets/star.svg").path), "fix-17 icon: the star's drawing is gone")
    // The A's box on the 1024 canvas: its centre within 2 pt of the middle across, and where the macOS 14/15 icon has it
    // down (516 of 1024 there, the drawing's own 3-pt offset taken off: 513).
    let svg = fix17Source("Aris/private/App/AppIcon.icon/Assets/A.svg")
    guard let box = fix17SVGBox(svg) else { return check(false, "fix-17 icon: the A's outline reads") }
    check(abs(box.midX - 512) < 2 && abs(box.midY - 513) < 2 && abs(box.width - 632.7) < 1,
          "fix-17 icon: the A keeps its size and sits in the middle of the tile (centre \(Int(box.midX)), \(Int(box.midY)))")
}

/// The box of the A's path in the 1024 canvas: its points (and curve handles) through its translate and scale.
private func fix17SVGBox(_ svg: String) -> CGRect? {
    guard let d = svg.range(of: #" d="[^"]+""#, options: .regularExpression).map({ String(svg[$0].dropFirst(4).dropLast()) }),
          let t = svg.range(of: #"translate\([-0-9. ]+\) scale\([-0-9.]+\)"#, options: .regularExpression) else { return nil }
    let numbers = String(svg[t]).components(separatedBy: CharacterSet(charactersIn: "-0123456789.").inverted).filter { !$0.isEmpty }.compactMap(Double.init)
    guard numbers.count == 3 else { return nil }
    let (tx, ty, scale) = (numbers[0], numbers[1], numbers[2])
    var tokens: [String] = []
    var current = ""
    for ch in d {
        if ch.isLetter { if !current.isEmpty { tokens.append(current) }; tokens.append(String(ch)); current = "" }
        else if ch == "-" { if !current.isEmpty { tokens.append(current) }; current = "-" }
        else if ch == " " || ch == "," { if !current.isEmpty { tokens.append(current) }; current = "" }
        else if ch == ".", current.contains(".") { tokens.append(current); current = "." }
        else { current.append(ch) }
    }
    if !current.isEmpty { tokens.append(current) }
    var i = 0, x = 0.0, y = 0.0, start = (0.0, 0.0), command = "m"
    var points: [(Double, Double)] = []
    func next() -> Double { defer { i += 1 }; return Double(tokens[i]) ?? 0 }
    while i < tokens.count {
        if tokens[i].first?.isLetter == true { command = tokens[i]; i += 1 }
        let relative = command == command.lowercased()
        switch command.lowercased() {
        case "z": x = start.0; y = start.1; continue
        case "m", "l":
            let a = next(), b = next()
            (x, y) = relative ? (x + a, y + b) : (a, b)
            if command.lowercased() == "m" { start = (x, y); command = relative ? "l" : "L" }
            points.append((x, y))
        case "h": let a = next(); x = relative ? x + a : a; points.append((x, y))
        case "v": let a = next(); y = relative ? y + a : a; points.append((x, y))
        case "c":
            let v = (0..<6).map { _ in next() }
            if relative { points += [(x + v[0], y + v[1]), (x + v[2], y + v[3])]; x += v[4]; y += v[5] }
            else { points += [(v[0], v[1]), (v[2], v[3])]; x = v[4]; y = v[5] }
            points.append((x, y))
        default: return nil
        }
    }
    let xs = points.map { $0.0 * scale + tx }, ys = points.map { $0.1 * scale + ty }
    guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { return nil }
    return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
}

// MARK: - 2. The sidebar's end fades again (the scroller is watched where it scrolls)

private func fix17SidebarWatchTests() {
    let sidebar = fix17Source("Aris/components/Settings/ArisSettingsSidebar.swift")
    check(!sidebar.contains("ArisSidebarListFrame") && !sidebar.contains(".onPreferenceChange("),
          "fix-17 fade: no preference from inside the ScrollView (it never reached the scroller: the end never faded)")
    check(sidebar.contains("onScrollGeometryChange(for: CGRect.self)") && sidebar.contains("geometry.contentSize.height")
          && sidebar.contains("-(geometry.contentOffset.y + geometry.contentInsets.top)") && sidebar.contains("if #available(macOS 15.0, *)"),
          "fix-17 fade: from macOS 15 the scroller's own geometry gives the list's height and how far it has scrolled")
    check(sidebar.contains(".onChange(of: frame) { _, next in follow(next) }") && sidebar.contains(".onAppear { follow(frame) }"),
          "fix-17 fade: on macOS 14 the list's laid-out frame does, from its first layout on")
    // With the list's real height the rule fades at the top of a long list and not at its end (fix-16's rule).
    typealias M = ArisSidebarMetrics
    let list = M.pagesHeight(), box = 480.0
    check(M.fades(listHeight: list, boxHeight: box, listTop: 0, chosen: M.rowSpan(.aris)) && !M.fades(listHeight: 0, boxHeight: box, listTop: 0, chosen: nil),
          "fix-17 fade: measured, a long list fades at the top; unmeasured (height 0, the thirteenth pass) it never did")
}

// MARK: - 3. Closing, the glass is never outside the wash even when its outline reaches the screen late

/// A polygon of `count` points on a w × h box from (0, top).
private func fix17Box(width: CGFloat, height: CGFloat, top: CGFloat, count: Int = 44) -> CGPath {
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

/// The worst overhang of the glass past the wash over a close asked for at 0, with the glass's outline reaching the
/// screen `latency` frames after it is set (it is set on every frame from the moment of asking, for the frame then due).
private func fix17Overhang(delayFrames: Int, sample: (ArisSideMorph, Double, Double) -> Double, latency: Int, frame: Double) -> CGFloat {
    let open = fix17Box(width: 232, height: 580, top: 0), hidden = fix17Box(width: 0, height: 48, top: 266)
    guard let close = ArisSideMorph(from: open, to: hidden, begin: Double(delayFrames) * frame, timing: ArisSideLook.closing) else { return .infinity }
    var worst: CGFloat = 0
    var shown = 0.0
    while shown <= close.end + 4 * frame {
        let wash = close.points(at: shown).map(\.x).max() ?? 0
        // What the glass shows now: what was set `latency` frames ago (the open outline before anything was set).
        let setFor = shown - Double(latency) * frame
        let glass = setFor < 0 ? 232 : close.points(at: sample(close, setFor, frame)).map(\.x).max() ?? 0
        worst = max(worst, glass - wash)
        shown += frame
    }
    return worst
}

private func fix17SideCloseLatencyTests() {
    for frame in [1.0 / 60, 1.0 / 120] {
        let hz = Int((1 / frame).rounded())
        // Before: the wash at once, the glass a frame ahead; with its outline two frames late the glass stood outside.
        let before = fix17Overhang(delayFrames: 0, sample: { _, shown, frame in shown + frame }, latency: 2, frame: frame)
        check(before > (hz == 60 ? 3 : 1), "fix-17 side close: at \(hz) Hz with the glass two frames late it stood \(Int(before)) pt outside the wash")
        for latency in 0...2 {
            let after = fix17Overhang(delayFrames: ArisSideMorph.washDelay, sample: { morph, shown, frame in morph.glassTime(shown: shown, frame: frame) },
                                      latency: latency, frame: frame)
            check(after <= 0, "fix-17 side close: at \(hz) Hz with the glass \(latency) frame(s) late it never stands outside the wash (\(after))")
        }
    }
    check(ArisSideMorph.begin(now: 5, frame: 0.01, shrinking: true) == 5.02 && ArisSideMorph.begin(now: 5, frame: 0.01, shrinking: false) == 5,
          "fix-17 side close: a shrinking morph starts two frames after it is asked for; a growing one at once")
    let layers = fix17Source("Aris/private/Aris/Side/ArisSideLayers.swift")
    check(layers.contains("begin = ArisSideMorph.begin(now: now, frame: frameInterval, shrinking: asked.shrinks)")
          && layers.contains("animation.fillMode = .backwards") && layers.contains("linkUntil = (morph?.end ?? CACurrentMediaTime() + duration) + 0.05"),
          "fix-17 side close: the wash, mask and rim start on the morph's (late) begin, holding the open outline until then, and the glass follows to the end")
}
