import CoreGraphics
import Foundation
import SwiftUI

/* The front's light round its edge, and fabric's halo: where the turned
   body's silhouette is and in what colour. A port of plastic.ts at
   bfb396b: `raysOf`, `sliceGradient` (the conic ramp), `hazeColor`,
   `brightest`, `stackReach`, `haloStretch`, `haloRays`, `haloMiss` and
   `measureMiss`. Affines are Core Graphics ones: `a.concatenating(b)`
   applies a first, as the canvas's mulAffine(b, a). */

private let PAD = BOT_AVATAR_PAD, SPAN = BOT_AVATAR_SPAN
/// Stops on the conic side gradients.
let FABRIC_CONIC_STOPS = 24
/* how far in on the front the halo's colour comes from at least, in
   design units: past the edge's shade, as a pile lit through */
let HALO_INSET = 3.0
/* how much of the far half's shade the halo keeps where that half forms the silhouette */
let HALO_SHADE = 0.5
/* how far the halo's stretched outline may miss the turned stack's
   silhouette, in design units, before it is cut into the body instead */
let HALO_FIT = 2.5
/* how much of the halo's colour is laid over the body's own edge */
let HALO_VEIL = 0.8
/* over how much of the recession the halo laid over the body is
   cross-faded into the cut, and how far that weight moves in a frame */
let HALO_BLEND = 0.3
let HALO_EASE = 0.1

/// The front's colour along 24 rays out from the centre, sampled every
/// half unit with how far each sample is from the outline.
struct FabricRays {
    /** per ray: the samples' distance in from the outline, and their colours (rgb, 0–255) */
    var d: [[Double]]
    var c: [[Double]]
}

func raysOf(_ img: [UInt8], _ form: FabricForm, _ c0: (Double, Double)) -> FabricRays {
    let N = form.N
    func toG(_ v: Double) -> Double { ((v + PAD) / SPAN) * Double(N) - 0.5 }
    var dOut: [[Double]] = [], cOut: [[Double]] = []
    form.sd.withUnsafeBufferPointer { sdp in
        let sd = sdp.baseAddress!
        for s in 0..<FABRIC_CONIC_STOPS {
            let phi = (Double(s) / Double(FABRIC_CONIC_STOPS)) * Double.pi * 2, ux = cos(phi), uy = sin(phi)
            var ds: [Double] = [], cs: [Double] = []
            var r = 0.0
            while r < 80 {
                defer { r += 0.5 }
                let x = c0.0 + ux * r, y = c0.1 + uy * r
                let d = bilerp(sd, N, toG(x), toG(y))
                if d < 0 { break }
                let gx = Int(jsRound(toG(x))), gy = Int(jsRound(toG(y)))
                if gx < 0 || gy < 0 || gx >= N || gy >= N { break }
                let k = (gy * N + gx) * 4
                ds.append(d)
                cs.append(Double(img[k])); cs.append(Double(img[k + 1])); cs.append(Double(img[k + 2]))
            }
            dOut.append(ds)
            cOut.append(cs)
        }
    }
    return FabricRays(d: dOut, c: cOut)
}

/// One slice's side light: every ray's colour at `inset` from the outline,
/// darkened by `dark`, as a conic ramp round the centre.
func sliceGradient(_ rays: FabricRays, inset: (Int) -> Double, dark: (Int) -> Double, _ c0: (Double, Double)) -> GraphicsContext.Shading {
    func at(_ s: Int) -> Color {
        let d = rays.d[s], c = rays.c[s]
        let ins = inset(s), k = 1 - dark(s)
        /* the samples run from the centre out: the last one at least `inset` in */
        var j = 0
        for i in 0..<d.count where d[i] >= ins { j = i }
        if c.isEmpty { return Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1) }
        return Color(.sRGB, red: floor(c[j * 3] * k) / 255, green: floor(c[j * 3 + 1] * k) / 255, blue: floor(c[j * 3 + 2] * k) / 255, opacity: 1)
    }
    var stops: [Gradient.Stop] = []
    stops.reserveCapacity(FABRIC_CONIC_STOPS + 1)
    for s in 0...FABRIC_CONIC_STOPS { stops.append(Gradient.Stop(color: at(s % FABRIC_CONIC_STOPS), location: Double(s) / Double(FABRIC_CONIC_STOPS))) }
    return .conicGradient(Gradient(stops: stops), center: CGPoint(x: c0.0, y: c0.1), angle: .zero)
}

/// The halo's lit tips: the front's brightest colour, toward the back
/// light's own through the dyed fibres as far as `rim` says.
func hazeColor(_ rays: FabricRays, _ base: BotColor, _ rim: Double, _ vivid: Double = 0) -> Color {
    let b = brightest(rays)
    let lin = base.linear
    let e = [srgb(lin[0]), srgb(lin[1]), srgb(lin[2])]
    let mx = max(e[0], e[1], e[2], 1)
    let k = min(0.85, 0.75 * rim)
    let pale = 0.45 + 0.55 * min(1, vivid)
    func q(_ i: Int) -> Double { jsRound(b[i] + (255 + ((255 * e[i]) / mx - 255) * pale - b[i]) * k) }
    return Color(.sRGB, red: q(0) / 255, green: q(1) / 255, blue: q(2) / 255, opacity: 1)
}

/// The front's brightest colour, in steps of four.
private func brightest(_ rays: FabricRays) -> [Double] {
    var best = -1.0, r = 0.0, g = 0.0, b = 0.0
    for c in rays.c {
        for i in stride(from: 0, to: c.count, by: 3) {
            let l = 0.2126 * c[i] + 0.7152 * c[i + 1] + 0.0722 * c[i + 2]
            if l > best { best = l; r = c[i]; g = c[i + 1]; b = c[i + 2] }
        }
    }
    func q(_ v: Double) -> Double { min(255, jsRound(v / 4) * 4) }
    return [q(r), q(g), q(b)]
}

/* ── the halo's fit ────────────────────────────────────────────────── */

/// The stack's reach along v given the outline's (h): the furthest of the
/// slices of either half that way, and which one (k, far).
func stackReach(_ rel: FabricRelief, _ K: Int, _ ex: Double, _ ey: Double, _ dl1: Double, _ vx: Double, _ vy: Double, _ h: Double) -> (Double, Int, Bool) {
    let v0 = vx * rel.cx[0] + vy * rel.cy[0], ve = (vx * ex + vy * ey) * dl1
    var best = h, kb = 0, far = false
    for k in 1..<K {
        let r = vx * rel.cx[k] + vy * rel.cy[k] + rel.scale[k] * (h - v0)
        if r + rel.z[k] * ve > best { best = r + rel.z[k] * ve; kb = k; far = false }
        if r - rel.z[k] * ve > best { best = r - rel.z[k] * ve; kb = k; far = true }
    }
    return (best, kb, far)
}

/// The stretch, in design units: along the turn e by 1 + s1, shifted, so
/// the outline spans the stack's reach both ways (face-on, none).
func haloStretch(_ form: FabricForm, _ rel: FabricRelief, _ K: Int, _ ex: Double, _ ey: Double, _ dl1: Double) -> CGAffineTransform {
    if dl1 <= 1e-4 { return .identity }
    let rim = form.rim
    let hp = reach(rim, ex, ey), hn = reach(rim, -ex, -ey)
    let up = stackReach(rel, K, ex, ey, dl1, ex, ey, hp).0, un = stackReach(rel, K, ex, ey, dl1, -ex, -ey, hn).0
    let s1 = (up + un) / max(1, hp + hn) - 1, t = up - (s1 + 1) * hp
    return CGAffineTransform(a: 1 + s1 * ex * ex, b: s1 * ex * ey, c: s1 * ex * ey, d: 1 + s1 * ey * ey, tx: ex * t, ty: ey * t)
}

/// The halo's colour along each ray: the inset and shade of the slice
/// forming the stack's silhouette where the stretched outline's ray lands.
func haloRays(_ form: FabricForm, _ rel: FabricRelief, _ K: Int, _ ex: Double, _ ey: Double, _ dl1: Double, _ S: CGAffineTransform, _ backShade: Double) -> (inset: [Double], dark: [Double]) {
    let rim = form.rim
    var inset = [Double](repeating: 0, count: FABRIC_CONIC_STOPS), dark = inset
    let s1 = Double(S.a + S.d) - 2
    for s in 0..<FABRIC_CONIC_STOPS {
        let phi = (Double(s) / Double(FABRIC_CONIC_STOPS)) * Double.pi * 2, ux = cos(phi), uy = sin(phi)
        /* the direction the stretched outline faces where this ray lands */
        let ue = ux * ex + uy * ey, q = s1 / (1 + s1)
        var vx = ux - q * ue * ex, vy = uy - q * ue * ey
        let vl = (vx * vx + vy * vy).squareRoot()
        vx /= vl
        vy /= vl
        let (_, k, far) = stackReach(rel, K, ex, ey, dl1, vx, vy, reach(rim, vx, vy))
        /* never from the front's outermost units, which are in the edge's shade */
        inset[s] = max(HALO_INSET, rel.inset[k])
        /* the hairs past the far half's edge keep only a little of its shade */
        dark[s] = far ? HALO_SHADE * backShade * (1 - exp(-2.4 * (Double(k) / Double(K)))) : 0
    }
    return (inset, dark)
}

/* How far the stretched outline misses the stack's silhouette, in design
   units — cutting into it (the stack reaching past it) or overhanging it:
   measured on a coarse grid with the stretch undone, once per form and
   turn in steps of MISS_STEP. */
let MISS_N = 96, MISS_STEP = 0.1

/// The measure, or nil while it is made on the bake queue (unless `sync`).
func haloMiss(_ form: FabricForm, _ path: CGPath, _ rel: FabricRelief, _ K: Int, _ S: CGAffineTransform, _ dxs: Double, _ dys: Double, sync: Bool) -> (Double, Double)? {
    let key = "\(K)|\(rel.q)|\(Int(jsRound(dxs / MISS_STEP)))|\(Int(jsRound(dys / MISS_STEP)))"
    if let hit = form.misses[key] {
        if let m = hit { return m }
        if !sync { return nil }
    }
    if form.misses.count > 256 { form.misses.removeAll() }
    if !sync {
        form.misses[key] = .some(nil)
        FabricBakes.onQueue {
            let m = measureMiss(form, path, rel, K, S, dxs, dys)
            DispatchQueue.main.async { form.misses[key] = m }
        }
        return nil
    }
    let r = measureMiss(form, path, rel, K, S, dxs, dys)
    form.misses[key] = r
    return r
}

/// The stack's slices with the stretch undone, rasterised at MISS_N; the
/// stack's cells outside the outline (cut) and the outline's away from the
/// stack (over), the furthest of each.
func measureMiss(_ form: FabricForm, _ path: CGPath, _ rel: FabricRelief, _ K: Int, _ S: CGAffineTransform, _ dxs: Double, _ dys: Double) -> (Double, Double) {
    let n = MISS_N
    guard let g = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return (0, 0) }
    let u = SPAN / Double(n)
    /* y down, as a canvas: row 0 of the bitmap is the top */
    g.translateBy(x: 0, y: CGFloat(n))
    g.scaleBy(x: 1, y: -1)
    g.setFillColor(gray: 1, alpha: 1)
    let base = CGAffineTransform(a: 1 / u, b: 0, c: 0, d: 1 / u, tx: PAD / u, ty: PAD / u)
    let undo = S.inverted()
    for k in 0..<K {
        for z in (k > 0 ? [rel.z[k], -rel.z[k]] : [0]) {
            let sk = rel.scale[k]
            var t = CGAffineTransform(translationX: z * dxs, y: z * dys).concatenating(undo).concatenating(base)
            if k > 0 { t = CGAffineTransform(a: sk, b: 0, c: 0, d: sk, tx: rel.cx[k] - sk * rel.cx[0], ty: rel.cy[k] - sk * rel.cy[0]).concatenating(t) }
            g.saveGState()
            g.concatenate(t)
            g.addPath(path)
            g.fillPath()
            g.restoreGState()
        }
    }
    guard let data = g.data?.bindMemory(to: UInt8.self, capacity: n * n) else { return (0, 0) }
    var on = [UInt8](repeating: 0, count: n * n), dist = [Float](repeating: 0, count: n * n)
    for i in 0..<(n * n) { on[i] = data[i] > 127 ? 1 : 0 }
    var none: [Int32] = []
    edt2d(on, 1, n, &dist, &none, wantNear: false)
    var cut = 0.0, over = 0.0
    form.sd.withUnsafeBufferPointer { sdp in
        let sd = sdp.baseAddress!
        var i = 0
        for y in 0..<n {
            for x in 0..<n {
                let d = bilerp(sd, form.N, ((Double(x) + 0.5) / Double(n)) * Double(form.N) - 0.5, ((Double(y) + 0.5) / Double(n)) * Double(form.N) - 0.5)
                if on[i] != 0 && d < 0 { cut = max(cut, -d) }
                if on[i] == 0 && d > 0 { over = max(over, Double(dist[i]).squareRoot() * u) }
                i += 1
            }
        }
    }
    return (cut, over)
}
