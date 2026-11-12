//
//  ArisInkOverlay.swift
//  Aris
//
//  One display's drawing surface while the user circles (plan D5): a
//  borderless, non-activating panel at status + 13 that never shows in a capture (`sharingType = .none`), never
//  becomes key and follows every Space. It holds the ink in the owner's pick E, the highlighter: the live stroke as one
//  shape layer whose path the screen's display link rebuilds only while it's fading (the fill is rasterised on the
//  render server), each seal as its own shape layer fading by itself, and the red reject loop and capsule (Core
//  Animation, so the shake runs on the render server).
//
//  Built when the pointer arms, closed (not ordered out) when the session ends: an ordered-out window keeps its
//  backing store. Headless (no panel, no display link) for the offscreen renders.
//

import AppKit
import QuartzCore

@MainActor
final class ArisInkOverlay {
    let display: UInt32
    /// The display's Cocoa frame (global, bottom-left origin).
    let screenFrame: CGRect
    let view: ArisInkView
    private var panel: NSPanel?

    /// `shownInCaptures`: an ad demo's ink (ArisAdDemo), which screen recordings must see; the real ink never shows.
    init(display: UInt32, screenFrame: CGRect, screen: NSScreen?, headless: Bool, now: @escaping () -> Double,
         shownInCaptures: Bool = false) {
        self.display = display
        self.screenFrame = screenFrame
        view = ArisInkView(frame: CGRect(origin: .zero, size: screenFrame.size), screen: headless ? nil : screen, now: now)
        guard !headless else { return }
        let panel = NSPanel(contentRect: screenFrame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + ArisGestureConstants.Session.overlayLevelOffset)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.sharingType = ArisCaptureSharing.type(demo: shownInCaptures)
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.setFrame(screenFrame, display: false)
        panel.contentView = view
        self.panel = panel
    }

    var isShown: Bool { panel?.isVisible ?? shownHeadless }
    /// The panel's capture setting and level (nil headless), for the tests.
    var sharingType: NSWindow.SharingType? { panel?.sharingType }
    var level: NSWindow.Level? { panel?.level }
    private var shownHeadless = false

    func show() {
        shownHeadless = true
        ArisOverlayCensus.shown(self) { [weak self] in self?.close() }
        guard let panel, !panel.isVisible else { return }
        panel.orderFrontRegardless()
    }

    /// Held after arming: the overlay takes the mouse (clicks don't reach the apps below) and shows a crosshair.
    /// Hands-free and before arming: click-through.
    func setInteractive(_ on: Bool) {
        panel?.ignoresMouseEvents = !on
        view.crosshair = on
    }

    var isInteractive: Bool { view.crosshair }

    func close() {
        ArisOverlayCensus.closed(self)
        view.crosshair = false // hands the cursor back before the panel goes
        view.stop()
        panel?.ignoresMouseEvents = true
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        shownHeadless = false
    }
}

/// The ink canvas. Top-left points. Live, the stroke and the seals are shape layers; headless (offscreen renders) they
/// are drawn in `draw(_:)`. The reject loop and capsule are image subviews animated with Core Animation.
@MainActor
final class ArisInkView: NSView {
    private struct Seal {
        let id: Int
        let points: [ArisGesturePoint]
        let closed: Bool
        let startedAt: Double
        var withdrawnAt: Double?
        /// Live only: the seal's own layer, fading on the render server.
        let layer: CAShapeLayer?
    }

    private struct Reject {
        let loop: ArisGestureImageView
        let capsule: ArisGestureImageView
        let startedAt: Double
        let token: Int
    }

    /// The live stroke, dropped and filtered as points come (ArisInkSmoothing), newest last; points older than the
    /// highlighter's 900 ms are dropped each frame.
    private var stroke = ArisInkSmoothing.Stroke()
    /// Live only: the stroke's one shape, filled once at the highlighter's alpha.
    private var cometLayer: CAShapeLayer?
    private var seals: [Seal] = []
    private var reject: Reject?
    private var rejectToken = 0
    private let now: () -> Double
    private weak var screen: NSScreen?
    /// On a screen (shape layers, a display link); false for the offscreen renders, which draw on demand.
    private let live: Bool
    private var link: CADisplayLink?
    private var tracking: NSTrackingArea?

    var crosshair = false {
        didSet {
            guard crosshair != oldValue else { return }
            window?.invalidateCursorRects(for: self)
            guard window != nil else { return }
            if crosshair { NSCursor.crosshair.set() } else { NSCursor.arrow.set() }
        }
    }

    init(frame: CGRect, screen: NSScreen?, now: @escaping () -> Double) {
        self.screen = screen
        live = screen != nil
        self.now = now
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        guard live, let layer else { return }
        let comet = Self.inkLayer(frame: bounds, scale: backingScale, color: ArisInkRenderer.markerColor)
        layer.addSublayer(comet)
        cometLayer = comet
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cometLayer?.frame = bounds
        for seal in seals { seal.layer?.frame = bounds }
        CATransaction.commit()
    }

    /// A shape layer the size of the view, filled with the non-zero rule at the highlighter's alpha.
    private static func inkLayer(frame: CGRect, scale: CGFloat, color: CGColor) -> CAShapeLayer {
        let l = CAShapeLayer()
        l.frame = frame
        l.contentsScale = scale
        l.fillColor = color
        l.fillRule = .nonZero
        l.strokeColor = nil
        l.opacity = Float(ArisGestureConstants.Ink.markerAlpha)
        l.actions = ["path": NSNull(), "opacity": NSNull(), "bounds": NSNull(), "position": NSNull()]
        return l
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { crosshair ? self : nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .cursorUpdate, .mouseMoved, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func cursorUpdate(with event: NSEvent) {
        if crosshair { NSCursor.crosshair.set() } else { super.cursorUpdate(with: event) }
    }

    override func mouseMoved(with event: NSEvent) {
        if crosshair { NSCursor.crosshair.set() }
    }

    // Held mode eats clicks (the controller's local monitor still sees them as "button down").
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}

    // MARK: - Ink

    /// The live stroke's curve as the next frame draws it (settled part, then the tail).
    var liveCurve: [ArisGesturePoint] { stroke.curve }

    func addTrailPoint(_ p: ArisGesturePoint) {
        // A stroke that had wholly faded starts the filter afresh.
        if let last = stroke.points.last, p.t - last.t >= ArisGestureConstants.Ink.markerLifeMs { stroke.reset() }
        stroke.add(p)
        startLink()
    }

    /// Clears the stroke in the same frame (a seal, a reject, a button press).
    func clearTrail() {
        guard !stroke.points.isEmpty else { return }
        stroke.reset()
        refresh()
    }

    func seal(points: [ArisGesturePoint], closed: Bool, id: Int) {
        let t = now()
        var layer: CAShapeLayer?
        if live, let host = self.layer {
            let l = Self.inkLayer(frame: bounds, scale: backingScale, color: ArisInkRenderer.markerColor)
            l.path = ArisInkRenderer.loopPath(points, closed: closed)
            l.opacity = 0
            host.addSublayer(l)
            l.add(Self.sealFade(), forKey: "seal")
            layer = l
        }
        seals.append(Seal(id: id, points: points, closed: closed, startedAt: t, layer: layer))
        afterSealsEnd(ArisGestureMotion.sealLifeMs)
    }

    /// The seal's capture failed: it fades out over 150 ms.
    func withdrawSeal(id: Int) {
        guard let i = seals.firstIndex(where: { $0.id == id }), seals[i].withdrawnAt == nil else { return }
        seals[i].withdrawnAt = now()
        if let l = seals[i].layer {
            let from = l.presentation()?.opacity ?? l.opacity
            l.removeAnimation(forKey: "seal")
            let out = CABasicAnimation(keyPath: "opacity")
            out.fromValue = from
            out.toValue = 0
            out.duration = ArisGestureMotion.sealWithdrawMs / 1000
            l.add(out, forKey: "withdraw")
        }
        afterSealsEnd(ArisGestureMotion.sealWithdrawMs)
    }

    /// The seal's fade, sampled from `sealStrength` (0.85 · (1 − u)², 600 ms) at the highlighter's alpha.
    private static func sealFade() -> CAKeyframeAnimation {
        let steps = 12
        let a = CAKeyframeAnimation(keyPath: "opacity")
        a.values = (0...steps).map { i -> NSNumber in
            let age = ArisGestureMotion.sealLifeMs * Double(i) / Double(steps)
            let k = ArisGestureMotion.sealStrength(ageMs: age) ?? 0
            return NSNumber(value: Double(ArisGestureConstants.Ink.markerAlpha * k))
        }
        a.keyTimes = (0...steps).map { NSNumber(value: Double($0) / Double(steps)) }
        a.duration = ArisGestureMotion.sealLifeMs / 1000
        return a
    }

    /// Live seals fade on their own: this only takes their layers away once they're over.
    private func afterSealsEnd(_ ms: Double) {
        guard live else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(ms) + 20))
            self?.prune(at: self?.now() ?? 0)
        }
    }

    /// Seals still visible at the clock's time (a withdrawn one until it has faded).
    var sealCount: Int {
        let t = now()
        return seals.filter { !Self.isOver($0, at: t) }.count
    }
    var showsReject: Bool { reject != nil }

    // MARK: - Reject

    /// Re-inks the loop red, shakes it and shows the capsule. One at a time: a new one replaces the old.
    /// `anchor` places the capsule (a picked window's click, ArisWindowPickView); the loop's bbox by default.
    func showReject(points: [ArisGesturePoint], closed: Bool, bbox: CGRect, text: String, icon: ArisGestureChrome.Icon,
                    anchor: CGRect? = nil) {
        removeReject()
        clearTrail()
        let scale = backingScale
        let pad = ArisGestureConstants.Shot.rejectPad
        let loopFrame = bbox.insetBy(dx: -pad, dy: -pad)
        let local = points.map { ArisGesturePoint(x: $0.x - loopFrame.minX, y: $0.y - loopFrame.minY, t: $0.t) }
        let loopImage = Self.image(size: loopFrame.size, scale: scale) { ctx in
            ArisInkRenderer.drawRejectLoop(ctx, points: local, closed: closed)
        }
        let capsuleImage = ArisGestureChrome.capsuleImage(text: text, icon: icon, scale: scale)
        let pill = ArisGestureMotion.capsuleFrame(loop: anchor ?? bbox, capsule: ArisGestureChrome.capsuleSize(text: text),
                                                  viewport: bounds.size)
        let margin = ArisGestureChrome.capsuleMargin
        let loopView = ArisGestureImageView(frame: loopFrame, image: loopImage)
        let capsuleView = ArisGestureImageView(frame: pill.insetBy(dx: -margin, dy: -margin), image: capsuleImage)
        // The red loop sits one below the ink, so live ink stays on top; the canvas is this view's own
        // content, so the loop sits behind nothing that matters (the comet was cleared above).
        addSubview(loopView)
        addSubview(capsuleView)
        rejectToken += 1
        let record = Reject(loop: loopView, capsule: capsuleView, startedAt: now(), token: rejectToken)
        reject = record
        guard window != nil else { return } // headless: `prepareSnapshot` poses it
        animate(record)
        let token = record.token
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(ArisGestureMotion.rejectRemoveAtMs)))
            guard let self, self.reject?.token == token else { return }
            self.removeReject()
        }
    }

    private func removeReject() {
        reject?.loop.removeFromSuperview()
        reject?.capsule.removeFromSuperview()
        reject = nil
    }

    /// The shake (a CAKeyframeAnimation), the capsule pop and the 850 ms fade, all from
    /// ArisGestureMotion so they match the offscreen renders.
    private func animate(_ r: Reject) {
        let start = CACurrentMediaTime()
        // emil-design-eng: on-screen movement eases in and out; (0.36,0.07,0.19,0.97) per keyframe, 380 ms.
        let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
        shake.values = ArisGestureMotion.shakeValues.map { NSNumber(value: Double($0)) }
        shake.keyTimes = ArisGestureMotion.shakeKeyTimes.map { NSNumber(value: Double($0)) }
        shake.timingFunctions = Array(repeating: Self.timing(ArisGestureMotion.shakeCurve),
                                      count: ArisGestureMotion.shakeValues.count - 1)
        shake.duration = ArisGestureMotion.shakeDurationMs / 1000
        r.loop.layer?.add(shake, forKey: "shake")

        // emil-design-eng: enter with ease-out and a subtle overshoot, never from scale 0 (0.7 → 1.06 → 1, 260 ms).
        let size = r.capsule.bounds.size
        let down = r.capsule.layer.map(Self.downSign) ?? 1
        let pop = CAKeyframeAnimation(keyPath: "transform")
        pop.values = ArisGestureMotion.capsulePoses.map { NSValue(caTransform3D: Self.transform($0, size: size, down: down)) }
        pop.keyTimes = ArisGestureMotion.capsuleKeyTimes.map { NSNumber(value: Double($0)) }
        pop.timingFunctions = Array(repeating: Self.timing(ArisGestureMotion.capsuleCurve), count: 2)
        pop.duration = ArisGestureMotion.capsulePopMs / 1000
        let popIn = CAKeyframeAnimation(keyPath: "opacity")
        popIn.values = ArisGestureMotion.capsulePoses.map { NSNumber(value: Double($0.opacity)) }
        popIn.keyTimes = pop.keyTimes
        popIn.duration = pop.duration
        r.capsule.layer?.add(pop, forKey: "pop")
        r.capsule.layer?.add(popIn, forKey: "popIn")

        // emil-design-eng: a fade is a colour change → `ease`; it holds to 850 ms, then fades over 0.4 s.
        for view in [r.loop, r.capsule] {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            fade.beginTime = start + ArisGestureMotion.rejectFadeAtMs / 1000
            fade.duration = ArisGestureMotion.rejectFadeDurationMs / 1000
            fade.timingFunction = Self.timing(ArisGestureMotion.fadeCurve)
            fade.fillMode = .forwards
            fade.isRemovedOnCompletion = false
            view.layer?.add(fade, forKey: "fade")
        }
    }

    // MARK: - Drawing

    /// Headless only (offscreen renders): live, the shape layers draw.
    override func draw(_ dirtyRect: NSRect) {
        guard !live, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let t = now()
        for seal in seals {
            let fade = seal.withdrawnAt.map { ArisGestureMotion.sealWithdrawal(sinceMs: t - $0) } ?? 1
            ArisInkRenderer.drawSeal(ctx, points: seal.points, closed: seal.closed, ageMs: t - seal.startedAt, fade: fade)
        }
        if let path = ArisInkRenderer.cometPath(stroke, now: t) {
            ArisInkRenderer.fill(ctx, path, color: ArisInkRenderer.markerColor, alpha: ArisGestureConstants.Ink.markerAlpha)
        }
    }

    /// One display-link frame: rebuild the stroke's tapering shape, and stop once it has faded.
    @objc private func step(_ link: CADisplayLink) {
        refresh()
        if stroke.points.isEmpty { stopLink() }
    }

    private func refresh() {
        let t = now()
        prune(at: t)
        guard let cometLayer else {
            // Headless: the whole view redraws on demand.
            needsDisplay = true
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cometLayer.path = ArisInkRenderer.cometPath(stroke, now: t)
        CATransaction.commit()
    }

    private func startLink() {
        // Headless (no screen): renders are taken on demand, nothing ticks.
        guard link == nil, let screen else { return }
        let link = screen.displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
    }

    /// Ends everything this view runs (the panel is closing).
    func stop() {
        stopLink()
        removeReject()
        stroke.reset()
        cometLayer?.path = nil
        for seal in seals { seal.layer?.removeFromSuperlayer() }
        seals.removeAll()
    }

    private func prune(at t: Double) {
        stroke.prune(before: t - ArisGestureConstants.Ink.markerLifeMs)
        if let last = stroke.points.last, t - last.t >= ArisGestureConstants.Ink.markerLifeMs { stroke.reset() }
        for seal in seals where Self.isOver(seal, at: t) { seal.layer?.removeFromSuperlayer() }
        seals.removeAll { Self.isOver($0, at: t) }
    }

    private static func isOver(_ seal: Seal, at t: Double) -> Bool {
        ArisGestureMotion.sealStrength(ageMs: t - seal.startedAt) == nil
            || (seal.withdrawnAt.map { ArisGestureMotion.sealWithdrawal(sinceMs: t - $0) == 0 } ?? false)
    }

    #if DEBUG
    // MARK: - Offscreen renders

    /// Poses the reject at the clock's time without Core Animation, for `cacheDisplay` renders (headless only).
    func prepareSnapshot() {
        prune(at: now())
        let t = now()
        guard let r = reject else { return }
        let age = t - r.startedAt
        if ArisGestureMotion.rejectRemoved(atMs: age) {
            removeReject()
            return
        }
        let fade = ArisGestureMotion.rejectOpacity(atMs: age)
        r.loop.pose = ArisGestureMotion.Pose(opacity: fade, scale: 1, dy: 0)
        r.loop.dx = ArisGestureMotion.shakeOffset(atMs: age)
        var pop = ArisGestureMotion.capsulePop(atMs: age)
        pop.opacity *= fade
        r.capsule.pose = pop
    }
    #endif

    // MARK: - Helpers

    private var backingScale: CGFloat {
        min(window?.backingScaleFactor ?? screen?.backingScaleFactor ?? 2, ArisGestureConstants.Ink.maxBackingScale)
    }

    static func timing(_ c: ArisCubicBezier) -> CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: Float(c.x1), Float(c.y1), Float(c.x2), Float(c.y2))
    }

    /// +1 when a layer's +y translation moves it down on screen, −1 when up: the parity of `isGeometryFlipped` in the
    /// spaces above it (a flipped NSView's layer is geometry-flipped, so its sublayers run top-down). With no
    /// superlayer yet (no window), the AppKit default for a flipped host: down.
    static func downSign(_ layer: CALayer) -> CGFloat {
        var flips = 0, any = false
        var above = layer.superlayer
        while let l = above {
            any = true
            if l.isGeometryFlipped { flips += 1 }
            above = l.superlayer
        }
        guard any else { return 1 }
        return flips % 2 == 1 ? 1 : -1
    }

    /// Scale about the centre, then a vertical offset of `pose.dy` points down (the layer's anchor is its corner).
    static func transform(_ pose: ArisGestureMotion.Pose, size: CGSize, down: CGFloat = 1) -> CATransform3D {
        var t = CATransform3DMakeTranslation(size.width / 2, size.height / 2 + pose.dy * down, 0)
        t = CATransform3DScale(t, pose.scale, pose.scale, 1)
        return CATransform3DTranslate(t, -size.width / 2, -size.height / 2, 0)
    }

    /// A transparent image of `size` points at `scale`, drawn in top-left points.
    static func image(size: CGSize, scale: CGFloat, draw: (CGContext) -> Void) -> CGImage? {
        let w = Int((size.width * scale).rounded(.up)), h = Int((size.height * scale).rounded(.up))
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: ArisInkRenderer.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        draw(ctx)
        return ctx.makeImage()
    }
}

/// A view that draws one image, upright, filling its bounds. `pose` and `dx` are only used by offscreen renders;
/// live motion runs on its layer.
@MainActor
final class ArisGestureImageView: NSView {
    var image: CGImage? { didSet { needsDisplay = true } }
    var pose = ArisGestureMotion.Pose(opacity: 1, scale: 1, dy: 0) { didSet { needsDisplay = true } }
    var dx: CGFloat = 0 { didSet { needsDisplay = true } }

    init(frame: CGRect, image: CGImage?) {
        self.image = image
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let image, pose.opacity > 0 else { return }
        let w = bounds.width * pose.scale, h = bounds.height * pose.scale
        let rect = CGRect(x: bounds.midX - w / 2 + dx, y: bounds.midY - h / 2 + pose.dy, width: w, height: h)
        NSImage(cgImage: image, size: bounds.size).draw(in: rect, from: .zero, operation: .sourceOver,
                                                        fraction: pose.opacity, respectFlipped: true, hints: nil)
    }
}
