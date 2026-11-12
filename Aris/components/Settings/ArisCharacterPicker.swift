//
//  ArisCharacterPicker.swift
//  Aris
//
//  The 팀원 page's character picker (the owner's pick C, mockup 11-picker.html): upstream's Bot Avatars types × its palette
//  × a shading (fabric first), and the two previews (the notch, a window) above it. Every tile is its look's baked
//  rest pose: one small atlas each, baked the first time it shows, nothing playing. Only the previews play the idle
//  loop, the same atlas a teammate on a window plays. All of them are drawn dark, as the notch and the windows draw
//  them. No hats or glasses (the user hasn't decided).
//

import SwiftUI

/// Press feedback for a tile: scale 0.97 over 140 ms on a strong ease-out (emil-design-eng: buttons scale 0.95–0.98
/// on press, 100–160 ms, custom ease-out (0.23, 1, 0.32, 1)). Reduce Motion keeps it still.
struct ArisPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.14), value: configuration.isPressed)
    }
}

/// One choice: the character on its tile, ringed when picked.
private struct ArisLookTile: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisSettingsArt) private var art
    let look: ArisCharacterLook
    let side: CGFloat
    let character: CGFloat
    let radius: CGFloat
    let selected: Bool
    let label: String
    let pick: () -> Void

    var body: some View {
        Button(action: pick) {
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(palette.tile)
                art.face(look, character, true)
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(selected ? palette.accent : palette.hairline, lineWidth: selected ? 2 : 1)
                    // A colour change: plain ease, 140 ms (emil-design-eng: hover/colour changes use ease).
                    .animation(.easeInOut(duration: 0.14), value: selected)
            }
            .frame(width: side, height: side)
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
        .buttonStyle(ArisPressStyle())
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct ArisCharacterPicker: View {
    @Environment(\.arisPalette) private var palette
    let look: ArisCharacterLook
    /// The types on offer: a teammate's every type but the one Aris wears; Aris's own seven (ArisFace.choices).
    let types: [String]
    var layout = Layout.teammate
    let pick: (ArisCharacterLook) -> Void

    /// The type row's grid. A teammate's: mockup C's, fitted to the detail card (6 a row of 54, then 질감). Aris's
    /// (Settings A): its seven faces in one row of 50, no 질감 (always fabric).
    struct Layout {
        var heading = ArisTeamCopy.faceTypeHeading
        var tile: CGFloat = 54
        var character: CGFloat = 34
        var columns = 6
        var gap: CGFloat = 6
        /// Above the 색 heading.
        var colorTop: CGFloat = 14
        var shadings = true
        /// The colour row's tiles (9 of 36 a row; the 팀원 inspector's narrower card takes 8 of 28).
        var colorTile: CGFloat = ArisCharacterPicker.colorTile
        var colorColumns = 9
        var colorCharacter: CGFloat = 24

        static let teammate = Layout()
        static var aris: Layout { Layout(heading: ArisTeamCopy.faceHeading, tile: 50, character: 32, columns: 7, gap: 5, colorTop: 18, shadings: false) }
    }

    /// 9 colours a row.
    static let colorTile: CGFloat = 36, gap: CGFloat = 6

    static func typeName(_ type: String) -> String { ArisFace.name(type) }

    static func shadingName(_ shading: String) -> String { ArisTeamCopy.shadingName(shading) ?? shading }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading(layout.heading, first: true)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(layout.tile), spacing: layout.gap), count: layout.columns), alignment: .leading, spacing: layout.gap) {
                ForEach(types, id: \.self) { type in
                    ArisLookTile(look: ArisCharacterLook(type: type, colorHex: look.type == type ? look.colorHex : nil, shading: look.shading),
                                 side: layout.tile, character: layout.character, radius: 14, selected: look.type == type, label: Self.typeName(type)) {
                        pick(ArisCharacterLook(type: type, colorHex: look.colorHex, shading: look.shading))
                    }
                }
            }
            heading(ArisTeamCopy.faceColorHeading, first: false).padding(.top, layout.colorTop - 14)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(layout.colorTile), spacing: Self.gap), count: layout.colorColumns), alignment: .leading, spacing: Self.gap) {
                ForEach(ArisCharacterLook.colorChoices(for: look.type), id: \.self) { hex in
                    ArisLookTile(look: ArisCharacterLook(type: look.type, colorHex: hex, shading: look.shading),
                                 side: layout.colorTile, character: layout.colorCharacter, radius: 12, selected: look.colorHex == hex || (hex == nil && look.colorHex == ArisCharacterLook.ownColors[look.type]), label: hex.map(ArisTeamCopy.faceColor) ?? ArisTeamCopy.faceOwnColor) {
                        pick(ArisCharacterLook(type: look.type, colorHex: hex, shading: look.shading))
                    }
                }
            }
            if layout.shadings {
                heading(ArisTeamCopy.faceTexture, first: false)
                ArisGlassSegmented(options: ArisCharacterLook.pickerShadings.map { ArisSettingOption(id: $0, title: Self.shadingName($0)) },
                                   selected: look.shading, label: ArisTeamCopy.faceTexture) { pick(ArisCharacterLook(type: look.type, colorHex: look.colorHex, shading: $0)) }
            }
        }
    }

    /// The mockup's h4: 11 semibold at ink2, +0.02 em, 14 above (none for the first) and 8 below.
    private func heading(_ text: String, first: Bool) -> some View {
        Text(text).font(.system(size: 11, weight: .semibold)).tracking(0.22).foregroundStyle(palette.desc)
            .padding(.top, first ? 0 : 14).padding(.bottom, 8)
    }
}

/// Mockup C's two previews: in the notch (dark) and on a window (light, the character on its top edge), each playing
/// the idle loop at the size a teammate on a window bakes at.
struct ArisCharacterPreviews: View {
    @Environment(\.arisSettingsArt) private var art
    let look: ArisCharacterLook
    let name: String

    private static let size: CGFloat = 44

    var body: some View {
        HStack(spacing: 8) {
            stage(dark: true)
            stage(dark: false)
        }
    }

    private func stage(dark: Bool) -> some View {
        ZStack(alignment: .bottom) {
            if dark {
                // `.pv.dark`: #000 → #000 at 53% → #1b1c22 (the notch's black, its glass gradient).
                LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.53),
                                       .init(color: Color(red: 0x1b / 255, green: 0x1c / 255, blue: 0x22 / 255), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            } else {
                LinearGradient(colors: [Color(red: 0xd9 / 255, green: 0xdc / 255, blue: 0xe3 / 255), Color(red: 0xc9 / 255, green: 0xcc / 255, blue: 0xd4 / 255)],
                               startPoint: .top, endPoint: .bottom)
                UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10, style: .continuous)
                    .fill(Color(red: 0xf4 / 255, green: 0xf4 / 255, blue: 0xf6 / 255))
                    .frame(height: 34).padding(.horizontal, 10)
            }
            art.face(look, Self.size, false)
                .accessibilityLabel(name)
                .padding(.bottom, dark ? 26 : 34)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 118)
        .overlay(alignment: .topLeading) {
            Text(dark ? ArisTeamCopy.faceInNotch : ArisTeamCopy.faceOnWindow).font(.system(size: 10, weight: .semibold))
                .foregroundStyle(dark ? Color.white.opacity(0.5) : Color.black.opacity(0.45))
                .padding(.top, 7).padding(.leading, 10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
