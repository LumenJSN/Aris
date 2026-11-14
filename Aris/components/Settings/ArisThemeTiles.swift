//
//  ArisThemeTiles.swift
//  Aris
//
//  설정 창 모양 as the measured preview tiles (SETTINGS-REA.md §4.2, PreviewTile): one tile per look in a radio group,
//  each 104 × 68 inside an r14 `p-3` frame, the picture r10 with a 1-pt inner line, the chosen one ringed 2.5 pt in
//  #0A84FF, and its 12-pt name (600 when chosen) under it. The pictures are Aris's own drawings of this window: the
//  sidebar beside the content card, light, dark, and half of each for 자동.
//

import SwiftUI

struct ArisThemeTiles: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let options: [ArisSettingOption]
    let selected: String
    let label: String
    let choose: (String) -> Void

    static let tile = CGSize(width: 104, height: 68)

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.id) { option in
                let on = option.id == selected
                Button { choose(option.id) } label: {
                    VStack(spacing: 6) {
                        ArisThemePicture(look: option.id)
                            .frame(width: Self.tile.width, height: Self.tile.height)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(palette.dark ? Color.white.opacity(0.1) : .black.opacity(0.1), lineWidth: 1))
                        Text(w(option.title)).font(.system(size: 12, weight: on ? .semibold : .regular)).foregroundStyle(on ? palette.title : palette.desc)
                    }
                    .padding(12)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(arisHex: 0x0a84ff), lineWidth: 2.5).opacity(on ? 1 : 0))
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(ArisPressScale(scale: ArisPressScale.measured))
                .accessibilityLabel(w(option.title))
                .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
            }
        }
        .animation(ArisSettingsMotion.hover, value: selected)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(w(label))
    }
}

/// A small picture of the settings window in one look: the tinted sidebar with three lines, the card with a title and
/// two rows. 자동 is the light one with its right half dark.
private struct ArisThemePicture: View {
    let look: String

    var body: some View {
        if look == "auto" {
            ZStack {
                window(dark: false)
                window(dark: true).mask(HStack(spacing: 0) { Color.clear; Color.black })
            }
        } else {
            window(dark: look == "dark")
        }
    }

    private func window(dark: Bool) -> some View {
        let ink: Color = dark ? .white : .black
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 2) { ForEach(0..<3, id: \.self) { _ in Circle().fill(ink.opacity(0.25)).frame(width: 3, height: 3) } }
                    .padding(.bottom, 3)
                RoundedRectangle(cornerRadius: 2).fill(ink.opacity(dark ? 0.16 : 0.1)).frame(width: 20, height: 6)
                ForEach(0..<2, id: \.self) { _ in Capsule().fill(ink.opacity(0.18)).frame(width: 16, height: 3) }
            }
            .padding(6)
            .frame(width: 32, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .top)
            VStack(alignment: .leading, spacing: 5) {
                Capsule().fill(ink.opacity(0.55)).frame(width: 22, height: 4)
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 3).fill(dark ? Color(arisHex: 0x222327) : .white).frame(height: 12)
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(ink.opacity(0.06), lineWidth: 0.5))
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(dark ? Color(arisHex: 0x18191d) : Color(arisHex: 0xf5f6f7)))
            .padding(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 3))
        }
        .background(dark ? Color(arisHex: 0x2a2c33) : Color(arisHex: 0xdfe3ea))
    }
}
