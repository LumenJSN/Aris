//
//  ArisOnboardingNotch.swift
//  Aris
//
//  The real notch while the onboarding holds it (ArisNotchModel.guide), drawn in the notch's own window
//  (mockups/onboarding2/js/notch.js, css/scenes.css): the silhouette morphing between the camera's notch, the voice
//  band (talk), the one-line message and rest, on the notch's own clocks; the band flexing when the star lands; the star
//  docked in the left slot at its own 22-pt size (working while macOS asks); the five voice bars while Aris speaks;
//  and each page's line lit word by word. The guide hands the notch back whenever Aris really listens, answers or
//  dictates, and for good at the finish, so this never covers the real thing.
//

import SwiftUI

struct ArisOnboardingNotch: View {
    @ObservedObject var guide: ArisOnboardingGuide
    /// The offscreen renders pin the clock.
    var frozen: Double?
    /// The canvas's width (the notch window's): the shapes are drawn about its centre line.
    var canvas: CGSize = windowSize

    private var still: Bool { (guide.phase == .setup && guide.narration == nil) || frozen != nil }

    var body: some View {
        TimelineView(.animation(paused: still)) { _ in
            frame(now: frozen ?? ArisOnboardingGuide.now())
        }
        .frame(width: canvas.width, height: canvas.height, alignment: .top)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .allowsHitTesting(false)
    }

    private func frame(now: Double) -> some View {
        let cx = Double(canvas.width) / 2, form = guide.morph.form(at: now)
        let speaking = guide.spoken.map { $0.captions(synthStarts: guide.audio?.synthStarts ?? []).speaking(at: now) && !$0.done } ?? false
        return ZStack(alignment: .topLeading) {
            Path(form.outline(cx: cx))
                .fill(Color(.sRGB, red: 0, green: 0, blue: 2 / 255, opacity: 0.98))
                .shadow(color: .black.opacity(0.28), radius: 6, y: 5)
                .shadow(color: Color(.sRGB, red: 235 / 255, green: 245 / 255, blue: 1, opacity: 0.22), radius: 0.45)
            star(form: form, cx: cx, now: now)
            bars(form: form, cx: cx, now: now, on: speaking)
            line(form: form, cx: cx, now: now)
        }
        .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
    }

    // MARK: - The star

    private func star(form: ArisNotchForm, cx: Double, now: Double) -> some View {
        let slot = form.slot(cx: cx)
        let wobble = ArisOnboardingMotion.wobble((now - guide.popAt) * 1000, amp: 0.24, tau: 110, period: 280)
        var opacity = guide.docked ? 1.0 : 0
        if guide.reduced, guide.phase == .flight, let flight = guide.flight {
            opacity = ArisOnboardingMotion.span((now - flight.start) * 1000, 250, 450)
        }
        return ArisOnboardingStar(size: ArisOnboardingScore.dock, state: guide.starWorking ? .working : .default, paused: guide.reduced, spot: .notch)
            .scaleEffect(x: 1 + wobble, y: 1 - wobble, anchor: .top)
            .opacity(opacity)
            .position(x: slot.x, y: slot.y)
            .accessibilityElement()
            .accessibilityLabel(ArisOnboardingCopy.starLabel)
            .accessibilityHidden(opacity < 0.5)
    }

    // MARK: - The voice bars

    private func bars(form: ArisNotchForm, cx: Double, now: Double, on: Bool) -> some View {
        let levels = on ? (guide.audio?.levels(at: now) ?? []) : []
        return HStack(spacing: 2.5) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white.opacity(0.92))
                    .frame(width: 2.5, height: 14)
                    .scaleEffect(y: 0.18 + 0.82 * Double(i < levels.count ? levels[i] : 0))
            }
        }
        .frame(height: 32)
        .position(x: form.barsX(cx: cx) + 11.25, y: form.bandY)
        .opacity(on ? 1 : 0)
        .animation(.easeOut(duration: 0.18), value: on)
        .accessibilityHidden(true)
    }

    // MARK: - The line under the band

    @ViewBuilder
    private func line(form: ArisNotchForm, cx: Double, now: Double) -> some View {
        let origin = form.lineOrigin(cx: cx)
        if let narration = guide.narration {
            let lit = narration.words.indices.map { i -> Double in
                let at = narration.start + ArisNarration.firstWord + Double(i) * ArisNarration.wordStep
                return narration.reduced ? 1 : ArisOnboardingMotion.span(now, at, at + 0.16)
            }
            narration.words.indices.reduce(Text("")) { text, i in
                text + Text((i == 0 ? "" : " ") + narration.words[i]).foregroundColor(.white.opacity(0.38 + (0.97 - 0.38) * easeOut(lit[i])))
            }
            .font(.system(size: 14, weight: .medium))
            .tracking(-0.14)
            .lineLimit(1)
            .fixedSize()
            .opacity(narration.opacity(at: now))
            .offset(x: origin.x, y: origin.y)
            .accessibilityLabel(narration.words.joined(separator: " "))
            .accessibilityAddTraits(.updatesFrequently)
        }
    }

    private func easeOut(_ x: Double) -> Double { 1 - (1 - x) * (1 - x) }
}
