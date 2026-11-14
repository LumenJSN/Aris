//
//  ArisSideLayers.swift
//  Aris
//
//  A side notch's body, drawn and animated by Core Animation: one outline
//  (ArisSideOutline) that fills the panel, masks its SwiftUI content, and carries the rim. Changing state animates
//  the outline's points on the render server, so the morph keeps its frame rate whatever the content costs.
//
//  The sliver's dots live inside the same clip (a mask animated with the outline), so they grow out of the edge and
//  are cut off by the contour as it narrows, with a short blur-in.
//
//  The body, bottom to top, each in a view of its own so AppKit keeps the order (every number is ArisSideLook's):
//    the rim       a white shadow of radius 2 behind the outline, .12 on the sliver and gone by 42 points of width;
//    the material  the glass (ArisSideGlassView: the top notch's glass tinted sRGB(0, 0, .015, .9), the outline
//                  as its path), or where a private part is missing the public blur Aris drew before, or with Reduce
//                  Transparency nothing;
//    the wash      rgba(0, 0, 6, .95) in the outline, in every state (solid where no material is
//                  under it: Reduce Transparency, and the closed sliver of the blur fallback);
//    the content   SwiftUI's, masked by the outline; above it the sliver's dots.
//  On the glass the open panel has no shadow of its own; the blur fallback keeps the soft
//  shadow and faint lit edge it had (without the blur the app behind read through the wash as crisp text, QA BUG-34).
//

import AppKit
import Combine
import CoreImage
import QuartzCore

@MainActor
final class ArisSideLayers: NSObject {
    enum Motion {
        case none, opening, closing, sliver

        /// The clock for this change (ArisSideLook: open 280 ms, close 200 ms, the sliver 180 ms).
        var look: ArisSideLook.Timing? {
            switch self {
            case .none: nil
            case .opening: ArisSideLook.opening
            case .closing: ArisSideLook.closing
            case .sliver: ArisSideLook.sliver
            }
        }

        var duration: CFTimeInterval {
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { return 0 }
            return look?.duration ?? 0
        }

        var timing: CAMediaTimingFunction {
            let curve = look ?? ArisSideLook.sliver
            return CAMediaTimingFunction(controlPoints: Float(curve.x1), Float(curve.y1), Float(curve.x2), Float(curve.y2))
        }
    }

    private let edge: ArisSidePanels.Edge
    private let container: NSView
    private let content: NSView
    /// Behind everything: the rim, and the blur fallback's shadow and lit edge.
    private let under = ArisSidePassiveView()
    private let rim = CAShapeLayer()
    /// The wash, over the material.
    private let washView = ArisSidePassiveView()
    private let fill = CAShapeLayer()
    private let mask = CAShapeLayer()
    /// The glass (macOS 26 with every private part): an ArisSideGlassView, made when first needed.
    private var glass: NSView?
    /// The public fallback: the window behind, blurred, clipped to the outline, shown only open.
    private let backdrop = NSVisualEffectView()
    private let backdropMask = CAShapeLayer()
    private var material = ArisSideLook.Material.solid
    /// The dots, clipped by a mask that follows the outline; the column inside slides from the edge to the sliver's middle.
    private let dotsView = ArisSidePassiveView()
    private let dotsClip = CALayer()
    private let dotsMask = CAShapeLayer()
    private let dotColumn = CALayer()
    private let blur = CIFilter(name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: 4])
    private var dotLayers: [CALayer] = []
    private var dots: [ArisSideSliver.Dot]?
    private var dotsVisible = false
    private var dotsToken = 0
    /// Shadow-only layers for the open panel of the blur fallback: a soft shadow and a faint lit edge.
    private let glows: [CAShapeLayer]
    private var spec: ArisSideOutline.Spec?
    private var open = false
    private var glowTask: Task<Void, Never>?
    /// Runs while the outline moves, to hand the glass the outline that is on screen.
    private var link: CADisplayLink?
    /// The outline's morph now running on the render server, for the glass to be sampled from (ArisSideMorph).
    private var morph: ArisSideMorph?
    private var linkUntil: CFTimeInterval = 0
    private var health: AnyCancellable?

    /// macOS's Reduce Transparency: the wash is solid and nothing is drawn under it.
    private static var reduceTransparency: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency }

    /// The wash for a state: .95 wherever a material is under it, solid where none is.
    private func wash(open: Bool) -> CGColor {
        let covered = material == .glass || (material == .blur && open)
        let alpha = covered ? ArisGlassRecipe.sideWash(reduceTransparency: Self.reduceTransparency) : 1
        return CGColor(srgbRed: 0, green: 0, blue: ArisSideLook.washBlue, alpha: alpha)
    }

    init(edge: ArisSidePanels.Edge, container: NSView, content: NSView) {
        self.edge = edge
        self.container = container
        self.content = content
        // The blur fallback's open panel: a soft shadow and a faint lit edge (the glass has neither).
        let glowStyles: [(CGColor, Float, CGFloat, CGSize)] = [
            (.black, 0.32, 10, CGSize(width: 0, height: -6)),
            (CGColor(srgbRed: 235 / 255, green: 245 / 255, blue: 1, alpha: 1), 0.22, 0.6, .zero),
        ]
        glows = glowStyles.map { color, opacity, radius, offset in
            let layer = CAShapeLayer()
            layer.fillColor = nil
            layer.shadowColor = color
            layer.shadowOpacity = opacity
            layer.shadowRadius = radius
            layer.shadowOffset = offset
            layer.opacity = 0
            return layer
        }
        super.init()
        container.wantsLayer = true
        content.wantsLayer = true
        // The rim (ArisSideLook.rimRadius, rimOpacity): the glass layer's white shadow, with no offset.
        rim.fillColor = nil
        rim.shadowColor = .white
        rim.shadowRadius = ArisSideLook.rimRadius
        rim.shadowOffset = .zero
        rim.shadowOpacity = 0
        for layer in glows + [rim] { under.layer?.addSublayer(layer) }
        backdrop.material = .hudWindow
        // Dark whatever the system appearance: the side notch is always the dark glass.
        backdrop.appearance = NSAppearance(named: .darkAqua)
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.wantsLayer = true
        backdrop.alphaValue = 0
        backdrop.autoresizingMask = [.width, .height]
        backdropMask.fillColor = .black
        backdrop.layer?.mask = backdropMask
        fill.fillColor = wash(open: false)
        washView.layer?.addSublayer(fill)
        // Bottom to top under the content: the rim, the material, the wash.
        for view in [washView, backdrop, under] as [NSView] {
            view.frame = container.bounds
            container.addSubview(view, positioned: .below, relativeTo: nil)
        }
        mask.fillColor = .black
        content.layer?.mask = mask
        dotsView.layerUsesCoreImageFilters = true
        blur?.name = "blur"
        dotColumn.filters = blur.map { [$0] }
        dotColumn.isHidden = true
        dotsMask.fillColor = .black
        dotsClip.mask = dotsMask
        dotsClip.addSublayer(dotColumn)
        dotsView.layer?.addSublayer(dotsClip)
        dotsView.frame = container.bounds
        container.addSubview(dotsView, positioned: .above, relativeTo: content)
        layout()
        // A private glass part that stops taking: the body goes to its public blur at once.
        health = ArisGlassHealth.shared.$parts.dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.materialMayHaveChanged() }
        }
    }

    /// Frames follow the container (it is always the window's full size).
    func layout() {
        let bounds = container.bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [fill, mask, dotsMask, dotsClip, backdropMask, rim] + glows { layer.frame = bounds }
        CATransaction.commit()
    }

    /// `force`: redraw even if the state is the same (the window changed size under it).
    func apply(_ next: ArisSideOutline.Spec, open nextOpen: Bool, dots nextDots: [ArisSideSliver.Dot], motion: Motion, force: Bool = false) {
        guard force || next != spec || nextOpen != open || nextDots != dots else { return }
        let path = ArisSideOutline.path(next, place: place)
        let opening = nextOpen && !open, closing = !nextOpen && open, first = spec == nil
        // The look's hidden preference is read as the panel opens, as the top notch reads it.
        if first || opening || force { chooseMaterial() }
        let widthNow = shownWidth()
        spec = next
        open = nextOpen
        let moving: Motion = first ? .none : motion
        animate(path, motion: moving)
        animateRim(from: widthNow, to: Double(next.width), motion: moving)
        applyDots(nextDots, spec: next, open: nextOpen, motion: moving)
        animate(fill, "fillColor", to: wash(open: nextOpen), motion: motion)
        // The blur fallback only while open (closed, the sliver is solid), and never with Reduce Transparency.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = motion.duration
            backdrop.animator().alphaValue = material == .blur && nextOpen ? 1 : 0
        }
        followOutline(for: moving.duration)
        guard material != .glass else { return hideGlows() }
        if opening {
            // The shadow fades in (220 ms) as the panel settles.
            glowTask?.cancel()
            glowTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(Int(Motion.opening.duration * 1000)))
                guard let self, !Task.isCancelled, self.open, self.material != .glass else { return }
                for layer in self.glows { self.animate(layer, "opacity", to: 1 as Float, duration: 0.22, timing: CAMediaTimingFunction(name: .easeOut)) }
            }
        } else if closing {
            hideGlows()
        }
    }

    private func hideGlows() {
        glowTask?.cancel()
        for layer in glows { animate(layer, "opacity", to: 0 as Float, duration: 0.08, timing: CAMediaTimingFunction(name: .easeIn)) }
    }

    // MARK: - Material

    /// Chooses what is under the wash (ArisSideLook.material) and puts it in place: the glass, the blur, or none.
    private func chooseMaterial() {
        let next = ArisSideLook.material(look: ArisGlassLook.current(), parts: ArisGlassHealth.shared.parts,
                                         reduceTransparency: Self.reduceTransparency)
        guard next != material || (next == .glass && glass == nil) else { return }
        material = next
        if #available(macOS 26.0, *), next == .glass {
            if glass == nil {
                let view = ArisSideGlassView(frame: container.bounds)
                container.addSubview(view, positioned: .below, relativeTo: washView)
                glass = view
            }
        } else {
            removeGlass()
        }
    }

    private func removeGlass() {
        if #available(macOS 26.0, *) { (glass as? ArisSideGlassView)?.release() }
        glass?.removeFromSuperview()
        glass = nil
    }

    /// A private part failed while the glass was up: the same state again on the public material.
    private func materialMayHaveChanged() {
        guard let spec, let dots else { return }
        apply(spec, open: open, dots: dots, motion: .none, force: true)
    }

    /// While the outline moves, the glass gets the outline of the frame about to be shown on every frame (the measured
    /// side notch redraws its glass per frame of a morph too); at rest, once. Not the one on screen now: that is a frame behind
    /// the wash, and closing, the bare glass's edge showed outside it as a silver flash (ArisSideMorph).
    private func followOutline(for duration: CFTimeInterval) {
        guard glass != nil else { return stopLink() }
        guard duration > 0 else {
            stopLink()
            return setGlassOutline(fill.path)
        }
        linkUntil = (morph?.end ?? CACurrentMediaTime() + duration) + 0.05
        let frame = frameInterval
        setGlassOutline(glassPath(shown: CACurrentMediaTime() + frame, frame: frame), moving: true)
        guard link == nil else { return }
        let link = container.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    /// One frame of this screen.
    private var frameInterval: CFTimeInterval { 1 / Double(max(1, container.window?.screen?.maximumFramesPerSecond ?? 60)) }

    @objc private func tick(_ link: CADisplayLink) {
        if CACurrentMediaTime() >= linkUntil {
            stopLink()
            setGlassOutline(fill.path)
        } else {
            setGlassOutline(glassPath(shown: link.targetTimestamp, frame: link.targetTimestamp - link.timestamp), moving: true)
        }
    }

    /// The glass's outline for the frame shown at `shown`: the morph's own sample then (a frame on while it shrinks),
    /// so the glass moves with the wash and never stands outside it (ArisSideMorph).
    private func glassPath(shown: CFTimeInterval, frame: CFTimeInterval) -> CGPath? {
        guard let morph, shown < morph.end + frame else { return fill.path }
        return morph.path(at: morph.glassTime(shown: shown, frame: frame))
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
    }

    /// `moving`: mid-morph the glass stays shown even if this frame's outline has no width yet.
    private func setGlassOutline(_ path: CGPath?, moving: Bool = false) {
        guard #available(macOS 26.0, *), let glass = glass as? ArisSideGlassView else { return }
        glass.setOutline(path, visible: moving || (spec?.width ?? 0) > 0)
    }

    // MARK: - Rim

    /// The outline's width on screen now (mid-morph: the frame being shown), for the rim to start from.
    private func shownWidth() -> Double {
        guard let spec else { return 0 }
        guard let shown = fill.presentation()?.path, fill.animation(forKey: "path") != nil else { return Double(spec.width) }
        return Double(shown.boundingBoxOfPath.width)
    }

    /// The rim follows the width frame by frame (ArisSideLook.rimKeyframes): its strength is not a straight line
    /// between two states, so it is laid out along the morph's own eased clock.
    private func animateRim(from: Double, to: Double, motion: Motion) {
        let key = "shadowOpacity"
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rim.shadowOpacity = Float(ArisSideLook.rimOpacity(width: to))
        CATransaction.commit()
        rim.removeAnimation(forKey: key)
        guard motion.duration > 0, let curve = motion.look else { return }
        let frames = CAKeyframeAnimation(keyPath: key)
        frames.values = ArisSideLook.rimKeyframes(from: from, to: to, timing: curve)
        frames.calculationMode = .linear
        frames.duration = motion.duration
        rim.add(frames, forKey: key)
    }

    /// Left-edge, y-down panel coordinates to the container layer's (y-up; mirrored for the right edge).
    private func place(_ point: CGPoint) -> CGPoint {
        let bounds = container.bounds
        let panelTop = (bounds.height - ArisGlass.sideSize.height) / 2
        let x = edge == .left ? point.x : bounds.width - point.x
        return CGPoint(x: x, y: bounds.height - (panelTop + point.y))
    }

    // MARK: - Dots

    private func applyDots(_ next: [ArisSideSliver.Dot], spec: ArisSideOutline.Spec, open: Bool, motion: Motion) {
        if next != dots { rebuildDots(next) }
        dots = next
        let visible = !open && spec.width > 0 && !next.isEmpty
        if !open {
            let center = place(CGPoint(x: spec.width / 2, y: spec.top + spec.height / 2))
            animate(dotColumn, "position", to: NSValue(point: center), motion: motion)
        }
        guard visible != dotsVisible else { return }
        dotsVisible = visible
        dotsToken += 1
        let token = dotsToken
        let duration = motion.duration
        if visible {
            // Visible after 45 ms, the blur clearing over the rest of the 180.
            let delay = min(ArisSideLook.dotRevealDelay, duration)
            animateBlur(to: 0, delay: delay, duration: duration - delay)
            if delay == 0 { setDotsHidden(false); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.dotsToken == token else { return }
                self.setDotsHidden(false)
            }
        } else {
            animateBlur(to: 4, delay: 0, duration: duration)
            if duration == 0 { setDotsHidden(true); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                guard let self, self.dotsToken == token else { return }
                self.setDotsHidden(true)
            }
        }
    }

    /// A standalone layer would fade `hidden` over a quarter second on its own; the dots flip at once.
    private func setDotsHidden(_ hidden: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dotColumn.isHidden = hidden
        CATransaction.commit()
    }

    private func rebuildDots(_ next: [ArisSideSliver.Dot]) {
        let size = ArisSideSliver.dotSize, gap = ArisSideSliver.dotGap
        let height = CGFloat(next.count) * size + CGFloat(max(0, next.count - 1)) * gap
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dotColumn.bounds = CGRect(x: 0, y: 0, width: size, height: height)
        while dotLayers.count > next.count { dotLayers.removeLast().removeFromSuperlayer() }
        while dotLayers.count < next.count {
            let layer = CALayer()
            layer.cornerRadius = size / 2
            layer.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            dotColumn.addSublayer(layer)
            dotLayers.append(layer)
        }
        for (index, dot) in next.enumerated() {
            let layer = dotLayers[index]
            layer.backgroundColor = Self.color(dot)
            layer.position = CGPoint(x: size / 2, y: height - size / 2 - CGFloat(index) * (size + gap))
            // Working dots are static: nothing in the side notch blinks.
            layer.opacity = 1
        }
        CATransaction.commit()
    }

    private func animateBlur(to radius: CGFloat, delay: CFTimeInterval, duration: CFTimeInterval) {
        let key = "filters.blur.inputRadius"
        let from = dotColumn.presentation()?.value(forKeyPath: key) ?? dotColumn.value(forKeyPath: key)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dotColumn.setValue(radius, forKeyPath: key)
        CATransaction.commit()
        dotColumn.removeAnimation(forKey: key)
        guard duration > 0, let from else { return }
        let animation = CABasicAnimation(keyPath: key)
        animation.fromValue = from
        animation.toValue = radius
        animation.duration = duration
        animation.timingFunction = Motion.sliver.timing
        if delay > 0 {
            animation.beginTime = CACurrentMediaTime() + delay
            animation.fillMode = .backwards
        }
        dotColumn.add(animation, forKey: key)
    }

    private static func color(_ dot: ArisSideSliver.Dot) -> CGColor {
        func rgb(_ hex: UInt32) -> CGColor {
            CGColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
        }
        switch dot {
        case .idle: return rgb(0x383b42)
        case .working: return rgb(0xffffff)
        case .waiting: return rgb(0xf4c64e)
        case .error: return rgb(0xf16c70)
        case .completed: return rgb(0x5faaff)
        case .limit: return rgb(0xfb923c)
        }
    }

    // MARK: - Animating

    private func animate(_ path: CGPath, motion: Motion) {
        // One begin for every layer of the outline and for the glass's samples, so they all run on the same clock; a
        // shrinking morph starts a little later than its glass (ArisSideMorph.washDelay).
        let now = CACurrentMediaTime()
        var begin = now
        let shown = fill.presentation()?.path ?? fill.path
        morph = nil
        if motion.duration > 0, let look = motion.look, let shown {
            let timing = ArisSideLook.Timing(duration: motion.duration, x1: look.x1, y1: look.y1, x2: look.x2, y2: look.y2)
            if let asked = ArisSideMorph(from: shown, to: path, begin: now, timing: timing) {
                begin = ArisSideMorph.begin(now: now, frame: frameInterval, shrinking: asked.shrinks)
                morph = ArisSideMorph(from: shown, to: path, begin: begin, timing: timing)
            }
        }
        for layer in [fill, mask, dotsMask, backdropMask] {
            animate(layer, "path", to: path, duration: motion.duration, timing: motion.timing, begin: begin)
        }
        animate(rim, "shadowPath", to: path, duration: motion.duration, timing: motion.timing, begin: begin)
        for layer in glows {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.shadowPath = path
            CATransaction.commit()
        }
    }

    private func animate(_ layer: CALayer, _ key: String, to value: Any, motion: Motion) {
        animate(layer, key, to: value, duration: motion.duration, timing: motion.timing)
    }

    /// Sets the model value and runs a basic animation from what's on screen now, so a reversal mid-way is smooth.
    /// `begin`: when it starts, in CACurrentMediaTime()'s clock (nil: when committed).
    private func animate(_ layer: CALayer, _ key: String, to value: Any, duration: CFTimeInterval, timing: CAMediaTimingFunction,
                         begin: CFTimeInterval? = nil) {
        let from = layer.presentation()?.value(forKeyPath: key) ?? layer.value(forKeyPath: key)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setValue(value, forKeyPath: key)
        CATransaction.commit()
        guard duration > 0, let from else { layer.removeAnimation(forKey: key); return }
        let animation = CABasicAnimation(keyPath: key)
        animation.fromValue = from
        animation.toValue = value
        animation.duration = duration
        animation.timingFunction = timing
        if let begin {
            animation.beginTime = layer.convertTime(begin, from: nil)
            // A morph that starts a frame or two late holds its first outline until then (ArisSideMorph.washDelay).
            animation.fillMode = .backwards
        }
        layer.add(animation, forKey: key)
    }
}
