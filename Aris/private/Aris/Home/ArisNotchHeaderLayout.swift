//
//  ArisNotchHeaderLayout.swift
//  Aris
//
//  The arithmetic of the open notch's top band (ArisNotchHeader): how wide it is, and how the place icons (shelf,
//  Claude, settings) fit right of the camera housing.
//

import CoreGraphics

enum ArisNotchHeaderLayout {
    /// A 23-point control, 2 apart.
    static let slot: CGFloat = 23
    static let minSlot: CGFloat = 16
    static let spacing: CGFloat = 2
    /// The places' SF Symbols are 11 points.
    static let glyph: CGFloat = 11
    /// Shelf, Claude and settings (the music page went with the full player).
    static let placeCount = 3

    /// Only the sessions list takes the wider 540 page. Claude's done notice reads like an Aris answer on the 416
    /// page, so its header stays 416 too (a 540 header left the notice hugging the left of a too-wide notch).
    static func usesSessionsWidth(claudePage: Bool, showingNotice: Bool) -> Bool {
        claudePage && !showingNotice
    }

    /// One character on screen (ArisStarBand: one band, one star, whatever holds it). The closed band gives itself to
    /// Claude and its ghost when Claude holds it (mode nil), so the open sessions page, whose ghost leads its column,
    /// holds the open band the same way: the band's star steps aside there. The 416 notice has no ghost: the star stays.
    static func showsStar(claudePage: Bool, showingNotice: Bool) -> Bool {
        !usesSessionsWidth(claudePage: claudePage, showingNotice: showingNotice)
    }

    /// The band's mark (N7): where the star steps aside, a turn's voice bars and working dots still show (`voiceOrWork`:
    /// the glyph isn't the resting star); only the resting star hides.
    static func showsGlyph(showsStar: Bool, voiceOrWork: Bool) -> Bool { showsStar || voiceOrWork }

    struct Places: Equatable {
        let slot: CGFloat
        let spacing: CGFloat
        /// From the last slot to the header's edge.
        let trailing: CGFloat
        let width: CGFloat
    }

    /// All `count` places, settings included, as big as fit (up to 23 points, never under 16). The last glyph's edge
    /// sits on the text line, as the mark's does on the left, so a smaller slot gets a little more of the edge.
    static func places(count: Int, headerWidth: CGFloat, housing: CGFloat, textInset: CGFloat) -> Places {
        let n = CGFloat(max(1, count))
        let room = (headerWidth - housing) / 2 - textInset - glyph / 2 - (n - 1) * spacing
        let size = min(slot, max(minSlot, (room / (n - 0.5)).rounded(.down)))
        return Places(slot: size, spacing: spacing, trailing: textInset - (size - glyph) / 2,
                      width: n * size + (n - 1) * spacing)
    }
}
