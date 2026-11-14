//
//  ArisLineIconPath.swift
//  Aris
//
//  Turns a line icon's shapes (ArisLineIconData) into paths on its 24 grid: SVG path data (M L H V C S Q T A Z, absolute
//  and relative), circles, rects with rounded corners, lines, ellipses and point lists. CoreGraphics only, so the
//  tests compile it.
//

import CoreGraphics
import Foundation

enum ArisLineIconPath {
    /// The grid every glyph is drawn on.
    static let grid: CGFloat = 24

    /// A glyph's outline (`stroke`) and its filled parts (`fill`), on the 24 grid.
    struct Glyph {
        let stroke: CGPath
        let fill: CGPath
    }

    /// The glyph for a name or an SF Symbol name the settings use, or nil when there is none.
    static func name(for name: String) -> String? {
        if ArisLineIconData.glyphs[name] != nil { return name }
        return ArisLineIconData.systemNames[name]
    }

    nonisolated(unsafe) private static var cache: [String: Glyph] = [:]
    private static let lock = NSLock()

    static func glyph(_ name: String) -> Glyph? {
        guard let resolved = Self.name(for: name), let elements = ArisLineIconData.glyphs[resolved] else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[resolved] { return hit }
        let stroke = CGMutablePath(), fill = CGMutablePath()
        for element in elements {
            let filled = element.hasPrefix("f")
            add(filled ? String(element.dropFirst()) : element, to: filled ? fill : stroke)
        }
        let glyph = Glyph(stroke: stroke, fill: fill)
        cache[resolved] = glyph
        return glyph
    }

    // MARK: Shapes

    static func add(_ element: String, to path: CGMutablePath) {
        guard let colon = element.firstIndex(of: ":") else { return }
        let kind = element[..<colon], body = String(element[element.index(after: colon)...])
        let n = numbers(body)
        switch kind {
        case "p": addPathData(body, to: path)
        case "c" where n.count >= 3: path.addEllipse(in: CGRect(x: n[0] - n[2], y: n[1] - n[2], width: n[2] * 2, height: n[2] * 2))
        case "e" where n.count >= 4: path.addEllipse(in: CGRect(x: n[0] - n[2], y: n[1] - n[3], width: n[2] * 2, height: n[3] * 2))
        case "l" where n.count >= 4:
            path.move(to: CGPoint(x: n[0], y: n[1]))
            path.addLine(to: CGPoint(x: n[2], y: n[3]))
        case "r" where n.count >= 4:
            let rect = CGRect(x: n[0], y: n[1], width: n[2], height: n[3])
            let rx = min(n.count > 4 ? n[4] : 0, rect.width / 2), ry = min(n.count > 5 ? n[5] : rx, rect.height / 2)
            if rx > 0 || ry > 0 { path.addRoundedRect(in: rect, cornerWidth: rx, cornerHeight: ry) } else { path.addRect(rect) }
        case "pl", "pg":
            var points: [CGPoint] = []
            var index = 0
            while index + 1 < n.count { points.append(CGPoint(x: n[index], y: n[index + 1])); index += 2 }
            guard let first = points.first else { return }
            path.move(to: first)
            points.dropFirst().forEach { path.addLine(to: $0) }
            if kind == "pg" { path.closeSubpath() }
        default: break
        }
    }

    private static func numbers(_ text: String) -> [CGFloat] {
        var scanner = Tokens(text)
        var out: [CGFloat] = []
        while let value = scanner.number() { out.append(value) }
        return out
    }

    // MARK: Path data

    /// SVG path data into `path`.
    static func addPathData(_ data: String, to path: CGMutablePath) {
        var t = Tokens(data)
        var current = CGPoint.zero, start = CGPoint.zero
        var lastControl: CGPoint?, lastQuad: CGPoint?
        var command: Character = "M"
        while true {
            if let next = t.command() { command = next } else if t.atEnd { break }
            let relative = command.isLowercase
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y) }
            switch command.uppercased() {
            case "M":
                guard let x = t.number(), let y = t.number() else { return }
                current = point(x, y); start = current
                path.move(to: current)
                // Further pairs after a move are lines.
                command = relative ? "l" : "L"
                lastControl = nil; lastQuad = nil
            case "L":
                guard let x = t.number(), let y = t.number() else { return }
                current = point(x, y)
                path.addLine(to: current)
                lastControl = nil; lastQuad = nil
            case "H":
                guard let x = t.number() else { return }
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current)
                lastControl = nil; lastQuad = nil
            case "V":
                guard let y = t.number() else { return }
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current)
                lastControl = nil; lastQuad = nil
            case "C":
                guard let x1 = t.number(), let y1 = t.number(), let x2 = t.number(), let y2 = t.number(), let x = t.number(), let y = t.number() else { return }
                let c1 = point(x1, y1), c2 = point(x2, y2), end = point(x, y)
                path.addCurve(to: end, control1: c1, control2: c2)
                current = end; lastControl = c2; lastQuad = nil
            case "S":
                guard let x2 = t.number(), let y2 = t.number(), let x = t.number(), let y = t.number() else { return }
                let c1 = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                let c2 = point(x2, y2), end = point(x, y)
                path.addCurve(to: end, control1: c1, control2: c2)
                current = end; lastControl = c2; lastQuad = nil
            case "Q":
                guard let x1 = t.number(), let y1 = t.number(), let x = t.number(), let y = t.number() else { return }
                let c = point(x1, y1), end = point(x, y)
                path.addQuadCurve(to: end, control: c)
                current = end; lastQuad = c; lastControl = nil
            case "T":
                guard let x = t.number(), let y = t.number() else { return }
                let c = lastQuad.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                let end = point(x, y)
                path.addQuadCurve(to: end, control: c)
                current = end; lastQuad = c; lastControl = nil
            case "A":
                guard let rx = t.number(), let ry = t.number(), let angle = t.number(), let large = t.flag(), let sweep = t.flag(),
                      let x = t.number(), let y = t.number() else { return }
                let end = point(x, y)
                addArc(to: path, from: current, to: end, rx: rx, ry: ry, angle: angle, large: large, sweep: sweep)
                current = end; lastControl = nil; lastQuad = nil
            case "Z":
                path.closeSubpath()
                current = start; lastControl = nil; lastQuad = nil
                // Z takes no numbers: the next token must be a command.
                guard let next = t.command() else { return }
                command = next
                continue
            default:
                return
            }
        }
    }

    /// An SVG elliptical arc as cubic curves (the endpoint-to-centre conversion of SVG 1.1 F.6.5).
    static func addArc(to path: CGMutablePath, from p0: CGPoint, to p1: CGPoint, rx rxIn: CGFloat, ry ryIn: CGFloat, angle: CGFloat, large: Bool, sweep: Bool) {
        var rx = abs(rxIn), ry = abs(ryIn)
        guard rx > 0, ry > 0, p0 != p1 else { path.addLine(to: p1); return }
        let phi = angle * .pi / 180, cosP = cos(phi), sinP = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1 = cosP * dx + sinP * dy, y1 = -sinP * dx + cosP * dy
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 { rx *= sqrt(lambda); ry *= sqrt(lambda) }
        let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var coef = den == 0 ? 0 : sqrt(max(0, num / den))
        if large == sweep { coef = -coef }
        let cx1 = coef * rx * y1 / ry, cy1 = -coef * ry * x1 / rx
        let cx = cosP * cx1 - sinP * cy1 + (p0.x + p1.x) / 2
        let cy = sinP * cx1 + cosP * cy1 + (p0.y + p1.y) / 2
        func angleOf(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let a = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
            return a
        }
        let theta1 = angleOf(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var delta = angleOf((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep, delta > 0 { delta -= 2 * .pi } else if sweep, delta < 0 { delta += 2 * .pi }
        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / CGFloat(segments)
        let k = 4 / 3 * tan(step / 4)
        func at(_ t: CGFloat) -> (CGPoint, CGPoint) {
            let x = rx * cos(t), y = ry * sin(t)
            let point = CGPoint(x: cx + cosP * x - sinP * y, y: cy + sinP * x + cosP * y)
            let dxT = -rx * sin(t), dyT = ry * cos(t)
            return (point, CGPoint(x: cosP * dxT - sinP * dyT, y: sinP * dxT + cosP * dyT))
        }
        var t = theta1
        for _ in 0..<segments {
            let (a, da) = at(t), (b, db) = at(t + step)
            path.addCurve(to: b, control1: CGPoint(x: a.x + k * da.x, y: a.y + k * da.y), control2: CGPoint(x: b.x - k * db.x, y: b.y - k * db.y))
            t += step
        }
    }

    /// Reads SVG path data: commands, numbers ("1.5-2", ".5.5", "1e-3") and the arcs' one-digit flags.
    private struct Tokens {
        private let chars: [Character]
        private var i = 0

        init(_ text: String) { chars = Array(text) }

        var atEnd: Bool {
            mutating get { skip(); return i >= chars.count }
        }

        private mutating func skip() {
            while i < chars.count, chars[i] == " " || chars[i] == "," || chars[i] == "\n" || chars[i] == "\t" { i += 1 }
        }

        mutating func command() -> Character? {
            skip()
            guard i < chars.count, chars[i].isLetter, chars[i] != "e", chars[i] != "E" else { return nil }
            defer { i += 1 }
            return chars[i]
        }

        mutating func flag() -> Bool? {
            skip()
            guard i < chars.count, chars[i] == "0" || chars[i] == "1" else { return nil }
            defer { i += 1 }
            return chars[i] == "1"
        }

        mutating func number() -> CGFloat? {
            skip()
            let begin = i
            if i < chars.count, chars[i] == "-" || chars[i] == "+" { i += 1 }
            var digits = false, dot = false
            while i < chars.count {
                let c = chars[i]
                if c.isNumber { digits = true; i += 1 } else if c == ".", !dot { dot = true; i += 1 } else { break }
            }
            if digits, i < chars.count, chars[i] == "e" || chars[i] == "E" {
                var j = i + 1
                if j < chars.count, chars[j] == "-" || chars[j] == "+" { j += 1 }
                if j < chars.count, chars[j].isNumber {
                    i = j
                    while i < chars.count, chars[i].isNumber { i += 1 }
                }
            }
            guard digits, let value = Double(String(chars[begin..<i])) else { i = begin; return nil }
            return CGFloat(value)
        }
    }
}
