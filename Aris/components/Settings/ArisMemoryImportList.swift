//
//  ArisMemoryImportList.swift
//  Aris
//
//  설정 › 기억 › 다른 AI에서 가져오기, step 3: every line the agent read, grouped as the export grouped them, each a tick
//  row in a review list: a ticked line is a white card with a gray-300 edge and a small shadow (white 6 % in
//  dark), an unticked one has no fill and is drawn at 55 %; its date and
//  kind under it, and the mark (이미 알아요, 명령처럼 읽혀요, 비밀처럼 보여서 뺐어요 …) as the settings chip, at full
//  strength and never moving. A line that can't be ticked keeps its box at half strength.
//  The list scrolls inside the sheet with faded ends, so the footer never sits on a row.
//

import SwiftUI

/// One line with its tick. `level` is the tick (0 empty → 1 ticked), animated as it changes so the box, the mark and
/// the card are drawn from one clock (ArisImportBox).
struct ArisImportTickRow: View, Animatable {
    typealias C = ArisMemoryImportCopy
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let row: ArisImportRow
    var level: Double
    let enabled: Bool
    /// What will be stored and what it replaces (ArisMemoryImportRowDetail).
    let extra: ArisMemoryImportRowDetail.Extra
    /// Pressed, as a render draws it (the app uses the button's own press).
    var pressed = false
    let toggle: () -> Void
    @State private var hovering = false

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    var body: some View {
        Button(action: toggle) { face }
            // List items and menu rows press to 0.98.
            .buttonStyle(ArisImportPress(forced: pressed))
            .disabled(!enabled)
            .onHover { hovering = $0 && enabled }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isToggle)
            .accessibilityValue(w(level > 0.5 ? "켬" : "끔"))
    }

    private var face: some View {
        let shape = RoundedRectangle(cornerRadius: ArisImportMetric.radius, style: .continuous)
        let card = ArisMemoryImportPacing.tick.progress(at: level * ArisMemoryImportPacing.tick.duration)
        return HStack(alignment: .top, spacing: ArisImportMetric.rowGap) {
            ArisImportBox(level: level, hovering: hovering)
                .opacity(row.importable ? 1 : 0.5)
                .padding(.top, 1.5)
            VStack(alignment: .leading, spacing: 4) {
                // The whole line, however long: he reads all of it before he ticks it (security review 8, H2).
                Text(row.text).font(.system(size: 14, weight: .medium)).foregroundStyle(palette.title)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(0.55 + 0.45 * card)
                meta
                detail(card)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, ArisImportMetric.rowSide).padding(.vertical, ArisImportMetric.rowTop)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(palette.tickedRow.opacity(card))
            .shadow(color: .black.opacity(palette.dark ? 0 : 0.1 * card), radius: 1.5, y: 1))
        .overlay(shape.strokeBorder(palette.plainRowEdge, lineWidth: 1).opacity(1 - card))
        .overlay(shape.strokeBorder(palette.tickedRowEdge, lineWidth: 1).opacity(card))
        .contentShape(shape)
    }

    /// What will be stored when it isn't the line itself, and the wording a replacing line takes the place of
    /// (security review 8, H2 and M3), each as "label  words" in 12 pt.
    @ViewBuilder private func detail(_ card: Double) -> some View {
        let english = w.pageEnglish
        if let stored = extra.stored {
            labelled(english ? "Stored as" : "저장되는 내용", stored).opacity(0.55 + 0.45 * card)
        }
        if let replaces = extra.replaces {
            labelled(english ? "Replaces" : "바꿀 기억", replaces).opacity(0.55 + 0.45 * card)
        }
    }

    private func labelled(_ label: String, _ words: String) -> some View {
        (Text(label + "  ").font(.system(size: 12, weight: .semibold)).foregroundColor(palette.icon)
            + Text(words).font(.system(size: 12)).foregroundColor(palette.desc))
            .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
    }

    /// "2025-03-01 · 취향" and the mark, if the line has one.
    private var meta: some View {
        let card = ArisMemoryImportPacing.tick.progress(at: level * ArisMemoryImportPacing.tick.duration)
        return HStack(spacing: 8) {
            Text(ArisMemoryImportBoard.sub(row).components(separatedBy: " · ").map { w($0) }.joined(separator: " · "))
                .font(.system(size: 12)).monospacedDigit().foregroundStyle(palette.desc)
                .opacity(0.55 + 0.45 * card)
            if let mark = C.states[row.state] {
                ArisChip(text: mark, tone: row.state == "known" || row.state == "updates" ? .plain : .warn)
            }
            if row.future == true { ArisChip(text: C.futureNote, tone: .warn) }
            if row.address == true { ArisChip(text: C.addressNote, tone: .warn) }
        }
    }
}

/// The row's press: 0.98 over 140 ms (ArisSettingsMotion.press), held down when a render asks.
struct ArisImportPress: ButtonStyle {
    var forced = false

    func makeBody(configuration: Configuration) -> some View {
        let down = (configuration.isPressed || forced) && !ArisSettingsMotion.reduced
        configuration.label
            .scaleEffect(down ? ArisPressScale.measured : 1)
            .animation(ArisSettingsMotion.press, value: configuration.isPressed)
    }
}

/// The groups, their rows, and the lines that couldn't be read. Rises in the first time it is shown (`rise`: seconds
/// since that began); a tick never makes it rise again.
struct ArisImportList: View {
    typealias C = ArisMemoryImportCopy
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    @Environment(\.arisSettingsStill) private var still
    @Environment(\.arisImportScrub) private var scrub
    @Environment(\.arisImportStandIn) private var standIn
    @Binding var board: ArisMemoryImportBoard
    let rise: Double?
    let reduced: Bool
    let tick: (Int) -> Void
    @State private var contentHeight: CGFloat?

    var body: some View {
        let most = ArisImportMetric.listMost
        if still {
            // Drawn once: the list as it rests at the top (or, for the end-of-list render, scrolled to its end).
            ArisImportCap(most: most, atEnd: scrub?.listAtEnd == true) { items }
                .arisImportFadedEnds()
        } else {
            ScrollView {
                items.onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
            }
            .scrollIndicators(.automatic)
            .frame(height: min(contentHeight ?? most, most))
            .arisImportFadedEnds()
        }
    }

    /// Every item, numbered in the order shown for the stagger.
    private var items: some View {
        let groups = board.groups
        // Each group's heading takes a place in the stagger, then its rows.
        var starts: [Int] = []
        var next = 0
        for group in groups {
            starts.append(next)
            next += group.rows.count + 1
        }
        return VStack(alignment: .leading, spacing: ArisImportMetric.rowSpacing) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { offset, group in
                heading(group, first: offset == 0).modifier(ArisImportRise(seconds: rise, index: starts[offset], reduced: reduced))
                ForEach(Array(group.rows.enumerated()), id: \.element.id) { place, row in
                    line(row).modifier(ArisImportRise(seconds: rise, index: starts[offset] + 1 + place, reduced: reduced))
                }
            }
            if !board.unreadable.isEmpty { unreadable }
        }
        .padding(.vertical, ArisImportMetric.fade)
    }

    @ViewBuilder private func heading(_ group: ArisMemoryImportBoard.Group, first: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ArisImportHeading(title: C.categories[group.id] ?? group.id, count: group.rows.count)
            if group.id == "instructions" { ArisImportNote(text: C.instructionNote) }
        }
        .padding(.top, first ? 0 : 8)
    }

    private func line(_ row: ArisImportRow) -> some View {
        let scrubbed = scrub?.tickRow == row.n ? scrub : nil
        let level = scrubbed.map { ArisImportList.tickLevel($0, ticked: row.ticked) } ?? (row.ticked && row.importable ? 1 : 0)
        let extra = standIn[row.n] ?? ArisMemoryImportRowDetail.extra(row)
        return ArisImportTickRow(row: row, level: level, enabled: row.importable && !board.busy, extra: extra,
                                 pressed: scrubbed.map { ($0.tick ?? 1) < $0.release } ?? false) { tick(row.n) }
    }

    /// A render's tick: empty until the press is let go, then ticking over the tick's time.
    static func tickLevel(_ scrub: ArisImportScrub, ticked: Bool) -> Double {
        let since = (scrub.tick ?? 1) - scrub.release
        let level = min(max(since / ArisMemoryImportPacing.tick.duration, 0), 1)
        return ticked ? level : 1 - level
    }

    private var unreadable: some View {
        VStack(alignment: .leading, spacing: 4) {
            ArisImportHeading(title: C.unreadable, count: board.unreadable.count)
            ArisImportNote(text: C.unreadableNote)
            ForEach(Array(board.unreadable.prefix(still ? 2 : 50).enumerated()), id: \.offset) { _, text in
                Text(text).font(.system(size: 12)).foregroundStyle(palette.pasteHint).lineLimit(2)
            }
        }
        .padding(.top, 8)
    }
}

/// A note under a heading: 12 pt in the description grey, one sentence a line.
struct ArisImportNote: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(ArisMemoryImportPacing.sentences(w(text)).enumerated()), id: \.offset) { _, line in
                Text(line).font(.system(size: 12)).foregroundStyle(palette.desc).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Drawn once: as tall as its content up to `most`, showing the top (or the end).
struct ArisImportCap: Layout {
    let most: CGFloat
    var atEnd = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 420
        let height = subviews.first?.sizeThatFits(ProposedViewSize(width: width, height: nil)).height ?? 0
        return CGSize(width: width, height: min(height, most))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let subview = subviews.first else { return }
        let height = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
        let y = atEnd ? bounds.maxY - height : bounds.minY
        subview.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: nil))
    }
}
