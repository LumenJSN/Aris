//
//  ArisStripLayout.swift
//  Aris
//
//  Where the calendar strip's row sits, and how the wheel or a trackpad swipe steps it (QA BUG-57). The strip was a
//  SwiftUI ScrollView whose scroll position never reached the side panel: it opened with the chosen day at its left
//  edge, and a click on a day never got to the day's button. Now the row is plain, slid so the chosen day sits in the
//  middle; a tap picks the day, and the wheel or a sideways swipe steps one. Pure.
//

import CoreGraphics

enum ArisStripLayout {
    /// The row's x offset that puts day `index` (cells `cell` wide) in the middle of a strip `width` wide.
    static func offset(width: CGFloat, index: Int, cell: CGFloat) -> CGFloat {
        (width - cell) / 2 - CGFloat(index) * cell
    }

    /// How far the wheel or a swipe has to go for one day: a trackpad (precise) reports small deltas, a wheel's notch
    /// a big one.
    static func threshold(precise: Bool) -> CGFloat { precise ? 18 : 2 }

    /// A scroll of (`dx`, `dy`) added to `pending`: the pending amount left and the step it makes (-1 earlier,
    /// +1 later, nil not yet). The larger axis counts: the wheel down or a swipe to the left goes later.
    static func scrolled(pending: CGFloat, dx: CGFloat, dy: CGFloat, precise: Bool) -> (pending: CGFloat, step: Int?) {
        let delta = abs(dy) >= abs(dx) ? dy : dx
        let total = pending + delta
        guard abs(total) >= threshold(precise: precise) else { return (total, nil) }
        return (0, total > 0 ? -1 : 1)
    }

    /// `index` moved by `step`, kept on the strip's `count` days.
    static func stepped(_ index: Int, by step: Int, count: Int) -> Int {
        min(max(0, index + step), max(0, count - 1))
    }
}
