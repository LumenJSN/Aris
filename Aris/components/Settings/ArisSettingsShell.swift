//
//  ArisSettingsShell.swift
//  Aris
//
//  The settings window's frame, as measured (SETTINGS-REA.md §3.1, §4.3): the window's material shows through the
//  sidebar under a light tint and through a 7-pt gutter under a .15 wash; the content is a floating card inset 7 on
//  its top, bottom and right, radius 13, with a white .8 border (light) or a #dfe2e8 ring (dark) and nothing between
//  it and the sidebar. In it, one column at most 800 wide, 48 from the left and 40 from the top: Aris's face on the
//  팀원 page, the page's 22/600 title, then the page's cards, which are all that changes when another page is chosen
//  (pick 4-A); a 20-pt fade at the top of the scroll and an 80-pt fade at the bottom. No page shows a notch preview
//  (the owner, 2026-11-12). A search result jumps to its setting and highlights it once.
//

import AppKit
import SwiftUI

struct ArisSettingsShell<Page: View>: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    @Environment(\.arisSettingsStill) private var still
    @ObservedObject var nav: ArisSettingsNav
    /// The pages' open menu (the window's one menu control).
    var menus: ArisSettingMenus?
    let status: String
    /// What the search may offer (ArisSettingsBuilder.searchable); nil offers every setting.
    var searchable: Set<String>?
    /// The window's real material is behind this view (the offscreen renders draw a stand-in: ArisMaterialStandIn).
    var vibrancy = true
    /// The helper's restart, for the status line while the helper doesn't answer.
    var helperFix: (title: String, press: () -> Void)?
    var aiFix: (title: String, press: () -> Void)?
    /// A control at the end of the title row (스킬's 스킬 기능 switch).
    var accessory: AnyView?
    @ViewBuilder let page: () -> Page
    @State private var entering = true

    var body: some View {
        HStack(spacing: 0) {
            ArisSettingsSidebar(nav: nav, status: status, searchable: searchable, helperFix: helperFix, aiFix: aiFix)
                .frame(maxHeight: .infinity)
                .background(palette.sidebarTint.ignoresSafeArea())
            ZStack {
                palette.wash.ignoresSafeArea()
                card.padding(EdgeInsets(top: inset, leading: 0, bottom: inset, trailing: inset))
            }
        }
        .background { if !vibrancy { ArisMaterialStandIn() } }
        .overlay { if let menus { ArisSettingMenuHost(menus: menus) } }
        .environment(\.arisSettingsFlash, nav.flash)
    }

    private var inset: CGFloat { ArisSidebarMetrics.cardInset }

    /// The content card: the pane gradient, the column, the bottom fade (its corners are the card's), and its edge.
    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: ArisSidebarMetrics.cardRadius, style: .continuous)
        return ZStack(alignment: .bottom) {
            palette.pane
            scroller
            LinearGradient(colors: [palette.fade, palette.fade.opacity(0)], startPoint: .bottom, endPoint: .top)
                .frame(height: ArisSettingsMetrics.bottomFade).opacity(0.9).allowsHitTesting(false)
        }
        .clipShape(shape)
        .overlay {
            // Light: a 1-pt border inside the card. Dark: a 1-pt ring just outside it (`0 0 0 1px`).
            if palette.dark { shape.inset(by: -0.5).stroke(palette.paneEdge, lineWidth: 1) } else { shape.strokeBorder(palette.paneEdge, lineWidth: 1) }
        }
    }

    /// The title stays as pages change (팀원 shows Aris's face above it); only the cards under it are the page's own,
    /// and they come in over 0.15 s (ArisPageSwap). The whole column is made anew each time the window opens, which is
    /// when its entrance plays.
    private var column: some View {
        VStack(alignment: .leading, spacing: 0) {
            if nav.page == .team { ArisFaceStageView().padding(.bottom, 22).modifier(ArisRise(index: 0)) }
            title.padding(.bottom, ArisSettingsMetrics.titleGap).modifier(ArisRise(index: 1))
            page().id(nav.page).modifier(ArisPageSwap(animated: !entering && !still && !nav.byKey))
        }
        // The wrapper's 48 on the left, then the column centred in what is left, at most 800 wide.
        .frame(maxWidth: ArisSettingsMetrics.columnMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
        .padding(.leading, ArisSettingsMetrics.columnLeading).padding(.trailing, ArisSettingsMetrics.columnTrailing)
        .padding(.top, ArisSettingsMetrics.columnTop).padding(.bottom, ArisSettingsMetrics.bottomFade)
        .id(nav.opens)
        .environment(\.arisSettingsEntering, entering)
    }

    private static var top: String { "settings.top" }

    @ViewBuilder
    private var scroller: some View {
        if still {
            Color.clear.overlay(alignment: .top) { column.fixedSize(horizontal: false, vertical: true) }.clipped()
        } else {
            scrolling
        }
    }

    private var scrolling: some View {
        ScrollViewReader { proxy in
            // The mark a page's opening scrolls to sits at the very top of the content, above the column's own inset.
            ScrollView { column.background(alignment: .top) { Color.clear.frame(height: 1).id(Self.top) } }
            .scrollIndicators(.never)
            .mask(VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 20)
                Rectangle()
            })
            // A page opens at its top: the one scroll view would otherwise stay where the page before had been
            // scrolled to (VM run 2026-11-11, bug 11). A jump to a row follows below, once the page is there.
            // Once at the change, and again when the new page has laid out (ArisSettingsPageTop.again): scrolled only
            // before its layout, the scroll view kept the old page's offset against the new page's height, and 5 of
            // 13 pages opened part-way down (final check on a new Mac). A jump to a row (nav.flash) has the last word.
            .onChange(of: nav.page) { _, page in
                entering = false
                proxy.scrollTo(Self.top, anchor: .top)
                Task { @MainActor in
                    for wait in ArisSettingsPageTop.again {
                        try? await Task.sleep(for: .milliseconds(wait))
                        guard ArisSettingsPageTop.stillScrolls(opened: page, shown: nav.page, jumping: nav.flash != nil) else { return }
                        proxy.scrollTo(Self.top, anchor: .top)
                    }
                }
            }
            .onChange(of: nav.flash) { _, target in
                guard let target else { return }
                Task { @MainActor in
                    // After the page (when it changed) has laid out, and a fold that holds the row has opened.
                    try? await Task.sleep(for: .milliseconds(90))
                    // It jumps and then the row lights once: a scroll that glides after a key press is felt as a wait.
                    proxy.scrollTo(target.id, anchor: UnitPoint(x: 0.5, y: 0.3))
                    // The highlight fades by 1.8 s (ArisFlash); then it is spent.
                    try? await Task.sleep(for: .seconds(2))
                    nav.settle(target.token)
                }
            }
        }
        .task(id: nav.opens) {
            entering = true
            try? await Task.sleep(for: .seconds(ArisSettingsMotion.entrance))
            if !Task.isCancelled { entering = false }
        }
    }

    /// The page's name alone (22 / 600, −0.02em; the measured pages carry no line under it), with the page's control at
    /// the end of its row. What the page is for is the title's help.
    private var title: some View {
        HStack(alignment: .center, spacing: 12) {
            // The page's name is the window's frame: English whenever the UI is, like the sidebar's names.
            Text(w.frame(nav.page.title)).font(.system(size: ArisSettingsMetrics.pageTitleSize, weight: .semibold))
                .tracking(ArisSettingsMetrics.pageTitleTracking).foregroundStyle(palette.title)
                .accessibilityAddTraits(.isHeader)
                .help(w.frame(nav.page.subtitle))
            Spacer(minLength: 0)
            if let accessory { accessory }
        }
    }
}

/// What the window's material shows, for the offscreen renders that can't sample a desktop: a flat stand-in, or with
/// `arisSettingsWallpaper` a generated wallpaper blurred and washed the way the sidebar material treats a desktop.
struct ArisMaterialStandIn: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisSettingsWallpaper) private var wallpaper

    var body: some View {
        if wallpaper {
            ZStack {
                ArisWallpaper()
                    .blur(radius: 28)
                    .saturation(1.4)
                palette.dark ? Color(arisHex: 0x1e1e20, 0.62) : Color(arisHex: 0xf2f2f4, 0.6)
            }
            .ignoresSafeArea()
        } else {
            palette.materialStandIn.ignoresSafeArea()
        }
    }
}

private struct WallpaperKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// Offscreen only: a stand-in wallpaper behind the window's stand-in material.
    var arisSettingsWallpaper: Bool {
        get { self[WallpaperKey.self] }
        set { self[WallpaperKey.self] = newValue }
    }
}
