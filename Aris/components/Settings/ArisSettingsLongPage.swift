//
//  ArisSettingsLongPage.swift
//  Aris
//
//  One of option A's long pages: its parts one under the other, each under its title (20 / 700, the section title, with
//  the mockup's small line beside it where it has one), 32 apart as sections are. Each part reports where its top is in
//  the scroll view, so the sidebar can mark the part in view (ArisSettingsSpy), and carries the tag the sidebar's link
//  scrolls to. What a part draws under its title is the caller's.
//

import SwiftUI

/// The scroll view's coordinate space, in which the parts report their tops.
enum ArisSettingsScrollSpace {
    static let name = "arisSettingsScroll"
    /// A part's tag sits this far above its title, so a jump leaves the title clear of the top fade (mockup
    /// `scroll-margin-top: 24px`).
    static let margin: CGFloat = 24
}

/// Where each part's top is, as the page scrolls; the sidebar's mark follows (only when it changes).
@MainActor
final class ArisSettingsSpyModel: ObservableObject {
    static let shared = ArisSettingsSpyModel()
    private var tops: [String: Double] = [:]
    private var end: Double = .infinity
    var box: Double = 0
    /// While a jump scrolls, the mark stays on the part jumped to.
    var holdUntil = Date.distantPast

    func report(_ part: String, top: Double, nav: ArisSettingsNav) {
        tops[part] = top
        update(nav)
    }

    func reportEnd(_ y: Double, nav: ArisSettingsNav) {
        end = y
        update(nav)
    }

    func reset() {
        tops = [:]
        end = .infinity
    }

    private func update(_ nav: ArisSettingsNav) {
        guard Date() >= holdUntil else { return }
        let order = nav.page.parts.map(\.id)
        let atEnd = box > 0 && end <= box + 1
        let now = ArisSettingsSpy.current(order: order, tops: tops, atEnd: atEnd)
        if nav.inView != now { nav.inView = now }
    }
}

struct ArisSettingsLongPage<Part: View>: View {
    @Environment(\.arisWords) private var w
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisSettingsStill) private var still
    @ObservedObject var nav: ArisSettingsNav
    let parts: [ArisPartSections]
    /// What the part draws under its title.
    @ViewBuilder let content: (ArisPartSections) -> Part
    /// A control at the end of a part's title (스킬's switch, a feature's 알아보기 link).
    var accessory: (ArisPartSections) -> AnyView? = { _ in nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(parts.enumerated()), id: \.element.id) { index, part in
                VStack(alignment: .leading, spacing: 0) {
                    marker(part.id)
                    heading(part).padding(.top, index == 0 ? 0 : ArisSettingsScrollSpace.margin)
                        .padding(.bottom, ArisSettingsMetrics.headingGap)
                    content(part)
                }
                .padding(.top, index == 0 ? 0 : ArisSettingsMetrics.sectionGap - ArisSettingsScrollSpace.margin)
                .modifier(ArisRise(index: index + 2))
            }
            endMarker
        }
    }

    /// The part's tag, and its top as the page scrolls.
    private func marker(_ id: String) -> some View {
        Color.clear.frame(height: 0).id(id)
            .background(GeometryReader { box in
                let top = box.frame(in: .named(ArisSettingsScrollSpace.name)).minY
                Color.clear
                    .onAppear { if !still { ArisSettingsSpyModel.shared.report(id, top: top, nav: nav) } }
                    .onChange(of: top) { _, next in ArisSettingsSpyModel.shared.report(id, top: next, nav: nav) }
            })
    }

    /// The page's end: scrolled to it, the last part is in view even when its top can't reach the line.
    private var endMarker: some View {
        Color.clear.frame(height: 0)
            .background(GeometryReader { box in
                let y = box.frame(in: .named(ArisSettingsScrollSpace.name)).minY
                Color.clear
                    .onAppear { if !still { ArisSettingsSpyModel.shared.reportEnd(y, nav: nav) } }
                    .onChange(of: y) { _, next in ArisSettingsSpyModel.shared.reportEnd(next, nav: nav) }
            })
    }

    private func heading(_ part: ArisPartSections) -> some View {
        HStack(alignment: .center, spacing: 8) {
            ArisSectionTitle(text: w(part.part.title))
            if let small = part.part.subtitle {
                Text(w(small)).font(.system(size: 12)).foregroundStyle(palette.desc).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let extra = accessory(part) { extra }
        }
        .arisFlash(part.id)
    }
}
