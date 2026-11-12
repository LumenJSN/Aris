//
//  ArisSpriteBaker.swift
//  Aris
//
//  Bakes a character's clips (ArisSpriteClip) into atlases: the kit's own Sim (upstream's motion) run offline, each
//  frame exactly 1/fps of its time, each pose drawn with drawBotAvatarFrame into its cell. A loop is a few variants cut
//  from one recording where it comes back to its anchor pose, their ends blended into the anchor's own run
//  (ArisSpriteLoop), so a layer can play them in any order. The drawing needs SwiftUI's GraphicsContext, which only
//  ImageRenderer makes, on the main actor; so frames are drawn a few milliseconds at a time with a display frame
//  between, the Sim costs next to nothing, and the atlas is cached on disk (ArisSpriteStore), so each look bakes once.
//

import BotAvatarsKit
import CoreGraphics
import SwiftUI

/// A baked clip: the atlas and how to play it.
struct ArisSpriteSheet {
    let image: CGImage
    let grid: ArisSpriteGrid
    let fps: Double
    /// A loop's variants, as frame ranges in the atlas (empty for poses).
    let segments: [Range<Int>]
    /// Which variant starts with a poke (the idle loop's), if any.
    let poke: Int?
    /// Drawn before the pile was made (a stand-in look): shown, never cached, baked again.
    var provisional = false

    var frames: Int { grid.count }
    var bytes: Int { image.bytesPerRow * image.height }
    /// The variants the loop shuffles (the poke's plays only for a poke).
    var loopSegments: [Range<Int>] { segments.enumerated().filter { $0.offset != poke }.map(\.element) }
}

@MainActor
enum ArisSpriteBaker {
    /// The loops settle this long in their state before the anchor is looked for.
    private static let warmUp = 3.0
    /// Where the anchor may be: the calmest frame in this window after the warm-up.
    private static let anchorWindow = 3.0
    /// How long the pile may take to bake before a clip is given up (the still poses wait less, then draw a stand-in).
    private static let pileWait: Duration = .seconds(20)
    private static let stillPileWait: Duration = .milliseconds(1500)
    /// Drawing runs at most this long, then waits a display frame.
    private static let slice = 0.003
    private static let pause: Duration = .milliseconds(17)

    // MARK: poses

    /// The kit's config for a look, as upstream draws it: the type's own colour, brightness and saturation, still (each
    /// frame drawn exactly, with no cross-fades carried from the last).
    static func config(_ look: ArisSpriteLook) -> BotAvatarDrawConfig {
        let avatar = BotAvatar(type: BotAvatarType(rawValue: look.type) ?? .star, size: Double(look.size),
                               color: look.colorHex.flatMap { BotColor($0) }, paused: true,
                               shading: BotAvatarShading(rawValue: look.shading) ?? .fabric, interactive: false)
        return avatar.drawConfig(scale: Double(look.scale), theme: look.dark ? .dark : .light)
    }

    static func vector(_ p: BotAvatarPose) -> [Double] {
        [p.yaw, p.pitch, p.roll, p.x, p.y, p.sx, p.sy, p.eyeOpen, p.blinkL, p.blinkR, p.lookX, p.lookY, p.breath, p.laugh,
         p.whirl, p.whirlAngle, p.w[0], p.w[1], p.w[2]]
    }

    static func pose(_ v: [Double]) -> BotAvatarPose {
        var p = BotAvatarPose()
        typealias V = ArisPoseVector
        p.yaw = v[V.yaw]; p.pitch = v[V.pitch]; p.roll = v[V.roll]; p.x = v[V.x]; p.y = v[V.y]; p.sx = v[V.sx]; p.sy = v[V.sy]
        p.eyeOpen = v[V.eyeOpen]; p.blinkL = v[V.blinkL]; p.blinkR = v[V.blinkR]; p.lookX = v[V.lookX]; p.lookY = v[V.lookY]
        p.breath = v[V.breath]; p.laugh = v[V.laugh]; p.whirl = v[V.whirl]; p.whirlAngle = v[V.whirlAngle]
        let sum = max(1e-9, v[V.w0] + v[V.w1] + v[V.w2])
        p.w = SIMD3(v[V.w0] / sum, v[V.w1] / sum, v[V.w2] / sum)
        return p
    }

    /// `frames` of a Sim at `fps`, from a fresh one in `state` (the look's seed, upstream's jump defaults); `at` runs
    /// on it just before frame `index` is recorded's update.
    private static func record(_ look: ArisSpriteLook, _ state: BotAvatarState, fps: Double, frames: Int, at index: Int? = nil, _ act: (BotAvatarSim) -> Void = { _ in }) -> [[Double]] {
        let sim = BotAvatarSim(seed: look.seed, state: state)
        sim.setJump(.defaults)
        let sub = ArisSpriteClock.substeps(fps: fps), step = ArisSpriteClock.step(fps: fps)
        for _ in 0..<Int((warmUp * fps).rounded()) * sub { sim.update(step) }
        var out: [[Double]] = []
        out.reserveCapacity(frames)
        for i in 0..<frames {
            if i == index { act(sim) }
            for _ in 0..<sub { sim.update(step) }
            out.append(vector(sim.pose))
        }
        return out
    }

    /// The calmest frame in the window: no blink, laugh or whirl, the head and body barely moving.
    private static func anchor(_ f: [[Double]], from: Int, to: Int) -> Int {
        typealias V = ArisPoseVector
        func busy(_ i: Int) -> Double {
            let a = f[i], b = f[i + 1]
            return a[V.blinkL] + a[V.laugh] + a[V.whirl] + 10 * abs(V.delta(b[V.yaw], a[V.yaw], V.yaw)) + abs(b[V.y] - a[V.y]) + abs(b[V.lookX] - a[V.lookX])
        }
        return (from..<min(to, f.count - 1)).min { busy($0) < busy($1) } ?? from
    }

    /// A loop's frames and variants: one recording cut at the anchor's returns, plus (idle) a variant that opens with a
    /// poke at the anchor, every variant's ends blended into the anchor's run.
    static func loop(_ look: ArisSpriteLook, _ clip: ArisSpriteClip, _ spec: ArisSpriteSpec) -> (frames: [[Double]], segments: [Range<Int>], poke: Int?) {
        let state: BotAvatarState = clip == .working ? .working : clip == .sleeping ? .sleeping : .default
        let fps = spec.fps
        let width = max(1, Int((ArisSpriteSpec.blendSeconds * fps).rounded()))
        let lengths = Int((spec.seconds.lowerBound * fps).rounded())...Int((spec.seconds.upperBound * fps).rounded())
        let window = Int((anchorWindow * fps).rounded())
        let total = width + window + spec.variants * lengths.upperBound + width + 2
        let all = record(look, state, fps: fps, frames: total)
        let a = anchor(all, from: width, to: width + window)
        let seams = ArisSpriteLoop.seams(all, anchor: a)
        let valid: (Int) -> Bool = { i in spec.period.map { ArisSpriteLoop.inPhase(i, anchor: a, fps: fps, period: $0) } ?? true }
        var cuts = ArisSpriteLoop.cuts(seams: seams, anchor: a, count: spec.variants, lengths: lengths, valid: valid)
        if cuts.count < 2 { cuts = [a, min(all.count - 1, a + lengths.upperBound)] }
        let pre = Array(all[(a - width)..<a]), post = Array(all[a..<min(all.count, a + width)])
        var frames: [[Double]] = [], segments: [Range<Int>] = []
        for (c0, c1) in zip(cuts, cuts.dropFirst()) {
            let start = frames.count
            frames += ArisSpriteLoop.blend(Array(all[c0..<c1]), pre: pre, post: post, width: width)
            segments.append(start..<frames.count)
        }
        var poke: Int?
        if let pokeSeconds = spec.pokeSeconds {
            // The same Sim, poked at the anchor (the frames before it are the same), cut where it comes back to the anchor.
            let pl = Int((pokeSeconds.lowerBound * fps).rounded())...Int((pokeSeconds.upperBound * fps).rounded())
            let poked = record(look, state, fps: fps, frames: a + pl.upperBound + 2, at: a) { $0.poke() }
            let back = poked.indices.map { i in
                i + 1 < poked.count ? ArisPoseVector.distance(poked[i], all[a]) + ArisPoseVector.distance(poked[i + 1], all[a + 1]) : .infinity
            }
            let end = ArisSpriteLoop.cuts(seams: back, anchor: a, count: 1, lengths: pl).dropFirst().first ?? min(poked.count - 1, a + pl.upperBound)
            let start = frames.count
            frames += ArisSpriteLoop.blend(Array(poked[a..<end]), pre: pre, post: post, width: width)
            segments.append(start..<frames.count)
            poke = segments.count - 1
        }
        return (frames, segments, poke)
    }

    /// Facing the pointer at the kit's pull `v` (its direction times its strength), as its Sim settles there with no
    /// wander: the head turns 22° and tips 12° per unit of pull, the eyes lead by 4.5 and 3.
    static func followPose(_ v: CGVector) -> BotAvatarPose {
        var p = BotAvatarPose.rest(.default)
        p.yaw = 22 * .pi / 180 * Double(v.dx)
        p.pitch -= 12 * .pi / 180 * Double(v.dy)
        p.lookX += 4.5 * Double(v.dx)
        p.lookY += 3 * Double(v.dy)
        return p
    }

    /// The rest pose turned `yaw` degrees to face the way it travels (set straight on the pose, as `followPose` does,
    /// never through the Sim's turn).
    static func facingPose(yaw: CGFloat) -> BotAvatarPose {
        var p = BotAvatarPose.rest(.default)
        p.yaw = Double(yaw) * .pi / 180
        return p
    }

    /// Every pose a clip draws, and its variants.
    private static func poses(_ key: ArisSpriteKey) -> (poses: [BotAvatarPose], segments: [Range<Int>], poke: Int?) {
        switch key.clip {
        case .still:
            return ([.rest(.default), .rest(.sleeping), .rest(.working)], [], nil)
        case .follow:
            return ((0..<ArisSpriteFollow.count).map { followPose(ArisSpriteFollow.direction($0)) }, [], nil)
        case .facing:
            return ((0..<ArisSpriteFacing.count).map { facingPose(yaw: ArisSpriteFacing.yaw($0)) }, [], nil)
        case .idle, .working, .sleeping:
            guard let spec = key.spec else { return ([.rest(.default)], [], nil) }
            let l = loop(key.look, key.clip, spec)
            return (l.frames.map(pose), l.segments, l.poke)
        }
    }

    // MARK: drawing

    /// Bakes `key`'s clip: waits for the kit's pile, then draws every pose into the atlas, a slice at a time. The still
    /// poses never wait long: past a moment they draw with the kit's stand-in and come back provisional.
    static func bake(_ key: ArisSpriteKey) async -> ArisSpriteSheet? {
        let look = key.look
        let cfg = config(look)
        let box = Double(look.size), scale = Double(look.scale)
        // A first frame queues the pile's bake on the kit's bake queue.
        let probe = ArisSpriteGrid(count: 1, cellPx: look.cellPx)
        if let scratch = context(probe) { draw(.rest(.default), cfg: cfg, box: box, scale: scale, into: scratch, at: probe.pixelRect(0), state: BotAvatarRenderState()) }
        let clock = ContinuousClock(), deadline = clock.now + (key.clip == .still ? stillPileWait : pileWait)
        var provisional = false
        while !botAvatarFabricIsBaked(cfg, box: box) {
            guard clock.now < deadline else {
                if key.clip == .still { provisional = true; break }
                return nil
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        let (frames, segments, poke) = poses(key)
        let grid = ArisSpriteGrid(count: frames.count, cellPx: look.cellPx)
        guard let atlas = context(grid) else { return nil }
        let state = BotAvatarRenderState()
        var since = CFAbsoluteTimeGetCurrent()
        for (i, pose) in frames.enumerated() {
            draw(pose, cfg: cfg, box: box, scale: scale, into: atlas, at: grid.pixelRect(i), state: state)
            if CFAbsoluteTimeGetCurrent() - since > slice {
                // Back to the run loop for a display frame: the notch never waits on a bake.
                try? await Task.sleep(for: pause)
                since = CFAbsoluteTimeGetCurrent()
            }
        }
        guard let image = atlas.makeImage() else { return nil }
        return ArisSpriteSheet(image: image, grid: grid, fps: key.fps, segments: segments, poke: poke, provisional: provisional)
    }

    static func context(_ grid: ArisSpriteGrid) -> CGContext? {
        CGContext(data: nil, width: grid.widthPx, height: grid.heightPx, bitsPerComponent: 8, bytesPerRow: grid.widthPx * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    /// One pose into one cell, as BotAvatar's canvas draws it (BotAvatarsKit's StillRenderer, into a cell of an atlas).
    static func draw(_ pose: BotAvatarPose, cfg: BotAvatarDrawConfig, box: Double, scale: Double, into atlas: CGContext, at cell: CGRect, state: BotAvatarRenderState) {
        let full = box * BOT_AVATAR_OVERSCAN
        let view = Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { context, _ in
            drawBotAvatarFrame(&context, box: box, pose: pose, cfg: cfg, state: state)
        }
        .frame(width: full, height: full)
        ImageRenderer(content: view).render(rasterizationScale: scale) { _, render in
            atlas.saveGState()
            atlas.clip(to: cell)
            atlas.translateBy(x: cell.minX, y: cell.minY)
            atlas.scaleBy(x: scale, y: scale)
            render(atlas)
            atlas.restoreGState()
        }
    }
}
