//
//  ArisMutedMarks.swift
//  Aris
//
//  A muted Aris in the closed notch: the mute switch's struck speaker, still and faint (white .45, as the
//  paused-listening mark is drawn), wherever ArisMutedMark places it. In the right ear, across the camera from the
//  star, while the band's ear is free; beside the waiting answer's dot (or the pause mark) when the ear holds one; and
//  at the right end of the resting strip on a display with no camera housing, where there are no ears at all (the
//  second VM run: muted, that strip showed nothing, and neither did a parked answer's band). Nothing here blinks or
//  pulses; the mark fades in and out over 180 ms. The views take what they show, so the off-screen render draws them.
//

import SwiftUI

/// The struck speaker.
struct ArisMutedGlyph: View {
    var size: CGFloat = ArisMutedGlyph.ear
    var english = ArisUIWords.english

    /// In an ear, beside another mark, and on the 11-point strip.
    static let ear: CGFloat = 9
    static let beside: CGFloat = 8.5
    static let strip: CGFloat = 7
    static let tone = 0.45
    static let fade = Animation.easeOut(duration: 0.18)

    var body: some View {
        Image(systemName: "speaker.slash.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(.white.opacity(Self.tone))
            .accessibilityLabel(ArisQuietCopy.mutedLabel(english: english))
    }
}

/// The right ear while nothing else is in it: the mark centred 23 in from the band's edge (ArisBand.markCenter),
/// nothing when Aris is not muted.
struct ArisMutedEar: View {
    let muted: Bool

    var body: some View {
        Group {
            if muted {
                ArisMutedGlyph().transition(.opacity)
            } else {
                Color.clear
            }
        }
        .frame(width: 2 * ArisBand.markCenter)
        .animation(ArisMutedGlyph.fade, value: muted)
    }
}

/// The right ear of a turn's band and of a parked answer's: the blue dot of an answer waiting (red when it failed), or
/// the still pause mark while listening waits for another app's sound; and the muted mark, alone in the ear's middle
/// when the ear is free, left of the dot or the pause mark when it is not.
struct ArisAnswerEar: View {
    /// The waiting answer's dot; nil for none.
    let dot: Color?
    /// Listening is paused while another app plays or records.
    var paused = false
    /// Where the muted mark sits (ArisMutedMark); nil when Aris is not muted.
    var mute: ArisMutedMark.Place?

    /// Between the muted mark and the dot.
    static let between: CGFloat = 3

    var body: some View {
        ZStack(alignment: .trailing) {
            ArisMutedEar(muted: mute == .ear)
            HStack(spacing: Self.between) {
                if mute == .besideMark {
                    ArisMutedGlyph(size: ArisMutedGlyph.beside).transition(.opacity)
                }
                Group {
                    if paused {
                        // Listening paused while another app plays or records: a still, faint pause mark.
                        Image(systemName: "pause.fill")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.45))
                            .accessibilityLabel(ArisUIWords.text("다른 앱 소리 때문에 듣기 멈춤", "Listening paused: another app is playing sound"))
                            .transition(.opacity)
                    } else if let dot {
                        Circle().fill(dot).frame(width: 7, height: 7).overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))
                            .transition(.opacity)
                    }
                }
                // The parked-answer dot fades over 180 ms; it used to pop in and out with the answer.
                .animation(.easeOut(duration: 0.18), value: dot)
                .frame(width: 10)
            }
            .padding(.trailing, 14)
        }
        .animation(ArisMutedGlyph.fade, value: mute)
    }
}

/// The resting strip of a display with no camera housing, muted: the mark at its right end.
struct ArisMutedStripMark: View {
    let muted: Bool

    /// In from the strip's right end.
    static let inset: CGFloat = 9

    var body: some View {
        Group {
            if muted {
                ArisMutedGlyph(size: ArisMutedGlyph.strip).transition(.opacity)
            }
        }
        .padding(.trailing, Self.inset)
        .animation(ArisMutedGlyph.fade, value: muted)
        .allowsHitTesting(false)
    }
}
