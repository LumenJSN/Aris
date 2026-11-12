//
//  ArisSpriteView.swift
//  Aris
//
//  A character on screen as a layer: its atlas as the layer's contents, stepped by a discrete contentsRect animation
//  that runs on the render server. The app does nothing per frame: SwiftUI only hears of a
//  character when its state changes, a loop's shuffled playlist of variants is handed to Core Animation whole, and the
//  pointer, while it moves near, picks a baked head pose at most 30 times a second. A loop pauses while its window
//  can't be seen.
//

import AppKit
import SwiftUI

/// The character's layer, sized as the kit's canvas (1.5 times the box) and placed where BotAvatar puts it.
struct ArisSpriteView: NSViewRepresentable {
    /// The look its atlases are baked for (a standard size; the layer scales it to its own).
    let look: ArisSpriteLook
    let play: ArisSpritePlay
    /// A count; each rise plays upstream's poke (from the idle loop only).
    var pokes = 0
    /// A count; each rise plays a landing squash about the feet (the star's hop into or out of the pill, A6).
    var lands = 0
    /// Greyed and tilted, still (the star dozing while the agent is down, audit ① B).
    var muted = false
    /// The poke may play (not under 모션 줄이기).
    var bursts = true
    /// Faces the pointer while it is within reach and the idle loop plays.
    var follows = false

    @ObservedObject private var store = ArisSpriteStore.shared

    func makeNSView(context: Context) -> ArisSpriteLayerView { ArisSpriteLayerView() }

    func updateNSView(_ view: ArisSpriteLayerView, context: Context) {
        // What shows first bakes first: the still poses, then what plays, then the follow grid.
        let still = store.sheet(look, .still, urgent: true)
        let main = play.clip == .still ? still : store.sheet(look, play.clip)
        let following = follows && play.follows
        let follow = following ? store.sheet(look, .follow) : nil
        var held: Set<ArisSpriteKey> = [ArisSpriteStore.key(look, .still), ArisSpriteStore.key(look, play.clip)]
        if following { held.insert(ArisSpriteStore.key(look, .follow)) }
        store.hold(held, for: ObjectIdentifier(view))
        view.update(.init(look: look, play: play, pokes: pokes, lands: lands, muted: muted, bursts: bursts, follows: following, still: still, main: main, follow: follow))
    }

    static func dismantleNSView(_ view: ArisSpriteLayerView, coordinator: ()) {
        view.teardown()
        ArisSpriteStore.shared.release(ObjectIdentifier(view))
    }
}

/// Everything the layer is told, compared to what it shows.
struct ArisSpriteInput {
    var look: ArisSpriteLook
    var play: ArisSpritePlay
    var pokes: Int
    var lands: Int
    var muted: Bool
    var bursts: Bool
    var follows: Bool
    var still: ArisSpriteSheet?
    var main: ArisSpriteSheet?
    var follow: ArisSpriteSheet?
}

final class ArisSpriteLayerView: NSView {
    private var input: ArisSpriteInput?
    /// What the layer is showing now.
    private enum Showing: Equatable { case none, still(Int), loop(ArisSpriteClip, ObjectIdentifier), follow(Int), easing(Int) }
    private var showing = Showing.none
    /// The poke count last seen, played or not, so turning 모션 줄이기 off never plays a poke that came meanwhile.
    private var pokesSeen: Int?
    /// The landing count last seen, the same way.
    private var landsSeen: Int?
    private var mutedShown = false
    private var followTarget: Int?
    private var followStep: DispatchWorkItem?
    private var pointerID: UUID?
    private var occlusion: NSObjectProtocol?
    private var visible = true
    /// Aris's own "zzz" over a sleeping character (ArisSleepZ): its layers, and what they were built for.
    private let zLayer = CALayer()
    private var zBuilt: (mode: ArisSleepZ.Mode, size: CGSize, dark: Bool)?
    /// Moving from one window to another (a travel's handover), or passing through none on the way.
    private var rebinding = false
    private var detaching = false
    /// How long a newly shown window may take to report itself visible.
    private static let occlusionSettle = 0.5
    /// Each view shuffles its own playlists, so two characters of a look never move in step.
    private var shuffle = UInt64.random(in: 0...UInt64.max)

    /// The playback's animation keys; the one-time fade-in has its own and survives them.
    private static let playKeys = ["loop", "shot", "fade"]
    /// Covers a cut into a variant's anchor (a poke, the pointer handing back).
    private static let cutFade = 0.1
    /// A change of state; dozing off or waking is slower, as upstream's switch to and from sleep is.
    private static let stateFade = 0.25
    private static let sleepFade = 0.6

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contentsGravity = .resize
        layer?.minificationFilter = .trilinear
        layer?.magnificationFilter = .linear
        layer?.opacity = 0
        zLayer.masksToBounds = true
        layer?.addSublayer(zLayer)
    }

    override func layout() {
        super.layout()
        if zLayer.frame != bounds {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            zLayer.frame = bounds
            CATransaction.commit()
            updateSleepZ()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if window != nil, newWindow != nil { rebinding = true }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusion { NotificationCenter.default.removeObserver(occlusion) }
        occlusion = nil
        guard let window else {
            // Gone, or only passing through no window on its way to another (a travel's handover between displays'
            // panels): a turn later tells which. Torn down only if still nowhere.
            guard !detaching else { return }
            detaching = true
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.detaching = false
                if self.window == nil { self.teardown() }
            }
            return
        }
        layer?.contentsScale = window.backingScaleFactor
        occlusion = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.occlusionChanged() }
        }
        // From one window straight to another: the same pictures keep playing on the same clock (no refresh, no re-cut).
        if rebinding || detaching {
            rebinding = false
            return
        }
        // A window just ordered in may not report itself visible yet: count it seen, and ask again shortly.
        visible = window.occlusionState.contains(.visible) || window.isVisible
        updatePointer()
        refresh(force: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.occlusionSettle) { [weak self] in
            MainActor.assumeIsolated { self?.occlusionChanged() }
        }
    }

    // MARK: travel

    /// The look's facing grid, for a travel to turn the character with (nil until baked; asking starts the bake).
    func facingSheet() -> ArisSpriteSheet? {
        guard let input else { return nil }
        return ArisSpriteStore.shared.sheet(input.look, .facing)
    }

    /// The animations a copy of this character replays to look the same on the same clock: the loop and the poke.
    var playAnimations: [(key: String, animation: CAAnimation)] {
        ["shot", "loop"].compactMap { key in layer?.animation(forKey: key).map { (key, $0) } }
    }

    func teardown() {
        followStep?.cancel()
        if let pointerID { ArisPointerHub.shared.unsubscribe(pointerID) }
        pointerID = nil
        stopPlayback()
        if let occlusion { NotificationCenter.default.removeObserver(occlusion) }
        occlusion = nil
    }

    private func occlusionChanged() {
        let now = window?.occlusionState.contains(.visible) ?? false
        guard now != visible else { return }
        visible = now
        updatePointer()
        // Hidden, nothing runs; seen again, the loop picks up at a variant's start.
        if visible { refresh(force: true) } else { stopPlayback() }
        zBuilt = nil
        updateSleepZ()
    }

    // MARK: input

    func update(_ new: ArisSpriteInput) {
        input = new
        defer { updateSleepZ() }
        let rose = pokesSeen.map { new.pokes > $0 } ?? false
        pokesSeen = new.pokes
        let landed = landsSeen.map { new.lands > $0 } ?? false
        landsSeen = new.lands
        if landed, new.bursts, visible, window != nil { playLanding() }
        if new.muted != mutedShown { setMuted(new.muted, animated: new.bursts) }
        updatePointer()
        // A job done: upstream's poke, from the idle loop's anchor, cut in with a short fade.
        if rose, new.bursts, new.play.takesPokes, let sheet = new.main, sheet.poke != nil, visible, window != nil {
            followStep?.cancel()
            followTarget = nil
            playLoop(sheet, clip: .idle, pokeFirst: true, fade: fadeInto(.loop(.idle, ObjectIdentifier(sheet.image))))
            return
        }
        refresh(force: false)
    }

    /// What the input asks to show: its loop once its atlas is in and the window is seen, else the state's rest pose.
    private func wanted(_ input: ArisSpriteInput) -> Showing {
        switch input.play {
        case let .still(i): return .still(i)
        case let .loop(clip):
            if let sheet = input.main, visible, !sheet.loopSegments.isEmpty { return .loop(clip, ObjectIdentifier(sheet.image)) }
            return .still(clip == .sleeping ? 1 : clip == .working ? 2 : 0)
        }
    }

    /// Shows what the input asks for, unless the pointer has the layer (and the state hasn't changed under it).
    private func refresh(force: Bool) {
        guard let input, window != nil else { return }
        switch showing {
        case .follow, .easing:
            if !force, input.play.follows { return }
        default: break
        }
        let want = wanted(input)
        // The same pose, unless its atlas was redrawn (a provisional still replaced once the pile landed).
        let redrawn: Bool
        if case .still = want, let still = input.still { redrawn = (layer?.contents as AnyObject?) !== still.image } else { redrawn = false }
        if want == showing && !force && !redrawn { return }
        show(want, fade: fadeInto(want))
    }

    /// The fade a change from what shows to `next` takes: none on the first picture, slow into or out of sleep.
    private func fadeInto(_ next: Showing) -> Double? {
        guard showing != .none, let input else { return nil }
        let wasAsleep: Bool
        switch showing {
        case .still(1), .loop(.sleeping, _): wasAsleep = true
        default: wasAsleep = false
        }
        if wasAsleep != input.play.asleep { return Self.sleepFade }
        switch (showing, next) {
        case let (.loop(a, _), .loop(b, _)) where a == b: return Self.cutFade
        case (.follow, _), (.easing, _): return Self.cutFade
        default: return Self.stateFade
        }
    }

    // MARK: playing

    /// The mockup's landSq: pressed to 1.12 × 0.84, back through 0.97 × 1.04, settled, in 260 ms on a strong ease-out,
    /// about the feet. On the render server, like the loop; the model transform is never touched.
    private func playLanding() {
        guard let layer else { return }
        let feet = ArisTravelBox(self).feet
        let dx = feet.x - layer.bounds.width * layer.anchorPoint.x, dy = feet.y - layer.bounds.height * layer.anchorPoint.y
        func about(_ sx: CGFloat, _ sy: CGFloat) -> NSValue {
            NSValue(caTransform3D: CATransform3DTranslate(CATransform3DScale(CATransform3DMakeTranslation(dx, dy, 0), sx, sy, 1), -dx, -dy, 0))
        }
        let squash = CAKeyframeAnimation(keyPath: "transform")
        squash.values = [about(1.12, 0.84), about(0.97, 1.04), about(1, 1)]
        squash.keyTimes = [0, 0.6, 1]
        let ease = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
        squash.timingFunctions = [ease, ease]
        squash.duration = ArisStarHop.land
        layer.add(squash, forKey: Self.landKey)
    }

    private static let landKey = "aris.land"
    private static let dozeKey = "aris.doze"

    /// The mockup's sleepy star: grayscale at .75 brightness and .55 alpha (one colour matrix), tilted 14° to the left
    /// and down a point, eased in over 400 ms. A held animation on the render server, so AppKit's own geometry for the
    /// layer is never touched and nothing runs per frame.
    private func setMuted(_ on: Bool, animated: Bool) {
        guard let layer else { return }
        mutedShown = on
        layerUsesCoreImageFilters = true
        if on, let grey = CIFilter(name: "CIColorMatrix") {
            let (r, g, b) = (0.2126 * 0.75, 0.7152 * 0.75, 0.0722 * 0.75)
            for key in ["inputRVector", "inputGVector", "inputBVector"] { grey.setValue(CIVector(x: r, y: g, z: b, w: 0), forKey: key) }
            grey.setValue(CIVector(x: 0, y: 0, z: 0, w: 0.55), forKey: "inputAVector")
            layer.filters = [grey]
        } else {
            layer.filters = nil
        }
        let centre = CGPoint(x: layer.bounds.midX - layer.bounds.width * layer.anchorPoint.x,
                             y: layer.bounds.midY - layer.bounds.height * layer.anchorPoint.y)
        let angle = (isFlipped ? -14.0 : 14.0) * Double.pi / 180, down: CGFloat = isFlipped ? 1 : -1
        var tilt = CATransform3DMakeTranslation(centre.x, centre.y + down, 0)
        tilt = CATransform3DRotate(tilt, angle, 0, 0, 1)
        tilt = CATransform3DTranslate(tilt, -centre.x, -centre.y, 0)
        let from = (layer.presentation()?.value(forKeyPath: "transform") as? NSValue) ?? NSValue(caTransform3D: CATransform3DIdentity)
        let turn = CABasicAnimation(keyPath: "transform")
        turn.fromValue = from
        turn.toValue = NSValue(caTransform3D: on ? tilt : CATransform3DIdentity)
        turn.duration = animated ? 0.4 : 0
        turn.timingFunction = CAMediaTimingFunction(name: .easeOut)
        turn.fillMode = .forwards
        turn.isRemovedOnCompletion = false
        layer.add(turn, forKey: Self.dozeKey)
    }

    private func show(_ next: Showing, fade: Double?) {
        guard let input else { return }
        followStep?.cancel()
        switch next {
        case let .still(i):
            guard let still = input.still else { showing = .none; return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            stopPlayback()
            if let fade { crossFade(fade) }
            setContents(still, i)
            CATransaction.commit()
            showing = next
            fadeInOnce()
        case let .loop(clip, _):
            guard let sheet = input.main else { return }
            playLoop(sheet, clip: clip, pokeFirst: false, fade: fade)
        case .follow, .easing, .none:
            break
        }
    }

    private func stopPlayback() {
        for key in Self.playKeys { layer?.removeAnimation(forKey: key) }
    }

    private func crossFade(_ duration: Double) {
        let t = CATransition()
        t.type = .fade
        t.duration = duration
        t.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer?.add(t, forKey: "fade")
    }

    private func setContents(_ sheet: ArisSpriteSheet, _ index: Int) {
        guard let layer else { return }
        layer.contents = sheet.image
        layer.contentsRect = sheet.grid.unitRect(index)
    }

    private func animation(_ sheet: ArisSpriteSheet, _ frames: [Int], key: String) -> CAKeyframeAnimation {
        let a = CAKeyframeAnimation(keyPath: "contentsRect")
        a.values = frames.map { NSValue(rect: sheet.grid.unitRect($0)) }
        a.calculationMode = .discrete
        a.duration = Double(frames.count) / max(1, sheet.fps)
        a.isRemovedOnCompletion = false
        a.fillMode = .forwards
        return a
    }

    /// A loop: its variants in a shuffled playlist of two minutes or more, repeating, from a variant's start (every one
    /// starts on the anchor, so the playlist and its repeat are seamless); a poke's variant first if asked.
    private func playLoop(_ sheet: ArisSpriteSheet, clip: ArisSpriteClip, pokeFirst: Bool, fade: Double?) {
        guard let layer else { return }
        let segments = sheet.loopSegments
        guard !segments.isEmpty else { return }
        shuffle &+= 0x9E37_79B9_7F4A_7C15
        let order = ArisSpritePlaylist.order(count: segments.count, plays: ArisSpritePlaylist.plays(segments: segments, fps: sheet.fps, seconds: 120), seed: shuffle)
        let frames = ArisSpritePlaylist.frames(segments: segments, order: order)
        let shot = pokeFirst ? sheet.poke.map { Array(sheet.segments[$0]) } : nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stopPlayback()
        if let fade { crossFade(fade) }
        setContents(sheet, shot?.first ?? frames.first ?? 0)
        let now = layer.convertTime(CACurrentMediaTime(), from: nil)
        var delay = 0.0
        if let shot {
            let a = animation(sheet, shot, key: "shot")
            a.beginTime = now
            layer.add(a, forKey: "shot")
            delay = a.duration
        }
        let loop = animation(sheet, frames, key: "loop")
        loop.repeatCount = .infinity
        // Added after the poke, so it takes over the moment it begins.
        loop.beginTime = now + delay
        layer.add(loop, forKey: "loop")
        CATransaction.commit()
        showing = .loop(clip, ObjectIdentifier(sheet.image))
        fadeInOnce()
    }

    private var faded = false
    private func fadeInOnce() {
        guard !faded, let layer, layer.contents != nil else { return }
        faded = true
        layer.opacity = 1
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = 0
        a.toValue = 1
        a.duration = 0.3
        layer.add(a, forKey: "show")
    }

    // MARK: the pointer

    /// Listens to the pointer only while it may follow it: asked to, seen, the idle loop playing, its grid baked.
    private func updatePointer() {
        let wants = (input?.follows ?? false) && visible && window != nil && input?.follow != nil
        if wants, pointerID == nil {
            pointerID = ArisPointerHub.shared.subscribe { [weak self] location in self?.pointer(at: location) }
        } else if !wants, let id = pointerID {
            ArisPointerHub.shared.unsubscribe(id)
            pointerID = nil
            switch showing {
            case .follow, .easing:
                followStep?.cancel()
                followTarget = nil
                showing = .none
                refresh(force: true)
            default: break
            }
        }
    }

    /// The pointer moved (at most 30 times a second): the head pose at the kit's pull toward it, or — once it's out of
    /// reach — back to rest, then the loop.
    private func pointer(at screen: CGPoint) {
        guard let input, let window, visible, let sheet = input.follow else { return }
        // The box's centre: the canvas is 1.5 times the box and sits a tenth of the box higher.
        let canvas = window.convertToScreen(convert(bounds, to: nil))
        let box = canvas.width / 1.5
        guard box > 0 else { return }
        let centre = CGPoint(x: canvas.midX, y: canvas.midY - 0.1 * box)
        let offset = CGVector(dx: (screen.x - centre.x) / box, dy: -(screen.y - centre.y) / box)
        guard let target = ArisSpriteFollow.cell(offset: offset) else {
            if case .follow(let at) = showing { showing = .easing(at); followTarget = ArisSpriteFollow.centre; stepToward(sheet) }
            return
        }
        followTarget = target
        switch showing {
        case .follow: break
        case .easing(let at): showing = .follow(at)
        default:
            // From the loop: the rest pose first, faded, then the steps toward the pointer.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            stopPlayback()
            crossFade(Self.cutFade)
            setContents(sheet, ArisSpriteFollow.centre)
            CATransaction.commit()
            showing = .follow(ArisSpriteFollow.centre)
        }
        stepToward(sheet)
    }

    /// One pose nearer the target, and again in a 30th of a second until it's there; easing back, the loop then takes
    /// over from a variant's start.
    private func stepToward(_ sheet: ArisSpriteSheet) {
        let at: Int, easing: Bool
        switch showing {
        case .follow(let i): at = i; easing = false
        case .easing(let i): at = i; easing = true
        default: return
        }
        guard let target = followTarget, layer != nil else { return }
        let next = ArisSpriteFollow.step(from: at, to: target)
        showing = easing ? .easing(next) : .follow(next)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        setContents(sheet, next)
        CATransaction.commit()
        followStep?.cancel()
        if next == target {
            if easing {
                followTarget = nil
                showing = .follow(next)
                if let input { show(wanted(input), fade: Self.cutFade) }
            }
            return
        }
        let work = DispatchWorkItem { [weak self] in self?.stepToward(sheet) }
        followStep = work
        DispatchQueue.main.asyncAfter(deadline: .now() + ArisSpriteFollow.interval, execute: work)
    }
}

extension ArisSpriteLayerView {
    /// The z's for what plays: drifting while asleep (each its own render-server animation, staggered), one still z
    /// asleep under 모션 줄이기, none awake or unseen. Rebuilt only when that, the size or the theme changes.
    fileprivate func updateSleepZ() {
        guard let input else { return }
        let mode = visible && window != nil ? ArisSleepZ.mode(input.play) : .none
        let size = bounds.size
        if let b = zBuilt, b.mode == mode, b.size == size, b.dark == input.look.dark { return }
        zBuilt = (mode, size, input.look.dark)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        zLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        guard mode != .none, size.width > 0 else { return }
        let box = size.width / 1.5
        let fontSize = ArisSleepZ.fontSize(box: box)
        let base = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: fontSize) } ?? base
        // Layer space is y up: the spec's points are y down.
        func point(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * size.width, y: (1 - p.y) * size.height) }
        let from = point(ArisSleepZ.from), to = point(ArisSleepZ.to)
        let now = zLayer.convertTime(CACurrentMediaTime(), from: nil)
        for i in 0..<(mode == .drifting ? ArisSleepZ.count : 1) {
            let z = CATextLayer()
            z.string = "z"
            z.font = font
            z.fontSize = fontSize
            z.alignmentMode = .center
            z.foregroundColor = (input.look.dark ? NSColor.white : NSColor.black).cgColor
            z.contentsScale = window?.backingScaleFactor ?? 2
            z.bounds = CGRect(x: 0, y: 0, width: fontSize * 1.2, height: fontSize * 1.3)
            zLayer.addSublayer(z)
            if mode == .resting {
                z.position = CGPoint(x: from.x + (to.x - from.x) * 0.4, y: from.y + (to.y - from.y) * 0.4)
                z.opacity = Float(ArisSleepZ.opacity)
                continue
            }
            z.position = to
            z.opacity = 0
            // A gentle arc: out to the side first, then up.
            let path = CGMutablePath()
            path.move(to: from)
            path.addQuadCurve(to: to, control: CGPoint(x: to.x, y: from.y + (to.y - from.y) * 0.35))
            let move = CAKeyframeAnimation(keyPath: "position")
            move.path = path
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = ArisSleepZ.scaleFrom
            grow.toValue = ArisSleepZ.scaleTo
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = ArisSleepZ.opacityKeys
            fade.keyTimes = ArisSleepZ.opacityTimes.map { NSNumber(value: $0) }
            let group = CAAnimationGroup()
            group.animations = [move, grow, fade]
            group.duration = ArisSleepZ.life
            // An even drift, so the z's in the air stay apart.
            group.timingFunction = CAMediaTimingFunction(name: .linear)
            group.repeatCount = .infinity
            group.beginTime = now + Double(i) * ArisSleepZ.interval
            group.fillMode = .backwards
            group.isRemovedOnCompletion = false
            z.add(group, forKey: "drift")
        }
    }
}

/// The pointer's moves, shared by every following character: one pair of event monitors while anyone listens,
/// at most 30 updates a second, nothing while the pointer is still.
@MainActor
final class ArisPointerHub {
    static let shared = ArisPointerHub()
    private var listeners: [UUID: (CGPoint) -> Void] = [:]
    private var monitors: [Any] = []
    private var last: TimeInterval?
    private var trailing: DispatchWorkItem?

    func subscribe(_ listener: @escaping (CGPoint) -> Void) -> UUID {
        let id = UUID()
        listeners[id] = listener
        if monitors.isEmpty { install() }
        return id
    }

    func unsubscribe(_ id: UUID) {
        listeners[id] = nil
        if listeners.isEmpty { remove() }
    }

    private func install() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.moved() }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.moved() }
            return event
        }) { monitors.append(local) }
    }

    private func remove() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        trailing?.cancel()
    }

    private func moved() {
        let now = ProcessInfo.processInfo.systemUptime
        guard ArisSpriteFollow.due(last: last, now: now) else {
            // The last move between ticks still lands, a 30th of a second later.
            if trailing == nil {
                let work = DispatchWorkItem { [weak self] in self?.trailing = nil; self?.moved() }
                trailing = work
                DispatchQueue.main.asyncAfter(deadline: .now() + ArisSpriteFollow.interval, execute: work)
            }
            return
        }
        last = now
        deliver(NSEvent.mouseLocation)
    }

    /// Hands a pointer location (screen space) to every listener.
    func deliver(_ location: CGPoint) {
        for listener in listeners.values { listener(location) }
    }
}
