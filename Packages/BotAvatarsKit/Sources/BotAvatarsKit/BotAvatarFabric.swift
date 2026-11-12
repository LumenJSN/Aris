import CoreGraphics
import Foundation
import SwiftUI

/* The 'fabric' shading's draw: the inflated body as a relief of the lit
   front, in a plush pile. A port of `drawPlasticCap` in plastic.ts at
   bfb396b on its fabric path (the web's plastic takes the same relief;
   this package's plastic keeps its own, older draw).

   The body: slices of the outline through the depth, each scaled to the
   cushion's profile there and shaded as the form's side at that depth,
   back to front, then the lit front laid over them once. Fabric draws
   them into a buffer of their own — here a layer of the canvas — lays its
   halo over the silhouette, and the pile over all of it at once as one
   film; the layer is then composited into the canvas. The canvas's
   sprites (the halo, the equator, the band) are drawn in place, each a
   layer of its own, from the same images and gradients. */

private let PAD = BOT_AVATAR_PAD, SPAN = BOT_AVATAR_SPAN
private let MM = MATCAP_M * MATCAP_M

/// Fabric's per-avatar, per-outline state (the web's `State` on the
/// fabric path): the matcap and its cross-fade, the texels, the slices'
/// light, the halo's fit.
final class FabricState {
    var N = 0
    var img: [UInt8] = []
    var image: Image? = nil
    var mc = [Float](repeating: 0, count: MM * 3)
    var mcPrev = [Float](repeating: 0, count: MM * 3)
    var mcMix = [Float](repeating: 0, count: MM * 3)
    /** what the matcap holds; rebuilt when any moves */
    var L: V3? = nil, V: V3? = nil, K: V3? = nil
    var lx = Double.nan, ly = Double.nan
    var base: BotColor? = nil
    var mat: FabricMaterial? = nil
    var version = 0
    var mixVersion = 0
    var blendT = 1.0
    var blendFrames = 1
    var sinceBuild = 0
    var imgVersion = -1
    var imgAoK = Double.nan
    var imgForm: FabricForm? = nil
    var aoK = -1.0
    var aoMul = [Float](repeating: 0, count: 256)
    /** the near and far halves' slices' light, and what it was made for */
    var sliceG: [GraphicsContext.Shading] = []
    var sliceKey = ""
    /** the equator's light and the rays it was taken from (per matcap) */
    var rays: FabricRays? = nil
    var raysVersion = -1
    var side: GraphicsContext.Shading? = nil
    var haze: Color? = nil
    /** the halo's fit: the last turn's miss and where it was measured, the
        last frame's turn, the recession and fade last drawn, the weight of
        the halo laid over the body */
    var miss = (0.0, 0.0)
    var missAt = (0.0, 0.0)
    var turnAt = (0.0, 0.0)
    var fade: (Double, Double)? = nil
    var lay = 1.0
    /** the matcap builds (for the demo's counters) */
    var matcapBuilds = 0
    /** the form the outline's light and the halo's fit were taken on */
    var form: FabricForm? = nil

    /// A new outline (or size of it): what was measured on the old one goes
    /// (the web keeps a state per outline).
    func outline(_ f: FabricForm) {
        if form === f { return }
        form = f
        rays = nil
        raysVersion = -1
        sliceKey = ""
        miss = (0, 0)
        missAt = (0, 0)
        turnAt = (0, 0)
        fade = nil
        lay = 1
    }
}

/* the matcap is rebuilt once a direction has moved a bin (1/48) */
private let BIN = 1.0 / 48
@inline(__always) private func moved(_ a: V3, _ b: V3?) -> Bool {
    guard let b = b else { return true }
    return abs(a[0] - b[0]) >= BIN || abs(a[1] - b[1]) >= BIN || abs(a[2] - b[2]) >= BIN
}

/// A layer drawn into `g` in its current transform, its own drawing
/// starting from full opacity and the normal blend: the layer itself is
/// composited with `g`'s.
private func layer(_ g: inout GraphicsContext, _ draw: (inout GraphicsContext) -> Void) {
    let t = g.transform
    g.drawLayer { s in
        s.transform = t
        s.opacity = 1
        s.blendMode = .normal
        draw(&s)
    }
}

/// What fabric's draw needs from the config besides the rig.
struct FabricCall {
    var path: Path
    var cgPath: CGPath
    var key: String
    var base: BotColor
    var mat: FabricMaterial
    var fur: BotAvatarFurStyle
    /** bake a still frame's pile on the queue all the same (the web's `furOnIdle`) */
    var bakeOnIdle: Bool
}

/// Draw the fabric body as a relief. Call with the context in the body
/// transform. Returns false while the form or pile is still baking: the
/// caller draws the smooth stand-in that frame.
///
/// Main thread only: the matcap state, the form's and the pile's caches and
/// the halo's measures are read and written here unsynchronised. A fabric
/// canvas renders asynchronously, but its drawing still runs on the main
/// thread (`CanvasThreadTests`, `botavatar-bench --threads`).
func drawFabricBody(_ ctx: inout GraphicsContext, _ call: FabricCall, rig: FabricRig, st: FabricState) -> Bool {
    dispatchPrecondition(condition: .onQueue(.main))
    let N = botAvatarTier(rig.dev)
    let capPx = (SPAN * rig.dev / 100).rounded(.up)
    let lights = FurLights(bx: rig.bx, by: rig.by, front: call.mat.front)
    guard let (form, fur) = FabricBakes.ready(key: call.key, path: call.cgPath, N: N, halfDepth: rig.halfDepth, capPx: capPx, lx: rig.lx, ly: rig.ly, style: call.fur, lights: lights, sync: rig.still && !call.bakeOnIdle) else { return false }
    st.outline(form)
    let mat = call.mat
    let f = fabricCapFrame(rig)
    updateMatcap(st, f, rig, call.base, mat)
    /* the occlusion strength follows `shadow`; a pile sinks deeper into its
       creases than a clear coat does, which keeps fur's lobes apart */
    let aoK = min(1.2, 0.3 + 0.8 * mat.shadow)
    if aoK != st.aoK {
        for a in 0..<256 { st.aoMul[a] = Float(max(0, 1 - aoK * (1 - Double(a) / 255))) }
        st.aoK = aoK
    }
    if st.N != N || st.img.count != N * N * 4 {
        st.img = [UInt8](repeating: 0, count: N * N * 4)
        st.N = N
        st.imgVersion = -1
    }
    if st.imgVersion != st.mixVersion || st.imgAoK != aoK || st.imgForm !== form {
        shadeFabricTexels(form, st.mcMix, &st.img, st.aoMul)
        st.imgVersion = st.mixVersion
        st.imgAoK = aoK
        st.imgForm = form
        st.image = straightImage(st.img, N).map { Image(decorative: $0, scale: 1).interpolation(.high) }
    }
    guard let capSrc = st.image else { return false }

    let K = rig.dev <= 100 ? 14 : rig.dev <= 224 ? 20 : 26
    let rel = reliefFor(form, K, rig.round)
    let cy = rig.cy, sy = rig.sy, cp = rig.cp, sp = rig.sp
    let ctm = rig.ctm
    let m1 = sy * sp
    let near: Double = rig.facing >= 0 ? 1 : -1
    let c0 = (rel.cx[0], rel.cy[0])

    /* the lit front's place, once, at the equator plane, stretched along
       the turn to span the front's projection */
    let dxs = sy / cy, dys = -sp / (cy * cp)
    let dl1 = (dxs * dxs + dys * dys).squareRoot()
    var lead = 50.0
    for k in 1..<K { lead = max(lead, 50 * rel.scale[k] + rel.z[k] * dl1) }
    let ex = dl1 > 1e-6 ? (near * dxs) / dl1 : 1, ey = dl1 > 1e-6 ? (near * dys) / dl1 : 0
    let backShade = min(0.7, 0.55 * min(1.6, mat.shadow / 0.35))
    let haloS = haloStretch(form, rel, K, ex, ey, dl1)
    /* the rays of the front's light, and the equator's and the halo's
       colours from them, once per matcap */
    if st.raysVersion != st.version || st.rays == nil {
        let rays = raysOf(st.img, form, c0)
        st.rays = rays
        st.raysVersion = st.version
        st.side = sliceGradient(rays, inset: { _ in max(HALO_INSET, rel.inset[0]) }, dark: { _ in 0 }, c0)
        st.haze = hazeColor(rays, call.base, mat.rim, mat.vivid)
    }
    let rays = st.rays!
    let edge = haloRays(form, rel, K, ex, ey, dl1, haloS, backShade)
    let fringeFill = sliceGradient(rays, inset: { edge.inset[$0] }, dark: { edge.dark[$0] }, c0)
    let stretch = (lead + 50) / 100, shift = (lead - 50) / 2
    let A = 1 + (stretch - 1) * ex * ex, B = (stretch - 1) * ex * ey, D = 1 + (stretch - 1) * ey * ey
    let rot = CGAffineTransform(a: cy, b: m1, c: 0, d: cp, tx: 0, ty: 0)
    let capStretch = CGAffineTransform(a: A, b: B, c: B, d: D, tx: shift * ex - 50 * A - 50 * B, ty: shift * ey - 50 * B - 50 * D)
    let capM = capStretch.concatenating(rot).concatenating(ctm)

    /* each slice in the front's own colour where its edge lies on it */
    let sliceKey = "\(st.version)|\(K)|\(rel.q)"
    if st.sliceKey != sliceKey {
        st.sliceG = (0..<K).map { k in sliceGradient(rays, inset: { _ in max(HALO_INSET, rel.inset[k]) }, dark: { _ in 0 }, c0) }
        st.sliceKey = sliceKey
    }

    /* at depth z: yaw about Y then pitch about X, orthographic */
    func at(_ z: Double) -> CGAffineTransform {
        CGAffineTransform(a: cy, b: m1, c: 0, d: cp, tx: z * sy - 50 * cy, ty: -z * cy * sp - 50 * m1 - 50 * cp).concatenating(ctm)
    }
    let square = Path(CGRect(x: -PAD, y: -PAD, width: SPAN, height: SPAN))
    let squareRect = CGRect(x: -PAD, y: -PAD, width: SPAN, height: SPAN)
    func img(_ cg: CGImage?) -> Image? { cg.map { Image(decorative: $0, scale: 1).interpolation(.low) } }
    let softImg = img(softMask(form, fur.R)), maskImg = img(fur.mask), hazeImg = img(fur.haze), coreImg = img(fur.core)

    /* the sprites, drawn in place: the side's light at the equator with a
       plain soft edge; the halo (its tips' haze in the brightest colour
       over the silhouette's colour, cut to the body and its fringe); and
       the halo's band, less the body's inside. A canvas's destination-in
       clears everything outside what it draws, where a context's leaves
       it: the cut is a clip to the mask's alpha instead. */
    func sideSprite(_ g: inout GraphicsContext) {
        layer(&g) { s in
            if let m = softImg ?? maskImg { s.clipToLayer { c in c.draw(m, in: squareRect) } }
            if let side = st.side { s.fill(square, with: side) }
        }
    }
    func fringed(_ s: inout GraphicsContext) {
        if let maskImg = maskImg { s.clipToLayer { c in c.draw(maskImg, in: squareRect) } }
        s.fill(square, with: fringeFill)
        if let hazeImg = hazeImg, let haze = st.haze {
            layer(&s) { h in
                h.draw(hazeImg, in: squareRect)
                h.blendMode = .sourceIn
                h.fill(square, with: .color(haze))
            }
        }
    }
    func fringedSprite(_ g: inout GraphicsContext) { layer(&g) { s in fringed(&s) } }
    func bandSprite(_ g: inout GraphicsContext) {
        layer(&g) { s in
            layer(&s) { f in fringed(&f) }
            s.blendMode = .destinationOut
            if let coreImg = coreImg { s.draw(coreImg, in: squareRect) }
        }
    }

    /* the slices that show, far half then near half */
    let ring = form.ring, rn = ring.x.count, NF = form.N
    let devK = rig.scale
    let det = Double(ctm.a * ctm.d - ctm.b * ctm.c) * cy * cp
    let hideBy = 1.5 / ((abs(det).squareRoot() * devK) > 0 ? abs(det).squareRoot() * devK : 1) + 0.4
    let texel = SPAN / Double(NF)
    func toG(_ v: Double) -> Double { ((v + PAD) / SPAN) * Double(NF) - 0.5 }
    let leanFar = atan2(-near * dys, -near * dxs), leanNear = atan2(near * dys, near * dxs)
    var farSlices: [Int] = []
    var nearSlices: [Int] = []
    let face = abs(rig.facing)
    let frontA = face >= 0.72 ? 1 : face <= 0.34 ? 0 : pow((face - 0.34) / 0.38, 1.5)
    let cdet = Double(capM.a * capM.d - capM.b * capM.c)
    let coverBy = FRONT_FADE + 1.5 / ((abs(cdet).squareRoot() * devK) > 0 ? abs(cdet).squareRoot() * devK : 1)
    let capInv = capM.inverted()
    form.sd.withUnsafeBufferPointer { sdp in
        let sd = sdp.baseAddress!
        /* a far slice lying wholly inside the equator, which is drawn over it, cannot show */
        for k in stride(from: K - 1, through: 1, by: -1) {
            let z = -near * rel.z[k], sk = rel.scale[k]
            let bx = rel.cx[k] - sk * rel.cx[0] + z * dxs, by = rel.cy[k] - sk * rel.cy[0] + z * dys
            var hidden = bx.isFinite && by.isFinite
            var j = 0
            while hidden && j < rn {
                let i = ringOrder(rn, leanFar, j)
                if bilerp(sd, NF, toG(sk * ring.x[i] + bx), toG(sk * ring.y[i] + by)) < hideBy + sk * (ring.d[i] + texel) { hidden = false }
                j += 1
            }
            if !hidden { farSlices.append(k) }
        }
        /* a near slice lying wholly inside the front's opaque part cannot show */
        for k in 1..<K {
            let z = near * rel.z[k], sk = rel.scale[k]
            if frontA >= 1 && abs(cdet) > 1e-9 {
                let t = at(z)
                let ux = rel.cx[k] - sk * rel.cx[0], uy = rel.cy[k] - sk * rel.cy[0]
                var covered = true
                var j = 0
                while covered && j < rn {
                    let i = ringOrder(rn, leanNear, j)
                    let p = CGPoint(x: sk * ring.x[i] + ux, y: sk * ring.y[i] + uy).applying(t).applying(capInv)
                    if bilerp(sd, NF, toG(Double(p.x)), toG(Double(p.y))) < coverBy + sk * (ring.d[i] + texel) { covered = false }
                    j += 1
                }
                if covered { continue }
            }
            nearSlices.append(k)
        }
    }
    func slice(_ g: inout GraphicsContext, _ k: Int, _ z: Double) {
        if k > 0 {
            let sk = rel.scale[k]
            g.transform = CGAffineTransform(a: sk, b: 0, c: 0, d: sk, tx: rel.cx[k] - sk * rel.cx[0], ty: rel.cy[k] - sk * rel.cy[0]).concatenating(at(z))
            g.fill(call.path, with: st.sliceG[k])
            return
        }
        /* the equator ends in its soft edge (its fringe is the halo) */
        g.transform = at(0)
        sideSprite(&g)
    }
    /// the body: the far half, its shade, the equator, the near half, the front
    func body(_ g: inout GraphicsContext) {
        for k in farSlices { slice(&g, k, -near * rel.z[k]) }
        /* the far half sinks into shade smoothly rather than a step a slice:
           one ramp from the outline's far edge out to the stack's */
        if dl1 > 1e-3 {
            let hn = reach(form.rim, -ex, -ey), span = 1.3 * rel.top * dl1
            g.transform = at(0)
            var stops: [Gradient.Stop] = []
            for s in 0...8 {
                let t = Double(s) / 8
                let a = (backShade * (1 - exp(-2.4 * t)) * t * t * (3 - 2 * t) * 1000).rounded() / 1000
                stops.append(Gradient.Stop(color: Color(.sRGB, red: 0, green: 0, blue: 0, opacity: a), location: t))
            }
            g.blendMode = .sourceAtop
            g.fill(Path(CGRect(x: -PAD - 60, y: -PAD - 60, width: SPAN + 120, height: SPAN + 120)), with: .linearGradient(Gradient(stops: stops), startPoint: CGPoint(x: -ex * hn, y: -ey * hn), endPoint: CGPoint(x: -ex * (hn + span), y: -ey * (hn + span))))
            g.blendMode = .normal
        }
        slice(&g, 0, 0)
        for k in nearSlices { slice(&g, k, near * rel.z[k]) }
        /* the front fades out over its outer band into the slices under it */
        if frontA > 0.01 {
            g.transform = capM
            g.opacity = frontA
            g.draw(capSrc, in: squareRect)
            g.opacity = 1
        }
    }

    /* the halo over the silhouette: laid over the body while the stretched
       outline fits the turned stack, cut into it and shown behind it as the
       fit goes */
    let mxT = near * dxs, myT = near * dys
    let stale = abs(mxT - st.missAt.0) > 1.5 * MISS_STEP || abs(myT - st.missAt.1) > 1.5 * MISS_STEP
    let measured: (Double, Double)? = dl1 > 1e-4 ? haloMiss(form, call.cgPath, rel, K, haloS, mxT, myT, sync: rig.still || stale) : (0, 0)
    if let m = measured {
        st.miss = m
        st.missAt = (mxT, myT)
    }
    let (cut, over) = st.miss
    let miss = max(cut, over)
    var back = smooth(HALO_FIT / 2, 2 * HALO_FIT, miss), gone = smooth(HALO_FIT / 2, HALO_FIT, over)
    let quick = abs(mxT - st.turnAt.0) > MISS_STEP || abs(myT - st.turnAt.1) > MISS_STEP
    st.turnAt = (mxT, myT)
    let settle = !rig.still && !quick
    if settle, let fd = st.fade {
        func ease(_ a: Double, _ b: Double) -> Double { abs(b - a) < 0.02 ? b : a + (b - a) * 0.2 }
        back = ease(fd.0, back)
        gone = ease(fd.1, gone)
    }
    st.fade = (back, gone)
    let haloT = haloS.concatenating(at(0))
    let layTo = (1 - smooth(0, HALO_BLEND, back)) * (1 - gone)
    st.lay = !settle ? layTo : st.lay + max(-HALO_EASE, min(HALO_EASE, layTo - st.lay))
    let lay = st.lay
    /* the veil comes in with the turn: face-on it would only lay the halo's
       lighter colour over the edge's own shade */
    let veil = HALO_VEIL * min(1, dl1 / 0.2)
    /* (a context's destination-atop reaches only as far as the halo's
       square, where a canvas's clears the body past it too: the body never
       reaches past the square the halo is stretched to fit) */
    func laid(_ g: inout GraphicsContext) {
        g.transform = haloT
        g.blendMode = .destinationAtop
        fringedSprite(&g)
        if veil > 0.01 {
            g.blendMode = .sourceAtop
            g.opacity = veil
            bandSprite(&g)
            g.opacity = 1
        }
        g.blendMode = .normal
    }
    func cutAway(_ g: inout GraphicsContext) {
        if back < 1, let cutImg = img(furCut(fur)) {
            /* the cut grown about the outline's centre */
            let fk = 1 + (back * (miss + HALO_FIT)) / 25, cx = rel.cx[0], cyC = rel.cy[0]
            g.transform = CGAffineTransform(a: fk, b: 0, c: 0, d: fk, tx: cx * (1 - fk), ty: cyC * (1 - fk)).concatenating(haloT)
            g.blendMode = .destinationOut
            g.draw(cutImg, in: squareRect)
        }
        if gone < 1 {
            g.transform = haloT
            g.opacity = 1 - gone
            g.blendMode = .destinationOver
            fringedSprite(&g)
            g.opacity = 1
        }
        g.blendMode = .normal
    }

    /* the pile over the whole body at once, only where it is */
    let lin = call.base.linear
    let lum = pow(0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2], 1 / 2.2)
    let darkFilm = img(gapFilm(fur, call.base, mat.vivid) ?? fur.dark), tips = img(tipFilm(fur, call.base, mat.vivid) ?? fur.light)
    /* the fibres' own light: baked for the front seen head-on, so it gives
       way as the body turns; on a small avatar single fibres are finer than its pixels */
    let sheenA = rig.dev < 160 ? 0 : face >= 0.88 ? 1 : face <= 0.55 ? 0 : (face - 0.55) / 0.33
    let sheen = sheenA > 0.01 ? img(sheenFilm(fur, call.base, mat)) : nil
    /* the pile's tops stand over its hollows: the film's light part is laid
       that much further along the turn than its dark part */
    let lift = near * PILE_H * call.fur.length
    let capT = capStretch.concatenating(rot).concatenating(CGAffineTransform(translationX: lift * sy, y: -lift * cy * sp)).concatenating(ctm)
    let filmRect = CGRect(x: -PAD - FILM_M, y: -PAD - FILM_M, width: FILM_SPAN, height: FILM_SPAN)
    func layFilm(_ g: inout GraphicsContext, _ M: CGAffineTransform, _ a: Double, _ withSheen: Bool, _ T: CGAffineTransform? = nil) {
        g.transform = M
        g.opacity = a
        if let darkFilm = darkFilm { g.draw(darkFilm, in: filmRect) }
        if let T = T { g.transform = T }
        g.opacity = a * (0.25 + 0.75 * lum)
        if let tips = tips { g.draw(tips, in: filmRect) }
        if withSheen, let sheen = sheen {
            g.opacity = a * sheenA
            g.draw(sheen, in: filmRect)
        }
        g.opacity = 1
    }
    /* turned far round, the pile is laid square to the view over the whole
       turned body instead, at its own size, about the slices' reach's middle */
    let sideU = face >= 0.62 ? 0 : face <= 0.36 ? 1 : (0.62 - face) / 0.26
    var bx0 = Double.infinity, by0 = Double.infinity, bx1 = -Double.infinity, by1 = -Double.infinity
    if sideU > 0 {
        for z in [-rel.top, rel.top] {
            let t = at(z)
            for x in [-PAD, 100 + PAD] { for y in [-PAD, 100 + PAD] {
                let p = CGPoint(x: x, y: y).applying(t)
                bx0 = min(bx0, Double(p.x)); bx1 = max(bx1, Double(p.x)); by0 = min(by0, Double(p.y)); by1 = max(by1, Double(p.y))
            } }
        }
    }
    func films(_ g: inout GraphicsContext) {
        g.blendMode = .sourceAtop
        if sideU < 1 { layFilm(&g, capM, 1 - sideU, true, capT) }
        if sideU > 0 {
            let k = rig.dev / 100 / rig.scale, cxs = (bx0 + bx1) / 2, cys = (by0 + by1) / 2
            layFilm(&g, CGAffineTransform(a: k, b: 0, c: 0, d: k, tx: cxs - 50 * k, ty: cys - 50 * k), sideU, false)
        }
        g.blendMode = .normal
    }

    /* the buffer: the body, its halo, the pile; laid over (lay 1), cut
       (lay 0), or (1 − lay) of the cut plus lay of the halo laid over */
    let laidOnly = lay >= 1
    layer(&ctx) { g in
        if laidOnly || lay <= 0 {
            body(&g)
            if laidOnly { laid(&g) } else { cutAway(&g) }
        } else {
            /* both premultiplied: the cut at 1 − lay, plus the laid at lay */
            g.opacity = 1 - lay
            layer(&g) { a in
                body(&a)
                cutAway(&a)
            }
            g.blendMode = .plusLighter
            g.opacity = lay
            layer(&g) { b in
                body(&b)
                laid(&b)
            }
            g.blendMode = .normal
            g.opacity = 1
        }
        films(&g)
    }
    ctx.transform = ctm
    return true
}

/// The matcap for this frame's light and view, rebuilt once a direction
/// has moved a bin, cross-faded from the last over as many frames as the
/// last bin took (a still frame shows the new one at once).
private func updateMatcap(_ st: FabricState, _ f: FabricFrame, _ rig: FabricRig, _ base: BotColor, _ mat: FabricMaterial) {
    if moved(f.L, st.L) || moved(f.V, st.V) || rig.lx != st.lx || rig.ly != st.ly || base != st.base || mat != st.mat || moved(f.K, st.K) {
        if st.version > 0 { st.mcPrev = st.mcMix }
        buildFabricMatcap(&st.mc, base.linear, f, mat)
        st.matcapBuilds += 1
        if st.version == 0 || rig.still {
            st.mcMix = st.mc
            st.blendT = 1
        } else {
            st.blendFrames = min(10, max(1, st.sinceBuild))
            st.blendT = 0
        }
        st.sinceBuild = 0
        st.mixVersion += 1
        st.L = f.L; st.V = f.V; st.K = f.K
        st.lx = rig.lx; st.ly = rig.ly
        st.base = base
        st.mat = mat
        st.version += 1
    }
    st.sinceBuild += 1
    if st.blendT < 1 {
        st.blendT = min(1, st.blendT + 1 / Double(st.blendFrames))
        let e = Float(st.blendT >= 1 ? 1 : st.blendT * st.blendT * (3 - 2 * st.blendT))
        st.mcPrev.withUnsafeBufferPointer { ap in st.mc.withUnsafeBufferPointer { bp in st.mcMix.withUnsafeMutableBufferPointer { op in
            let a = ap.baseAddress!, b = bp.baseAddress!, o = op.baseAddress!
            for i in 0..<(MM * 3) { o[i] = a[i] + (b[i] - a[i]) * e }
        } } }
        st.mixVersion += 1
    }
}
