//
//  ArisNoticeLayout.swift
//  Aris
//
//  Where the cards go and how big each is, with the measured numbers: a card 345 wide, 64, 80 or 96 high by its text,
//  radius 22, padding 13; its window 14 around (the close button's overhang) and 22 below (the shadow), its top 50
//  under the work area's top, centred on the notch's display. Behind the front card at most 2 others peek out 9 below
//  it, 13 in from each side per layer (only their bottom band shows). Expanded, up to 5 stand one under the other 8
//  apart, then a "+N" row 26 high. Everything is in the cards' own space: x from the cards' left edge, y down from
//  the front card's top. CoreGraphics only (tested).
//

import CoreGraphics
import Foundation

enum ArisNoticeLayout {
    // MARK: The card

    static let width: CGFloat = 345
    static let compactHeight: CGFloat = 64
    static let mediumHeight: CGFloat = 80
    static let largeHeight: CGFloat = 96
    static let cornerRadius: CGFloat = 22
    static let padding: CGFloat = 13
    /// Between the tile and the text.
    static let gap: CGFloat = 10
    static let tileSize: CGFloat = 30

    // MARK: Text (points, line heights, white opacities)

    static let titleSize: CGFloat = 13
    static let titleLine: CGFloat = 17
    /// -0.01 em.
    static let titleTracking: CGFloat = -0.13
    static let titleOpacity = 0.96
    static let bodySize: CGFloat = 12.5
    static let bodyLine: CGFloat = 16.5
    static let bodyOpacity = 0.7
    /// An incoming card's second line.
    static let subtitleSize: CGFloat = 12.5
    static let subtitleLine: CGFloat = 16
    static let subtitleOpacity = 0.85
    /// An incoming card's snippet: 2 lines at most.
    static let snippetSize: CGFloat = 12
    static let snippetLine: CGFloat = 16
    static let snippetOpacity = 0.55
    /// Above the body (2) and above the subtitle (1).
    static let bodyTop: CGFloat = 2
    static let subtitleTop: CGFloat = 1

    /// How the height is told from the text: the content's room in a compact and a medium card, and how many
    /// narrow characters fill a line (a wide one, such as Hangul, counts as two).
    static let contentSmall: CGFloat = 38
    static let contentMedium: CGFloat = 54
    static let charactersPerLine = 42

    // MARK: Buttons and close

    static let buttonHeight: CGFloat = 22
    static let buttonMinWidth: CGFloat = 52
    static let buttonPadding: CGFloat = 11
    static let buttonTextSize: CGFloat = 11
    static let buttonGap: CGFloat = 5
    /// The buttons sit 8 above the card's bottom and 10 in from its right.
    static let buttonsBottom: CGFloat = 8
    static let buttonsRight: CGFloat = 10
    static let pressScale: CGFloat = 0.97
    static let hoverBrightness = 0.1
    static let pressBrightness = -0.08
    /// #0A84FF and #3A3A40.
    static let primaryColor: UInt32 = 0x0A84FF
    static let secondaryColor: UInt32 = 0x3A3A40
    static let closeSize: CGFloat = 24
    /// The close circle straddles the top-left corner: a quarter of it outside on each side.
    static let closeOut: CGFloat = closeSize / 4
    /// The close circle while hidden.
    static let closeHiddenScale: CGFloat = 0.8

    // MARK: Motion (seconds)

    /// Cards move and the stack opens in 220 ms on (0.22, 1, 0.36, 1).
    static let motion: Double = 0.22
    static let motionCurve: (Double, Double, Double, Double) = (0.22, 1, 0.36, 1)
    /// Buttons and the close circle appear in 140 ms (rising 4 points); a new card fades in over 180 ms.
    static let reveal: Double = 0.14
    static let revealRise: CGFloat = 4
    static let fadeIn: Double = 0.18
    /// Buttons react in 120 ms.
    static let press: Double = 0.12

    // MARK: The stack

    static let stackMaxLayers = 2
    static let stackInset: CGFloat = 13
    static let stackOffset: CGFloat = 9
    static let expandedGap: CGFloat = 8
    static let expandedMax = 5
    static let moreRowHeight: CGFloat = 26

    // MARK: The window

    /// Around the cards for the close circle; below them for the shadow.
    static let closeOverhang: CGFloat = 14
    static let shadowMargin: CGFloat = 22
    /// The front card's top under the top of the display's work area (below the menu bar).
    static let topBelowWorkArea: CGFloat = 50

    /// Room for the tallest expanded stack: 5 large cards, their gaps and the "+N" row.
    static var tallestStack: CGFloat { CGFloat(expandedMax) * largeHeight + CGFloat(expandedMax - 1) * expandedGap + moreRowHeight }

    static var windowSize: CGSize {
        CGSize(width: width + 2 * closeOverhang, height: closeOverhang + tallestStack + shadowMargin)
    }

    /// The window's frame on a display whose work area (AppKit's visible frame, y up) is `workArea`: centred, its
    /// cards' top 50 under the work area's top.
    static func windowFrame(workArea: CGRect) -> CGRect {
        let size = windowSize
        let top = workArea.maxY - topBelowWorkArea + closeOverhang
        return CGRect(x: (workArea.midX - size.width / 2).rounded(), y: top - size.height, width: size.width, height: size.height)
    }

    /// Where the cards' space starts in the window, in the window's own coordinates with y down.
    static let cardsOrigin = CGPoint(x: closeOverhang, y: closeOverhang)

    // MARK: Heights

    /// A line's worth of text: a wide character (CJK, Hangul, full-width) counts as two narrow ones.
    static func units(_ text: String) -> Int {
        text.unicodeScalars.reduce(0) { $0 + (isWide($1) ? 2 : 1) }
    }

    private static func isWide(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x11FF, 0x2E80...0x9FFF, 0xA960...0xA97F, 0xAC00...0xD7FF, 0xF900...0xFAFF, 0xFE30...0xFE4F, 0xFF00...0xFF60,
             0xFFE0...0xFFE6, 0x1F300...0x1FAFF, 0x20000...0x3FFFD: true
        default: false
        }
    }

    /// How many lines a body may take: 3 once it would fill more than two, else 2.
    static func bodyLines(_ body: String) -> Int { units(body) > charactersPerLine * 2 ? 3 : 2 }

    /// The snippet's lines: 2 when it runs past one line or breaks, 1, or 0 without one.
    static func snippetLines(_ snippet: String) -> Int {
        guard !snippet.isEmpty else { return 0 }
        return units(snippet) > charactersPerLine || snippet.contains(where: \.isNewline) ? 2 : 1
    }

    /// The card's height, from its text.
    static func height(_ notice: ArisNotice) -> CGFloat {
        if notice.kind == .incoming {
            let snippet = snippetLines(notice.body)
            let content = titleLine + (notice.subtitle?.isEmpty == false ? subtitleTop + subtitleLine : 0)
                + (snippet > 0 ? bodyTop + snippetLine * CGFloat(snippet) : 0)
            if content <= contentSmall { return compactHeight }
            return content <= contentMedium ? mediumHeight : largeHeight
        }
        if bodyLines(notice.body) == 3 { return largeHeight }
        return units(notice.body) > charactersPerLine ? mediumHeight : compactHeight
    }

    // MARK: The stack

    /// What is drawn for `heights` (the shown cards, newest first) collapsed or expanded.
    static func stack(_ heights: [CGFloat], expanded: Bool) -> ArisNoticeStack {
        guard let front = heights.first else { return ArisNoticeStack(cards: [], layers: [], hidden: 0, moreRow: nil, height: 0) }
        guard expanded, heights.count > 1 else {
            let layers = layerCount(heights.count)
            let bands = (1...max(1, layers)).prefix(layers).map { depth -> CGRect in
                let inset = CGFloat(depth) * stackInset
                // The layer has the front card's size, pushed down; only its last 9 points show under the one above.
                return CGRect(x: inset, y: front + CGFloat(depth - 1) * stackOffset, width: width - 2 * inset, height: stackOffset)
            }
            let cards = [CGRect(x: 0, y: 0, width: width, height: front)]
            return ArisNoticeStack(cards: cards, layers: bands, hidden: 0, moreRow: nil, height: front + CGFloat(layers) * stackOffset)
        }
        var y: CGFloat = 0
        var cards: [CGRect] = []
        for height in heights.prefix(expandedMax) {
            if !cards.isEmpty { y += expandedGap }
            cards.append(CGRect(x: 0, y: y, width: width, height: height))
            y += height
        }
        let hidden = max(0, heights.count - expandedMax)
        let more = hidden > 0 ? CGRect(x: 0, y: y + expandedGap, width: width, height: moreRowHeight) : nil
        return ArisNoticeStack(cards: cards, layers: [], hidden: hidden, moreRow: more, height: more?.maxY ?? y)
    }

    /// The layers peeking under the front card, for `count` cards shown.
    static func layerCount(_ count: Int) -> Int { max(0, min(stackMaxLayers, count - 1)) }

    /// Where the pointer is the cards' own (clicks there are the panel's; everywhere else they pass through): each
    /// card with its close circle's corner, the bands of the layers, the "+N" row.
    static func hitRects(_ stack: ArisNoticeStack) -> [CGRect] {
        let cards = stack.cards.map { CGRect(x: $0.minX - closeOut, y: $0.minY - closeOut, width: $0.width + closeOut, height: $0.height + closeOut) }
        return cards + stack.layers + (stack.moreRow.map { [$0] } ?? [])
    }
}

/// The cards' frames, the peeking layers' visible bands and the "+N" row, in the cards' space (y down).
struct ArisNoticeStack: Equatable {
    /// One frame per card drawn in full: the front one alone collapsed, up to 5 expanded.
    let cards: [CGRect]
    /// The visible band of each layer behind the front card, nearest first.
    let layers: [CGRect]
    /// Cards left out of the expanded list ("+N").
    let hidden: Int
    let moreRow: CGRect?
    /// From the front card's top to the bottom of what is drawn.
    let height: CGFloat
}

/// What a card's surface is drawn with. A peeking layer behind the front card is never AppKit's glass: a glass view
/// under a mask, behind another glass card, samples that card's glass and draws a black band in Light (seventh VM
/// pass). It takes the solid colours of its appearance instead (the glass card's Reduce Transparency fill), so it
/// matches the front card in Light and in Dark.
enum ArisNoticeFill: Equatable {
    /// AppKit's glass with the thin skin over it.
    case glass
    /// The appearance's solid colour.
    case solid
    /// The opaque card's dark gradient.
    case gradient

    static func of(glassMaterial: Bool, reduceTransparency: Bool, layer: Bool) -> ArisNoticeFill {
        guard glassMaterial else { return .gradient }
        return reduceTransparency || layer ? .solid : .glass
    }
}
