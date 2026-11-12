//
//  ArisDayEndList.swift
//  Aris
//
//  Under the day-end sentence (ArisDayEnd), the owner's pick 2-C (qa/design-1111/cards-dayend-mock.html): one folded row,
//  목록, with small counts (done, not done, waiting) and a chevron. A press opens the checklist in place, on the
//  notch's own opening clock, and it stays open or folded for the day. The checklist is tiles on the composer's glass:
//  오늘 하려던 일 (a mark, the words, the kind, and on an open to-do one button, 내일로 넘기기), 내 확인 (each with 보기),
//  내일 (the first things with their time), and at the bottom one more folded row, 그 밖, for what was done without
//  having been planned. No sentences in it, and nobody's tally. Taller than the notch's room, the tiles scroll; the
//  sentence above and the 목록 row stay. Nothing here moves by itself, and with Reduce Motion nothing slides.
//

import SwiftUI

struct ArisDayEndFold: View {
    let summary: ArisDayEnd
    let open: Bool
    /// The rows whose 내일로 넘기기 didn't go through.
    var notPushed: Set<String> = []
    /// How tall the opened tiles may grow before they scroll.
    var budget: CGFloat = ArisAnswerBudget.widgetMax
    /// 그 밖 starts open (the renders draw it; in the app it is always folded first).
    var extrasOpen = false
    var toggle: () -> Void = {}
    var push: (ArisDayEnd.Item) -> Void = { _ in }
    var show: (String) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 그 밖 as the user last pressed it; nil until they does.
    @State private var pressedExtras: Bool?

    /// The turn's own gap between the sentence, the row and the tiles; the tiles are 8 apart, their rows 5.
    static let gap: CGFloat = 12
    static let tileGap: CGFloat = 8
    static let rowGap: CGFloat = 5
    static let rowHeight: CGFloat = 24
    static let tileInset = EdgeInsets(top: 9, leading: 11, bottom: 10, trailing: 9)
    /// Tomorrow's time column, so every row's words start on one line.
    static let timeWidth: CGFloat = 64
    /// What the sentence above (up to three lines) and the 목록 row take of the answer's room, with their gaps.
    static let reserved: CGFloat = 72 + gap + ArisDayEndFoldRow.height + gap
    /// The tiles' type, as the mockup's: 12.5 for words, 11.5 beside them, 10.5 labels.
    static let words = Font.system(size: 12.5)
    static let beside = Font.system(size: 11.5)
    static let label = Font.system(size: 10.5)

    private var english: Bool { summary.english }
    private var showsExtras: Bool { pressedExtras ?? extrasOpen }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.gap) {
            ArisDayEndFoldRow(title: ArisDayEndCopy.list(english: english), marks: summary.marks, open: open, english: english,
                              help: ArisDayEndCopy.listHelp(open: open, english: english)) {
                withAnimation(reduceMotion ? nil : ArisGlass.opening) { toggle() }
            }
            if open {
                ArisFadingScroll(budget: budget) { tiles }
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var tiles: some View {
        VStack(alignment: .leading, spacing: Self.tileGap) {
            if !summary.planned.isEmpty {
                tile(ArisDayEndCopy.plannedTitle(summary.counts.planned, english: english)) { ForEach(summary.planned) { planned($0) } }
            }
            if !summary.waiting.isEmpty {
                tile(ArisDayEndCopy.waitingTitle(summary.counts.waiting, english: english)) { ForEach(summary.waiting) { waiting($0) } }
            }
            if !summary.tomorrow.isEmpty {
                tile(ArisDayEndCopy.tomorrowTitle(summary.counts.tomorrow, english: english)) {
                    ForEach(summary.tomorrow) { later($0) }
                    more(summary.counts.tomorrow - summary.tomorrow.count)
                }
            }
            extras
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 2)
    }

    /// What was done without having been planned: folded, and by name once opened.
    @ViewBuilder private var extras: some View {
        if !summary.extras.isEmpty, summary.planned.isEmpty, summary.waiting.isEmpty, summary.tomorrow.isEmpty {
            // Nothing else to list: it is the list, so it needs no fold of its own.
            tile(ArisDayEndCopy.extrasTitle(summary.counts.extra, english: english)) { extraRows }
        } else if !summary.extras.isEmpty {
            ArisDayEndFoldRow(title: ArisDayEndCopy.extrasTitle(summary.counts.extra, english: english), marks: [], open: showsExtras, english: english,
                              help: ArisDayEndCopy.listHelp(open: showsExtras, english: english)) {
                withAnimation(reduceMotion ? nil : ArisGlass.opening) { pressedExtras = !showsExtras }
            }
            if showsExtras {
                tile(nil) { extraRows }
                    .transition(.opacity)
            }
        } else if summary.activityUnread {
            Text(verbatim: ArisDayEndCopy.extrasUnread(english: english)).font(Self.beside).foregroundStyle(.white.opacity(0.43))
                .lineLimit(1).padding(.horizontal, Self.tileInset.leading)
        }
    }

    @ViewBuilder private var extraRows: some View {
        ForEach(summary.extras) { extra in
            row { ArisDayEndMark(mark: .done, english: english) } words: { main(extra.title) }
        }
        more(summary.counts.extra - summary.extras.count)
    }

    private func tile<Rows: View>(_ title: String?, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: Self.rowGap) {
            if let title { Text(verbatim: title).font(Self.label).foregroundStyle(.white.opacity(0.35)).lineLimit(1) }
            rows()
        }
        .padding(Self.tileInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ArisSideStyle.pill(RoundedRectangle(cornerRadius: ArisGlass.pillRadius, style: .continuous)))
    }

    private func planned(_ item: ArisDayEnd.Item) -> some View {
        row { ArisDayEndMark(mark: item.mark, english: english) } words: {
            main(item.title, help: item.note)
            Text(verbatim: ArisDayEndCopy.kind(item.kind, english: english)).font(Self.beside).foregroundStyle(.white.opacity(0.43)).lineLimit(1).fixedSize()
            if item.state == .moved {
                settled(ArisDayEndCopy.pushed(english: english))
            } else if notPushed.contains(item.id) {
                settled(ArisDayEndCopy.notPushed(english: english))
            } else if item.pushes {
                ArisMiniButton(title: ArisDayEndCopy.push(english: english)) { push(item) }
            }
        }
    }

    private func waiting(_ item: ArisDayEnd.Waiting) -> some View {
        row { ArisDayEndMark(mark: .wait, english: english) } words: {
            main(item.title)
            if let card = item.card { ArisMiniButton(title: ArisDayEndCopy.show(english: english)) { show(card) } }
        }
    }

    private func later(_ item: ArisDayEnd.Later) -> some View {
        row {
            Text(verbatim: item.time).font(Self.beside.monospacedDigit()).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                .frame(width: Self.timeWidth, alignment: .leading)
        } words: {
            main(item.title)
            Text(verbatim: ArisDayEndCopy.kind(item.kind, english: english)).font(Self.beside).foregroundStyle(.white.opacity(0.43)).lineLimit(1).fixedSize()
        }
    }

    /// A row of the mockup's .trow: what leads it, its words, and what stands at its end, 8 apart and 24 tall.
    private func row<Lead: View, Words: View>(@ViewBuilder lead: () -> Lead, @ViewBuilder words: () -> Words) -> some View {
        HStack(alignment: .center, spacing: 8) {
            lead()
            words()
        }
        .frame(minHeight: Self.rowHeight)
    }

    private func main(_ text: String, help: String? = nil) -> some View {
        Text(verbatim: text).font(Self.words).foregroundStyle(.white.opacity(0.88)).lineLimit(1).truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(help ?? text)
    }

    /// Where a button was, once it has done its work: its words without the button (the mockup's disabled .mini).
    private func settled(_ words: String) -> some View {
        Text(verbatim: words).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.white.opacity(0.43)).lineLimit(1).fixedSize()
            .padding(.horizontal, 10).frame(height: Self.rowHeight)
    }

    @ViewBuilder private func more(_ count: Int) -> some View {
        if count > 0 {
            Text(verbatim: ArisDayEndCopy.andMore(count, english: english)).font(Self.beside).foregroundStyle(.white.opacity(0.43)).lineLimit(1)
        }
    }
}

/// A folded row (the mockup's .fold): at least 28 tall, 14 round, white 6% (13% under the pointer), its words at 12 /
/// .72, the counts, and a chevron that turns down on the notch's opening clock. It presses to .97.
struct ArisDayEndFoldRow: View {
    let title: String
    let marks: [(mark: ArisDayEnd.Mark, count: Int)]
    let open: Bool
    var english = ArisUILanguage.english
    var help = ""
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    static let height: CGFloat = 28
    static let radius: CGFloat = 14
    static let chevron: CGFloat = 10

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(verbatim: title).font(.system(size: 12)).foregroundStyle(.white.opacity(0.72)).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !marks.isEmpty { ArisDayEndCounts(marks: marks, english: english) }
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.43))
                    .frame(width: Self.chevron, height: Self.chevron)
                    .rotationEffect(.degrees(open ? 90 : 0))
                    .animation(reduceMotion ? nil : ArisGlass.opening, value: open)
            }
            .padding(.leading, 11).padding(.trailing, 9)
            .frame(maxWidth: .infinity, minHeight: Self.height)
            .background(RoundedRectangle(cornerRadius: Self.radius, style: .continuous).fill(.white.opacity(hovering ? 0.13 : 0.06)))
            .contentShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        }
        .buttonStyle(ArisPressStyle())
        .onHover { hovering = $0 }
        .animation(.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.14), value: hovering)
        .help(help)
        .accessibilityValue(ArisDayEndCopy.listState(open: open, english: english))
    }
}
