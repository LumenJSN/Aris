import Foundation

/* The rig. A pose is a handful of numbers — head yaw / pitch / roll, a
   position, squash, how open the eyes are, where they look — and blend
   weights for the three states. A Sim advances a pose through time: each
   state sets targets and wanders around them, runs its own events (a
   flip, a hop, a nod, a blink), and a state change eases from one set of
   targets to the next on a timed curve, so it starts and ends softly.
   A line-for-line port of the web package's engine.ts (at 1c87c11; the
   file is unchanged since bfb396b). */

let botAvatarStates: [BotAvatarState] = [.default, .working, .sleeping]
/* the working state's hop: its period, and the height of the spinning one */
let HOP_T = 0.68
private let HOP_SPIN_H = 26.0
/* a flip is that spinning hop on its own: a crouch before it (the squash
   that, in the working state, the previous landing leaves), the hop, and
   the landing's recovery after — measured in hop periods */
private let FLIP_PRE = 0.2

/* a click's jump crouches for its squash time before take-off and lands
   with a squash of the same length; an idle jump's crouch is the working
   hop's short one */
func flipPre(_ j: BotAvatarJumpConfig, _ poked: Bool) -> Double { poked ? j.clickSquashTime : FLIP_PRE * j.time }
func flipDuration(_ j: BotAvatarJumpConfig, _ poked: Bool) -> Double {
    flipPre(j, poked) + j.time + squashPeak(j.squashEase) * (poked ? j.clickSquashTime : j.squashTime)
        + max(0, j.groundTime) + j.riseTime + max(0, j.land) + 0.05
}
/* where in its time each easing reaches the deepest squash */
func squashPeak(_ e: BotAvatarSquashEase) -> Double {
    switch e {
    case .sharp: 0
    case .pulse: 2.0 / 7
    case .soft: 0.5
    case .bouncy: 0.144
    }
}
/* the rise: how the body comes back from its deepest squash to its own
   shape, 1 → 0 over the rise time. `sharp` lets go at once and eases in
   to rest, `pulse` leaves quickly with a long settle, `soft` eases out of
   the squash and into rest, `bouncy` passes rest into a slight stretch
   and settles back. */
func risePulse(_ v: Double, _ ease: BotAvatarSquashEase) -> Double {
    if v <= 0 { return 1 }
    if v >= 1 { return 0 }
    switch ease {
    case .sharp: return (1 - v) * (1 - v)
    case .soft: return 0.5 + 0.5 * cos(.pi * v)
    case .bouncy: return exp(-3.2 * v) * cos(5.4 * v) - v * v * v * 0.026
    case .pulse:
        let k = 4.2 * v
        return (1 + k) * exp(-k) - v * v * v * 0.078
    }
}
/* the weight settling through the hold, as a gain on the deepest squash:
   the same four curves as the landing squash, pressing up to a quarter
   deeper and back to the held depth, so the hold's ends never step */
func groundShape(_ v: Double, _ ease: BotAvatarSquashEase) -> Double { 1 + 0.25 * squashPulse(v, ease) }
/* the landing squash over its time, 0–1 → its depth, 0–1 at the peak:
   sharp is all there at contact and eases off; pulse presses quickly and
   recovers without a wobble; soft eases in and out; bouncy overshoots
   into a stretch and settles. Each is faded out over the last part so it
   ends at nothing. */
func squashPulse(_ u: Double, _ ease: BotAvatarSquashEase) -> Double {
    if u <= 0 || u >= 1 { return 0 }
    var x: Double
    switch ease {
    case .sharp: x = (1 - u) * (1 - u)
    case .soft: x = pow(sin(.pi * u), 2)
    case .bouncy: x = (exp(-3.15 * u) * sin(8.43 * u)) / 0.596
    case .pulse:
        let k = 7 * u
        x = (k * k * exp(2 - k)) / 4
    }
    let tail = u > 0.85 ? 1 - (u - 0.85) / 0.15 : 1
    return x * tail * tail * (3 - 2 * tail)
}
/* the hop's shaping: squash on the ground, stretch at the top */
private func hopSquash(_ a: Double) -> Double { exp(-pow(min(abs(a), abs(a - 1)) / 0.11, 2)) }

/// The rig's output for one frame.
public struct BotAvatarPose {
    /// radians; yaw > 0 turns the face to the viewer's right, pitch > 0 looks up
    public var yaw = 0.0, pitch = 0.0, roll = 0.0
    /// body-box units (the 100×100 design space)
    public var x = 0.0, y = 0.0, sx = 1.0, sy = 1.0
    /// 0 shut … 1 open, before blinks
    public var eyeOpen = 1.0
    /// how far each lid is down right now, 0 … 1
    public var blinkL = 0.0, blinkR = 0.0
    public var lookX = 0.0, lookY = 0.0
    /// the breathing cycle, −1 … 1
    public var breath = 0.0
    /// working only: how far the eyes have closed into a laugh, 0 … 1
    public var laugh = 0.0
    /// the cartoon whirl round a spinning body: strength 0 … 1, and where
    /// its head is, in radians round the ring
    public var whirl = 0.0, whirlAngle = 0.0
    /// blend weights: default, working, sleeping — they sum to 1
    public var w: SIMD3<Double> = SIMD3(1, 0, 0)
    public init() {}

    /// The still pose of a state, for reduced motion and the first paint (the web's `restPose`).
    public static func rest(_ state: BotAvatarState) -> BotAvatarPose {
        let r = REST[state]!
        var p = BotAvatarPose()
        p.pitch = r.pitch; p.roll = r.roll; p.y = r.y; p.lookX = r.lookX; p.lookY = r.lookY
        p.w = SIMD3(state == .default ? 1 : 0, state == .working ? 1 : 0, state == .sleeping ? 1 : 0)
        return p
    }
}

private let DEG = Double.pi / 180
private let TAU = Double.pi * 2
/* How long a switch takes. Settling down takes longer than getting to
   work: coming back to idle the body has to let go of the hops, so it
   eases out over more than a second. */
let SWITCH_TO: [BotAvatarState: Double] = [.default: 1.2, .working: 0.7, .sleeping: 1.4]
let SWITCH_FROM_SLEEP = 1.0

/* Deterministic per-instance randomness (mulberry32). */
struct Mulberry32 {
    private var a: UInt32
    init(seed: UInt32) {
        let s = seed &* 0x9e3779b1
        a = s == 0 ? 1 : s
    }
    mutating func next() -> Double {
        a = a &+ 0x6d2b79f5
        var t = a
        t = (t ^ (t >> 15)) &* (t | 1)
        t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
        return Double(t ^ (t >> 14)) / 4294967296
    }
}

/// Exponential approach: `rate` per second, frame-rate independent.
@inline(__always) private func approach(_ cur: Double, _ target: Double, _ rate: Double, _ dt: Double) -> Double {
    cur + (target - cur) * (1 - exp(-rate * dt))
}
@inline(__always) private func easeInOut(_ p: Double) -> Double { p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2 }
/* gentler at both ends than the cubic: for drifting off and waking */
@inline(__always) func easeSine(_ p: Double) -> Double { 0.5 - 0.5 * cos(.pi * p) }

/* A value that drifts: picks a new target inside its range every hold,
   and eases toward it. The head channels move as a lightly damped spring,
   the eyes dart with an exponential approach. */
private struct Wander {
    var value = 0.0
    private var vel = 0.0
    private var target = 0.0
    private var next = 0.0
    var amp: Double, holdMin: Double, holdMax: Double, rate: Double
    let spring: Bool
    init(amp: Double, holdMin: Double, holdMax: Double, rate: Double, spring: Bool = false) {
        self.amp = amp; self.holdMin = holdMin; self.holdMax = holdMax; self.rate = rate; self.spring = spring
    }
    mutating func update(_ t: Double, _ dt: Double, _ rand: inout Mulberry32) {
        if t >= next {
            target = (rand.next() * 2 - 1) * amp
            next = t + holdMin + rand.next() * (holdMax - holdMin)
        }
        if spring {
            let w = rate * 1.6, z = 0.9
            vel += (w * w * (target - value) - 2 * z * w * vel) * dt
            value += vel * dt
        } else {
            value = approach(value, target, rate, dt)
        }
    }
    /// aim at a value and stay there: the rig picks the next one
    mutating func aim(_ v: Double) {
        target = v
        next = .infinity
    }
    mutating func set(_ amp: Double, _ holdMin: Double, _ holdMax: Double, _ rate: Double) {
        self.amp = amp; self.holdMin = holdMin; self.holdMax = holdMax; self.rate = rate
        next = 0
    }
}

/* A one-shot event: progress 0 → 1 over its duration, then idle at -1. */
private struct Event {
    var p = -1.0
    var duration: Double
    init(_ duration: Double) { self.duration = duration }
    mutating func fire() { p = 0 }
    var active: Bool { p >= 0 }
    mutating func update(_ dt: Double) {
        if p < 0 { return }
        p += dt / duration
        if p >= 1 { p = -1 }
    }
}

/* The idle gaze: how far the head swings, and how long it stays. The
   sideways reach is the big one — a look to a corner reads as a turn of
   the head, with the rise and a slight tilt going along. */
let GAZE_YAW = 35 * DEG
let GAZE_PITCH = 14 * DEG
private let GAZE_ROLL = 3.2 * DEG
let GAZE_HOLD_MIN = 2.6
let GAZE_HOLD_MAX = 4.4

private struct Rest { var pitch: Double, roll: Double, y: Double, lookX: Double, lookY: Double }
private let REST: [BotAvatarState: Rest] = [
    .default: Rest(pitch: 0, roll: 0, y: 0, lookX: 0, lookY: 0),
    .working: Rest(pitch: 5 * DEG, roll: 0, y: 0, lookX: 0, lookY: 0),
    .sleeping: Rest(pitch: -16 * DEG, roll: 6 * DEG, y: 3, lookX: 0, lookY: 1),
]

/// The simulation behind one avatar: advance it with `update(dt)` and draw `pose`.
public final class BotAvatarSim {
    public private(set) var pose = BotAvatarPose()
    public private(set) var state: BotAvatarState = .default

    private var rand: Mulberry32
    private var t = 0.0
    /* a state change: the weights it started from and its progress */
    private var wFrom = SIMD3<Double>(1, 0, 0)
    private var tr = 1.0
    private var trDuration = 1.2
    private var yawW: Wander
    private var pitchW: Wander
    private var rollW: Wander
    private var lookXW: Wander
    private var lookYW: Wander
    private var blink = Event(0.17)
    private var blinkAt = 0.0
    private var blinkAgain = false
    private var dart = Event(0.12)
    private var dartAt = 0.0
    private var dartX = 0.0
    private var dartY = 0.0
    private var flip = Event(flipDuration(.defaults, false))
    private var flipPoked = false
    private var jump = BotAvatarJumpConfig.defaults
    private var flipAt = 0.0
    private var flipSide = 1.0
    private var nod = Event(1.7)
    private var nodAt = 0.0
    private var hopPhase = 0.0
    private var hopCount = 0
    /* the hops' gain: the working weight while in the state, then held so a
       hop under way finishes whole when the state is left */
    private var hopGain = 0.0
    private var laughEv = Event(0.8)
    private var laughAt = 0.0
    /* the jelly: a damped spring driven by how fast the head turns, so a
       sweep stretches the body and it wobbles back */
    private var prevYaw = 0.0
    private var jelly = 0.0
    private var jellyV = 0.0
    /* how far the eyes run ahead of a head turn */
    private var gazeLead = 0.0
    /* the idle gaze: where the head is looking, and when it moves on */
    private var gazeDir = (0.0, 0.0)
    private var gazeAt = 0.0
    /* how far it turns to the side, 1 as the gaze has it */
    private var turnK = 1.0
    /* the breathing cycle's phase, in turns */
    private var breathPhase = 0.0
    /* the pointer, as an offset from the head in head-widths, and how much
       to follow it — both smoothed */
    private var ptrX = 0.0, ptrY = 0.0, ptrS = 0.0
    private var ptrTargetX = 0.0, ptrTargetY = 0.0, ptrTargetS = 0.0
    /* the smoothed yaw the head is turning to on its own */
    private var baseYaw = 0.0

    /// `seed` 0–1 offsets every loop so a row of avatars never moves in step.
    public init(seed: Double, state: BotAvatarState = .default) {
        rand = Mulberry32(seed: UInt32(truncatingIfNeeded: Int(floor(seed * 1e6)) + 1))
        yawW = Wander(amp: 36 * DEG, holdMin: 1.1, holdMax: 2.6, rate: 3, spring: true)
        pitchW = Wander(amp: 10 * DEG, holdMin: 1.1, holdMax: 2.6, rate: 2.6, spring: true)
        rollW = Wander(amp: 5 * DEG, holdMin: 1.6, holdMax: 3.2, rate: 2, spring: true)
        lookXW = Wander(amp: 3.6, holdMin: 0.5, holdMax: 2, rate: 14)
        lookYW = Wander(amp: 2.4, holdMin: 0.5, holdMax: 2, rate: 14)
        /* every instance starts somewhere else in its loops */
        t = rand.next() * 10
        hopPhase = rand.next()
        breathPhase = rand.next()
        /* event timers count from that start, so nothing fires on the first tick */
        blinkAt = t + 1 + rand.next() * 3
        flipAt = nextFlip(t, 1)
        nodAt = t + 3 + rand.next() * 4
        dartAt = t + 1 + rand.next() * 2
        laughAt = t + 0.6 + rand.next() * 1.5
        setState(state, immediate: true)
    }

    /// Start over with another seed (the view does this when its `seed` changes).
    public func reseed(_ seed: Double, state: BotAvatarState) {
        let fresh = BotAvatarSim(seed: seed, state: state)
        rand = fresh.rand; t = fresh.t; pose = fresh.pose; self.state = fresh.state
        wFrom = fresh.wFrom; tr = fresh.tr; trDuration = fresh.trDuration
        yawW = fresh.yawW; pitchW = fresh.pitchW; rollW = fresh.rollW; lookXW = fresh.lookXW; lookYW = fresh.lookYW
        blink = fresh.blink; blinkAt = fresh.blinkAt; blinkAgain = false
        dart = fresh.dart; dartAt = fresh.dartAt; dartX = 0; dartY = 0
        flip = fresh.flip; flipPoked = false; flipAt = fresh.flipAt; flipSide = 1
        nod = fresh.nod; nodAt = fresh.nodAt; hopPhase = fresh.hopPhase; hopCount = 0; hopGain = 0
        laughEv = fresh.laughEv; laughAt = fresh.laughAt
        prevYaw = 0; jelly = 0; jellyV = 0; gazeLead = 0; gazeDir = fresh.gazeDir; gazeAt = fresh.gazeAt
        breathPhase = fresh.breathPhase
        ptrX = 0; ptrY = 0; ptrS = 0; ptrTargetX = 0; ptrTargetY = 0; ptrTargetS = 0; baseYaw = 0
        let j = jump, k = turnK
        jump = .defaults; turnK = 1
        setJump(j)
        setTurn(k)
    }

    public func setState(_ next: BotAvatarState, immediate: Bool = false) {
        if next == state && !immediate { return }
        let from = state
        state = next
        if immediate {
            pose.w = SIMD3(next == .default ? 1 : 0, next == .working ? 1 : 0, next == .sleeping ? 1 : 0)
            tr = 1
        } else {
            wFrom = pose.w
            tr = 0
            trDuration = from == .sleeping ? SWITCH_FROM_SLEEP : SWITCH_TO[next]!
        }
        switch next {
        case .default:
            /* the head takes its time: it holds a place, then swings to the
               next over about a second — no short quick jabs. The gaze picks
               where, so these carry the motion and their amplitude is unused. */
            yawW.set(GAZE_YAW, 2.6, 5.4, 2)
            pitchW.set(GAZE_PITCH, 2.8, 5.8, 1.8)
            rollW.set(GAZE_ROLL, 3.4, 6.6, 1.5)
            gazeAt = 0
            gazeDir = (0, 0)
            /* the eyes keep their quickness: they dart, the head follows */
            lookXW.set(3.6, 0.6, 2.2, 13)
            lookYW.set(2.4, 0.6, 2.2, 13)
            flipAt = nextFlip(t, 0.6)
        case .working:
            yawW.set(16 * DEG, 0.9, 1.8, 4)
            pitchW.set(3 * DEG, 1.2, 2.4, 3)
            rollW.set(0, 1, 2, 3)
            lookXW.set(2, 0.5, 1.2, 12)
            lookYW.set(1, 0.5, 1.2, 12)
            hopPhase = 0
            hopCount = 0
            laughAt = t + 0.5 + rand.next() * 1.2
        case .sleeping:
            yawW.set(7 * DEG, 3, 6, 0.7)
            pitchW.set(3 * DEG, 3, 6, 0.7)
            rollW.set(2 * DEG, 3, 6, 0.6)
            lookXW.set(0, 2, 4, 2)
            lookYW.set(0, 2, 4, 2)
            nodAt = t + 2.5 + rand.next() * 4
        }
    }

    /// Where the pointer is, relative to the head (−1 … 1 across a head
    /// width), and how strongly to follow it (0 lets go).
    public func setPointer(x: Double, y: Double, strength: Double) {
        ptrTargetX = max(-1.2, min(1.2, x))
        ptrTargetY = max(-1.2, min(1.2, y))
        ptrTargetS = max(0, min(1, strength))
    }

    /// A hop and a full turn, right now, whatever the state.
    public func poke() {
        if flip.active && flip.p < 0.6 { return }
        flipPoked = true
        flip.duration = flipDuration(jump, true)
        flipSide = rand.next() < 0.5 ? -1 : 1
        flip.fire()
        flipAt = nextFlip(t, 1.1)
    }

    /// How far the head turns to the side while idle: 1 as the gaze has
    /// it, 0 keeps it facing forward.
    public func setTurn(_ k: Double) {
        let next = max(0, k)
        if next == turnK { return }
        turnK = next
        /* take the new reach at once rather than at the next place */
        if state == .default { gazeAt = 0 }
    }

    /// The jump's numbers.
    public func setJump(_ j: BotAvatarJumpConfig) {
        let every = jump.every
        jump = j
        /* a new interval takes effect at once, so `every: 0` stops the next
           jump that was already due and a first value starts the clock */
        if j.every != every { flipAt = nextFlip(t, 1) }
    }
    public var jumpConfig: BotAvatarJumpConfig { jump }

    /* Where the head looks next. From a corner it mostly swings straight
       across to the opposite one — top right, stay, bottom left — now and
       then only sideways, or back to the middle for a beat. */
    private func nextGaze() -> (Double, Double) {
        let (px, py) = gazeDir
        if px != 0 || py != 0 {
            let p = rand.next()
            if p < 0.66 { return (-px, -py) }
            if p < 0.85 { return (-px, py) }
            return (0, 0)
        }
        let corners: [(Double, Double)] = [(1, -1), (-1, 1), (-1, -1), (1, 1)]
        return corners[Int(floor(rand.next() * Double(corners.count)))]
    }

    /* when the next idle jump is due: `every` seconds, give or take 40 % */
    private func nextFlip(_ t: Double, _ k: Double) -> Double {
        let every = jump.every
        return every > 0 ? t + every * k * (0.625 + rand.next() * 0.75) : .infinity
    }

    /// Advance by `dt` seconds (already scaled by the speed).
    public func update(_ dt0: Double) {
        let dt = min(dt0, 0.05)
        t += dt
        let t = self.t

        /* the state change eases from the weights it started with to the new
           state's on an S-curve: soft start, soft finish, no creeping tail */
        if tr < 1 {
            tr = min(1, tr + dt / trDuration)
            /* a sine ease: no kick at either end of a switch */
            let e = easeSine(tr)
            for i in 0..<3 {
                let target: Double = botAvatarStates[i] == state ? 1 : 0
                pose.w[i] = wFrom[i] + (target - wFrom[i]) * e
            }
        }
        let w = pose.w
        let wd = w[0], ww = w[1], ws = w[2]

        /* rest targets, blended */
        var restPitch = 0.0, restRoll = 0.0, restY = 0.0, restLookX = 0.0, restLookY = 0.0
        for i in 0..<3 {
            let r = REST[botAvatarStates[i]]!
            restPitch += r.pitch * w[i]; restRoll += r.roll * w[i]; restY += r.y * w[i]
            restLookX += r.lookX * w[i]; restLookY += r.lookY * w[i]
        }

        /* the idle gaze: a place to look, a while to stay, then the swing to
           the next — the wanderers carry it on their own springs */
        if state == .default && t >= gazeAt {
            let (gx, gy) = nextGaze()
            gazeDir = (gx, gy)
            let reach = 0.84 + rand.next() * 0.16
            yawW.aim(gx * GAZE_YAW * reach * turnK)
            pitchW.aim(gy * GAZE_PITCH * reach)
            /* the tilt goes with the turn, so it follows it */
            rollW.aim(gx * GAZE_ROLL * reach * turnK)
            gazeAt = t + GAZE_HOLD_MIN + rand.next() * (GAZE_HOLD_MAX - GAZE_HOLD_MIN)
        }

        /* wander */
        yawW.update(t, dt, &rand)
        pitchW.update(t, dt, &rand)
        rollW.update(t, dt, &rand)
        lookXW.update(t, dt, &rand)
        lookYW.update(t, dt, &rand)

        /* following the pointer: the eyes lead, the head turns after them,
           and the wander quietens while it lasts */
        ptrS = approach(ptrS, ptrTargetS, 8, dt)
        ptrX = approach(ptrX, ptrTargetX, 14, dt)
        ptrY = approach(ptrY, ptrTargetY, 14, dt)
        let ps = ptrS
        let quiet = 1 - 0.75 * ps

        /* the base pose: the blended rest plus the smoothed wander and the
           pointer's pull — every term is already continuous */
        baseYaw = approach(baseYaw, yawW.value * quiet + 22 * DEG * ptrX * ps, 5, dt)
        let basePitch = restPitch + pitchW.value * quiet - 12 * DEG * ptrY * ps
        let baseRoll = restRoll + rollW.value * quiet
        let baseY = restY
        let baseLookX = restLookX + lookXW.value * quiet + 4.5 * ptrX * ps
        let baseLookY = restLookY + lookYW.value * quiet + 3 * ptrY * ps

        /* ── events ── */
        var spin = 0.0, hopY = 0.0, sx = 1.0, sy = 1.0, pitchAdd = 0.0, rollAdd = 0.0, blinkClose = 0.0, lookXAdd = 0.0, lookYAdd = 0.0, laugh = 0.0
        var whirl = 0.0, whirlAngle = 0.0
        /* the whirl: not there until the turn is visibly under way, gone
           before the landing */
        func smooth(_ a: Double, _ b: Double, _ v: Double) -> Double {
            let x = min(1, max(0, (v - a) / (b - a)))
            return x * x * (3 - 2 * x)
        }
        func envelope(_ q: Double) -> Double { smooth(0.1, 0.26, q) * (1 - smooth(0.66, 0.9, q)) }
        /* the ring's own travel: fast and steady from the first frame, with a
           little of the body's own easing on top */
        func ringAngle(_ q: Double) -> Double { TAU * (1.5 * q + 0.9 * easeInOut(q)) }

        /* blinks: idle and working blink; a double blink now and then */
        if t >= blinkAt && !blink.active && wd + ww > 0.5 {
            blink.fire()
            blinkAgain = !blinkAgain && rand.next() < 0.22
            blinkAt = t + (blinkAgain ? 0.28 : 2.2 + rand.next() * 2.6)
        }
        blink.update(dt)
        if blink.active { blinkClose = sin(.pi * blink.p) }

        /* eye darts: a quick glance to the side and back, between the slower
           looks — the eyes have a life of their own */
        if t >= dartAt && !dart.active && wd + ww > 0.5 {
            dart.fire()
            dartX = (rand.next() * 2 - 1) * 4
            dartY = (rand.next() * 2 - 1) * 2
            dart.duration = 0.25 + rand.next() * 0.45
            dartAt = t + 1.2 + rand.next() * 2.6
        }
        dart.update(dt)
        if dart.active {
            let q = dart.p
            /* snap out, hold, snap back */
            let hold = q < 0.15 ? q / 0.15 : q > 0.8 ? (1 - q) / 0.2 : 1
            lookXAdd += dartX * hold * (wd + ww)
            lookYAdd += dartY * hold * (wd + ww)
        }

        /* idle: a full turn now and then, with a jump */
        if state == .default && t >= flipAt && !flip.active {
            flipPoked = false
            flip.duration = flipDuration(jump, false)
            flipSide = rand.next() < 0.5 ? -1 : 1
            flip.fire()
            flipAt = nextFlip(t, 1)
        }
        flip.update(dt)
        if flip.active {
            let J = jump
            /* the hop's own phase: below 0 the crouch, above 1 the recovery */
            let preS = flipPre(J, flipPoked)
            let a = (flip.p * flip.duration - preS) / J.time
            let q = min(1, max(0, a))
            let arc = sin(.pi * q)
            /* whole turns, eased in and out, no overshoot to snap back from */
            spin += TAU * J.spin * easeInOut(q)
            hopY -= J.height * arc
            /* the crouch before take-off; then the landing squash from `land`
               seconds round the moment of contact */
            let tl = (a - 1) * J.time - J.land
            let squashTime = flipPoked ? J.clickSquashTime : J.squashTime
            /* the crouch: a click's builds over its squash time, an idle jump's
               is the hop's short bump; then the hop, then the landing squash */
            let poked = flipPoked
            func crouch(_ u: Double) -> Double { poked ? u * u * (3 - 2 * u) : hopSquash(u - 1) }
            /* the landing in three parts: the press down to the deepest squash
               in the squash easing's own shape, the hold on the ground, then
               the rise back to the body's shape — each with its own time and
               easing, and all three meeting at the same depth */
            let hold = max(0, J.groundTime)
            let peakT = squashPeak(J.squashEase) * squashTime
            let rise = tl - peakT - hold
            let depth = tl <= peakT
                ? squashPulse(tl / squashTime, J.squashEase)
                : rise <= 0
                    ? groundShape((tl - peakT) / hold, J.groundEase)
                    : risePulse(rise / J.riseTime, J.riseEase)
            let land = (a < 0 ? crouch(max(0, 1 + (a * J.time) / preS)) : tl > 0 ? depth : a < 0.2 ? hopSquash(a) : 0) * J.squash
            sx += 0.16 * land - 0.06 * arc * J.stretch
            sy += -0.18 * land + 0.09 * arc * J.stretch
            /* lean into it; eyes shut for a turn */
            rollAdd += flipSide * J.lean * DEG * arc
            if J.spin > 0 {
                laugh = max(laugh, arc)
                whirl = max(whirl, envelope(q))
                whirlAngle = ringAngle(q)
            }
        }

        /* working: hops all the time; every third one spins. Leaving the
           state, the hop under way keeps the strength it had — it flies its
           whole arc, finishes its turn and lands — and that last landing is
           not the rhythm's quick bump but a jump's proper one: the hold on
           the ground and the rise back, from the depth the hop reached. */
        let J = jump
        let exitHold = max(0, J.groundTime)
        let exitFor = exitHold + J.riseTime
        if state == .working { hopGain = ww }
        if hopGain > 0.02 && (state == .working || hopPhase > 0) {
            hopPhase += dt / HOP_T
            if hopPhase >= 1 {
                if state == .working {
                    hopPhase -= 1
                    hopCount += 1
                } else if (hopPhase - 1) * HOP_T >= exitFor {
                    /* the last hop has landed and settled */
                    hopPhase = 0
                    hopGain = 0
                }
            }
            let g = hopGain
            /* past 1 the body is down and only the landing is still playing */
            let q = min(1, hopPhase)
            let arc = sin(.pi * q)
            let spinning = hopCount % 3 == 2
            let h = spinning ? HOP_SPIN_H : 18
            hopY -= h * arc * g
            /* squash on landing, stretch at the top */
            let exitT = state != .working && hopPhase > 1 ? (hopPhase - 1) * HOP_T : -1
            let land = exitT < 0
                ? hopSquash(hopPhase)
                : exitT < exitHold
                    ? groundShape(exitT / exitHold, J.groundEase)
                    : risePulse((exitT - exitHold) / J.riseTime, J.riseEase)
            sx += (0.16 * land - 0.06 * arc) * g
            sy += (-0.18 * land + 0.09 * arc) * g
            if spinning {
                spin += TAU * easeInOut(q) * g
                /* eyes shut for the spin */
                laugh = max(laugh, arc * g)
                if envelope(q) * g > whirl {
                    whirl = envelope(q) * g
                    whirlAngle = ringAngle(q)
                }
            }
            /* lean into each hop, alternating sides */
            rollAdd += (hopCount % 2 == 0 ? 1 : -1) * 6 * DEG * arc * g
        }

        /* working: now and then a laugh shuts the eyes into arcs, then they
           open again */
        if state == .working && t >= laughAt && !laughEv.active {
            laughEv.fire()
            laughEv.duration = 0.6 + rand.next() * 0.5
            laughAt = t + 1.6 + rand.next() * 2.2
        }
        laughEv.update(dt)
        if laughEv.active {
            let q = laughEv.p
            /* quick shut, hold, quick open */
            laugh = max(laugh, q < 0.18 ? q / 0.18 : q > 0.78 ? (1 - q) / 0.22 : 1)
        }

        /* sleeping: the head drops, then jerks back up */
        if state == .sleeping && t >= nodAt && !nod.active {
            nod.fire()
            nodAt = t + 4 + rand.next() * 4
        }
        nod.update(dt)
        if nod.active {
            let q = nod.p
            /* slow slide down, quick recovery */
            let dip = q < 0.72 ? easeInOut(q / 0.72) : 1 - easeInOut((q - 0.72) / 0.28)
            pitchAdd -= 13 * DEG * dip * ws
        }

        /* breathing, always, deeper and slower asleep. The phase is integrated
           so the period can change with the state without the cycle jumping */
        breathPhase += dt / (3.6 + 1.2 * ws)
        let breath = sin(breathPhase * TAU)
        pose.breath = breath
        sx += breath * (0.008 + 0.014 * ws)
        sy += breath * (0.012 + 0.02 * ws)
        let bob = sin(t * TAU / 3.4) * 2 * (1 - ws)

        /* ── compose ── */
        pose.yaw = baseYaw + spin

        /* the jelly: the faster the head turns, the more the body stretches
           along the turn, on a spring that overshoots and settles. A flip's
           spin is left out: that is a jump, and the landing spring handles it. */
        var dyaw = baseYaw - prevYaw
        dyaw = ((dyaw + .pi).truncatingRemainder(dividingBy: TAU) + TAU).truncatingRemainder(dividingBy: TAU) - .pi
        prevYaw = baseYaw
        let rate = dt > 0 ? abs(dyaw) / dt : 0
        /* the eyes lead a head turn, the way a gaze shift goes: they run
           ahead of it and come back as the head settles */
        let leadTarget = dt > 0 ? max(-2.2, min(2.2, (dyaw / dt) * 2.4)) : 0
        gazeLead = approach(gazeLead, leadTarget, 9, dt)
        let jellyTarget = min(0.22, 0.055 * rate)
        let omega = 16.0, zeta = 0.45
        jellyV += (omega * omega * (jellyTarget - jelly) - 2 * zeta * omega * jellyV) * dt
        jelly += jellyV * dt
        let jel = max(-0.08, min(0.28, jelly)) * 0.6
        sx *= 1 + jel
        sy *= 1 - 0.55 * jel

        pose.pitch = basePitch + pitchAdd
        pose.roll = baseRoll + rollAdd
        pose.x = 0
        pose.y = baseY + hopY + bob
        pose.sx = sx
        pose.sy = sy
        /* the lids: the sleeping state closes them through its own weight in
           the renderer, so here the eyes stay open apart from blinks */
        pose.eyeOpen = 1
        pose.laugh = approach(pose.laugh, laugh, 30, dt)
        pose.blinkL = blinkClose
        pose.blinkR = blinkClose
        pose.lookX = baseLookX + lookXAdd + gazeLead
        pose.lookY = baseLookY + lookYAdd
        pose.whirl = whirl
        pose.whirlAngle = whirlAngle
    }
}
