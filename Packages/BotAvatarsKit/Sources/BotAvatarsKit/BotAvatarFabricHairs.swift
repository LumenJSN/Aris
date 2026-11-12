import CoreGraphics
import Foundation

/* The pile's single hairs, the fuzz along the edge, the silhouette's tufts
   and the halo. A port of furJob's steps after the fleece in plastic.ts at
   bfb396b: the hair kinds, the fringe, the tufts, the halo's haze and its
   mask and core. The canvas strokes are Core Graphics strokes on bitmaps
   whose coordinates run y down, as a canvas's do. */

private let PAD = BOT_AVATAR_PAD, SPAN = BOT_AVATAR_SPAN

/// One kind of single hair (see `kinds` in `hairs()`).
private struct HairKind {
    var count: Double, len: Double, vary: Double, endOn: Double, width: Double, spread: Double, alpha: Double, deep: Double, lift: Double
    var light: Double, dark: Double, bend: Double, clump: (Int, Int), clumpW: Double, shadow: Double, shadowW: Double, over: Double, crowd: Bool, short: Double
}

extension FabricBitmap {
    /// A canvas stroke: `gray` 0 black or 1 white at `colorAlpha`, the
    /// canvas's globalAlpha `alpha` and its composite op, offset by (ox, oy).
    func stroke(_ path: CGPath, width: Double, gray: Double, colorAlpha: Double = 1, alpha: Double, blend: CGBlendMode = .normal, offset: Double = 0) {
        guard let g = ctx, !path.isEmpty else { return }
        g.saveGState()
        g.translateBy(x: offset, y: offset)
        g.setLineWidth(width)
        g.setStrokeColor(gray: gray, alpha: colorAlpha)
        g.setAlpha(alpha)
        g.setBlendMode(blend)
        g.addPath(path)
        g.strokePath()
        g.restoreGState()
    }
}

extension FurBake {
    /* ── 2. single hairs over the fleece, at two scales ── */

    /// Guard hairs: sparse, longer fibres combed with the flow but messily.
    /// Fine hairs: many short single fibres of mixed length and curl,
    /// gathered in twos and threes — only on a pile large enough to hold
    /// them, crowding toward the outline. Each runs from its root, deep in
    /// the pile and in its shade, to its tip, up in the light; strokes are
    /// bucketed by shade.
    func hairs() {
        let SHADES = 16
        let area = FILM_SPAN * FILM_SPAN
        let kinds = [
            HairKind(count: 0.12, len: 1.2, vary: 1.0, endOn: 0.6, width: 0.09, spread: 30, alpha: 0.4, deep: 1, lift: 0.25, light: 0.46, dark: 0.34, bend: 0.93, clump: (1, 0), clumpW: 0, shadow: 0, shadowW: 1, over: 0, crowd: false, short: 0),
            HairKind(count: 0.4 * fine, len: 0.9, vary: 1.2, endOn: 0.35, width: 0.13, spread: 100, alpha: 0.26, deep: 0.2, lift: 0.18, light: 0.55, dark: 0.06, bend: 1.2, clump: (1, Int(jsRound(1 + 2 * clumps))), clumpW: 0.08 + 0.07 * clumps, shadow: 0.25, shadowW: 2, over: 0.25, crowd: true, short: 1),
        ]
        func shadeOf(_ v: Double) -> Int { min(SHADES - 1, max(0, Int(jsRound(((max(-1, min(1, v)) + 1) / 2) * Double(SHADES - 1))))) }
        func glintOf(_ v: Double) -> Int { min(GLINTS - 1, Int(v * Double(GLINTS))) }
        let SEGS = 4
        var hx = [Double](repeating: 0, count: SEGS + 1), hy = hx
        let filmOff = FILM_M * px
        for L in kinds {
            if L.count <= 0 { continue }
            /* a dense kind goes in more, smaller steps (on the web, idle tasks) */
            let perRoot = Double(L.clump.0) + 0.5 * Double(L.clump.1)
            let parts = max(1, Int(((area * L.count * kDen * (L.crowd ? 2 : 1) * (0.5 + 0.5 * perRoot)) / 9000).rounded(.up)))
            for part in 0..<parts {
                let buckets = (0..<SHADES).map { _ in CGMutablePath() }
                let glints = (0..<GLINTS).map { _ in CGMutablePath() }, backs = (0..<GLINTS).map { _ in CGMutablePath() }
                let shades = (0..<3).map { _ in CGMutablePath() }
                let over = CGMutablePath()
                /* crowding: twice the tries, kept as the surface faces away */
                let count = Int(jsRound((area * L.count * kDen * (L.crowd ? 2 : 1)) / Double(parts)))
                for n in 0..<count {
                    let X = rand.next() * FILM_SPAN - O, Y = rand.next() * FILM_SPAN - O
                    let r0 = rand.next(), r1 = rand.next(), r2 = rand.next(), r3 = rand.next(), r4 = rand.next(), r5 = rand.next()
                    /* toward the film's own edge the hairs thin out with the fleece */
                    if r5 * 8 > min(X + O, FILM_SPAN - O - X, Y + O, FILM_SPAN - O - Y) { continue }
                    if L.crowd && r5 > (sdAt(X, Y) > 0 ? 0.5 / max(0.25, gridAt(nZg, X, Y)) : 0.5) { continue }
                    /* with the strand as seen: end-on where the surface faces
                       the viewer, side-on where it turns away */
                    let (fx, fy) = dirAt(X, Y)
                    let tiltS = gridAt(tiltG, X, Y), vl = gridAt(foreG, X, Y) / PILE_COS
                    let ang = (r1 - 0.5) * (0.6 + 0.8 * curl) * (1 - 0.5 * tiltS)
                    let ca = cos(ang), sa = sin(ang)
                    let ux = fx * ca - fy * sa, uy = fx * sa + fy * ca
                    /* mostly the kind's length, now and then one half as long again */
                    let longer = r2 < 0.1 ? 1.35 + 0.6 * r3 : 1
                    let len = (L.len + L.vary * r3 * r3) * px * kLen * longer * vl * (1 - L.endOn + 1.25 * L.endOn * tiltS)
                    fibreLight(X, Y, ux, uy, 0.1 + 0.5 * hash2(n, 7 + part))
                    /* the clump's own shade */
                    var v = 0.22 * lockAt(lock, X, Y) + 0.3 * lockAt(lockLit, X, Y)
                    let lit = r0 < L.light * (0.4 + 0.6 * fib[2])
                    if lit { v += 0.2 + 0.28 * r4 } else if r0 < L.light + L.dark { v -= 0.2 + 0.28 * r4 }
                    v += L.lift
                    v += 0.45 * (fib[2] - 0.5) - 0.35 * fib[8]
                    if v > 0 { v *= 0.3 + 0.7 * fib[2] }
                    let deepen = 0.15 * (1 - fib[2])
                    let x0 = (X + PAD) * px, y0 = (Y + PAD) * px
                    /* the two bends: mostly one arc, now and then an S */
                    let b1 = (rand.next() - 0.5) * L.bend * curl * len, b2 = r4 < 0.3 ? -0.6 * b1 : b1 * (0.6 + 0.8 * rand.next())
                    /* a clump: hairs rooted side by side across the flow, gathering toward one tip */
                    let hairsN = L.clump.0 + Int(rand.next() * Double(L.clump.1 + 1))
                    let wC = L.clumpW * px * min(1.5, kLen)
                    for k in 0..<hairsN {
                        let o = hairsN > 1 ? rand.next() - 0.5 : 0
                        let f = hairsN > 1 ? 0.7 + 0.3 * rand.next() : 1
                        let j = hairsN > 1 ? (rand.next() - 0.5) * 0.3 : 0
                        let rx = x0 - uy * o * wC, ry = y0 + ux * o * wC
                        let lk = len * f, e1 = b1 + j * lk, e2 = b2 + j * lk - o * wC * 0.7
                        let c1x = rx + ux * lk * 0.33 - uy * e1, c1y = ry + uy * lk * 0.33 + ux * e1
                        let c2x = rx + ux * lk * 0.67 - uy * e2, c2y = ry + uy * lk * 0.67 + ux * e2
                        let x1 = rx + ux * lk - uy * (b2 - o * wC * 0.75), y1 = ry + uy * lk + ux * (b2 - o * wC * 0.75)
                        let sg = lk < 4 ? 2 : lk < 10 ? 3 : SEGS
                        for s in 0...sg {
                            let t = Double(s) / Double(sg), q = 1 - t
                            let a = q * q * q, b = 3 * q * q * t, c = 3 * q * t * t, d = t * t * t
                            hx[s] = a * rx + b * c1x + c * c2x + d * x1
                            hy[s] = a * ry + b * c1y + c * c2y + d * y1
                        }
                        /* root in the pile's shade, tip in the light */
                        let vh = v + (hairsN > 1 ? (rand.next() - 0.5) * 0.25 : 0), rise = 0.3 + 0.15 * fib[2]
                        for s in 0..<sg {
                            let bk = buckets[shadeOf(vh - 0.3 - deepen * (1 - Double(s) / Double(sg)) + (rise * (Double(s) + 0.5)) / Double(sg))]
                            bk.move(to: CGPoint(x: hx[s], y: hy[s]))
                            bk.addLine(to: CGPoint(x: hx[s + 1], y: hy[s + 1]))
                        }
                        if lit && L.over > 0 {
                            over.move(to: CGPoint(x: hx[1], y: hy[1]))
                            for s in 2...sg { over.addLine(to: CGPoint(x: hx[s], y: hy[s])) }
                        }
                        /* the clump's shadow, once, along its middle hair */
                        if k == 0 && L.shadow > 0 && fib[2] > 0.25 && v > -0.2 {
                            let kk = L.shadow * px * min(1, kLen), sh = shades[min(2, Int((fib[2] - 0.25) * 4))]
                            for s in 1...sg {
                                let t = Double(s) / Double(sg), ox = -Lx * kk * t, oy = -Ly * kk * t + 0.3 * kk * t
                                if s == 1 { sh.move(to: CGPoint(x: hx[0], y: hy[0])) }
                                sh.addLine(to: CGPoint(x: hx[s] + ox, y: hy[s] + oy))
                            }
                        }
                        let h = sg >> 1
                        if fib[0] > 0.3 {
                            let gb = glints[glintOf(fib[0])]
                            gb.move(to: CGPoint(x: hx[h], y: hy[h]))
                            for s in (h + 1)...sg { gb.addLine(to: CGPoint(x: hx[s], y: hy[s])) }
                        }
                        if fib[1] > 0.1 {
                            let bb = backs[glintOf(fib[1])]
                            bb.move(to: CGPoint(x: hx[h], y: hy[h]))
                            for s in (h + 1)...sg { bb.addLine(to: CGPoint(x: hx[s], y: hy[s])) }
                        }
                    }
                }
                let shortK = pow(min(1, kLen), L.short)
                let lw = max(0.45, L.width * px * (0.5 + 0.5 * shortK))
                /* first what the hairs hide and the shadows they cast, then the hairs */
                if L.over > 0 { dark.stroke(over, width: lw, gray: 0, alpha: L.over * shortK, blend: .destinationOut, offset: filmOff) }
                if L.shadow > 0 {
                    /* a clump's shadow is soft: wider than a hair, and faint */
                    for i in 0..<3 { dark.stroke(shades[i], width: lw * L.shadowW, gray: 0, alpha: 0.03 * Double(i + 1) * shortK, offset: filmOff) }
                }
                /* a grey stroke as the film's black or white at the matching alpha */
                for i in 0..<SHADES {
                    let v = FUR_MID + ((Double(i) / Double(SHADES - 1)) * 2 - 1) * L.spread
                    let a = L.alpha * shortK * (v < FUR_MID ? L.deep * (1 - v / FUR_MID) : (v - FUR_MID) / (255 - FUR_MID))
                    (v < FUR_MID ? dark : light).stroke(buckets[i], width: lw, gray: v < FUR_MID ? 0 : 1, alpha: a, offset: filmOff)
                }
                for i in 0..<GLINTS {
                    glint.stroke(glints[i], width: lw, gray: 1, alpha: (0.4 * (Double(i) + 0.5)) / Double(GLINTS), offset: filmOff)
                    back.stroke(backs[i], width: lw, gray: 1, alpha: (0.8 * (Double(i) + 0.5)) / Double(GLINTS), offset: filmOff)
                }
            }
        }
    }

    /* ── 3. the fuzz and the tufts ── */

    /// The fuzz: fibres rooted just inside the edge, standing out past it —
    /// many, very fine, mostly short, leaning with the flow. Then the
    /// silhouette's tufts: a few hairs each from roots side by side just
    /// inside the outline, standing out, bending over with the flow and
    /// gravity, gathering toward one tip. Then both stroked into the films.
    func fuzzAndTufts() {
        let cu = SPAN / Double(N)
        for i in 0..<(N * N) where form.sd[i] > -1.6 && form.sd[i] < 2.2 { cells.append(i) }
        if cells.isEmpty { return }
        /* fewer on a small pile, and where the pile is fine enough for the tufts to carry the silhouette */
        let edgeTries = Int(jsRound(Double(cells.count) * cu * cu * 24 * (0.3 + 1.4 * fuzz) * kDen.squareRoot() * (0.5 + 0.5 * min(1, Double(R) / 512)) * (1 - 0.55 * fine)))
        let FRINGE_PARTS = 2
        for part in 0..<FRINGE_PARTS {
            /* the same draws in the same order as the web's two steps */
            for _ in ((edgeTries * part) / FRINGE_PARTS)..<((edgeTries * (part + 1)) / FRINGE_PARTS) { fuzzHair(cu) }
        }
        tuftHairs(cu)
        strokeEdge()
    }

    private func fuzzHair(_ cu: Double) {
        let c = cells[Int(rand.next() * Double(cells.count))]
        let X = (Double(c % N) + rand.next()) * cu - PAD, Y = (Double(c / N) + rand.next()) * cu - PAD
        let d0 = sdAt(X, Y)
        if d0 < -1.2 || d0 > 1.8 { return }
        let d = d0 + tuftAt(X, Y)
        if d < -0.2 || d > 1.2 { return }
        let (fx, fy) = flow(X, Y)
        let (ox, oy) = outward(X, Y)
        let ang = (rand.next() - 0.5) * 1.1
        let ca = cos(ang), sa = sin(ang)
        var ux = fx * ca - fy * sa, uy = fx * sa + fy * ca
        let r1 = rand.next()
        /* hanging hairs are longer below and at the sides than on top */
        let hang = 1 + 0.5 * gravity * max(0, oy) - 0.35 * gravity * max(0, -oy)
        var fl = (0.3 + 1.5 * r1 * r1 * r1) * px * kLen * (0.5 + fuzz) * hang
        let x0 = (X + PAD) * px, y0 = (Y + PAD) * px
        var bend = (rand.next() - 0.5) * 1.17 * curl * fl
        /* a few flyaways on top: out over the edge, then arching down */
        if oy < -0.3 && rand.next() < 0.06 * (0.3 + fuzz) {
            ux = ox * 0.8 + (rand.next() - 0.5) * 0.6
            uy = oy * 0.8
            fl *= 1.2
            bend = (rand.next() < 0.5 ? -1 : 1) * (0.25 + 0.3 * gravity) * fl
        }
        fringe.move(to: CGPoint(x: x0, y: y0))
        /* and the tip sags a little more under its own weight */
        let qx = x0 + ux * fl * 0.5 - uy * bend, qy = y0 + uy * fl * 0.5 + ux * bend, ex = x0 + ux * fl, ey = y0 + uy * fl + gravity * fl * 0.25
        fringe.addQuadCurve(to: CGPoint(x: ex, y: ey), control: CGPoint(x: qx, y: qy))
        fibreLight(X, Y, ux, uy, 0.3)
        if fib[1] > 0.08 {
            let fb = fringeBack[min(GLINTS - 1, Int(fib[1] * Double(GLINTS)))]
            fb.move(to: CGPoint(x: x0, y: y0))
            fb.addQuadCurve(to: CGPoint(x: ex, y: ey), control: CGPoint(x: qx, y: qy))
        }
    }

    private func tuftHairs(_ cu: Double) {
        let band = Double(cells.count) * cu * cu, around = band / 3.8
        let count = Int(jsRound((around / (0.45 + 0.3 * kLen)) * (0.3 + 0.8 * fuzz) * kDen.squareRoot() * (1 + 0.6 * fine)))
        var n = 0, tries = 0
        while n < count && tries < 6 * count {
            tries += 1
            let c = cells[Int(rand.next() * Double(cells.count))]
            let X = (Double(c % N) + rand.next()) * cu - PAD, Y = (Double(c / N) + rand.next()) * cu - PAD
            let r0 = rand.next(), r1 = rand.next(), r2 = rand.next(), r3 = rand.next()
            let d0 = sdAt(X, Y)
            if d0 < -0.5 || d0 > 1.6 { continue }
            let d = d0 + tuftAt(X, Y)
            if d < 0 || d > 0.9 { continue }
            if lockAt(lock, X, Y) < -0.4 + 0.8 * r3 { continue }
            n += 1
            let (fx, fy) = flow(X, Y)
            let (ox, oy) = outward(X, Y)
            /* it leaves the surface standing out, then bends over with the flow and down */
            let a = (r0 - 0.5) * 0.8 * (0.5 + curl), ca = cos(a), sa = sin(a)
            var sx = 0.75 * ox + 0.25 * fx, sy = 0.75 * oy + 0.25 * fy
            var ex = 0.55 * fx + 0.45 * ox, ey = 0.55 * fy + 0.45 * oy + 0.35 * gravity
            var sl = (sx * sx + sy * sy).squareRoot(), el = (ex * ex + ey * ey).squareRoot()
            if sl == 0 { sl = 1 }
            if el == 0 { el = 1 }
            (sx, sy) = ((sx * ca - sy * sa) / sl, (sx * sa + sy * ca) / sl)
            (ex, ey) = ((ex * ca - ey * sa) / el, (ex * sa + ey * ca) / el)
            let hang = 1 + 0.5 * gravity * max(0, oy) - 0.35 * gravity * max(0, -oy)
            let Lt = (0.5 + 1.1 * r1 * r1) * px * kLen * (0.5 + fuzz) * hang
            let wT = (0.3 + 0.35 * r2) * px * min(1.5, kLen)
            let x0 = (X + PAD) * px, y0 = (Y + PAD) * px
            let cx = x0 + sx * Lt * 0.5, cy = y0 + sy * Lt * 0.5
            let tx = x0 + (sx * 0.4 + ex * 0.6) * Lt, ty = y0 + (sy * 0.4 + ey * 0.6) * Lt
            let qx = -sy, qy = sx
            fibreLight(X, Y, ex, ey, 0.4)
            let fb = fib[1] > 0.08 ? tuftBack[min(GLINTS - 1, Int(fib[1] * Double(GLINTS)))] : nil
            let tt = tuftTips[min(2, Int(fib[2] * 3))]
            let hairsN = 4 + Int(rand.next() * 5)
            for _ in 0..<hairsN {
                let o = rand.next() - 0.5, f = 0.7 + 0.3 * rand.next(), w = (rand.next() - 0.5) * 0.35
                let hx0 = x0 + qx * o * wT, hy0 = y0 + qy * o * wT
                let hcx = cx + qx * o * wT * 0.6, hcy = cy + qy * o * wT * 0.6
                let htx = hx0 + (tx + qx * (o * 0.25 + w) * wT - hx0) * f, hty = hy0 + (ty + qy * (o * 0.25 + w) * wT - hy0) * f
                tufts.move(to: CGPoint(x: hx0, y: hy0))
                tufts.addQuadCurve(to: CGPoint(x: htx, y: hty), control: CGPoint(x: hcx, y: hcy))
                /* the outer half, up in the light, for the tips' film */
                let mx = 0.25 * hx0 + 0.5 * hcx + 0.25 * htx, my = 0.25 * hy0 + 0.5 * hcy + 0.25 * hty
                tt.move(to: CGPoint(x: mx, y: my))
                tt.addQuadCurve(to: CGPoint(x: htx, y: hty), control: CGPoint(x: 0.5 * (hcx + htx), y: 0.5 * (hcy + hty)))
                if let fb = fb {
                    fb.move(to: CGPoint(x: mx, y: my))
                    fb.addQuadCurve(to: CGPoint(x: htx, y: hty), control: CGPoint(x: 0.5 * (hcx + htx), y: 0.5 * (hcy + hty)))
                }
            }
        }
    }

    /// The tufts' tips a touch lighter and clear of the gaps' shade; the
    /// edge hairs seen side-on against the light, likewise.
    private func strokeEdge() {
        let off = FILM_M * px
        let tw = max(0.4, 0.11 * px)
        for i in 0..<3 {
            dark.stroke(tuftTips[i], width: tw, gray: 0, alpha: 0.6, blend: .destinationOut, offset: off)
            light.stroke(tuftTips[i], width: tw, gray: 1, alpha: 0.08 + 0.11 * Double(i), offset: off)
        }
        for i in 0..<GLINTS { back.stroke(tuftBack[i], width: tw, gray: 1, alpha: (Double(i) + 0.5) / Double(GLINTS), offset: off) }
        let fw = max(0.35, 0.08 * px)
        light.stroke(fringe, width: fw, gray: 1, alpha: 0.5 * ((140 - FUR_MID) / (255 - FUR_MID)), offset: off)
        for i in 0..<GLINTS { back.stroke(fringeBack[i], width: fw, gray: 1, alpha: (Double(i) + 0.5) / Double(GLINTS), offset: off) }
        dark.stroke(fringe, width: fw, gray: 0, alpha: 0.7, blend: .destinationOut, offset: off)
    }

    /* ── 4. the halo ── */

    /// The body's coverage laid over the silhouette of the whole turned
    /// body: solid inside, to the outline; past it the pile's outermost
    /// tips, a haze of fine hairs thinning outward, streaked along the flow
    /// from the fleece's own noise, with the fuzz's and the tufts' hairs
    /// standing in it. Also the haze's light and the body's core.
    func halo() {
        var mi = [UInt8](repeating: 0, count: R * R), zi = mi, ci = mi
        let hOut = 0.5 + 1.2 * fuzz, reachOut = hOut + tuftK
        let haloA = HALO_A * (1 - 0.6 * fine), haloStreak = HALO_STREAK * (1 + 1.2 * fine)
        let HALO_CORE = FABRIC_HALO_CORE
        let hn = max(1, Int(jsRound(HALO_HAIR * kLen * px))), hs1 = Double(hn + 1)
        let hsd = (W_SD * (1 + (Double(hn) * (2 * Double(hn) + 1)) / (3 * hs1)).squareRoot()) / hs1
        let off = Int(jsRound(FILM_M * px))
        for y in 0..<R {
            let Y = (Double(y) + 0.5) / px - PAD
            for x in 0..<R {
                let X = (Double(x) + 0.5) / px - PAD
                let k = y * R + x
                let d0 = sdAt(X, Y)
                if d0 >= tuftK + HALO_CORE {
                    mi[k] = 255; ci[k] = 255
                    continue
                }
                let d = d0 <= -reachOut ? d0 : d0 + tuftAt(X, Y)
                if d >= 0 {
                    mi[k] = 255
                    ci[k] = byte(jsRound(255 * smooth(0.25 * HALO_CORE, HALO_CORE, d)))
                    continue
                }
                /* past the outline the hairs are lit, the further out the more,
                   most where the halo faces the back light */
                let z = min(1, -d / (2 * hOut))
                let nB = gridAt(nXg, X, Y) * B3[0] + gridAt(nYg, X, Y) * B3[1]
                zi[k] = byte(jsRound(255 * HALO_LIFT * z * z * (3 - 2 * z) * (0.45 + 0.55 * smooth(-0.3, 0.6, nB))))
                if d <= -hOut { continue }
                let o = 1 + d / hOut, f = o * o * (3 - 2 * o)
                let (ux, uy) = freeDirAt(X, Y)
                var acc = 0.0
                for t in -hn...hn {
                    let sx = Int(jsRound(Double(x + off) + ux * Double(t))), sy = Int(jsRound(Double(y + off) + uy * Double(t)))
                    acc += (sx < 0 || sy < 0 || sx >= Rb || sy >= Rb ? W_MEAN : Double(white[sy * Rb + sx])) * (1 - Double(abs(t)) / hs1)
                }
                let strand = (acc / hs1 - W_MEAN) / hsd
                mi[k] = byte(jsRound(255 * max(0, min(1, f * (haloA + haloStreak * strand)))))
            }
        }
        fur.haze = whiteMaskImage(zi, R)
        /* the mask: the coverage, then the fuzz's and the tufts' whole strands */
        if let p = maskBmp.pixels {
            for i in 0..<(R * R) { let v = mi[i]; p[i * 4] = v; p[i * 4 + 1] = v; p[i * 4 + 2] = v; p[i * 4 + 3] = v }
        }
        maskBmp.stroke(fringe, width: max(0.35, 0.08 * px), gray: 1, colorAlpha: 0.45, alpha: 1)
        maskBmp.stroke(tufts, width: max(0.4, 0.11 * px), gray: 1, colorAlpha: 0.8, alpha: 1)
        fur.mask = maskBmp.image()
        /* the core: black, its alpha what the halo's band leaves of the body */
        let core = FabricBitmap(R)
        if let p = core.pixels { for i in 0..<(R * R) { p[i * 4 + 3] = ci[i] } }
        fur.core = core.image()
    }
}

/// how far in from the outline the halo's band reaches, in design units
let FABRIC_HALO_CORE = 1.2
