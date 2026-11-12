import CoreGraphics
import Foundation

/* Fabric's light: its two lights, the lit sphere for the pile, the front's
   texels and the films in the body's colour. A port of plastic.ts at
   bfb396b: `fabricKey`, `fabricBack`, `backFromKey`, `stockLights`,
   `capFrame` (with the floor and back-light axes), `buildFabricMatcap`,
   `shadeTexels` (with the lift), `gapFilm`, `tipFilm`, `sheenFilm` and
   `furCut`. */

private let M = MATCAP_M
/// Light elevation off the screen plane (plastic's key, which sets the
/// frame's L: fabric only reads its direction on screen from it).
private let EL = 48.0 * Double.pi / 180
private let E_XY = cos(EL), E_Z = sin(EL)

/* The pile's two lights, in a frame where U is toward the light on screen,
   V toward the viewer and D down on screen. The key comes in lower than
   plastic's, from further round the side, so the far side of the form
   falls into real shade. The back light is behind the toy, above it and
   toward the side away from the key, grazing it: a pile catches it only
   toward the silhouette, and there the fibres carry it through to the
   viewer as a bright rim. */
let KEY_EL = 32.0 * Double.pi / 180
/// how soft the back light is by default (see FabricMaterial.backSoft)
let BACK_SOFT = 1.0

@inline(__always) func unit3(_ v: V3) -> V3 {
    let l = (v[0] * v[0] + v[1] * v[1] + v[2] * v[2]).squareRoot()
    return l > 0 ? v / l : v
}
@inline(__always) func smooth(_ a: Double, _ b: Double, _ v: Double) -> Double {
    let t = v <= a ? 0 : v >= b ? 1 : (v - a) / (b - a)
    return t * t * (3 - 2 * t)
}

func fabricKey(_ U: V3, _ V: V3, _ front: Double = KEY_EL) -> V3 {
    let c = cos(front), s = sin(front)
    return unit3(V3(U[0] * c + V[0] * s, U[1] * c + V[1] * s, U[2] * c + V[2] * s))
}
func fabricBack(_ K: V3, _ V: V3) -> V3 {
    unit3(V3(0.94 * K[0] - 0.34 * V[0], 0.94 * K[1] - 0.34 * V[1], 0.94 * K[2] - 0.34 * V[2]))
}
/// Where the back light is on screen by default, as a unit vector (y down)
/// from the key's (lx, ly): above the toy and toward the side away from the key.
func backFromKey(_ lx: Double, _ ly: Double) -> (Double, Double) {
    let x = -0.5 * lx, y = -0.5 * ly - 0.87
    var l = (x * x + y * y).squareRoot()
    if l == 0 { l = 1 }
    return (x / l, y / l)
}

/// The lights the pile's own fibres are baked for: the back light's
/// direction on screen (unit, y down) and how far round to the front the
/// key sits (radians).
struct FurLights: Hashable {
    var bx: Double
    var by: Double
    var front: Double
    /// the stock lights for a key at (lx, ly) on screen
    static func stock(_ lx: Double, _ ly: Double) -> FurLights {
        let (bx, by) = backFromKey(lx, ly)
        return FurLights(bx: bx, by: by, front: KEY_EL)
    }
    /// the bins the pile is kept by: 5° of the back light, 2° of the front
    var id: String { "\(Int(jsRound(atan2(by, bx) / (Double.pi / 36))))|\(Int(jsRound(front / (Double.pi / 90))))" }
}

/// Fabric's material: the light's strengths and fabric's own knobs.
struct FabricMaterial: Equatable {
    var shadow: Double, highlight: Double, spread: Double, rim: Double
    /** 0–1: how much colour the light keeps past the palette's full
        saturation; always 0 in this port (it has no `richer`), kept so the
        formulas read as the web's */
    var vivid = 0.0
    /** how far round to the front the key sits, radians */
    var front = KEY_EL
    /** the strength of the light along single fibres */
    var shine = 0.0
    /** 0–1, how soft the back light is */
    var backSoft = BACK_SOFT
    /** the smooth, satin light over the body's edge */
    var sheen = 0.0
}

/* ── the cap's frame ───────────────────────────────────────────────── */

/// The rig's numbers the fabric needs for one frame.
struct FabricRig {
    /** the rig's (floored) cos/sin of yaw and pitch, as used by the slice affines */
    var cy: Double, sy: Double, cp: Double, sp: Double
    /** cos(yaw)·cos(pitch), unfloored: the front faces the viewer while positive */
    var facing: Double
    var roll: Double
    var halfDepth: Double
    /** unit vector toward the light on screen, and toward the back light */
    var lx: Double, ly: Double
    var bx: Double, by: Double
    /** the avatar box in device pixels (points × scale) */
    var dev: Double
    /** the display scale, capped at 2: device pixels per point */
    var scale: Double
    /** the transform for body space, in points */
    var ctm: CGAffineTransform
    /** no animation loop will follow */
    var still: Bool
    /** the profile through the depth */
    var round: Double
}

/// Light and view directions in the cap's own frame.
struct FabricFrame {
    var L: V3, V: V3, U: V3
    /** down on screen: toward the floor */
    var D: V3
    /** toward the back light on screen */
    var K: V3
}

/// Screen-space vectors into the cap's frame: un-roll, then the transpose
/// of the rig's rotation; the back is the front mirrored in z.
func fabricCapFrame(_ r: FabricRig) -> FabricFrame {
    let cr = cos(r.roll), sr = sin(r.roll)
    let lx = cr * r.lx + sr * r.ly, ly = -sr * r.lx + cr * r.ly
    let mirror: Double = r.facing < 0 ? -1 : 1
    /* the flip passes through edge-on: fade the mirrored component so the
       light does not pop from one side of the sliver to the other */
    let zf = mirror * min(1, abs(r.facing) / 0.16)
    let cy = r.cy, sy = r.sy, cp = r.cp, sp = r.sp
    func local(_ x: Double, _ y: Double, _ z: Double, _ zk: Double) -> V3 {
        unit3(V3(cy * x + sy * sp * y - sy * cp * z, cp * y + sp * z, zk * (sy * x - cy * sp * y + cy * cp * z)))
    }
    let L = local(E_XY * lx, E_XY * ly, E_Z, zf)
    let V = local(0, 0, 1, mirror)
    let U = local(lx, ly, 0, mirror)
    /* screen down, un-rolled the same way as the light */
    let D = local(sr, cr, 0, mirror)
    let K = local(cr * r.bx + sr * r.by, -sr * r.bx + cr * r.by, 0, mirror)
    return FabricFrame(L: L, V: V, U: U, D: D, K: K)
}

/* ── the matcap ────────────────────────────────────────────────────── */

/// linear to 0–255 sRGB, no shoulder
@inline(__always) func srgb(_ v: Double) -> Double {
    v <= 0 ? 0 : v >= 1 ? 255 : 255 * (v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055)
}

/* More colour than a fully saturated palette colour has: the light's own
   mixes pulled away from grey about their luminance, as far as the gamut
   allows. In place on a linear triple. */
private func vivify(_ c: inout V3, _ v: Double, _ cap: Double = .infinity) {
    if !(v > 0) { return }
    let y = 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
    let mn = min(c[0], c[1], c[2]), mx = max(c[0], c[1], c[2])
    var k = 1 + 3 * v
    if mn < y { k = min(k, y / (y - mn)) }
    if mx > y { k = min(k, max(1, (cap - y) / (mx - y))) }
    c = V3(y + (c[0] - y) * k, y + (c[1] - y) * k, y + (c[2] - y) * k)
}

/// The lit sphere for the pile, as a studio photograph of a plush toy
/// lights it: a clear key high on the light's side with a soft but readable
/// terminator and a real shade side, the shade the colour deepened rather
/// than greyed, a saturated band where the key turns into shade, a sheen
/// where the fibres at the lit side's silhouette lie side-on to the key,
/// and a strong back light along the silhouette. No specular lobe and no
/// reflections — fur has no clear coat. Fills `out` (M × M × rgb, sRGB 0–255).
func buildFabricMatcap(_ out: inout [Float], _ c: V3, _ f: FabricFrame, _ p: FabricMaterial) {
    let V = f.V, U = f.U, D = f.D
    let vivid = p.vivid
    let L = fabricKey(U, V, p.front)
    let Lb = fabricBack(f.K, V)
    /* the shade side: a little ambient from the room and a dim fill from the
       other side and the front; `shadow` takes both down */
    let amb = max(0.03, 0.2 - 0.15 * p.shadow)
    let fillK = max(0.04, 0.24 - 0.13 * p.shadow)
    /* the key wraps a little past the terminator — the pile scatters it —
       and more toward the silhouette */
    let wrap = min(0.7, 0.05 + 0.12 * p.spread)
    let kd = 1.3
    let floorK = 0.34 * min(1.6, p.shadow / 0.35)
    let Fl = unit3(V3(-0.55 * U[0] + 0.85 * V[0] + 0.15 * D[0], -0.55 * U[1] + 0.85 * V[1] + 0.15 * D[1], -0.55 * U[2] + 0.85 * V[2] + 0.15 * D[2]))
    /* `sheen` scales the smooth light — the key's sheen and the back light's
       band as one even gradient over the body's edge, a satin look */
    let satin = p.sheen
    let backSoft = min(1, max(0, p.backSoft))
    let sheenK = 0.16 * p.highlight * satin, rimK = 1.15 * p.rim * satin, sssK = 0.2 + 0.25 * vivid
    /* the colour at full brightness */
    let mx = max(c[0], c[1], c[2], 0.02)
    let cb = V3(c[0] / mx, c[1] / mx, c[2] / mx)
    /* the back light through the pile comes out in the fibres' colour at
       full brightness; only the outermost hairs pass some of its white */
    let rimIn = cb
    let wR = 0.45 * (1 - vivid), wS = 0.25 * (1 - vivid)
    let rimOut = V3(wR + (1 - wR) * cb[0], wR + (1 - wR) * cb[1], wR + (1 - wR) * cb[2])
    let sheenC = V3(wS + (1 - wS) * cb[0], wS + (1 - wS) * cb[1], wS + (1 - wS) * cb[2])
    /* the shade's colour: the body's twice filtered through its own dye,
       brought back to the body's luminance */
    func yOf(_ v: V3) -> Double { 0.2126 * v[0] + 0.7152 * v[1] + 0.0722 * v[2] }
    let de = 1.8 + 2.2 * vivid
    let d0 = V3(pow(c[0], de), pow(c[1], de), pow(c[2], de))
    let dk = yOf(c) / max(1e-4, yOf(d0))
    let deep = d0 * dk
    /* and the band at the terminator: the colour filtered once more */
    let sc = V3(cb[0] * cb[0] * c[0], cb[1] * cb[1] * c[1], cb[2] * cb[2] * c[2])
    out.withUnsafeMutableBufferPointer { op in
        let out = op.baseAddress!
        for j in 0..<M {
            for i in 0..<M {
                var nx = (Double(i) / Double(M - 1)) * 2 - 1, ny = (Double(j) / Double(M - 1)) * 2 - 1
                var r2 = nx * nx + ny * ny
                if r2 > 1.14 { continue }
                if r2 > 1 {
                    let s = 1 / r2.squareRoot()
                    nx *= s; ny *= s; r2 = 1
                }
                let nz = (1 - r2).squareRoot()
                let nl = nx * L[0] + ny * L[1] + nz * L[2]
                let nv = max(0, nx * V[0] + ny * V[1] + nz * V[2])
                let nd = nx * D[0] + ny * D[1] + nz * D[2]
                let nb = nx * Lb[0] + ny * Lb[1] + nz * Lb[2]
                let q = 1 - nv
                let w = wrap + (0.45 - wrap) * q * q
                var dif = min(1, max(0, (nl + w) / (1 + w)))
                dif = pow(dif, 1.35)
                let fill = fillK * max(0, nx * Fl[0] + ny * Fl[1] + nz * Fl[2])
                let floor = 1 - floorK * max(0, nd) * (0.6 + 0.4 * q)
                let light = (amb + kd * dif + fill) * floor
                /* toward the shade the colour deepens rather than greys */
                let t = min(1, max(0, 1 - light))
                let sb = max(0, 1 - ((nl + 0.08) * (nl + 0.08)) / 0.18)
                let sss = sssK * sb * sb * floor
                /* the key's sheen on the lit side where the fibres lie side-on to it */
                let lit = min(1, max(0, (nl + 0.2) / 0.8))
                let sheen = sheenK * q * q * lit
                /* the back light: where the pile faces it at all, seen through
                   the most pile toward the silhouette; the underside catches little */
                let bl = smooth(-0.3, 0.6, nb)
                let rq = smooth(0.18 - 0.12 * backSoft, 0.62 + 0.18 * backSoft, q)
                let rim = rimK * rq * rq.squareRoot() * (0.3 + 0.7 * bl) * (1 - 0.7 * max(0, nd))
                let hot = rq * rq * rq.squareRoot() * (1 - 0.5 * backSoft)
                var px = V3()
                for ch in 0..<3 {
                    let base = c[ch] + (deep[ch] - c[ch]) * t * 0.9
                    px[ch] = base * light + sss * sc[ch] + sheen * sheenC[ch] + rim * (rimIn[ch] + (rimOut[ch] - rimIn[ch]) * hot)
                }
                /* bright parts roll off as a whole, not channel by channel */
                let m = max(px[0], px[1], px[2])
                if m > 0.8 {
                    let kk = (0.8 + 0.2 * (1 - exp(-(m - 0.8) / 0.2))) / m
                    px *= kk
                }
                if vivid > 0 { vivify(&px, vivid, 1) }
                let k = (j * M + i) * 3
                out[k] = Float(srgb(px[0]))
                out[k + 1] = Float(srgb(px[1]))
                out[k + 2] = Float(srgb(px[2]))
            }
        }
    }
}

/* how wide the front's texture fades out toward the outline, in design
   units: that band is the side of the form, which the slices under it
   shade — the front blends into them instead of ending at a line */
let FRONT_FADE = 5.0

/// Per frame: matcap lookup × baked occlusion (the edge's darkening lifted
/// back out) into the texture's pixels, RGBA not premultiplied (the web's
/// ImageData); the alpha fades the front out over its outer FRONT_FADE units.
func shadeFabricTexels(_ form: FabricForm, _ mc: [Float], _ px: inout [UInt8], _ aoMul: [Float]) {
    let N = form.N
    let R = M * 3
    let lift = form.lift
    form.i00.withUnsafeBufferPointer { i00p in form.wx.withUnsafeBufferPointer { wxp in form.wy.withUnsafeBufferPointer { wyp in
    form.ao.withUnsafeBufferPointer { aop in form.sd.withUnsafeBufferPointer { sdp in mc.withUnsafeBufferPointer { mcp in
    aoMul.withUnsafeBufferPointer { amp in lift.ao.withUnsafeBufferPointer { lap in lift.k.withUnsafeBufferPointer { lkp in
    px.withUnsafeMutableBufferPointer { pxp in
        let i00 = i00p.baseAddress!, wx = wxp.baseAddress!, wy = wyp.baseAddress!, ao = aop.baseAddress!, sd = sdp.baseAddress!
        let mc = mcp.baseAddress!, aoMul = amp.baseAddress!, lao = lap.baseAddress!, lk = lkp.baseAddress!, px = pxp.baseAddress!
        var k = 0
        for i in 0..<(N * N) {
            if ao[i] == 0 {
                px[k + 3] = 0
                k += 4
                continue
            }
            var m = aoMul[Int(lao[i])] * lk[i]
            let b = Int(i00[i]) * 3, x = Float(wx[i]) * (1 / 255), y = Float(wy[i]) * (1 / 255)
            /* The occlusion is the room's light hidden by the form around a
               point, not the key's: where the matcap is lit by the key it
               takes less of it, so the lit side stays bright and only the
               shade and the creases sink */
            let g = (mc[b + 1] * (1 - x) + mc[b + 4] * x) * (1 - y) + (mc[b + R + 1] * (1 - x) + mc[b + R + 4] * x) * y
            m = 1 - (1 - m) * (1.1 - 0.75 * min(1, g / 235))
            let w00 = (1 - x) * (1 - y) * m, w10 = x * (1 - y) * m, w01 = (1 - x) * y * m, w11 = x * y * m
            let r = mc[b] * w00 + mc[b + 3] * w10 + mc[b + R] * w01 + mc[b + R + 3] * w11
            let gg = mc[b + 1] * w00 + mc[b + 4] * w10 + mc[b + R + 1] * w01 + mc[b + R + 4] * w11
            let bl = mc[b + 2] * w00 + mc[b + 5] * w10 + mc[b + R + 2] * w01 + mc[b + R + 5] * w11
            /* a Uint8ClampedArray rounds half to even */
            px[k] = UInt8(min(255, max(0, r.rounded(.toNearestOrEven))))
            px[k + 1] = UInt8(min(255, max(0, gg.rounded(.toNearestOrEven))))
            px[k + 2] = UInt8(min(255, max(0, bl.rounded(.toNearestOrEven))))
            let t = Double(sd[i]) / FRONT_FADE
            px[k + 3] = t >= 1 ? 255 : t <= 0 ? 0 : UInt8(jsRound(255 * t * t * (3 - 2 * t)))
            k += 4
        }
    } } } } } } } } } }
}

/// RGBA bytes, not premultiplied, as an image.
func straightImage(_ px: [UInt8], _ N: Int) -> CGImage? {
    guard let provider = CGDataProvider(data: Data(px) as CFData) else { return nil }
    return CGImage(width: N, height: N, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: N * 4, space: fabricSRGB, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
}

/* ── the films in the body's colour ────────────────────────────────── */

/// The colour's sRGB channels, 0–255, through its linear values as the web
/// reckons them (`srgb(linearColor(c))`).
private func encoded(_ color: BotColor) -> V3 {
    let lin = color.linear
    return V3(srgb(lin[0]), srgb(lin[1]), srgb(lin[2]))
}

private extension FabricBitmap {
    /// draw an image over the whole bitmap (the canvas's drawImage(src, 0, 0))
    func drawWhole(_ img: CGImage, alpha: Double = 1, blend: CGBlendMode = .normal) {
        guard let g = ctx else { return }
        g.saveGState()
        g.translateBy(x: 0, y: CGFloat(size))
        g.scaleBy(x: 1, y: -1)
        g.setAlpha(alpha)
        g.setBlendMode(blend)
        g.draw(img, in: CGRect(x: 0, y: 0, width: size, height: size))
        g.restoreGState()
    }
    /// fill the whole bitmap with an sRGB 0–255 colour
    func fillWhole(_ r: Double, _ gr: Double, _ b: Double, alpha: Double = 1, blend: CGBlendMode = .normal) {
        guard let g = ctx else { return }
        g.saveGState()
        g.setBlendMode(blend)
        g.setFillColor(CGColor(colorSpace: fabricSRGB, components: [r / 255, gr / 255, b / 255, alpha])!)
        g.fill(CGRect(x: 0, y: 0, width: size, height: size))
        g.restoreGState()
    }
}

/* The gaps between locks and strands are the pile's own colour in shade —
   a dyed fibre deepens there, it does not grey — so the film's dark part is
   laid in a deep, richer shade of the body colour rather than black. A
   light, pale dye lets the light scatter far down into the pile and fill
   its depths in: the lighter and paler the colour, the lighter its gaps. */
private let GAP_DEEP = 0.28, GAP_SCATTER = 0.42
/// the shade the film's dark part is encoded for (see the fleece)
let GAP_REF = 0.36

func gapFilm(_ fur: Fur, _ color: BotColor, _ vivid: Double = 0) -> CGImage? {
    guard let src = fur.dark else { return nil }
    let vq = jsRound(min(1, vivid) * 10) / 10
    return filmCache(&fur.gapFilms, FilmKey(color: color, v: [vq]), limit: 4) {
        let c = FabricBitmap(src.width)
        let e = encoded(color) / 255
        let mx = max(e[0], e[1], e[2], 1e-3)
        let lu = 0.2126 * e[0] + 0.7152 * e[1] + 0.0722 * e[2]
        let pale = min(e[0], e[1], e[2]) / mx
        let kd = GAP_DEEP + GAP_SCATTER * lu * lu * pale
        func ch(_ v: Double) -> Double { jsRound(255 * kd * v * pow(v / mx, 3.2 + 3 * vq)) }
        let r = ch(e[0]), gr = ch(e[1]), b = ch(e[2])
        /* laid at the share that halves the difference from GAP_REF: a strong
           colour's gaps read a little deeper, its body keeps its tone */
        let deep = (0.2126 * r + 0.7152 * gr + 0.0722 * b) / 255 / max(1e-3, lu)
        c.drawWhole(src, alpha: min(1, ((1 - GAP_REF) / max(0.05, 1 - deep)).squareRoot()))
        c.fillWhole(r, gr, b, blend: .sourceIn)
        return c.image()
    }
}

/* The fibres' lit tips are the key come through a dyed fibre: the film's
   light part is laid in the colour at full brightness, TIP_TINT of the way
   from white, so lighting a lock lifts its colour rather than chalking it. */
private let TIP_TINT = 0.6

func tipFilm(_ fur: Fur, _ color: BotColor, _ vivid: Double) -> CGImage? {
    guard let src = fur.light else { return nil }
    let v = jsRound((TIP_TINT + (1 - TIP_TINT) * min(1, max(0, vivid))) * 10) / 10
    return filmCache(&fur.tipFilms, FilmKey(color: color, v: [v]), limit: 6) {
        let c = FabricBitmap(src.width)
        c.drawWhole(src)
        let e = encoded(color)
        let mx = max(e[0], e[1], e[2], 1)
        func ch(_ u: Double) -> Double { jsRound(255 + ((255 * u) / mx - 255) * min(1, v)) }
        c.fillWhole(ch(e[0]), ch(e[1]), ch(e[2]), blend: .sourceIn)
        return c.image()
    }
}

/* The fibres' own light as one film for a colour and material: the key's
   highlights along the fibres (as strong as `highlight` × `shine` say) and
   the back light the fibres carry, mostly in the dye's colour at full
   brightness (as strong as `rim` says); a softer back light gives its even
   glow in place of the light on single fibres. */
func sheenFilm(_ fur: Fur, _ color: BotColor, _ p: FabricMaterial) -> CGImage? {
    guard let gl = fur.glint, let bk = fur.back else { return nil }
    let hk = min(1, 0.45 * p.highlight * p.shine), rk = min(1, 1.1 * p.rim)
    if hk <= 0.01 && rk <= 0.01 { return nil }
    let vivid = min(1, p.vivid)
    let soft = min(1, max(0, jsRound(p.backSoft * 20) / 20))
    /* keyed as the web's: the strengths to a hundredth, vivid to a tenth */
    let key = FilmKey(color: color, v: [jsRound(hk * 100), jsRound(rk * 100), jsRound(vivid * 10), soft])
    return filmCache(&fur.sheenFilms, key, limit: 6) {
        let W = gl.width
        let c = FabricBitmap(W), t = FabricBitmap(W)
        let e = encoded(color)
        let mx = max(e[0], e[1], e[2], 1)
        func mix(_ k: Double) -> V3 { V3(jsRound(255 + ((255 * e[0]) / mx - 255) * k), jsRound(255 + ((255 * e[1]) / mx - 255) * k), jsRound(255 + ((255 * e[2]) / mx - 255) * k)) }
        let layers: [(CGImage?, V3, Double)] = [
            (bk, mix(0.65 + 0.35 * vivid), rk * (1 - 0.85 * soft)),
            (fur.backSoft, mix(0.7 + 0.3 * vivid), rk * soft),
            (gl, mix(0.45 + 0.55 * vivid), hk),
        ]
        for (src, fill, a) in layers {
            guard let src = src, a > 0.01 else { continue }
            t.drawWhole(src, blend: .copy)
            t.fillWhole(fill[0], fill[1], fill[2], blend: .sourceIn)
            if let ti = t.image() { c.drawWhole(ti, alpha: a) }
        }
        return c.image()
    }
}

/// What a film in the body's colour is made for: the colour and the
/// numbers that shape it.
struct FilmKey: Hashable {
    var color: BotColor
    var v: [Double]
}

/// A film from its cache, or made and kept (the cache cleared past `limit`).
private func filmCache(_ store: inout [FilmKey: CGImage?], _ key: FilmKey, limit: Int, _ make: () -> CGImage?) -> CGImage? {
    if let hit = store[key] { return hit }
    let made = make()
    if store.count >= limit { store.removeAll() }
    store[key] = made
    return made
}

/// The halo's complement, made the first time a turn needs it and kept.
func furCut(_ fur: Fur) -> CGImage? {
    if let cut = fur.cut { return cut }
    guard let mask = fur.mask else { return nil }
    let c = FabricBitmap(mask.width)
    c.fillWhole(0, 0, 0)
    c.drawWhole(mask, blend: .destinationOut)
    fur.cut = c.image()
    return fur.cut
}
