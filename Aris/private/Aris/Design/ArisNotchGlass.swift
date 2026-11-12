//
//  ArisNotchGlass.swift
//  Aris
//
//  The shipped notch's material (the look `private-glass`, ArisGlassLook). One AppKit view fills a fixed area
//  behind the notch and holds, bottom to top:
//    the shadow    the notch's drop shadow and cool rim, shown only outside the outline;
//    the glass     `NSGlassEffectView`, regular style, tint sRGB(0, 0, .02, .18), with its private settings and
//                  the outline as its own path (ArisGlassPrivate);
//    the black     a `CAGradientLayer` (black 1, 1, .5 at 0, .53, 1 from the top, ending max(height, safe-area top /
//                  0.53) down) masked by a `CAShapeLayer` with the same outline.
//  The notch's content is SwiftUI's, above this view, clipped to the same outline.
//
//  Motion. The glass is drawn again on every frame of a morph from an eased sample of (width, height, radius), with
//  the same duration and cubic-bezier as the content. The sample is animatable data: SwiftUI eases it in the very
//  transaction that moves the content (open 280 ms, close 200 ms, a size change 340 ms) and calls `update` with each
//  frame's value, which sets the glass's path, the gradient's mask and end point and the shadow in one CATransaction
//  with actions off. So the glass cannot lag the outline: both come from one clock, and only the path moves, never
//  the glass view.
//
//  A part of the private glass that does not take is told to ArisGlassHealth, and the surface then draws
//  `clear-glass` (ArisGlassFallback).
//

import AppKit
import OSLog
import SwiftUI

/// Which private glass parts this macOS took, asked once and corrected if one later fails; the surface reads it to
/// choose between the private glass and `clear-glass`.
@MainActor
final class ArisGlassHealth: ObservableObject {
    static let shared = ArisGlassHealth()
    @Published private(set) var parts: ArisGlassParts
    private let log = Logger(subsystem: "com.lumenjsn.aris", category: "glass")

    private init() {
        parts = ArisGlassPrivate.probe()
        report()
    }

    /// A part stopped taking on a live view: from now on the notch draws the public look. Logged once per part.
    /// Told after the current view update, since it is found while a view is being made or drawn.
    func failed(_ part: WritableKeyPath<ArisGlassParts, Bool>) {
        Task { @MainActor in
            guard self.parts[keyPath: part] else { return }
            self.parts[keyPath: part] = false
            self.report()
        }
    }

    private func report() {
        log.notice("\(ArisGlassFallback.logLine(self.parts), privacy: .public)")
    }
}

/// The glass, the black and the shadow for one eased frame of the notch. Animatable: SwiftUI hands `body` every
/// frame's sample while the notch opens, closes or grows.
@available(macOS 26.0, *)
struct ArisNotchGlass: View, Animatable {
    var sample: ArisNotchGlassSample
    /// The display's safe-area top (0 without a camera housing).
    let safeTop: CGFloat
    /// False while the notch is hidden: the glass is hidden then, and only then.
    let active: Bool

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat>> {
        get { AnimatablePair(AnimatablePair(sample.width, sample.height), AnimatablePair(AnimatablePair(sample.top, sample.bottom), sample.openness)) }
        set {
            sample = ArisNotchGlassSample(width: newValue.first.first, height: newValue.first.second, top: newValue.second.first.first,
                                          bottom: newValue.second.first.second, openness: newValue.second.second)
        }
    }

    var body: some View {
        ArisNotchGlassHost(sample: sample, safeTop: safeTop, active: active)
    }
}

@available(macOS 26.0, *)
private struct ArisNotchGlassHost: NSViewRepresentable {
    let sample: ArisNotchGlassSample
    let safeTop: CGFloat
    let active: Bool

    func makeNSView(context: Context) -> ArisNotchGlassView { ArisNotchGlassView() }

    func updateNSView(_ view: ArisNotchGlassView, context: Context) {
        view.update(sample, safeTop: safeTop, active: active)
    }

    static func dismantleNSView(_ view: ArisNotchGlassView, coordinator: ()) { view.release() }
}

@available(macOS 26.0, *)
final class ArisNotchGlassView: NSView {
    private let shade = NSView()
    private let drop = CALayer()
    private let dropMask = CAShapeLayer()
    private let rim = CALayer()
    private let rimMask = CAShapeLayer()
    private let glass = NSGlassEffectView()
    private let black = NSView()
    private let gradient = CAGradientLayer()
    private let gradientMask = CAShapeLayer()
    private var sample = ArisNotchGlassSample(width: 0, height: 0, top: 0, bottom: 0, openness: 0)
    private var safeTop: CGFloat = 0
    private var active = true
    /// The window whose active appearance this view forced, to give it back.
    private weak var forcedWindow: NSWindow?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false

        // The shadow: two layers that have only a shadow, each cut to what lies outside the outline.
        shade.layer = CALayer()
        shade.wantsLayer = true
        for (layer, mask) in [(drop, dropMask), (rim, rimMask)] {
            mask.fillRule = .evenOdd
            layer.mask = mask
            layer.shadowOffset = .zero
            shade.layer?.addSublayer(layer)
        }
        drop.shadowColor = .black
        rim.shadowColor = CGColor(srgbRed: 235.0 / 255, green: 245.0 / 255, blue: 1, alpha: 1)
        rim.shadowRadius = ArisNotchGlassGeometry.rimRadius

        // The glass: regular style, tint sRGB(0, 0, .02, .18); its private settings are ArisGlassPrivate's. Dark
        // whatever the Mac's appearance, as the notch's panel is.
        glass.style = .regular
        glass.tintColor = NSColor(srgbRed: 0, green: 0, blue: ArisGlassRecipe.tintBlue, alpha: ArisGlassRecipe.tintAlpha)
        glass.appearance = NSAppearance(named: .darkAqua)
        let took = ArisGlassPrivate.configure(glass)
        if !took.variant { ArisGlassHealth.shared.failed(\.variant) }
        if !took.lensing { ArisGlassHealth.shared.failed(\.lensing) }

        // The black: 1, 1, .5 at 0, .53, 1, from the top.
        gradient.colors = [1, 1, ArisGlassRecipe.rimAlpha].map { CGColor(srgbRed: 0, green: 0, blue: 0, alpha: $0) }
        gradient.locations = [0, NSNumber(value: ArisGlassRecipe.darkStop), 1]
        gradient.startPoint = CGPoint(x: 0.5, y: 1)
        gradient.mask = gradientMask
        black.layer = gradient
        black.wantsLayer = true

        for view in [shade, glass, black] {
            view.autoresizingMask = [.width, .height]
            view.frame = bounds
            addSubview(view)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// A background: clicks belong to the notch's content above it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// One frame: the outline, the black's reach and the shadow, all at once and with no animation of their own.
    func update(_ sample: ArisNotchGlassSample, safeTop: CGFloat, active: Bool) {
        self.sample = sample
        self.safeTop = safeTop
        self.active = active
        draw()
    }

    override func layout() {
        super.layout()
        draw()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncWindow()
    }

    /// The view is going away (another look, or the notch itself): the window's active appearance is AppKit's again.
    func release() {
        if let forcedWindow { ArisGlassPrivate.forceActiveAppearance(forcedWindow, on: false) }
        forcedWindow = nil
    }

    private func draw() {
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        let outline = ArisNotchGlassGeometry.outline(sample, canvas: size)
        let look = ArisNotchGlassGeometry.shadow(openness: sample.openness)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if !ArisGlassPrivate.setPath(glass, outline) { ArisGlassHealth.shared.failed(\.path) }
        glass.isHidden = !active
        for layer in [drop, dropMask, rim, rimMask, gradientMask] as [CALayer] { layer.frame = CGRect(origin: .zero, size: size) }
        gradientMask.path = outline
        gradient.endPoint = CGPoint(x: 0.5, y: ArisNotchGlassGeometry.gradientEnd(height: sample.height, safeTop: safeTop, canvasHeight: size.height))
        let outside = ArisNotchGlassGeometry.outside(outline, canvas: size, reach: 4 * CGFloat(ArisNotchGlassGeometry.shadowOpen.radius))
        drop.shadowPath = outline
        drop.shadowOpacity = Float(look.opacity)
        drop.shadowRadius = look.radius
        drop.shadowOffset = CGSize(width: 0, height: -look.drop)
        dropMask.path = outside
        rim.shadowPath = outline
        rim.shadowOpacity = Float(ArisNotchGlassGeometry.rimOpacity * Double(min(1, max(0, sample.openness))))
        rimMask.path = outside
        CATransaction.commit()
    }

    /// The notch's panel keeps its glass in the active look while this view is in it, and gets its own back when
    /// the view leaves.
    private func syncWindow() {
        if let forcedWindow, forcedWindow !== window { release() }
        guard let window, forcedWindow == nil else { return }
        if ArisGlassPrivate.forceActiveAppearance(window, on: true) {
            forcedWindow = window
        } else {
            ArisGlassPrivate.forceActiveAppearance(window, on: false)
            ArisGlassHealth.shared.failed(\.activeAppearance)
        }
    }
}
