//
//  ArisSprite.swift
//  Aris
//
//  The characters' sprite engine, its pure part (no BotAvatarsKit, no AppKit, so the tests build it). A character is
//  never drawn per frame: the kit's own Sim — upstream's motion, unchanged — is run offline into atlases of frames per
//  look (ArisSpriteBaker), and a layer steps through them with a contentsRect animation on the render server
//  (ArisSpriteView). Upstream's motion is random, so a clip is several long variants cut from one recording where it
//  comes back to the same pose (the anchor), their ends blended into it, and played in a shuffled order: any variant
//  may follow any other without a seam. This file holds what that rests on: the clips and their budgets, the cuts, the
//  blend, the playlist, how frames sit in an atlas, the cache's key and eviction, and the pointer-follow grid.
//

import CoreGraphics
import Foundation

/// What an atlas holds.
enum ArisSpriteClip: String, Hashable, CaseIterable {
    /// Three rest poses: 0 idle, 1 asleep, 2 working (upstream's `restPose`, for 모션 줄이기 and while the others bake).
    case still
    /// Upstream's idle (the gaze to the corners, blinks, darts, a flip now and then), plus one variant that starts with
    /// a poke.
    case idle
    /// Upstream's working state: the hops, every third one spinning, the laughs.
    case working
    /// Upstream's sleep: breathing and nods.
    case sleeping
    /// Head poses toward the pointer, `ArisSpriteFollow.columns` × `rows`.
    case follow
    /// Turned to face the way it travels, `ArisSpriteFacing.count` still cells from left to right.
    case facing

    var id: String { rawValue }
    var loops: Bool { self == .idle || self == .working || self == .sleeping }
}

/// How a loop is recorded for a cell size: frames a second, how many variants and how long each, the poke's variant,
/// and the period its cuts keep (working: six hops, the spin's and the lean's common beat).
struct ArisSpriteSpec: Equatable {
    let fps: Double
    let variants: Int
    let seconds: ClosedRange<Double>
    let pokeSeconds: ClosedRange<Double>?
    let period: Double?

    /// A loop's atlas, decoded, aims to stay under this; past it, fewer variants, then fewer frames a second.
    static let budgetBytes = 8 * 1024 * 1024
    /// The working hop's period (the kit's HOP_T) and the six hops after which it repeats: every third spins, the lean
    /// alternates.
    static let hop = 0.68
    static let workingPeriod = 6 * hop
    /// The seam's blend: this long at each end of a variant.
    static let blendSeconds = 0.25

    /// Frames at most (all variants at their longest, the poke's too).
    var maxFrames: Int {
        Int((fps * (Double(variants) * seconds.upperBound + (pokeSeconds?.upperBound ?? 0))).rounded(.up))
    }

    /// The spec for `clip` at `cellPx`: the richest that fits the budget (the highest rate, then the most variants,
    /// never under two at the full rate before the rate drops), else the leanest.
    static func plan(_ clip: ArisSpriteClip, cellPx: Int) -> ArisSpriteSpec? {
        let base: (fps: [Double], variants: Int, seconds: ClosedRange<Double>, poke: ClosedRange<Double>?, period: Double?)
        switch clip {
        case .idle: base = ([24, 12], 3, 6...9, 2...5, nil)
        case .working: base = ([30, 20], 3, 4...9, nil, workingPeriod)
        case .sleeping: base = ([15, 10], 2, 8...14, nil, nil)
        case .still, .follow, .facing: return nil
        }
        let frameBytes = cellPx * cellPx * 4
        var tries: [(Double, Int)] = []
        for v in stride(from: base.variants, through: 2, by: -1) { tries.append((base.fps[0], v)) }
        tries += [(base.fps[1], 2), (base.fps[0], 1), (base.fps[1], 1)]
        var last: ArisSpriteSpec?
        for (fps, v) in tries {
            let s = ArisSpriteSpec(fps: fps, variants: v, seconds: base.seconds, pokeSeconds: base.poke, period: base.period)
            if s.maxFrames * frameBytes <= budgetBytes { return s }
            last = s
        }
        return last
    }
}

/// Stepping a Sim for a recording: each frame advances exactly 1/fps, in equal sub-steps no longer than the kit's
/// 60 Hz frame.
enum ArisSpriteClock {
    static func substeps(fps: Double) -> Int { max(1, Int((60 / fps).rounded(.up))) }
    static func step(fps: Double) -> Double { 1 / fps / Double(substeps(fps: fps)) }
}

/// A pose as numbers (BotAvatarPose's fields, in this order), so the cut, the seam and the blend are pure.
enum ArisPoseVector {
    static let yaw = 0, pitch = 1, roll = 2, x = 3, y = 4, sx = 5, sy = 6, eyeOpen = 7, blinkL = 8, blinkR = 9
    static let lookX = 10, lookY = 11, breath = 12, laugh = 13, whirl = 14, whirlAngle = 15, w0 = 16, w1 = 17, w2 = 18
    static let count = 19
    /// Angles: compared and blended the short way round (a spin adds whole turns).
    static let angles: Set<Int> = [yaw, whirlAngle]

    /// `a` − `b` for field `i`, the short way round for an angle.
    static func delta(_ a: Double, _ b: Double, _ i: Int) -> Double {
        let d = a - b
        guard angles.contains(i) else { return d }
        let tau = 2 * Double.pi
        let r = (d + .pi).truncatingRemainder(dividingBy: tau)
        return (r < 0 ? r + tau : r) - .pi
    }

    /// How far apart two poses look: the turn (whole turns don't count), the tilt, the eyes, the hop and squash, the
    /// breath, the whirl and the states' weights.
    static func distance(_ a: [Double], _ b: [Double]) -> Double {
        func d(_ i: Int) -> Double { abs(delta(a[i], b[i], i)) }
        let turn = 1 - cos(delta(a[yaw], b[yaw], yaw))
        let tilt = d(pitch) + d(roll)
        let eyes = 0.1 * (d(lookX) + d(lookY)) + d(blinkL) + d(blinkR) + d(laugh)
        let body = 0.02 * d(y) + 2 * (d(sx) + d(sy))
        let rest = 0.5 * d(breath) + d(whirl) + d(w0) + d(w1) + d(w2)
        return 4 * turn + tilt + eyes + body + rest
    }

    /// `a` toward `b` by `t` (0 … 1), angles the short way round.
    static func mix(_ a: [Double], _ b: [Double], _ t: Double) -> [Double] {
        (0..<count).map { a[$0] + delta(b[$0], a[$0], $0) * t }
    }
}

/// Picking where a recording comes back to its anchor (the variants' cuts), and blending each variant's ends into it.
enum ArisSpriteLoop {
    /// How far each frame (and the one after) is from the anchor frame `anchor` (and the one after): the seam a cut
    /// there would leave. The last frame has none (infinity).
    static func seams(_ frames: [[Double]], anchor: Int) -> [Double] {
        guard anchor + 1 < frames.count else { return frames.map { _ in .infinity } }
        return frames.indices.map { i in
            i + 1 < frames.count ? ArisPoseVector.distance(frames[i], frames[anchor]) + ArisPoseVector.distance(frames[i + 1], frames[anchor + 1]) : .infinity
        }
    }

    /// The cuts of up to `count` variants from `anchor`: each the frame in `lengths` past the last cut with the smallest
    /// seam among the frames `valid` allows (the earliest on a tie). The first cut is the anchor; the variants are the
    /// ranges between cuts. Stops early once the recording runs out.
    static func cuts(seams: [Double], anchor: Int, count: Int, lengths: ClosedRange<Int>, valid: (Int) -> Bool = { _ in true }) -> [Int] {
        var out = [anchor]
        for _ in 0..<max(0, count) {
            let c = out.last!
            let lo = c + max(1, lengths.lowerBound), hi = min(seams.count - 1, c + lengths.upperBound)
            guard lo <= hi else { break }
            var best: Int?
            for i in lo...hi where valid(i) && seams[i].isFinite {
                if best == nil || seams[i] < seams[best!] { best = i }
            }
            guard let b = best else { break }
            out.append(b)
        }
        return out
    }

    /// Whether frame `i` (at `fps`) keeps the anchor's phase in `period`, within half a frame.
    static func inPhase(_ i: Int, anchor: Int, fps: Double, period: Double) -> Bool {
        let t = Double(i - anchor) / fps
        var r = t.truncatingRemainder(dividingBy: period)
        if r < 0 { r += period }
        return min(r, period - r) <= 0.5 / fps + 1e-9
    }

    /// A variant's frames with both ends blended into the anchor's own run: its first `width` frames come out of the
    /// frames from the anchor on (`post`), its last `width` run into the frames just before the anchor (`pre`), each on
    /// a smoothstep. So a variant starts exactly on the anchor and ends exactly on the frame before it, and any variant
    /// may follow any other.
    static func blend(_ frames: [[Double]], pre: [[Double]], post: [[Double]], width: Int) -> [[Double]] {
        let n = frames.count
        let w = min(width, n / 2, pre.count, post.count)
        guard w > 0 else { return frames }
        func smooth(_ x: Double) -> Double { x * x * (3 - 2 * x) }
        var out = frames
        for m in 0..<w {
            // The start: all anchor at m = 0, all its own by m = w.
            out[m] = ArisPoseVector.mix(frames[m], post[m], 1 - smooth(Double(m) / Double(w)))
            // The end: all the frame before the anchor on the last frame.
            let j = n - w + m
            out[j] = ArisPoseVector.mix(frames[j], pre[pre.count - w + m], smooth(Double(m + 1) / Double(w)))
        }
        return out
    }
}

/// The order a layer plays a loop's variants in: shuffled, seeded per view, never the same variant three times running.
enum ArisSpritePlaylist {
    /// `plays` variant indices out of `count`.
    static func order(count: Int, plays: Int, seed: UInt64) -> [Int] {
        guard count > 1 else { return Array(repeating: 0, count: max(0, plays)) }
        var state = seed
        func next() -> UInt64 {
            // splitmix64
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        var out: [Int] = []
        // Each round plays every variant once, in a fresh order; a round never opens with the last one's last variant.
        while out.count < plays {
            var round = Array(0..<count)
            for i in stride(from: count - 1, to: 0, by: -1) { round.swapAt(i, Int(next() % UInt64(i + 1))) }
            if let last = out.last, round.first == last { round.swapAt(0, count - 1) }
            out += round
        }
        return Array(out.prefix(plays))
    }

    /// The frames a playlist steps through.
    static func frames(segments: [Range<Int>], order: [Int]) -> [Int] {
        order.flatMap { segments.indices.contains($0) ? Array(segments[$0]) : [] }
    }

    /// How many plays make at least `seconds` of a loop at `fps`.
    static func plays(segments: [Range<Int>], fps: Double, seconds: Double) -> Int {
        let frames = segments.map(\.count).reduce(0, +)
        guard frames > 0, !segments.isEmpty else { return 0 }
        let mean = Double(frames) / Double(segments.count) / fps
        return max(segments.count, Int((seconds / mean).rounded(.up)))
    }
}

/// Where frames sit in an atlas: left to right, then rows upward, in Core Graphics' bottom-left space, which is also
/// how a macOS layer reads contentsRect (y 0 is the image's bottom row).
struct ArisSpriteGrid: Equatable {
    let count: Int
    let cellPx: Int
    let columns: Int
    let rows: Int

    /// The longest side a layer's contents may have.
    static let maxSidePx = 8192

    init(count: Int, cellPx: Int) {
        self.count = max(1, count)
        self.cellPx = max(1, cellPx)
        let fit = max(1, Self.maxSidePx / self.cellPx)
        // As square as it fits: fewer, longer rows keep the image's width under the cap.
        let square = Int(Double(self.count).squareRoot().rounded(.up))
        columns = min(fit, max(1, square))
        rows = (self.count + columns - 1) / columns
    }

    var widthPx: Int { columns * cellPx }
    var heightPx: Int { rows * cellPx }
    /// RGBA, 8 bits a channel, as it sits in memory decoded.
    var bytes: Int { widthPx * heightPx * 4 }

    /// Frame `index`'s pixels in the atlas (Core Graphics space).
    func pixelRect(_ index: Int) -> CGRect {
        let i = min(count - 1, max(0, index))
        return CGRect(x: (i % columns) * cellPx, y: (i / columns) * cellPx, width: cellPx, height: cellPx)
    }

    /// Frame `index` as a layer's contentsRect.
    func unitRect(_ index: Int) -> CGRect {
        let p = pixelRect(index)
        return CGRect(x: p.minX / CGFloat(widthPx), y: p.minY / CGFloat(heightPx), width: CGFloat(cellPx) / CGFloat(widthPx), height: CGFloat(cellPx) / CGFloat(heightPx))
    }
}

/// One character's look at one size on one display: what an atlas is baked for.
struct ArisSpriteLook: Hashable {
    let type: String
    let colorHex: String?
    let shading: String
    /// Points: one of `standardSizes` (see `bakeSize`); the layer scales it to the size it's shown at.
    let size: CGFloat
    /// Display scale (1 or 2).
    let scale: CGFloat
    let dark: Bool

    /// The sizes atlases are baked at. A character shown at another size takes the nearest at or above it, scaled down
    /// on the render server, so a handful of sizes in the app share a few atlases.
    static let standardSizes: [CGFloat] = [14, 20, 44]

    /// The size to bake for a character shown `size` points big: the smallest standard size that holds it; past the
    /// largest, its own.
    static func bakeSize(_ size: CGFloat) -> CGFloat {
        standardSizes.first { $0 >= size - 0.01 } ?? size
    }

    /// The atlas cell, in pixels: the kit's canvas is 1.5 times the box.
    var cellPx: Int { Int((Double(size) * 1.5 * Double(scale)).rounded()) }

    /// A seed for the look's own Sim, fixed by the look so it moves the same every launch and two looks never move in
    /// step.
    var seed: Double { Double(ArisSpriteKey.fnv1a("\(type)|\(colorHex ?? "-")|\(shading)") % 1_000_000) / 1_000_000 }
}

/// An atlas's name on disk: the look, the clip and the renderer's version (a kit change re-bakes everything).
struct ArisSpriteKey: Hashable {
    let look: ArisSpriteLook
    let clip: ArisSpriteClip
    let version: String

    var canonical: String {
        let l = look
        return [l.type, l.colorHex ?? "-", l.shading, String(format: "%.2f", Double(l.size)), String(format: "%.2f", Double(l.scale)),
                l.dark ? "dark" : "light", clip.id, version].joined(separator: "|")
    }

    /// Stable across launches (Swift's Hasher is seeded per process).
    var fileName: String { String(format: "%016llx", Self.fnv1a(canonical)) }

    /// How the clip is recorded at this look's cell size (nil for the still poses and the follow grid).
    var spec: ArisSpriteSpec? { ArisSpriteSpec.plan(clip, cellPx: look.cellPx) }
    /// Frames a second it plays at (0: not played, poses picked one at a time).
    var fps: Double { spec?.fps ?? 0 }

    static func fnv1a(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x0000_0100_0000_01b3 }
        return h
    }
}

/// What sits beside an atlas on disk: what it is (its key, checked on read) and where its variants are.
struct ArisSpriteMeta: Codable, Equatable {
    var canonical: String
    var count: Int
    var cellPx: Int
    /// The variants, as [start, end) frame ranges.
    var segments: [[Int]]
    /// Which of them starts with a poke (the idle loop's), if any.
    var poke: Int?

    var ranges: [Range<Int>] { segments.compactMap { $0.count == 2 && $0[0] < $0[1] ? $0[0]..<$0[1] : nil } }

    /// Whether this meta describes `key`'s atlas, `width` × `height` pixels.
    func matches(_ key: ArisSpriteKey, width: Int, height: Int) -> Bool {
        let grid = ArisSpriteGrid(count: count, cellPx: cellPx)
        return canonical == key.canonical && cellPx == key.look.cellPx && grid.widthPx == width && grid.heightPx == height
            && ranges.count == segments.count && ranges.allSatisfy { $0.upperBound <= count } && (poke.map { ranges.indices.contains($0) } ?? true)
    }
}

/// The atlas cache's limit: the least recently used go first until what's left fits, never one a layer is showing.
enum ArisSpriteCache {
    struct Entry: Equatable {
        let name: String
        let bytes: Int
        let lastUsed: Date
    }

    /// On disk (PNG): about a tenth of the decoded size each, so this holds a few dozen looks.
    static let diskCapBytes = 96 * 1024 * 1024
    /// In memory (decoded).
    static let memoryCapBytes = 48 * 1024 * 1024

    /// Whether a queued atlas still bakes: not once the layers that held it have all let go (a picker tile scrolled off,
    /// a closed page). One no layer has held yet (a job's prefetch) still bakes.
    static func runnable<K: Hashable>(_ key: K, everHeld: Set<K>, held: Set<K>) -> Bool {
        !everHeld.contains(key) || held.contains(key)
    }

    /// Which entries to drop, oldest use first, so the rest fit in `cap` bytes; never a `pinned` one (in use), even if
    /// the pinned alone are over the cap. Ties go by name, so it is stable.
    static func evictions(_ entries: [Entry], cap: Int, pinned: Set<String> = []) -> [String] {
        var total = entries.reduce(0) { $0 + $1.bytes }
        guard total > cap else { return [] }
        var out: [String] = []
        for e in entries.sorted(by: { ($0.lastUsed, $0.name) < ($1.lastUsed, $1.name) }) where !pinned.contains(e.name) {
            guard total > cap else { break }
            out.append(e.name)
            total -= e.bytes
        }
        return out
    }

    /// The pinned atlases' bytes are over the cap by themselves (worth a log line, not an eviction).
    static func pinnedOverCap(_ entries: [Entry], cap: Int, pinned: Set<String>) -> Bool {
        entries.filter { pinned.contains($0.name) }.reduce(0) { $0 + $1.bytes } > cap
    }

    /// Files on disk to delete: an atlas without its meta or a meta without its atlas (names without extension).
    static func orphans(pngs: Set<String>, metas: Set<String>) -> (pngs: [String], metas: [String]) {
        (pngs.subtracting(metas).sorted(), metas.subtracting(pngs).sorted())
    }

    /// How long a failed bake waits before it may be tried again: 5 s, doubling, at most 5 minutes.
    static func retryDelay(failures: Int) -> TimeInterval {
        guard failures > 0 else { return 0 }
        return min(300, 5 * pow(2, Double(failures - 1)))
    }
}

/// Facing the way it travels: the rest pose turned about its vertical axis, −30° to 30° in 7.5° steps. Capped at 30°:
/// at 45° the star's far eye slides off its edge and its extrusion shows.
enum ArisSpriteFacing {
    static let maxYaw: CGFloat = 30
    static let step: CGFloat = 7.5
    static var count: Int { Int((2 * maxYaw / step).rounded()) + 1 }
    static var front: Int { count / 2 }

    /// Cell `index`'s turn, in degrees (positive: to the viewer's right).
    static func yaw(_ index: Int) -> CGFloat { CGFloat(index - front) * step }

    /// The cell nearest `yaw` degrees, the last one past the cap.
    static func cell(yaw: CGFloat) -> Int {
        front + Int((min(maxYaw, max(-maxYaw, yaw)) / step).rounded())
    }
}

/// Following the pointer without a live Sim: a grid of baked head poses at the kit's pull, and which one faces it.
enum ArisSpriteFollow {
    static let columns = 12
    static let rows = 5
    static var count: Int { columns * rows }
    /// The kit's reach: full pull within a head width, gone by three.
    static let reach = 3.0
    /// Pointer updates at most this often.
    static let interval = 1.0 / 30

    /// The pull cell (`column`, `row`) is baked for, −1 … 1 each way, y down.
    static func direction(_ index: Int) -> CGVector {
        let c = index % columns, r = index / columns
        return CGVector(dx: -1 + 2 * Double(c) / Double(columns - 1), dy: -1 + 2 * Double(r) / Double(rows - 1))
    }

    /// The kit's pull toward a pointer `offset` from the head, in head widths (y down), as BotAvatar hands it to
    /// `setPointer`: its direction (the offset itself within a head width) times its strength — full within a head
    /// width, fading to nothing at three. Nil once out of reach.
    static func pull(offset: CGVector) -> CGVector? {
        let d = (offset.dx * offset.dx + offset.dy * offset.dy).squareRoot()
        guard d.isFinite, d < reach else { return nil }
        let strength = d < 1 ? 1 : 1 - (d - 1) / (reach - 1)
        let k = strength / max(1, d)
        return CGVector(dx: offset.dx * k, dy: offset.dy * k)
    }

    /// The cell nearest a pull.
    static func cell(pull: CGVector) -> Int {
        let x = min(1, max(-1, pull.dx)), y = min(1, max(-1, pull.dy))
        let c = Int(((x + 1) / 2 * Double(columns - 1)).rounded())
        let r = Int(((y + 1) / 2 * Double(rows - 1)).rounded())
        return min(rows - 1, max(0, r)) * columns + min(columns - 1, max(0, c))
    }

    /// The cell facing a pointer `offset` from the character's centre; nil once it's out of reach.
    static func cell(offset: CGVector) -> Int? { pull(offset: offset).map { cell(pull: $0) } }

    /// The cell with no pull: the head at rest, where it eases back to before the loop takes over again.
    static var centre: Int { cell(pull: .zero) }

    /// One step from cell `from` toward `to`: at most a column and a row, so a fast pointer still turns the head
    /// through the poses between.
    static func step(from: Int, to: Int) -> Int {
        let fc = from % columns, fr = from / columns, tc = to % columns, tr = to / columns
        let c = fc + (tc > fc ? 1 : tc < fc ? -1 : 0)
        let r = fr + (tr > fr ? 1 : tr < fr ? -1 : 0)
        return r * columns + c
    }

    /// Whether a pointer event at `now` may update the head (`last` the previous update).
    static func due(last: TimeInterval?, now: TimeInterval) -> Bool {
        guard let last else { return true }
        return now - last >= interval * 0.95
    }
}

/// What a character's layer shows.
enum ArisSpritePlay: Equatable {
    /// A still pose: index into `.still` (0 idle, 1 asleep, 2 working).
    case still(Int)
    case loop(ArisSpriteClip)

    /// Upstream's states as they are: idle plays the idle loop, working the working loop, asleep the sleep loop (only a
    /// character that may sleep; the others stay idle). 모션 줄이기 (or the system's Reduce Motion): the state's rest pose,
    /// as upstream draws a reduced-motion avatar.
    static func from(state: String, canSleep: Bool, reduceMotion: Bool) -> ArisSpritePlay {
        switch state {
        case "working": reduceMotion ? .still(2) : .loop(.working)
        case "sleeping" where canSleep: reduceMotion ? .still(1) : .loop(.sleeping)
        default: reduceMotion ? .still(0) : .loop(.idle)
        }
    }

    /// The atlas this play needs.
    var clip: ArisSpriteClip {
        switch self {
        case .still: .still
        case let .loop(c): c
        }
    }

    /// Upstream's poke (a click on an interactive avatar) plays only over the idle loop here; the pointer is followed
    /// there too.
    var takesPokes: Bool { self == .loop(.idle) }
    var follows: Bool { self == .loop(.idle) }
    /// Dozing off or waking: the poses cross-fade slowly, as upstream's switch to sleep eases over a second and more.
    var asleep: Bool { self == .still(1) || self == .loop(.sleeping) }
}

/// Aris's own "zzz" over a sleeping character (upstream Bot Avatars has none, in its source or on its site): small
/// rounded z's rising from beside the head, up and to the side, each growing a little as it fades in and out, one every
/// 1.8 s, two in the air. Text layers animated on the render server; inside the character's canvas, so nothing reaches past what the
/// character itself may cover.
enum ArisSleepZ {
    enum Mode: Equatable { case none, drifting, resting }

    /// Asleep: drifting; asleep under 모션 줄이기: one small still z; awake: none.
    static func mode(_ play: ArisSpritePlay) -> Mode {
        switch play {
        case .loop(.sleeping): .drifting
        case .still(1): .resting
        default: .none
        }
    }

    static let count = 2
    static let interval = 1.8
    /// Each z's life: the count of them a beat apart, so the cycle meets itself.
    static var life: Double { Double(count) * interval }
    /// The ambient text alpha (white on the dark notch, black on light).
    static let opacity = 0.56
    /// Fades in over the first quarter, holds, fades out from 60 %.
    static let opacityKeys: [Double] = [0, opacity, opacity, 0]
    static let opacityTimes: [Double] = [0, 0.25, 0.6, 1]
    static let scaleFrom = 0.7
    static let scaleTo = 1.15
    /// Where a z's centre starts and ends, in the character's canvas (0 … 1, y down; the canvas is 1.5 times the box):
    /// from beside the star's top right, up and outward.
    static let from = CGPoint(x: 0.60, y: 0.36)
    static let to = CGPoint(x: 0.88, y: 0.11)
    /// The letter's size as a fraction of the character's box.
    static let fontFraction = 0.25

    static func fontSize(box: CGFloat) -> CGFloat { max(4, box * fontFraction) }
}
