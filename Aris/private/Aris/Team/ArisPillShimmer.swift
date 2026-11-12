//
//  ArisPillShimmer.swift
//  Aris
//
//  The pill's working line (mockups/pill-oneline.html `.shim`): 11.5 / 560 white at .55, a soft band up to white swept
//  across it left to right in 1.2 s, then 1.2 s still (2.4 s, linear). The text is laid out by SwiftUI (an invisible
//  copy keeps its size and place) and drawn once into a Core Animation mask; the sweep is a gradient layer under it,
//  animated on the render server, so nothing runs per frame on the main thread. A sweep, never a blink. Reduce Motion
//  or 모션 줄이기: the plain line at .62, still.
//

import AppKit
import Defaults
import SwiftUI

struct ArisPillShimmerLabel: View {
    let text: String

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Default(.arisReduceMotion) private var reduceSetting

    static let size: CGFloat = 11.5
    static let weight: CGFloat = 560
    static let tracking: CGFloat = -0.115

    var body: some View {
        let still = systemReduceMotion || reduceSetting
        Text(verbatim: text)
            .font(Font(ArisFont.system(Self.size, weight: Self.weight)))
            .tracking(Self.tracking)
            .foregroundStyle(.white.opacity(still ? 0.62 : 0))
            .overlay {
                if !still { ArisShimmerLayer(text: text).allowsHitTesting(false).accessibilityHidden(true) }
            }
    }
}

private struct ArisShimmerLayer: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> ArisShimmerView { ArisShimmerView() }

    func updateNSView(_ view: ArisShimmerView, context: Context) { view.text = text }
}

final class ArisShimmerView: NSView {
    var text = "" {
        didSet { if text != oldValue { needsLayout = true } }
    }

    /// The text's mask holds still on `holder`; only the gradient under it moves.
    private let holder = CALayer()
    private let sweep = CAGradientLayer()
    private let mask = CALayer()
    private static let key = "aris.shimmer"
    /// The mockup's 2.4 s: the sweep takes the first half, the second is still.
    private static let period: CFTimeInterval = 2.4
    private static let travel: CFTimeInterval = 1.2
    /// One clock for the sweep, so a new line or width re-aims it without restarting it.
    private let begin = CACurrentMediaTime()
    private var drawn: (text: String, size: CGSize, scale: CGFloat)?
    private var aimed: CGFloat = -1

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        // The band sits in the middle of a layer three lines wide: .55 far off, .6 near, white at its centre.
        sweep.startPoint = CGPoint(x: 0, y: 0.5)
        sweep.endPoint = CGPoint(x: 1, y: 0.5)
        sweep.colors = [0.55, 0.55, 0.6, 1, 0.6, 0.55, 0.55].map { NSColor.white.withAlphaComponent($0).cgColor }
        sweep.locations = [0, 0.5 / 3, 1.2 / 3, 0.5, 1.8 / 3, 2.5 / 3, 1].map { NSNumber(value: $0) }
        holder.mask = mask
        holder.addSublayer(sweep)
        layer?.addSublayer(holder)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        let scale = window?.backingScaleFactor ?? 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        holder.frame = bounds
        mask.frame = holder.bounds
        sweep.frame = CGRect(x: 0, y: 0, width: 3 * size.width, height: size.height)
        if drawn.map({ $0.text != text || $0.size != size || $0.scale != scale }) ?? true {
            mask.contents = Self.textImage(text, size: size, scale: scale)
            mask.contentsScale = scale
            drawn = (text, size, scale)
        }
        CATransaction.commit()
        guard size.width != aimed else { return }
        aimed = size.width
        aim(width: size.width)
    }

    /// The band's centre from 0.3 widths before the line to 0.3 after it in 1.2 s, then off to the left, still, for
    /// the rest of the 2.4 s.
    private func aim(width: CGFloat) {
        let from = -1.8 * width, to = -0.2 * width
        let move = CABasicAnimation(keyPath: "transform.translation.x")
        move.fromValue = from
        move.toValue = to
        move.duration = Self.travel
        move.timingFunction = CAMediaTimingFunction(name: .linear)
        let rest = CABasicAnimation(keyPath: "transform.translation.x")
        rest.fromValue = from
        rest.toValue = from
        rest.duration = Self.period
        let group = CAAnimationGroup()
        // The later one wins while both run: the move for 1.2 s, then the rest.
        group.animations = [rest, move]
        group.duration = Self.period
        group.repeatCount = .infinity
        group.beginTime = sweep.convertTime(begin, from: nil)
        group.isRemovedOnCompletion = false
        sweep.add(group, forKey: Self.key)
    }

    /// The line in white on clear, as SwiftUI sets it: the same font, weight and tracking, centred on the height.
    static func textImage(_ text: String, size: CGSize, scale: CGFloat) -> CGImage? {
        let font = ArisFont.system(ArisPillShimmerLabel.size, weight: ArisPillShimmerLabel.weight)
        let string = NSAttributedString(string: text, attributes: [.font: font, .tracking: ArisPillShimmerLabel.tracking,
                                                                   .foregroundColor: NSColor.white])
        let px = CGSize(width: (size.width * scale).rounded(.up), height: (size.height * scale).rounded(.up))
        guard let ctx = CGContext(data: nil, width: Int(px.width), height: Int(px.height), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        let line = string.boundingRect(with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: size.height),
                                       options: [.usesLineFragmentOrigin, .usesFontLeading])
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        string.draw(with: CGRect(x: 0, y: (size.height - line.height) / 2 - line.origin.y, width: size.width + 1, height: line.height),
                    options: [.usesLineFragmentOrigin, .usesFontLeading])
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }
}
