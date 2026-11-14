//
//  ArisSettingsSidebar.swift
//  Aris
//
//  The settings sidebar (SETTINGS-REA.md §3.2–3.3): Aris's star greeting with how things are, the settings search, and
//  the pages in their three groups, 44-pt items with 20-pt line icons, and one liquid-glass highlight (the measured
//  fill and four shades, its rim only under the pointer) on the page on screen: it simply appears on the new item, with no slide. While something is typed the pages give way to the settings that match (ArisSettingsIndex);
//  choosing one opens its page, scrolls to it and highlights it once. Return picks the first, the arrows move.
//

import AppKit
import SwiftUI

/// The page on screen, the original settings screen opened in it, and where a search landed. Shared so the notch,
/// the to-do tab and the preview harness can open a page.
@MainActor
final class ArisSettingsNav: ObservableObject {
    static let shared = ArisSettingsNav()

    @Published var page: ArisSettingsPage = .aris
    /// A sheet or popover a page opens by itself (the preview harness): "language" or "voice".
    @Published var sheet: String?
    @Published var query = ""
    @Published private(set) var flash: ArisSettingsFlashTarget?
    /// Rises each time the window opens: the page's staggered entrance plays then, and only then (pick 4-A).
    @Published var opens = 0
    /// The page on screen was chosen with a key (Return on a search result): it is shown at once, with no fade.
    private(set) var byKey = false

    /// The pages opened at least once (a page added lately loses its 새 then), kept between launches where the app
    /// says (`remember`); the offscreen renders keep nothing.
    @Published private(set) var seen: Set<String> = []
    static let seenKey = "arisSettingsSeenPages"
    private var seenStore: UserDefaults?

    func remember(in store: UserDefaults) {
        seenStore = store
        seen = Set(store.stringArray(forKey: Self.seenKey) ?? [])
    }

    /// `page` is on screen in the open window.
    func markSeen(_ page: ArisSettingsPage) {
        guard page.isNew, !seen.contains(page.rawValue) else { return }
        seen.insert(page.rawValue)
        seenStore?.set(seen.sorted(), forKey: Self.seenKey)
    }

    /// The landing has played: it won't play again when the page is next drawn.
    func settle(_ token: Int) {
        if flash?.token == token { flash = nil }
    }

    /// Opens `page` and, with `anchor`, scrolls to that setting and highlights it.
    func go(_ page: ArisSettingsPage, anchor: String? = nil, byKey: Bool = false) {
        self.byKey = byKey
        self.page = page
        if let anchor { flash = ArisSettingsFlashTarget(id: anchor, token: (flash?.token ?? 0) + 1) }
    }
}

struct ArisSettingsSidebar: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    @Environment(\.arisSettingsStill) private var still
    @Environment(\.arisSettingsArt) private var art
    @ObservedObject var nav: ArisSettingsNav
    /// The line under Aris's name ("모두 잘 되고 있어요").
    let status: String
    /// The ids a search may land on now (ArisSettingsBuilder.searchable); nil offers every setting.
    var searchable: Set<String>?
    /// What pressing the status line does while the helper doesn't answer: the helper's restart, and what it is called.
    var helperFix: (title: String, press: () -> Void)?
    /// What pressing it does while a saved key has never answered: the key's check, made again.
    var aiFix: (title: String, press: () -> Void)?
    @FocusState private var searching: Bool
    @State private var cursor = 0
    @State private var listHeight: CGFloat = 0
    /// The list's top in its scroller: 0, less once scrolled down.
    @State private var listTop: CGFloat = 0

    /// In the English window a setting is found by its English name too.
    private var results: [ArisSettingsIndex.Match] {
        ArisSettingsIndex.matches(nav.query, among: searchable, alias: w.frameEnglish ? { .init(title: w.of($0.page, $0.title), page: w.frame($0.page.title)) } : nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            greeting.padding(.horizontal, 6).padding(.bottom, ArisSidebarMetrics.greetingGap)
            search.padding(.horizontal, 2).padding(.bottom, ArisSidebarMetrics.searchGap)
            if still {
                // Drawn once: the list as far as the window shows it, its end fading as the scroller's does.
                GeometryReader { box in
                    list.fixedSize(horizontal: false, vertical: true)
                        .frame(width: box.size.width, height: box.size.height, alignment: .top)
                        .clipped()
                        .mask(fadeMask(fades(listHeight: listedHeight, box: box.size.height, listTop: 0)))
                }
            } else {
                scroller
            }
        }
        // ⌘F puts the keyboard in the search field from anywhere in the window (item 15).
        .background(Button("") { searching = true }.keyboardShortcut("f", modifiers: .command).opacity(0).accessibilityHidden(true))
        .padding(.top, ArisSidebarMetrics.top).padding(.horizontal, ArisSidebarMetrics.padding).padding(.bottom, ArisSidebarMetrics.bottom)
        .frame(width: ArisSidebarMetrics.width)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// The list scrolls only when the window is too short for it (or the results are many); then its end fades out
    /// over 44 pt while more of it lies below, so a cut row reads as more below and not as the end. Scrolled to its end,
    /// or with the chosen row in the fade, nothing fades (ArisSidebarMetrics.fades).
    private var scroller: some View {
        GeometryReader { box in
            ScrollView {
                list.background(GeometryReader { inner in
                    // macOS 14: the list's frame in the scroller, read where it is laid out (a preference from inside a
                    // ScrollView never reached the scroller: thirteenth VM pass, the end never faded).
                    let frame = inner.frame(in: .named(Self.scrollSpace))
                    Color.clear
                        .onAppear { follow(frame) }
                        .onChange(of: frame) { _, next in follow(next) }
                })
            }
            .coordinateSpace(name: Self.scrollSpace)
            .scrollIndicators(.never)
            .modifier(ArisSidebarScrollWatch { height, top in
                listHeight = height
                listTop = top
            })
            .mask(fadeMask(fades(listHeight: listHeight, box: box.size.height, listTop: listTop)))
        }
    }

    /// The list's height and its top in the scroller (0, less once scrolled down), from its laid-out frame.
    private func follow(_ frame: CGRect) {
        if listHeight != frame.height { listHeight = frame.height }
        if listTop != frame.minY { listTop = frame.minY }
    }

    private static let scrollSpace = "arisSidebarList"

    /// The list's height as laid out: measured while it scrolls, the pages' own height in a still drawing.
    private var listedHeight: CGFloat {
        listHeight > 0 ? listHeight : (showsPages ? CGFloat(ArisSidebarMetrics.pagesHeight()) : 0)
    }

    private var showsPages: Bool { nav.query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Whether the end fades now, for a box `box` tall with the list's top at `listTop` in it.
    private func fades(listHeight: CGFloat, box: CGFloat, listTop: CGFloat) -> Bool {
        let top = Double(listTop)
        let chosen = showsPages ? ArisSidebarMetrics.rowSpan(nav.page).map { (top: $0.top + top, bottom: $0.bottom + top) } : nil
        return ArisSidebarMetrics.fades(listHeight: Double(listHeight), boxHeight: Double(box), listTop: top, chosen: chosen)
    }

    private func fadeMask(_ fading: Bool) -> some View {
        VStack(spacing: 0) {
            Rectangle()
            LinearGradient(colors: [.black, fading ? .clear : .black], startPoint: .top, endPoint: .bottom).frame(height: ArisSidebarMetrics.fade)
        }
    }

    @ViewBuilder
    private var list: some View {
        if showsPages { pages } else { found }
    }

    // MARK: greeting

    /// What a press on the line does, in the line's own order: a helper that isn't answering is restarted first (nothing
    /// else can be known or fixed without it), then "권한 N개가 더 필요해요" opens the permission rows, then the AI.
    @ViewBuilder
    private var greeting: some View {
        if ArisSettingsCaption.asksForHelper(status), let helperFix {
            Button(action: helperFix.press) { greetingRow }
                .buttonStyle(.plain)
                .help(helperFix.title)
                .accessibilityHint(helperFix.title)
        } else if ArisSettingsCaption.asksForPermissions(status) {
            Button { nav.go(.control, anchor: ArisSettingsCaption.permissionsAnchor) } label: { greetingRow }
                .buttonStyle(.plain)
                .help(w.frame("권한 설정 열기"))
        } else if ArisSettingsCaption.asksForAICheck(status), let aiFix {
            Button(action: aiFix.press) { greetingRow }
                .buttonStyle(.plain)
                .help(aiFix.title)
                .accessibilityHint(aiFix.title)
        } else if ArisSettingsCaption.asksForAI(status) {
            Button { nav.go(.ai, anchor: ArisSettingsCaption.brainAnchor) } label: { greetingRow }
                .buttonStyle(.plain)
                .help(w.frame("AI 서비스 열기"))
        } else if let lacking = ArisSettingsCaption.prerequisite(status) {
            // Something the install lacks: the line wraps, and what to do about it is under the pointer.
            greetingRow.help(ArisPrerequisites.full(lacking))
        } else {
            greetingRow
        }
    }

    private var greetingRow: some View {
        HStack(spacing: 10) {
            art.star(34).frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("Aris").font(.system(size: 15, weight: .bold)).tracking(-0.3).foregroundStyle(palette.title)
                Text(w.frame(status)).font(.system(size: 11)).foregroundStyle(palette.desc)
                    // Two lines: "Aris's helper isn't answering" used to end "isn't answe…" (second upgrade run, item 6).
                    .lineLimit(ArisSettingsCaption.prerequisite(status) == nil ? 2 : 3).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: search

    private var search: some View {
        ZStack(alignment: .leading) {
            if still {
                Text(nav.query.isEmpty ? w.frame("설정 검색") : nav.query).font(.system(size: 13))
                    .foregroundStyle(nav.query.isEmpty ? palette.ink3 : palette.title).frame(maxWidth: .infinity, alignment: .leading)
                    .modifier(ArisFieldStyle(focused: !nav.query.isEmpty))
            } else {
            TextField(w.frame("설정 검색"), text: $nav.query)
                .focused($searching)
                .modifier(ArisFieldStyle(focused: searching))
                .onSubmit { pick(cursor, byKey: true) }
                .onChange(of: nav.query) { _, _ in cursor = 0 }
                .onKeyPress(.downArrow) { move(1) }
                .onKeyPress(.upArrow) { move(-1) }
                .onExitCommand { nav.query = "" }
                .accessibilityLabel(w.frame("설정 검색"))
            }
            ArisLineIcon("magnifyingglass", size: 14).foregroundStyle(palette.ink3)
                .padding(.leading, 10).allowsHitTesting(false)
        }
        .environment(\.arisFieldLeading, 30)
        .overlay(alignment: .trailing) {
            if nav.query.isEmpty {
                // The way in, shown where it is used (mockup `.kbd`: 10/600 in a small raised cap).
                Text("⌘F").font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.desc)
                    .padding(.horizontal, 5).frame(height: 18)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(palette.capFill))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(palette.capBorder, lineWidth: 1))
                    .padding(.trailing, 8).allowsHitTesting(false).accessibilityHidden(true)
            } else {
                Button { nav.query = ""; searching = true } label: {
                    ArisLineIcon("xmark", size: 11, stroke: 2.5).foregroundStyle(palette.ink3)
                        .frame(width: 20, height: 20).contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(ArisPressScale())
                .padding(.trailing, 6)
                .help(w.frame("지우기")).accessibilityLabel(w.frame("검색어 지우기"))
            }
        }
    }

    private func move(_ step: Int) -> KeyPress.Result {
        guard !results.isEmpty else { return .ignored }
        cursor = min(max(cursor + step, 0), results.count - 1)
        return .handled
    }

    private func pick(_ index: Int, byKey: Bool = false) {
        guard results.indices.contains(index) else { return }
        let entry = results[index].entry
        nav.query = ""
        searching = false
        nav.go(entry.page, anchor: entry.id, byKey: byKey)
    }

    private var found: some View {
        VStack(alignment: .leading, spacing: 2) {
            if results.isEmpty {
                Text(w.frame("찾는 설정이 없어요")).font(.system(size: 12)).foregroundStyle(palette.ink3).padding(10)
            }
            ForEach(Array(results.enumerated()), id: \.element.entry.id) { index, match in
                ArisSearchResultRow(entry: match.entry, why: match.why, current: index == cursor) { pick(index) }
            }
        }
    }

    // MARK: pages

    private var pages: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(ArisSettingsGroup.allCases, id: \.self) { group in
                Text(w.frame(group.rawValue)).font(.system(size: ArisSidebarMetrics.groupLabelSize, weight: .semibold)).foregroundStyle(palette.groupLabel)
                    .frame(height: ArisSidebarMetrics.groupLabel)
                    .padding(.horizontal, ArisSidebarMetrics.rowLeading).padding(.top, group == ArisSettingsGroup.allCases.first ? ArisSidebarMetrics.firstGroupTop : ArisSidebarMetrics.groupTop)
                    .padding(.bottom, ArisSidebarMetrics.groupBottom)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: ArisSidebarMetrics.rowGap) {
                    ForEach(group.pages) { page in
                        ArisNavItem(page: page, current: nav.page == page, isNew: ArisSettingsIndex.showsNew(page, seen: nav.seen)) { nav.go(page) }
                    }
                }
            }
        }
    }
}

/// From macOS 15 the scroller itself says how tall its content is and how far it has scrolled (its own geometry, as it
/// scrolls); on macOS 14 the list's laid-out frame says it (ArisSettingsSidebar.follow).
private struct ArisSidebarScrollWatch: ViewModifier {
    let changed: (_ height: CGFloat, _ top: CGFloat) -> Void

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.onScrollGeometryChange(for: CGRect.self) { geometry in
                CGRect(x: 0, y: -(geometry.contentOffset.y + geometry.contentInsets.top), width: geometry.contentSize.width, height: geometry.contentSize.height)
            } action: { _, next in
                changed(next.height, next.minY)
            }
        } else {
            content
        }
    }
}

/// A page in the sidebar: 44 tall, r12, a 20-pt line icon 12 from the name at 14 / 500, 15.5 in from the left and 16
/// from the right; idle .5, chosen .9 / .98 (its colour eases over 200 ms), no fill under the pointer. The chosen one
/// carries the glass (it appears there at once, as measured), whose rim shows while the pointer is on it.
private struct ArisNavItem: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let page: ArisSettingsPage
    let current: Bool
    /// Added lately and not opened yet: it carries 새.
    var isNew = false
    let go: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: go) {
            HStack(spacing: ArisSidebarMetrics.iconGap) {
                ArisLineIcon(page.lineIcon, size: ArisSidebarMetrics.iconSize)
                // The name takes the whole room after the icon (ArisSidebarMetrics.labelRoom): no gap to a spacer eats
                // into it. Every name fits there at 14 pt (tested); the scale is only a guard.
                Text(w.frame(page.title)).font(.system(size: ArisSidebarMetrics.labelSize, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isNew {
                    Text(w.frame("새")).font(.system(size: ArisSidebarMetrics.newSize, weight: .semibold)).foregroundStyle(palette.accent)
                        .padding(.horizontal, ArisSidebarMetrics.newPadding).frame(height: 16)
                        .background(Capsule().fill(palette.accent.opacity(palette.dark ? 0.2 : 0.1)))
                }
            }
            .foregroundStyle(current ? palette.navOn : palette.navIdle)
            .animation(.easeInOut(duration: 0.2), value: current)
            .padding(.leading, ArisSidebarMetrics.rowLeading).padding(.trailing, ArisSidebarMetrics.rowTrailing)
            .frame(height: ArisSidebarMetrics.row)
            .background {
                if current {
                    ArisGlassHighlight(radius: ArisSidebarMetrics.rowRadius, hovering: hovering)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: ArisSidebarMetrics.rowRadius, style: .continuous))
        }
        .buttonStyle(ArisPressScale(scale: ArisPressScale.measured))
        .onHover { hovering = $0 }
        .accessibilityLabel(w.frame(page.title))
        .accessibilityAddTraits(current ? .isSelected : [])
    }
}

/// The chosen item's liquid glass (§3.3), both appearances: the −75° sheen (edge, middle, edge) and its four shades
/// (ArisMenuLook.radioShadows*: a top shade and a bottom light inside, a lift under it, an inner glow), with no rim at
/// rest. Under the pointer a 1-pt rim fades in over 0.2 s: light, a turning conic ring over a pale vertical one; dark,
/// a white radial that follows the pointer.
struct ArisGlassHighlight: View {
    @Environment(\.arisPalette) private var palette
    var radius: CGFloat = 12
    var hovering = false
    @State private var pointer: CGPoint?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let dark = palette.dark, edge = ArisMenuLook.radioEdge.color(dark), middle = ArisMenuLook.radioMiddle.color(dark)
        let shades = dark ? ArisMenuLook.radioShadowsDark : ArisMenuLook.radioShadowsLight
        GeometryReader { box in
            ZStack {
                ForEach(Array(shades.enumerated()), id: \.offset) { _, shade in
                    if !shade.inset {
                        shape.inset(by: -shade.spread).fill(Color.black).shadow(color: shade.shade.color, radius: shade.blur / 2, y: shade.y)
                            .mask(Rectangle().padding(-40).overlay(shape.fill(Color.black).blendMode(.destinationOut)).compositingGroup())
                    }
                }
                shape.fill(Self.sheen(edge: edge, middle: middle, size: box.size))
                ForEach(Array(shades.enumerated()), id: \.offset) { _, shade in
                    if shade.inset { ArisInsetShade(shape: shape, shadow: shade) }
                }
                ArisNavGlassRim(shape: shape, dark: dark, pointer: pointer, size: box.size)
                    .opacity(hovering ? 1 : 0)
                    .animation(.easeOut(duration: 0.2), value: hovering)
            }
        }
        .onContinuousHover { phase in
            if case .active(let point) = phase { pointer = point } else { pointer = nil }
        }
        .allowsHitTesting(false)
    }

    /// A CSS `linear-gradient(-75deg, …)` on a box of `size`: the gradient line runs toward 285°, as long as the box's
    /// extent along it, through the centre.
    static func sheen(edge: Color, middle: Color, size: CGSize) -> LinearGradient {
        let angle = -75.0 * Double.pi / 180
        let dx = sin(angle), dy = -cos(angle)
        let length = abs(size.width * dx) + abs(size.height * dy)
        let w = max(size.width, 1), h = max(size.height, 1)
        let half = CGSize(width: dx * length / 2 / w, height: dy * length / 2 / h)
        return LinearGradient(colors: [edge, middle, edge], startPoint: UnitPoint(x: 0.5 - half.width, y: 0.5 - half.height),
                              endPoint: UnitPoint(x: 0.5 + half.width, y: 0.5 + half.height))
    }
}

/// The glass's 1-pt rim (shown under the pointer only). Light: a conic ring that turns once every 3 s from 90°, over a
/// #dcf0ff → white .5 vertical ring, with a .5-pt #dcf0ff .5 line inside. Dark: the ring filled with a white radial
/// (.4 → .2, a 120-pt circle) where the pointer is, and a .5-pt #96aac8 .2 line inside. Still under Reduce Motion.
private struct ArisNavGlassRim<S: InsettableShape>: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisSettingsStill) private var still
    let shape: S
    let dark: Bool
    let pointer: CGPoint?
    let size: CGSize

    var body: some View {
        if dark {
            let at = pointer ?? CGPoint(x: size.width / 2, y: size.height / 2)
            ZStack {
                shape.strokeBorder(RadialGradient(colors: [.white.opacity(0.4), .white.opacity(0.2)], center: UnitPoint(x: at.x / max(size.width, 1), y: at.y / max(size.height, 1)),
                                                  startRadius: 0, endRadius: 60), lineWidth: 1)
                shape.inset(by: 0.5).strokeBorder(Color(arisHex: 0x96aac8, 0.2), lineWidth: 0.5)
            }
        } else {
            ZStack {
                shape.strokeBorder(LinearGradient(colors: [Color(arisHex: 0xdcf0ff, 0.5), .white.opacity(0.5)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                if still || ArisSettingsMotion.reduced {
                    conic(90)
                } else {
                    TimelineView(.animation) { time in
                        conic(90 + time.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3) / 3 * 360)
                    }
                }
                shape.inset(by: 1).strokeBorder(Color(arisHex: 0xdcf0ff, 0.5), lineWidth: 0.5)
            }
        }
    }

    private func conic(_ degrees: Double) -> some View {
        let rim = palette.rim
        return shape.strokeBorder(AngularGradient(stops: [.init(color: rim[0], location: 0), .init(color: rim[1], location: 0.08), .init(color: rim[2], location: 0.15),
                                                          .init(color: rim[1], location: 0.5), .init(color: rim[2], location: 0.85), .init(color: rim[1], location: 0.92),
                                                          .init(color: rim[0], location: 1)],
                                                  center: .center, angle: .degrees(degrees)), lineWidth: 1)
    }
}

/// A search result: the setting, and under it its page and (when its name doesn't say) the word it was found by.
private struct ArisSearchResultRow: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let entry: ArisSettingsEntry
    /// The keyword it was found by, when its name doesn't say why.
    var why: String?
    let current: Bool
    let pick: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: pick) {
            HStack(spacing: 10) {
                ArisLineIcon(entry.page.symbol, size: 16).foregroundStyle(palette.navIdle).frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    // A long name takes a second line (in English: "Look at the screen w…").
                    Text(w.of(entry.page, entry.title)).font(.system(size: 13, weight: .medium)).foregroundStyle(palette.navOn).lineLimit(2)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    Text(w.frame(entry.page.title) + (why.map { " · " + $0 } ?? "")).font(.system(size: 11)).foregroundStyle(palette.ink3).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 5).frame(minHeight: 42)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(current || hovering ? palette.navFill : .clear))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .animation(.easeInOut(duration: 0.15), value: hovering)
        }
        .buttonStyle(ArisPressScale(scale: ArisPressScale.measured))
        .onHover { hovering = $0 }
        .accessibilityLabel("\(w.of(entry.page, entry.title)), \(w.frame(entry.page.title))")
    }
}
