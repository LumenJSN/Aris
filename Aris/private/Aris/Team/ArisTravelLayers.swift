//
//  ArisTravelLayers.swift
//  Aris
//
//  The layers a travel plays on (ArisTravelAnimator): where the character's box sits in the view it's given, the
//  render-server animations (the motion about the feet, the facing turn, G1's sparkle pop), and the copies other
//  displays' panels show while the character crosses. A copy is no bitmap: it shows the sprite's own atlas and replays its own loop on the
//  same clock, so both sides of a display edge are the same frame of the same character.
//

import AppKit
import BotAvatarsKit

/// Where the character's box (the size it is shown at) sits in the view a travel is given.
@MainActor
struct ArisTravelBox {
    /// The box, in the view's coordinates.
    let rect: CGRect
    /// The sprite layer view inside (or the view itself), when there is one: its atlas, loop and facing grid.
    let sprite: ArisSpriteLayerView?
    let flipped: Bool

    init(_ view: NSView) {
        sprite = Self.sprite(in: view)
        flipped = view.isFlipped
        if view is ArisSpriteLayerView {
            // The sprite layer view is the kit's canvas: 1.5 times the box, the box a tenth of itself below the middle.
            let b = view.bounds.width / CGFloat(BOT_AVATAR_OVERSCAN), rise = CGFloat(BOT_AVATAR_RISE) * b
            rect = CGRect(x: view.bounds.midX - b / 2, y: view.bounds.midY - rise - b / 2, width: b, height: b)
        } else {
            rect = view.bounds
        }
    }

    var centre: CGPoint { CGPoint(x: rect.midX, y: rect.midY) }
    /// The bottom middle of the box, which squash and lean turn about.
    var feet: CGPoint { CGPoint(x: rect.midX, y: flipped ? rect.maxY : rect.minY) }

    private static func sprite(in view: NSView) -> ArisSpriteLayerView? {
        if let sprite = view as? ArisSpriteLayerView { return sprite }
        for sub in view.subviews { if let found = sprite(in: sub) { return found } }
        return nil
    }
}

/// The animations of one trip, built the same for the view and each copy: everything on one clock, `begin`.
@MainActor
struct ArisTravelLayers {
    static let motionKey = "aris.travel"
    static let facingKey = "aris.travel.facing"
    static let hideKey = "aris.travel.hide"
    static let sparkleKey = "aris.travel.sparkle"
    /// The cut-fade between the live sprite and the facing grid, at each end of the turn.
    static let facingCut = 0.1
    static let frameRates = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)

    let track: ArisMotionTrack
    let begin: CFTimeInterval
    let end: CGPoint
    /// The feet, from the layer's position, in its superlayer's space.
    let pivot: CGVector
    let facing: ArisSpriteSheet?
    private let keyframes: [ArisTravelKeyframe]

    init(track: ArisMotionTrack, begin: CFTimeInterval, end: CGPoint, pivot: CGVector, facing: ArisSpriteSheet?) {
        self.track = track
        self.begin = begin
        self.end = end
        self.pivot = pivot
        self.facing = facing
        keyframes = track.keyframes(rate: ArisTravelTimeline.keyRate)
    }

    /// How long the layers play: the track, and the facing grid's fade back into the live sprite.
    var length: Double { track.duration + (facing == nil ? 0 : Self.facingCut) }

    /// The motion for `layer`: the centre's offset from the end, the shape about the feet.
    func motion(for layer: CALayer) -> CAAnimationGroup {
        let times = keyframes.map { NSNumber(value: $0.time / length) } + [1]
        let last = keyframes.last?.pose ?? ArisTravelPose(position: end)
        let poses = keyframes.map(\.pose) + [last]
        let offset = CAKeyframeAnimation(keyPath: "position")
        offset.isAdditive = true
        offset.values = poses.map { NSValue(point: CGPoint(x: $0.position.x - end.x, y: $0.position.y - end.y)) }
        offset.keyTimes = times
        let shape = CAKeyframeAnimation(keyPath: "transform")
        shape.values = poses.map { NSValue(caTransform3D: transform($0)) }
        shape.keyTimes = times
        let group = CAAnimationGroup()
        group.animations = [offset, shape]
        return timed(group, on: layer, duration: length)
    }

    /// The facing turn over a sprite layer: an overlay showing the facing grid's cells as the track turns, faded in
    /// over the live sprite at the start and back out once it faces front; under it the sprite's own picture hidden
    /// while the overlay is whole. Nothing without a facing grid.
    func addFacing(to sprite: CALayer) {
        guard let facing, track.duration > 2 * Self.facingCut else { return }
        let overlay = CALayer()
        overlay.name = Self.facingKey
        overlay.frame = sprite.bounds
        overlay.contents = facing.image
        overlay.contentsGravity = .resize
        overlay.contentsScale = sprite.contentsScale
        overlay.minificationFilter = .trilinear
        overlay.contentsRect = facing.grid.unitRect(ArisSpriteFacing.front)
        overlay.opacity = 0
        sprite.addSublayer(overlay)
        // The cells, keyed only where they change.
        var cells: [(time: Double, cell: Int)] = []
        for i in 0...Int((track.duration * ArisTravelTimeline.keyRate).rounded(.up)) {
            let t = min(track.duration, Double(i) / ArisTravelTimeline.keyRate)
            let cell = ArisSpriteFacing.cell(yaw: track.pose(at: t).yaw)
            if cells.last?.cell != cell { cells.append((t, cell)) }
        }
        let turn = CAKeyframeAnimation(keyPath: "contentsRect")
        turn.calculationMode = .discrete
        turn.values = cells.map { NSValue(rect: facing.grid.unitRect($0.cell)) }
        turn.keyTimes = cells.map { NSNumber(value: $0.time / length) } + [1]
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]
        fade.keyTimes = [0, Self.facingCut / length, track.duration / length, 1].map { NSNumber(value: $0) }
        let group = CAAnimationGroup()
        group.animations = [turn, fade]
        overlay.add(timed(group, on: overlay, duration: length), forKey: Self.facingKey)
        // The sprite's own picture, hidden while the overlay is whole.
        let hide = CABasicAnimation(keyPath: "contents")
        hide.fromValue = Self.clear
        hide.toValue = Self.clear
        hide.beginTime = sprite.convertTime(begin, from: nil) + Self.facingCut
        hide.duration = track.duration - Self.facingCut
        hide.isRemovedOnCompletion = false
        sprite.add(hide, forKey: Self.hideKey)
    }

    static func removeFacing(from sprite: CALayer) {
        sprite.removeAnimation(forKey: hideKey)
        sprite.sublayers?.filter { $0.name == facingKey }.forEach { $0.removeFromSuperlayer() }
    }

    /// A copy of `view` for another panel, its model at the end there (`position`), showing the sprite's own atlas and
    /// replaying its loop on the same clock, with the trip's motion and facing (`moving`; else it stands still).
    func copy(of view: NSView, box: ArisTravelBox, at position: CGPoint, into parent: CALayer, moving: Bool = true) -> CALayer? {
        guard let source = view.layer else { return nil }
        let container = CALayer()
        container.bounds = source.bounds
        container.anchorPoint = source.anchorPoint
        container.position = position
        container.isGeometryFlipped = source.isGeometryFlipped
        parent.addSublayer(container)
        if let spriteView = box.sprite, let sprite = spriteView.layer {
            let twin = sprite === source ? container : CALayer()
            if twin !== container {
                twin.frame = source.convert(sprite.bounds, from: sprite)
                container.addSublayer(twin)
            }
            twin.contents = sprite.contents
            twin.contentsRect = sprite.contentsRect
            twin.contentsGravity = sprite.contentsGravity
            twin.contentsScale = sprite.contentsScale
            twin.minificationFilter = sprite.minificationFilter
            twin.magnificationFilter = sprite.magnificationFilter
            twin.opacity = sprite.opacity
            for (key, animation) in spriteView.playAnimations {
                guard let replay = animation.copy() as? CAAnimation else { continue }
                replay.beginTime = ArisTravelCopy.beginTime(sourceBegin: animation.beginTime, sourceToMedia: { sprite.convertTime($0, to: nil) },
                                                            mediaToCopy: { twin.convertTime($0, from: nil) })
                twin.add(replay, forKey: key)
            }
            if moving { addFacing(to: twin) }
        } else {
            container.contents = source.contents
        }
        if moving { container.add(motion(for: container), forKey: Self.motionKey) }
        return container
    }

    /// G1's sparkle pop in `parent` (a panel's content layer), the feet at `feet` there and `up` its upward y (1, or −1
    /// when flipped): five sparkles, each one render-server group starting at touchdown on the trip's clock, shown once
    /// and gone within 0.45 s. Nil when the track has none.
    func sparkle(into parent: CALayer, feet: CGPoint, up: CGFloat, size: CGFloat, contentsScale: CGFloat) -> CALayer? {
        guard let touchdown = track.sparkleTime else { return nil }
        let holder = CALayer()
        holder.name = Self.sparkleKey
        holder.bounds = .zero
        holder.position = feet
        holder.zPosition = 1
        parent.addSublayer(holder)
        let side = ArisLandingSparkle.side * size / ArisLandingSparkle.referenceSize
        let path = ArisLandingSparkle.path(side: side), colour = CGColor(srgbRed: ArisLandingSparkle.rgb.0, green: ArisLandingSparkle.rgb.1,
                                                                         blue: ArisLandingSparkle.rgb.2, alpha: 1)
        let start = holder.convertTime(begin + touchdown, from: nil)
        for i in 0..<ArisLandingSparkle.count {
            let frames = ArisLandingSparkle.keyframes(i, size: size, rate: ArisTravelTimeline.keyRate)
            let spark = CAShapeLayer()
            spark.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            spark.path = path
            spark.fillColor = colour
            spark.contentsScale = contentsScale
            spark.opacity = 0
            holder.addSublayer(spark)
            let times = frames.map { NSNumber(value: $0.time / ArisLandingSparkle.life) }
            let move = CAKeyframeAnimation(keyPath: "position")
            move.values = frames.map { NSValue(point: CGPoint(x: $0.offset.dx, y: up * $0.offset.dy)) }
            let turn = CAKeyframeAnimation(keyPath: "transform")
            // Clockwise on screen: negative about z where y is up.
            turn.values = frames.map { NSValue(caTransform3D: CATransform3DRotate(CATransform3DMakeScale($0.scale, $0.scale, 1), -up * $0.spin, 0, 0, 1)) }
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = frames.map { Float($0.opacity) }
            for a in [move, turn, fade] { a.keyTimes = times }
            let group = CAAnimationGroup()
            group.animations = [move, turn, fade]
            group.duration = ArisLandingSparkle.life
            group.beginTime = start
            // Only after it starts: before touchdown the model (opacity 0) shows; after, the last frame (also 0).
            group.fillMode = .forwards
            group.isRemovedOnCompletion = false
            group.preferredFrameRateRange = Self.frameRates
            spark.add(group, forKey: Self.sparkleKey)
        }
        return holder
    }

    private func timed<A: CAAnimation>(_ animation: A, on layer: CALayer, duration: Double) -> A {
        animation.duration = duration
        animation.beginTime = layer.convertTime(begin, from: nil)
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        animation.preferredFrameRateRange = Self.frameRates
        return animation
    }

    /// Scale and lean about the feet.
    private func transform(_ pose: ArisTravelPose) -> CATransform3D {
        var t = CATransform3DMakeTranslation(pivot.dx, pivot.dy, 0)
        t = CATransform3DRotate(t, pose.rotation, 0, 0, 1)
        t = CATransform3DScale(t, pose.scaleX, pose.scaleY, 1)
        return CATransform3DTranslate(t, -pivot.dx, -pivot.dy, 0)
    }

    /// A transparent picture, to hide a layer's own contents under the facing overlay.
    private static let clear: CGImage? = {
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        return context?.makeImage()
    }()

    /// The camera housings of the displays with a notch, in screen coordinates (a glide keeps clear of them).
    static func cameraHousings() -> [CGRect] {
        NSScreen.screens.compactMap { screen in
            let top = screen.safeAreaInsets.top
            guard top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return nil }
            let f = screen.frame
            return CGRect(x: f.minX + left.width, y: f.maxY - top, width: max(0, f.width - left.width - right.width), height: top)
        }
    }
}
