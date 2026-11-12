// Off-screen proof that the open notch stays readable over a bright window. It draws the notch's background recipe
// (the glass's tint and the black gradient over it; the system's blur is treated as passing what is behind straight
// through) over a white window, a mid-grey one and a dark photo-like gradient, before (ArisGlass at 42394215) and
// after (ArisGlassRecipe), with the notch's real text colours and sizes on top, and prints each text style's WCAG
// contrast at the first line, the middle, three quarters down and the last line of a tall answer. Nothing touches the screen.
// usage: render.sh [OUT_DIR]
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : NSTemporaryDirectory()
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// MARK: - The notch's measurements (ArisGlass, ArisNotchHeader, ArisComposer)

enum Notch {
    static let canvas = CGSize(width: 620, height: 760)
    static let height = 710.0
    static let corner = 31.0
    static let body = 440.0
    static let left = (canvas.width - body) / 2
    static let inset = 12.0
    static let textInset = 16.0
    static let band = 37.0
    static let bottomInset = 8.0
    static var textX: Double { left + inset + textInset }
    static var firstLine: Double { 112 }
    static var lastLine: Double { height - bottomInset }
}

struct Backdrop {
    let name: String
    let file: String
    /// The colour behind the notch at a height (the system's blur passes the neighbourhood's average through).
    let color: (Double) -> GlassRGB
}

/// A dark photo: deep water at the top, a lighter band of rock and foam, dark again below.
private func photo(_ y: Double) -> GlassRGB {
    let stops: [(Double, GlassRGB)] = [(0, GlassRGB(r: 0.08, g: 0.16, b: 0.28)), (0.45, GlassRGB(r: 0.16, g: 0.36, b: 0.46)),
                                       (0.7, GlassRGB(r: 0.47, g: 0.56, b: 0.58)), (1, GlassRGB(r: 0.10, g: 0.20, b: 0.22))]
    let t = min(1, max(0, y / Notch.canvas.height))
    guard let next = stops.firstIndex(where: { $0.0 >= t }), next > 0 else { return stops[0].1 }
    let a = stops[next - 1], b = stops[next], f = (t - a.0) / (b.0 - a.0)
    return GlassRGB(r: a.1.r + (b.1.r - a.1.r) * f, g: a.1.g + (b.1.g - a.1.g) * f, b: a.1.b + (b.1.b - a.1.b) * f)
}

let backdrops = [Backdrop(name: "white window", file: "white", color: { _ in .white }),
                 Backdrop(name: "mid-grey window", file: "grey", color: { _ in .grey(0.5) }),
                 Backdrop(name: "dark photo", file: "dark", color: photo)]

enum Recipe: String, CaseIterable {
    case before, after, solid

    /// What is behind the text `y` points down the notch.
    func ground(at y: Double, backdrop: Backdrop) -> GlassRGB {
        switch self {
        case .before:
            return glassBehind(backdrop: backdrop.color(y), tint: GlassRecipeBefore.tint, black: GlassRecipeBefore.color,
                               blackAlpha: GlassRecipeBefore.alpha(at: y, height: Notch.height))
        case .after:
            return glassBehind(backdrop: backdrop.color(y), tint: (GlassRGB(r: 0, g: 0, b: ArisGlassRecipe.tintBlue), ArisGlassRecipe.tintAlpha),
                               black: .black, blackAlpha: ArisGlassRecipe.alpha(at: y, height: Notch.height))
        case .solid:
            // Reduce Transparency: no glass, solid black.
            return glassBehind(backdrop: backdrop.color(y), tint: nil, black: .black, blackAlpha: ArisGlassRecipe.alpha(at: y, height: Notch.height, glass: false))
        }
    }
}

// MARK: - Drawing

extension GlassRGB {
    func ns(_ alpha: Double = 1) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: alpha) }
}

/// The open notch's outline (NotchShape, squircle handle 2/3): concave ears at the top, convex corners at the bottom.
func notchPath() -> CGPath {
    let r = Notch.corner, h = 2.0 / 3.0
    let minX = Notch.left - r, maxX = Notch.left + Notch.body + r, maxY = Notch.height
    let path = CGMutablePath()
    var pen = CGPoint(x: minX, y: 0)
    path.move(to: pen)
    func turn(to end: CGPoint, around v: CGPoint) {
        path.addCurve(to: end, control1: CGPoint(x: pen.x + (v.x - pen.x) * h, y: pen.y + (v.y - pen.y) * h),
                      control2: CGPoint(x: end.x + (v.x - end.x) * h, y: end.y + (v.y - end.y) * h))
        pen = end
    }
    func line(to end: CGPoint) { path.addLine(to: end); pen = end }
    let left = minX + r, right = maxX - r
    turn(to: CGPoint(x: left, y: r), around: CGPoint(x: left, y: 0))
    line(to: CGPoint(x: left, y: maxY - r))
    turn(to: CGPoint(x: left + r, y: maxY), around: CGPoint(x: left, y: maxY))
    line(to: CGPoint(x: right - r, y: maxY))
    turn(to: CGPoint(x: right, y: maxY - r), around: CGPoint(x: right, y: maxY))
    line(to: CGPoint(x: right, y: r))
    turn(to: CGPoint(x: maxX, y: 0), around: CGPoint(x: right, y: 0))
    path.closeSubpath()
    return path
}

func text(_ words: String, x: Double, y: Double, size: Double, weight: NSFont.Weight = .regular, color: GlassRGB = .white, alpha: Double, tracking: Double = 0) {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let string = NSAttributedString(string: words, attributes: [.font: font, .foregroundColor: color.ns(alpha), .kern: tracking])
    string.draw(at: CGPoint(x: x, y: y))
}

func width(_ words: String, size: Double, weight: NSFont.Weight = .regular) -> Double {
    NSAttributedString(string: words, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight)]).size().width
}

func fill(_ rect: CGRect, radius: Double, white alpha: Double) {
    NSColor(white: 1, alpha: alpha).setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

/// A capsule with words in it; returns its right edge.
@discardableResult
func chip(_ words: String, x: Double, y: Double, height: Double = 28, fillAlpha: Double, textAlpha: Double, size: Double = 11.5, weight: NSFont.Weight = .medium) -> Double {
    let w = width(words, size: size, weight: weight) + 19
    fill(CGRect(x: x, y: y, width: w, height: height), radius: height / 2, white: fillAlpha)
    text(words, x: x + 9.5, y: y + (height - size * 1.25) / 2, size: size, weight: weight, alpha: textAlpha)
    return x + w
}

/// What the open notch shows in a long turn, in its own colours and sizes: the header, the user's words, a tall answer,
/// a card, the tags, a receipt, "Read more" and the composer's hint against the bottom inset.
func drawContent() {
    let x = Notch.textX, cardX = Notch.left + Notch.inset, cardW = Notch.body - 2 * Notch.inset
    fill(CGRect(x: Notch.left + Notch.body - 14 - 50, y: 7, width: 50, height: 23), radius: 11.5, white: 0.15)
    text("Close", x: Notch.left + Notch.body - 14 - 41, y: 11, size: 11, weight: .medium, alpha: 0.94)
    fill(CGRect(x: cardX, y: 39, width: cardW, height: 54), radius: 24, white: 0.07)
    text("why not?", x: x, y: 56, size: 15, alpha: 0.9)
    var y = Notch.firstLine
    func line(_ words: String, alpha: Double, size: Double = 15, weight: NSFont.Weight = .regular, indent: Double = 0, step: Double = 22.5) {
        text(words, x: x + indent, y: y, size: size, weight: weight, alpha: alpha)
        y += step
    }
    line("Aris's rules didn't refuse that. The model answered in its", alpha: 0.95)
    line("own words, and no command was tried. Your request does", alpha: 0.95)
    line("have a word about paying, and Aris never pays or orders.", alpha: 0.95)
    y += 8
    line("“pay my phone bill” (a quote, white .65)", alpha: 0.65)
    y += 8
    for row in ["You asked: “pay my phone bill”", "AI: the model you chose", "Memory: what went along with the request",
                "Read: neither the screen nor outside content", "Done: nothing in the activity log",
                "Rule: nothing was refused by Aris's gate", "Instead: that part is yours to do", "List lines are white .85, the last ones sit low"] {
        text("•", x: x, y: y, size: 15, alpha: 0.85)
        line(row, alpha: 0.85, indent: 16)
    }
    y += 6
    line("A closing paragraph near the bottom of a tall answer, where", alpha: 0.95)
    line("the old gradient had already faded to clear glass.", alpha: 0.95)
    // A widget card with its small label, low in the notch.
    y += 8
    fill(CGRect(x: cardX, y: y, width: cardW, height: 76), radius: 26, white: 0.06)
    text("To-dos", x: cardX + 18, y: y + 16, size: 15, weight: .semibold, alpha: 0.95)
    text("Reminders · 5", x: cardX + cardW - 18 - width("Reminders · 5", size: 12), y: y + 18, size: 12, alpha: 0.42)
    text("Call the dentist", x: cardX + 18, y: y + 44, size: 13, alpha: 0.92)
    y += 76 + 12
    var right = chip("Adding a to-do…", x: cardX + 8, y: y, fillAlpha: 0.13, textAlpha: 0.74)
    right = chip("Looked at the screen ✓", x: right + 6, y: y, fillAlpha: 0.06, textAlpha: 0.5)
    y += 28 + 8
    chip("✓ Added to your to-dos   ↩ Undo", x: cardX + 8, y: y, fillAlpha: 0.07, textAlpha: 0.62)
    y += 28 + 8
    text("Read more ›", x: x, y: y, size: 12.5, alpha: 0.5)
    // The composer: 38 tall, 8 above the bottom edge, with its hint and its key caps.
    let composer = CGRect(x: cardX, y: Notch.height - Notch.bottomInset - 38, width: cardW, height: 38)
    fill(composer, radius: 19, white: 0.06)
    let hint = GlassRGB(r: 236.0 / 255, g: 239.0 / 255, b: 247.0 / 255), hy = composer.minY + 9.5
    var hx = composer.minX + 16
    text("Type or hold", x: hx, y: hy, size: 15, color: hint, alpha: 0.62, tracking: 0.2)
    hx += width("Type or hold", size: 15) + 0.2 * 12 + 5
    for cap in ["option", "space"] {
        let w = width(cap, size: 10, weight: .semibold) + 12
        fill(CGRect(x: hx, y: hy + 2, width: w, height: 16), radius: 8, white: 0.12)
        text(cap, x: hx + 6, y: hy + 3.5, size: 10, weight: .semibold, alpha: 0.7)
        hx += w + 5
    }
    text("to speak", x: hx, y: hy, size: 15, color: hint, alpha: 0.62, tracking: 0.2)
}

func render(_ recipe: Recipe, over backdrop: Backdrop) {
    let scale = 2.0, size = Notch.canvas
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale), bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let bitmap = NSGraphicsContext(bitmapImageRep: rep) else { print("no bitmap for \(recipe.rawValue)"); return }
    let cg = bitmap.cgContext
    // y down from the top, in points, as the notch is laid out.
    cg.translateBy(x: 0, y: size.height * scale)
    cg.scaleBy(x: scale, y: -scale)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
    // The window behind, then the notch: its row of pixels at each height is what the recipe makes of that backdrop.
    for row in 0..<Int(size.height * scale) {
        let y = Double(row) / scale
        cg.setFillColor(backdrop.color(y).ns().cgColor)
        cg.fill(CGRect(x: 0, y: y, width: size.width, height: 1 / scale))
    }
    cg.saveGState()
    cg.addPath(notchPath())
    cg.clip()
    for row in 0..<Int(Notch.height * scale) {
        let y = Double(row) / scale
        cg.setFillColor(recipe.ground(at: y, backdrop: backdrop).ns().cgColor)
        cg.fill(CGRect(x: 0, y: y, width: size.width, height: 1 / scale))
    }
    drawContent()
    cg.restoreGState()
    NSGraphicsContext.current = nil
    let path = "\(outDir)/\(recipe.rawValue)-\(backdrop.file).png"
    guard let png = rep.representation(using: .png, properties: [:]) else { print("no png for \(path)"); return }
    do { try png.write(to: URL(fileURLWithPath: path)); print("wrote \(path)") } catch { print("could not write \(path): \(error)") }
}

for backdrop in backdrops {
    render(.before, over: backdrop)
    render(.after, over: backdrop)
}
render(.solid, over: backdrops[0])

// MARK: - The table

func ratio(_ value: Double) -> String { String(format: "%.1f", (value * 10).rounded(.down) / 10) }

let rows: [(String, Double)] = [("first line", Notch.firstLine), ("middle", Notch.height / 2), ("three quarters down", Notch.height * 0.75), ("last line", Notch.lastLine)]
for backdrop in backdrops {
    print("\n### Over a \(backdrop.name) (notch \(Int(Notch.height)) pt tall; first line at \(Int(Notch.firstLine)), middle at \(Int(Notch.height / 2)), three quarters at \(Int(Notch.height * 0.75)), last line ends at \(Int(Notch.lastLine)))\n")
    print("| Text | needs | before: first / middle / ¾ / last | after: first / middle / ¾ / last |")
    print("|---|---|---|---|")
    for style in glassTextStyles {
        func cells(_ recipe: Recipe) -> String {
            rows.map { row in
                let value = style.contrast(over: recipe.ground(at: row.1, backdrop: backdrop))
                return ratio(value) + (value < style.needs ? " ✗" : "")
            }.joined(separator: " / ")
        }
        print("| \(style.name) | \(style.needs):1 | \(cells(.before)) | \(cells(.after)) |")
    }
}
let failing = glassTextStyles.filter { style in
    rows.contains { style.contrast(over: Recipe.after.ground(at: $0.1, backdrop: backdrops[0])) < style.needs }
}
print(failing.isEmpty ? "\nAFTER: every style passes over white" : "\nAFTER FAILS: \(failing.map(\.name))")
