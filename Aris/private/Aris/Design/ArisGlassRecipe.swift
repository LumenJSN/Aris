//
//  ArisGlassRecipe.swift
//  Aris
//
//  How dark the open notch is at each height, as numbers. Over the glass lies a black gradient; it is what keeps the
//  words readable when a white window is behind the notch, so it is decided here and tested (tests/glass-tests.swift),
//  and the view only draws these stops.
//
//  The values: gradient colours sRGB(0,0,0,1), (0,0,0,1), (0,0,0,.5) at locations 0, .53, 1; glass tint
//  sRGB(0, 0, .02, .18). The plain gradient thins the black evenly from 53 % down to its half at the bottom edge
//  and counts on the glass material for the rest. Counting only on what Aris draws itself, that left dim text
//  (chips, the composer's hint, small labels) under 3:1 over a pure white window. So the black here never thins
//  under `textFloor` above the bottom inset, where the last line of anything ends, and thins to the half only inside
//  that inset: the notch keeps its light lower rim and every line above it keeps its contrast.
//
//  With macOS's Reduce Transparency the surfaces are solid and no glass is drawn. Foundation only (tested).
//

import Foundation

enum ArisGlassRecipe {
    /// The black is full from the top to 53 % of the notch's height.
    static let darkStop = 0.53
    /// The black at the very bottom edge.
    static let rimAlpha = 0.5
    /// The glass tint: sRGB(0, 0, .02) at .18.
    static let tintBlue = 0.02
    static let tintAlpha = 0.18
    /// Aris's own: the least black behind anything the notch shows. At .8 the dimmest text on the glass (white .42
    /// on a card's .06 fill) keeps 3:1 over pure white even if the glass's tint darkened nothing, and running text
    /// (white .65 and up) keeps 4.5:1.
    static let textFloor = 0.8
    /// The points at the bottom where the black thins from the floor to the rim: the open notch's bottom inset
    /// (ArisGlass.bottomInset), so nothing is ever drawn over it.
    static let rimBand = 8.0

    /// One stop of the gradient: how far down (0 at the top, 1 at the bottom) and how much black.
    struct Stop: Equatable {
        let location: Double
        let alpha: Double
    }

    /// The gradient of a notch `height` points tall. Always four stops, so closed, open and every height between
    /// slide into each other. `glass` false (Reduce Transparency) or closed: solid black all the way. `floor` is the
    /// least black behind the content (another look of ArisGlassLook may ask for a lighter one).
    static func stops(height: Double, open: Bool, glass: Bool, floor: Double = textFloor) -> [Stop] {
        guard open, glass else {
            return [Stop(location: 0, alpha: 1), Stop(location: 1, alpha: 1), Stop(location: 1, alpha: 1), Stop(location: 1, alpha: 1)]
        }
        let rimStart = height > 0 ? 1 - rimBand / height : 0
        // Too short for both the full part and the rim (only mid-way through opening): the plain fade.
        guard rimStart > darkStop else {
            return [Stop(location: 0, alpha: 1), Stop(location: darkStop, alpha: 1), Stop(location: darkStop, alpha: 1), Stop(location: 1, alpha: rimAlpha)]
        }
        return [Stop(location: 0, alpha: 1), Stop(location: darkStop, alpha: 1), Stop(location: rimStart, alpha: floor), Stop(location: 1, alpha: rimAlpha)]
    }

    /// How much black there is `y` points down a notch `height` tall: the stops above, read as the gradient draws them.
    static func alpha(at y: Double, height: Double, open: Bool = true, glass: Bool = true) -> Double {
        let all = stops(height: height, open: open, glass: glass)
        let t = height > 0 ? min(1, max(0, y / height)) : 0
        guard let next = all.firstIndex(where: { $0.location >= t }) else { return all.last?.alpha ?? 1 }
        guard next > 0 else { return all[0].alpha }
        let from = all[next - 1], to = all[next]
        guard to.location > from.location else { return to.alpha }
        return from.alpha + (to.alpha - from.alpha) * (t - from.location) / (to.location - from.location)
    }

    /// Whether the glass itself is drawn: only open, and never with Reduce Transparency.
    static func showsGlass(open: Bool, reduceTransparency: Bool) -> Bool { open && !reduceTransparency }

    /// The side panels' dark wash over their glass, rgba(0, 0, 6, .95), solid with Reduce Transparency.
    static func sideWash(reduceTransparency: Bool) -> Double { reduceTransparency ? 1 : 0.95 }

    /// The pill's and the bubble's dark fill, rgba(22,22,27,.96) to rgba(12,12,15,.96), solid with Reduce
    /// Transparency.
    static func pillFill(reduceTransparency: Bool) -> Double { reduceTransparency ? 1 : 0.96 }
}
