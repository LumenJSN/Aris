//
//  ArisSidePanelView.swift
//  Aris
//
//  One side notch, the history notch: one outline (ArisSideOutline, animated by ArisSideLayers) that is nothing
//  at rest, a 16-point black sliver when there's something to report or the pointer touches the edge (18 under it),
//  and grows into the 232 × 580 panel when the sliver is clicked, revealing the panel's content as it grows. The
//  header row is a search pill (here: the tabs) and its keep-open lock.
//

import SwiftUI

struct ArisSidePanelView: View {
    let edge: ArisSidePanels.Edge
    @ObservedObject private var panels = ArisSidePanels.shared

    private var isOpen: Bool { panels.open.contains(edge) }
    private var size: CGSize { ArisGlass.sideSize }

    /// Kept a moment after closing so the outline can close over it; then gone, so nothing in it (lists,
    /// clocks, relative times) keeps updating while it can't be seen.
    @State private var contentShown = false

    /// The panel's content, centred; the outline (ArisSideLayers) fills it, masks it and carries the glow.
    var body: some View {
        Group { if contentShown { panel } else { Color.clear } }
            .task(id: isOpen) {
                if isOpen { contentShown = true; return }
                try? await Task.sleep(for: .milliseconds(260))
                if !Task.isCancelled && !isOpen { contentShown = false }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            // No fade: the outline reveals and clips the content as it grows and shrinks.
            .allowsHitTesting(isOpen)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge == .left ? .leading : .trailing)
            .preferredColorScheme(.dark)
    }

    private var panel: some View {
        // The header's pill ends at 85 and the list's first row starts at 95 (header 91 + 4).
        VStack(alignment: .leading, spacing: ArisSideLook.listTop - ArisSideLook.headerTop - ArisSideLook.headerPill) {
            switch edge {
            case .left: ArisLeftPanel()
            case .right: ArisRightPanel()
            }
        }
        // The header clears the 31-point shoulder by 18; 14 in on the edge side, 20 on the other.
        .padding(.top, ArisSideLook.headerTop)
        .padding(.bottom, ArisSideLook.panelBottomInset)
        .padding(.leading, edge == .left ? ArisSideLook.headerEdgeSide : ArisSideLook.headerFarSide)
        .padding(.trailing, edge == .left ? ArisSideLook.headerFarSide : ArisSideLook.headerEdgeSide)
    }
}

/// What sits over the outline, unmasked: after a rest, the popover saying what the sliver's dots are (the dots
/// themselves are drawn by ArisSideLayers, inside the outline's clip).
struct ArisSideOverlayView: View {
    let edge: ArisSidePanels.Edge
    @ObservedObject private var panels = ArisSidePanels.shared
    @ObservedObject private var firstTries = ArisFirstTries.shared

    private var alignment: Alignment { edge == .left ? .leading : .trailing }

    var body: some View {
        let isOpen = panels.open.contains(edge)
        let offset = panels.sliverOffset[edge] ?? 0
        ZStack(alignment: alignment) {
            // Right after the first-run setup the left sliver shows itself once, with two words beside it (ArisFirstTries).
            if edge == .left, firstTries.sliverShown, !isOpen {
                ArisFirstTriesSliverLabel()
                    .padding(.leading, ArisSidePanels.popoverLeft)
                    .offset(y: offset)
                    .transition(.opacity)
            }
            if panels.popover.contains(edge) && !isOpen {
                ArisSliverPopover(edge: edge)
                    .frame(width: ArisSidePanels.popoverSize.width)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(edge == .left ? .leading : .trailing, ArisSidePanels.popoverLeft)
                    .offset(y: offset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .animation(.easeOut(duration: 0.18).delay(0.06), value: firstTries.sliverShown)
        .preferredColorScheme(.dark)
    }
}

/// The sliver's numbers: 16 wide (18 under the pointer), 48 tall or enough for its dots (6 points, 8 apart, at
/// most five). It comes out only while the pointer is at the edge.
enum ArisSideSliver {
    enum Dot: Equatable { case idle, working, waiting, error, completed, limit }

    /// What each side's sliver shows, at most five: a dot and, for its popover, what the dot is.
    /// Left: the AI sessions running (amber waiting on you, white working, red failed, blue finished, grey resting),
    /// orange when a plan is nearly used up, then recent Aris conversations in grey. Right: a deadline alert in amber,
    /// then upcoming Canvas deadlines and open to-dos in grey.
    @MainActor
    static func items(_ edge: ArisSidePanels.Edge) -> [(dot: Dot, title: String, state: String)] {
        var rows: [(dot: Dot, title: String, state: String)] = []
        // A tab turned off in settings reports nothing.
        let panels = ArisSidePanels.shared
        switch edge {
        case .left:
            let claude = ClaudeStore.shared
            let peak = ArisUsageModel.shared.peak
            if panels.shows(.usage), peak >= ClaudeUsage.warnAt[0] { rows.append((.limit, ArisSideTab.usage.name(), ArisUIWords.text("\(Int(peak))% 썼어요", "\(Int(peak))% used"))) }
            guard panels.shows(.history) else { break }
            for session in claude.sessionList {
                let dot: Dot
                if claude.approvals.contains(where: { $0.sessionId == session.id }) {
                    dot = .waiting
                } else {
                    switch session.state {
                    case .notification: dot = .waiting
                    case .error: dot = .error
                    case .happy: dot = .completed
                    case .thinking, .typing, .building, .juggling: dot = .working
                    case .idle, .sleeping: dot = .idle
                    }
                }
                rows.append((dot, session.title, label(dot)))
            }
            for turn in ArisController.shared.pastTurns.prefix(maxDots) {
                rows.append((.idle, turn.heard, turn.date.formatted(date: .omitted, time: .shortened)))
            }
        case .right:
            guard panels.shows(.todo) else { break }
            let todos = ArisTodoModel.shared
            if let alert = todos.alert { rows.append((.waiting, alert.due.title, ArisUIWords.text("마감 알림", "Due soon"))) }
            let now = Date()
            for due in todos.due.filter({ $0.at > now && $0.id != todos.alert?.due.id }).sorted(by: { $0.at < $1.at }) {
                rows.append((.idle, due.title, ArisUIDates.day(due.at)))
            }
            for item in todos.items {
                rows.append((.idle, item.title, ArisSideTab.todo.name()))
            }
        }
        return Array(rows.prefix(maxDots))
    }

    @MainActor
    static func dots(_ edge: ArisSidePanels.Edge) -> [Dot] { items(edge).map(\.dot) }

    static func label(_ dot: Dot) -> String {
        switch dot {
        case .idle: ArisUIWords.text("쉬는 중", "Resting")
        case .working: ArisUIWords.text("작업 중", "Working")
        case .waiting: ArisUIWords.text("기다리는 중", "Waiting for you")
        case .error: ArisUIWords.text("오류", "Error")
        case .completed: ArisUIWords.text("끝났어요", "Done")
        case .limit: ArisUIWords.text("한도 가까움", "Near the limit")
        }
    }

    static let dotSize: CGFloat = 6
    static let dotGap: CGFloat = 8
    static let maxDots = 5

    static func height(dots: Int) -> CGFloat {
        let count = CGFloat(min(maxDots, max(0, dots)))
        return max(48, count * dotSize + max(0, count - 1) * dotGap + 32)
    }
}

/// The sliver's popover: #0a0a0a, radius 12, a white-8% hairline, 220 wide, 26 from the edge, 8 in.
/// The shortcut that opens the panel, "↕ 끌어서 옮기기" over a hairline, then "사이드바 숨기기" with 10분 / 1시간 / 계속
/// (until it's opened again) as three 32-point keys.
struct ArisSliverPopover: View {
    let edge: ArisSidePanels.Edge
    @ObservedObject private var panels = ArisSidePanels.shared

    private static let dim = Color.white.opacity(0.64)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                // The shortcut opens the 클립보드 tab, so it's only offered while that tab is on.
                let byKey = edge == .left && panels.shows(.clipboard)
                let hint = ArisSideMenu.openHint(byKey: byKey)
                if !hint.lead.isEmpty { Text(hint.lead) }
                Text(hint.key).foregroundStyle(.white.opacity(0.92))
                if !hint.tail.isEmpty { Text(hint.tail) }
            }
            .font(.system(size: 11))
            .foregroundStyle(Self.dim)
            .frame(height: 20)
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
            Text(ArisUIWords.text("↕ 끌어서 옮기기", "↕ Drag to move"))
                .font(.system(size: 11))
                .foregroundStyle(Self.dim)
                .frame(height: 16, alignment: .top)
                .padding(.horizontal, 4)
                .padding(.bottom, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }
                .padding(.bottom, 8)
            HStack(spacing: 6) {
                Image(systemName: "clock").font(.system(size: 10, weight: .medium))
                Text(ArisUIWords.text("사이드바 숨기기", "Hide the sidebar")).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Self.dim)
            .frame(height: 16)
            .padding(.horizontal, 4)
            .padding(.bottom, 6)
            HStack(spacing: 4) {
                hideButton(ArisUIWords.text("10분", "10 min"), 600)
                hideButton(ArisUIWords.text("1시간", "1 hour"), 3600)
                hideButton(ArisUIWords.text("계속", "Always"), nil)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .circular).fill(Color(white: 0x0a / 255)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .circular).strokeBorder(.white.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 9, y: 6)
    }

    private func hideButton(_ title: String, _ seconds: TimeInterval?) -> some View {
        ArisPopoverKey(title: title) { panels.hide(edge, for: seconds) }
    }
}

/// One of the popover's keys: white 6%, 10% under the pointer, radius 6, 32 tall.
private struct ArisPopoverKey: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12)).foregroundStyle(.white.opacity(0.94))
                .frame(maxWidth: .infinity).frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 6, style: .circular).fill(.white.opacity(hovering ? 0.1 : 0.06)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// The header row: a 36-point search pill (white 6%, a lit top edge) holding the tabs, the current one on
/// a white-12% capsule, then the keep-open lock (30-point disc; locked it turns solid white with a dark glyph).
struct ArisSideTabs: View {
    let edge: ArisSidePanels.Edge
    let tabs: [(ArisSidePanels.Tab, String)]
    @Binding var current: ArisSidePanels.Tab
    /// An unselected tab's width: 34, or 28 where four tabs share the pill so the selected one keeps room for its label.
    var unselectedWidth: CGFloat = 34
    @ObservedObject private var panels = ArisSidePanels.shared
    @State private var lockHovered = false

    private var lockHint: String {
        panels.pinned.contains(edge) ? ArisUIWords.text("고정 풀기", "Let it close") : ArisUIWords.text("열어 두기", "Keep it open")
    }

    var body: some View {
        HStack(spacing: ArisSideLook.headerGap) {
            ArisSlidingTabs(
                items: tabs.map { tab, title in
                    .init(id: tab, icon: AnyView(Image(systemName: tab.symbol).font(.system(size: 12, weight: .medium))), title: title)
                },
                selection: $current, unselectedWidth: unselectedWidth, height: 28)
            .padding(4)
            .frame(height: ArisSideLook.headerPill)
            // The search pill has the lit top edge and the ring but no outer drop, so its edge reads crisp against
            // the panel.
            .background(ArisSideStyle.pill(Capsule(), drop: false))

            Button { panels.togglePin(edge) } label: { EmptyView() }
                .buttonStyle(ArisLockStyle(locked: panels.pinned.contains(edge)))
                .onHover { lockHovered = $0 }
                .accessibilityLabel(lockHint)
                // Its hint is drawn inside the panel, under the lock and reaching in from the panel's far side: macOS's
                // own tooltip came out past the screen's edge from the left panel and read "Keep it" (second upgrade run).
                .overlay(alignment: .topTrailing) {
                    if lockHovered {
                        ArisLockHint(text: lockHint)
                            .offset(y: ArisSideLook.headerPill + 6)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.14), value: lockHovered)
        }
        // The header is above the list (z-index 4), whose rows fade as they slide under it.
        .zIndex(1)
    }
}

/// The lock's hint: one short line on the panel's own pill, never wider than it needs.
private struct ArisLockHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.white.opacity(ArisSideLook.searchAlpha))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(ArisSideStyle.pill(Capsule(), drop: false))
    }
}

/// The keep-open lock: a quiet glyph on a glass disc that lifts on hover; locked, a warm-white disc with a
/// near-black glyph and a faint halo. Colours and shadows ease over 140 ms (CSS's `ease`). On top of that (the user's
/// pick "B", Emil Kowalski's numbers): the shackle springs open and drops shut (0.25 s, bounce 0.15) instead of
/// swapping, and a press dips to 0.97 with a strong ease-out over 140 ms.
private struct ArisLockStyle: ButtonStyle {
    let locked: Bool

    func makeBody(configuration: Configuration) -> some View {
        LockDisc(locked: locked, pressed: configuration.isPressed)
    }

    /// One disc whose colours ease together (background, glyph colour and shadows over 140 ms), so the fill
    /// changes as one colour rather than two layers crossfading; the shackle moves on its own spring.
    private struct LockDisc: View {
        let locked: Bool
        let pressed: Bool
        @State private var hovering = false

        private static let ink = Color(red: 18 / 255, green: 20 / 255, blue: 27 / 255)
        private static let shackle = Animation.spring(duration: 0.25, bounce: 0.15)
        private static let press = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.14)

        var body: some View {
            // Off: white 6% (12% hovered), glyph white 60% (90%). On: white 92% (100%), glyph near-black 92% (98%).
            let fill = Color.white.opacity(locked ? (hovering ? 1 : 0.92) : (hovering ? 0.12 : 0.06))
            let glyph = locked ? Self.ink.opacity(hovering ? 0.98 : 0.92) : Color.white.opacity(hovering ? 0.9 : 0.6)
            ZStack {
                Circle().fill(fill)
                    // 0 1px 3px rgba(0,0,0,.14) off; 0 1px 4px rgba(0,0,0,.28) and a 12px white 10% halo on.
                    .shadow(color: .black.opacity(locked ? 0.28 : 0.14), radius: locked ? 2 : 1.5, y: 1)
                    .shadow(color: .white.opacity(locked ? 0.1 : 0), radius: 6)
                // inset 0 1px 0: the lit top edge, white 5% off and 95% on.
                ArisTopBevel().fill(Color.white.opacity(locked ? 0.95 : 0.05))
                Circle().strokeBorder(Color.white.opacity(locked ? 0 : 0.015), lineWidth: 1)
                // lucide at 14 px, stroke 2.2 on its 24 grid; the shackle's openness animates on its own spring
                // (Reduce Motion: it changes at once, the colours still ease).
                ArisLucideLock(openness: locked ? 0 : 1)
                    .stroke(glyph, style: StrokeStyle(lineWidth: 2.2 * 14 / 24, lineCap: .round, lineJoin: .round))
                    .frame(width: 14, height: 14)
                    .animation(ArisTabMotion.reduceMotion ? nil : Self.shackle, value: locked)
            }
            .frame(width: 30, height: 30)
            .contentShape(Circle())
            .scaleEffect(pressed ? 0.97 : 1)
            .animation(Self.press, value: pressed)
            .animation(ArisSideStyle.cssEase(0.14), value: locked)
            .animation(ArisSideStyle.cssEase(0.14), value: hovering)
            .onHover { hovering = $0 }
        }
    }
}

/// The 1-point crescent along a circle's top inside edge (CSS `inset 0 1px 0`).
private struct ArisTopBevel: Shape {
    func path(in rect: CGRect) -> Path {
        Path(ellipseIn: rect).subtracting(Path(ellipseIn: rect.offsetBy(dx: 0, dy: 1)))
    }
}

/// The lucide Lock / LockOpen on their 24-unit grid: an 18 × 11 body (radius 2) and a radius-5 shackle. In
/// between, `openness` (0 locked, 1 open) shortens the right leg to nothing while the arc stops 11.5° short, and the
/// shackle lifts a little on the way, so it reads as springing open. A spring's overshoot past 0 or 1 just carries on.
struct ArisLucideLock: Shape {
    var openness: CGFloat

    var animatableData: CGFloat {
        get { openness }
        set { openness = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let k = min(rect.width, rect.height) / 24
        let t = openness
        let lift = sin(min(1, max(0, t)) * .pi) * 0.9 + max(0, t) * 0.3
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * k, y: rect.minY + y * k) }
        var path = Path(roundedRect: CGRect(origin: p(3, 11), size: CGSize(width: 18 * k, height: 11 * k)), cornerRadius: 2 * k, style: .circular)
        // a5 5 0 0 1 10 0 locked, 9.9 -1 open: over the top of a circle centred at (12, 7), raised by `lift`.
        let end = Angle.radians(Double(t) * atan2(-1, 4.9))
        let leg = max(0, 1 - t) * 4
        path.move(to: p(7, 11 - lift))
        path.addLine(to: p(7, 7 - lift))
        path.addArc(center: p(12, 7 - lift), radius: 5 * k, startAngle: .degrees(180), endAngle: .degrees(360) + end, clockwise: false)
        if leg > 0.01 { path.addLine(to: CGPoint(x: path.currentPoint!.x, y: path.currentPoint!.y + leg * k)) }
        return path
    }
}

/// The side notch surfaces.
enum ArisSideStyle {
    /// rgba(236, 239, 247, 0.62): placeholder text and quiet glyphs.
    static let placeholder = Color(red: 236 / 255, green: 239 / 255, blue: 247 / 255).opacity(0.62)
    /// A row under the pointer: rgba(150, 160, 210, 0.06).
    static let rowHover = Color(red: 150 / 255, green: 160 / 255, blue: 210 / 255).opacity(0.06)
    static let unreadBlue = Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255)

    /// CSS's `ease` (cubic-bezier(0.25, 0.1, 0.25, 1)), which the side notch's transitions use.
    static func cssEase(_ duration: Double) -> Animation { .timingCurve(0.25, 0.1, 0.25, 1, duration: duration) }

    /// White 6% with a 1-point lit top edge and a whisper of a ring, the composer's recipe. `drop`: the lock's soft
    /// 0 1px 3px rgba(0,0,0,.14) lift, which the search pill does not have.
    static func pill<S: Shape>(_ shape: S, drop: Bool = true) -> some View {
        shape.fill(.white.opacity(0.06))
            .overlay(shape.stroke(.white.opacity(0.015), lineWidth: 1))
            .overlay(shape.stroke(LinearGradient(colors: [.white.opacity(0.05), .clear], startPoint: .top, endPoint: .center), lineWidth: 1))
            .shadow(color: .black.opacity(drop ? 0.14 : 0), radius: 1.5, y: 1)
    }

    /// What a list says when it has nothing: 12 at white .52, centred, 28 above, 18 beside and 30 below.
    static func empty(_ words: String) -> some View {
        Text(words)
            .font(.system(size: ArisSideLook.emptySize))
            .foregroundStyle(.white.opacity(ArisSideLook.emptyAlpha))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(EdgeInsets(top: ArisSideLook.emptyInsets.top, leading: ArisSideLook.emptyInsets.side,
                                bottom: ArisSideLook.emptyInsets.bottom, trailing: ArisSideLook.emptyInsets.side))
    }

    /// The room a list's rows keep inside their scroller: under the header, the 22 points the
    /// scroller reaches up behind it, so the first row still starts at 95; at the end, 73 where the list runs to the
    /// panel's lower edge (`toEdge`), else the 34 its fade takes.
    static func listInsets(underHeader: Bool, toEdge: Bool) -> EdgeInsets {
        EdgeInsets(top: underHeader ? ArisSideLook.listRise : 0, leading: 0,
                   bottom: toEdge ? ArisSideLook.scrollEndPadding : ArisSideLook.fadeBottom, trailing: 0)
    }

    /// A day heading in a list: 10.5 semibold at 42%.
    static func dayHeading(_ title: String, first: Bool = false) -> some View {
        Text(title)
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.1)
            .foregroundStyle(.white.opacity(0.42))
            .padding(EdgeInsets(top: first ? 4 : 13, leading: 12, bottom: 5, trailing: 12))
    }
}

/// A list row: radius 12, 10 / 12 / 9 / 10 in, at least 42 tall, a faint lavender fill under the pointer.
struct ArisSideRow<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var hovering = false
    /// Preview harness only (side-debug-rows): every row filled strongly, to compare row shapes.
    @AppStorage("arisDebugRowFill") private var debugFill = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 9) { content() }
                .padding(EdgeInsets(top: 10, leading: 10, bottom: 9, trailing: 12))
                .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .circular)
                    .fill(debugFill ? Color(red: 150 / 255, green: 160 / 255, blue: 210 / 255).opacity(0.3) : hovering ? ArisSideStyle.rowHover : .clear))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .circular))
        }
        .buttonStyle(ArisRowPress())
        .onHover { hovering = $0 }
        .animation(ArisSideStyle.cssEase(0.14), value: hovering)
    }
}

/// The row press: scale(0.99) over 120 ms, no dimming.
private struct ArisRowPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(ArisSideStyle.cssEase(0.12), value: configuration.isPressed)
    }
}

/// A list's frame and fades: the scroller reaches up behind the header to where its mask is
/// clear (73 down the panel) and down to the panel's lower edge; the rows fade in over the 32 points under the header
/// and out over 34 points that end on the body's lower edge, so no row is cut through by the outline (side 1).
/// `underHeader`: the list is the first thing under the tabs; `toEdge`: nothing follows it.
/// Its rows keep ArisSideStyle.listInsets inside the scroller.
struct ArisSideListFrame: ViewModifier {
    var underHeader = true
    var toEdge = true

    func body(content: Content) -> some View {
        content
            .mask {
                GeometryReader { proxy in
                    LinearGradient(stops: ArisSideLook.listFade(height: proxy.size.height, underHeader: underHeader,
                                                                below: toEdge ? ArisSideLook.bodyEdgeInset : 0).map {
                        .init(color: .black.opacity($0.alpha), location: $0.location)
                    }, startPoint: .top, endPoint: .bottom)
                }
            }
            .padding(.top, underHeader ? -ArisSideLook.listRise : 0)
            .padding(.bottom, toEdge ? -ArisSideLook.panelBottomInset : 0)
    }
}
