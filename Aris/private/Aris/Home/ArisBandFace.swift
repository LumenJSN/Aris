//
//  ArisBandFace.swift
//  Aris
//
//  The open notch's top band laid out on its grid (ArisVNotch): the 28-point
//  control holding the 18-point mark 9 points from the body's left edge, the voice switch 32 points into that control
//  (41 from the edge), and the right slot ending 14 points from the body's right edge, all centred on the band's
//  height. The band spans the notch's body (440), not the content inside its 12-point inset: the mark used to sit 14
//  points further in, and Stop and Close the same on the right.
//  Only the layout and the glow are here, so the off-screen renders draw the same band the app does.
//

import SwiftUI

struct ArisBandFace<Mark: View, Beside: View, Trailing: View>: View {
    /// The notch's body: the band's own width.
    let bodyWidth: CGFloat
    let height: CGFloat
    /// The mark in its 28-point control.
    @ViewBuilder let mark: () -> Mark
    /// What appears beside the mark from the body's left edge (the voice switch brings its own 41-point lead).
    @ViewBuilder let beside: () -> Beside
    /// The right slot's content, right-aligned.
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        ZStack {
            mark()
                .frame(width: ArisVNotch.orbBox, height: ArisVNotch.orbBox)
                .padding(.leading, ArisVNotch.orbLeft)
                .frame(maxWidth: .infinity, alignment: .leading)
            beside()
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
                .padding(.trailing, ArisVNotch.slotTrailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(width: bodyWidth, height: height)
    }
}

/// The glow behind the mark, its halo: only while Aris speaks or after a failure, a soft
/// round light reaching 10 points past the mark (9 in error), breathing over 2.6 s. Aris's own sky blue while it
/// speaks, red for a failure. It fades in and out over 180 ms; with Reduce Motion it holds still.
struct ArisMarkHalo: View {
    let halo: ArisVNotch.Halo
    var size: CGFloat = ArisVNotch.orbSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    /// rgb(255, 69, 58): the error glow.
    static let errorColor = Color(.sRGB, red: 1, green: 69 / 255, blue: 58 / 255, opacity: 1)
    /// Aris's sky blue (ArisOrb.glow).
    static let speakingColor = Color(.sRGB, red: 0.45, green: 0.78, blue: 1, opacity: 1)
    /// The pulse: opacity .65 ↔ 1 and scale .96 ↔ 1.04; speaking .72 ↔ 1 and .98 ↔ 1.07.
    static let period = 2.6

    var body: some View {
        let spec = ArisVNotch.haloSpec(halo)
        let color = halo == .error ? Self.errorColor : Self.speakingColor
        let alphas = spec?.alphas ?? [0, 0, 0]
        let side = size + 2 * (spec?.outset ?? 9)
        Circle()
            .fill(RadialGradient(stops: [
                .init(color: color.opacity(alphas[0]), location: 0),
                .init(color: color.opacity(alphas[1]), location: 0.30),
                .init(color: color.opacity(alphas[2]), location: 0.55),
                .init(color: color.opacity(0), location: 0.78),
            ], center: .center, startRadius: 0, endRadius: side / 2))
            .frame(width: side, height: side)
            .blur(radius: spec?.blur ?? 3)
            .scaleEffect(scale)
            .opacity(halo == .none ? 0 : dim)
            .animation(.easeInOut(duration: 0.18), value: halo)
            // Breathes only while it shows; each time it comes up it starts from its small, dim end.
            .onChange(of: halo, initial: true) { _, now in
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) { breathing = false }
                guard now != .none, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: Self.period / 2).repeatForever(autoreverses: true)) { breathing = true }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var scale: CGFloat {
        guard halo != .none, !reduceMotion else { return 1 }
        return halo == .speaking ? (breathing ? 1.07 : 0.98) : (breathing ? 1.04 : 0.96)
    }

    private var dim: Double {
        guard !reduceMotion else { return 1 }
        return halo == .speaking ? (breathing ? 1 : 0.72) : (breathing ? 1 : 0.65)
    }
}

/// The four bars alone (ArisVoiceBars, the waveform: 2.5 wide, 2 to 17 tall, a new height every 58 ms), for the
/// closed band, where the star is drawn by the notch's own stage. Its clock runs only while it listens.
struct ArisVoiceBarsView: View {
    let listening: Bool
    /// 0…1 (the listener's level, RMS × 8), asked for as each frame is drawn, so nothing re-renders at audio rate.
    let level: () -> Float
    var size: CGFloat = ArisVNotch.orbSize
    /// Bars to draw as they stand (the off-screen render only: a still has no clock to scroll them in).
    var preview: [Float] = []

    @State private var bars = ArisVoiceBars()

    var body: some View {
        TimelineView(.animation(paused: !listening)) { context in
            Canvas { canvas, canvasSize in
                for (step, loud) in preview.enumerated() {
                    bars.step(at: Double(step + 1) * ArisVoiceBars.tick * 1.01, mode: .wave, level: loud, size: size)
                }
                if preview.isEmpty {
                    bars.step(at: context.date.timeIntervalSinceReferenceDate, mode: listening ? .wave : .orb, level: level(), size: size)
                }
                bars.draw(in: &canvas, size: canvasSize)
            }
        }
        .frame(width: max(ArisVoiceBars.width, size), height: size)
        .opacity(listening ? 1 : 0)
        .scaleEffect(listening ? 1 : ArisVNotch.crossfade.barsScale)
        .animation(.timingCurve(ArisVNotch.crossfade.curve.0, ArisVNotch.crossfade.curve.1, ArisVNotch.crossfade.curve.2, ArisVNotch.crossfade.curve.3,
                                duration: ArisVNotch.crossfade.duration), value: listening)
        .allowsHitTesting(false)
    }
}

/// The hands-free mark in the band's right slot: a small white lock while Aris keeps listening by itself, an ×
/// in its place under the pointer (the two trade places over 160 ms). A press ends the listening, as Esc does.
/// The lock is an SF Symbol in a 14 × 18 box.
struct ArisHandsFreeLock: View {
    let action: () -> Void
    /// Drawn as if the pointer were on it (the off-screen render only).
    var previewHover = false

    @State private var hovering = false

    static let box = CGSize(width: 14, height: 18)

    var body: some View {
        let over = hovering || previewHover
        Button(action: action) {
            ZStack {
                Image(systemName: "lock.fill").font(.system(size: 12.5, weight: .semibold)).opacity(over ? 0 : 1)
                Image(systemName: "xmark").font(.system(size: 10.5, weight: .bold)).opacity(over ? 1 : 0)
            }
            .foregroundStyle(.white)
            .frame(width: Self.box.width, height: Self.box.height)
            .frame(width: ArisVNotch.stopSize, height: ArisVNotch.stopSize, alignment: .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(ArisLockStyle())
        .arisNotchHover($hovering)
        .animation(.easeInOut(duration: 0.16), value: over)
        // Said to assistive tools only: a system tooltip over the closed band keeps the notch's hover from arriving.
        .accessibilityLabel(ArisBandWords.endListening(english: ArisUIWords.english))
    }
}

/// Press feedback: the lock dips a little while held.
private struct ArisLockStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// The band's own words.
enum ArisBandWords {
    static func endListening(english: Bool) -> String { english ? "Stop listening (esc)" : "듣기 끝내기 (esc)" }
}

/// The attachment count in the band's right slot: a 13-point paperclip and the number in a 15-point capsule
/// (white 14 %, 11-point medium), while files given to Aris wait for the next request and the notch is closed. With an
/// answer parked (or a turn's pause) its mark rides on the capsule's top-right corner (ArisBandEar).
struct ArisAttachCount: View {
    let count: Int
    /// The waiting answer's dot, in its colour (blue, red after a failure); nil for none.
    var dot: Color?
    /// Listening waits while another app plays or records: the still pause mark on the corner instead.
    var paused = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "paperclip")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.82))
                .frame(width: 13, height: 13)
            Text("\(count)")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 3)
                .frame(minWidth: 15, minHeight: 15)
                .background(Capsule().fill(.white.opacity(0.14)))
                .overlay(alignment: .topTrailing) { badge }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ArisBandWords.filesWaiting(count, english: ArisUIWords.english))
        // The parked answer's dot used to fade over 180 ms; it does on the corner too.
        .animation(.easeOut(duration: 0.18), value: dot)
        .animation(.easeOut(duration: 0.18), value: paused)
    }

    /// The dot (or pause mark) on the corner, ringed in the band's black so it reads apart from the capsule.
    @ViewBuilder private var badge: some View {
        let side = ArisBandEar.badgeSize, shift = side / 2 - ArisBandEar.badgeInset
        Group {
            if paused {
                Image(systemName: "pause.fill")
                    .font(.system(size: 5.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: side, height: side)
                    .background(Circle().fill(.black))
            } else if let dot {
                Circle().fill(dot).frame(width: side, height: side)
                    .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))
                    .background(Circle().fill(.black).padding(-1.5))
            }
        }
        .offset(x: shift, y: -shift)
        .transition(.opacity)
    }
}

extension ArisBandWords {
    static func filesWaiting(_ count: Int, english: Bool) -> String {
        english ? (count == 1 ? "1 file waits for your next request" : "\(count) files wait for your next request") : "파일 \(count)개가 다음 요청을 기다려요"
    }
}
