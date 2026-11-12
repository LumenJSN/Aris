//
//  ClaudeEarLayout.swift
//  Aris
//
//  The closed notch's Claude ears, pure. Left: the Claude Code teammate's character, 10 % under the band's old box
//  (band height − 8) and seated just low enough that a hop's peak (the working hops, a poke, an idle flip) never leaves
//  the band at its top, nor the fur its bottom on landing, whatever type the user picks. Right: the status ring and glyph,
//  12.5 % over the 20 points they had, to weigh as much as the character beside the camera.
//

import CoreGraphics

enum ClaudeEarLayout {
    /// Measured over every pickable type's idle loop (its poke included) and working loop, drawn as the baker draws
    /// them: the fur's highest reach above the box's top at a hop's peak (flower, mech and puddle: 0.327 of the box)
    /// and its lowest below the box's top (clover and square: 1.014).
    static let hopRise: CGFloat = 0.33
    static let reach: CGFloat = 1.02
    static let shrink: CGFloat = 0.9
    /// The ring and glyph on the right (the timer's ear keeps ClaudeEarGlyph.closedSize).
    static let glyphSize: CGFloat = 22.5

    /// The box the character had before: the band less 4 points above and below.
    static func fullSize(bandHeight: CGFloat) -> CGFloat { max(0, bandHeight - 8) }

    static func characterSize(bandHeight: CGFloat) -> CGFloat { fullSize(bandHeight: bandHeight) * shrink }

    /// Down from centred, just enough that the highest hop clears the band's top.
    static func drop(bandHeight: CGFloat) -> CGFloat {
        let size = characterSize(bandHeight: bandHeight)
        return max(0, hopRise * size - (bandHeight - size) / 2)
    }

    /// The top of the highest hop, from the band's top.
    static func peakTop(bandHeight: CGFloat) -> CGFloat {
        let size = characterSize(bandHeight: bandHeight)
        return (bandHeight - size) / 2 + drop(bandHeight: bandHeight) - hopRise * size
    }

    /// The lowest fur, from the band's top.
    static func lowest(bandHeight: CGFloat) -> CGFloat {
        let size = characterSize(bandHeight: bandHeight)
        return (bandHeight - size) / 2 + drop(bandHeight: bandHeight) + reach * size
    }
}
