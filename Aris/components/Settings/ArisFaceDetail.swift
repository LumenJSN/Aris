//
//  ArisFaceDetail.swift
//  Aris
//
//  Aris's row on the 팀원 page, opened like a teammate's (the owner's "Settings A", mockups/face/sa.html): its name and
//  line, the picker's tiles (its seven faces in one row, the colours nine a row; always fabric), the notice when a
//  teammate wearing the chosen face was moved to the star, and the six faces the teammates are given now (the star
//  ringed where it took Aris's type's place). The faces come from the window's art (the baked sprites).
//

import SwiftUI

struct ArisFaceDetail: View {
    /// A teammate moved off the face Aris took: the page's line and the button that opens that teammate.
    struct Moved: Equatable {
        let id: String
        let text: String
        let action: String
    }

    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let row: ArisTeamEditing.Row
    let face: ArisCharacterLook
    let moved: Moved?
    let wear: (ArisCharacterLook) -> Void
    let open: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.title)
                // Aris's own line is the app's: said in the page's wording (it stayed Korean on an English Mac).
                Text(w(row.role)).font(.system(size: 12)).foregroundStyle(palette.desc).lineLimit(1)
            }
            .padding(.bottom, 12)
            ArisCharacterPicker(look: face, types: ArisFace.choices, layout: .aris, pick: wear)
            if let moved {
                ArisFaceNotice(moved: moved, open: open).padding(.top, 12)
                    .transition(ArisSettingsMotion.reduced ? .opacity : .opacity.combined(with: .offset(y: 4)))
            }
            ArisFacePool(aris: face.type).padding(.top, 16)
        }
        .animation(ArisSettingsMotion.reduced ? nil : ArisSettingsMotion.house(0.34), value: moved)
    }
}

/// "코디도 고양이였어요. 이제 코디는 별이에요." on the warning wash, and the button that opens 코디's row.
private struct ArisFaceNotice: View {
    @Environment(\.arisPalette) private var palette
    let moved: ArisFaceDetail.Moved
    let open: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(moved.text).font(.system(size: 12)).foregroundStyle(palette.title).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            ArisSettingsButton(title: moved.action, small: true) { open(moved.id) }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.warn.opacity(0.08)))
        .accessibilityElement(children: .contain)
    }
}

/// 팀원이 받는 얼굴: the six a teammate is given by name, the star ringed in the accent once it stands in for Aris's
/// type. A face that changes drops in on the land curve (모션 줄이기: it just appears).
private struct ArisFacePool: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisSettingsArt) private var art
    let aris: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(ArisTeamCopy.facePoolTitle).font(.system(size: 11, weight: .semibold)).tracking(0.22).foregroundStyle(palette.desc).padding(.bottom, 8)
            Text(ArisKoreanText.keepAll(ArisTeamCopy.facePoolDetail))
                .font(.system(size: 12)).foregroundStyle(palette.desc).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)
            HStack(spacing: 6) {
                ForEach(Array(ArisFace.pool(aris: aris).enumerated()), id: \.offset) { _, type in slot(type) }
            }
        }
        .padding(.top, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(palette.hairline).frame(height: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(ArisTeamCopy.facePoolLabel(ArisFace.pool(aris: aris).map(ArisFace.name).joined(separator: ", ")))
    }

    private func slot(_ type: String) -> some View {
        let new = type == "star" && aris != "star"
        return VStack(spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.well)
                art.face(ArisCharacterLook(type: type, colorHex: nil, shading: ArisFace.shading), 24, true)
                    .id(type)
                    .transition(ArisSettingsMotion.reduced ? .opacity : .asymmetric(
                        insertion: .modifier(active: Drop(on: false), identity: Drop(on: true)), removal: .opacity))
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(new ? palette.accent : palette.hairline, lineWidth: new ? 1.5 : 1)
            }
            .frame(width: 36, height: 36)
            .animation(ArisSettingsMotion.reduced ? nil : .timingCurve(0.34, 1.56, 0.64, 1, duration: 0.46), value: type)
            Text(ArisFace.name(type)).font(.system(size: 10.5)).foregroundStyle(new ? palette.accent : palette.desc).lineLimit(1)
        }
        .frame(width: 52)
    }

    /// In from 8 above at .6, as the mockup's pool slot lands.
    private struct Drop: ViewModifier {
        let on: Bool
        func body(content: Content) -> some View {
            content.opacity(on ? 1 : 0).scaleEffect(on ? 1 : 0.6).offset(y: on ? 0 : -8)
        }
    }
}
