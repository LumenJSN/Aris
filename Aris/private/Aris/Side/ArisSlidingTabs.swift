//
//  ArisSlidingTabs.swift
//  Aris
//
//  Segmented tabs: the selected tab takes the row's spare width and shows its label, the rest shrink to
//  icons, and one highlight slides behind them. Everything is derived from one animated weight per tab
//  (ArisSlidingTabsGeometry), so moving left looks exactly like moving right and a move interrupted halfway
//  carries on smoothly. `fitted` (the 한 일 strip): the selected tab is as wide as its icon, whole name and count,
//  the others icons only, and the row scrolls sideways (ArisStripScroll), bringing the picked tab into view.
//

import AppKit
import SwiftUI

struct ArisSlidingTabs<ID: Hashable>: View {
    struct Item {
        let id: ID
        let icon: AnyView
        let title: String
        /// The icon's colour while selected (white when nil).
        var selectedTint: Color?
        /// A number shown after the title while the tab is selected (the 한 일 strip's count today); never otherwise.
        var count: Int?
    }

    let items: [Item]
    @Binding var selection: ID
    let unselectedWidth: CGFloat
    let height: CGFloat
    var spacing: CGFloat = 2
    /// Room kept clear inside the selected tab on each side of its icon and label.
    var labelPadding: CGFloat = 8
    /// Tabs as wide as their content when selected, in a sideways scroller, instead of sharing the row's width.
    var fitted = false

    var body: some View {
        let index = items.firstIndex { $0.id == selection } ?? 0
        let target = ArisWeights((0..<items.count).map { $0 == index ? 1 : 0 })
        let base = SlidingRow(weights: target, items: items, select: { selection = $0 }, unselectedWidth: unselectedWidth,
                              height: height, spacing: spacing, padding: labelPadding, fitted: fitted)
        // Only a press on a tab slides the highlight; a tab changed any other way is simply shown (ArisTabMotion).
        let row = base.animation(ArisTabMotion.reduceMotion || !ArisTabPress.pressed ? nil : ArisTabMotion.slide, value: selection)
        if fitted {
            // Laid out as the move will end, so the scroller sizes its row and brings the picked tab in from that.
            let rest = ArisSlidingTabsGeometry.fitted(weights: target.values, selectedWidths: base.selectedWidths,
                                                      unselected: unselectedWidth, spacing: spacing)
            ArisStripScroll(contentWidth: ArisSlidingTabsGeometry.contentWidth(rest, spacing: spacing), height: height,
                            focus: rest.starts.isEmpty ? nil : ArisStripFocus(key: index, start: rest.starts[index], width: rest.tabWidths[index])) {
                row
            }
            .frame(height: height)
        } else {
            row.frame(height: height)
        }
    }
}

private struct SlidingRow<ID: Hashable>: View, Animatable {
    var weights: ArisWeights
    let items: [ArisSlidingTabs<ID>.Item]
    let select: (ID) -> Void
    let unselectedWidth: CGFloat
    let height: CGFloat
    let spacing: CGFloat
    let padding: CGFloat
    let fitted: Bool
    @Environment(\.displayScale) private var scale

    var animatableData: ArisWeights {
        get { weights }
        set { weights = newValue }
    }

    private static var font: NSFont { .systemFont(ofSize: 12, weight: .semibold) }
    private static var countFont: NSFont { .monospacedDigitSystemFont(ofSize: 10, weight: .semibold) }
    private static var iconWidth: CGFloat { 16 }
    private static var gap: CGFloat { 5 }

    /// Each tab's label: its whole title, then its count.
    private func labelWidth(_ item: ArisSlidingTabs<ID>.Item) -> CGFloat {
        let title = ceil((item.title as NSString).size(withAttributes: [.font: Self.font]).width)
        let count = item.count.map { ceil((String($0) as NSString).size(withAttributes: [.font: Self.countFont]).width) }
        return ArisSlidingTabsGeometry.labelWidth(title: title, count: count, gap: Self.gap)
    }

    /// Fitted: how wide each tab is when selected, all of its label showing.
    var selectedWidths: [CGFloat] {
        items.map { ArisSlidingTabsGeometry.selectedWidth(label: labelWidth($0), icon: Self.iconWidth, gap: Self.gap, padding: padding) }
    }

    var body: some View {
        if fitted {
            let widths = selectedWidths
            let frames = ArisSlidingTabsGeometry.fitted(weights: weights.values, selectedWidths: widths, unselected: unselectedWidth,
                                                        spacing: spacing, scale: scale)
            tabs(frames, selected: { widths[$0] }, unselected: unselectedWidth)
                .frame(width: ArisSlidingTabsGeometry.contentWidth(frames, spacing: spacing), height: height, alignment: .leading)
        } else {
            GeometryReader { geometry in
                // The others are icons: they narrow as far as the selected tab's measured name needs (never cut it).
                let narrow = items.map {
                    ArisSlidingTabsGeometry.unselectedWidth(label: labelWidth($0), row: geometry.size.width, count: items.count,
                                                            preferred: unselectedWidth, floor: ArisSlidingTabsGeometry.narrowest(icon: Self.iconWidth),
                                                            icon: Self.iconWidth, gap: Self.gap, padding: padding, spacing: spacing, scale: scale)
                }
                let frames = ArisSlidingTabsGeometry.frames(weights: weights.values, width: geometry.size.width,
                                                           unselectedWidths: narrow, spacing: spacing, scale: scale)
                tabs(frames, selected: { _ in frames.indicatorWidth }, unselected: frames.unselected)
            }
            .frame(height: height)
        }
    }

    private func tabs(_ frames: ArisSlidingTabsGeometry.Frames, selected: @escaping (Int) -> CGFloat, unselected: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.12))
                .frame(width: frames.indicatorWidth, height: height)
                .offset(x: frames.indicatorX)
            HStack(spacing: spacing) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    tab(item, f: frames.selectedness[index], width: frames.tabWidths[index],
                        start: frames.starts[index], exactStart: frames.exactStarts[index], selected: selected(index), unselected: unselected)
                }
            }
        }
    }

    /// While a label is still opening, its trailing edge fades out instead of ending in a hard edge. The fade
    /// narrows to nothing over the last quarter of the opening, in the same view, so nothing switches at the end; a
    /// label too long for its tab keeps it, so it never ends mid-glyph (ArisSlidingTabsGeometry.labelFade).
    private func fade(_ f: Double, cut: Bool) -> some View {
        HStack(spacing: 0) {
            Rectangle()
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: ArisSlidingTabsGeometry.labelFade(selectedness: f, cut: cut))
        }
    }

    /// `selected`: this tab's width once selected (the row's spare width, or fitted, its own content). `unselected`: its
    /// width as an icon alone, as laid out now.
    private func tab(_ item: ArisSlidingTabs<ID>.Item, f: Double, width: CGFloat, start: CGFloat, exactStart: CGFloat,
                     selected: CGFloat, unselected: CGFloat) -> some View {
        // The content is placed by hand on the pixel grid (a centring stack would sit on arbitrary fractions).
        let (lead, visible) = ArisSlidingTabsGeometry.content(selectedness: f, width: width, start: start, exactStart: exactStart,
                                                              selected: selected, unselected: unselected, label: labelWidth(item),
                                                              icon: Self.iconWidth, gap: Self.gap, padding: padding, scale: scale)
        return Button { select(item.id) } label: {
            ZStack(alignment: .leading) {
                Color.clear.frame(width: width, height: height)
                HStack(spacing: 0) {
                    ZStack {
                        item.icon.foregroundStyle(ArisSideStyle.placeholder)
                        item.icon.foregroundStyle(item.selectedTint ?? Color.white.opacity(0.95)).opacity(f)
                    }
                    .frame(width: Self.iconWidth, height: height)
                    label(item)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(width: visible, alignment: .leading)
                        .clipped()
                        .mask { fade(f, cut: ArisSlidingTabsGeometry.labelCut(label: labelWidth(item), selected: selected,
                                                                              icon: Self.iconWidth, gap: Self.gap, padding: padding)) }
                        .opacity(f)
                        .padding(.leading, Self.gap * f)
                }
                .fixedSize()
                .offset(x: lead)
            }
            .frame(width: width, height: height)
            .clipped()
            .contentShape(Capsule())
        }
        .buttonStyle(ArisTabButtonStyle())
        .help(item.title)
    }

    /// The title, and the count after it in a quieter 10 (mockup 5b D+: 10 semibold at 43%). Only a selected tab shows
    /// it (it opens with the tab's selectedness), so an unselected tab never shows a count.
    private func label(_ item: ArisSlidingTabs<ID>.Item) -> some View {
        HStack(spacing: Self.gap) {
            Text(item.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.95))
            if let count = item.count {
                Text(String(count))
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.43))
            }
        }
    }
}

/// A tab press changes nothing about the tab (no pressed dimming), so nothing shifts when a click ends.
private struct ArisTabButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

/// One weight per tab, animated as a vector.
struct ArisWeights: VectorArithmetic, Equatable {
    var values: [Double]

    init(_ values: [Double]) { self.values = values }

    static var zero: ArisWeights { ArisWeights([]) }

    private static func combine(_ a: ArisWeights, _ b: ArisWeights, _ op: (Double, Double) -> Double) -> ArisWeights {
        ArisWeights((0..<max(a.values.count, b.values.count)).map { op($0 < a.values.count ? a.values[$0] : 0, $0 < b.values.count ? b.values[$0] : 0) })
    }

    static func + (a: ArisWeights, b: ArisWeights) -> ArisWeights { combine(a, b, +) }
    static func - (a: ArisWeights, b: ArisWeights) -> ArisWeights { combine(a, b, -) }
    static func += (a: inout ArisWeights, b: ArisWeights) { a = a + b }
    static func -= (a: inout ArisWeights, b: ArisWeights) { a = a - b }

    mutating func scale(by rhs: Double) { values = values.map { $0 * rhs } }

    var magnitudeSquared: Double { values.reduce(0) { $0 + $1 * $1 } }
}
