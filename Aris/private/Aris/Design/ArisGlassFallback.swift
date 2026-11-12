//
//  ArisGlassFallback.swift
//  Aris
//
//  What the notch draws when this macOS lacks one of the private AppKit parts its shipped glass is made of. The
//  shipped look (ArisGlassLook.privateGlass) needs all of them; each can vanish in any macOS update. So each part is
//  asked for on its own (ArisGlassPrivate), and this file decides, part by part, what its absence means. The answer
//  is the same for every one of them: the notch looks like `clear-glass` (the same black over the public clear
//  glass), never a blank or a grey notch, and nothing private is left set. Why, per part:
//
//    the glass view   no NSGlassEffectView (before macOS 26): there is no AppKit glass to configure at all.
//    variant          without variant 11 the regular glass is a frosted charcoal that hides the screen.
//    lensing          without content lensing 3 the glass's edge does not bend the screen.
//    path             without `_setPath:` AppKit's glass cannot have the notch's outline.
//    active look      without the window's active appearance forced, the regular glass turns flat and grey whenever
//                     the notch's panel is not key, which is nearly always.
//
//  A missing part never turns the notch solid black: there is a public glass to fall back to, so the look stays.
//  Foundation only (tested).
//

import Foundation

/// Which private parts this macOS took. Each is true only after its own call was made and (where it can be read
/// back) held.
struct ArisGlassParts: Equatable {
    /// AppKit's glass view exists (macOS 26 and later).
    var glassView = false
    /// `set_variant:` 11.
    var variant = false
    /// `set_contentLensing:` 3.
    var lensing = false
    /// `_setPath:` with the notch's outline.
    var path = false
    /// The window's active appearance forced on (`_hasActiveAppearance`, `_setHasActiveAppearance:`).
    var activeAppearance = false

    static let all = ArisGlassParts(glassView: true, variant: true, lensing: true, path: true, activeAppearance: true)
    static let none = ArisGlassParts()

    /// The parts that did not take, by the names the log uses.
    var missing: [String] {
        [(glassView, "glass view"), (variant, "variant"), (lensing, "lensing"), (path, "path"), (activeAppearance, "active appearance")]
            .filter { !$0.0 }.map(\.1)
    }
}

enum ArisGlassFallback {
    struct Decision: Equatable {
        /// AppKit's glass with the private settings is drawn (every part took).
        var privateGlass: Bool
        /// The panel's active appearance is forced: only together with the private glass, never left on without it.
        var forcesActiveAppearance: Bool
        /// The look the notch has.
        var look: ArisGlassLook
        /// The parts that are missing (empty when the private glass is drawn).
        var missing: [String]
    }

    /// What `private-glass` draws with these parts: the private glass only when none is missing.
    static func decide(_ parts: ArisGlassParts) -> Decision {
        let complete = parts.missing.isEmpty
        return Decision(privateGlass: complete, forcesActiveAppearance: complete,
                        look: complete ? .privateGlass : .clearGlass, missing: parts.missing)
    }

    /// The one line the log gets, the first time the look is decided and again only if a part later fails.
    static func logLine(_ parts: ArisGlassParts) -> String {
        let took = "variant \(parts.variant) lensing \(parts.lensing) path \(parts.path) active appearance \(parts.activeAppearance)"
        let decision = decide(parts)
        return decision.privateGlass
            ? "private-glass: \(took): AppKit glass with its private settings"
            : "private-glass: \(took): missing \(decision.missing.joined(separator: ", ")), so the notch draws clear-glass"
    }
}
