//
//  ArisFeatureSheet.swift
//  Aris
//
//  A feature's detail sheet, as measured (SETTINGS-REA.md §5): a 620-wide panel, radius 20, with a floating close
//  button; in it, 28 apart, the hero (an 88-pt icon tile, the 28 / 700 title and its 15-pt line, the green switch),
//  the info strip between two hairlines, "미리 보기" with its scrolling strip of 420 × 244 demo tiles (a looping scene
//  drawn in code, and the answer as it lands in the notch), 소개, what to try saying, and the information rows. A small
//  알아보기 link (ArisFeatureLink) opens it from its page.
//

import SwiftUI

/// The sheet's own colours: its ink, second ink and hairline, the panel, and the icon tile (the measured store colours).
private struct StoreInk {
    let dark: Bool
    var ink: Color { dark ? Color(arisHex: 0xf5f5f7) : Color(arisHex: 0x1d1d1f) }
    var secondary: Color { dark ? Color(arisHex: 0x98989d) : Color(arisHex: 0x6e6e73) }
    var hairline: Color { dark ? Color(arisHex: 0xdfe2e8, 0.09) : .black.opacity(0.1) }
    var panel: Color { dark ? Color(arisHex: 0x1a1b1e) : Color(arisHex: 0xfafafa) }
    var panelBorder: Color { dark ? Color(arisHex: 0xdfe2e8, 0x12 / 255.0) : .black.opacity(0.08) }
}

struct ArisFeatureSheet: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    @Environment(\.arisSettingsStill) private var still
    let feature: ArisFeature
    /// The hero's switch, when the feature has one.
    var isOn: Bool?
    var toggle: () -> Void = {}
    let close: () -> Void

    private var ink: StoreInk { StoreInk(dark: palette.dark) }
    private var content: ArisFeatureContent { feature.content }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if still {
                sections
            } else {
                ScrollView { sections }.scrollIndicators(.never)
            }
            closeButton.padding(.top, ArisFeatureLook.closeInset).padding(.trailing, ArisFeatureLook.closeInset)
        }
        .frame(width: ArisFeatureLook.width)
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: ArisFeatureLook.sectionGap) {
            hero
            ArisFeatureInfoStrip(cells: content.cells, ink: ink)
            VStack(alignment: .leading, spacing: 0) {
                header("미리 보기")
                previews.padding(.top, 12)
            }
            VStack(alignment: .leading, spacing: 8) {
                header("소개")
                Text(ArisKoreanText.keepAll(w(content.about))).font(.system(size: 14)).foregroundStyle(ink.ink).lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 8) {
                header("이렇게 말해 보세요")
                ForEach(content.tries, id: \.self) { line in
                    Text(w(line)).font(.system(size: 13)).foregroundStyle(ink.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                header("정보")
                VStack(spacing: 0) {
                    ForEach(Array(content.facts.enumerated()), id: \.offset) { index, fact in
                        if index > 0 { Rectangle().fill(ink.hairline).frame(height: 1) }
                        HStack(alignment: .firstTextBaseline) {
                            Text(w(fact.label)).font(.system(size: 13)).foregroundStyle(ink.secondary)
                            Spacer(minLength: 16)
                            Text(w(fact.value)).font(.system(size: 13)).foregroundStyle(ink.ink).multilineTextAlignment(.trailing)
                        }
                        .padding(.vertical, 12)
                    }
                }
            }
        }
        .padding(.top, ArisFeatureLook.bodyTop).padding(.bottom, ArisFeatureLook.bodyTop)
        .padding(.leading, ArisFeatureLook.bodyLeading).padding(.trailing, ArisFeatureLook.bodyTrailing)
        .frame(width: ArisFeatureLook.width, alignment: .leading)
    }

    // MARK: Hero

    private var hero: some View {
        HStack(alignment: .top, spacing: ArisFeatureLook.heroGap) {
            ArisIconTile(content.icon, size: ArisFeatureLook.icon, elevated: true)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(w(content.title)).font(.system(size: ArisFeatureLook.titleSize, weight: .bold)).tracking(-0.56).foregroundStyle(ink.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(ArisKoreanText.keepAll(w(content.line))).font(.system(size: ArisFeatureLook.lineSize)).foregroundStyle(ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let isOn {
                    ArisSwitch(isOn: isOn, style: .store, label: content.title, toggle: toggle).padding(.top, 8)
                }
            }
            // Clear of the close button.
            .padding(.trailing, 32)
            .frame(minHeight: ArisFeatureLook.icon, alignment: .top)
        }
    }

    private func header(_ text: String) -> some View {
        Text(w(text)).font(.system(size: 20, weight: .bold)).tracking(-0.4).foregroundStyle(ink.ink).accessibilityAddTraits(.isHeader)
    }

    // MARK: Previews

    /// The strip bleeds to the sheet's edges and scrolls sideways.
    private var previews: some View {
        let tiles = HStack(alignment: .top, spacing: ArisFeatureLook.tileGap) {
            ArisPreviewFrame(caption: w(content.sceneCaption), dark: false, ink: ink) { ArisFeatureScene(feature: feature) }
            ArisPreviewFrame(caption: w(content.answerCaption), dark: true, ink: ink) {
                ArisFeatureAnswerTile(query: w(content.query), answer: w(content.answer), feature: feature)
            }
        }
        .padding(.vertical, 8).padding(.leading, ArisFeatureLook.bodyLeading).padding(.trailing, ArisFeatureLook.bodyLeading)
        return Group {
            if still { tiles } else { ScrollView(.horizontal) { tiles }.scrollIndicators(.never) }
        }
        .padding(.leading, -ArisFeatureLook.bodyLeading).padding(.trailing, -ArisFeatureLook.bodyTrailing)
    }

    private var closeButton: some View {
        ArisFeatureClose(action: close).accessibilityLabel(w("닫기"))
    }
}

/// The floating close button: a 20-pt X in a p-2 r12 box, grey .4 → .6 (gray-500 → 300 dark) with a 5% fill under the pointer.
private struct ArisFeatureClose: View {
    @Environment(\.arisPalette) private var palette
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ArisLineIcon("x", size: ArisIconSizes.close)
                .foregroundStyle(palette.dark ? Color(arisHex: hovering ? 0xd1d5dc : 0x6a7282) : Color(arisHex: hovering ? 0x4a5565 : 0x99a1af))
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hovering ? (palette.dark ? Color.white : .black).opacity(0.05) : .clear))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(ArisPressScale())
        .onHover { hovering = $0 }
        .animation(ArisSettingsMotion.hover, value: hovering)
    }
}

/// The info strip: hairlines above and below, cells at least 104 wide with a hairline between, each an uppercase label,
/// a 21 / 600 value or a 24-pt icon (stroke 1.6), and a caption.
private struct ArisFeatureInfoStrip: View {
    @Environment(\.arisWords) private var w
    let cells: [ArisFeatureContent.Cell]
    let ink: StoreInk

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                if index > 0 { Rectangle().fill(ink.hairline).frame(width: 1).padding(.vertical, 12) }
                VStack(spacing: 6) {
                    Text(w(cell.label).uppercased()).font(.system(size: 11, weight: .medium)).tracking(0.88).foregroundStyle(ink.secondary).lineLimit(1)
                    Group {
                        if let icon = cell.icon {
                            ArisLineIcon(icon, size: ArisIconSizes.info, stroke: ArisIconSizes.infoStroke).foregroundStyle(ink.secondary)
                        } else {
                            Text(w(cell.value ?? "")).font(.system(size: 21, weight: .semibold)).tracking(-0.42).foregroundStyle(ink.secondary).lineLimit(1)
                        }
                    }
                    .frame(height: 28)
                    Text(w(cell.caption)).font(.system(size: 11)).foregroundStyle(ink.secondary).lineLimit(1).minimumScaleFactor(0.85)
                }
                .padding(.horizontal, 12).padding(.vertical, 16)
                .frame(minWidth: ArisFeatureLook.cellMinWidth, maxWidth: .infinity)
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(ink.hairline).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(ink.hairline).frame(height: 1) }
    }
}

/// A preview tile's frame: 420 × 244, radius 26, a 1-pt silhouette outside and a 1-pt edge inside (#111 when dark),
/// and its caption 8 under it.
private struct ArisPreviewFrame<Content: View>: View {
    @Environment(\.arisPalette) private var palette
    let caption: String
    let dark: Bool
    let ink: StoreInk
    @ViewBuilder let content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ArisFeatureLook.tileRadius, style: .continuous)
        VStack(spacing: 8) {
            content()
                .frame(width: ArisFeatureLook.tile.width, height: ArisFeatureLook.tile.height)
                .background(dark ? Color(arisHex: 0x111111) : .clear)
                .clipShape(shape)
                .overlay(shape.strokeBorder(palette.dark ? Color.black : Color(arisHex: 0x0f172a, 0.22), lineWidth: 1))
                .overlay(shape.inset(by: -0.5).stroke(palette.dark ? Color.black : Color(arisHex: 0x0f172a, 0.14), lineWidth: 1))
            Text(caption).font(.system(size: 11)).foregroundStyle(ink.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption)
    }
}

// MARK: - The panel

/// The sheet's panel over the window: the backdrop (.38 / .78, at once), the panel at most 620 wide and 86% of the
/// window tall, radius 20, #fafafa / #1a1b1e with its line, `0 25 50 −12` black .25 and a white .9 ring (light) or the
/// dark modal shadow; in from scale .96 and 10 down over 300 ms ease-out.
struct ArisFeaturePanel<Content: View>: View {
    @Environment(\.arisPalette) private var palette
    let close: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        let ink = StoreInk(dark: palette.dark)
        let shape = RoundedRectangle(cornerRadius: ArisFeatureLook.radius, style: .continuous)
        GeometryReader { box in
            ZStack {
                palette.backdrop.ignoresSafeArea().onTapGesture(perform: close)
                content()
                    .frame(maxHeight: box.size.height * ArisFeatureLook.maxHeightShare, alignment: .top)
                    .fixedSize(horizontal: false, vertical: true)
                    .clipped()
                    .background(shape.fill(ink.panel))
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(ink.panelBorder, lineWidth: 1))
                    .overlay { if !palette.dark { shape.inset(by: -0.5).stroke(.white.opacity(0.9), lineWidth: 1) } }
                    .compositingGroup()
                    .shadow(color: .black.opacity(palette.dark ? 0.82 : 0.25), radius: palette.dark ? 32 : 25, y: palette.dark ? 24 : 25)
                    .padding(.horizontal, 16)
                    .onExitCommand(perform: close)
                    .background(Button("", action: close).keyboardShortcut(.cancelAction).opacity(0).accessibilityHidden(true))
            }
            .frame(width: box.size.width, height: box.size.height)
        }
    }
}
