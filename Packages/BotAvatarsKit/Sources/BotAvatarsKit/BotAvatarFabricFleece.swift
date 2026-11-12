import CoreGraphics
import Foundation

/* The pile's fleece: every pixel's fibres, lit. A port of furJob's step 3
   in plastic.ts at bfb396b (`fibreLight`, `lockSeen`, the strands' kernels
   and buffer, the fleece pass and the lock height's spread). */

extension FurBake {
    /// The light on single fibres at a design point, for a fibre lying along
    /// (ux, uy) on screen and standing `stand` radians out of the surface:
    /// into `fib` the key's highlight along it [0], the back light it carries
    /// [1], how far the point faces the key at all [2], the even glow of a
    /// soft back light [3]; the body's own normal [4–6] and how far it faces
    /// the key [7]; how deep in a crease or under the body it lies [8]; how
    /// far it is on the body and its halo at all [9]; and the pile's tone [10].
    func fibreLight(_ X: Double, _ Y: Double, _ ux: Double, _ uy: Double, _ stand: Double) {
        /* the grids read at one set of bilinear weights */
        let fx = min(Double(G - 1), max(0, (X + O) / gu - 0.5)), fy = min(Double(G - 1), max(0, (Y + O) / gu - 0.5))
        let x0 = min(G - 2, Int(fx)), y0 = min(G - 2, Int(fy))
        let u = fx - Double(x0), v = fy - Double(y0), j = y0 * G + x0
        let w00 = (1 - u) * (1 - v), w10 = u * (1 - v), w01 = (1 - u) * v, w11 = u * v
        @inline(__always) func read(_ f: [Float]) -> Double {
            Double(f[j]) * w00 + Double(f[j + 1]) * w10 + Double(f[j + G]) * w01 + Double(f[j + G + 1]) * w11
        }
        var nx = read(nXg), ny = read(nYg), nz = read(nZg)
        var nn = (nx * nx + ny * ny + nz * nz).squareRoot()
        if nn == 0 { nn = 1 }
        nx /= nn
        ny /= nn
        nz /= nn
        let nK = nx * K3[0] + ny * K3[1] + nz * K3[2]
        fib[4] = nx
        fib[5] = ny
        fib[6] = nz
        fib[7] = nK
        fib[8] = read(creaseG)
        /* past the halo, under a turned body's side, the tips keep most of
           their light and there is no light on single fibres */
        let on = read(onG)
        fib[9] = on
        fib[10] = read(toneG)
        if on <= 0 {
            fib[0] = 0; fib[1] = 0; fib[3] = 0
            fib[2] = 0.7
            return
        }
        let key = smooth(-0.2, 0.5, nK)
        /* the fibre: the flow laid onto the surface, then raised out of it */
        let along = ux * nx + uy * ny
        var tx = ux - along * nx, ty = uy - along * ny, tz = -along * nz
        let tl = (tx * tx + ty * ty + tz * tz).squareRoot()
        if tl > 1e-3 {
            tx /= tl
            ty /= tl
            tz /= tl
        } else {
            tx = 0; ty = 0; tz = 1
        }
        let cs = cos(stand), sn = sin(stand)
        tx = tx * cs + nx * sn
        ty = ty * cs + ny * sn
        tz = tz * cs + nz * sn
        /* Kajiya–Kay, two reflections as Marschner's: off the fibre's
           surface, sharp, tilted toward the root; and through the fibre and
           back, broad, tilted toward the tip */
        let tH = tx * H3[0] + ty * H3[1] + tz * H3[2], nH = nx * H3[0] + ny * H3[1] + nz * H3[2]
        let a1 = tH - 0.12 * nH, a2 = tH + 0.2 * nH
        let b1 = max(0, 1 - a1 * a1), b2 = b1 * b1, b4 = b2 * b2, b8 = b4 * b4, b16 = b8 * b8
        let c1 = max(0, 1 - a2 * a2), c2 = c1 * c1
        fib[0] = key * (0.85 * b16 * b16 * b4 + 0.15 * c2 * c2)
        /* and brightest where the key grazes the pile */
        fib[0] *= (0.4 + 0.6 * (1 - smooth(0.35, 0.85, nK))) * on
        /* the back light carried through the fibres to the viewer: toward
           the silhouette, on a fibre seen side-on; the underside gets little */
        let side = max(0, 1 - tz * tz).squareRoot()
        let nB = nx * B3[0] + ny * B3[1] + nz * B3[2]
        fib[1] = smooth(-0.3, 0.6, nB) * pow(1 - nz, 1.6) * (0.4 + 0.6 * side) * (1 - 0.6 * max(0, ny)) * on
        /* and as a large soft source gives it: wider, further in, even */
        fib[3] = smooth(-0.5, 0.75, nB) * pow(1 - nz, 0.85) * (1 - 0.6 * max(0, ny)) * on
        fib[2] = key * on + 0.7 * (1 - on)
    }

    /// The lock seen at a film pixel (x, y), design point (X, Y), into
    /// `seen`: its strands' way there, how far along the lock (0 root … 1
    /// tip) and how high in it — with no lock, the flow and a lock's middle.
    func lockSeen(_ x: Int, _ y: Int, _ X: Double, _ Y: Double, _ k: Int) {
        if k < 0 {
            let (ux, uy) = dirAt(X, Y)
            seen[0] = ux
            seen[1] = uy
            seen[2] = 0.5
            seen[3] = 0
            return
        }
        let b = k * LP
        let ax = Double(locks[b + 2]), ay = Double(locks[b + 3]), La = Double(locks[b + 4]), Wa = Double(locks[b + 5]), bend = Double(locks[b + 7])
        let dx = Double(x) + 0.5 - Double(locks[b]), dy = Double(y) + 0.5 - Double(locks[b + 1])
        let s = min(0.995, max(0.005, (dx * ax + dy * ay) / La))
        let ss = s.squareRoot(), w = LOCK_TAPER * ss * (1 - s), dw = LOCK_TAPER * ((0.5 * (1 - s)) / ss - ss)
        let q = max(-1, min(1, ((dy * ax - dx * ay) / Wa - bend * s * s) / w))
        /* a strand keeps its place across the lock as it narrows */
        let sl = max(-1.2, min(1.2, q * dw + 2 * bend * s))
        let ux = La * ax - sl * Wa * ay, uy = La * ay + sl * Wa * ax
        var ul = (ux * ux + uy * uy).squareRoot()
        if ul == 0 { ul = 1 }
        seen[0] = ux / ul
        seen[1] = uy / ul
        seen[2] = s
        seen[3] = lockAlong(s) * (1 - q * q)
    }

    /// the sparse bright noise the strands are drawn from
    func whiteNoise() {
        var i = 0
        for y in 0..<Rb {
            for x in 0..<Rb {
                let h = hash2(x + 911, y + 37)
                white[i] = Float(h * h * h)
                i += 1
            }
        }
    }

    /// For each longest length L, the kernel's weights, and the mean and
    /// spread its sum of the noise has, to bring every length to one contrast.
    func strandKernels() {
        strandW = []
        for L in 0...(2 * strandHalf) {
            var w = [Float](repeating: 0, count: L + 1)
            var m1 = 0.0, v2 = 0.0
            for t in 0...L {
                let tau = L > 0 ? Double(t) / Double(L) : 0, p = tau <= STRAND_SHORT ? 1 : (1 - tau) / (1 - STRAND_SHORT)
                w[t] = Float(1 - STRAND_TAPER * tau)
                let wt = Double(w[t])
                m1 += wt * p * W_MEAN
                v2 += wt * wt * (p / 7 - W_MEAN * W_MEAN * p * p)
            }
            strandW.append(w)
            strandMean[L] = Float(m1)
            strandSd[L] = Float(max(1e-6, v2).squareRoot())
        }
    }

    /// The fine strands first, into a buffer of their own, so the pass after
    /// can read a strand's neighbours: each grows one way from its root down
    /// the flow, its root in the shade of the tips lying over it and its tip
    /// up in the light.
    func strands() {
        white.withUnsafeBufferPointer { wp in
            let white = wp.baseAddress!
            for y in 0..<Rb {
                let Y = (Double(y) + 0.5) / px - O
                var i = y * Rb
                for x in 0..<Rb {
                    defer { i += 1 }
                    let X = (Double(x) + 0.5) / px - O
                    lockSeen(x, y, X, Y, Int(own[i]))
                    let ux = seen[0], uy = seen[1]
                    /* the surface's tilt and the share of a fibre seen */
                    let gx = min(Double(G - 1), max(0, (X + O) / gu - 0.5)), gy = min(Double(G - 1), max(0, (Y + O) / gu - 0.5))
                    let gx0 = min(G - 2, Int(gx)), gy0 = min(G - 2, Int(gy)), gtx = gx - Double(gx0), gty = gy - Double(gy0), gj = gy0 * G + gx0
                    let tilt = (Double(tiltG[gj]) * (1 - gtx) + Double(tiltG[gj + 1]) * gtx) * (1 - gty) + (Double(tiltG[gj + G]) * (1 - gtx) + Double(tiltG[gj + G + 1]) * gtx) * gty
                    let fore = (Double(foreG[gj]) * (1 - gtx) + Double(foreG[gj + 1]) * gtx) * (1 - gty) + (Double(foreG[gj + G]) * (1 - gtx) + Double(foreG[gj + G + 1]) * gtx) * gty
                    let L = 2 * max(1, min(strandHalf, Int(jsRound((Double(strandHalf) * (0.5 + 0.5 * tilt) * fore) / PILE_COS))))
                    let sw = strandW[L]
                    let mean = Double(strandMean[L])
                    var acc = 0.0, accR = 0.0
                    for t in 0...L {
                        let sx = Int(jsRound(Double(x) - ux * Double(t))), sy = Int(jsRound(Double(y) - uy * Double(t)))
                        if sx < 0 || sy < 0 || sx >= Rb || sy >= Rb {
                            acc += mean / Double(L + 1)
                            continue
                        }
                        let m = Double(white[sy * Rb + sx]), f = m * 53.7, Ls = Double(L) * (STRAND_SHORT + (1 - STRAND_SHORT) * (f - floor(f)))
                        if Double(t) <= Ls {
                            acc += m * Double(sw[t])
                            accR += (m * Double(sw[t]) * Double(t)) / (Ls != 0 ? Ls : 1)
                        }
                    }
                    let strand = (acc - mean) / Double(strandSd[L])
                    let along = acc > 1e-4 ? accR / acc : 0.5
                    strandBuf[i] = Float(strand + STRAND_RISE * min(2.5, max(0, strand)) * (along - 0.45))
                }
            }
        }
    }

    /// the key on a surface facing it by n·k, wrapped a little past the terminator
    @inline(__always) func keyOn(_ nk: Double) -> Double {
        let q = (nk + PILE_WRAP) / (1 + PILE_WRAP)
        return q <= 0 ? 0 : q >= 1 ? 1 : difLut[Int(q * Double(FUR_POW_N))]
    }

    /// The fleece: the lock seen at every pixel gives the pile's own surface
    /// and its strands; the key on that surface against the key on the
    /// smooth body is how much lighter or darker the pile is there. Kept as
    /// the film's two parts — darker as black, lighter as white — with the
    /// fibres' own light and the lock's height and light at half the size.
    func fleece() {
        let dd = dark.pixels!, ld = light.pixels!, gd = glint.pixels!, bd = back.pixels!, sd2 = soft.pixels!
        for y in 0..<Rb {
            let Y = (Double(y) + 0.5) / px - O
            for x in 0..<Rb {
                let X = (Double(x) + 0.5) / px - O
                let i = y * Rb + x, k = Int(own[i]), b = k * LP
                lockSeen(x, y, X, Y, k)
                let ux = seen[0], uy = seen[1], s = seen[2], hgt = seen[3]
                /* each strand stands at its own angle */
                fibreLight(X, Y, ux, uy, 0.25 + 0.2 * hgt)
                let nx = fib[4], ny = fib[5], nz = fib[6], nKb = fib[7]
                /* the pile's own surface: the body's, tilted by the slope of
                   the pile's height along the two directions on it */
                let xl0 = x > 0 ? i - 1 : i, xr0 = x < Rb - 1 ? i + 1 : i, yu0 = y > 0 ? i - Rb : i, yd0 = y < Rb - 1 ? i + Rb : i
                let gx = ((Double(pileH[xr0]) - Double(pileH[xl0])) * px) / Double(xr0 - xl0 != 0 ? xr0 - xl0 : 1)
                let gy = ((Double(pileH[yd0]) - Double(pileH[yu0])) * px * Double(Rb)) / Double(yd0 - yu0 != 0 ? yd0 - yu0 : 1)
                let l1 = (nx * nx + ny * ny).squareRoot()
                var t1x = 1.0, t1y = 0.0, t2x = 0.0, t2y = 1.0, t2z = 0.0
                if l1 > 1e-3 {
                    t1x = -ny / l1
                    t1y = nx / l1
                    t2x = (-nz * nx) / l1
                    t2y = (-nz * ny) / l1
                    t2z = l1
                }
                let g1 = max(-1.5, min(1.5, gx * t1x + gy * t1y)), g2 = max(-1.5, min(1.5, gx * t2x + gy * t2y))
                var mx = nx - g1 * t1x - g2 * t2x, my = ny - g1 * t1y - g2 * t2y, mz = nz - g2 * t2z
                var ml = (mx * mx + my * my + mz * mz).squareRoot()
                if ml == 0 { ml = 1 }
                mx /= ml
                my /= ml
                mz /= ml
                /* a fibre catches the key as far as it lies across it */
                var kk = 1.0
                if k >= 0 {
                    let tx = Double(locks[b + 8]), ty = Double(locks[b + 9]), tz = Double(locks[b + 10])
                    let fx = 0.9 * tx + 0.44 * nx, fy = 0.9 * ty + 0.44 * ny, fz = 0.9 * tz + 0.44 * nz
                    var fl = (fx * fx + fy * fy + fz * fz).squareRoot()
                    if fl == 0 { fl = 1 }
                    let fK = (fx * K3[0] + fy * K3[1] + fz * K3[2]) / fl
                    kk = 1 - PILE_KK + PILE_KK * min(1.2, max(0, 1 - fK * fK).squareRoot() / 0.85)
                }
                let nKp = mx * K3[0] + my * K3[1] + mz * K3[2]
                /* the key's shadow: a lock standing higher toward the light */
                let h0 = Double(pileH[i])
                var sh = 1.0
                if nKb > -0.25 {
                    let sinE = min(0.97, max(0.05, nKb)), tanE = sinE / (1 - sinE * sinE).squareRoot()
                    var occ = 0.0
                    for t in 0..<NSH {
                        let sx = x + shX[t], sy = y + shY[t]
                        if sx < 0 || sy < 0 || sx >= Rb || sy >= Rb { break }
                        let o = Double(pileH[sy * Rb + sx]) - h0 - Double(shD[t]) * tanE
                        if o > occ { occ = o }
                    }
                    sh = 1 - PILE_SHADOW * smooth(0, 0.35 * hMax, occ)
                }
                /* the hollows, and a lock's root under the tip lying over it */
                var ao = 1 - PILE_AO * smooth(0, 0.6 * hMax, Double(pileB[i]) - h0)
                if k >= 0 { ao *= 1 - PILE_ROOT * (1 - smooth(0, 0.35, s)) }
                /* the pile against the smooth body, in the same light */
                let fillP = PILE_AMB + PILE_FILL * max(0, mx * F3[0] + my * F3[1] + mz * F3[2])
                let fillB = PILE_AMB + PILE_FILL * max(0, nx * F3[0] + ny * F3[1] + nz * F3[2])
                var r = (ao * (fillP + keyOn(nKp) * sh * kk) * PILE_GAIN) / (fillB + keyOn(nKb))
                if k >= 0 { r *= (1 + 0.15 * s * s) * (1 + 0.08 * (hash2(k, 5) - 0.5)) }
                /* in a crease the room's light hardly reaches the roots */
                let crease = fib[8]
                r *= 1 - PILE_CREASE * crease * (0.6 + 0.4 * smooth(0, 0.6 * hMax, Double(pileB[i]) - h0))
                r = 1 + (r - 1) * depthK
                /* the smooth body's own light here, as the screen shows it */
                let on = fib[9], lq = (fillB + keyOn(nKb)) / PILE_LIT
                let lbs = (lq >= 1 ? 1 : gamLut[Int(lq * Double(FUR_POW_N))]) * on + 0.75 * (1 - on)
                /* matte: the lit side of a lock lifts the colour, but rolls off */
                var m0 = (r > 2.4 ? 2.4 : r).squareRoot()
                if m0 > 1 { m0 = 1 + (m0 - 1) / (1 + 2.5 * lbs * (m0 - 1)) }
                /* the fine strands, and the shadow a strand standing over the
                   pile casts beside it, away from the key */
                let strand = Double(strandBuf[i])
                var cast = 0.0
                if nKb > 0 {
                    let kx = K3[0] - nKb * nx, ky = K3[1] - nKb * ny, kt = (1 - nKb * nKb).squareRoot()
                    let reachS = kt > 1e-3 ? (STRAND_CAST_H * px * min(3, kt / max(0.2, nKb))) / kt : 0
                    let cx = min(Double(Rb) - 1.001, max(0, Double(x) + kx * reachS)), cy = min(Double(Rb) - 1.001, max(0, Double(y) + ky * reachS))
                    let cx0 = Int(cx), cy0 = Int(cy), tx = cx - Double(cx0), ty = cy - Double(cy0), ci = cy0 * Rb + cx0
                    let caster = (Double(strandBuf[ci]) * (1 - tx) + Double(strandBuf[ci + 1]) * tx) * (1 - ty) + (Double(strandBuf[ci + Rb]) * (1 - tx) + Double(strandBuf[ci + Rb + 1]) * tx) * ty
                    cast = max(0, caster - max(0, strand)) * smooth(0, 0.3, nKb)
                }
                var m = m0 * (1 + strandK * (strand * (0.45 + 0.55 * fib[2]) * (0.75 + 0.5 * s) - STRAND_CAST * cast)) + 0.04 * (fib[10] - 0.5) + PILE_BIAS * depthK * on
                /* toward the film's own edge the pile thins out to nothing */
                let edgeD = min(X + O, FILM_SPAN - O - X, Y + O, FILM_SPAN - O - Y)
                let fadeE = edgeD >= 8 ? 1 : edgeD <= 0 ? 0 : (edgeD / 8) * (edgeD / 8) * (3 - (2 * edgeD) / 8)
                m = 1 + (m - 1) * fadeE
                let k4 = i * 4
                if m < 1 {
                    /* darker as the gap film's alpha (black, premultiplied) */
                    dd[k4 + 3] = byte(jsRound(255 * min(1, ((1 - m) * lbs) / max(0.4, lbs - GAP_REF))))
                } else {
                    /* lighter as the tips' film (white, premultiplied) */
                    let a = byte(jsRound(255 * min(1, ((PILE_LIFT * (TIP_TOP - 1) * lbs) / (TIP_TOP - lbs)) * (m - 1) * (1 - 0.7 * crease))))
                    ld[k4] = a; ld[k4 + 1] = a; ld[k4 + 2] = a; ld[k4 + 3] = a
                }
                /* the lock's height and light at half the resolution */
                let lit = max(-2, min(2, 4 * (m0 - 1)))
                let xl = x >> 1, yl = y >> 1
                if xl < Rl && yl < Rl {
                    let j = yl * Rl + xl
                    lock[j] = Float(Double(lock[j]) + 0.25 * h0)
                    lockLit[j] = Float(Double(lockLit[j]) + 0.25 * lit)
                }
                /* the fibres' own light is on the strands standing out and
                   the locks facing the light, not in the gaps between them */
                let tipK = smooth(-0.4, 1, lit) * max(0, min(1.4, 0.65 + 0.25 * strand))
                let ga = byte(jsRound(255 * min(1, fib[0] * tipK)))
                gd[k4] = ga; gd[k4 + 1] = ga; gd[k4 + 2] = ga; gd[k4 + 3] = ga
                let ba = byte(jsRound(255 * min(1, fib[1] * max(0, min(1.6, 0.5 + 0.4 * strand)))))
                bd[k4] = ba; bd[k4 + 1] = ba; bd[k4 + 2] = ba; bd[k4 + 3] = ba
                /* the soft back light's glow, still on the pile */
                let onPile = max(0.55, min(1.3, 0.85 + 0.15 * strand + 0.12 * lit))
                let sa = byte(jsRound(255 * min(1, 0.85 * fib[3] * onPile)))
                sd2[k4] = sa; sd2[k4 + 1] = sa; sd2[k4 + 2] = sa; sd2[k4 + 3] = sa
            }
        }
    }

    /// the half-resolution height brought to one spread, as the tufts read it
    func normaliseLock() {
        let n = Rl * Rl
        var lsum = 0.0, lsum2 = 0.0
        for i in 0..<n {
            lsum += Double(lock[i])
            lsum2 += Double(lock[i]) * Double(lock[i])
        }
        let mean = lsum / Double(n), sdv = max(1e-9, lsum2 / Double(n) - mean * mean).squareRoot()
        for i in 0..<n { lock[i] = Float(max(-2.5, min(2.5, (Double(lock[i]) - mean) / sdv))) }
    }
}

/// A value already rounded, clamped into a byte (a Uint8ClampedArray store).
@inline(__always) func byte(_ v: Double) -> UInt8 { v <= 0 ? 0 : v >= 255 ? 255 : UInt8(v) }
