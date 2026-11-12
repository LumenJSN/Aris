// Tests for the glass looks of 2026-11-11 (the owner: "I really like the transparent look… it has a max length"). One
// hidden preference, arisGlassLook, picks how the open notch's glass is drawn, so the looks can be compared on a real
// screen: what ships now (floor), what was drawn before (before), the deep black over AppKit's public regular glass
// (regular-glass), the same with private AppKit parts (private-glass), the deep black over the clear glass
// (clear-glass), and a lighter floor (mid). And a maximum: a written answer stops at 360 points and scrolls inside.
// Since the owner picked private-glass it is what ships (glass3-tests.swift has its own rules); these keep the six
// looks and their numbers. Called from main.swift; uses its check().
// Nothing is drawn on screen: only the rules, the numbers and the sources.
import Foundation

private typealias L = ArisGlassLook
private typealias R = ArisGlassRecipe

private func glass2Source(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

private func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.0001 }

/// The preference: six names, and anything else is what ships (private-glass).
private func glass2PreferenceTests() {
    check(L.preferenceKey == "arisGlassLook", "glass look: the hidden preference is arisGlassLook")
    check(L.allCases.map(\.rawValue).sorted() == ["before", "clear-glass", "floor", "mid", "private-glass", "regular-glass"],
          "glass look: the looks are floor, before, regular-glass, private-glass, clear-glass and mid")
    check(L(preference: nil) == .privateGlass && L(preference: "") == .privateGlass && L(preference: "liquid") == .privateGlass
          && L.fallback == .privateGlass,
          "glass look: no preference, an empty one or an unknown name draws what ships (private-glass)")
    check(L(preference: "regular-glass") == .regularGlass && L(preference: "private-glass") == .privateGlass && L(preference: "mid") == .mid
          && L(preference: "before") == .before && L(preference: "floor") == .floor && L(preference: "clear-glass") == .clearGlass,
          "glass look: each name picks its look")
    check(L(preference: " Private-Glass\n") == .privateGlass, "glass look: the name is read without its case or the spaces around it")
    let suite = testSuiteName("aris-glass2-tests")
    guard let defaults = UserDefaults(suiteName: suite) else { check(false, "glass look: a defaults suite for the test"); return }
    defaults.removePersistentDomain(forName: suite)
    check(L.current(defaults) == .privateGlass, "glass look: with nothing written the notch opens in the shipped look")
    defaults.set("regular-glass", forKey: L.preferenceKey)
    check(L.current(defaults) == .regularGlass, "glass look: a written name is the look the next time the notch opens")
    defaults.set(3, forKey: L.preferenceKey)
    check(L.current(defaults) == .privateGlass, "glass look: a preference that is no look's name (a number) draws what ships")
    defaults.removePersistentDomain(forName: suite)
}

/// The black over the glass, look by look.
private func glass2GradientTests() {
    let h = 400.0
    check(L.floor.stops(height: h, open: true, glass: true) == R.stops(height: h, open: true, glass: true)
          && near(L.floor.alpha(at: h - 8, height: h), 0.8),
          "glass look floor: exactly the recipe Aris shipped before, never under 80 % behind the content")
    check(near(L.mid.alpha(at: h - 8, height: h), 0.6) && near(L.mid.alpha(at: 0.53 * h, height: h), 1) && near(L.mid.alpha(at: h, height: h), 0.5)
          && L.mid.alpha(at: 300, height: h) < L.floor.alpha(at: 300, height: h),
          "glass look mid: the same black with a 60 % floor, so it is lighter than floor below the 53 % line")
    check(near(L.before.alpha(at: 0, height: h), 0.98) && near(L.before.alpha(at: 0.48 * h, height: h), 0.98) && near(L.before.alpha(at: h, height: h), 0)
          && near(L.before.alpha(at: 0.74 * h, height: h), 0.49) && near(L.before.blackBlue, 2.0 / 255) && near(L.before.tintBlue, 5.0 / 255),
          "glass look before: rgba(0, 0, 2, .98) to 48 % and fading to nothing at the bottom, as Aris drew it until 2026-11-11")
    for look in [L.regularGlass, L.privateGlass, L.clearGlass] {
        let stops = look.stops(height: h, open: true, glass: true)
        check(stops.count == 4 && stops.first == R.Stop(location: 0, alpha: 1) && stops[1] == R.Stop(location: 0.53, alpha: 1)
              && stops.last == R.Stop(location: 1, alpha: 0.5),
              "glass look \(look.rawValue): the deep-black gradient, black 1, 1, .5 at 0, .53, 1")
        check(near(look.alpha(at: 0.53 * h, height: h), 1) && near(look.alpha(at: h, height: h), 0.5)
              && near(look.alpha(at: 0.765 * h, height: h), 0.75) && near(look.alpha(at: h - 8, height: h), 0.5 + 0.5 * 8 / (0.47 * h)),
              "glass look \(look.rawValue): the black thins evenly from 53 % down to its half at the edge, with no floor")
        check(look.alpha(at: h - 8, height: h) < L.mid.alpha(at: h - 8, height: h),
              "glass look \(look.rawValue): at the last line it is lighter than both floors (the material does the rest)")
        check(near(look.blackBlue, 0) && near(look.tintBlue, 0.02) && near(look.tintAlpha, 0.18),
              "glass look \(look.rawValue): the black is #000 and the tint sRGB(0, 0, .02) at .18")
    }
    // The span rule: max(height, safe-area top / 0.53).
    check(near(L.regularGlass.span(height: 400, safeTop: 38), 400) && near(L.regularGlass.span(height: 40, safeTop: 38), 38 / 0.53)
          && near(L.regularGlass.span(height: 40, safeTop: 0), 40) && near(L.privateGlass.span(height: 40, safeTop: 32), 32 / 0.53),
          "glass look regular-glass: the black spans max(height, safe-area top / 0.53)")
    check(near(L.regularGlass.alpha(at: 38, height: 40, safeTop: 38), 1) && L.regularGlass.alpha(at: 40, height: 40, safeTop: 38) > 0.97,
          "glass look regular-glass: over a short notch the full black still covers the whole camera housing")
    check(near(L.floor.span(height: 40, safeTop: 38), 40) && near(L.mid.span(height: 40, safeTop: 38), 40) && near(L.before.span(height: 40, safeTop: 38), 40),
          "glass look: the other looks' black ends on the notch's own edge")
    // With Reduce Transparency every look is solid. Closed, Aris's own looks are solid; the deep-black looks keep
    // their gradient, whose span makes a closed notch solid over a camera housing (32 points tall on a 32-point
    // safe area).
    for look in L.allCases {
        let closed = look.stops(height: 32, open: false, glass: true), reduced = look.stops(height: h, open: true, glass: false)
        check(closed.count == 4 && (look.deepBlack ? near(look.alpha(at: 32, height: 32, safeTop: 32, open: false), 1) : closed.allSatisfy { $0.alpha >= 0.98 }),
              "glass look \(look.rawValue): closed over a camera housing, the notch is solid")
        check(reduced.count == 4 && reduced.allSatisfy { $0.alpha == 1 }, "glass look \(look.rawValue): with Reduce Transparency the open notch is solid black")
        check(look.stops(height: h, open: true, glass: true).count == 4 && look.stops(height: 60, open: true, glass: true).count == 4,
              "glass look \(look.rawValue): always four stops, so the looks and the heights slide into each other")
    }
}

/// Which glass, and where the private calls may be made.
private func glass2MaterialTests() {
    check(L.regularGlass.regularMaterial && L.privateGlass.regularMaterial && !L.floor.regularMaterial && !L.mid.regularMaterial && !L.before.regularMaterial
          && !L.clearGlass.regularMaterial,
          "glass look: only regular-glass and private-glass use AppKit's regular glass; floor, mid, before and clear-glass keep the clear one")
    check(L.clearGlass.deepBlack && L.regularGlass.deepBlack && L.privateGlass.deepBlack && !L.floor.deepBlack && !L.mid.deepBlack
          && near(L.clearGlass.span(height: 40, safeTop: 38), 38 / 0.53) && L.clearGlass.stops(height: 400, open: true, glass: true) == L.regularGlass.stops(height: 400, open: true, glass: true),
          "glass look clear-glass: the deep black and its span, over the clear glass, with public API only")
    check(L.allCases.filter(\.usesPrivateParts) == [.privateGlass], "glass look: private AppKit calls are made for private-glass and no other look")
    check(L.privateVariant == 11 && L.privateContentLensing == 3, "glass look private-glass: variant 11 and content lensing 3")
    let secret = glass2Source("Aris/private/Aris/Design/ArisGlassPrivate.swift"), native = glass2Source("Aris/private/Aris/Design/ArisNativeGlass.swift")
    let surface = glass2Source("Aris/private/Aris/Design/ArisGlass.swift")
    check(!secret.isEmpty && !native.isEmpty && !surface.isEmpty, "glass look: the glass sources are where the tests read them")
    let names = ["set_variant:", "set_contentLensing:", "_setPath:", "_hasActiveAppearance", "_setHasActiveAppearance:"]
    check(names.allSatisfy { secret.contains("\"\($0)\"") }, "glass look private-glass: the private calls are these five, all in ArisGlassPrivate")
    check(names.allSatisfy { !native.contains($0) && !surface.contains($0) } && !surface.contains("ArisGlassPrivate.") && !native.contains("ArisGlassPrivate."),
          "glass look: no private selector is named outside ArisGlassPrivate, and the public glass view never reaches it")
    check(secret.contains("PRIVATE AppKit API") && secret.contains("private-glass"), "glass look: the private file says what it is and when it is used")
    check(native.contains("glass.style = .regular") && native.contains("glass.tintColor = tint") && native.contains("glass.cornerRadius"),
          "glass look regular-glass: the glass is NSGlassEffectView's public style, tint and corner radius")
    check(surface.contains("look.usesPrivateParts, wash == nil, !reduceTransparency {") && surface.contains("if !reduceTransparency {\n                glass"),
          "glass look: the surface draws the private glass by the look alone, and no glass with Reduce Transparency")
    check(surface.contains("@State private var chosen = ArisGlassLook.current()") && surface.contains("if opened { chosen = ArisGlassLook.current() }"),
          "glass look: the preference is read as the notch opens, so a new name shows without a rebuild")
}

/// The maximum: a written answer is at most 360 points tall, and the rest scrolls inside.
private func glass2MaximumTests() {
    check(ArisAnswerBudget.textMax == 360, "max height: a written answer stops at 360 points")
    let tall = ArisAnswerRoom(surfaceMax: 710, band: 37, context: 0, composer: 38)
    check(tall.answer(prompt: 54) == 539 && tall.text(prompt: 54) == 360,
          "max height: on a tall display the room is 539 but a written answer takes min(360, room), 360")
    check(tall.text(prompt: 54, footer: 44) == 360, "max height: a footer under the answer leaves it its 360")
    let short = ArisAnswerRoom(surfaceMax: 420, band: 37, context: 0, composer: 38)
    check(short.text(prompt: 54) == short.answer(prompt: 54) && short.text(prompt: 54) == 249,
          "max height: on a short display the answer takes what room there is (249), under the cap")
    let tiny = ArisAnswerRoom(surfaceMax: 200, band: 37, context: 92, composer: 38)
    check(tiny.text(prompt: 160, footer: 44) == 120, "max height: never under 120")
    // The open notch around a one-line question and a long answer: band, insets and gaps, prompt, answer, composer.
    let surface = 37 + (2 + 8 + 8 * 4) + 54 + tall.text(prompt: 54) + 38
    check(surface == 531 && surface < 710, "max height: the open notch with a long answer is 531 points tall, not the display's 710")
    check(ArisAnswerReader.limit(budget: tall.answer(prompt: 54)) == 360 && ArisAnswerReader.offers(content: 362, budget: 539)
          && !ArisAnswerReader.offers(content: 360, budget: 539),
          "max height: the reader is offered exactly when the answer is taller than what is drawn")
    let edges = ArisScrollEdges.at(offset: 0, visible: 360, content: 900)
    check(edges == ArisScrollEdges(top: false, bottom: true) && ArisScrollEdges.ramp == 22
          && ArisScrollEdges.at(offset: 200, visible: 360, content: 900) == ArisScrollEdges(top: true, bottom: true)
          && ArisScrollEdges.at(offset: 540, visible: 360, content: 900) == ArisScrollEdges(top: true, bottom: false),
          "max height: the capped answer scrolls under 22-point fades, only on the sides with more to read")
    let turn = glass2Source("Aris/private/Aris/Home/ArisTurnView.swift")
    check(turn.contains("private var answerBudget: CGFloat { room.text(prompt: promptRoom, footer: footerRoom + moreRoom + cardRoom) }"),
          "max height: the turn's written answer is drawn within the capped room")
}

func runGlass2Tests() {
    glass2PreferenceTests()
    glass2GradientTests()
    glass2MaterialTests()
    glass2MaximumTests()
}
