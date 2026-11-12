//
//  ArisTravelAnimator.swift
//  Aris
//
//  Plays a teammate's travel (ArisTravelTimeline: a style's legs from `style.legs(from:to:screens:)`, the user's G1 glide by
//  default) or its 낑낑 strain (ArisStrainClip) in the overlay panels (ArisOverlayPanels). Smoothness is the bar, so
//  the motion runs on the render server: the whole trip goes to Core Animation once (ArisTravelLayers), and a busy main
//  thread can't drop a frame of it. Nothing NSWindow ever moves.
//
//  The view's model frame is set to the end at the start and the motion is an additive offset from there, so when the
//  animation ends the view is already where it lands. A travel needs nothing per frame: the moments its centre crosses
//  onto another display are worked out ahead, and the view is handed to that panel then, on a timer; every other
//  display it touches shows a copy playing the same animations, so the part over an edge is drawn on both sides in the
//  same frame. G1's sparkle pop is one more set of render-server layers at the perch, in each of those displays' panels,
//  on the same clock. It ends when its animation does. A display link runs only for the strain (the window's offset, every
//  frame) or while Step 6's measurement log is on.
//
//  모션 줄이기 (or the system's Reduce Motion): no movement, no squash, no sparkle; the character fades out where it is
//  and in where it ends.
//

import AppKit
import Defaults

/// One display-link frame of a trip, for Step 6's measurement.
struct ArisTravelFrame {
    /// The frame's display time (CADisplayLink.targetTimestamp), and the frame duration of the display it is on (60 Hz
    /// externals and the 120 Hz built-in differ, so lateness is counted against this).
    let target: CFTimeInterval
    let frameDuration: CFTimeInterval
    /// When the tick ran, and where the render server had the centre then (AppKit, screen coordinates).
    let now: CFTimeInterval
    let centre: CGPoint
    /// Where the track says the centre is at `now`.
    let expected: CGPoint
}

@MainActor
final class ArisTravelAnimator {
    /// Step 6's measurement hook, called every frame of a trip. Nil in normal use (no per-frame work at all).
    var frameLog: ((ArisTravelFrame) -> Void)?

    var isRunning: Bool { trip != nil || fade != nil }

    private var trip: Trip?
    private var fade: Fade?
    private static let fadeKey = "aris.travel.fade"
    private static let fadeTime = 0.2

    /// Travels `view` (moved into the panels; its frame the character's box, or the sprite layer view itself) from
    /// `from` to the perch `to` in `style` (the user's glide unless asked), over today's displays and clear of their camera
    /// housings; `completion` once it has landed (or was stopped).
    func travel(from: CGPoint, to: CGPoint, style: ArisTravelStyle = .default, view: NSView, panels: ArisOverlayPanels,
                completion: @escaping () -> Void) {
        let size = ArisTravelBox(view).rect.width
        let legs = style.legs(from: from, to: to, screens: NSScreen.screens.map(\.frame), obstacles: ArisTravelLayers.cameraHousings(), size: size)
        travel(legs, style: style, view: view, panels: panels, completion: completion)
    }

    /// Travels `view` along `legs`, which must come from `style.legs(from:to:screens:)` of the same style.
    func travel(_ legs: [ArisTravelLeg], style: ArisTravelStyle, view: NSView, panels: ArisOverlayPanels, completion: @escaping () -> Void) {
        play(ArisTravelTimeline(legs, style: style), turns: style.glides, view: view, panels: panels, onTick: nil, completion: completion)
    }

    /// Plays the 낑낑 strain on `view`; `onWindowOffset` gets how far the window has gone every frame (Task 10 moves the
    /// real window with it).
    func strain(_ clip: ArisStrainClip, view: NSView, panels: ArisOverlayPanels, onWindowOffset: ((CGVector) -> Void)? = nil,
                completion: @escaping () -> Void) {
        play(clip, turns: false, view: view, panels: panels, onTick: onWindowOffset.map { report in { report(clip.windowOffset(at: $0)) } },
             completion: completion)
    }

    /// Stops what plays where the character is now, upright (between displays apart: where it comes back on one), and
    /// returns that centre; the completion runs too. Nil when nothing plays. A new trip stops the last the same way.
    @discardableResult
    func stop() -> CGPoint? {
        if let fade {
            self.fade = nil
            fade.cancel()
            return fade.end
        }
        guard let trip else { return nil }
        let here = trip.restingPoint(at: CACurrentMediaTime() - trip.layers.begin)
        finish(placingAt: here)
        return here
    }

    // MARK: playing

    private func play(_ track: ArisMotionTrack, turns: Bool, view: NSView, panels: ArisOverlayPanels, onTick: ((Double) -> Void)?,
                      completion: @escaping () -> Void) {
        stop()
        let screens = NSScreen.screens.map(\.frame)
        guard track.duration > 0, !screens.isEmpty else { completion(); return }
        let start = track.pose(at: 0).position, end = track.pose(at: track.duration).position
        let host = ArisTravelTimeline.hostScreen(track, at: 0, screens: screens) ?? Self.nearest(start, screens)
        guard let content = panels.panel(for: host)?.contentView else { completion(); return }
        if view.superview !== content { content.addSubview(view) }
        view.wantsLayer = true
        guard let layer = view.layer else { completion(); return }
        let box = ArisTravelBox(view)
        // Ask for the facing grid either way: it bakes once, for this trip or the next.
        let facing = box.sprite?.facingSheet()

        if Self.reducesMotion {
            fadeAcross(view: view, box: box, to: end, screens: screens, panels: panels, completion: completion)
            onTick?(track.duration)
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        place(view, box: box, at: end, on: host, screens: screens)
        let feet = view.convert(box.feet, to: content)
        let layers = ArisTravelLayers(track: track, begin: CACurrentMediaTime(), end: end,
                                      pivot: CGVector(dx: feet.x - layer.position.x, dy: feet.y - layer.position.y), facing: turns ? facing : nil)
        let trip = Trip(track: track, layers: layers, view: view, box: box, panels: panels, screens: screens, host: host, onTick: onTick,
                        completion: completion)
        let motion = layers.motion(for: layer)
        motion.delegate = ArisTravelEnd { [weak self, weak trip] finished in
            guard finished, let self, let trip, self.trip === trip else { return }
            self.finish(placingAt: nil)
        }
        layer.add(motion, forKey: ArisTravelLayers.motionKey)
        if let sprite = box.sprite?.layer { layers.addFacing(to: sprite) }
        for screen in ArisTravelTimeline.screensTouched(track, size: box.rect.width, screens: screens) where screen != host {
            trip.copies[screen] = copy(trip, on: screen)
        }
        trip.sparkles = ([host] + trip.copies.keys).compactMap { sparkle(trip, feet: feet, on: $0) }
        CATransaction.commit()
        self.trip = trip
        scheduleHandOvers(trip)
        if onTick != nil || frameLog != nil { startLink(trip) }
    }

    /// Hands the view over at each moment its centre crosses onto another display, worked out now.
    private func scheduleHandOvers(_ trip: Trip) {
        let n = Int((trip.track.duration * ArisTravelTimeline.keyRate).rounded(.up))
        var host = trip.host
        for i in 0...n {
            let t = trip.track.duration * Double(i) / Double(max(1, n))
            guard let next = ArisTravelTimeline.hostScreen(trip.track, at: t, screens: trip.screens), next != host else { continue }
            host = next
            let item = DispatchWorkItem { [weak self, weak trip] in
                guard let self, let trip, self.trip === trip else { return }
                self.handOver(trip, to: next)
            }
            trip.handOvers.append(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, t - (CACurrentMediaTime() - trip.layers.begin)), execute: item)
        }
    }

    /// The display link, for the strain's window offset and the measurement log only.
    private func startLink(_ trip: Trip) {
        trip.link?.stop()
        let screen = NSScreen.screens.indices.contains(trip.host) ? NSScreen.screens[trip.host] : nil
        trip.link = ArisTravelLink(screen: screen) { [weak self, weak trip] link in
            guard let self, let trip, self.trip === trip else { return false }
            let t = link.targetTimestamp - trip.layers.begin
            trip.onTick?(min(max(0, t), trip.track.duration))
            if let frameLog = self.frameLog {
                frameLog(trip.frame(target: link.targetTimestamp, frameDuration: link.targetTimestamp - link.timestamp))
            }
            return t < trip.track.duration
        }
    }

    /// The character's centre crossed onto another display: the view goes to that panel (its copy there goes away) and
    /// the panel it left gets a copy. The sprite keeps playing on its clock (ArisSpriteLayerView only rebinds).
    private func handOver(_ trip: Trip, to next: Int) {
        guard let content = trip.panels.panel(for: next)?.contentView else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trip.copies.removeValue(forKey: next)?.removeFromSuperlayer()
        let left = trip.host
        content.addSubview(trip.view)
        trip.view.wantsLayer = true
        place(trip.view, box: trip.box, at: trip.layers.end, on: next, screens: trip.screens)
        trip.host = next
        trip.copies[left] = copy(trip, on: left)
        if let layer = trip.view.layer, let old = layer.animation(forKey: ArisTravelLayers.motionKey) {
            let motion = trip.layers.motion(for: layer)
            motion.delegate = old.delegate
            layer.removeAnimation(forKey: ArisTravelLayers.motionKey)
            layer.add(motion, forKey: ArisTravelLayers.motionKey)
        }
        CATransaction.commit()
        if trip.link != nil { startLink(trip) }
    }

    /// Ends the trip: the animations and the copies go (and the panels left empty), the view stays at its model frame
    /// (the end) or at `here`.
    private func finish(placingAt here: CGPoint?) {
        guard let trip else { return }
        self.trip = nil
        trip.link?.stop()
        trip.handOvers.forEach { $0.cancel() }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let here {
            var screen = trip.host
            if let other = ArisTravelTimeline.screensTouched(at: here, size: 0.001, screens: trip.screens).min(), other != trip.host,
               let content = trip.panels.panel(for: other)?.contentView {
                content.addSubview(trip.view)
                screen = other
            }
            place(trip.view, box: trip.box, at: here, on: screen, screens: trip.screens)
            trip.host = screen
        }
        trip.view.layer?.removeAnimation(forKey: ArisTravelLayers.motionKey)
        if let sprite = trip.box.sprite?.layer { ArisTravelLayers.removeFacing(from: sprite) }
        trip.copies.values.forEach { $0.removeFromSuperlayer() }
        trip.sparkles.forEach { $0.removeFromSuperlayer() }
        CATransaction.commit()
        for screen in trip.copies.keys where screen != trip.host { trip.panels.orderOutIfEmpty(screen) }
        trip.completion()
    }

    // MARK: pieces

    /// The view's frame with its box centred on `point` (screen coordinates), in the panel of `screen`.
    private func place(_ view: NSView, box: ArisTravelBox, at point: CGPoint, on screen: Int, screens: [CGRect]) {
        let origin = screens.indices.contains(screen) ? screens[screen].origin : .zero
        let inBox = box.centre, frameOrigin = view.frame.origin
        // The box's centre in the superview, from the frame's origin (the view isn't flipped against its panel).
        let offset = CGPoint(x: view.convert(inBox, to: view.superview).x - frameOrigin.x, y: view.convert(inBox, to: view.superview).y - frameOrigin.y)
        view.setFrameOrigin(CGPoint(x: point.x - origin.x - offset.x, y: point.y - origin.y - offset.y))
    }

    /// A copy of the character in the panel of `screen`, its model at the end there.
    private func copy(_ trip: Trip, on screen: Int) -> CALayer? {
        guard let parent = trip.panels.panel(for: screen)?.contentView?.layer, let source = trip.view.layer else { return nil }
        let from = trip.screens[trip.host].origin, to = trip.screens[screen].origin
        return trip.layers.copy(of: trip.view, box: trip.box, at: CGPoint(x: source.position.x + from.x - to.x, y: source.position.y + from.y - to.y),
                                into: parent)
    }

    /// G1's sparkle pop at the perch in the panel of `screen`, `feet` being the feet at the end in the host's panel.
    private func sparkle(_ trip: Trip, feet: CGPoint, on screen: Int) -> CALayer? {
        guard let panel = trip.panels.panel(for: screen), let content = panel.contentView, let parent = content.layer else { return nil }
        let from = trip.screens[trip.host].origin, to = trip.screens[screen].origin
        return trip.layers.sparkle(into: parent, feet: CGPoint(x: feet.x + from.x - to.x, y: feet.y + from.y - to.y), up: content.isFlipped ? -1 : 1,
                                   size: trip.box.rect.width, contentsScale: panel.backingScaleFactor)
    }

    /// 모션 줄이기: out where it is, in where it ends, no movement.
    private func fadeAcross(view: NSView, box: ArisTravelBox, to end: CGPoint, screens: [CGRect], panels: ArisOverlayPanels,
                            completion: @escaping () -> Void) {
        guard let source = view.layer, let parent = view.superview?.layer else { completion(); return }
        let still = ArisTravelLayers(track: ArisStill(position: end), begin: CACurrentMediaTime(), end: end, pivot: .zero, facing: nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let ghost = still.copy(of: view, box: box, at: source.position, into: parent, moving: false)
        ghost?.opacity = 0
        ghost?.add(Self.opacity([1, 0], times: [0, 1], duration: Self.fadeTime), forKey: Self.fadeKey)
        let to = Self.nearest(end, screens)
        if let content = panels.panel(for: to)?.contentView, view.superview !== content { content.addSubview(view) }
        place(view, box: box, at: end, on: to, screens: screens)
        view.layer?.add(Self.opacity([0, 0, 1], times: [0, 0.5, 1], duration: 2 * Self.fadeTime), forKey: Self.fadeKey)
        CATransaction.commit()
        let fade = Fade(view: view, ghost: ghost, end: end, completion: completion)
        let done = DispatchWorkItem { [weak self, weak fade] in
            guard let self, let fade, self.fade === fade else { return }
            self.fade = nil
            fade.cancel()
        }
        fade.work = done
        self.fade = fade
        DispatchQueue.main.asyncAfter(deadline: .now() + 2 * Self.fadeTime, execute: done)
    }

    private static func opacity(_ values: [Float], times: [Double], duration: Double) -> CAKeyframeAnimation {
        let a = CAKeyframeAnimation(keyPath: "opacity")
        a.values = values
        a.keyTimes = times.map { NSNumber(value: $0) }
        a.duration = duration
        a.timingFunctions = Array(repeating: CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1), count: max(1, values.count - 1))
        return a
    }

    private static var reducesMotion: Bool {
        Defaults[.arisReduceMotion] || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private static func nearest(_ p: CGPoint, _ screens: [CGRect]) -> Int {
        ArisTravelRoute.screen(of: p, screens).flatMap { screens.firstIndex(of: $0) } ?? 0
    }
}

/// A trip under way.
@MainActor
private final class Trip {
    let track: ArisMotionTrack
    let layers: ArisTravelLayers
    let view: NSView
    let box: ArisTravelBox
    let panels: ArisOverlayPanels
    let screens: [CGRect]
    var host: Int
    let onTick: ((Double) -> Void)?
    let completion: () -> Void
    var copies: [Int: CALayer] = [:]
    /// G1's sparkle pop, one per panel the trip shows in (they stay put: it pops at the perch).
    var sparkles: [CALayer] = []
    var handOvers: [DispatchWorkItem] = []
    var link: ArisTravelLink?

    init(track: ArisMotionTrack, layers: ArisTravelLayers, view: NSView, box: ArisTravelBox, panels: ArisOverlayPanels, screens: [CGRect],
         host: Int, onTick: ((Double) -> Void)?, completion: @escaping () -> Void) {
        self.track = track
        self.layers = layers
        self.view = view
        self.box = box
        self.panels = panels
        self.screens = screens
        self.host = host
        self.onTick = onTick
        self.completion = completion
    }

    /// Where the character is at `time`; between displays apart, where it next comes back onto one (else the end).
    func restingPoint(at time: Double) -> CGPoint {
        let size = box.rect.width
        var t = max(0, time)
        while t < track.duration {
            let p = track.pose(at: t).position
            if !ArisTravelTimeline.screensTouched(at: p, size: size, screens: screens).isEmpty { return p }
            t += 1 / ArisTravelTimeline.keyRate
        }
        return layers.end
    }

    func frame(target: CFTimeInterval, frameDuration: CFTimeInterval) -> ArisTravelFrame {
        let now = CACurrentMediaTime()
        let model = view.layer?.position ?? .zero
        let shown = view.layer?.presentation()?.position ?? model
        let centre = CGPoint(x: layers.end.x + shown.x - model.x, y: layers.end.y + shown.y - model.y)
        return ArisTravelFrame(target: target, frameDuration: frameDuration, now: now, centre: centre, expected: track.pose(at: now - layers.begin).position)
    }
}

/// 모션 줄이기's fade under way.
@MainActor
private final class Fade {
    let view: NSView
    let ghost: CALayer?
    let end: CGPoint
    let completion: () -> Void
    var work: DispatchWorkItem?

    init(view: NSView, ghost: CALayer?, end: CGPoint, completion: @escaping () -> Void) {
        self.view = view
        self.ghost = ghost
        self.end = end
        self.completion = completion
    }

    /// Ends it now: the ghost goes, the view shows where it ends.
    func cancel() {
        work?.cancel()
        ghost?.removeFromSuperlayer()
        view.layer?.removeAnimation(forKey: "aris.travel.fade")
        completion()
    }
}

/// A point that stays put (for a still copy).
private struct ArisStill: ArisMotionTrack {
    let position: CGPoint
    var duration: Double { 0 }
    func pose(at time: Double) -> ArisTravelPose { ArisTravelPose(position: position) }
}

/// Calls back when a trip's motion ends (Core Animation calls its delegate on the main thread).
@MainActor
private final class ArisTravelEnd: NSObject, CAAnimationDelegate {
    private let done: (Bool) -> Void

    init(_ done: @escaping (Bool) -> Void) { self.done = done }

    nonisolated func animationDidStop(_ animation: CAAnimation, finished: Bool) {
        MainActor.assumeIsolated { self.done(finished) }
    }
}

/// The display link of one screen, only while a strain or the measurement log needs it; it stops when `onTick` says so.
@MainActor
private final class ArisTravelLink: NSObject {
    private var link: CADisplayLink?
    private let onTick: (CADisplayLink) -> Bool

    init(screen: NSScreen?, onTick: @escaping (CADisplayLink) -> Bool) {
        self.onTick = onTick
        super.init()
        guard let screen = screen ?? NSScreen.main else { return }
        let link = screen.displayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = ArisTravelLayers.frameRates
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        if !onTick(link) { stop() }
    }
}
