//
//  ArisAnswerLayout.swift
//  Aris
//
//  The open notch's answer, sized and faded: how tall the answer may grow before it scrolls, and which of its
//  edges fade. Pure, so the tests check them.
//

import CoreGraphics

/// The height budget. The surface goes to `min(visible height − 20, 710)`; the answer gets what's left after the
/// band and the chrome (`2 + 8 + prompt + footer + context + composer + 8·4`), never under 120. A written answer
/// stops at 360 and scrolls inside under its edge fades (`textMax`); cards keep their own limits.
enum ArisAnswerBudget {
    static let surfaceCap: CGFloat = 710
    static let screenMargin: CGFloat = 20
    static let band: CGFloat = 37
    static let minimum: CGFloat = 120
    static let widgetMax: CGFloat = 360
    /// The tallest a written answer is drawn before it scrolls: 360. A text answer gets `min(360, room)` (a card
    /// gets the whole room) and scrolls inside, with no scroll bar, under 22-point edge fades, so the open notch
    /// never grows past about 580 points however long the answer is.
    static let textMax: CGFloat = 360
    /// 2 under the band, 8 at the bottom, and four 8-point gaps.
    private static let insets: CGFloat = 2 + 8 + 8 * 4

    static func surfaceMax(visibleHeight: CGFloat) -> CGFloat {
        min(visibleHeight - screenMargin, surfaceCap)
    }

    static func answer(surfaceMax: CGFloat, band: CGFloat = band, prompt: CGFloat, footer: CGFloat = 0, context: CGFloat = 0,
                       composer: CGFloat, widget: Bool = false) -> CGFloat {
        let room = max(minimum, surfaceMax - band - (insets + prompt + footer + context + composer))
        return widget ? min(room, widgetMax) : room
    }
}

/// What the open notch around a turn takes up (everything but the prompt and the activity footer, which the turn
/// measures itself).
struct ArisAnswerRoom: Equatable {
    var surfaceMax = ArisAnswerBudget.surfaceCap
    var band = ArisAnswerBudget.band
    /// Rows between the turn and the composer (background work, a timer), with their gaps.
    var context: CGFloat = 0
    /// The composer's height, 0 while it's hidden.
    var composer: CGFloat = 0

    func answer(prompt: CGFloat, footer: CGFloat = 0) -> CGFloat {
        ArisAnswerBudget.answer(surfaceMax: surfaceMax, band: band, prompt: prompt, footer: footer, context: context, composer: composer)
    }

    /// A written answer's room: the same, never past 360 (ArisAnswerBudget.textMax); the rest scrolls.
    func text(prompt: CGFloat, footer: CGFloat = 0) -> CGFloat {
        min(ArisAnswerBudget.textMax, answer(prompt: prompt, footer: footer))
    }
}

/// Which edges of a scroller fade: none without overflow, the top once it's scrolled
/// more than a point, the bottom while there's more than a point below.
struct ArisScrollEdges: Equatable {
    var top = false
    var bottom = false

    /// The fade's length, absolute (not a share of the height).
    static let ramp: CGFloat = 22

    static func at(offset: CGFloat, visible: CGFloat, content: CGFloat) -> ArisScrollEdges {
        let overflow = content - 1 > visible
        return ArisScrollEdges(top: overflow && offset > 1, bottom: overflow && offset + visible < content - 1)
    }

    struct Stop: Equatable {
        let opaque: Bool
        let location: CGFloat
    }

    /// The mask's gradient stops, top to bottom, for a view `height` tall; empty means no mask.
    func stops(height: CGFloat) -> [Stop] {
        guard top || bottom else { return [] }
        let r = min(0.5, Self.ramp / max(height, 1))
        var stops = top ? [Stop(opaque: false, location: 0), Stop(opaque: true, location: r)] : [Stop(opaque: true, location: 0)]
        stops += bottom ? [Stop(opaque: true, location: 1 - r), Stop(opaque: false, location: 1)] : [Stop(opaque: true, location: 1)]
        return stops
    }
}

/// Tags laid out as a wrapping footer row (gap 6): each line holds what fits, a tag wider than the
/// line gets one to itself. Index ranges, one per line.
enum ArisFlowLines {
    static func lines(widths: [CGFloat], limit: CGFloat, spacing: CGFloat) -> [Range<Int>] {
        var lines: [Range<Int>] = []
        var start = 0
        var used: CGFloat = 0
        for (index, width) in widths.enumerated() {
            if index > start, used + spacing + width > limit {
                lines.append(start..<index)
                start = index
                used = width
            } else {
                used += (index > start ? spacing : 0) + width
            }
        }
        if start < widths.count { lines.append(start..<widths.count) }
        return lines
    }
}
