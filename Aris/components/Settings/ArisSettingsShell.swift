//
//  ArisSettingsShell.swift
//  Aris
//
//  The settings window's frame: B's sidebar on the left (220, the system sidebar material under its tint), and C's
//  content pane (the pane gradient, one 700-wide column 44 from the top, a 20-pt fade at the top of the scroll and an
//  80-pt fade at the bottom): the notch preview on the pages that have something to show in it (pick 1-A), the page's
//  title with its line under it, then the page's cards, which are all that changes when another page is chosen (pick
//  4-A). A search result jumps to its setting and highlights it once.
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
    let plan: ArisNotchPreviewPlan
    var replay = 0
    /// What the search may offer (ArisSettingsBuilder.searchable); nil offers every setting.
    var searchable: Set<String>?
    /// The real sidebar material (the offscreen renders draw a stand-in under the tint).
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
                .background(ArisSidebarBackdrop(vibrancy: vibrancy))
            pane
                .overlay(alignment: .leading) { Rectangle().fill(palette.hairline).frame(width: 1) }
        }
        .overlay { if let menus { ArisSettingMenuHost(menus: menus) } }
        .environment(\.arisSettingsFlash, nav.flash)
    }

    private var pane: some View {
        ZStack(alignment: .bottom) {
            palette.pane
            scroller
            LinearGradient(colors: [palette.fade, palette.fade.opacity(0)], startPoint: .bottom, endPoint: .top)
                .frame(height: 80).opacity(0.9).allowsHitTesting(false)
        }
        .background(palette.wash)
    }

    /// The preview (on the pages that have one) and the title stay as pages change; only the cards under them are the
    /// page's own, and they come in over 0.15 s (ArisPageSwap). The whole column is made anew each time the window
    /// opens, which is when its entrance plays.
    private var column: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasStage { stage.padding(.bottom, 22).modifier(ArisRise(index: 0)) }
            title.padding(.bottom, ArisSettingsMetrics.titleGap).modifier(ArisRise(index: 1))
            page().id(nav.page).modifier(ArisPageSwap(animated: !entering && !still && !nav.byKey))
        }
        .frame(maxWidth: 700, alignment: .leading)
        .padding(.horizontal, 40).padding(.top, 44).padding(.bottom, 80)
        .frame(maxWidth: .infinity)
        .id(nav.opens)
        .environment(\.arisSettingsEntering, entering)
    }

    private static var top: String { "settings.top" }

    /// 팀원 plays Aris's face; the other pages their notch preview when they have something to show in it.
    private var hasStage: Bool { nav.page == .team || plan.shown }

    /// The 팀원 page plays Aris's face (Settings A); every other page its notch preview.
    @ViewBuilder
    private var stage: some View {
        if nav.page == .team {
            ArisFaceStageView()
        } else {
            ArisNotchPreview(plan: plan, replay: replay)
        }
    }

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

    /// The page's name, and its line under it (mockup `.ttl.under`: 22/600, then 13 pt in the second ink 4 below).
    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 12) {
                // The page's name and its line are the window's frame: English whenever the UI is, like the sidebar's names.
                Text(w.frame(nav.page.title)).font(.system(size: 22, weight: .semibold)).tracking(-0.44).foregroundStyle(palette.title)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if let accessory { accessory }
            }
            Text(w.frame(nav.page.subtitle)).font(.system(size: 13)).foregroundStyle(palette.desc).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The sidebar's backdrop: the system sidebar material (or a stand-in) under mockup B's tint.
struct ArisSidebarBackdrop: View {
    @Environment(\.arisPalette) private var palette
    let vibrancy: Bool

    var body: some View {
        ZStack {
            if vibrancy {
                ArisVisualEffect()
            } else {
                // Offscreen renders: about what the material shows over a plain desktop.
                palette.dark ? Color(arisHex: 0x24262c) : Color(arisHex: 0xe4e7ec)
            }
            palette.sidebarTint
        }
        .ignoresSafeArea()
    }
}

private struct ArisVisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
