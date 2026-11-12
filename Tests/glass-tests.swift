// Tests for two rulings of 2026-11-11. One: a private (incognito) browser window is read like any other, and the list
// of apps Aris never reads is the password managers and nothing more. Two: the open notch stays readable over a white
// window: the black over its glass is full to 53 % and .5 at the rim, and never thinner than a floor behind
// the content, so every text style reaches its contrast over pure white; with Reduce Transparency there is no glass.
// Called from main.swift; uses its check(). Nothing is drawn on screen: only the rules, the numbers and the sources.
import Foundation

private func glassSource(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

/// The user: "시크릿창 봐도 되지 뭐." The tab of an incognito window is read like a normal one, for them and for a look.
private func glassPrivateWindowTests() {
    typealias T = ArisTabTarget
    let screen = glassSource("ArisTools/ArisScreen.swift"), target = glassSource("ArisTools/ArisTabTarget.swift")
    check(!screen.isEmpty && !target.isEmpty, "private windows: the tab tool's sources are where the tests read them")
    let asksMode = ["mode of front window", "privateScript", "privateRefusal", "isPrivate(status", "\"incognito\""]
    check(asksMode.allSatisfy { !screen.contains($0) && !target.contains($0) },
          "private windows: aris-tools tab never asks a browser whether its window is incognito, so that tab is read like any other")
    check(!screen.contains("is a private one"), "private windows: no reply says a browser window is private and unread")
    // What stays of that security fix: the look reads the browser it chose, and fails plainly when it isn't running.
    let known = ["com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser", "com.brave.Browser", "com.microsoft.edgemac"]
    let both: Set<String> = ["com.apple.Safari", "com.google.Chrome", "com.lumenjsn.aris"]
    check(T.choose(named: "com.google.chrome", front: "com.lumenjsn.aris", running: both, browsers: known) == .browser("com.google.Chrome")
          && T.choose(named: "com.google.Chrome", front: nil, running: ["com.apple.Safari"], browsers: known) == .refused(T.notRunning("com.google.Chrome"))
          && screen.contains(#"option("--app", in: &args)"#),
          "private windows: tab --app still reads exactly the named browser and fails plainly when it isn't running")
    // The list of apps never read is the password managers, exactly as it was: no browser, bank or authenticator.
    let managers: Set<String> = ["com.apple.keychainaccess", "com.apple.passwords", "com.1password.1password", "com.agilebits.onepassword7",
                                 "com.bitwarden.desktop", "com.dashlane.dashlane", "com.dashlane.dashlanephonefinal", "com.lastpass.lastpass",
                                 "me.proton.pass.electron", "in.sinew.enpass-desktop", "org.keepassxc.keepassxc"]
    check(ArisCaptureRules.privateBundleIds == managers, "private windows: the never-read list is the same eleven password managers")
    check(known.allSatisfy { !ArisCaptureRules.isPrivate($0) } && ArisCaptureRules.isPrivate("com.1password.1password"),
          "private windows: no browser is on the never-read list; a password manager still is")
}

// MARK: - The open notch over a bright window

private typealias R = ArisGlassRecipe

/// What is behind a line of text at `y` of an open notch `height` tall, over `backdrop`.
private func glassGround(at y: Double, height: Double, backdrop: GlassRGB, tinted: Bool = true) -> GlassRGB {
    let tint = tinted ? (color: GlassRGB(r: 0, g: 0, b: R.tintBlue), alpha: R.tintAlpha) : nil
    return glassBehind(backdrop: backdrop, tint: tint, black: .black, blackAlpha: R.alpha(at: y, height: height))
}

/// The lowest contrast `style` reaches anywhere content can be (from the top to the bottom inset), point by point.
private func glassWorst(_ style: GlassTextStyle, height: Double, backdrop: GlassRGB, tinted: Bool = true) -> Double {
    stride(from: 0.0, through: height - R.rimBand, by: 1).map { style.contrast(over: glassGround(at: $0, height: height, backdrop: backdrop, tinted: tinted)) }.min() ?? 0
}

/// The gradient's numbers, with the floor behind the content.
private func glassRecipeTests() {
    check(R.darkStop == 0.53 && R.rimAlpha == 0.5 && R.tintBlue == 0.02 && R.tintAlpha == 0.18,
          "glass: the black is full to 53 % and half at the bottom, over a sRGB(0, 0, .02, .18) tint")
    let tall = R.stops(height: 700, open: true, glass: true)
    check(tall.count == 4 && tall[0] == .init(location: 0, alpha: 1) && tall[1] == .init(location: 0.53, alpha: 1)
          && tall[2].alpha == R.textFloor && abs(tall[2].location - (700 - R.rimBand) / 700) < 1e-9 && tall[3] == .init(location: 1, alpha: 0.5),
          "glass: open, the black is full to 53 %, eases to the text floor at the bottom inset, and only there thins to half")
    check(R.alpha(at: 0, height: 700) == 1 && R.alpha(at: 371, height: 700) == 1 && abs(R.alpha(at: 692, height: 700) - R.textFloor) < 1e-9
          && abs(R.alpha(at: 700, height: 700) - 0.5) < 1e-9 && abs(R.alpha(at: 696, height: 700) - (R.textFloor + 0.5) / 2) < 1e-9,
          "glass: the black at a height is read off the same stops the notch draws")
    var floorHolds = true, ordered = true
    for height in stride(from: 100.0, through: 800, by: 7) {
        let stops = R.stops(height: height, open: true, glass: true)
        ordered = ordered && stops.count == 4 && zip(stops, stops.dropFirst()).allSatisfy { $0.location <= $1.location && $0.alpha >= $1.alpha }
        for y in stride(from: 0.0, through: height - R.rimBand, by: 1) where R.alpha(at: y, height: height) < R.textFloor - 1e-9 { floorHolds = false }
    }
    check(floorHolds, "glass: whatever the notch's height, the black never thins under the floor above the bottom inset, where the last line ends")
    check(ordered, "glass: every height has the same four stops, in order and only ever thinning downward")
    check(glassSource("Aris/private/Aris/Design/ArisGlass.swift").contains("static let bottomInset: CGFloat = 8") && R.rimBand == 8,
          "glass: the light lower rim is exactly the open notch's bottom inset, under everything it shows")
    let closed = R.stops(height: 32, open: false, glass: true)
    check(closed.count == 4 && closed.allSatisfy { $0.alpha == 1 }, "glass: closed, the notch is solid black, with the same four stops so opening slides them")
    // A notch too short to hold both the 53 % and the inset (only mid-way through opening): a plain fade.
    let short = R.stops(height: 12, open: true, glass: true)
    check(short.count == 4 && zip(short, short.dropFirst()).allSatisfy { $0.location <= $1.location } && short[3].alpha == 0.5 && short[0].alpha == 1,
          "glass: a notch shorter than its own rim (mid-opening) still gets ordered stops")
}

/// The user: the lower half was clear glass and unreadable over a white window. Every text style, over pure white.
private func glassContrastTests() {
    for style in glassTextStyles {
        check(glassSource(style.file).contains(style.needle), "glass: the table's “\(style.name)” is still the colour in \(style.file.split(separator: "/").last ?? "")")
        var worst = Double.infinity
        for height in [140.0, 300, 500, 710] { worst = min(worst, glassWorst(style, height: height, backdrop: .white)) }
        check(worst >= style.needs, "glass: over a pure white window “\(style.name)” reaches \(style.needs):1 on every line (worst \((worst * 100).rounded() / 100):1)")
        let bare = glassWorst(style, height: 710, backdrop: .white, tinted: false)
        check(bare >= style.needs, "glass: and still does if the glass's tint darkened nothing (worst \((bare * 100).rounded() / 100):1)")
    }
    // The test bites: the recipe before failed exactly where the VM runs said it did.
    let hint = glassTextStyles.first { $0.name.hasPrefix("composer hint") }
    let more = glassTextStyles.first { $0.name.contains("Read more") }
    let lastLine = 710.0 - R.rimBand
    let before = glassBehind(backdrop: .white, tint: GlassRecipeBefore.tint, black: GlassRecipeBefore.color, blackAlpha: GlassRecipeBefore.alpha(at: lastLine, height: 710))
    check((hint?.contrast(over: before) ?? 9) < 1.5 && (more?.contrast(over: before) ?? 9) < 1.5,
          "glass: before, the composer hint and “Read more” over a white window were under 1.5:1 at the last line")
    // A mid-grey window and a dark one only make it easier.
    let body = glassTextStyles[0]
    check(glassWorst(body, height: 710, backdrop: .grey(0.5)) > glassWorst(body, height: 710, backdrop: .white)
          && glassWorst(body, height: 710, backdrop: .grey(0.1)) > glassWorst(body, height: 710, backdrop: .grey(0.5)),
          "glass: white is the worst backdrop; grey and dark ones read better")
}

/// "Liquid Glass off": macOS's Reduce Transparency makes every dark surface solid, with no glass behind it.
private func glassReduceTransparencyTests() {
    let solid = R.stops(height: 500, open: true, glass: false)
    check(solid.count == 4 && solid.allSatisfy { $0.alpha == 1 } && R.alpha(at: 499, height: 500, glass: false) == 1,
          "reduce transparency: the open notch is solid black from top to bottom")
    check(R.showsGlass(open: true, reduceTransparency: false) && !R.showsGlass(open: true, reduceTransparency: true)
          && !R.showsGlass(open: false, reduceTransparency: false),
          "reduce transparency: no glass is drawn at all (nor under a closed notch, which is solid anyway)")
    check(R.sideWash(reduceTransparency: false) == 0.95 && R.sideWash(reduceTransparency: true) == 1
          && R.pillFill(reduceTransparency: false) == 0.96 && R.pillFill(reduceTransparency: true) == 1,
          "reduce transparency: the side panel's wash and the pill's fill turn solid; otherwise they are .95 and .96 (vside-tests.swift)")
    let glass = glassSource("Aris/private/Aris/Design/ArisGlass.swift"), side = glassSource("Aris/private/Aris/Side/ArisSideLayers.swift")
    let pill = glassSource("Aris/private/Aris/Team/ArisBubbleView.swift")
    // The stops are the look's now (ArisGlassLook, glass2-tests.swift); the shipped look, floor, is the recipe's own.
    let look = glassSource("Aris/private/Aris/Design/ArisGlassLook.swift")
    check(glass.contains("@Environment(\\.accessibilityReduceTransparency)")
          && glass.contains("look.stops(height: along, safeTop: safeTop, open: open, glass: !reduceTransparency)")
          && look.contains("case .floor:\n            return ArisGlassRecipe.stops(height: height, open: open, glass: glass)")
          && glass.contains("look.showsGlass(open: open, hidden: hidden, reduceTransparency: reduceTransparency)")
          && look.contains("ArisGlassRecipe.showsGlass(open: open, reduceTransparency: reduceTransparency)"),
          "reduce transparency: the notch's surface reads the setting and draws the recipe's stops")
    check(side.contains("accessibilityDisplayShouldReduceTransparency") && side.contains("ArisGlassRecipe.sideWash(reduceTransparency:")
          && pill.contains("ArisGlassRecipe.pillFill(reduceTransparency:"),
          "reduce transparency: the side panel and the pill read it too")
    // The other dark surfaces over the desktop already pass over white as they are (their own numbers, unchanged).
    let dim = GlassTextStyle(name: "side row subtitle", color: .white, alpha: 0.43, fills: [], needs: 3, file: "", needle: "")
    let sideGround = GlassRGB(r: 0, g: 0, b: 6.0 / 255).over(.white, alpha: R.sideWash(reduceTransparency: false))
    let pillGround = GlassRGB(r: 22.0 / 255, g: 22.0 / 255, b: 27.0 / 255).over(.white, alpha: R.pillFill(reduceTransparency: false))
    check(dim.contrast(over: sideGround) >= 3 && dim.contrast(over: pillGround) >= 3,
          "glass: the side panel's wash and the pill's fill keep their dimmest text (white .43) over 3:1 on a white window")
}

func runGlassTests() {
    glassPrivateWindowTests()
    glassRecipeTests()
    glassContrastTests()
    glassReduceTransparencyTests()
}
