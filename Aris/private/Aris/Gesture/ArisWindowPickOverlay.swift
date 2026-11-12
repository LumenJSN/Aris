//
//  ArisWindowPickOverlay.swift
//  Aris
//
//  One display's surface while windows can be picked (ArisWindowPicker): a borderless, non-activating panel the size
//  of the display at the status-bar level (over every app window and the menu bar, under the notch, so the notch
//  stays clickable), never in a capture (`sharingType = .none`), never key. It takes every click while it's up, so a
//  click used for picking never reaches the app below; it exists only while picking is armed.
//  It draws the owner's ①B: a picked window gets a .13 yellow wash with a 2 pt ink E ring, swept in once from the left
//  (340 ms) and then still; a let-go wash fades (180 ms); the window under the pointer gets a faint 1.5 pt ring.
//  The red refusal (a private window, or the 9th shot) is the circle's: ArisInkView's loop and capsule.
//  Core Graphics in `draw(_:)`, redrawn by the display link only while something moves; headless for the renders.
//

import AppKit
import QuartzCore

@MainActor
final class ArisWindowPickOverlay {
    let display: UInt32
    /// Cocoa frame (global, bottom-left).
    let screenFrame: CGRect
    /// Quartz bounds (global, top-left): the washes' rects are relative to its origin.
    let quartzBounds: CGRect
    let view: ArisWindowPickView
    private var panel: NSPanel?

    init(display: UInt32, screenFrame: CGRect, quartzBounds: CGRect, screen: NSScreen?, headless: Bool,
         now: @escaping () -> Double) {
        self.display = display
        self.screenFrame = screenFrame
        self.quartzBounds = quartzBounds
        view = ArisWindowPickView(frame: CGRect(origin: .zero, size: screenFrame.size), screen: headless ? nil : screen, now: now)
        guard !headless else { return }
        let panel = NSPanel(contentRect: screenFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.sharingType = .none
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = false // every click is ours while picking
        panel.acceptsMouseMovedEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.setFrame(screenFrame, display: false)
        panel.contentView = view
        self.panel = panel
    }

    func show() {
        panel?.orderFrontRegardless()
        ArisOverlayCensus.shown(self) { [weak self] in self?.close() }
    }

    /// Takes the clicks (picking) or lets them through to the apps (anything else: QA BUG-44).
    func setInteractive(_ on: Bool) { panel?.ignoresMouseEvents = !on }

    var isInteractive: Bool { !(panel?.ignoresMouseEvents ?? true) }

    func close() {
        ArisOverlayCensus.closed(self)
        view.stop()
        panel?.ignoresMouseEvents = true
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }

    /// A window's Quartz frame in this panel's points, or nil when it isn't on this display.
    func local(_ window: CGRect) -> CGRect? { ArisWindowPickGeometry.local(window, display: quartzBounds) }
}

@MainActor
final class ArisWindowPickView: NSView {
    private struct Wash {
        let rect: CGRect
        let startedAt: Double
        var letGoAt: Double?
    }

    private struct Hover {
        let id: UInt32
        let rect: CGRect
        let since: Double
        let on: Bool
    }

    /// A click, in Cocoa global points.
    var onClick: ((CGPoint) -> Void)?
    /// The pointer moved, in Cocoa global points.
    var onMove: ((CGPoint) -> Void)?

    /// The red refusal (loop and capsule), as a circle gets it.
    let ink: ArisInkView
    private var washes: [UInt32: Wash] = [:]
    private var hovers: [Hover] = []
    private let now: () -> Double
    private weak var screen: NSScreen?
    private let live: Bool
    private var link: CADisplayLink?
    private var tracking: NSTrackingArea?
    /// The system's window corners (settable for the offscreen renders, whose windows are the mockup's).
    var radius = ArisWindowPickWash.cornerRadius(macOSMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)

    init(frame: CGRect, screen: NSScreen?, now: @escaping () -> Double) {
        self.screen = screen
        live = screen != nil
        self.now = now
        ink = ArisInkView(frame: CGRect(origin: .zero, size: frame.size), screen: screen, now: now)
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        ink.autoresizingMask = [.width, .height]
        addSubview(ink)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { self } // the refusal's subviews never take a click
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    // Every button is eaten: nothing reaches the app below while picking.
    override func mouseDown(with event: NSEvent) { onClick?(NSEvent.mouseLocation) }
    override func mouseUp(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func rightMouseUp(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    override func otherMouseUp(with event: NSEvent) {}
    override func mouseMoved(with event: NSEvent) { onMove?(NSEvent.mouseLocation) }

    // MARK: - Washes

    var washCount: Int { washes.values.filter { $0.letGoAt == nil }.count }

    /// A picked window: its wash sweeps in once.
    func addWash(id: UInt32, rect: CGRect) {
        washes[id] = Wash(rect: rect, startedAt: now())
        changed(rect)
    }

    /// A let-go window: its wash fades out.
    func removeWash(id: UInt32) {
        guard var wash = washes[id], wash.letGoAt == nil else { return }
        wash.letGoAt = now()
        washes[id] = wash
        changed(wash.rect)
    }

    func removeAllWashes() { washes.keys.forEach(removeWash) }

    /// The window under the pointer (nil: none or one that can't be picked) gets the faint ring.
    func setHover(id: UInt32?, rect: CGRect?) {
        let current = hovers.last(where: \.on)
        guard current?.id != id || current?.rect != rect else { return }
        let t = now()
        hovers = hovers.filter { !$0.on && t - $0.since < ArisWindowPickWash.hoverMs }
        if let current {
            hovers.append(Hover(id: current.id, rect: current.rect, since: t, on: false))
            changed(current.rect)
        }
        if let id, let rect {
            hovers.append(Hover(id: id, rect: rect, since: t, on: true))
            changed(rect)
        }
    }

    /// The red refusal over a window, its capsule by the click.
    func showRefusal(rect: CGRect, click: CGPoint, text: String, icon: ArisGestureChrome.Icon) {
        let points = Self.outline(rect.insetBy(dx: 4, dy: 4), radius: radius)
        ink.showReject(points: points, closed: true, bbox: rect, text: text, icon: icon,
                       anchor: CGRect(x: click.x - 1, y: click.y - 1, width: 2, height: 2))
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let t = now()
        typealias W = ArisWindowPickWash
        for hover in hovers {
            let k = W.hover(sinceMs: t - hover.since, on: hover.on)
            guard k > 0 else { continue }
            ring(ctx, hover.rect, width: W.hoverWidth, alpha: W.hoverAlpha * k)
        }
        for wash in washes.values.sorted(by: { $0.startedAt < $1.startedAt }) {
            let fade = wash.letGoAt.map { W.fade(sinceMs: t - $0) } ?? 1
            let reveal = W.reveal(ageMs: t - wash.startedAt)
            guard fade > 0, reveal > 0 else { continue }
            ctx.saveGState()
            ctx.clip(to: CGRect(x: wash.rect.minX, y: wash.rect.minY, width: wash.rect.width * reveal, height: wash.rect.height))
            let shape = CGPath(roundedRect: wash.rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            ctx.addPath(shape)
            ctx.setFillColor(W.color.copy(alpha: W.fillAlpha * fade) ?? W.color)
            ctx.fillPath()
            ring(ctx, wash.rect, width: W.ringWidth, alpha: W.ringAlpha * fade)
            ctx.restoreGState()
        }
    }

    /// An inset ring (CSS `box-shadow: inset 0 0 0 w`), inside the rounded rect.
    private func ring(_ ctx: CGContext, _ rect: CGRect, width: CGFloat, alpha: CGFloat) {
        let r = rect.insetBy(dx: width / 2, dy: width / 2)
        let corner = max(0, radius - width / 2)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: corner, cornerHeight: corner, transform: nil))
        ctx.setStrokeColor(ArisWindowPickWash.color.copy(alpha: alpha) ?? ArisWindowPickWash.color)
        ctx.setLineWidth(width)
        ctx.strokePath()
    }

    // MARK: - Motion

    private var moving: Bool {
        let t = now()
        return washes.values.contains { !ArisWindowPickWash.settled(ageMs: t - $0.startedAt) || $0.letGoAt != nil }
            || hovers.contains { t - $0.since < ArisWindowPickWash.hoverMs || !$0.on }
    }

    private func changed(_ rect: CGRect) {
        setNeedsDisplay(rect.insetBy(dx: -4, dy: -4))
        startLink()
    }

    @objc private func step(_ link: CADisplayLink) {
        let t = now()
        for wash in washes.values where !ArisWindowPickWash.settled(ageMs: t - wash.startedAt) || wash.letGoAt != nil {
            setNeedsDisplay(wash.rect.insetBy(dx: -4, dy: -4))
        }
        for hover in hovers { setNeedsDisplay(hover.rect.insetBy(dx: -4, dy: -4)) }
        prune(at: t)
        if !moving { stopLink() }
    }

    private func prune(at t: Double) {
        washes = washes.filter { _, wash in wash.letGoAt.map { t - $0 < ArisWindowPickWash.fadeMs } ?? true }
        hovers.removeAll { !$0.on && t - $0.since >= ArisWindowPickWash.hoverMs }
    }

    private func startLink() {
        guard live, link == nil, let screen else { return }
        let link = screen.displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
    }

    func stop() {
        stopLink()
        ink.stop()
        washes = [:]
        hovers = []
    }

    /// Points around a rounded rect, every ~6 pt, for the red loop.
    static func outline(_ r: CGRect, radius: CGFloat) -> [ArisGesturePoint] {
        let path = CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
        var points: [ArisGesturePoint] = []
        let step: CGFloat = 6
        var last: CGPoint?
        func add(_ p: CGPoint) {
            if let l = last {
                let d = hypot(p.x - l.x, p.y - l.y)
                let n = max(1, Int(d / step))
                for i in 1...n {
                    let u = CGFloat(i) / CGFloat(n)
                    points.append(ArisGesturePoint(x: l.x + (p.x - l.x) * u, y: l.y + (p.y - l.y) * u, t: 0))
                }
            } else {
                points.append(ArisGesturePoint(x: p.x, y: p.y, t: 0))
            }
            last = p
        }
        path.applyWithBlock { element in
            let e = element.pointee
            switch e.type {
            case .moveToPoint, .addLineToPoint: add(e.points[0])
            case .addQuadCurveToPoint:
                guard let l = last else { return add(e.points[1]) }
                for i in 1...6 {
                    let u = CGFloat(i) / 6, a = (1 - u) * (1 - u), b = 2 * (1 - u) * u, c = u * u
                    add(CGPoint(x: a * l.x + b * e.points[0].x + c * e.points[1].x, y: a * l.y + b * e.points[0].y + c * e.points[1].y))
                }
            case .addCurveToPoint:
                guard let l = last else { return add(e.points[2]) }
                for i in 1...6 {
                    let u = CGFloat(i) / 6, v = 1 - u
                    let x = v * v * v * l.x + 3 * v * v * u * e.points[0].x + 3 * v * u * u * e.points[1].x + u * u * u * e.points[2].x
                    let y = v * v * v * l.y + 3 * v * v * u * e.points[0].y + 3 * v * u * u * e.points[1].y + u * u * u * e.points[2].y
                    add(CGPoint(x: x, y: y))
                }
            case .closeSubpath: if let first = points.first { add(CGPoint(x: first.x, y: first.y)) }
            @unknown default: break
            }
        }
        return points
    }

    #if DEBUG
    /// Poses everything at the clock's time for a `cacheDisplay` render (headless only).
    func prepareSnapshot() {
        prune(at: now())
        ink.prepareSnapshot()
        needsDisplay = true
    }
    #endif
}
