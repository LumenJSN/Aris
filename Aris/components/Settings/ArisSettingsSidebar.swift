//
//  ArisSettingsSidebar.swift
//  Aris
//
//  The settings sidebar, mockup B's (the owner's pick for it): Aris's star greeting with how things are, the settings
//  search, and the pages in their three groups with one glass highlight that slides to the page on screen (0.4 s on
//  the house curve). While something is typed the pages give way to the settings that match (ArisSettingsIndex);
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
    @Namespace private var glass
    @FocusState private var searching: Bool
    @State private var cursor = 0
    @State private var listHeight: CGFloat = 0

    /// In the English window a setting is found by its English name too.
    private var results: [ArisSettingsIndex.Match] {
        ArisSettingsIndex.matches(nav.query, among: searchable, alias: w.frameEnglish ? { .init(title: w.of($0.page, $0.title), page: w.frame($0.page.title)) } : nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            greeting.padding(.horizontal, 6).padding(.bottom, ArisSidebarMetrics.greetingGap)
            search.padding(.horizontal, 2).padding(.bottom, ArisSidebarMetrics.searchGap)
            if still {
                list
            } else {
                scroller
            }
        }
        // ⌘F puts the keyboard in the search field from anywhere in the window (item 15).
        .background(Button("") { searching = true }.keyboardShortcut("f", modifiers: .command).opacity(0).accessibilityHidden(true))
        .padding(.top, ArisSidebarMetrics.top).padding(.horizontal, 12).padding(.bottom, ArisSidebarMetrics.bottom)
        .frame(width: ArisSidebarMetrics.width)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// The list scrolls only when the window is too short for it (or the results are many); then its end fades out
    /// over 44 pt, so a cut row reads as more below and not as the end.
    private var scroller: some View {
        GeometryReader { box in
            let more = listHeight > box.size.height + 1
            ScrollView {
                list.background(GeometryReader { inner in
                    Color.clear.onAppear { listHeight = inner.size.height }.onChange(of: inner.size.height) { _, next in listHeight = next }
                })
            }
            .scrollIndicators(.never)
            .mask(VStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, more ? .clear : .black], startPoint: .top, endPoint: .bottom).frame(height: ArisSidebarMetrics.fade)
            })
        }
    }

    @ViewBuilder
    private var list: some View {
        if nav.query.trimmingCharacters(in: .whitespaces).isEmpty { pages } else { found }
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
            Image(systemName: "magnifyingglass").font(.system(size: 11.5, weight: .medium)).foregroundStyle(palette.ink3)
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
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(palette.ink3)
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
                    .padding(.horizontal, 12).padding(.top, group == ArisSettingsGroup.allCases.first ? ArisSidebarMetrics.firstGroupTop : ArisSidebarMetrics.groupTop)
                    .padding(.bottom, ArisSidebarMetrics.groupBottom)
                    .accessibilityAddTraits(.isHeader)
                ForEach(group.pages) { page in
                    ArisNavItem(page: page, current: nav.page == page, isNew: ArisSettingsIndex.showsNew(page, seen: nav.seen), glass: glass) { nav.go(page) }
                }
            }
        }
        .animation(ArisSettingsMotion.reduced ? nil : ArisSettingsMotion.house(0.4), value: nav.page)
    }
}

/// A page in the sidebar: 32 tall, r12, a 16-pt icon and the name at 14 (500 when chosen); the chosen one carries
/// the sliding glass.
private struct ArisNavItem: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let page: ArisSettingsPage
    let current: Bool
    /// Added lately and not opened yet: it carries 새.
    var isNew = false
    let glass: Namespace.ID
    let go: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: go) {
            HStack(spacing: 10) {
                Image(systemName: page.symbol).font(.system(size: 13.5)).frame(width: ArisSidebarMetrics.iconSize)
                Text(w.frame(page.title)).font(.system(size: ArisSidebarMetrics.labelSize, weight: current ? .medium : .regular)).lineLimit(1)
                Spacer(minLength: 0)
                if isNew {
                    Text(w.frame("새")).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(palette.accent)
                        .padding(.horizontal, 6).frame(height: 16)
                        .background(Capsule().fill(palette.accent.opacity(palette.dark ? 0.2 : 0.1)))
                }
            }
            .foregroundStyle(current ? palette.navOn : hovering ? palette.navHover : palette.navIdle)
            .padding(.horizontal, 10)
            .frame(height: ArisSidebarMetrics.row)
            .background {
                if current {
                    ArisGlassHighlight().matchedGeometryEffect(id: "nav", in: glass)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.navFill)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .animation(.easeInOut(duration: 0.15), value: hovering)
        }
        .buttonStyle(ArisPressScale(scale: ArisPressScale.light))
        .onHover { hovering = $0 }
        .accessibilityLabel(w.frame(page.title))
        .accessibilityAddTraits(current ? .isSelected : [])
    }
}

/// Liquid glass, light (a sheen, a shade at the top, light at the bottom, a conic rim); a quiet fill, dark.
struct ArisGlassHighlight: View {
    @Environment(\.arisPalette) private var palette
    var radius: CGFloat = 12

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if palette.dark {
            shape.fill(palette.segTrack)
                .overlay(shape.strokeBorder(Color(arisHex: 0xdfe2e8, 0.06), lineWidth: 1))
                .overlay(shape.strokeBorder(LinearGradient(colors: [Color(arisHex: 0xeff1f5, 0.024), .clear], startPoint: .top, endPoint: .center), lineWidth: 1))
        } else {
            shape.fill(palette.sheen)
                .overlay(shape.stroke(.black.opacity(0.05), lineWidth: 2).blur(radius: 1).offset(y: 1).clipShape(shape))
                .overlay(shape.stroke(.white.opacity(0.5), lineWidth: 2).blur(radius: 1).offset(y: -1).clipShape(shape))
                .overlay(shape.strokeBorder(AngularGradient(colors: [palette.rim[0], palette.rim[1], palette.rim[2], palette.rim[1], palette.rim[0]],
                                                            center: .center, angle: .degrees(-75)), lineWidth: 1))
                .shadow(color: Color(arisHex: 0x1e1e1e, 0.15), radius: 1, y: 2)
        }
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
                Image(systemName: entry.page.symbol).font(.system(size: 13)).foregroundStyle(palette.navIdle).frame(width: 16)
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
        .buttonStyle(ArisPressScale(scale: ArisPressScale.light))
        .onHover { hovering = $0 }
        .accessibilityLabel("\(w.of(entry.page, entry.title)), \(w.frame(entry.page.title))")
    }
}
