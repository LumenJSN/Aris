//
//  ArisAIServicesMenu.swift
//  Aris
//
//  The settings window's dropdown, drawn over the whole window, to the measured dropdown (ArisMenuLook): r16, 8 inside,
//  a 1-pt line and one 0 25 50 −12 shadow at black .1; items r8, 10 × 12, 14/500 with an 11-pt line under, small
//  trailing text. The AI 서비스 page's menus hang 4 under their button, as wide as it (240 to 360), at most 300 tall,
//  and mark the chosen item with a 16-pt blue check; a settings row's hang 8 under, flush with its right edge, as wide
//  as their longest item (at least 220), at most 320 tall, and light the chosen item in glass instead. The list scrolls
//  between a fixed search field and a fixed foot. It opens under its button, or above it when there is no room, and is
//  there at once and gone at once (the measured panel has no animation). Arrows move the one highlight and the list
//  follows it, return picks, esc closes.
//

import AppKit
import SwiftUI

struct ArisAIMenuHost: View {
    @ObservedObject var model: ArisAIServicesModel

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            ZStack(alignment: .topLeading) {
                if let open = model.menu, let menu = model.openMenu {
                    Color.black.opacity(0.0001).onTapGesture { model.menu = nil }
                    // No entrance and no exit (ArisMenuLook.animates).
                    ArisAIMenuPanel(menu: menu, open: open, anchor: open.anchor.offsetBy(dx: -origin.x, dy: -origin.y), bounds: proxy.size, model: model)
                        .id(open.kind)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }
}

enum ArisAIMenuMetrics {
    static let gap: CGFloat = ArisMenuLook.pageGap
    static let maxHeight: CGFloat = ArisMenuLook.pageMaxHeight
    static let minWidth: CGFloat = 240
    static let maxWidth: CGFloat = 360
    static let edge: CGFloat = ArisMenuLook.edge

    struct Place: Equatable {
        let x: CGFloat
        let width: CGFloat
        /// The most the panel may be tall.
        let room: CGFloat
        let below: Bool
    }

    /// Where a menu of `natural` height goes for a button at `anchor` in a window of `bounds`: under the button when it
    /// fits (or there is more room than above), never over it. The page's: a button on the window's right half opens
    /// leftwards. A settings row's (`radio`, `content`: its longest item's width): its right edge on the button's.
    static func place(anchor: CGRect, bounds: CGSize, natural: CGFloat, radio: Bool = false, content: CGFloat = 0) -> Place {
        let gap = radio ? ArisMenuLook.settingsGap : gap, tallest = radio ? ArisMenuLook.settingsMaxHeight : maxHeight
        let width = radio ? min(bounds.width - 2 * edge, max(ArisMenuLook.settingsMinWidth, content)) : min(maxWidth, max(minWidth, anchor.width))
        let below = bounds.height - anchor.maxY - gap - edge, above = anchor.minY - gap - edge
        let wanted = min(tallest, natural)
        let down = below >= wanted || below >= above
        let room = max(120, min(tallest, down ? below : above))
        var x = radio || anchor.midX > bounds.width / 2 ? anchor.maxX - width : anchor.minX
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
    @FocusState private var focus: Focus?

    /// The one highlighted row (ArisAIMenuHighlight): a key or the pointer's moving puts it there.
    private var highlighted: String? { open.highlight.id }

    private enum Focus { case search, list }

    private var headHeight: CGFloat { menu.search == nil ? 0 : 40 }
    private var footHeight: CGFloat {
        (menu.foot.isEmpty ? 0 : 2 * ArisMenuLook.separatorMargin + 1 + CGFloat(menu.foot.count) * 38) + (menu.source == nil ? 0 : 19 + (menu.foot.isEmpty ? 5 : 0))
    }

    var body: some View {
        let inset = ArisMenuLook.inset, padding = 2 * inset
        let natural = listHeight + headHeight + footHeight + padding
        let place = ArisAIMenuMetrics.place(anchor: anchor, bounds: bounds, natural: natural, radio: menu.radio, content: contentWidth)
        let visible = max(40, min(listHeight, place.room - headHeight - footHeight - padding))
        let height = visible + headHeight + footHeight + padding
        let gap = menu.radio ? ArisMenuLook.settingsGap : ArisAIMenuMetrics.gap
        let shape = RoundedRectangle(cornerRadius: ArisMenuLook.radius, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            if let placeholder = menu.search { search(placeholder).padding(.bottom, 4) }
            list(visible: visible)
            if !menu.foot.isEmpty || menu.source != nil { foot }
        }
        .padding(inset)
        .frame(width: place.width, alignment: .leading)
        .background(shape.fill(palette.menu))
        .background(.ultraThinMaterial, in: shape)
        .overlay(shape.strokeBorder(palette.menuBorder, lineWidth: 1))
        .background(ArisMenuShadow(shape: shape, fill: palette.menu))
        .offset(x: place.x, y: place.below ? anchor.maxY + gap : anchor.minY - gap - height)
        .opacity(listHeight == 0 ? 0 : 1)
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
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    /// A settings row's menu is as wide as its longest item: the title at 14/500 or its line at 11, the row's 12 a
    /// side, the check's room (none: its chosen row is lit), the panel's 8 a side.
    private var contentWidth: CGFloat {
        guard menu.radio else { return 0 }
        let title = NSFont.systemFont(ofSize: ArisMenuLook.rowFont, weight: .medium), line = NSFont.systemFont(ofSize: 11)
        let widest = menu.items.map { item in
            max((w.dotted(item.title) as NSString).size(withAttributes: [.font: title]).width,
                (w.dotted(item.subtitle ?? "") as NSString).size(withAttributes: [.font: line]).width)
        }.max() ?? 0
        return ceil(widest) + 2 * ArisMenuLook.rowPaddingH + 2 * ArisMenuLook.inset + 2
    }

    // MARK: Parts

    private func search(_ placeholder: String) -> some View {
        ArisAITextField(placeholder: placeholder, text: Binding(get: { open.query }, set: { model.menu?.query = $0 }), leading: 32)
            .focused($focus, equals: .search)
            .overlay(alignment: .leading) {
                ArisLineIcon("magnifyingglass", size: 14).foregroundStyle(palette.ink3).padding(.leading, 11).allowsHitTesting(false)
            }
    }

    private var entries: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(menu.entries.enumerated()), id: \.offset) { index, entry in
                switch entry {
                case .group(let title):
                    // DropdownMenuLabel: 12/600, upper case, .05 em apart, gray-500 / gray-400, 12 × 8.
                    Text(w.dotted(title)).font(.system(size: ArisMenuLook.labelFont, weight: .semibold)).textCase(.uppercase)
                        .tracking(ArisMenuLook.labelFont * ArisMenuLook.labelTracking).foregroundStyle(ArisMenuLook.label.color(palette.dark))
                        .padding(.horizontal, ArisMenuLook.labelPaddingH).padding(.vertical, ArisMenuLook.labelPaddingV)
                        .accessibilityAddTraits(.isHeader)
                case .separator:
                    ArisMenuSeparator()
                case .note(let text):
                    Text(w(text)).font(.system(size: 12)).foregroundStyle(palette.ink3).padding(.horizontal, 12).padding(.vertical, 8)
                case .item(let item):
                    ArisAIMenuRow(item: item, highlighted: highlighted == item.id, playing: model.state.ui.playing == item.id, radio: menu.radio, model: model)
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
        ArisLineIcon(symbol, size: 13, stroke: 2.25).foregroundStyle(palette.ink3)
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
                ArisMenuSeparator()
                ForEach(menu.foot) { item in
                    ArisAIMenuRow(item: item, highlighted: highlighted == item.id, playing: false, radio: menu.radio, model: model)
                }
            }
            if let source = menu.source {
                Text(w(source)).font(.system(size: 11)).foregroundStyle(palette.ink3).padding(.horizontal, 12).padding(.top, menu.foot.isEmpty ? 9 : 4).padding(.bottom, 2)
            }
        }
    }

    // MARK: Keys

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
    /// A settings row's menu: the chosen item is lit in glass, with no check.
    var radio = false
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
                    if !item.action, !radio {
                        // Check `h-4 w-4`: a 2-pt line in a 24 box drawn at 16.
                        ArisLineIcon("checkmark", size: 14).foregroundStyle(palette.accent)
                            .frame(width: ArisMenuLook.checkBox, height: ArisMenuLook.checkBox).opacity(item.checked ? 1 : 0)
                    }
                }
                .padding(.horizontal, ArisMenuLook.rowPaddingH).padding(.vertical, ArisMenuLook.rowPaddingV)
                .background {
                    let shape = RoundedRectangle(cornerRadius: ArisMenuLook.rowRadius, style: .continuous)
                    ZStack {
                        shape.fill(highlighted && !item.disabled ? ArisMenuLook.rowHover.color(palette.dark) : .clear)
                        if radio, item.checked { ArisRadioGlass(radius: ArisMenuLook.rowRadius) }
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: ArisMenuLook.rowRadius, style: .continuous))
                .animation(.easeInOut(duration: 0.15), value: highlighted)
            }
            .buttonStyle(ArisPressScale(scale: ArisPressScale.measured))
            .disabled(item.disabled)
            .opacity(item.disabled ? ArisMenuLook.disabledOpacity : 1)
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
                ArisLineIcon("ellipsis", size: 14, stroke: 2.25).foregroundStyle(palette.ink3).frame(width: 28, height: 28)
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
            ArisLineIcon(playing ? "stop.fill" : "play.circle", size: playing ? 12 : 16)
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

extension ArisMenuLook.Shade {
    var color: Color { Color(arisHex: hex, alpha) }
}

extension ArisMenuLook.Pair {
    func color(_ dark: Bool) -> Color { pick(dark).color }
}

/// The panel's one shadow, `0 25 50 −12` at black .1: cast by a copy of the panel 12 smaller on every side (SwiftUI's
/// shadow has no spread), hidden behind the panel.
struct ArisMenuShadow<S: InsettableShape>: View {
    let shape: S
    let fill: Color
    var shadow = ArisMenuLook.shadow

    var body: some View {
        shape.inset(by: -shadow.spread).fill(fill)
            .shadow(color: shadow.shade.color, radius: shadow.blur / 2, y: shadow.y)
    }
}

/// DropdownMenuSeparator: 1 pt, edge to edge, 6 above and below.
struct ArisMenuSeparator: View {
    @Environment(\.arisPalette) private var palette

    var body: some View {
        Rectangle().fill(ArisMenuLook.separator.color(palette.dark)).frame(height: 1).padding(.vertical, ArisMenuLook.separatorMargin)
    }
}

/// A settings menu's chosen item (RadioItem checked): the sheen from left to right (edge, middle, edge) and the four
/// shades of its box-shadow, top shade and bottom light inside, a soft drop under, a glow along the inside edge.
struct ArisRadioGlass: View {
    @Environment(\.arisPalette) private var palette
    let radius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let dark = palette.dark, edge = ArisMenuLook.radioEdge.color(dark), middle = ArisMenuLook.radioMiddle.color(dark)
        let shades = dark ? ArisMenuLook.radioShadowsDark : ArisMenuLook.radioShadowsLight
        ZStack {
            ForEach(Array(shades.enumerated()), id: \.offset) { _, shade in
                if !shade.inset {
                    shape.inset(by: -shade.spread).fill(Color.black).shadow(color: shade.shade.color, radius: shade.blur / 2, y: shade.y)
                        .mask(Rectangle().padding(-40).overlay(shape.fill(Color.black).blendMode(.destinationOut)).compositingGroup())
                }
            }
            shape.fill(LinearGradient(colors: [edge, middle, edge], startPoint: .leading, endPoint: .trailing))
            ForEach(Array(shades.enumerated()), id: \.offset) { _, shade in
                if shade.inset { ArisInsetShade(shape: shape, shadow: shade) }
            }
        }
        .allowsHitTesting(false)
    }
}

/// One inset box-shadow: a ring outside `shape` (grown by its blur), shifted by its offset, blurred and kept inside.
struct ArisInsetShade<S: InsettableShape>: View {
    let shape: S
    let shadow: ArisMenuLook.Shadow

    var body: some View {
        let ring = max(1, shadow.blur) * 2 + abs(shadow.y) + 4
        shape.inset(by: shadow.spread - ring / 2).stroke(shadow.shade.color, lineWidth: ring)
            .offset(y: shadow.y)
            .blur(radius: shadow.blur / 2)
            .clipShape(shape)
    }
}
