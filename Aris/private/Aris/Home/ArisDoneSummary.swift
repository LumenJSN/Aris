//
//  ArisDoneSummary.swift
//  Aris
//
//  The owner's 1B (mockups/done-and-reader.html, .chip and .tray): every finished job in one chip at the end of the tag row
//  — the tag's 28-point capsule at white .07 (.11 on hover) with words at .62 (.82), a 10-point check at .62, the count
//  at .9 in tabular figures, the newest title, and a 9-point chevron at .6 that turns over when the tray is open (220
//  ms, the opening curve). The tray opens in place from .965 (280 ms): 14 round, a .08 hairline over white .05 → .02, rows
//  at least 30 high and 9 round (white .05 on hover) with a check at .5, the title (12.5/510 .88) and the answer (.43),
//  and 열기 (10.5/620 .5); "+N개 더 · 기록 탭에 있어요" past four, then ArisUIWords.text("다 봤어요", "Seen them all")
//  (24 high, 8 round, white .08).
//  A question that waits off screen (확인 대기, ArisWaitingCards) is the same chip with the confirm card's shield and no
//  chevron: a click brings its card back.
//

import AppKit
import SwiftUI

/// The row and the tray, from a fold: no controller, so the offscreen render draws the real thing.
struct ArisTaskTagsContent: View {
    let fold: ArisDoneFold.Fold
    @Binding var trayOpen: Bool
    let open: (ArisBackgroundTask) -> Void
    let seenAll: () -> Void
    /// 확인 대기: the questions parked off screen (ArisWaitingCards), a chip each; a click brings that card back.
    var waiting: [ArisWaitingChip] = []
    var openWaiting: (String) -> Void = { _ in }
    /// When each job was handed out, for its tag's clock; and what a press on a running job's tag does (nil: nothing).
    var since: [UUID: Date] = [:]
    var stop: ((UUID) -> Void)?
    var stopHelp = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ArisFlowRow(spacing: ArisActivityTag.gap) {
                ForEach(fold.running) { task in
                    ArisActivityTag(label: ArisDoneFold.label(task), done: task.isDone, failed: task.isFailed,
                                    since: task.isFinished ? nil : since[task.id], stop: task.isFinished ? nil : stop.map { stop in ArisTagStop(help: stopHelp) { stop(task.id) } })
                        .allowsHitTesting(!task.isFinished && stop != nil)
                        .transition(ArisTaskTagsContent.tagExit)
                }
                ForEach(waiting) { chip in
                    ArisDoneSummaryChip(count: chip.lead, latest: chip.detail, open: false, symbol: "checkmark.shield.fill", unfolds: false,
                                        help: chip.help) {
                        openWaiting(chip.id)
                    }
                    .transition(ArisTaskTagsContent.tagExit)
                }
                if !fold.done.isEmpty {
                    ArisDoneSummaryChip(count: ArisDoneFold.count(fold), latest: ArisDoneFold.latest(fold) ?? "", open: trayOpen,
                                        symbol: ArisDoneFold.symbol(fold)) {
                        withAnimation(ArisGlass.opening) { trayOpen.toggle() }
                    }
                    .transition(ArisTaskTagsContent.tagExit)
                }
            }
            .padding(.horizontal, ArisActivityTag.rowInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            if trayOpen && !fold.done.isEmpty {
                ArisDoneTray(rows: ArisDoneFold.tray(fold), more: ArisDoneFold.more(fold.done.count), open: open) {
                    withAnimation(ArisGlass.resize) {
                        trayOpen = false
                        seenAll()
                    }
                }
                // The mockup's tray sits on the tag row's edge (its margin is the row's padding).
                .padding(.horizontal, ArisActivityTag.rowInset)
                .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.965, anchor: .top)), removal: .opacity))
            }
        }
        .animation(ArisGlass.resize, value: fold)
        .animation(ArisGlass.resize, value: waiting)
    }

    /// The mockup's .tag.out: 4 up at .985 as it fades, over 220 ms on the resize curve; in as a tag enters.
    static let tagExit: AnyTransition = .asymmetric(
        insertion: ArisActivityTag.entry,
        removal: .opacity.combined(with: .offset(y: -4)).combined(with: .scale(scale: 0.985))
            .animation(.timingCurve(0.45, 0, 0.55, 1, duration: 0.22)))
}

/// A 확인 대기 chip's words: what waits ("확인 대기"), whose question it is and what it asks, and its tooltip.
struct ArisWaitingChip: Equatable, Identifiable {
    /// The question's id.
    let id: String
    let lead: String
    let detail: String
    let help: String
}

private extension ArisBackgroundTask {
    var isDone: Bool { if case .done = state { true } else { false } }
    var isFailed: Bool { if case .failed = state { true } else { false } }
}

struct ArisDoneSummaryChip: View {
    let count: String
    let latest: String
    let open: Bool
    /// The mark before the words: the done chip's check, or the confirm card's shield for a question that waits.
    var symbol = "checkmark"
    /// It opens a tray under it (the chevron); a 확인 대기 chip shows its card instead.
    var unfolds = true
    var help = ArisUIWords.text("끝난 일 보기", "Show what's done")
    let action: () -> Void

    @State private var hovering = false

    private static let font = Font(ArisFont.system(11.5, weight: 560) as CTFont)
    private static let hover = Animation.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.14)

    var body: some View {
        Button(action: action) {
            HStack(spacing: ArisActivityTag.gap) {
                Image(systemName: symbol).font(.system(size: 8.5, weight: .heavy)).frame(width: 10, height: 10)
                    .foregroundStyle(.white.opacity(0.62))
                Text(verbatim: count).font(Self.font.monospacedDigit()).tracking(-0.115).foregroundStyle(.white.opacity(0.9))
                    .contentTransition(.numericText())
                Text(verbatim: latest).font(Self.font).tracking(-0.115).lineLimit(1).truncationMode(.tail)
                    .contentTransition(.interpolate).arisTextBacking()
                if unfolds {
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).frame(width: 9, height: 9).opacity(0.6)
                        .rotationEffect(.degrees(open ? 180 : 0))
                        .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.22), value: open)
                }
            }
            .foregroundStyle(.white.opacity(hovering ? 0.82 : 0.62))
            .padding(.leading, 8)
            .padding(.trailing, 11)
            .frame(height: ArisActivityTag.height)
            .frame(maxWidth: 380, alignment: .leading)
            .background(Capsule().fill(.white.opacity(hovering ? 0.11 : 0.07)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: false, vertical: true)
        .onHover { hovering = $0 }
        .animation(Self.hover, value: hovering)
        .animation(ArisActivityTag.relabel, value: count)
        .help(help)
    }
}

struct ArisDoneTray: View {
    let rows: [ArisBackgroundTask]
    let more: String?
    let open: (ArisBackgroundTask) -> Void
    let seenAll: () -> Void

    private static let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(rows) { task in
                ArisDoneTrayRow(task: task) { open(task) }
            }
            if let more {
                Text(verbatim: more).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.white.opacity(0.43)).arisTextBacking()
                    .padding(EdgeInsets(top: 1, leading: 31, bottom: 3, trailing: 8))
            }
            VStack(spacing: 0) {
                Rectangle().fill(.white.opacity(0.05)).frame(height: 1)
                HStack {
                    Spacer()
                    ArisMiniButton(title: ArisUIWords.text("다 봤어요", "Seen them all"), action: seenAll)
                }
                .padding(EdgeInsets(top: 4, leading: 2, bottom: 2, trailing: 2))
            }
            .padding(.top, 3)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 5)
        .background {
            Self.shape.fill(LinearGradient(colors: [.white.opacity(0.05), .white.opacity(0.02)], startPoint: .top, endPoint: .bottom))
            Self.shape.strokeBorder(.white.opacity(0.08), lineWidth: 1)
            Self.shape.strokeBorder(LinearGradient(stops: [.init(color: .white.opacity(0.05), location: 0), .init(color: .clear, location: 0.06)],
                                                   startPoint: .top, endPoint: .bottom), lineWidth: 1)
                .padding(1)
        }
    }
}

private struct ArisDoneTrayRow: View {
    let task: ArisBackgroundTask
    let open: () -> Void

    @State private var hovering = false
    @State private var goHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: failed ? "exclamationmark" : "checkmark").font(.system(size: 9, weight: .heavy))
                .foregroundStyle(failed ? Color(red: 1, green: 0.45, blue: 0.4).opacity(0.8) : .white.opacity(0.5))
                .frame(width: 16)
            (Text(verbatim: task.title).font(.system(size: 12.5, weight: .medium)).foregroundColor(.white.opacity(0.88))
                + Text(verbatim: "  " + ArisDoneFold.detail(task)).font(.system(size: 12.5))
                .foregroundColor(.white.opacity(0.43)))
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: open) {
                Text(ArisUIWords.text("열기", "Open")).font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(goHovering ? 0.9 : 0.5))
                    .padding(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(goHovering ? 0.1 : 0)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { goHovering = $0 }
        }
        .padding(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 4))
        .frame(minHeight: 30)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(hovering ? 0.05 : 0)))
        .onHover { hovering = $0 }
        .animation(.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.14), value: hovering)
        .animation(.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.14), value: goHovering)
    }

    private var failed: Bool { if case .failed = task.state { true } else { false } }
}

/// The mockup's .mini: 24 high, 10 in, 8 round, white .08 (.14 on hover), 11.5/600 at .82; it presses to .97.
struct ArisMiniButton: View {
    let title: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(verbatim: title).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.white.opacity(0.82))
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(hovering ? 0.14 : 0.08)))
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(ArisPressStyle())
        .onHover { hovering = $0 }
        .animation(.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.14), value: hovering)
    }
}
