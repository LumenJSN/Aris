//
//  ArisStarCardView.swift
//  Aris
//
//  The repository card as the owner picked it (option B, 2026-11-17, star-mock/aris-star-mockups.html .b-*): the try
//  pages' tile material (#222327 dark, r20, p16), the repository's mark in a 36-pt well, "LumenJSN/Aris" over
//  "GitHub 저장소", the star count in a chip; under them, right-aligned, 건너뛰기 (quiet) and a small glass button
//  whose words cross-fade in one cell so it never changes width. While the star is being left a linear sweep crosses
//  its words (1.1 s, never a pulse); left, a gold star (ArisOBColor.star) pops from 0.8 over 280 ms with six sparks,
//  the count rolls up one and the card's edge warms to gold. Every move is under 300 ms on (.23, 1, .32, 1); with
//  Reduce Motion only opacity changes.
//

import SwiftUI

/// The mockup's ease-out: (.23, 1, .32, 1).
enum ArisStarMotion {
    static func out(_ seconds: Double) -> Animation { .timingCurve(0.23, 1, 0.32, 1, duration: seconds) }
    static let swap = out(0.18)
    static let edge = Animation.easeOut(duration: 0.26)
    static let roll = out(0.24)
    static let fade = Animation.easeOut(duration: 0.18)
    /// The sweep's one pass, linear.
    static let sweepSeconds = 1.1
}

struct ArisStarCardView: View {
    @ObservedObject var card: ArisStarCardModel
    let palette: ArisSetupPalette
    let reduced: Bool

    private var state: ArisStarCard.State { card.state }
    private var filled: Bool { ArisStarCard.filled(state) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            top
            actions
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(palette.tile)
                .shadow(color: palette.dark ? .black.opacity(0.6) : Color(.sRGB, red: 15 / 255, green: 23 / 255, blue: 42 / 255, opacity: 0.06),
                        radius: 14, y: palette.dark ? 16 : 8)
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(filled ? ArisOBColor.hex(0xefdb8e, palette.dark ? 0.22 : 0.6) : palette.tileLine, lineWidth: 0.75)
                .animation(ArisStarMotion.edge, value: filled)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - The repository

    private var top: some View {
        HStack(spacing: 12) {
            Image(systemName: "book.closed")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(palette.t2)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(palette.well))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(palette.wellLine, lineWidth: 1))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(ArisStarCard.repo)
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(-0.15)
                    .foregroundStyle(palette.t1)
                Text(ArisOnboardingCopy.starRepoSub)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.t2)
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            if let count = ArisStarCard.shownCount(card.count, state) { chip(count).transition(.opacity) }
        }
        .animation(ArisStarMotion.fade, value: card.count != nil)
    }

    private func chip(_ count: Int) -> some View {
        HStack(spacing: 6) {
            ArisStarMark(size: 14, filled: filled, celebrations: card.celebrations, reduced: reduced, ink: palette.t2)
            Text(count, format: .number)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(palette.t4)
                .contentTransition(reduced ? .opacity : .numericText(value: Double(count)))
                .animation(reduced ? ArisStarMotion.fade : ArisStarMotion.roll, value: count)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(palette.well))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(palette.wellLine, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ArisOnboardingCopy.starCount(count))
    }

    // MARK: - 건너뛰기 and the button

    private var actions: some View {
        let settled = filled
        return HStack(spacing: 14) {
            Spacer(minLength: 0)
            Button(ArisOnboardingCopy.skip) { card.skip() }
                .buttonStyle(ArisQuietButtonStyle(palette: palette, size: 13))
                .opacity(ArisStarCard.skips(state) ? 1 : 0)
                .allowsHitTesting(ArisStarCard.skips(state))
                .accessibilityHidden(!ArisStarCard.skips(state))
            ZStack(alignment: .trailing) {
                ArisGlassSmall(state: state, palette: palette, reduced: reduced) { card.press() }
                    .modifier(ArisStarSwap(on: !settled && state != .looking, reduced: reduced))
                    .disabled(ArisStarCard.press(state) == .none)
                HStack(spacing: 8) {
                    ArisStarMark(size: 15, filled: settled, celebrations: card.celebrations, reduced: reduced, ink: palette.t2)
                    // One line or the other (they never follow each other), so the star sits right beside its words.
                    Text(state == .thanks ? ArisOnboardingCopy.starThanks : ArisOnboardingCopy.starDone)
                        .font(.system(size: 14))
                        .foregroundStyle(palette.t4)
                }
                .modifier(ArisStarSwap(on: settled, reduced: reduced))
                .accessibilityElement(children: .combine)
                .accessibilityHidden(!settled)
            }
        }
        .frame(minHeight: 36)
        .animation(ArisStarMotion.swap, value: state)
    }
}

/// One of the labels sharing a cell: on, or off (gone with a 2-pt blur and 3 pt down; Reduce Motion: opacity alone).
struct ArisStarSwap: ViewModifier {
    let on: Bool
    let reduced: Bool

    func body(content: Content) -> some View {
        content
            .opacity(on ? 1 : 0)
            .blur(radius: on || reduced ? 0 : 2)
            .offset(y: on || reduced ? 0 : 3)
            .allowsHitTesting(on)
    }
}

/// The card's small glass button (the mockup's .glass.sm: h36, padding 0 14, 14 pt, r12), on ArisGlassRect's own body.
/// Its three labels (star as @login, starring, star on GitHub) share one cell; while starring, a sweep crosses the words.
struct ArisGlassSmall: View {
    let state: ArisStarCard.State
    let palette: ArisSetupPalette
    let reduced: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var hover = false

    private var login: String {
        switch state {
        case .ask(let login), .busy(let login): login
        default: ""
        }
    }
    private var busy: Bool { if case .busy = state { true } else { false } }
    private var web: Bool { state == .web }

    var body: some View {
        let dark = scheme == .dark
        let ink = dark ? ArisOBColor.hexa(0xf4f9fff5) : ArisOBColor.hex(0x323232)
        Button(action: action) {
            ZStack {
                if !login.isEmpty {
                    Text(ArisOnboardingCopy.starAsk("@" + login))
                        .foregroundStyle(ink)
                        .modifier(ArisStarSwap(on: !busy && !web, reduced: reduced))
                }
                ArisSweepText(text: ArisOnboardingCopy.starBusy, dim: palette.t2.opacity(0.55), bright: palette.t1, still: ink, sweeping: busy && !reduced)
                    .modifier(ArisStarSwap(on: busy, reduced: reduced))
                Text(ArisOnboardingCopy.starWeb)
                    .foregroundStyle(ink)
                    .modifier(ArisStarSwap(on: web, reduced: reduced))
            }
            .font(.system(size: 14))
            .tracking(-0.14)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background { ArisGlassRectBody(dark: dark, hover: hover && !busy, radius: 12) }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(ArisGlassPress(hoverScale: reduced ? 1 : 0.98, pressScale: reduced ? 1 : 0.97, hover: hover && !busy))
        .onHover { hover = $0 }
        .accessibilityLabel(busy ? ArisOnboardingCopy.starBusy : web ? ArisOnboardingCopy.starWeb : ArisOnboardingCopy.starAsk("@" + login))
    }
}

/// Words with a light sweeping across them, linear, once every 1.1 s (the mockup's `sweep`); `sweeping` false draws
/// them still in `still`.
struct ArisSweepText: View {
    let text: String
    let dim: Color
    let bright: Color
    let still: Color
    let sweeping: Bool

    var body: some View {
        if sweeping {
            TimelineView(.animation(minimumInterval: 1 / 60)) { context in
                let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: ArisStarMotion.sweepSeconds) / ArisStarMotion.sweepSeconds
                Text(text).foregroundStyle(gradient(phase))
            }
        } else {
            Text(text).foregroundStyle(still.opacity(0.75))
        }
    }

    /// CSS's 250%-wide band moved from 100% to −150%: its bright middle runs from −0.25 to 3.5 widths of the words.
    private func gradient(_ phase: Double) -> LinearGradient {
        let middle = -0.25 + 3.75 * phase
        return LinearGradient(stops: [.init(color: dim, location: 0), .init(color: dim, location: 0.35), .init(color: bright, location: 0.5),
                                      .init(color: dim, location: 0.65), .init(color: dim, location: 1)],
                              startPoint: UnitPoint(x: middle - 1.25, y: 0.5), endPoint: UnitPoint(x: middle + 1.25, y: 0.5))
    }
}

/// The star: an outline in `ink`, or gold and filled; each new `celebrations` pops it from 0.8 (−18°) through 1.14 to
/// rest over 280 ms and throws six sparks out 260 ms. Reduce Motion: the fill cross-fades, nothing moves.
struct ArisStarMark: View {
    let size: CGFloat
    let filled: Bool
    let celebrations: Int
    let reduced: Bool
    let ink: Color

    private struct Pop {
        var scale: CGFloat = 1
        var turn: Double = 0
        /// The sparks' run, 0 → 1; at rest 1 (none shown).
        var sparks: Double = 1
    }

    var body: some View {
        let star = ZStack {
            Image(systemName: "star")
                .font(.system(size: size * 0.86, weight: .medium))
                .foregroundStyle(ink)
                .opacity(filled ? 0 : 1)
            Image(systemName: "star.fill")
                .font(.system(size: size * 0.86, weight: .medium))
                .foregroundStyle(ArisOBColor.star)
                .shadow(color: ArisOBColor.hex(0xefdb8e, 0.28), radius: 2)
                .opacity(filled ? 1 : 0)
        }
        .frame(width: size, height: size)
        .animation(ArisStarMotion.fade, value: filled)
        .accessibilityHidden(true)
        if reduced {
            star
        } else {
            star.keyframeAnimator(initialValue: Pop(), trigger: celebrations) { view, pop in
                view
                    .scaleEffect(pop.scale)
                    .rotationEffect(.degrees(pop.turn))
                    .overlay { Self.sparks(pop.sparks, size: size) }
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    MoveKeyframe(0.8)
                    CubicKeyframe(1.14, duration: 0.168)
                    CubicKeyframe(1, duration: 0.112)
                }
                KeyframeTrack(\.turn) {
                    MoveKeyframe(-18)
                    CubicKeyframe(4, duration: 0.168)
                    CubicKeyframe(0, duration: 0.112)
                }
                KeyframeTrack(\.sparks) {
                    MoveKeyframe(0)
                    LinearKeyframe(0, duration: 0.04)
                    CubicKeyframe(1, duration: 0.26, startVelocity: 3, endVelocity: 0)
                }
            }
        }
    }

    /// Six 2 × 4 sparks at 60° steps, out from 9 to 15 (on a 16-pt star), fading and shortening as they go.
    nonisolated private static func sparks(_ run: Double, size: CGFloat) -> some View {
        let unit = size / 16
        return ZStack {
            ForEach(0..<6, id: \.self) { i in
                Capsule()
                    .fill(ArisOBColor.star)
                    .frame(width: 2 * unit, height: 4 * unit)
                    .scaleEffect(x: 1, y: 1 - 0.6 * run)
                    .offset(y: -(9 + 6 * run) * unit)
                    .rotationEffect(.degrees(Double(i) * 60))
            }
        }
        .opacity(run < 1 ? 1 - run : 0)
        .allowsHitTesting(false)
    }
}
