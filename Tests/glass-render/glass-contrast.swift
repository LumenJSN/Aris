// The contrast arithmetic for the open notch's glass, shared by tests/glass-tests.swift and the off-screen renders
// (glass-render/main.swift). The model: whatever is behind the notch comes through the glass as its average colour
// (the system's blur is treated as passing it through unchanged), the glass's tint darkens it, the black gradient
// (ArisGlassRecipe) darkens it again, a control's own white fill lightens it, and the text is composited on top.
// Contrast is WCAG 2's: (L1 + 0.05) / (L2 + 0.05) on relative luminance. Foundation only.
import Foundation

struct GlassRGB: Equatable {
    var r: Double, g: Double, b: Double

    static let white = GlassRGB(r: 1, g: 1, b: 1)
    static let black = GlassRGB(r: 0, g: 0, b: 0)
    static func grey(_ v: Double) -> GlassRGB { GlassRGB(r: v, g: v, b: v) }

    /// `self` at `alpha` over `under`, in sRGB as Core Animation composites.
    func over(_ under: GlassRGB, alpha: Double) -> GlassRGB {
        GlassRGB(r: r * alpha + under.r * (1 - alpha), g: g * alpha + under.g * (1 - alpha), b: b * alpha + under.b * (1 - alpha))
    }

    /// WCAG relative luminance.
    var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
}

func glassContrast(_ a: GlassRGB, _ b: GlassRGB) -> Double {
    let high = max(a.luminance, b.luminance), low = min(a.luminance, b.luminance)
    return (high + 0.05) / (low + 0.05)
}

/// One kind of text that sits straight on the notch's glass (not on a card with a surface of its own).
struct GlassTextStyle {
    let name: String
    let color: GlassRGB
    let alpha: Double
    /// The white fills between the glass and the text, bottom first (a chip's, the composer's and a key cap's).
    let fills: [Double]
    /// 4.5 for running text, 3 for large or secondary text.
    let needs: Double
    /// Where the colour is written, and the words that write it: the tests read the file so the table follows the code.
    let file: String
    let needle: String

    /// The contrast of this text over `behind` (the glass and its black, before this style's own fills).
    func contrast(over behind: GlassRGB) -> Double {
        let ground = fills.reduce(behind) { GlassRGB.white.over($0, alpha: $1) }
        return glassContrast(color.over(ground, alpha: alpha), ground)
    }
}

private let glassHome = "Aris/private/Aris/Home/"
let glassTextStyles: [GlassTextStyle] = [
    .init(name: "answer paragraph (15 pt, white .95)", color: .white, alpha: 0.95, fills: [], needs: 4.5,
          file: glassHome + "ArisAnswerAttributed.swift", needle: "inline(words, font: base, color: white(0.95))"),
    .init(name: "answer list line (white .85)", color: .white, alpha: 0.85, fills: [], needs: 4.5,
          file: glassHome + "ArisAnswerAttributed.swift", needle: "inline(item.text, font: base, color: white(0.85))"),
    .init(name: "answer quote (white .65)", color: .white, alpha: 0.65, fills: [], needs: 4.5,
          file: glassHome + "ArisAnswerAttributed.swift", needle: "inline(words, font: base, color: white(0.65))"),
    .init(name: "typed words in the composer (white .95 on .06)", color: .white, alpha: 0.95, fills: [0.06], needs: 4.5,
          file: glassHome + "ArisComposer.swift", needle: ".foregroundStyle(.white.opacity(0.95))"),
    .init(name: "composer hint (236,239,247 at .62 on .06)", color: GlassRGB(r: 236.0 / 255, g: 239.0 / 255, b: 247.0 / 255), alpha: 0.62, fills: [0.06], needs: 3,
          file: glassHome + "ArisComposer.swift", needle: "Color(red: 236 / 255, green: 239 / 255, blue: 247 / 255).opacity(0.62)"),
    .init(name: "key cap in the hint (white .7 on .12 on .06)", color: .white, alpha: 0.7, fills: [0.06, 0.12], needs: 3,
          file: "Aris/private/Aris/Design/ArisGlass.swift", needle: ".foregroundStyle(.white.opacity(0.7))"),
    .init(name: "working tag (white .74 on .13)", color: .white, alpha: 0.74, fills: [0.13], needs: 3,
          file: glassHome + "ArisActivityTag.swift", needle: ".foregroundStyle(.white.opacity(settled ? 0.5 : 0.74))"),
    .init(name: "finished tag (white .5 on .06)", color: .white, alpha: 0.5, fills: [0.06], needs: 3,
          file: glassHome + "ArisActivityTag.swift", needle: "static let doneFill = 0.06"),
    .init(name: "receipt chip (white .62 on .07)", color: .white, alpha: 0.62, fills: [0.07], needs: 3,
          file: glassHome + "ArisReceiptChip.swift", needle: ".foregroundStyle(.white.opacity(hovering ? 0.82 : 0.62))"),
    .init(name: "“Read more” (12.5 pt, white .5)", color: .white, alpha: 0.5, fills: [], needs: 3,
          file: glassHome + "ArisOpenAnswerButton.swift", needle: ".foregroundStyle(.white.opacity(hovering ? 0.78 : 0.5))"),
    .init(name: "shelf chip label (white .5 on .08)", color: .white, alpha: 0.5, fills: [0.08], needs: 3,
          file: "Aris/private/Aris/Design/ArisGlass.swift", needle: "static let secondaryText = Color.white.opacity(0.5)"),
    .init(name: "widget card's small label (white .42 on .06)", color: .white, alpha: 0.42, fills: [0.06], needs: 3,
          file: glassHome + "ArisWidgetCards.swift", needle: "static let ink42 = Color.white.opacity(0.42)"),
]

/// What is behind the text at one height of the notch: the backdrop through the glass's tint, then the black.
/// `tint`: the glass's own (sRGB(0, 0, .02, .18)); nil counts the glass as adding nothing.
func glassBehind(backdrop: GlassRGB, tint: (color: GlassRGB, alpha: Double)?, black: GlassRGB, blackAlpha: Double) -> GlassRGB {
    let tinted = tint.map { $0.color.over(backdrop, alpha: $0.alpha) } ?? backdrop
    return black.over(tinted, alpha: blackAlpha)
}

/// The gradient as it was before 2026-11-11 (ArisGlass.swift at 42394215): rgba(0, 0, 2, .98) to 48 % of the height,
/// then to nothing at the bottom.
enum GlassRecipeBefore {
    static let color = GlassRGB(r: 0, g: 0, b: 2.0 / 255)
    static let tint = (color: GlassRGB(r: 0, g: 0, b: 5.0 / 255), alpha: 0.18)
    static func alpha(at y: Double, height: Double) -> Double {
        let t = height > 0 ? min(1, max(0, y / height)) : 0
        return t <= 0.48 ? 0.98 : 0.98 * (1 - (t - 0.48) / 0.52)
    }
}
