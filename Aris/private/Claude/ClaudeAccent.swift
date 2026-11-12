//
//  ClaudeAccent.swift
//  Aris
//
//  The Claude card's and ears' accent, pure (no SwiftUI, so the tests build it): the colour of the Claude Code
//  teammate's character (picked in 팀원, else its type's own), lifted toward white until it reads on the notch's dark
//  glass. The colours that mean something stay fixed (mockups/clawd-replace.html, pick C): approval yellow, done green,
//  error red; an accent too near one of them gives way to the glass's own white, so a state never reads as another.
//

import Foundation

/// An sRGB colour, components 0 … 1.
struct ClaudeRGBA: Equatable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    func opacity(_ alpha: Double) -> ClaudeRGBA { ClaudeRGBA(r: r, g: g, b: b, a: alpha) }
}

enum ClaudeAccent {
    /// The mockup's fixed meaning colours.
    static let approval = ClaudeRGBA(r: 0xF4 / 255.0, g: 0xC6 / 255.0, b: 0x4E / 255.0, a: 1)
    static let done = ClaudeRGBA(r: 0x4A / 255.0, g: 0xDE / 255.0, b: 0x80 / 255.0, a: 1)
    static let error = ClaudeRGBA(r: 0xF1 / 255.0, g: 0x6C / 255.0, b: 0x70 / 255.0, a: 1)
    /// The resting moon in the right ear.
    static let moon = ClaudeRGBA(r: 0xF5 / 255.0, g: 0xD9 / 255.0, b: 0x8C / 255.0, a: 1)
    /// The glass's own white (pick A's accent): what an accent that would read as a meaning colour becomes.
    static let neutral = ClaudeRGBA(r: 1, g: 1, b: 1, a: 0.86)
    /// The card's surface (white 0.06 over the notch's black): the darkest the accent sits on.
    static let glass = ClaudeRGBA(r: 0.06, g: 0.06, b: 0.06, a: 1)
    /// WCAG AA for text: the tool glyph and the chips' dots are small, so the text bar rather than 3:1.
    static let minContrast = 4.5
    /// The ghost's own white, for a type the list doesn't know.
    static let fallbackHex = "#F4F2FA"
    /// Nearer than this in hue (degrees) to a meaning colour, and coloured enough to show a hue, clashes.
    static let clashDegrees = 18.0
    static let clashSaturation = 0.25
    /// Each lift toward white.
    private static let liftStep = 0.02

    /// The accent and its weaker uses: the panel's lit hairline, its wash at work, the glow behind the character at
    /// work, the usage tab.
    struct Palette: Equatable {
        let accent: ClaudeRGBA
        let rim: ClaudeRGBA
        let wash: ClaudeRGBA
        let glow: ClaudeRGBA
        let tab: ClaudeRGBA
    }

    /// The Claude Code teammate's look: by id, the ghost until the list is in.
    static func look(in team: [ArisTeammate]) -> ArisCharacterLook {
        .of(teammateId: ArisTeammate.claudeCodeId, name: ArisTeammate.claudeCode.name, in: team)
    }

    /// The colour the character is drawn in: the one picked, else its type's own.
    static func sourceHex(of look: ArisCharacterLook) -> String {
        look.colorHex ?? ArisCharacterLook.ownColors[look.type] ?? fallbackHex
    }

    static func accent(for look: ArisCharacterLook) -> ClaudeRGBA {
        guard let colour = parse(sourceHex(of: look)), !clashes(colour) else { return neutral }
        return readable(colour)
    }

    static func palette(for look: ArisCharacterLook) -> Palette {
        let accent = accent(for: look)
        if accent == neutral {
            let white = ClaudeRGBA(r: 1, g: 1, b: 1, a: 0)
            return Palette(accent: accent, rim: white.opacity(0.1), wash: white, glow: white, tab: white.opacity(0.12))
        }
        return Palette(accent: accent, rim: accent.opacity(0.24), wash: accent.opacity(0.06), glow: accent.opacity(0.16), tab: accent.opacity(0.18))
    }

    /// "#RRGGBB" only.
    static func parse(_ hex: String) -> ClaudeRGBA? {
        guard hex.count == 7, hex.first == "#", let n = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return ClaudeRGBA(r: Double(n >> 16 & 0xFF) / 255, g: Double(n >> 8 & 0xFF) / 255, b: Double(n & 0xFF) / 255, a: 1)
    }

    /// The colour mixed toward white, a step at a time, until it reads on the glass.
    static func readable(_ colour: ClaudeRGBA) -> ClaudeRGBA {
        var t = 0.0, out = colour
        while contrast(out, glass) < minContrast && t < 1 {
            t = min(1, t + liftStep)
            out = ClaudeRGBA(r: colour.r + (1 - colour.r) * t, g: colour.g + (1 - colour.g) * t, b: colour.b + (1 - colour.b) * t, a: colour.a)
        }
        return out
    }

    /// Too near approval, done or error in hue to tell apart at a glance.
    static func clashes(_ colour: ClaudeRGBA) -> Bool {
        let (hue, saturation) = hueSaturation(colour)
        guard saturation >= clashSaturation else { return false }
        return [approval, done, error].contains { meaning in
            let d = abs(hue - hueSaturation(meaning).hue).truncatingRemainder(dividingBy: 360)
            return min(d, 360 - d) < clashDegrees
        }
    }

    /// WCAG relative-luminance contrast ratio, 1 … 21.
    static func contrast(_ a: ClaudeRGBA, _ b: ClaudeRGBA) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    static func luminance(_ c: ClaudeRGBA) -> Double {
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }

    /// HSV hue in degrees (0 ..< 360) and saturation (0 … 1).
    private static func hueSaturation(_ c: ClaudeRGBA) -> (hue: Double, saturation: Double) {
        let top = max(c.r, c.g, c.b), bottom = min(c.r, c.g, c.b), d = top - bottom
        guard d > 0 else { return (0, 0) }
        let h: Double
        if top == c.r { h = ((c.g - c.b) / d).truncatingRemainder(dividingBy: 6) }
        else if top == c.g { h = (c.b - c.r) / d + 2 }
        else { h = (c.r - c.g) / d + 4 }
        let degrees = 60 * h
        return (degrees < 0 ? degrees + 360 : degrees, d / top)
    }
}
