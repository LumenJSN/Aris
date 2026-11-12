// Tests for the shipped glass of 2026-11-11 (the owner picked private-glass after seeing the six looks side by side).
// The look private-glass is what the notch draws with nothing written; it is the same in every state: the glass is
// there closed too, under one deep black, whose span is what makes a closed notch solid over a camera housing; where
// this macOS lacks a private part the notch draws clear-glass; the outline keeps the same elements in every state, so
// the glass follows it frame by frame.
// Called from main.swift; uses its check(). Nothing is drawn on screen: only the rules, the numbers and the sources.
import CoreGraphics
import Foundation

private typealias L = ArisGlassLook
private typealias P = ArisGlassParts
private typealias G = ArisNotchGlassGeometry

private func glass3Source(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

private func near(_ a: Double, _ b: Double, _ slack: Double = 0.0001) -> Bool { abs(a - b) < slack }

/// A path's elements, by kind, and its points.
private func elements(_ path: CGPath) -> (kinds: [Int32], points: [CGPoint]) {
    var kinds: [Int32] = [], points: [CGPoint] = []
    path.applyWithBlock { element in
        kinds.append(element.pointee.type.rawValue)
        let count: Int
        switch element.pointee.type {
        case .moveToPoint, .addLineToPoint: count = 1
        case .addQuadCurveToPoint: count = 2
        case .addCurveToPoint: count = 3
        default: count = 0
        }
        for i in 0..<count { points.append(element.pointee.points[i]) }
    }
    return (kinds, points)
}

/// The look with nothing written is private-glass, and the others are still there by name.
private func glass3DefaultTests() {
    check(L.fallback == .privateGlass && L(preference: nil) == .privateGlass && L(preference: "") == .privateGlass
          && L(preference: "liquid") == .privateGlass,
          "shipped glass: no preference, an empty one or an unknown name is private-glass")
    check(L(preference: "floor") == .floor && L(preference: "mid") == .mid && L(preference: "before") == .before && L(preference: "regular-glass") == .regularGlass
          && L(preference: "clear-glass") == .clearGlass && L(preference: "private-glass") == .privateGlass && L.allCases.count == 6,
          "shipped glass: the five other looks are kept behind the hidden preference")
    let suite = testSuiteName("aris-glass3-tests")
    guard let defaults = UserDefaults(suiteName: suite) else { check(false, "shipped glass: a defaults suite for the test"); return }
    defaults.removePersistentDomain(forName: suite)
    check(L.current(defaults) == .privateGlass, "shipped glass: with nothing written the notch opens in private-glass")
    defaults.set("floor", forKey: L.preferenceKey)
    check(L.current(defaults) == .floor, "shipped glass: the old look can still be asked for by name")
    defaults.removeObject(forKey: L.preferenceKey)
    check(L.current(defaults) == .privateGlass, "shipped glass: taking the preference away is private-glass again")
    defaults.removePersistentDomain(forName: suite)
    check(L.allCases.filter(\.usesPrivateParts) == [.privateGlass] && L.privateVariant == 11 && L.privateContentLensing == 3,
          "shipped glass: variant 11 and content lensing 3, asked for by private-glass alone")
}

/// What private-glass draws when this macOS lacks a private part: decided part by part, always clear-glass.
private func glass3FallbackTests() {
    check(P.all.missing.isEmpty && P.none.missing == ["glass view", "variant", "lensing", "path", "active appearance"],
          "glass fallback: the five parts are the glass view, the variant, the lensing, the path and the active appearance")
    let all = ArisGlassFallback.decide(.all)
    check(all.privateGlass && all.forcesActiveAppearance && all.look == .privateGlass && all.missing.isEmpty && L.privateGlass.resolved(.all) == .privateGlass,
          "glass fallback: with every part the notch is AppKit's glass with the private settings")
    let parts: [(WritableKeyPath<P, Bool>, String)] = [(\.glassView, "glass view"), (\.variant, "variant"), (\.lensing, "lensing"), (\.path, "path"),
                                                         (\.activeAppearance, "active appearance")]
    for (part, name) in parts {
        var one = P.all
        one[keyPath: part] = false
        let decision = ArisGlassFallback.decide(one)
        check(!decision.privateGlass && !decision.forcesActiveAppearance && decision.look == .clearGlass && decision.missing == [name]
              && L.privateGlass.resolved(one) == .clearGlass,
              "glass fallback: without the \(name) the notch looks like clear-glass, and nothing private stays on")
        check(ArisGlassFallback.logLine(one).contains("missing \(name)") && ArisGlassFallback.logLine(one).contains("clear-glass"),
              "glass fallback: the log names the missing \(name) and the look drawn instead")
    }
    // Every combination of the five: the private glass only when none is missing.
    var privateCount = 0
    for bits in 0..<32 {
        let some = P(glassView: bits & 1 != 0, variant: bits & 2 != 0, lensing: bits & 4 != 0, path: bits & 8 != 0, activeAppearance: bits & 16 != 0)
        let decision = ArisGlassFallback.decide(some)
        if decision.privateGlass { privateCount += 1 }
        check(decision.privateGlass == (bits == 31) && decision.look == (bits == 31 ? .privateGlass : .clearGlass)
              && decision.forcesActiveAppearance == decision.privateGlass && decision.missing.count == 5 - bits.nonzeroBitCount,
              "glass fallback: parts \(bits) of 31 decide \(bits == 31 ? "the private glass" : "clear-glass")")
    }
    check(privateCount == 1, "glass fallback: only one of the 32 combinations draws the private glass")
    check(ArisGlassFallback.logLine(.all).hasPrefix("private-glass: variant true lensing true path true active appearance true"),
          "glass fallback: the log line says which private parts took")
    for look in L.allCases where look != .privateGlass {
        check(look.resolved(.none) == look && look.resolved(.all) == look, "glass fallback: \(look.rawValue) is itself whatever the private parts")
    }
    // The fallback is the deep black and its span over the public clear glass, in every state too.
    check(L.clearGlass.deepBlack && !L.clearGlass.regularMaterial && !L.clearGlass.usesPrivateParts
          && L.clearGlass.stops(height: 400, open: true, glass: true) == L.privateGlass.stops(height: 400, open: true, glass: true)
          && L.clearGlass.stops(height: 32, safeTop: 32, open: false, glass: true) == L.privateGlass.stops(height: 32, safeTop: 32, open: false, glass: true)
          && near(L.clearGlass.span(height: 32, safeTop: 32), L.privateGlass.span(height: 32, safeTop: 32)),
          "glass fallback: clear-glass has the same black, stops and span as private-glass, with public glass")
}

/// The glass is there in every state except hidden; Aris's older looks keep it for the open notch.
private func glass3StateTests() {
    for look in [L.privateGlass, L.clearGlass, L.regularGlass] {
        check(look.showsGlass(open: false, hidden: false, reduceTransparency: false) && look.showsGlass(open: true, hidden: false, reduceTransparency: false),
              "glass states \(look.rawValue): the glass is drawn closed and open")
        check(!look.showsGlass(open: false, hidden: true, reduceTransparency: false) && look.showsGlass(open: true, hidden: true, reduceTransparency: false),
              "glass states \(look.rawValue): no glass while the closed notch is hidden for a full-screen app; opened there, it has its glass")
        check(!look.showsGlass(open: true, hidden: false, reduceTransparency: true) && !look.showsGlass(open: false, hidden: false, reduceTransparency: true),
              "glass states \(look.rawValue): no glass with Reduce Transparency")
        let solid = look.stops(height: 400, open: true, glass: false) + look.stops(height: 32, safeTop: 32, open: false, glass: false)
        check(solid.count == 8 && solid.allSatisfy { $0.alpha == 1 }, "glass states \(look.rawValue): with Reduce Transparency the notch is solid black, open and closed")
        check(look.stops(height: 32, safeTop: 0, open: false, glass: true) == look.stops(height: 32, safeTop: 0, open: true, glass: true),
              "glass states \(look.rawValue): one gradient in every state (nothing changes when it opens)")
    }
    for look in [L.floor, L.mid, L.before] {
        check(!look.showsGlass(open: false, hidden: false, reduceTransparency: false) && look.showsGlass(open: true, hidden: false, reduceTransparency: false)
              && !look.showsGlass(open: true, hidden: false, reduceTransparency: true),
              "glass states \(look.rawValue): Aris's older look keeps its glass for the open notch only")
        check(look.stops(height: 32, open: false, glass: true).allSatisfy { $0.alpha >= 0.98 }, "glass states \(look.rawValue): closed, the older look is solid")
    }
}

/// The deep black on each display: colours 1, 1, .5 at 0, .53, 1 over max(height, safe-area top / 0.53).
private func glass3SpanTests() {
    let look = L.privateGlass
    let stops = look.stops(height: 400, open: true, glass: true)
    check(stops.first == ArisGlassRecipe.Stop(location: 0, alpha: 1) && stops[1] == ArisGlassRecipe.Stop(location: 0.53, alpha: 1)
          && stops.last == ArisGlassRecipe.Stop(location: 1, alpha: 0.5) && stops.count == 4 && look.blackBlue == 0,
          "deep black: #000 at 1, 1 and .5, at 0, .53 and 1")
    check(near(look.tintBlue, 0.02) && near(look.tintAlpha, 0.18), "glass tint: the tint is sRGB(0, 0, .02) at .18")
    // A camera housing: the closed notch is as tall as the safe-area top, so all of it lies in the full black.
    // 14- and 16-inch MacBook Pro at their default sizes have 32 points; scaled to "more space" (1800 wide) 38.
    for safeTop in [32.0, 38.0] {
        let span = look.span(height: safeTop, safeTop: safeTop)
        check(near(span, safeTop / 0.53) && near(safeTop / span, 0.53), "black span: a \(Int(safeTop))-point housing makes the black span \(Int(safeTop)) / 0.53")
        check((0...Int(safeTop)).allSatisfy { near(look.alpha(at: Double($0), height: safeTop, safeTop: safeTop, open: false), 1) },
              "black span: closed on a \(Int(safeTop))-point camera housing, every point of the notch is solid black")
        // Hovered or a band taller than the housing: full black over the housing, thinning only below it.
        let taller = safeTop + 6
        check(near(look.alpha(at: safeTop, height: taller, safeTop: safeTop, open: false), 1)
              && look.alpha(at: taller, height: taller, safeTop: safeTop, open: false) < 1 && look.alpha(at: taller, height: taller, safeTop: safeTop, open: false) > 0.87,
              "black span: 6 points taller than a \(Int(safeTop))-point housing, the housing is still fully covered and the part below starts to thin")
        // Open, the notch is far taller than the housing: the span is the notch's own height.
        check(near(look.span(height: 400, safeTop: safeTop), 400) && near(look.alpha(at: safeTop, height: 400, safeTop: safeTop), 1)
              && near(look.alpha(at: 400, height: 400, safeTop: safeTop), 0.5),
              "black span: open on a \(Int(safeTop))-point housing the black is full to 53 % of the notch and half at its edge")
    }
    check(near(32 / 0.53, 60.377, 0.001) && near(38 / 0.53, 71.698, 0.001), "black span: 32 points span 60.4 and 38 points span 71.7")
    // No camera housing: the span is the notch's own height in every state, so a closed strip thins to half at its edge.
    for height in [24.0, 29.0, 32.0] {
        check(near(look.span(height: height, safeTop: 0), height) && near(look.alpha(at: 0.53 * height, height: height, safeTop: 0, open: false), 1)
              && near(look.alpha(at: height, height: height, safeTop: 0, open: false), 0.5),
              "black span: on a display with no notch a \(Int(height))-point closed strip is full to 53 % and half at its edge, glass showing under it")
    }
    // The gradient layer's end point, 1 − g / H in a layer H tall.
    check(near(Double(G.gradientEnd(height: 32, safeTop: 32, canvasHeight: 820)), 1 - (32 / 0.53) / 820)
          && near(Double(G.gradientEnd(height: 400, safeTop: 32, canvasHeight: 820)), 1 - 400.0 / 820)
          && near(Double(G.gradientEnd(height: 29, safeTop: 0, canvasHeight: 820)), 1 - 29.0 / 820) && G.gradientEnd(height: 29, safeTop: 0, canvasHeight: 0) == 0,
          "deep black: the gradient layer ends 1 − max(height, safe-area top / 0.53) / layer height from its top")
}

/// The silhouette: quarter circles, the radius rule, the clamp, and the same elements in every state.
private func glass3OutlineTests() {
    check(NotchShape.circleHandle == 0.5522847498307936 && NotchShape(circular: 1).handle == 0.5522847498307936,
          "outline: the corners are quarter circles with κ = 0.5522847498307936")
    // The radius rule: 31 when the visual width is at least 502 (body 440 + two shoulders), else 13.
    check(ArisNotchGeometry.openRadii.top == 31 && ArisNotchGeometry.openRadii.bottom == 31 && ArisGlass3Numbers.openVisualWidth == 502
          && ArisBand.radius == 13,
          "radius: the open notch is 440 + 2 · 31 = 502 wide with corners 31; a closed band has 13")
    for camera in [185.0, 204.0, 224.0] as [CGFloat] {
        check(ArisBand.bodyWidth(notchWidth: camera) + 2 * ArisBand.radius < 502, "radius: a closed band on a \(Int(camera))-point camera is under 502 wide, so its corners are 13")
    }
    check(ArisBand.bodyWidth(notchWidth: 189) == 270, "band: 270 wide on a 185-point camera (the closed width is the camera's plus 4)")
    // The clamp: never more than a quarter of the width or half the height.
    let tight = NotchShape(topCornerRadius: 31, bottomCornerRadius: 31, circular: 1)
    check(tight.radii(in: CGRect(x: 0, y: 0, width: 502, height: 400)) == (31, 31) && tight.radii(in: CGRect(x: 0, y: 0, width: 502, height: 40)) == (20, 20)
          && tight.radii(in: CGRect(x: 0, y: 0, width: 80, height: 400)) == (20, 20) && tight.radii(in: CGRect(x: 0, y: 0, width: 0, height: 0)) == (0, 0),
          "outline: each radius is held to min(r, width / 4, height / 2)")
    // The same elements closed, open and anywhere between, so one outline slides into the next point by point.
    let canvas = CGSize(width: 640, height: 820)
    let closed = ArisNotchGlassSample(width: 250, height: 32, top: 13, bottom: 13, openness: 0)
    let open = ArisNotchGlassSample(width: 502, height: 400, top: 31, bottom: 31, openness: 1)
    let from = elements(G.outline(closed, canvas: canvas)), to = elements(G.outline(open, canvas: canvas))
    check(from.kinds == to.kinds && from.points.count == to.points.count && from.kinds.filter { $0 == CGPathElementType.addCurveToPoint.rawValue }.count == 4,
          "outline: closed and open have the same elements, four corner curves among them")
    var steady = true, monotone = true, last = from.points
    for step in 1...20 {
        let t = CGFloat(step) / 20
        let between = ArisNotchGlassSample(width: 250 + (502 - 250) * t, height: 32 + (400 - 32) * t, top: 13 + 18 * t, bottom: 13 + 18 * t, openness: t)
        let now = elements(G.outline(between, canvas: canvas))
        steady = steady && now.kinds == from.kinds && now.points.count == from.points.count
        // Each frame's outline holds the one before: it only grows while opening.
        let box = G.outline(between, canvas: canvas).boundingBoxOfPath
        monotone = monotone && last.allSatisfy { box.insetBy(dx: -0.001, dy: -0.001).contains($0) }
        last = now.points
    }
    check(steady, "outline: every frame between closed and open has the same elements")
    check(monotone, "outline: while opening each frame's outline contains the frame before")
    // Where it sits: centred, hanging from the top of the glass view (y up), with one point above the top.
    let box = G.outline(open, canvas: canvas).boundingBoxOfPath
    check(near(Double(box.minX), 69) && near(Double(box.maxX), 571) && near(Double(box.minY), 420) && near(Double(box.maxY), 821),
          "outline: centred in the glass view, from one point above its top down the notch's height")
    let path = G.outline(open, canvas: canvas)
    check(path.contains(CGPoint(x: 320, y: 600)) && path.contains(CGPoint(x: 320, y: 421)) && !path.contains(CGPoint(x: 320, y: 419))
          && !path.contains(CGPoint(x: 72, y: 800)) && path.contains(CGPoint(x: 97, y: 815)) && !path.contains(CGPoint(x: 101, y: 421.5)),
          "outline: inside the body, outside under it, in the shoulder's flare and past the bottom corner")
    let outside = G.outside(path, canvas: canvas, reach: 48)
    check(!outside.contains(CGPoint(x: 320, y: 600), using: .evenOdd) && outside.contains(CGPoint(x: 320, y: 400), using: .evenOdd)
          && outside.contains(CGPoint(x: 20, y: 600), using: .evenOdd),
          "shadow: the shadow's mask is everything but the outline, so no shadow darkens the glass")
    let rest = G.shadow(openness: 0), full = G.shadow(openness: 1), half = G.shadow(openness: 0.5)
    check(near(Double(rest.opacity), 0.25) && rest.radius == 6 && rest.drop == 2 && near(Double(full.opacity), 0.28) && full.radius == 12 && full.drop == 5
          && near(Double(half.opacity), 0.265) && half.radius == 9 && half.drop == 3.5 && G.shadow(openness: 3).radius == 12,
          "shadow: 0 2 6 at .25 closed, 0 5 12 at .28 open, and evenly between")
}

/// The timings and text, read from where Aris keeps them.
private func glass3WiringTests() {
    let animations = glass3Source("Aris/private/Notch/ArisNotchAnimations.swift"), tokens = glass3Source("Aris/private/Aris/Design/ArisGlass.swift")
    check(animations.contains(".timingCurve(0.2, 0.8, 0.2, 1, duration: 0.28 / speed)") && animations.contains(".timingCurve(0.45, 0, 0.55, 1, duration: 0.2 / speed)"),
          "motion: open 280 ms (0.2, 0.8, 0.2, 1), close 200 ms (0.45, 0, 0.55, 1)")
    check(tokens.contains("static let resize = Animation.timingCurve(0.45, 0, 0.55, 1, duration: 0.34)"), "motion: a size change takes 340 ms (0.45, 0, 0.55, 1)")
    let root = glass3Source("Aris/private/Notch/ArisNotchRoot.swift")
    check(root.contains(".animation(ArisGlass.resize, value: closedKind)") && root.contains("withAnimation(ArisGlass.resize) { drawnHeight = height }")
          && root.contains(".animation(open ? StandardAnimations.open : StandardAnimations.close, value: vm.notchState)"),
          "motion: the notch opens and closes on those curves, and a band or a height changes on the 340 ms one")
    check(root.contains("NotchShape(topCornerRadius: radii.top, bottomCornerRadius: radii.bottom, circular: 1)")
          && root.contains("ArisGlassSurface(shape: shape, open: open, hidden: hidden, safeTop: glassSafeTop,"),
          "outline: the notch draws quarter-circle corners in every state and tells the glass when it is hidden")
    // The surface: the private glass only for the resolved look, without Reduce Transparency; everything else as before.
    check(tokens.contains("private var look: ArisGlassLook { chosen.resolved(health.parts) }")
          && tokens.contains("if #available(macOS 26.0, *), look.usesPrivateParts, wash == nil, !reduceTransparency {\n                privateGlassStack")
          && tokens.contains("@State private var chosen = ArisGlassLook.current()") && tokens.contains("if opened { chosen = ArisGlassLook.current() }"),
          "shipped glass: the surface draws the private glass stack only while every private part took, and reads the look as the notch opens")
    check(tokens.contains("ArisNotchGlass(sample: ArisNotchGlassSample(width: proxy.size.width, height: proxy.size.height, top: shape.topCornerRadius,")
          && tokens.contains("active: look.showsGlass(open: open, hidden: hidden, reduceTransparency: reduceTransparency)")
          && tokens.contains(".frame(width: windowSize.width, height: windowSize.height)"),
          "shipped glass: the surface's size, radii and state reach the glass as one animatable sample, in a view that does not move")
    let stack = glass3Source("Aris/private/Aris/Design/ArisNotchGlass.swift")
    check(stack.contains("struct ArisNotchGlass: View, Animatable {") && stack.contains("view.update(sample, safeTop: safeTop, active: active)"),
          "glass motion: every eased frame of the sample is handed to the AppKit view")
    check(stack.contains("CATransaction.setDisableActions(true)\n        if !ArisGlassPrivate.setPath(glass, outline) { ArisGlassHealth.shared.failed(\\.path) }")
          && stack.contains("gradientMask.path = outline") && stack.contains("drop.shadowPath = outline") && stack.contains("gradient.endPoint = CGPoint(x: 0.5, y: ArisNotchGlassGeometry.gradientEnd("),
          "glass motion: one frame sets the glass's path, the gradient's mask and end and the shadow together, with no animation of their own")
    check(stack.contains("glass.style = .regular") && stack.contains("glass.tintColor = NSColor(srgbRed: 0, green: 0, blue: ArisGlassRecipe.tintBlue, alpha: ArisGlassRecipe.tintAlpha)")
          && stack.contains("gradient.colors = [1, 1, ArisGlassRecipe.rimAlpha].map { CGColor(srgbRed: 0, green: 0, blue: 0, alpha: $0) }")
          && stack.contains("gradient.locations = [0, NSNumber(value: ArisGlassRecipe.darkStop), 1]") && stack.contains("gradient.startPoint = CGPoint(x: 0.5, y: 1)")
          && stack.contains("gradient.mask = gradientMask") && stack.contains("glass.isHidden = !active"),
          "shipped glass: regular style, the glass tint, a gradient from the top masked by a shape layer, and hidden only when the notch is")
    check(stack.contains("if !took.variant { ArisGlassHealth.shared.failed(\\.variant) }") && stack.contains("if !took.lensing { ArisGlassHealth.shared.failed(\\.lensing) }")
          && stack.contains("ArisGlassHealth.shared.failed(\\.activeAppearance)") && stack.contains("parts = ArisGlassPrivate.probe()"),
          "glass fallback: each private part is asked for on its own and its failure told, so the notch turns to clear-glass")
    check(stack.contains("func release() {\n        if let forcedWindow { ArisGlassPrivate.forceActiveAppearance(forcedWindow, on: false) }")
          && stack.contains("static func dismantleNSView(_ view: ArisNotchGlassView, coordinator: ()) { view.release() }")
          && stack.contains("if let forcedWindow, forcedWindow !== window { release() }"),
          "switching looks: the panel's forced active appearance is given back when the private glass leaves it")
    // Private API stays in its one file, each call guarded.
    let secret = glass3Source("Aris/private/Aris/Design/ArisGlassPrivate.swift")
    let names = ["set_variant:", "_variant", "set_contentLensing:", "_contentLensing", "_setPath:", "hasActiveAppearance", "_hasActiveAppearance", "_setHasActiveAppearance:"]
    check(names.allSatisfy { secret.contains("\"\($0)\"") }, "private glass: the private selectors are all named in ArisGlassPrivate")
    let design = ["ArisGlass.swift", "ArisGlassLook.swift", "ArisGlassFallback.swift", "ArisNotchGlass.swift", "ArisNotchGlassGeometry.swift", "ArisNativeGlass.swift", "ArisGlassRecipe.swift"]
        .map { glass3Source("Aris/private/Aris/Design/\($0)") }
    check(design.allSatisfy { !$0.isEmpty } && design.allSatisfy { file in names.allSatisfy { !file.contains("\"\($0)\"") } && !file.contains("NSSelectorFromString") && !file.contains("objc_") },
          "private glass: no private selector is named, and no runtime call made, in any other glass file")
    let calls = secret.components(separatedBy: "unsafeBitCast(imp, to:").count - 1
    let guards = secret.components(separatedBy: "\n").filter { $0.contains(".responds(to: selector)") && $0.contains("let imp = ") && $0.contains("else { return false }") }
    check(calls == 4 && guards.count == 4 && guards.filter { $0.contains("takes(") || $0.contains("returns(") }.count == 4,
          "private glass: each of the four call sites is reached only when the object responds and the method still has its type")
    check(secret.contains("PRIVATE AppKit API") && secret.contains("responds(to:)"),
          "private glass: the file says what it is and that each call is asked before it is made")
    // A closed band leaves the camera's width to the notch's own surface: one gradient from ear to ear on a display
    // with no camera housing, where a black block of its own would stand out between two glass ears.
    let row = glass3Source("Aris/private/Aris/Design/ArisBandRow.swift"), parts = glass3Source("Aris/private/Notch/ArisNotchClosedParts.swift")
    check(row.contains("Color.clear.frame(width: notchWidth)") && !row.contains("fill(.black)") && !parts.contains("Rectangle().fill(.black)"),
          "closed band: the camera's width is drawn by the notch's surface, not by a black block of the band's own")
    // The answer's text and the composer's hint.
    let answer = glass3Source("Aris/private/Aris/Home/ArisAnswerAttributed.swift"), composer = glass3Source("Aris/private/Aris/Home/ArisComposer.swift")
    let scroll = glass3Source("Aris/private/Aris/Home/ArisFadingScroll.swift")
    check(ArisAnswerAttributed.size == 15 && answer.contains("inline(words, font: base, color: white(0.95))"), "text: the answer is 15 points, white .95")
    check(composer.contains("Font(ArisFont.system(15, weight: 450) as CTFont)") && composer.contains("Color(red: 236 / 255, green: 239 / 255, blue: 247 / 255).opacity(0.62)"),
          "text: the composer's hint is rgba(236, 239, 247, .62) at weight 450")
    check(scroll.contains(".scrollIndicators(.never)") && ArisScrollEdges.ramp == 22 && ArisAnswerBudget.textMax == 360,
          "answer: at most 360 points, 22-point edge fades and no scroll bar")
}

/// The open notch's visual width: the body and a shoulder each side.
private enum ArisGlass3Numbers {
    static let openVisualWidth: CGFloat = 440 + 2 * ArisNotchGeometry.openRadii.top
}

func runGlass3Tests() {
    glass3DefaultTests()
    glass3FallbackTests()
    glass3StateTests()
    glass3SpanTests()
    glass3OutlineTests()
    glass3WiringTests()
}
