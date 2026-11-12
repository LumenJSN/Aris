import CoreGraphics
import Foundation

/* ── fabric: a plush pile instead of a clear coat ─────────────────── */

/* The same form, dressed in a plush pile. The fibres are combed from a
   parting behind the top of the head and hang, gathered into locks that
   lie along the flow; past the edge the locks stand out as soft tufts with
   a haze of hairs, so the silhouette is soft instead of cut. Everything
   here depends only on the form, so it is made once per outline and size
   and kept.

   A port of plastic.ts at bfb396b: `furJob` (this file: the flow, the
   locks and the fleece; BotAvatarFabricHairs.swift: the hairs, the fuzz,
   the tufts and the halo), with its constants, `rng`, `hash2`, `hash3`,
   `valueNoise` and `valueNoise3`. The web bakes in idle-time steps; here
   the same steps run in order on the bake queue. */

/// The pile for one outline, depth, size and light.
final class Fur {
    /** the pile's own resolution: finer than the form, so the fibres stay thin on a large avatar */
    let R: Int
    /** the body plus a fringe of hairs past its edge, as alpha: the halo */
    var mask: CGImage?
    /** how far the halo's hairs are lit toward their tips, as alpha */
    var haze: CGImage?
    /** the halo's complement, made on first use (see furCut) */
    var cut: CGImage?
    /** the body's inside, clear of the halo's band along the outline */
    var core: CGImage?
    /** the pile as a film over the wider square FILM_SPAN across: black
        where it deepens the colour, white where it lightens it */
    var dark: CGImage?
    var light: CGImage?
    /** the light on single fibres, white: the key's highlights along them
        and the back light they carry, and the soft back light's even glow */
    var glint: CGImage?
    var back: CGImage?
    var backSoft: CGImage?
    /** the films in the body's colour, made on first use (main thread only;
        the images above are written once, on the bake queue, before the
        pile is filed, and only read after) */
    var gapFilms: [FilmKey: CGImage?] = [:]
    var tipFilms: [FilmKey: CGImage?] = [:]
    var sheenFilms: [FilmKey: CGImage?] = [:]
    init(R: Int) { self.R = R }
}

/* the pile's resolution for a cap drawn `capPx` device pixels across */
func furTier(_ capPx: Double) -> Int { capPx <= 200 ? 192 : capPx <= 360 ? 320 : 512 }

/* the pile's neutral grey: below it the film darkens the colour, above it
   lightens it, as a hard-light blend of the grey would */
let FUR_MID = 128.0
/* the locks: how many overlap each point of the pile on average, how many
   more are seeded than a surface seen face-on needs, and how a lock tapers
   — its width sqrt(s)·(1 − s) brought to 1 at its widest */
let LOCK_COVER = 3.2
let LOCK_DENSE = 1 / 2.56
let LOCK_TAPER = 1 / ((2.0 / 3) * (1.0 / 3).squareRoot())
/* how much sparser the locks grow between the tufts they gather into */
let LOCK_PART = 0.6
/* the light in the pile, against the key's full strength: the room's, the
   fill's (from the front, on the side away from the key), and how far the
   key wraps past the terminator through the fibres */
let PILE_AMB = 0.07
let PILE_FILL = 0.14
let PILE_WRAP = 0.3
/* how much of the key a lock's shadow takes from the pile below it, how
   dark the hollows between locks are, how much a lock's root is shaded by
   the tip lying over it, and how much less of the key a fibre lying along
   it catches than one lying across it */
let PILE_SHADOW = 0.6
let PILE_AO = 0.35
let PILE_ROOT = 0.3
let PILE_KK = 0.3
/* the pile's light against the smooth body's, brought back to about one
   on average, and how far the film's light part lifts the colour */
let PILE_GAIN = 1.26
let PILE_LIFT = 1.6
/* the even lift that gives back what the pile's relief takes on average */
let PILE_BIAS = 0.045
/* how far a plush's fibres stand out of the surface (about 29°) */
let PILE_STAND = 0.5
let PILE_COS = cos(PILE_STAND), PILE_SIN = sin(PILE_STAND)
/* how much of the light the pile loses at the deepest of a crease */
let PILE_CREASE = 0.22
/* how high the pile's tops stand over its hollows, in design units per
   unit of its length: how far the two move apart as the body turns */
let PILE_H = 0.5
/* the smooth body's light where the key is full on it, and the light the
   film's light part lifts the colour toward */
let PILE_LIT = 1.1
let TIP_TOP = 1.625
/* the fine strands: thinning toward the tip by this much of its weight,
   how much lighter a strand's tip is than its root, the shortest against
   the longest, how high a strand stands over the pile and how dark the
   shadow it casts there */
let STRAND_TAPER = 0.5
let STRAND_RISE = 0.9
let STRAND_SHORT = 0.7
let STRAND_CAST_H = 0.15
let STRAND_CAST = 1.3
/* how far past the body's square the pile's film reaches, and its span */
let FILM_M = 20.0
let FILM_SPAN = BOT_AVATAR_SPAN + 2 * FILM_M
/* the halo: how dense its haze is at the outline, how much its hairs
   streak it, and how far each is drawn out along the flow */
let HALO_A = 0.8
let HALO_STREAK = 0.3
let HALO_HAIR = 0.8
/* how far the halo's hairs turn to the front's brightest colour toward their tips */
let HALO_LIFT = 0.7
/* a triangle kernel's mean of the noise and the spread it keeps */
let W_MEAN = 0.25
let W_SD = (1.0 / 7 - 1.0 / 16).squareRoot()

private let PAD = BOT_AVATAR_PAD, SPAN = BOT_AVATAR_SPAN

/* ── noise ─────────────────────────────────────────────────────────── */

/// A stable white noise, so every avatar of a type wears the same pile
/// (the web's hash2, in 32-bit integer arithmetic).
@inline(__always) func hash2(_ x: Int, _ y: Int) -> Double {
    var h = UInt32(truncatingIfNeeded: Int64(x) &* 374761393 &+ Int64(y) &* 668265263)
    h = (h ^ (h >> 13)) &* 1274126177
    return Double(h ^ (h >> 16)) / 4294967296
}
@inline(__always) func hash3(_ x: Int, _ y: Int, _ z: Int) -> Double {
    var h = UInt32(truncatingIfNeeded: Int64(x) &* 374761393 &+ Int64(y) &* 668265263 &+ Int64(z) &* 1274126177)
    h = (h ^ (h >> 13)) &* 1274126177
    return Double(h ^ (h >> 16)) / 4294967296
}

/// A small deterministic generator (mulberry32), so a type's pile is the
/// same every bake.
struct FurRandom {
    private var a: UInt32
    init(_ seed: Int) { a = UInt32(truncatingIfNeeded: seed) }
    mutating func next() -> Double {
        a = a &+ 0x6d2b79f5
        var t = (a ^ (a >> 15)) &* (1 | a)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return Double(t ^ (t >> 14)) / 4294967296
    }
}

/// Smooth value noise over the design box.
struct ValueNoise {
    let scale: Double, seed: Int
    @inline(__always) func callAsFunction(_ x: Double, _ y: Double) -> Double {
        let fx = x / scale, fy = y / scale
        let x0 = floor(fx), y0 = floor(fy)
        let tx = fx - x0, ty = fy - y0
        let sx = tx * tx * (3 - 2 * tx), sy = ty * ty * (3 - 2 * ty)
        let i = Int(x0), j = Int(y0)
        func h(_ i: Int, _ j: Int) -> Double { hash2(i + seed * 131, j - seed * 71) }
        let a = h(i, j), b = h(i + 1, j), c = h(i, j + 1), d = h(i + 1, j + 1)
        return (a + (b - a) * sx) * (1 - sy) + (c + (d - c) * sx) * sy
    }
}

/// The same in three dimensions: a solid texture read on the body's surface.
struct ValueNoise3 {
    let scale: Double, seed: Int
    func callAsFunction(_ x: Double, _ y: Double, _ z: Double) -> Double {
        let fx = x / scale, fy = y / scale, fz = z / scale
        let x0 = floor(fx), y0 = floor(fy), z0 = floor(fz)
        let tx = fx - x0, ty = fy - y0, tz = fz - z0
        let sx = tx * tx * (3 - 2 * tx), sy = ty * ty * (3 - 2 * ty), sz = tz * tz * (3 - 2 * tz)
        let i = Int(x0), j = Int(y0), k = Int(z0)
        func h(_ i: Int, _ j: Int, _ k: Int) -> Double { hash3(i + seed * 131, j - seed * 71, k + seed * 17) }
        func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
        let c00 = lerp(h(i, j, k), h(i + 1, j, k), sx), c10 = lerp(h(i, j + 1, k), h(i + 1, j + 1, k), sx)
        let c01 = lerp(h(i, j, k + 1), h(i + 1, j, k + 1), sx), c11 = lerp(h(i, j + 1, k + 1), h(i + 1, j + 1, k + 1), sx)
        return lerp(lerp(c00, c10, sy), lerp(c01, c11, sy), sz)
    }
}

/// x^e over x ∈ [0, 1] as a table of POW_N + 1, for a fractional exponent.
let FUR_POW_N = 1024
func furPowLut(_ e: Double) -> [Double] { (0...FUR_POW_N).map { pow(Double($0) / Double(FUR_POW_N), e) } }

/* ── the bake ──────────────────────────────────────────────────────── */

/**
 The pile for a form: made once per outline, texture size and light.

 A faux fur like a plush toy's: fine strands lying in one flow — combed
 from a parting behind the top of the head and falling — gathered into
 locks, and the locks into tufts. Each lock is a tapering mound laid on the
 body's curved surface and seen as that surface is; together they make a
 height field, lit by the same key and fill as the body. Over that,
 strands and single hairs. It is kept as a film in two parts, black where
 it deepens the colour and white where it lightens it, over a square wider
 than the body's. The silhouette breaks into tufts of hairs standing past
 it, with a haze of fine hairs between them.
 */
final class FurBake {
    let form: FabricForm
    let N: Int
    let R: Int
    /** pixels per design unit */
    let px: Double
    let O: Double
    let Rb: Int
    let fur: Fur
    var rand: FurRandom
    let lean = ValueNoise(scale: 3.4, seed: 21), tone = ValueNoise(scale: 22, seed: 9)
    /* slow swirls across the body: where the pile parts and turns */
    let swirl = ValueNoise(scale: 13, seed: 57)
    let kLen: Double, kDen: Double, fuzz: Double, clumps: Double, curl: Double, gravity: Double
    let Lx: Double, Ly: Double
    /* the key, back light, fill and the key's half vector as the front sees them head-on */
    let K3: V3, B3: V3, H3: V3, F3: V3
    var crownY = 12.0
    let crownX = 50.0

    /* 1. the flow on a coarse grid */
    let G = 112
    let gu: Double
    var flowX: [Float], flowY: [Float], tiltG: [Float]
    var nXg: [Float], nYg: [Float], nZg: [Float]
    var onG: [Float]
    var pfX: [Float], pfY: [Float], foreG: [Float]
    var hG: [Float], creaseG: [Float]
    var toneG: [Float]

    /* 2. the locks */
    let Rl: Int, pl: Double
    var lock: [Float], lockLit: [Float]
    let bump: ValueNoise, swell: ValueNoise
    let tuftK: Double
    let lockW: Double, lockWd: Double, lockLd: Double, hMax: Double
    var pileH: [Float], own: [Int32]
    let LP = 16
    let cell: Double, gn: Int
    var locks: [Float]
    var nLocks = 0
    let stand0: Double
    let tuftN: ValueNoise3, sizeN: ValueNoise
    let tuftH: Double
    var pileB: [Float]
    let rB: Int

    /* 3. the fleece */
    let dark: FabricBitmap, light: FabricBitmap, glint: FabricBitmap, back: FabricBitmap, soft: FabricBitmap, maskBmp: FabricBitmap
    var white: [Float]
    var fib = [Double](repeating: 0, count: 11)
    var seen = [Double](repeating: 0, count: 4)
    let strandHalf: Int
    var strandW: [[Float]] = []
    var strandMean: [Float], strandSd: [Float]
    let strandK: Double
    let NSH: Int
    var shX: [Int], shY: [Int], shD: [Float]
    let difLut: [Double], gamLut: [Double]
    let depthK: Double
    var strandBuf: [Float]

    /* the hairs, the fuzz and the tufts (BotAvatarFabricHairs.swift) */
    let fine: Double
    var cells: [Int] = []
    var fringe = CGMutablePath()
    var fringeBack: [CGMutablePath]
    var tufts = CGMutablePath()
    var tuftTips: [CGMutablePath]
    var tuftBack: [CGMutablePath]

    init(form: FabricForm, R: Int, lx: Double, ly: Double, style: BotAvatarFurStyle, lights: FurLights) {
        self.form = form
        N = form.N
        self.R = R
        px = Double(R) / SPAN
        O = PAD + FILM_M
        Rb = Int(jsRound(Double(R) * FILM_SPAN / SPAN))
        fur = Fur(R: R)
        rand = FurRandom(N * 7919 + 17)
        kLen = style.length; kDen = style.density; fuzz = style.fuzz; clumps = style.clumps; curl = style.curl; gravity = style.gravity
        var ll = (lx * lx + ly * ly).squareRoot()
        if ll == 0 { ll = 1 }
        Lx = lx / ll; Ly = ly / ll
        let Uf = V3(Lx, Ly, 0), Vf = V3(0, 0, 1), Df = V3(0, 1, 0)
        K3 = fabricKey(Uf, Vf, lights.front)
        B3 = fabricBack(V3(lights.bx, lights.by, 0), Vf)
        H3 = unit3(V3(K3[0], K3[1], K3[2] + 1))
        F3 = unit3(-0.55 * Uf + 0.85 * Vf + 0.15 * Df)

        gu = FILM_SPAN / Double(G)
        let GG = G * G
        flowX = [Float](repeating: 0, count: GG); flowY = flowX; tiltG = flowX
        nXg = flowX; nYg = flowX; nZg = flowX; onG = flowX
        pfX = flowX; pfY = flowX; foreG = flowX; hG = flowX; creaseG = flowX; toneG = flowX

        Rl = Rb >> 1
        pl = Double(Rl) / FILM_SPAN
        lock = [Float](repeating: 0, count: Rl * Rl); lockLit = lock
        bump = ValueNoise(scale: 0.7 + 0.35 * kLen, seed: 61)
        swell = ValueNoise(scale: 2.2 + 0.6 * kLen, seed: 67)
        tuftK = (0.2 + 0.5 * fuzz) * min(1.8, kLen)
        lockW = 0.8 + 0.45 * kLen
        /* a lock's size on the surface — as wide as the clumps gather it,
           about three times as long as wide — and how high it stands */
        lockWd = lockW * (0.65 + 0.4 * clumps)
        lockLd = 1.5 + 1.6 * kLen
        hMax = 0.32 * lockWd * (0.15 + 0.85 * clumps)
        pileH = [Float](repeating: Float(-0.25 * hMax), count: Rb * Rb)
        own = [Int32](repeating: -1, count: Rb * Rb)
        cell = ((0.6 * lockWd * lockLd) / LOCK_COVER / LOCK_DENSE).squareRoot()
        gn = Int((FILM_SPAN / cell).rounded(.up))
        locks = [Float](repeating: 0, count: gn * gn * 16)
        /* a hanging pile lies flatter */
        stand0 = 0.45 - 0.2 * gravity
        tuftN = ValueNoise3(scale: 1.6 * lockLd, seed: 79)
        sizeN = ValueNoise(scale: 9, seed: 73)
        tuftH = 1.5 * hMax * (0.25 + clumps)
        pileB = [Float](repeating: 0, count: Rb * Rb)
        rB = max(1, Int(jsRound(0.3 * lockWd * px)))

        dark = FabricBitmap(Rb); light = FabricBitmap(Rb); glint = FabricBitmap(Rb); back = FabricBitmap(Rb); soft = FabricBitmap(Rb)
        maskBmp = FabricBitmap(R)
        white = [Float](repeating: 0, count: Rb * Rb)
        strandHalf = max(1, Int(jsRound((0.35 + 0.4 * kLen) * px)))
        strandMean = [Float](repeating: 0, count: 2 * strandHalf + 1)
        strandSd = strandMean
        strandK = 0.12 * (R >= 512 ? 1 : R >= 320 ? 0.75 : 0.4) * min(1.4, 0.55 + 0.35 * kDen)
        let reachSh = max(1, 1.5 * lockWd * px)
        NSH = max(1, min(5, Int(jsRound(reachSh))))
        shX = [Int](repeating: 0, count: NSH); shY = shX; shD = [Float](repeating: 0, count: NSH)
        difLut = furPowLut(1.35); gamLut = furPowLut(1 / 2.2)
        depthK = R >= 512 ? 1 : R >= 320 ? 0.8 : 0.55
        strandBuf = [Float](repeating: 0, count: Rb * Rb)

        fine = R >= 512 ? 1 : R >= 320 ? 0.45 : 0
        fringeBack = (0..<GLINTS).map { _ in CGMutablePath() }
        tuftTips = (0..<3).map { _ in CGMutablePath() }
        tuftBack = (0..<GLINTS).map { _ in CGMutablePath() }

        for t in 0..<NSH {
            let d = (Double(t + 1) / Double(NSH)) * reachSh
            shX[t] = Int(jsRound(Lx * d))
            shY[t] = Int(jsRound(Ly * d))
            shD[t] = Float((Double(shX[t] * shX[t] + shY[t] * shY[t])).squareRoot() / px)
        }
        /* the parting: over the top of the head, behind it — seen from the
           front the pile comes over the top and falls, with no parting line */
        var y = -PAD
        while y < 60 {
            if sdAt(50, y) > 0.5 { crownY = y + 1; break }
            y += 0.5
        }
        crownY -= 18
    }

    /// Bake every step, in the web's order, and return the pile.
    func run() -> Fur {
        flowGrid()
        crease()
        seedLocks()
        splatLocks()
        hollows()
        whiteNoise()
        strandKernels()
        strands()
        fleece()
        normaliseLock()
        hairs()
        fuzzAndTufts()
        halo()
        fur.dark = dark.image(); fur.light = light.image(); fur.glint = glint.image(); fur.back = back.image(); fur.backSoft = soft.image()
        return fur
    }

    /* ── reading the form ── */

    @inline(__always) func at(_ f: [Float], _ x: Double, _ y: Double) -> Double {
        bilerp(f, N, ((x + PAD) / SPAN) * Double(N) - 0.5, ((y + PAD) / SPAN) * Double(N) - 0.5)
    }
    @inline(__always) func sdAt(_ x: Double, _ y: Double) -> Double { at(form.sd, x, y) }
    @inline(__always) func hAt(_ x: Double, _ y: Double) -> Double { at(form.h, x, y) }

    /// the outline's outward direction at a point
    func outward(_ x: Double, _ y: Double) -> (Double, Double) {
        let e = 0.8
        let ox = sdAt(x - e, y) - sdAt(x + e, y), oy = sdAt(x, y - e) - sdAt(x, y + e)
        var ol = (ox * ox + oy * oy).squareRoot()
        if ol == 0 { ol = 1 }
        return (ox / ol, oy / ol)
    }

    /// The flow: away from the parting, and falling; near the edge it turns
    /// out over the outline where the edge faces sideways or down; each tuft
    /// leans its own way, and slow swirls turn whole patches.
    func flow(_ x: Double, _ y: Double) -> (Double, Double) {
        var rx = x - crownX, ry = y - crownY
        var rl = (rx * rx + ry * ry).squareRoot()
        if rl == 0 { rl = 1 }
        rx /= rl
        ry /= rl
        let fall = gravity * (1 - 0.6 * exp(-rl / 8))
        var dx = rx * (1 - 0.8 * fall), dy = ry * (1 - 0.8 * fall) + fall
        let d0 = sdAt(x, y)
        if d0 < 5 {
            let (ox, oy) = outward(x, y)
            let up = max(0, -oy)
            let ex = ox * (1 - gravity * up), ey = oy * (1 - gravity * up) + 1.2 * gravity
            let w = max(0, min(1, 1 - d0 / 5)) * 0.75
            dx = dx * (1 - w) + ex * w * 1.6
            dy = dy * (1 - w) + ey * w * 1.6
        }
        let a = (lean(x, y) - 0.5) * (0.5 + 1.6 * curl) + (swirl(x, y) - 0.5) * (0.6 + curl)
        let ca = cos(a), sa = sin(a)
        let qx = dx * ca - dy * sa, qy = dx * sa + dy * ca
        var m = (qx * qx + qy * qy).squareRoot()
        if m == 0 { m = 1 }
        return (qx / m, qy / m)
    }

    /// the body's surface slope at a point: downhill, and how steep (0 facing the viewer … toward 1 at the outline)
    func slopeAt(_ x: Double, _ y: Double) -> (Double, Double, Double) {
        let e = 0.6
        let gx = (hAt(x + e, y) - hAt(x - e, y)) / (2 * e), gy = (hAt(x, y + e) - hAt(x, y - e)) / (2 * e)
        let m = (gx * gx + gy * gy).squareRoot()
        return (m > 1e-6 ? -gx / m : 0, m > 1e-6 ? -gy / m : 0, m / (1 + m * m).squareRoot())
    }

    @inline(__always) func gridAt(_ f: [Float], _ X: Double, _ Y: Double) -> Double {
        bilerp(f, G, (X + O) / gu - 0.5, (Y + O) / gu - 0.5)
    }
    /// the projected flow's unit direction at a design point: how the strands are seen lying on the body
    func dirAt(_ X: Double, _ Y: Double) -> (Double, Double) {
        let ux = gridAt(pfX, X, Y), uy = gridAt(pfY, X, Y)
        let ul = (ux * ux + uy * uy).squareRoot()
        return ul > 1e-4 ? (ux / ul, uy / ul) : (0, 1)
    }
    /// the plain flow's, for the locks and the hairs standing free past the edge
    func freeDirAt(_ X: Double, _ Y: Double) -> (Double, Double) {
        let ux = gridAt(flowX, X, Y), uy = gridAt(flowY, X, Y)
        let ul = (ux * ux + uy * uy).squareRoot()
        return ul > 1e-4 ? (ux / ul, uy / ul) : (0, 1)
    }
    @inline(__always) func lockAt(_ f: [Float], _ X: Double, _ Y: Double) -> Double {
        bilerp(f, Rl, (X + O) * pl - 0.5, (Y + O) * pl - 0.5)
    }
    /// how far past (or short of) the outline the silhouette's tufts reach here
    func tuftAt(_ X: Double, _ Y: Double) -> Double {
        let v = 0.3 * max(-1.6, min(1.6, lockAt(lock, X, Y))) / 1.6 + 0.25 * (bump(X, Y) - 0.5) * 2.4 + 0.45 * (swell(X, Y) - 0.5) * 2.4
        return tuftK * max(-1, min(1, v))
    }

    /* ── 1. the flow ── */

    /// The flow on a coarse grid, with the surface's normal, how far the
    /// halo's hairs reach, the projected flow and how much of a fibre shows,
    /// the body's height and the slow drift in the pile's tone.
    func flowGrid() {
        var i = 0
        for j in 0..<G {
            for x in 0..<G {
                let X = (Double(x) + 0.5) * gu - O, Y = (Double(j) + 0.5) * gu - O
                var (fx, fy) = flow(X, Y)
                let (dx, dy, tiltS) = slopeAt(X, Y)
                /* a hanging pile lies down its slope only as far as gravity lets it */
                let w = tiltS * (0.25 + 0.5 * (1 - gravity)) * (1 - gravity * max(0, -dy))
                fx = fx * (1 - w) + dx * w
                fy = fy * (1 - w) + (dy + 0.35 * gravity) * w
                var fl = (fx * fx + fy * fy).squareRoot()
                if fl == 0 { fl = 1 }
                fx /= fl
                fy /= fl
                flowX[i] = Float(fx)
                flowY[i] = Float(fy)
                tiltG[i] = Float(tiltS)
                var nx = dx * tiltS, ny = dy * tiltS, nz = max(0, 1 - tiltS * tiltS).squareRoot()
                let d0 = sdAt(X, Y)
                if d0 < 2 {
                    let (ox, oy) = outward(X, Y)
                    let w = d0 >= 0 ? 0.7 * (1 - d0 / 2) : min(1, 0.7 - 0.2 * d0)
                    nx += w * (ox - nx)
                    ny += w * (oy - ny)
                    nz -= w * nz
                    var nl = (nx * nx + ny * ny + nz * nz).squareRoot()
                    if nl == 0 { nl = 1 }
                    nx /= nl
                    ny /= nl
                    nz /= nl
                }
                nXg[i] = Float(nx)
                nYg[i] = Float(ny)
                nZg[i] = Float(nz)
                onG[i] = Float(smooth(-3.5, -1.5, d0))
                toneG[i] = Float(tone(X, Y))
                hG[i] = Float(d0 > 0 ? hAt(X, Y) : 0)
                /* the flow as a direction on the surface, foreshortened by the
                   surface's cosine, then raised out of it at the pile's angle */
                let s = (nx * nx + ny * ny).squareRoot(), gx = s > 1e-4 ? nx / s : 0, gy = s > 1e-4 ? ny / s : 0
                let a = fx * gx + fy * gy, k = (1 - max(0, nz)) * a
                var qx = PILE_COS * (fx - k * gx) + PILE_SIN * s * gx, qy = PILE_COS * (fy - k * gy) + PILE_SIN * s * gy
                /* past the outline the halo's hairs stand free, seen whole */
                let att = smooth(-0.5, 1.5, d0)
                qx = fx + (qx - fx) * att
                qy = fy + (qy - fy) * att
                var ql = (qx * qx + qy * qy).squareRoot()
                if ql == 0 { ql = 1 }
                pfX[i] = Float(qx / ql)
                pfY[i] = Float(qy / ql)
                foreG[i] = Float(1 + (min(1, ql) - 1) * att)
                i += 1
            }
        }
    }

    /// The crease: the body's height under a wide average of it (a valley
    /// between lobes), and the underside, by how far it faces the floor.
    func crease() {
        var tmp = [Float](repeating: 0, count: G * G), avg = hG
        for _ in 0..<3 {
            var i = 0
            for y in 0..<G {
                for x in 0..<G {
                    var acc: Double = 0
                    for t in -2...2 { acc += Double(avg[y * G + min(G - 1, max(0, x + t))]) }
                    tmp[i] = Float(acc / 5)
                    i += 1
                }
            }
            i = 0
            for y in 0..<G {
                for x in 0..<G {
                    var acc: Double = 0
                    for t in -2...2 { acc += Double(tmp[min(G - 1, max(0, y + t)) * G + x]) }
                    avg[i] = Float(acc / 5)
                    i += 1
                }
            }
        }
        var i = 0
        for j in 0..<G {
            for x in 0..<G {
                /* only on the body: past the outline every edge would read as a valley */
                let inside = smooth(0.2, 2, sdAt((Double(x) + 0.5) * gu - O, (Double(j) + 0.5) * gu - O))
                let valley = smooth(0.3, 3.5, Double(avg[i] - hG[i])) * inside
                let under = smooth(0.15, 0.85, Double(nYg[i])) * (1 - Double(nZg[i]))
                creaseG[i] = Float(min(1, valley + 0.45 * under) * Double(onG[i]))
                i += 1
            }
        }
    }

    /* ── 2. the locks ── */

    /// The locks, seeded on a jittered grid at LOCK_DENSE times the density
    /// a surface seen face-on needs, and kept as far as the surface is
    /// foreshortened there; fewer between the tufts than in them.
    func seedLocks() {
        for gy in 0..<gn {
            for gx in 0..<gn {
                let X = (Double(gx) + rand.next()) * cell - O, Y = (Double(gy) + rand.next()) * cell - O
                let r1 = rand.next(), r2 = rand.next(), r3 = rand.next(), r4 = rand.next(), r5 = rand.next(), r6 = rand.next(), r7 = rand.next()
                var nx = gridAt(nXg, X, Y), ny = gridAt(nYg, X, Y), nz = gridAt(nZg, X, Y)
                var nl = (nx * nx + ny * ny + nz * nz).squareRoot()
                if nl == 0 { nl = 1 }
                nx /= nl
                ny /= nl
                nz /= nl
                let (fx, fy) = freeDirAt(X, Y)
                let ja = (r1 - 0.5) * (0.2 + 0.45 * curl), cj = cos(ja), sj = sin(ja)
                let ux = fx * cj - fy * sj, uy = fx * sj + fy * cj
                /* the flow laid onto the surface; where it runs straight out
                   over the silhouette the lock runs on round the side */
                let a = ux * nx + uy * ny
                var tx = ux - a * nx, ty = uy - a * ny, tz = -a * nz
                var tl = (tx * tx + ty * ty + tz * tz).squareRoot()
                if tl < 0.05 {
                    tx = nz * nx
                    ty = nz * ny
                    tz = nz * nz - 1
                    tl = (tx * tx + ty * ty + tz * tz).squareRoot()
                    if tl == 0 { tl = 1 }
                }
                tx /= tl
                ty /= tl
                tz /= tl
                /* across it, on the surface */
                var bx = ny * tz - nz * ty, by = nz * tx - nx * tz, bz = nx * ty - ny * tx
                /* the lock stands a little out of the surface from its root */
                let st = stand0 + 0.2 * r2, cs = cos(st), sn = sin(st)
                let grow = 0.8 + 0.45 * sizeN(X, Y)
                let Wd = lockWd * grow * (0.8 + 0.4 * r3), Ld = lockLd * grow * (0.75 + 0.5 * r4)
                var ax = (tx * cs + nx * sn) * Ld * px, ay = (ty * cs + ny * sn) * Ld * px
                var La = (ax * ax + ay * ay).squareRoot()
                if La < 1.5 {
                    ax = ux
                    ay = uy
                    La = 1.5
                } else {
                    ax /= La
                    ay /= La
                }
                /* its width on screen, across its axis there */
                var across = -bx * ay + by * ax
                if across < 0 {
                    bx = -bx
                    by = -by
                    bz = -bz
                    across = -across
                }
                let Wa = max(0.6, 0.5 * Wd * px * max(0.15, across))
                /* as many locks on each piece of the surface wherever it is */
                let seenK = (La / (Ld * px)) * (Wa / (0.5 * Wd * px))
                let tn = tuftN(X, Y, hAt(X, Y))
                if r5 > (LOCK_DENSE / max(LOCK_DENSE, seenK)) * (1 - LOCK_PART * clumps * (1 - smooth(0.25, 0.65, tn))) { continue }
                let b = nLocks * LP
                nLocks += 1
                locks[b] = Float((X + O) * px)
                locks[b + 1] = Float((Y + O) * px)
                locks[b + 2] = Float(ax)
                locks[b + 3] = Float(ay)
                locks[b + 4] = Float(La)
                locks[b + 5] = Float(Wa)
                locks[b + 6] = Float(0.1 * hMax * r6 + tuftH * tn)
                locks[b + 7] = Float((r7 - 0.5) * 1.2 * curl)
                locks[b + 8] = Float(tx)
                locks[b + 9] = Float(ty)
                locks[b + 10] = Float(tz)
                locks[b + 11] = Float(bx)
                locks[b + 12] = Float(by)
                locks[b + 13] = Float(bz)
                locks[b + 14] = Float(Ld)
                locks[b + 15] = Float(Wd)
            }
        }
    }

    /// along a lock (s, root 0 to tip 1): rising over its first quarter,
    /// sinking to half its height at the tip
    @inline(__always) func lockAlong(_ s: Double) -> Double { (s < 0.25 ? 4 * s : 1) * (1 - 0.5 * s) }

    /// Each lock into the height field, rounded across, tapering to a point,
    /// bending a little as the pile curls; the highest lock at a point is the one seen.
    func splatLocks() {
        for k in 0..<nLocks {
            let b = k * LP
            let ox = Double(locks[b]), oy = Double(locks[b + 1]), ax = Double(locks[b + 2]), ay = Double(locks[b + 3])
            let La = Double(locks[b + 4]), Wa = Double(locks[b + 5]), z0 = Double(locks[b + 6]), bend = Double(locks[b + 7])
            let ext = Wa * (1 + abs(bend)) + 1, ex = ox + ax * La, ey = oy + ay * La
            let xa = max(0, Int(floor(min(ox, ex) - ext))), xb = min(Rb - 1, Int((max(ox, ex) + ext).rounded(.up)))
            let ya = max(0, Int(floor(min(oy, ey) - ext))), yb = min(Rb - 1, Int((max(oy, ey) + ext).rounded(.up)))
            if xa > xb || ya > yb { continue }
            let iLa = 1 / La, iWa = 1 / Wa
            for y in ya...yb {
                let dy = Double(y) + 0.5 - oy
                var i = y * Rb + xa
                for x in xa...xb {
                    defer { i += 1 }
                    let dx = Double(x) + 0.5 - ox
                    let s = (dx * ax + dy * ay) * iLa
                    if s <= 0 || s >= 1 { continue }
                    let w = LOCK_TAPER * s.squareRoot() * (1 - s)
                    let v = (dy * ax - dx * ay) * iWa - bend * s * s
                    if v >= w || v <= -w { continue }
                    let q = v / w
                    let h = z0 + hMax * lockAlong(s) * (1 - q * q)
                    if h > Double(pileH[i]) {
                        pileH[i] = Float(h)
                        own[i] = Int32(k)
                    }
                }
            }
        }
    }

    /// A box of half-width r along rows (stride 1) or columns (stride Rb),
    /// from src into dst (which may be the same) through one line's copy.
    private func box(_ src: UnsafePointer<Float>, _ dst: UnsafeMutablePointer<Float>, _ r: Int, _ k: Int, _ stride: Int, _ line: UnsafeMutablePointer<Float>) {
        let step = stride == 1 ? Rb : 1
        let inv = 1 / Double(2 * r + 1)
        let o = k * step
        for t in 0..<Rb { line[t] = src[o + t * stride] }
        let last = Rb - 1
        var acc = 0.0
        for t in -r...r { acc += Double(line[t < 0 ? 0 : t > last ? last : t]) }
        for t in 0..<Rb {
            dst[o + t * stride] = Float(acc * inv)
            let a = t + r + 1, b = t - r
            acc += Double(line[a > last ? last : a]) - Double(line[b < 0 ? 0 : b])
        }
    }

    /// The pile's height averaged over about a lock's width (what lies
    /// below it is a hollow: two passes of a box each way, so a lone lock's
    /// hollow is round), and the pile itself softened by a pixel.
    func hollows() {
        var line = [Float](repeating: 0, count: Rb)
        line.withUnsafeMutableBufferPointer { lp in pileH.withUnsafeMutableBufferPointer { hp in pileB.withUnsafeMutableBufferPointer { bp in
            let line = lp.baseAddress!, H = hp.baseAddress!, B = bp.baseAddress!
            for y in 0..<Rb { box(H, B, rB, y, 1, line) }
            for y in 0..<Rb { box(B, B, rB, y, 1, line) }
            for x in 0..<Rb { box(B, B, rB, x, Rb, line) }
            for x in 0..<Rb { box(B, B, rB, x, Rb, line) }
            for y in 0..<Rb { box(H, H, 1, y, 1, line) }
            for x in 0..<Rb { box(H, H, 1, x, Rb, line) }
        } } }
    }
}

/// how many steps of the fibres' own light are bucketed
let GLINTS = 6
