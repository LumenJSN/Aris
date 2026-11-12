//
//  ArisMusicBars.swift
//  Aris
//
//  The bars beside the closed-notch music pill: six 2-pt bars with 1-pt gaps on a 14-pt-tall axis, each fading from
//  the tint at the top to 60 % of it at the bottom. While music plays, every bar wanders through its own smooth random
//  heights (30–100 %, a 15 s loop, starts staggered); paused, they shrink to dots.
//

import AppKit
import SwiftUI

struct MusicVisualizer: NSViewRepresentable {
    let isPlaying: Bool
    let tintColor: Color

    init(isPlaying: Bool, tintColor: Color) {
        self.isPlaying = isPlaying
        self.tintColor = tintColor
    }

    func makeNSView(context: Context) -> ArisMusicBarsView {
        let view = ArisMusicBarsView()
        view.update(playing: isPlaying, tint: NSColor(tintColor))
        return view
    }

    func updateNSView(_ view: ArisMusicBarsView, context: Context) {
        view.update(playing: isPlaying, tint: NSColor(tintColor))
    }
}

final class ArisMusicBarsView: NSView {
    static let barCount = 6
    static let barWidth: CGFloat = 2
    static let gap: CGFloat = 1
    static let axisHeight: CGFloat = 14
    static let loop: CFTimeInterval = 15
    static let keyframes = 50
    static let stagger: CFTimeInterval = 0.08
    static let heights: ClosedRange<Double> = 0.3...1
    static let collapse: CFTimeInterval = 0.3

    private var bars: [CAGradientLayer] = []
    private var playing: Bool?
    private var tint: NSColor?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for index in 0..<Self.barCount {
            let bar = CAGradientLayer()
            bar.startPoint = CGPoint(x: 0.5, y: 0)
            bar.endPoint = CGPoint(x: 0.5, y: 1)
            bar.cornerRadius = Self.barWidth / 2
            bar.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            bar.position = CGPoint(x: CGFloat(index) * (Self.barWidth + Self.gap) + Self.barWidth / 2, y: Self.axisHeight / 2)
            bar.bounds = CGRect(x: 0, y: 0, width: Self.barWidth, height: Self.barWidth)
            bar.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        bars.forEach { $0.contentsScale = scale }
    }

    func update(playing: Bool, tint: NSColor) {
        if tint != self.tint {
            self.tint = tint
            let color = tint.usingColorSpace(.extendedSRGB) ?? tint
            let colors = [color.withAlphaComponent(0.6 * color.alphaComponent).cgColor, color.cgColor]
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            bars.forEach { $0.colors = colors }
            CATransaction.commit()
        }
        guard playing != self.playing else { return }
        let first = self.playing == nil
        self.playing = playing
        playing ? play() : rest(animated: !first)
    }

    private func play() {
        let start = CACurrentMediaTime()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            var values = (0..<Self.keyframes).map { _ in Double.random(in: Self.heights) }
            values.append(values[0])
            bar.removeAllAnimations()
            bar.bounds = CGRect(x: 0, y: 0, width: Self.barWidth, height: Self.axisHeight)
            bar.transform = CATransform3DMakeScale(1, values[0], 1)
            let wander = CAKeyframeAnimation(keyPath: "transform.scale.y")
            wander.values = values
            wander.keyTimes = (0...Self.keyframes).map { NSNumber(value: Double($0) / Double(Self.keyframes)) }
            wander.calculationMode = .cubic
            wander.duration = Self.loop
            wander.repeatCount = .infinity
            wander.beginTime = start + Double(index) * Self.stagger
            bar.add(wander, forKey: "wander")
        }
        CATransaction.commit()
    }

    private func rest(animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(Self.collapse)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        for bar in bars {
            bar.removeAnimation(forKey: "wander")
            bar.bounds = CGRect(x: 0, y: 0, width: Self.barWidth, height: Self.barWidth)
            bar.transform = CATransform3DIdentity
        }
        CATransaction.commit()
    }
}
