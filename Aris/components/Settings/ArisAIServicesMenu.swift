//
//  ArisAIServicesMenu.swift
//  Aris
//
//  AI 서비스's dropdown, drawn over the whole window (as mockup ai-services-D-menu sets it): r16, 8 inside, 4 from
//  its button, as wide as the button (240 to 360), at most 300 tall
//  with the list scrolling between a fixed search field and a fixed foot; items r8, 10 × 12, 14/500 with an 11-pt line
//  under, small trailing text, and a 16-pt blue check. It opens under its button, or above it when there is no room,
//  in from 4 pt lower at 0.97 over 150 ms. Arrows move the one highlight and the list follows it, return picks, esc closes.
//

import SwiftUI

struct ArisAIMenuHost: View {
    @Environment(\.arisSettingsStill) private var still
    @ObservedObject var model: ArisAIServicesModel

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            ZStack(alignment: .topLeading) {
                if let open = model.menu, let menu = model.openMenu {
                    Color.black.opacity(0.0001).onTapGesture { model.menu = nil }
                    ArisAIMenuPanel(menu: menu, open: open, anchor: open.anchor.offsetBy(dx: -origin.x, dy: -origin.y), bounds: proxy.size, model: model)
                        .id(open.kind)
                        // It leaves with a fade; how it arrives is the panel's own (from the edge it hangs on).
                        .transition(.asymmetric(insertion: .identity, removal: .opacity))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .animation(still || ArisSettingsMotion.reduced ? nil : .easeOut(duration: 0.15), value: model.menu?.kind)
    }
}

enum ArisAIMenuMetrics {
    static let gap: CGFloat = 4
    static let maxHeight: CGFloat = 300
    static let minWidth: CGFloat = 240
    static let maxWidth: CGFloat = 360
    static let edge: CGFloat = 12

    /// Where the panel grows from: the corner of its button it hangs on (emil-design-eng: a popover scales from its
    /// trigger, never from its own middle).
    static func origin(place: Place, anchor: CGRect) -> UnitPoint {
        let right = abs(place.x + place.width - anchor.maxX) < abs(place.x - anchor.minX)
        return UnitPoint(x: right ? 1 : 0, y: place.below ? 0 : 1)
    }

    struct Place: Equatable {
        let x: CGFloat
        let width: CGFloat
        /// The most the panel may be tall.
        let room: CGFloat
        let below: Bool
    }

    /// Where a menu of `natural` height goes for a button at `anchor` in a window of `bounds`: under the button when it
    /// fits (or there is more room than above), never over it; a button on the window's right half opens leftwards.
    static func place(anchor: CGRect, bounds: CGSize, natural: CGFloat) -> Place {
        let width = min(maxWidth, max(minWidth, anchor.width))
        let below = bounds.height - anchor.maxY - gap - edge, above = anchor.minY - gap - edge
        let wanted = min(maxHeight, natural)
        let down = below >= wanted || below >= above
        let room = max(120, min(maxHeight, down ? below : above))
        var x = anchor.midX > bounds.width / 2 ? anchor.maxX - width : anchor.minX
        x = max(edge, min(x, bounds.width - edge - width))
        return Place(x: x, width: width, room: room, below: down)
    }
}

private struct ArisAIMenuPanel: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    @Environment(\.arisSettingsStill) private var still
    let menu: ArisAIMenu
    let open: ArisAIServicesModel.OpenMenu
    let anchor: CGRect
    let bounds: CGSize
    @ObservedObject var model: ArisAIServicesModel
    @State private var listHeight: CGFloat = 0
    @State private var offset: CGFloat = 0
    /// The entrance has played (from 4 pt off and 0.97, 150 ms ease-out).
    @State private var arrived = false
    @FocusState private var focus: Focus?

    /// The one highlighted row (ArisAIMenuHighlight): a key or the pointer's moving puts it there.
    private var highlighted: String? { open.highlight.id }

    private enum Focus { case search, list }

    private var headHeight: CGFloat { menu.search == nil ? 0 : 40 }
    private var footHeight: CGFloat {
        (menu.foot.isEmpty ? 0 : 9 + CGFloat(menu.foot.count) * 38) + (menu.source == nil ? 0 : 19 + (menu.foot.isEmpty ? 5 : 0))
    }

    var body: some View {
        let natural = listHeight + headHeight + footHeight + 16
        let place = ArisAIMenuMetrics.place(anchor: anchor, bounds: bounds, natural: natural)
        let visible = max(40, min(listHeight, place.room - headHeight - footHeight - 16))
        let height = visible + headHeight + footHeight + 16
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            if let placeholder = menu.search { search(placeholder).padding(.bottom, 4) }
            list(visible: visible)
            if !menu.foot.isEmpty || menu.source != nil { foot }
        }
        .padding(8)
        .frame(width: place.width, alignment: .leading)
        .background(shape.fill(palette.menu))
        .background(.ultraThinMaterial, in: shape)
        .overlay(shape.strokeBorder(palette.menuBorder, lineWidth: 1))
        // One shadow for the whole panel (ungrouped, a highlighted row would cast its own onto it).
        .compositingGroup()
        .shadow(color: palette.menuShadow, radius: 25, y: 18)
        // It grows from the edge it hangs on: down from its button's bottom, or up from its top when it opens above.
        .scaleEffect(entered ? 1 : 0.97, anchor: ArisAIMenuMetrics.origin(place: place, anchor: anchor))
        .offset(x: place.x, y: (place.below ? anchor.maxY + ArisAIMenuMetrics.gap : anchor.minY - ArisAIMenuMetrics.gap - height) + (entered ? 0 : place.below ? 4 : -4))
        .opacity(listHeight == 0 || !entered ? 0 : 1)
        .focusable()
        .focusEffectDisabled()
        .focused($focus, equals: .list)
        .onKeyPress(.downArrow) { model.moveHighlight(1); return .handled }
        .onKeyPress(.upArrow) { model.moveHighlight(-1); return .handled }
        .onKeyPress(.return) { pickHighlighted() }
        .onKeyPress(.space) { focus == .list ? pickHighlighted() : .ignored }
        .onKeyPress(phases: .down) { press in typeAhead(press) }
        .onExitCommand { model.menu = nil }
        .onAppear {
            model.menu?.highlight = ArisAIMenuHighlight.opening(menu)
            focus = menu.search == nil ? .list : .search
            withAnimation(plain ? nil : .easeOut(duration: 0.15)) { arrived = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    // MARK: Parts

    private func search(_ placeholder: String) -> some View {
        ArisAITextField(placeholder: placeholder, text: Binding(get: { open.query }, set: { model.menu?.query = $0 }), leading: 32)
            .focused($focus, equals: .search)
            .overlay(alignment: .leading) {
                Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium)).foregroundStyle(palette.ink3).padding(.leading, 11).allowsHitTesting(false)
            }
    }

    private var entries: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(menu.entries.enumerated()), id: \.offset) { index, entry in
                switch entry {
                case .group(let title):
                    Text(w.dotted(title)).font(.system(size: 11, weight: .medium)).foregroundStyle(palette.ink3)
                        .padding(.horizontal, 12).padding(.top, index == 0 ? 4 : 8).padding(.bottom, 4)
                        .accessibilityAddTraits(.isHeader)
                case .separator:
                    Rectangle().fill(palette.line).frame(height: 1).padding(4)
                case .note(let text):
                    Text(w(text)).font(.system(size: 12)).foregroundStyle(palette.ink3).padding(.horizontal, 12).padding(.vertical, 8)
                case .item(let item):
                    ArisAIMenuRow(item: item, highlighted: highlighted == item.id, playing: model.state.ui.playing == item.id, model: model)
                        .id(item.id)
                }
            }
        }
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { listHeight = proxy.size.height }
                .onChange(of: proxy.size.height) { _, next in listHeight = next }
                .onChange(of: proxy.frame(in: .named("arisAIMenuList")).minY) { _, next in offset = next }
        })
    }

    /// A small still chevron at an edge that hides more rows (ArisAIMenuEdges): the fade alone shows nothing over a
    /// separator or a gap.
    private func edgeHint(_ symbol: String, shown: Bool, at edge: Alignment) -> some View {
        Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.ink3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge)
            .opacity(shown ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func list(visible: CGFloat) -> some View {
        if still {
            entries.frame(height: visible, alignment: .top).clipped()
                .overlay { edgeHint("chevron.compact.down", shown: ArisAIMenuEdges.more(listHeight: listHeight, visible: visible, offset: 0).below, at: .bottom) }
        } else {
            // A soft fade where more items hide (the mockup's scroll edges), and a chevron on it.
            let edges = ArisAIMenuEdges.more(listHeight: listHeight, visible: visible, offset: offset)
            ScrollViewReader { proxy in
                ScrollView { entries }
                    .coordinateSpace(name: "arisAIMenuList")
                    .scrollIndicators(.never)
                    .frame(height: visible)
                    .mask(VStack(spacing: 0) {
                        LinearGradient(colors: [edges.above ? .clear : .black, .black], startPoint: .top, endPoint: .bottom).frame(height: 24)
                        Rectangle()
                        LinearGradient(colors: [.black, edges.below ? .clear : .black], startPoint: .top, endPoint: .bottom).frame(height: 24)
                    })
                    .overlay { edgeHint("chevron.compact.up", shown: edges.above, at: .top) }
                    .overlay { edgeHint("chevron.compact.down", shown: edges.below, at: .bottom) }
                    // A key moved the highlight: the list brings that row to its middle, clear of the fading edges
                    // (it used to leave the visible rows, so nothing looked selected).
                    .onChange(of: open.highlight.keyMoves) { _, _ in
                        guard let id = open.highlight.id else { return }
                        withAnimation(ArisSettingsMotion.reduced ? nil : .easeOut(duration: 0.12)) { proxy.scrollTo(id, anchor: .center) }
                    }
                    // The list has its height: it opens with the chosen row in view.
                    .onChange(of: listHeight) { before, _ in
                        if before == 0, let id = ArisAIMenuHighlight.opening(menu).id { proxy.scrollTo(id, anchor: .center) }
                    }
            }
        }
    }

    private var foot: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !menu.foot.isEmpty {
                Rectangle().fill(palette.line).frame(height: 1).padding(.top, 4).padding(.bottom, 4)
                ForEach(menu.foot) { item in
                    ArisAIMenuRow(item: item, highlighted: highlighted == item.id, playing: false, model: model)
                }
            }
            if let source = menu.source {
                Text(w(source)).font(.system(size: 11)).foregroundStyle(palette.ink3).padding(.horizontal, 12).padding(.top, menu.foot.isEmpty ? 9 : 4).padding(.bottom, 2)
            }
        }
    }

    // MARK: Keys

    /// Opened with a key, drawn offscreen, or under Reduce Motion: it is simply there.
    private var plain: Bool { still || open.byKey || ArisSettingsMotion.reduced }
    private var entered: Bool { arrived || plain }

    /// A letter typed while the list (not its search field) has the keyboard moves the highlight to the next item
    /// that starts with it.
    private func typeAhead(_ press: KeyPress) -> KeyPress.Result {
        guard focus == .list, menu.search == nil, press.modifiers.isDisjoint(with: [.command, .control, .option]),
              let letter = press.characters.first, letter.isLetter || letter.isNumber else { return .ignored }
        model.typeAhead(String(letter)) { w.dotted($0) }
        return .handled
    }

    private func pickHighlighted() -> KeyPress.Result {
        guard let id = highlighted, ArisAIMenuHighlight.stops(menu).contains(id) else { return .ignored }
        model.pick(id)
        return .handled
    }
}

/// One item: its title and small line, the trailing text, the check; and beside it a sample's ▶ or a connection's ⋯.
private struct ArisAIMenuRow: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let item: ArisAIMenuItem
    let highlighted: Bool
    let playing: Bool
    @ObservedObject var model: ArisAIServicesModel
    @State private var moreFrame: CGRect = .zero

    var body: some View {
        HStack(spacing: 4) {
            Button { model.pick(item.id) } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(w.dotted(item.title)).font(.system(size: 14, weight: .medium)).foregroundStyle(item.action ? palette.desc : palette.title).lineLimit(1)
                        if item.subtitle != nil || item.code != nil { subtitle }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let tail = item.tail {
                        Text(w.dotted(tail)).font(.system(size: 11, weight: .medium)).foregroundStyle(palette.ink3).lineLimit(1).fixedSize()
                    }
                    if !item.action {
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(palette.accent)
                            .frame(width: 16, height: 16).opacity(item.checked ? 1 : 0)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(highlighted && !item.disabled ? palette.menuHover : .clear))
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .animation(.easeInOut(duration: 0.15), value: highlighted)
            }
            .buttonStyle(ArisPressScale(scale: ArisPressScale.light))
            .disabled(item.disabled)
            .opacity(item.disabled ? 0.45 : 1)
            // The pointer's moving puts the one highlight on this row; a row has none of its own.
            .onContinuousHover { phase in
                if case .active = phase { model.hoverMenu(item.id, over: true) } else { model.hoverMenu(item.id, over: false) }
            }
            .accessibilityAddTraits(item.checked ? .isSelected : [])
            .accessibilityHint(w.dotted(item.tail ?? ""))
            trailing
        }
    }

    private var subtitle: some View {
        let parts = [item.subtitle].compactMap { $0 }.filter { !$0.isEmpty }.map { w.dotted($0) }
        var text = Text(parts.joined()).foregroundColor(palette.desc)
        if let code = item.code {
            text = text + Text(parts.isEmpty ? "" : " · ").foregroundColor(palette.desc) + Text(code).font(.system(size: 11, design: .monospaced)).foregroundColor(palette.ink3)
        }
        // A second line when one isn't enough: beside "Not installed" the line ended in "Answers through…".
        return text.font(.system(size: 11)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var trailing: some View {
        switch item.trailing {
        case .play(let url):
            ArisAISampleButton(playing: playing, name: item.title, enabled: !item.disabled) { model.perform(.sample(id: item.id, url: url)) }
        case .more:
            Button { model.menu = .init(kind: .connectionMore(String(item.id.dropFirst(4))), anchor: moreFrame) } label: {
                Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.ink3).frame(width: 28, height: 28)
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(ArisPressScale())
            .modifier(ArisAIFrameReader(frame: $moreFrame))
            .accessibilityLabel(w("\(item.title) 더 보기"))
        case nil:
            EmptyView()
        }
    }
}

/// A voice sample's button (28 square, r8): ▶, or ■ while it plays.
struct ArisAISampleButton: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let playing: Bool
    let name: String
    var enabled = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: playing ? "stop.fill" : "play.circle").font(.system(size: playing ? 10 : 13, weight: .medium))
                .foregroundStyle(playing || hovering ? palette.title : palette.ink3)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hovering ? palette.menuHover : .clear))
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .animation(.easeInOut(duration: 0.15), value: hovering)
        }
        .buttonStyle(ArisPressScale())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .onHover { hovering = $0 && enabled }
        .accessibilityLabel(w(playing ? "\(name) 그만 듣기" : "\(name) 미리 듣기"))
    }
}
