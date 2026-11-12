//
//  ArisActivityView.swift
//  Aris
//
//  The left panel's 한 일 tab, the owner's pick D+ (mockups/5b-history.html): a strip of teammates like the 사용량 tab's
//  (avatar, name, today's count; 전체 first), then the timeline in B's look (a time column, a hairline rail with a
//  still node per entry, a text 되돌리기 pill), grouped by teammate under 전체 and under one quiet "<name> · 오늘" line
//  for one teammate. Undone entries fade with their title struck through. Switching teammates fades the list out over
//  120 ms and the new one in (opacity 180 ms, rise 200 ms). No status dot ever blinks or pulses.
//

import SwiftUI

struct ArisActivityView: View {
    @ObservedObject private var model = ArisActivityModel.shared
    /// False for the first frame: the list that opens with the tab doesn't fade in again under ArisTabSwap.
    @State private var settled = false

    var body: some View {
        let now = Date()
        let mates = ArisActivityTab.teammates(model.items, now: now, calendar: .current)
        let today = ArisActivityTab.todayCount(model.items, now: now, calendar: .current)
        VStack(alignment: .leading, spacing: 8) {
            if !mates.isEmpty {
                strip(mates, today: today)
            }
            ZStack(alignment: .top) {
                ArisActivityList(sections: ArisActivityTab.sections(model.items, filter: model.filter, now: now, calendar: .current),
                                 placeholder: placeholder(empty: today == 0), entering: settled)
                    .id(model.filter)
                    .transition(.asymmetric(insertion: .identity, removal: ArisActivityMotion.listOut))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            footer(mates: mates.count, today: today)
        }
        .onAppear {
            model.opened()
            DispatchQueue.main.async { settled = true }
        }
    }

    /// 전체, then every teammate who did something today, in a strip that scrolls sideways: each chip is its icon or
    /// avatar; the picked one opens to its whole name and today's count (never cut) and is brought into view. The
    /// heading below the strip names the pick.
    private func strip(_ mates: [ArisActivityTab.Teammate], today: Int) -> some View {
        typealias Item = ArisSlidingTabs<ArisActivityFilter>.Item
        let everyone = Item(id: .everyone, icon: AnyView(Image(systemName: "checklist.checked").font(.system(size: 12, weight: .medium))),
                            title: ArisUIWords.text("전체", "All"), count: today)
        let ids = ArisActivityTab.teammateIds(model.items)
        let people = mates.map { mate in
            Item(id: .teammate(mate.name), icon: AnyView(ArisTeammateAvatar(name: mate.name, id: ids[mate.name], size: 18)), title: ArisTeammateName.display(mate.name),
                 count: mate.today)
        }
        return ArisSlidingTabs(items: [everyone] + people, selection: $model.filter, unselectedWidth: 30, height: 28,
                               labelPadding: ArisActivityTab.chipPadding, fitted: true)
            .padding(.horizontal, -2)
    }

    /// What shows instead of rows: nil once there are some.
    private func placeholder(empty: Bool) -> String? {
        switch model.load {
        case .loading: empty ? ArisUIWords.text("불러오는 중…", "Loading…") : nil
        case .failed: ArisUIWords.text("Aris 도우미에 연결하지 못했어요", "Couldn't reach Aris's helper")
        case .loaded: empty ? ArisUIWords.text("오늘 한 일이 아직 없어요", "Nothing done yet today") : nil
        }
    }

    /// 10 at 38%, the phrase that also undoes at 62% (mockup .foot); an undo that failed says why instead.
    private func footer(mates: Int, today: Int) -> some View {
        Group {
            if let notice = model.waitingNotice ?? model.notice {
                Text(notice).foregroundStyle(.white.opacity(0.62))
            } else if today > 0 {
                Text(ArisActivityTab.footer(teammates: mates, today: today) + " · ") + Text(ArisActivityTab.undoPhrase()).foregroundStyle(.white.opacity(0.62))
            } else {
                Text(ArisActivityTab.undoPhrase()).foregroundStyle(.white.opacity(0.62))
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.white.opacity(0.38))
        .lineLimit(2)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }
}

/// The 한 일 list's motion (mockup 5b D+, Emil Kowalski's numbers): out over 120 ms with a 2-point blur and a 3-point
/// lift, then in: opacity over 180 ms (0.22, 0.61, 0.36, 1) and a rise from 4 points below over 200 ms (0.22, 1, 0.36, 1).
/// Reduce Motion keeps only the fades.
enum ArisActivityMotion {
    static let outDuration = 0.12
    static let fadeIn = Animation.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.18).delay(outDuration)
    static let riseIn = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.2).delay(outDuration)
    static var rise: CGFloat { ArisTabMotion.reduceMotion ? 0 : 4 }
    /// Undone fade and the 되돌리기 / 되돌림 swap (mockup .fadeable 180 ms, .swap 200 ms, CSS ease).
    static let fade = ArisSideStyle.cssEase(0.18)
    static let swap = ArisSideStyle.cssEase(0.2)
    /// A press: 140 ms strong ease-out.
    static let press = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.14)

    static var listOut: AnyTransition {
        let still = ArisTabMotion.reduceMotion
        return AnyTransition.modifier(active: ListShift(opacity: 0, blur: still ? 0 : 2, y: still ? 0 : -3),
                                      identity: ListShift(opacity: 1, blur: 0, y: 0))
            .animation(ArisSideStyle.cssEase(outDuration))
    }

    private struct ListShift: ViewModifier {
        let opacity: Double
        let blur: CGFloat
        let y: CGFloat

        func body(content: Content) -> some View {
            content.blur(radius: blur).offset(y: y).opacity(opacity)
        }
    }
}

/// The scrolling timeline: section headings (a teammate's avatar, name and count, or one teammate's day line) over
/// rows, the bottom fading out like the 기록 tab's list. `entering`: it replaces another list (a teammate was picked),
/// so it comes in after the old one went out, its opacity and its rise on their own curves.
private struct ArisActivityList: View {
    let sections: [ArisActivityTab.Section]
    let placeholder: String?
    @ObservedObject private var model = ArisActivityModel.shared
    @State private var shown: Double
    @State private var lift: CGFloat

    init(sections: [ArisActivityTab.Section], placeholder: String?, entering: Bool) {
        self.sections = sections
        self.placeholder = placeholder
        _shown = State(initialValue: entering ? 0 : 1)
        _lift = State(initialValue: entering ? ArisActivityMotion.rise : 0)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let placeholder {
                    ArisSideStyle.empty(placeholder)
                } else {
                    ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                        heading(section, first: index == 0)
                        ForEach(section.rows) { item in
                            ArisActivityRow(item: item, style: ArisActivityTab.style(item),
                                            time: ArisActivityTab.time(item.date, calendar: .current),
                                            busy: model.undoing.contains(item.id),
                                            undo: { Task { await model.undo(item.id) } })
                        }
                    }
                }
            }
            .padding(ArisSideStyle.listInsets(underHeader: false, toEdge: false))
        }
        // Between the teammates' strip and the footer: only the 34-point fade at the end.
        .modifier(ArisSideListFrame(underHeader: false, toEdge: false))
        // After the mask, as the 기록 tab: the rows reach 7 points past the panel's text column.
        .padding(.horizontal, -7)
        .opacity(shown)
        .offset(y: lift)
        .onAppear {
            guard shown < 1 || lift != 0 else { return }
            withAnimation(ArisActivityMotion.fadeIn) { shown = 1 }
            withAnimation(ArisActivityMotion.riseIn) { lift = 0 }
        }
    }

    /// A teammate's heading: avatar, name at 78%, "· n" at 43% and a hairline to the edge, 10.5 semibold at 42%
    /// (mockup .tm). One teammate's timeline has only the quiet day line instead (mockup .day: no hairline).
    @ViewBuilder
    private func heading(_ section: ArisActivityTab.Section, first: Bool) -> some View {
        if let mate = section.teammate {
            HStack(spacing: 7) {
                ArisTeammateAvatar(name: mate, id: ArisActivityTab.teammateIds(model.items)[mate], size: 16)
                Text(section.title).foregroundStyle(.white.opacity(0.78))
                Text("· \(section.rows.count)").monospacedDigit().foregroundStyle(.white.opacity(0.43))
                Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            }
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.white.opacity(0.42))
            // Names are never cut: a long one wraps.
            .fixedSize(horizontal: false, vertical: true)
            .padding(EdgeInsets(top: first ? 4 : 12, leading: 12, bottom: 6, trailing: 12))
        } else {
            ArisSideStyle.dayHeading(section.title, first: first).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One entry (mockup .rowB): the time, the rail and its node, the summary (two lines at most), and when it has an undo
/// the 되돌리기 pill, which becomes 되돌림 once done.
private struct ArisActivityRow: View {
    let item: ArisActivityItem
    let style: ArisActivityTab.Style
    let time: String
    let busy: Bool
    let undo: () -> Void
    @State private var hovering = false

    private static let hairline = Color.white.opacity(0.08)

    var body: some View {
        let faded = style.faded
        HStack(alignment: .top, spacing: 10) {
            Text(time)
                .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.43))
                .padding(.top, 2)
                .frame(width: 30, alignment: .leading)
                .opacity(faded ? 0.38 : 1)
            VStack(alignment: .leading, spacing: 0) {
                Text(ArisActivityWords.shown(item.summary))
                    .font(.system(size: 12.5, weight: .medium))
                    .lineSpacing(2.5)
                    .foregroundStyle(.white.opacity(0.94))
                    .strikethrough(faded, color: .white.opacity(0.35))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    // CSS line-height 1.4 (17.5): SwiftUI's 15-point line plus 2.5 between lines and half above and below.
                    .padding(.vertical, 1.25)
                    .opacity(faded ? 0.38 : 1)
                if style.hasMeta || item.checked == true {
                    HStack(spacing: 6) {
                        // The automatic check let it run: the same quiet mark as its receipt's (ArisCheckedMark).
                        if item.checked == true { ArisCheckedMark(english: ArisUIWords.english).frame(height: 20).padding(.leading, -4) }
                        Spacer(minLength: 0)
                        if style.hasMeta { ArisUndoSwap(undone: faded, busy: busy, undo: undo) }
                    }
                    .frame(minHeight: 20)
                    .padding(.top, 4)
                }
            }
            .padding(.leading, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(EdgeInsets(top: 6, leading: 12, bottom: 8, trailing: 10))
        .background(alignment: .topLeading) { backdrop(faded: faded) }
        .animation(ArisActivityMotion.fade, value: faded)
        .onHover { hovering = $0 }
        .animation(ArisSideStyle.cssEase(0.14), value: hovering)
        .help(ArisActivityTab.jobTip(item.job))
    }

    /// The hover fill, then the rail through the row at x 40 and the node on it (white 38%; a hollow ring once undone).
    private func backdrop(faded: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12, style: .circular).fill(hovering ? ArisSideStyle.rowHover : .clear)
            Self.hairline.frame(width: 1).frame(maxHeight: .infinity).padding(.leading, 40)
            ZStack {
                Circle().fill(.white.opacity(faded ? 0 : 0.38))
                Circle().strokeBorder(.white.opacity(faded ? 0.3 : 0), lineWidth: 1)
            }
            .frame(width: 6, height: 6)
            .padding(.leading, 37.5)
            .padding(.top, 10)
        }
    }
}

/// 되돌리기 and 되돌림 in one place; only the shown one is hit-testable, and they swap by a 200 ms cross-blur.
private struct ArisUndoSwap: View {
    let undone: Bool
    let busy: Bool
    let undo: () -> Void

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: undo) {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.uturn.backward").font(.system(size: 8.5, weight: .bold))
                    Text(ArisActivityTab.undoWord())
                }
            }
            .buttonStyle(ArisUndoPillStyle())
            .disabled(busy || undone)
            .opacity(undone ? 0 : busy ? 0.5 : 1)
            .blur(radius: undone ? 2 : 0)
            .allowsHitTesting(!undone)
            .help(ArisActivityTab.undoWord())
            Text(ArisUIWords.text("되돌림", "Undone"))
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.43))
                .opacity(undone ? 1 : 0)
                .blur(radius: undone ? 0 : 2)
        }
        .animation(ArisActivityMotion.swap, value: undone)
        .animation(ArisActivityMotion.swap, value: busy)
    }
}

/// The text pill (mockup .rowB .undo-btn): 20 tall, 7 in, white 6% (10% hovered, 16% pressed), 10.5 semibold at 62%
/// (95% hovered); a press dips to 0.93 over 140 ms.
private struct ArisUndoPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Pill(configuration: configuration)
    }

    private struct Pill: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            let pressed = configuration.isPressed
            configuration.label
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(hovering || pressed ? 0.95 : 0.62))
                .padding(.horizontal, 7)
                .frame(height: 20)
                .background(Capsule().fill(.white.opacity(pressed ? 0.16 : hovering ? 0.1 : 0.06)))
                .contentShape(Capsule())
                .scaleEffect(pressed ? 0.93 : 1)
                .animation(ArisActivityMotion.press, value: pressed)
                .animation(ArisSideStyle.cssEase(0.14), value: hovering)
                .onHover { hovering = $0 }
        }
    }
}
