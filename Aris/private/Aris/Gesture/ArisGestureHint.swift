//
//  ArisGestureHint.swift
//  Aris
//
//  The hint chip "동그라미로 가리키세요" with Aris's star (the owner's pick B), shown at commit near the cursor and
//  following it until the first stroke. Its own 280×48 panel at status + 14: click-through,
//  never in a capture, on every Space. The chip enters over 220 ms; it hides with no animation on the first stroke,
//  so it can never be in a frame, and fades for good after 220 pt of travel. Headless for the offscreen renders.
//

import AppKit
import QuartzCore

@MainActor
final class ArisGestureHint {
    /// Aris's star in the chip's icon slot: a live view in the app (the real fabric star), or an image in renders.
    enum Icon {
        case view(@MainActor () -> NSView)
        case image(CGImage?)
    }

    let view: ArisGestureHintView
    /// The panel's capture setting and level (nil headless), for the tests.
    var sharingType: NSWindow.SharingType? { panel?.sharingType }
    var level: NSWindow.Level? { panel?.level }
    private var panel: NSPanel?
    private let now: () -> Double
    private var shownAt: Double?
    private var fadingSince: Double?

    /// `shownInCaptures`: an ad demo's hint (ArisAdDemo), which screen recordings must see; the real one never shows.
    init(icon: Icon, headless: Bool, now: @escaping () -> Double, shownInCaptures: Bool = false) {
        self.now = now
        let size = ArisGestureConstants.Ink.hintSize
        view = ArisGestureHintView(frame: CGRect(origin: .zero, size: size), icon: icon)
        guard !headless else { return }
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + ArisGestureConstants.Session.hintLevelOffset)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.sharingType = ArisCaptureSharing.type(demo: shownInCaptures)
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = true
        panel.contentView = view
        self.panel = panel
    }

    /// The window's frame in Cocoa global points, and the chip's spot inside it (top-left).
    private(set) var frame: CGRect = .zero

    func show(frame: CGRect, chipOrigin: CGPoint) {
        place(frame: frame, chipOrigin: chipOrigin)
        shownAt = now()
        fadingSince = nil
        view.isHidden = false
        guard let panel else { return }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        // emil-design-eng: entering → ease-out, under 300 ms: 0.22 s ease-out, a 3 pt rise.
        let duration = ArisGestureMotion.hintEntranceMs / 1000
        let curve = ArisInkView.timing(ArisGestureMotion.hintCurve)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = duration
        fade.timingFunction = curve
        let rise = CABasicAnimation(keyPath: "transform.translation.y")
        let down = view.chip.layer.map(ArisInkView.downSign) ?? 1
        rise.fromValue = ArisGestureMotion.hintRise * down
        rise.toValue = 0
        rise.duration = duration
        rise.timingFunction = curve
        view.chip.layer?.add(fade, forKey: "hintIn")
        view.chip.layer?.add(rise, forKey: "hintRise")
    }

    /// Moves the window; a frame that hasn't changed costs nothing (the pump calls this every tick).
    func place(frame: CGRect, chipOrigin: CGPoint) {
        if view.chipOrigin != chipOrigin { view.chipOrigin = chipOrigin }
        guard frame != self.frame else { return }
        self.frame = frame
        panel?.setFrame(frame, display: false)
        placements += 1
    }

    /// How many times the window actually moved.
    private(set) var placements = 0

    /// Back on the hint's display after leaving it: shown again at once (it already made its entrance).
    func reveal() {
        view.isHidden = false
        guard let panel else { return }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    /// The first stroke: gone this frame, with every animation killed (it must never be in a capture).
    func hideInstantly() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.chip.layer?.removeAllAnimations()
        view.isHidden = true
        CATransaction.commit()
        panel?.orderOut(nil)
        fadingSince = nil
    }

    /// 220 pt of travel: fades for good. emil-design-eng: exits faster than entrances (150 ms ease-out).
    func fadeOut() {
        fadingSince = now()
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = ArisGestureMotion.hintFadeOutMs / 1000
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.fadingSince != nil else { return }
                self.panel?.orderOut(nil)
            }
        }
    }

    func close() {
        panel?.close()
        panel = nil
        view.isHidden = true
    }

    #if DEBUG
    /// Poses the chip at the clock's time without Core Animation, for `cacheDisplay` renders (headless only).
    func prepareSnapshot() {
        guard let shownAt, !view.isHidden else { return }
        var pose = ArisGestureMotion.hintEntrance(atMs: now() - shownAt)
        if let fadingSince {
            let u = min(1, (now() - fadingSince) / ArisGestureMotion.hintFadeOutMs)
            pose.opacity *= CGFloat(1 - u)
        }
        view.chip.pose = pose
    }
    #endif
}

/// The 280×48 hint window's content: the chip image at its cursor-side corner, with the star view laid over the
/// icon slot when the icon is a live view.
@MainActor
final class ArisGestureHintView: NSView {
    let chip: ArisGestureImageView
    private var iconView: NSView?

    var chipOrigin: CGPoint = .zero {
        didSet { chip.setFrameOrigin(chipOrigin) }
    }

    init(frame: CGRect, icon: ArisGestureHint.Icon) {
        let size = ArisGestureChrome.hintChipSize()
        let image: CGImage?
        switch icon {
        case .image(let star): image = ArisGestureChrome.hintChipImage(icon: star, scale: 2)
        case .view: image = ArisGestureChrome.hintChipImage(icon: nil, scale: 2)
        }
        chip = ArisGestureImageView(frame: CGRect(origin: .zero, size: size), image: image)
        super.init(frame: frame)
        wantsLayer = true
        addSubview(chip)
        if case .view(let make) = icon {
            let star = make()
            star.frame = ArisGestureChrome.hintIconFrame()
            chip.addSubview(star)
            iconView = star
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
