import CoreGraphics
import Foundation

/* Fabric's body: the inflated form the pile is laid on, and what is
   measured on it. A port of plastic.ts at bfb396b — `buildForm` (the web's
   current form: a taller pillow than this package's plastic one, and a
   halo of borrowed texels reaching out to the fringe), the relief's
   levels (`reliefFor`), the edge lift (`edgeLift`), the soft mask
   (`softMask`) and the rim (`rimOf`, `ringOf`, `reach`). Plastic keeps its
   own form (BotAvatarPlastic.swift); the two share the distance
   transform, the blur and the Poisson solve. */

private let PAD = BOT_AVATAR_PAD, SPAN = BOT_AVATAR_SPAN
private let M = MATCAP_M
private let INF = 1e12

/// The form of one outline at one texture size, as fabric wears it, and
/// what is measured on it once (the web keeps those in WeakMaps on it).
/// Built on the bake queue; read and its caches filled on the main thread.
final class FabricForm {
    let N: Int
    /** bilinear cell in the matcap: index of the top-left cell, and the weights inside it, 0–255 */
    let i00: [UInt16]
    let wx: [UInt8]
    let wy: [UInt8]
    /** baked occlusion × edge darkening, gamma-compensated, 0–255; 0 = not drawn */
    let ao: [UInt8]
    /** signed distance to the outline in design units (positive inside),
        and the pillow height: the fibres grow down its slope and out past the edge */
    let sd: [Float]
    let h: [Float]

    init(N: Int, i00: [UInt16], wx: [UInt8], wy: [UInt8], ao: [UInt8], sd: [Float], h: [Float]) {
        self.N = N; self.i00 = i00; self.wx = wx; self.wy = wy; self.ao = ao; self.sd = sd; self.h = h
    }

    /* the caches: main thread only (the draw runs there; the bake queue
       reads only the fields above, which never change) */
    var reliefs: [String: FabricRelief] = [:]
    lazy var lift: FabricLift = edgeLift(self)
    var softMasks: [Int: CGImage] = [:]
    lazy var rim: [Double] = rimOf(self)
    lazy var ring: FabricRing = ringOf(self)
    var misses: [String: (Double, Double)?] = [:]
}

/// The form of one outline from its coverage raster (N × N, 0–255, over
/// design units [-PAD, 100 + PAD]): a pillow height field, its normals as
/// matcap cells, and baked occlusion; outside texels within 8 texels of the
/// edge borrow their nearest inside texel, as far as fabric's fringe reaches.
func buildFabricForm(_ cov: [UInt8], N: Int, halfDepth: Double) -> FabricForm {
    let u = Float(SPAN) / Float(N), NN = N * N
    var mask = [UInt8](repeating: 0, count: NN)
    for i in 0..<NN { mask[i] = cov[i] >= 128 ? 1 : 0 }

    /* signed distance to the outline, in design units, positive inside */
    var dIn = [Float](repeating: 0, count: NN), dOut = [Float](repeating: 0, count: NN), nearIn = [Int32](repeating: 0, count: NN)
    var none: [Int32] = []
    edt2d(mask, 0, N, &dIn, &none, wantNear: false)
    edt2d(mask, 1, N, &dOut, &nearIn, wantNear: true)
    var sd = [Float](repeating: 0, count: NN), tmp = [Float](repeating: 0, count: NN)
    for i in 0..<NN {
        let a = Float(cov[i]) / 255
        sd[i] = u * (a > 0 && a < 1 ? a - 0.5 : mask[i] != 0 ? dIn[i].squareRoot() - 0.5 : 0.5 - dOut[i].squareRoot())
    }
    /* round the medial-axis crease into a ridge (σ ≈ 2.2 texels) */
    blur5(&sd, N, &tmp)
    blur5(&sd, N, &tmp)

    /* the pillow: the torsion function; a toy is puffed up well past its
       own thickness, the height growing with the depth asked for and with
       how wide the shape is inside */
    let phi = poisson(cov, N, u)
    var phiMax: Float = 0
    for i in 0..<NN where phi[i] > phiMax { phiMax = phi[i] }
    let rIn = 2 * phiMax.squareRoot()
    let hMax = min(1.5 * Float(halfDepth) + 0.32 * rIn, 1.4 * rIn)
    let kh = phiMax > 0 ? hMax / phiMax.squareRoot() : 0
    var h = [Float](repeating: 0, count: NN)
    for i in 0..<NN { h[i] = phi[i] > 0 ? kh * phi[i].squareRoot() : 0 }
    blur5(&h, N, &tmp)

    /* normals, silhouette fix, horizon AO, matcap cells */
    var i00 = [UInt16](repeating: 0, count: NN), wx = [UInt8](repeating: 0, count: NN), wy = [UInt8](repeating: 0, count: NN), ao = [UInt8](repeating: 0, count: NN)
    let STEPS: [Int] = N <= 64 ? [1, 2, 3, 5, 8] : N <= 96 ? [1, 2, 4, 7, 11] : [1, 2, 4, 7, 11, 15]
    let halo: Float = 64
    let last = N - 1
    for y in 0..<N {
        for x in 0..<N {
            let i = y * N + x
            let src = mask[i] != 0 ? i : dOut[i] <= halo ? Int(nearIn[i]) : -1
            if src < 0 { continue }
            let sx = src % N, sy = (src - sx) / N
            let xl = sx > 0 ? sx - 1 : 0, xr = sx < last ? sx + 1 : last, yu = sy > 0 ? sy - 1 : 0, yd = sy < last ? sy + 1 : last
            var nx = -(h[sy * N + xr] - h[sy * N + xl]) / (2 * u)
            var ny = -(h[yd * N + sx] - h[yu * N + sx]) / (2 * u)
            var nz: Float = 1
            var len = (nx * nx + ny * ny + 1).squareRoot()
            nx /= len; ny /= len; nz /= len
            let dd = max(0, sd[src])
            if dd < 2 {
                /* toward the in-plane outward direction, so the silhouette grazes */
                var gx = sd[sy * N + xr] - sd[sy * N + xl], gy = sd[yd * N + sx] - sd[yu * N + sx]
                var gl = (gx * gx + gy * gy).squareRoot()
                if gl == 0 { gl = 1 }
                gx /= gl; gy /= gl
                let w = 0.7 * (1 - dd / 2)
                nx += w * (-gx - nx); ny += w * (-gy - ny); nz += w * (0 - nz)
                len = (nx * nx + ny * ny + nz * nz).squareRoot()
                if len == 0 { len = 1 }
                nx /= len; ny /= len; nz /= len
            }
            /* horizon-based occlusion on the height field */
            let h0 = h[src]
            var occ: Float = 0
            for d in 0..<8 {
                var m: Float = 0
                for r in STEPS {
                    var qx = sx + DX[d] * r, qy = sy + DY[d] * r
                    if qx < 0 { qx = 0 } else if qx > last { qx = last }
                    if qy < 0 { qy = 0 } else if qy > last { qy = last }
                    let t = (h[qy * N + qx] - h0) / (Float(r) * u * DL[d])
                    if t > m { m = t }
                }
                occ += m / (1 + m * m).squareRoot()
            }
            let e = 1 - min(1, dd / 3)
            let edge = 1 - 0.2 * e * e
            let aoLin = pow(1 - 0.9 * occ / 8, 1.5) * edge
            ao[i] = UInt8(max(1, (255 * pow(aoLin, 1 / 2.2)).rounded()))
            let fx = (nx * 0.5 + 0.5) * Float(M - 1), fy = (ny * 0.5 + 0.5) * Float(M - 1)
            let cx = min(M - 2, max(0, Int(fx))), cy = min(M - 2, max(0, Int(fy)))
            i00[i] = UInt16(cy * M + cx)
            wx[i] = UInt8((255 * min(1, max(0, fx - Float(cx)))).rounded())
            wy[i] = UInt8((255 * min(1, max(0, fy - Float(cy)))).rounded())
        }
    }
    return FabricForm(N: N, i00: i00, wx: wx, wy: wy, ao: ao, sd: sd, h: h)
}

/// A field on the form's grid read at any point, bilinear.
@inline(__always) func bilerp(_ f: UnsafePointer<Float>, _ N: Int, _ x: Double, _ y: Double) -> Double {
    let last = N - 1
    let fx = min(Double(last), max(0, x)), fy = min(Double(last), max(0, y))
    let x0 = min(last - 1, Int(fx)), y0 = min(last - 1, Int(fy))
    let tx = fx - Double(x0), ty = fy - Double(y0), i = y0 * N + x0
    return (Double(f[i]) * (1 - tx) + Double(f[i + 1]) * tx) * (1 - ty) + (Double(f[i + N]) * (1 - tx) + Double(f[i + N + 1]) * tx) * ty
}
func bilerp(_ f: [Float], _ N: Int, _ x: Double, _ y: Double) -> Double {
    f.withUnsafeBufferPointer { bilerp($0.baseAddress!, N, x, y) }
}

/* ── the profile: an inflated body, not an extruded one ────────────── */

/// The body's slices through its depth follow the height field: at each
/// depth the slice is the outline scaled to the area and centre of where
/// the surface stands at least that high, so the side silhouette is the
/// cushion's own round profile. Measured once per form, count and roundness.
struct FabricRelief {
    /** the surface's highest point, in design units from the centre plane */
    var top: Double
    /** each level's depth from the centre plane; level 0 is the outline itself */
    var z: [Double]
    /** each level's region as the outline scaled about its centre: the
        scale (by area) and the centre it moves to */
    var scale: [Double]
    var cx: [Double]
    var cy: [Double]
    /** how far in from the outline each level's edge lies, in design
        units: where on the front's texture its side's light is */
    var inset: [Double]
    /** the exponent the levels were cut with */
    var q: Double
}

func reliefFor(_ form: FabricForm, _ K: Int, _ round: Double) -> FabricRelief {
    let q = max(0.05, min(1, round))
    let key = "\(K)|\(String(format: "%.2f", q))"
    if let hit = form.reliefs[key] { return hit }
    let N = form.N, h = form.h, sd = form.sd
    var top = 0.0
    for i in 0..<(N * N) where Double(h[i]) > top { top = Double(h[i]) }
    let u = SPAN / Double(N)
    var z = [Double](repeating: 0, count: K)
    var scale = [Double](repeating: 0, count: K), cx = z, cy = z, inset = z
    inset[0] = 1.2
    /* a level's area and centre, in texels */
    func measure(_ inside: (Int) -> Bool) -> (Double, Double, Double) {
        var n = 0.0, sx = 0.0, sy = 0.0
        var i = 0
        for j in 0..<N { for x in 0..<N { if inside(i) { n += 1; sx += Double(x); sy += Double(j) }; i += 1 } }
        return n > 0 ? (n, (sx / n + 0.5) * u - PAD, (sy / n + 0.5) * u - PAD) : (0, 50, 50)
    }
    let (a0, x0, y0) = measure { sd[$0] >= 0 }
    scale[0] = 1
    cx[0] = x0
    cy[0] = y0
    for k in 1..<K {
        let s = Double(k) / Double(K)
        z[k] = top * s
        /* level k holds every point that stands at depth top·s or more */
        let tau = Float(top * pow(s, 1 / q))
        /* inside the outline only, and never larger than the level before */
        let (ak, xk, yk) = measure { sd[$0] >= 0 && h[$0] >= tau }
        scale[k] = min(scale[k - 1], a0 > 0 ? (ak / a0).squareRoot() : 1)
        cx[k] = xk
        cy[k] = yk
        /* the mean distance in from the outline of the texels on the level's edge */
        let band = Float(top / (2 * Double(K)))
        var n = 0, sum = 0.0
        for i in 0..<(N * N) where sd[i] > 0 && abs(h[i] - tau) < band {
            sum += Double(sd[i])
            n += 1
        }
        inset[k] = max(inset[k - 1], n > 0 ? sum / Double(n) : inset[k - 1])
    }
    let r = FabricRelief(top: top, z: z, scale: scale, cx: cx, cy: cy, inset: inset, q: q)
    if form.reliefs.count > 6 { form.reliefs.removeAll() }
    form.reliefs[key] = r
    return r
}

/* ── the edge lift ─────────────────────────────────────────────────── */

/// The form bakes a darkening into its last few units (plastic's rim sinks
/// into shade there), but a pile does the opposite — the fibres at the
/// silhouette are seen side-on and catch the light — so fabric divides
/// that darkening back out.
struct FabricLift {
    /** the baked occlusion with the edge's darkening taken back out */
    var ao: [UInt8]
    /** the sheen band just inside the outline, a gain */
    var k: [Float]
}

func edgeLift(_ form: FabricForm) -> FabricLift {
    let N = form.N
    var l = FabricLift(ao: [UInt8](repeating: 0, count: N * N), k: [Float](repeating: 0, count: N * N))
    for i in 0..<(N * N) {
        if form.ao[i] == 0 { continue }
        let dd = max(0, Double(form.sd[i]))
        let e = 1 - min(1, dd / 3)
        let edge = 1 - 0.2 * e * e
        /* undo the edge factor where it was baked: in the linear occlusion,
           before the material's strength is applied */
        let lin = min(1, pow(Double(form.ao[i]) / 255, 2.2) / edge)
        l.ao[i] = UInt8(max(1, (255 * pow(lin, 1 / 2.2)).rounded()))
        l.k[i] = 1
    }
    return l
}

/* ── the soft mask ─────────────────────────────────────────────────── */

/// The body's outline with a plain soft edge, no fringe, at a pile's
/// resolution (white, premultiplied): fabric's equator slice.
func softMask(_ form: FabricForm, _ R: Int) -> CGImage? {
    if let hit = form.softMasks[R] { return hit }
    let N = form.N
    let px = Double(R) / SPAN
    var a = [UInt8](repeating: 0, count: R * R)
    form.sd.withUnsafeBufferPointer { sdp in
        let sd = sdp.baseAddress!
        for y in 0..<R {
            for x in 0..<R {
                let d = bilerp(sd, N, (((Double(x) + 0.5) / px) / SPAN) * Double(N) - 0.5, (((Double(y) + 0.5) / px) / SPAN) * Double(N) - 0.5)
                let t = (d + 0.2) / 0.6
                a[y * R + x] = t >= 1 ? 255 : t <= 0 ? 0 : UInt8((255 * t * t * (3 - 2 * t)).rounded())
            }
        }
    }
    let img = whiteMaskImage(a, R)
    form.softMasks[R] = img
    return img
}

/// An R × R alpha raster as a white image (premultiplied: every channel the alpha).
func whiteMaskImage(_ a: [UInt8], _ R: Int) -> CGImage? {
    let ctx = FabricBitmap(R)
    guard let p = ctx.pixels else { return nil }
    for i in 0..<(R * R) {
        let v = a[i]
        p[i * 4] = v; p[i * 4 + 1] = v; p[i * 4 + 2] = v; p[i * 4 + 3] = v
    }
    return ctx.image()
}

/* ── the rim ───────────────────────────────────────────────────────── */

/// The outline's rim as points (x, y, distance in), flat: the texels just
/// inside it. A texel p that far inside reaches at least e·p + d along any
/// direction e, and the one nearest the outline there reaches exactly its
/// extent — so how far the outline reaches along a direction is a max
/// over these few hundred points.
func rimOf(_ form: FabricForm) -> [Double] {
    let N = form.N
    let u = SPAN / Double(N)
    var pts: [Double] = []
    var i = 0
    for j in 0..<N {
        for x in 0..<N {
            let d = Double(form.sd[i])
            if d >= 0 && d < 2 * u { pts.append((Double(x) + 0.5) * u - PAD); pts.append((Double(j) + 0.5) * u - PAD); pts.append(d) }
            i += 1
        }
    }
    return pts
}

/// About a hundred of the rim's points, in order round its middle.
struct FabricRing {
    var x: [Double], y: [Double], d: [Double]
}

func ringOf(_ form: FabricForm) -> FabricRing {
    let rim = form.rim
    let n = rim.count / 3
    var mx = 0.0, my = 0.0
    for i in stride(from: 0, to: rim.count, by: 3) { mx += rim[i]; my += rim[i + 1] }
    mx /= n > 0 ? Double(n) : 1
    my /= n > 0 ? Double(n) : 1
    var all: [(Double, Double, Double, Double)] = []
    all.reserveCapacity(n)
    for i in stride(from: 0, to: rim.count, by: 3) { all.append((rim[i], rim[i + 1], atan2(rim[i + 1] - my, rim[i] - mx), rim[i + 2])) }
    /* sorted round first, then thinned, so every side keeps its points;
       a stable sort, as the web's */
    let sorted = all.enumerated().sorted { $0.element.2 != $1.element.2 ? $0.element.2 < $1.element.2 : $0.offset < $1.offset }.map(\.element)
    let step = max(1, sorted.count / 96)
    var r = FabricRing(x: [], y: [], d: [])
    for (i, p) in sorted.enumerated() where i % step == 0 { r.x.append(p.0); r.y.append(p.1); r.d.append(p.3) }
    return r
}

/// The ring's points from the one nearest angle `a` outward, both ways.
@inline(__always) func ringOrder(_ n: Int, _ a: Double, _ k: Int) -> Int {
    let start = Int(jsRound(((a + Double.pi) / (2 * Double.pi)) * Double(n)))
    let off = k & 1 != 0 ? (k + 1) >> 1 : -(k >> 1)
    return (((start + off) % n) + n) % n
}

/// How far the outline reaches along (ex, ey).
func reach(_ rim: [Double], _ ex: Double, _ ey: Double) -> Double {
    var m = -INF
    for i in stride(from: 0, to: rim.count, by: 3) {
        let v = rim[i] * ex + rim[i + 1] * ey + rim[i + 2]
        if v > m { m = v }
    }
    return m
}

/* ── an RGBA bitmap, y down, as a canvas is ────────────────────────── */

/// A square premultiplied sRGB bitmap whose drawing coordinates run y down
/// from the top-left corner, as a canvas's do; its rows are stored top first.
final class FabricBitmap {
    let size: Int
    let ctx: CGContext?
    init(_ size: Int) {
        self.size = size
        ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: fabricSRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        ctx?.translateBy(x: 0, y: CGFloat(size))
        ctx?.scaleBy(x: 1, y: -1)
        ctx?.setLineCap(.round)
        ctx?.setLineJoin(.round)
        ctx?.interpolationQuality = .low
    }
    /// the pixels, RGBA premultiplied, rows top first
    var pixels: UnsafeMutablePointer<UInt8>? { ctx?.data?.bindMemory(to: UInt8.self, capacity: size * size * 4) }
    func image() -> CGImage? { ctx?.makeImage() }
}

let fabricSRGB = CGColorSpace(name: CGColorSpace.sRGB)!

/// Round half up, as JavaScript's Math.round.
@inline(__always) func jsRound(_ v: Double) -> Double { (v + 0.5).rounded(.down) }
