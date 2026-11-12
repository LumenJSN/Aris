//
//  ArisVoiceGlyph.swift
//  Aris
//
//  The 18-point mark in the notch's top band: four white bars that scroll with your voice while Aris listens, the
//  same bars shrunk to dots that hop in turn while it works, and Aris's star otherwise (A5: the star, never an orb).
//  Bars 2.5 wide with 1.5 either side, 2 to 17 tall, a new height every 58 ms; dots hop on a 1.15 s cycle, each 13%
//  behind the last, grey at rest and white at the top of the hop.
//

import SwiftUI

struct ArisVoiceGlyph: View {
    enum Mode: Equatable { case wave, loading, orb }

    let mode: Mode
    /// 0…1 (the listener's level, RMS × 8).
    let level: Float
    var size: CGFloat = 18

    @State private var bars = ArisVoiceBars()

    var body: some View {
        ZStack {
            // Hidden behind the star, the bars don't need a clock.
            TimelineView(.animation(paused: mode == .orb)) { context in
                Canvas { canvas, canvasSize in
                    bars.step(at: context.date.timeIntervalSinceReferenceDate, mode: mode, level: level, size: size)
                    bars.draw(in: &canvas, size: canvasSize)
                }
            }
            .opacity(mode == .orb ? 0 : 1)
            .scaleEffect(mode == .orb ? ArisVNotch.crossfade.barsScale : 1)

            // Aris's star, still (the bars and dots are the voice and the work here).
            ArisCharacterView(size: size, isAris: true)
                .opacity(mode == .orb ? 1 : 0)
                .scaleEffect(mode == .orb ? 1 : ArisVNotch.crossfade.orbScale)
        }
        .frame(width: max(ArisVoiceBars.width, size), height: size)
        .animation(.timingCurve(ArisVNotch.crossfade.curve.0, ArisVNotch.crossfade.curve.1, ArisVNotch.crossfade.curve.2, ArisVNotch.crossfade.curve.3,
                                duration: ArisVNotch.crossfade.duration), value: mode)
        .allowsHitTesting(false)
    }
}

/// The voice mark fed the live level. Only this view observes the level, so the notch around it doesn't re-render
/// at audio rate.
struct ArisLiveVoiceGlyph: View {
    @ObservedObject private var audio = ArisController.shared.audioLevel

    let mode: ArisVoiceGlyph.Mode

    var body: some View {
        ArisVoiceGlyph(mode: mode, level: audio.value)
    }
}

/// The bars' state between frames. A class so the Canvas can advance it while drawing without invalidating the view.
final class ArisVoiceBars {
    static let count = 4
    static let barWidth: CGFloat = 2.5
    static let gap: CGFloat = 1.5
    static let width = CGFloat(count) * (barWidth + 2 * gap)
    static let minHeight: CGFloat = 2
    static let maxHeight: CGFloat = 17
    static let tick = 0.058
    static let hopPeriod = 1.15
    static let hopStagger = 0.13
    static let greyFloor = 110.0 / 255

    private struct Bar { var height = minHeight, lift: CGFloat = 0, scaleX: CGFloat = 1, scaleY: CGFloat = 1, light = 0.0 }

    private var history = Array(repeating: minHeight, count: count)
    private var shown = Array(repeating: Bar(), count: count)
    private var loudness = 0.0
    private var dotMix = 0.0
    private var lastTick = 0.0
    private var lastFrame = 0.0
    private var lastLoading = -Double.infinity

    func step(at now: Double, mode: ArisVoiceGlyph.Mode, level: Float, size: CGFloat) {
        // The clock was paused behind the star: a new listen starts flat, not with the last one's bars frozen in.
        if mode == .wave, lastFrame > 0, now - lastFrame > 0.25 {
            history = Array(repeating: Self.minHeight, count: Self.count)
            loudness = 0
        }
        let dt = lastFrame == 0 ? 1.0 / 60 : min(0.1, now - lastFrame)
        lastFrame = now
        // The level is RMS × 8; the bars take raw RMS.
        let raw = mode == .wave ? Double(level) / 8 : 0
        let above = max(0, raw - 0.012)
        let root = above > 0 ? above.squareRoot() : 0
        let target = root < 0.08 ? root * root / 0.08 : root
        loudness += (target - loudness) * (target > loudness ? 0.45 : 0.14)

        if now - lastTick >= Self.tick {
            let drive = min(1, loudness * 2.4) * (loudness > 0 ? Double.random(in: 0.85...1.15) : 1)
            history.removeFirst()
            history.append(Self.minHeight + CGFloat(min(1, drive)) * (Self.maxHeight - Self.minHeight))
            lastTick = now
        }

        if mode == .loading { lastLoading = now }
        let wantsDots = mode == .wave ? 0.0 : (mode == .loading || now - lastLoading < 0.13 ? 1 : 0)
        dotMix += (wantsDots - dotMix) * min(1, dt / 0.18)

        for index in 0..<Self.count {
            let height = history[Self.count - 1 - index]
            let normalized = Double((height - Self.minHeight) / (Self.maxHeight - Self.minHeight)).clamped01
            let hop = (now / Self.hopPeriod - Double(index) * Self.hopStagger).fract
            let rise = Self.bounce(hop)
            let speed = abs((Self.bounce((hop + 0.001).fract) - Self.bounce((hop - 0.001).fract)) / 0.002)
            let stretch = min(1, speed / 7.5)
            let squash = exp(-pow(hop - 0.94, 2) / (2 * 0.05 * 0.05))
            let mix = CGFloat(dotMix)
            let dotScaleX: Double = 1 - 0.096 * stretch + 0.119 * squash
            let dotScaleY: Double = 1 + 0.16 * stretch - 0.14 * squash
            let barLight: Double = pow(normalized, 1.5)
            var bar = Bar()
            bar.height = height + (Self.barWidth - height) * mix
            bar.lift = -0.24 * size * CGFloat(rise) * mix
            bar.scaleX = 1 + CGFloat(dotScaleX - 1) * mix
            bar.scaleY = 1 + CGFloat(dotScaleY - 1) * mix
            bar.light = barLight + (rise - barLight) * dotMix
            shown[index] = bar
        }
    }

    func draw(in canvas: inout GraphicsContext, size: CGSize) {
        let pitch = Self.barWidth + 2 * Self.gap
        let left = (size.width - Self.width) / 2
        for (index, bar) in shown.enumerated() {
            let width = Self.barWidth * bar.scaleX
            let height = bar.height * bar.scaleY
            let centerX = left + CGFloat(index) * pitch + Self.gap + Self.barWidth / 2
            let rect = CGRect(x: centerX - width / 2, y: size.height / 2 - height / 2 + bar.lift, width: width, height: height)
            let grey = Self.greyFloor + bar.light.clamped01 * (1 - Self.greyFloor)
            canvas.fill(Path(roundedRect: rect, cornerRadius: min(width, height) / 2), with: .color(Color(white: grey)))
        }
    }

    private static func bounce(_ t: Double) -> Double {
        if t < 0.4 { return 1 - pow(1 - t / 0.4, 3) }
        if t < 0.52 { return 1 }
        if t < 0.92 { return 1 - pow((t - 0.52) / 0.4, 3) }
        return 0
    }
}

private extension Double {
    var clamped01: Double { Swift.min(1, Swift.max(0, self)) }
    var fract: Double { self - floor(self) }
}

extension ArisSession.Phase {
    /// What the top band's mark shows for this phase (ArisVNotch.indicator): listening is the
    /// recording, thinking the request under way with nothing arrived, speaking the answer being said.
    var indicator: ArisVNotch.Indicator {
        ArisVNotch.indicator(recording: self == .listening, requestActive: self == .thinking, hasResult: self == .speaking,
                             speaking: self == .speaking)
    }

    var glyphMode: ArisVoiceGlyph.Mode {
        switch indicator {
        case .waveform: .wave
        case .loading: .loading
        case .orb: .orb
        }
    }
}
