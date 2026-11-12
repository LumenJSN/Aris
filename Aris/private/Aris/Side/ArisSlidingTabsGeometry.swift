//
//  ArisSlidingTabsGeometry.swift
//  Aris
//
//  The sliding tabs' layout as a function of one weight per tab (how selected it is; one-hot at rest). A move is
//  the weights blending from one tab to another, so a jump leaves the tabs in between alone and a move
//  interrupted halfway carries on from wherever the weights are. The highlight is a pill as wide as the selected
//  tab, at the weighted average of the tabs' starts. The unselected tabs are icons, so they give way to a long name:
//  each tab says how wide the others may be while it is selected (`unselectedWidth`, from its measured label), and
//  the row blends those widths with the same weights.
//

import CoreGraphics

enum ArisSlidingTabsGeometry {
    struct Frames: Equatable {
        /// Each tab's width.
        var tabWidths: [CGFloat]
        /// How selected each tab is, 0…1 (the weights, normalised).
        var selectedness: [Double]
        var indicatorX: CGFloat
        var indicatorWidth: CGFloat
        /// Each tab's left edge as laid out (on the grid), and before rounding (where icons are placed from).
        var starts: [CGFloat] = []
        var exactStarts: [CGFloat] = []
        /// An unselected tab's width as laid out (it narrows while a tab with a long label is selected).
        var unselected: CGFloat = 0
    }

    /// The narrowest an unselected tab gets: its icon and half a point each side.
    static func narrowest(icon: CGFloat) -> CGFloat { icon + 1 }

    /// How wide the other tabs are while the tab with this `label` is selected, so its whole name shows beside its
    /// icon (inside the padding): `preferred` while the row has the room, less for a long name, never under `floor`
    /// (a name longer than that allows is cut with a fade, as before). On the pixel grid, rounded down so the name fits.
    static func unselectedWidth(label: CGFloat, row: CGFloat, count: Int, preferred: CGFloat, floor: CGFloat, icon: CGFloat,
                                gap: CGFloat, padding: CGFloat, spacing: CGFloat, scale: CGFloat = 2) -> CGFloat {
        guard count > 1 else { return preferred }
        let needed = selectedWidth(label: label, icon: icon, gap: gap, padding: padding)
        let room = (row - needed) / CGFloat(count - 1) - spacing
        return min(preferred, max(floor, (room * scale).rounded(.down) / scale))
    }

    /// One unselected width for every tab.
    static func frames(weights: [Double], width: CGFloat, unselected: CGFloat, spacing: CGFloat, scale: CGFloat = 2) -> Frames {
        frames(weights: weights, width: width, unselectedWidths: [CGFloat](repeating: unselected, count: weights.count), spacing: spacing, scale: scale)
    }

    /// Every width and position lands on the device's pixel grid (`scale` pixels per point), so glyphs are never resampled
    /// between frames; the row is as wide as the grid allows and the rounding residue goes to the most selected tab.
    /// `unselectedWidths`: for each tab, how wide the others are while it is selected; a move blends them.
    static func frames(weights: [Double], width: CGFloat, unselectedWidths: [CGFloat], spacing: CGFloat, scale: CGFloat = 2) -> Frames {
        let count = weights.count
        guard count > 0 else { return Frames(tabWidths: [], selectedness: [], indicatorX: 0, indicatorWidth: 0) }
        func snap(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }
        let row = (width * scale).rounded(.down) / scale
        let clean = weights.map { max(0, $0) }
        let total = clean.reduce(0, +)
        let f = total > 0 ? clean.map { $0 / total } : [1] + [Double](repeating: 0, count: count - 1)
        let u = snap(f.indices.reduce(CGFloat(0)) { $0 + CGFloat(f[$1]) * ($1 < unselectedWidths.count ? unselectedWidths[$1] : unselectedWidths.last ?? 0) })
        let selected = max(u, row - CGFloat(count - 1) * (u + spacing))
        var widths = f.map { snap(u + (selected - u) * CGFloat($0)) }
        let lead = f.indices.max { f[$0] < f[$1] } ?? 0
        widths[lead] += row - CGFloat(count - 1) * spacing - widths.reduce(0, +)
        let x = f.enumerated().reduce(CGFloat(0)) { $0 + CGFloat($1.element) * CGFloat($1.offset) * (u + spacing) }
        var starts: [CGFloat] = [], exactStarts: [CGFloat] = []
        var start: CGFloat = 0, exact: CGFloat = 0
        for index in 0..<count {
            starts.append(start)
            exactStarts.append(exact)
            start += widths[index] + spacing
            exact += u + (selected - u) * CGFloat(f[index]) + spacing
        }
        return Frames(tabWidths: widths, selectedness: f, indicatorX: snap(x), indicatorWidth: selected,
                      starts: starts, exactStarts: exactStarts, unselected: u)
    }

    /// Where a tab's icon starts (`lead`, from the tab's left edge) and how much of its label shows. At rest the icon
    /// is centred alone, or with its label (cut to fit inside the padding); in between it goes straight from one
    /// spot to the other, so it never turns back near the end of a move. The label shows as far as the tab allows.
    /// The icon's place in the row is rounded once, from the tab's unrounded edge (`exactStart`): rounding the edge
    /// and the offset separately can step it back half a pixel while the two move opposite ways.
    static func content(selectedness f: Double, width: CGFloat, start: CGFloat = 0, exactStart: CGFloat = 0, selected: CGFloat,
                        unselected: CGFloat, label: CGFloat, icon: CGFloat, gap: CGFloat, padding: CGFloat,
                        scale: CGFloat = 2) -> (lead: CGFloat, visible: CGFloat) {
        func snap(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }
        let f = CGFloat(min(1, max(0, f)))
        let alone = (unselected - icon) / 2
        let shown = min(label, max(0, selected - icon - gap - 2 * padding))
        let withLabel = (selected - icon - gap - shown) / 2
        let lead = snap(exactStart + alone + (withLabel - alone) * f) - start
        let visible = max(0, min(label * f, width - lead - icon - gap * f - padding))
        return (lead, visible)
    }

    /// Whether a label doesn't fit its selected tab at rest (inside the padding, beside the icon), by more than half
    /// a point: it's shown cut, so it must end in a fade rather than mid-glyph.
    static func labelCut(label: CGFloat, selected: CGFloat, icon: CGFloat, gap: CGFloat, padding: CGFloat) -> Bool {
        label > selected - icon - gap - 2 * padding + 0.5
    }

    /// The fade at a label's trailing edge, 12 points: while the label opens it narrows to nothing over the last
    /// quarter (nothing switches at the end); a label cut at rest keeps all of it.
    static func labelFade(selectedness f: Double, cut: Bool) -> CGFloat {
        cut ? 12 : 12 * CGFloat(min(1, max(0, (1 - f) * 4)))
    }

    /// A label's width: the title, and the count after a gap when there is one.
    static func labelWidth(title: CGFloat, count: CGFloat?, gap: CGFloat) -> CGFloat {
        title + (count.map { gap + $0 } ?? 0)
    }

    /// A tab that is as wide as its content when selected (the 한 일 strip): padding, icon, gap, label, padding.
    static func selectedWidth(label: CGFloat, icon: CGFloat, gap: CGFloat, padding: CGFloat) -> CGFloat {
        2 * padding + icon + gap + label
    }

    /// The layout for tabs that are as wide as their content when selected (`selectedWidths`, one per tab) and
    /// `unselected` otherwise, so the row is as wide as its tabs (it scrolls) and nothing is ever cut. As in `frames`, a
    /// move blends the weights: each tab grows by its own share, and the highlight blends both width and place.
    static func fitted(weights: [Double], selectedWidths: [CGFloat], unselected: CGFloat, spacing: CGFloat, scale: CGFloat = 2) -> Frames {
        let count = min(weights.count, selectedWidths.count)
        guard count > 0 else { return Frames(tabWidths: [], selectedness: [], indicatorX: 0, indicatorWidth: 0) }
        func snap(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }
        let u = snap(unselected)
        let clean = weights.prefix(count).map { max(0, $0) }
        let total = clean.reduce(0, +)
        let f = total > 0 ? clean.map { $0 / total } : [1] + [Double](repeating: 0, count: count - 1)
        let full = selectedWidths.prefix(count).map { max(u, snap($0)) }
        let exact = (0..<count).map { u + (full[$0] - u) * CGFloat(f[$0]) }
        let widths = exact.map(snap)
        var starts: [CGFloat] = [], exactStarts: [CGFloat] = []
        var start: CGFloat = 0, exactStart: CGFloat = 0
        for index in 0..<count {
            starts.append(start)
            exactStarts.append(exactStart)
            start += widths[index] + spacing
            exactStart += exact[index] + spacing
        }
        // Where the highlight rests on tab i: every tab before it unselected.
        let x = (0..<count).reduce(CGFloat(0)) { $0 + CGFloat(f[$1]) * CGFloat($1) * (u + spacing) }
        let width = (0..<count).reduce(CGFloat(0)) { $0 + CGFloat(f[$1]) * full[$1] }
        return Frames(tabWidths: widths, selectedness: f, indicatorX: snap(x), indicatorWidth: snap(width),
                      starts: starts, exactStarts: exactStarts)
    }

    /// The row's width: its tabs and the spacing between them.
    static func contentWidth(_ frames: Frames, spacing: CGFloat = 2) -> CGFloat {
        frames.tabWidths.reduce(0, +) + CGFloat(max(0, frames.tabWidths.count - 1)) * spacing
    }

    /// The scroll offset that shows the tab at `start`…`start + width` whole and clear of the `inset` edge fade, moving
    /// the row as little as possible (none when it already shows), within 0…`content - viewport`. A tab wider than the
    /// view shows its start.
    static func scrollTarget(start: CGFloat, width: CGFloat, viewport: CGFloat, offset: CGFloat, content: CGFloat, inset: CGFloat) -> CGFloat {
        let limit = max(0, content - viewport)
        let lead = start - inset, trail = start + width + inset
        let wanted: CGFloat
        if trail - lead > viewport || lead < offset {
            wanted = lead
        } else if trail > offset + viewport {
            wanted = trail - viewport
        } else {
            wanted = offset
        }
        return min(limit, max(0, wanted))
    }
}
