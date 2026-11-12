//
//  ArisGlassLook.swift
//  Aris
//
//  The notch's glass as one of six looks. What ships is `private-glass`: the user compared the six on a screen and
//  chose it (2026-11-11). The others stay behind a hidden preference:
//  `defaults write com.lumenjsn.aris arisGlassLook <name>`, then open the notch again (it is read each time the notch
//  opens). There is no switch for it anywhere in the app; unset, or no look's name, means `private-glass`.
//
//    private-glass    the shipped notch: AppKit's `NSGlassEffectView` in its regular style with the notch's tint and
//                     private AppKit settings on it (ArisGlassPrivate), under the deep black (full to 53 %, half at
//                     the end, spanning max(height, safe-area top / 0.53)). The glass is there in every state but
//                     hidden. Where this macOS lacks any private part, the notch draws `clear-glass` instead
//                     (ArisGlassFallback).
//    clear-glass      the same black and span over the public clear glass: the nearest to private-glass that
//                     public API gives, and what private-glass falls back to.
//    regular-glass    the public regular glass with the same tint and black: a frosted charcoal, for comparison.
//    floor            what Aris shipped before: clear glass, the deep black never under 80 % behind the content.
//    mid              the same with a lighter floor, 60 %.
//    before           what Aris drew until 2026-11-11: black to 48 %, then fading to nothing; for comparison only.
//
//  The numbers: tint sRGB(0, 0, .02, .18), variant 11 and content lensing 3 (ArisGlassPrivate), and the black
//  1, 1, .5 at 0, .53, 1 over max(height, safe-area top / 0.53). Foundation only (tested).
//

import Foundation

enum ArisGlassLook: String, CaseIterable, Equatable {
    case floor
    case before
    case regularGlass = "regular-glass"
    case privateGlass = "private-glass"
    case clearGlass = "clear-glass"
    case mid

    /// The hidden preference's name in Aris's own defaults.
    static let preferenceKey = "arisGlassLook"
    /// What the notch draws when the preference is missing or is no look's name: what ships.
    static let fallback = ArisGlassLook.privateGlass

    /// The private glass settings: `set_variant:` 11 and `_contentLensing` 3.
    static let privateVariant = 11
    static let privateContentLensing = 3
    /// Aris's lighter floor for `mid`.
    static let midFloor = 0.6
    /// `before`: Aris's old solid, rgba(0, 0, 2, .98) to 48 % of the height, and its tint's blue, 5 / 255.
    static let beforeStop = 0.48
    static let beforeAlpha = 0.98
    static let beforeBlue = 2.0 / 255
    static let beforeTintBlue = 5.0 / 255

    /// A look from what the preference holds: its name in any letter case, spaces around it ignored.
    init(preference: String?) {
        let name = preference?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        self = ArisGlassLook(rawValue: name) ?? Self.fallback
    }

    /// The look to draw now, read from the preference (called as the notch opens).
    static func current(_ defaults: UserDefaults = .standard) -> ArisGlassLook {
        ArisGlassLook(preference: defaults.string(forKey: preferenceKey))
    }

    /// Whether the glass is AppKit's regular material, not the public clear one.
    var regularMaterial: Bool { self == .regularGlass || self == .privateGlass }

    /// Whether the private AppKit calls are made too. Only ever for `private-glass`.
    var usesPrivateParts: Bool { self == .privateGlass }

    /// The look that is really drawn on this macOS: `private-glass` only while every private part it needs took
    /// (ArisGlassFallback), else `clear-glass`; any other look is itself.
    func resolved(_ parts: ArisGlassParts) -> ArisGlassLook {
        self == .privateGlass && !ArisGlassFallback.decide(parts).privateGlass ? .clearGlass : self
    }

    /// Whether the glass itself is drawn. The deep-black looks: in every state except hidden (closed too: over a
    /// camera housing the full black covers it, see `span`); `hidden` is a closed notch put away for a full-screen
    /// app, and an open notch is never hidden. The others: only open. Never with Reduce Transparency.
    func showsGlass(open: Bool, hidden: Bool, reduceTransparency: Bool) -> Bool {
        deepBlack ? (open || !hidden) && !reduceTransparency : ArisGlassRecipe.showsGlass(open: open, reduceTransparency: reduceTransparency)
    }

    /// The blue of the black drawn over the glass (red and green are 0).
    var blackBlue: Double { self == .before ? Self.beforeBlue : 0 }

    /// The glass's tint: sRGB(0, 0, blue) at .18.
    var tintBlue: Double { self == .before ? Self.beforeTintBlue : ArisGlassRecipe.tintBlue }
    var tintAlpha: Double { ArisGlassRecipe.tintAlpha }

    /// Whether the black over the glass is the deep black: full to 53 %, half at the end, with no floor.
    var deepBlack: Bool { self == .regularGlass || self == .privateGlass || self == .clearGlass }

    /// How many points the black's gradient runs over, from the notch's top. The deep-black looks: at least the
    /// display's safe-area top / 0.53, so the full black always covers the camera housing. The others: the notch's
    /// height.
    func span(height: Double, safeTop: Double = 0) -> Double {
        deepBlack ? max(height, safeTop / ArisGlassRecipe.darkStop) : height
    }

    /// The black's stops along its span (0 at the notch's top, 1 at the span's end). Always four, so closed, open
    /// and every look slide into each other. `glass` false (Reduce Transparency): solid all the way. Closed: solid
    /// for `floor`, `mid` and `before`; the deep-black looks keep their one gradient in every state (the span is what
    /// makes a closed notch solid over a camera housing).
    func stops(height: Double, safeTop: Double = 0, open: Bool, glass: Bool) -> [ArisGlassRecipe.Stop] {
        typealias Stop = ArisGlassRecipe.Stop
        switch self {
        case .floor:
            return ArisGlassRecipe.stops(height: height, open: open, glass: glass)
        case .mid:
            return ArisGlassRecipe.stops(height: height, open: open, glass: glass, floor: Self.midFloor)
        case .before:
            let solid = glass ? Self.beforeAlpha : 1
            guard open, glass else {
                return [Stop(location: 0, alpha: solid), Stop(location: 1, alpha: solid), Stop(location: 1, alpha: solid), Stop(location: 1, alpha: solid)]
            }
            return [Stop(location: 0, alpha: solid), Stop(location: Self.beforeStop, alpha: solid),
                    Stop(location: Self.beforeStop, alpha: solid), Stop(location: 1, alpha: 0)]
        case .regularGlass, .privateGlass, .clearGlass:
            guard glass else { return ArisGlassRecipe.stops(height: height, open: false, glass: false) }
            let stop = ArisGlassRecipe.darkStop
            return [Stop(location: 0, alpha: 1), Stop(location: stop, alpha: 1), Stop(location: stop, alpha: 1),
                    Stop(location: 1, alpha: ArisGlassRecipe.rimAlpha)]
        }
    }

    /// How much black there is `y` points down an open notch `height` tall.
    func alpha(at y: Double, height: Double, safeTop: Double = 0, open: Bool = true, glass: Bool = true) -> Double {
        let all = stops(height: height, safeTop: safeTop, open: open, glass: glass)
        let along = span(height: height, safeTop: safeTop)
        let t = along > 0 ? min(1, max(0, y / along)) : 0
        guard let next = all.firstIndex(where: { $0.location >= t }) else { return all.last?.alpha ?? 1 }
        guard next > 0 else { return all[0].alpha }
        let from = all[next - 1], to = all[next]
        guard to.location > from.location else { return to.alpha }
        return from.alpha + (to.alpha - from.alpha) * (t - from.location) / (to.location - from.location)
    }
}
