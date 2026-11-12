//
//  ArisMuteSwitch.swift
//  Aris
//
//  The mute control in the open notch's top band, the voice switch: a 32 × 19 switch 4 points right of the
//  28-point mark, green with a speaker on its thumb while Aris speaks, grey with a struck speaker while it is muted.
//  It shows while the pointer is on the mark, and stays up for as long as Aris is muted, so the state is read at a
//  glance. The closed notch carries the same struck speaker, still and faint (ArisMutedMarks.swift). Nothing here
//  blinks or pulses. The glyphs are SF Symbols.
//

import Defaults
import SwiftUI

struct ArisMuteSwitch: View {
    /// The band's mark is showing (it steps aside on the coding sessions page, and the switch goes with it).
    let shown: Bool
    /// Drawn as if the pointer were on it (the off-screen render only).
    var previewHover = false

    @Default(.arisMuted) private var muted
    @State private var hovering = false

    /// The 28-point mark slot, then a 4-point bridge so the pointer can cross to the switch.
    static let markSlot: CGFloat = 28
    static let bridge: CGFloat = 4
    /// The switch: 32 × 19, a 16-point white thumb 1.5 in that travels 13.
    static let track = CGSize(width: 32, height: 19)
    static let thumb: CGFloat = 16
    static let thumbInset: CGFloat = 1.5
    static let travel: CGFloat = 13
    /// The speaker on the thumb, an SF Symbol.
    static let glyph: CGFloat = 8.5
    /// On #32d74b; off rgba(120, 120, 128, .36) with a 1-point inner rim at white 10%.
    static let onFill = Color(red: 50 / 255, green: 215 / 255, blue: 75 / 255)
    static let offFill = Color(red: 120 / 255, green: 120 / 255, blue: 128 / 255).opacity(0.36)
    static let offRim = Color.white.opacity(0.1)
    /// The glyph: #248a3d on, #636366 off.
    static let onGlyph = Color(red: 36 / 255, green: 138 / 255, blue: 61 / 255)
    static let offGlyph = Color(red: 99 / 255, green: 99 / 255, blue: 102 / 255)
    /// Appears over 80 ms from 3 points to its right at 98%; the track and thumb change over 140 ms (CSS `ease`).
    static let appear = Animation.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.08)
    static let flip = Animation.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.14)

    private var visible: Bool { ArisMuteSwitchRule.visible(shown: shown, muted: muted, hovering: hovering || previewHover) }
    private var english: Bool { ArisUIWords.english }

    var body: some View {
        HStack(spacing: 0) {
            // The mark's own room: the pointer over it brings the switch up, and a click still reaches the mark.
            // From the body's left edge: the control at 9, the switch 32 into it (ArisVNotch.voiceSwitchMinX).
            Color.clear
                .frame(width: ArisVNotch.voiceSwitchMinX)
                .allowsHitTesting(false)
            Button { ArisQuietLive.shared.toggle() } label: { face }
                .buttonStyle(ArisMuteSwitchStyle())
                .opacity(visible ? 1 : 0)
                .scaleEffect(visible ? 1 : 0.98)
                .offset(x: visible ? 0 : 3)
                .allowsHitTesting(visible)
                .help(ArisQuietCopy.switchHelp(muted: muted, english: english))
                .accessibilityLabel(ArisQuietCopy.menuItem(english: english))
                .accessibilityValue(muted ? ArisQuietCopy.mutedLabel(english: english) : "")
                .accessibilityAddTraits(.isToggle)
        }
        .frame(height: ArisNotchHeader.height)
        // No content shape of its own: only the switch takes clicks, the mark under the clear part keeps its own.
        // It lets go when the pointer leaves the notch, however it leaves (ArisNotchHovered).
        .arisNotchHover($hovering)
        .animation(Self.appear, value: visible)
    }

    /// Green and to the right while Aris speaks; grey and to the left while muted.
    private var face: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(muted ? Self.offFill : Self.onFill)
                .overlay(Capsule().strokeBorder(Self.offRim, lineWidth: 1).opacity(muted ? 1 : 0))
            Circle().fill(.white)
                .frame(width: Self.thumb, height: Self.thumb)
                .shadow(color: .black.opacity(0.35), radius: 1.25, y: 1)
                .overlay {
                    Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: Self.glyph, weight: .semibold))
                        .foregroundStyle(muted ? Self.offGlyph : Self.onGlyph)
                }
                .offset(x: Self.thumbInset + (muted ? 0 : Self.travel))
        }
        .frame(width: Self.track.width, height: Self.track.height)
        .animation(Self.flip, value: muted)
    }
}

/// Press feedback: the switch dips a little while held.
private struct ArisMuteSwitchStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
