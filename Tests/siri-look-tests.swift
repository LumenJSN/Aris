// Tests for the hidden "siri" look (arisVoiceLook): which look a preference means and when it is read, the surface's
// fill against what Siri's own panel read over a white window and over black in the owner's captures (macOS 27.2,
// 2026-11-11), the control glass solved from the same two readings, the sizes and type read from the screenshots,
// the working dots (a smooth turning and swelling, never a blink), the springs fitted to the recording, and the
// places the look is switched in. Called from main.swift; uses its check(). Nothing is drawn on screen.
import Foundation

private typealias S = ArisSiriLook

private func near(_ a: Double, _ b: Double, _ tolerance: Double = 0.001) -> Bool { abs(a - b) <= tolerance }

private func siriLookSource(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

private func siriLookResolutionTests() {
    check(ArisVoiceLook.resolve(nil) == .aris && ArisVoiceLook.resolve("") == .aris && ArisVoiceLook.resolve("orb") == .aris,
          "siri look: with no preference, or one Aris doesn't know, Aris is drawn as today")
    check(ArisVoiceLook.resolve("siri") == .siri && ArisVoiceLook.resolve(" Siri\n") == .siri && ArisVoiceLook.resolve("aris") == .aris,
          "siri look: arisVoiceLook siri switches the look on, however it is capitalised; aris is today's")
    check(ArisVoiceLook.resolve("siri-frost") == .siriFrost && ArisVoiceLook.siriFrost.isSiri && ArisVoiceLook.siri.isSiri && !ArisVoiceLook.aris.isSiri,
          "siri look: siri-frost is the same look over the system's frosted glass, to compare on a real screen")
    check(ArisVoiceLook.resolve("siri-screen") == .aris, "siri look: there is no whole-screen light: siri-screen is not a look and stays today's")
    check(ArisVoiceLook.key == "arisVoiceLook", "siri look: the one preference is arisVoiceLook")
    check(ArisSiriLookNow.look == .aris && !ArisSiriLookNow.on, "siri look: until the preference says otherwise the look in force is today's")

    var stored: String? = nil
    var reads = 0
    let latch = ArisVoiceLookLatch { reads += 1; return stored }
    let closedIdle = ArisSiriLookMoment.name(open: false, state: "idle"), openIdle = ArisSiriLookMoment.name(open: true, state: "idle")
    check(latch.look(entering: closedIdle) == .aris && reads == 1, "siri look: the preference is read when a state begins")
    stored = "siri"
    check(latch.look(entering: closedIdle) == .aris && reads == 1, "siri look: it is not read again while nothing has changed")
    check(closedIdle != openIdle && latch.look(entering: openIdle) == .siri && reads == 2,
          "siri look: the notch opening is a moment the preference is read at, so a defaults write shows at the next open with no rebuild or restart")
    check(ArisSiriLookMoment.name(open: true, state: "thinking") != openIdle, "siri look: a voice state beginning is such a moment too")
    stored = "aris"
    check(latch.look(entering: openIdle) == .siri && latch.look(entering: closedIdle) == .aris,
          "siri look: switching back takes effect at the next moment too, never halfway through one")
}

private func siriLookSurfaceTests() {
    let closed = S.Surface.stops(height: 300, band: 37, open: false, glass: true)
    let solid = S.Surface.stops(height: 300, band: 37, open: true, glass: false)
    check(closed.count == 4 && closed.allSatisfy { $0.coverage == 1 && $0.grey == 0 }, "siri look: the closed notch is solid black, as today")
    check(solid.allSatisfy { $0.coverage == 1 && $0.grey == 0 }, "siri look: with Reduce Transparency the open notch is solid black")
    let open = S.Surface.stops(height: 300, band: 37, open: true, glass: true)
    check(open.count == 4 && open[0].coverage == 1 && open[1].coverage == 1 && near(open[1].location, 37.0 / 300),
          "siri look: the band beside the camera housing stays full black, so the notch still disappears into the hardware")
    check(zip(open, open.dropFirst()).allSatisfy { $0.coverage >= $1.coverage && $0.location <= $1.location && $0.grey <= $1.grey },
          "siri look: under the band the black only ever thins, and lightens, on the way down")
    check(near(open[3].coverage, 0.40) && near(open[3].grey, 70.0 / 255), "siri look: the bottom edge is Siri's clear end: .40 of a grey of 70")
    check([120.0, 172, 276, 600].allSatisfy { S.Surface.stops(height: $0, band: 37, open: true, glass: true).last == open.last },
          "siri look: the fill ends the same however tall the notch is, as Siri's 172, 276 and 600-point panels do")
    check(S.Surface.stops(height: 20, band: 37, open: true, glass: true).allSatisfy { $0.location <= 1 },
          "siri look: a notch shorter than its band (mid-way through opening) still has its stops in order")

    // Siri's own panel has no band: its readings are checked against a band of nothing.
    check(S.Surface.reads(at: 0, height: 172, band: 0, behind: 255) <= 8.5, "siri look: the top reads black over a white window (Siri: 8 of 255)")
    check(near(S.Surface.reads(at: 300, height: 600, band: 0, behind: 255), 83, 5) && near(S.Surface.reads(at: 300, height: 600, band: 0, behind: 0), 11.6, 1),
          "siri look: half-way down it reads what Siri's reads over white (83) and over black (11.6)")
    check(near(S.Surface.reads(at: 600, height: 600, band: 0, behind: 255), 182, 4) && near(S.Surface.reads(at: 600, height: 600, band: 0, behind: 0), 28, 1),
          "siri look: at the bottom it reads what Siri's reads over white (182) and over black (28)")
    check(S.Surface.reads(at: 20, height: 300, band: 37, behind: 255) == 0, "siri look: in Aris's band nothing of a white window shows")
    // Over Aris's clear glass, which already takes some of what is behind it, the fill is thinner by that much.
    let bottom = S.Surface.stops(height: 300, band: 37, open: true, glass: true, base: S.Surface.clearBase)[3]
    check(near(1 - (1 - S.Surface.clearBase) * (1 - bottom.coverage), S.Surface.bottomCoverage) && near(bottom.grey * bottom.coverage, S.Surface.bottomGrey * S.Surface.bottomCoverage),
          "siri look: the glass and the fill over it together take what Siri's surface takes, and the fill keeps its light")
    check(near(S.Surface.reads(at: 600, height: 600, band: 0, behind: 255, base: S.Surface.clearBase), 182, 4)
          && near(S.Surface.reads(at: 600, height: 600, band: 0, behind: 0, base: S.Surface.clearBase), 28, 1),
          "siri look: over Aris's clear glass the bottom still reads Siri's 182 over white and 28 over black")
    check(S.Surface.stops(height: 300, band: 37, open: true, glass: true, base: S.Surface.clearBase)[1].coverage == 1,
          "siri look: the band is full black over the glass too")
    check(S.Surface.over(S.Surface.frostBase, S.Stop(location: 1, coverage: S.Surface.bottomCoverage, grey: S.Surface.bottomGrey)).coverage == 0,
          "siri look: the frosted glass alone already takes more than Siri's bottom does, so nothing is drawn over it there (siri-frost is darker than Siri)")
    check(S.Surface.over(0, open[3]) == open[3], "siri look: with no glass under it the fill is Siri's own numbers")
    check(near(S.Surface.shadowAlpha * 0.5, 0.20, 0.01), "siri look: the shadow darkens a white window by a fifth at the side edges, as Siri's does")
    check(S.Surface.rimBottom > S.Surface.rimTop && S.Surface.rimTop > S.Surface.rimSide && S.Surface.rimWidth == 0.5,
          "siri look: the rim is half a point, strongest along the bottom")
}

private func siriLookControlTests() {
    func reads(_ behind: Double) -> Double { behind * (1 - S.Control.alpha) + 255 * S.Control.grey * S.Control.alpha }
    check(near(reads(3), 34, 2.5), "siri look: a round button over the black top reads lighter than it, as Siri's does (34 over 3)")
    check(near(reads(169), 148, 2.5) && reads(169) < 169, "siri look: over the light bottom on a white window the same glass reads darker than it (148 over 169)")
    check(S.Control.size == 36 && S.Control.inset == 16 && S.Control.gap == 12 && S.Field.height == 36,
          "siri look: the field's row is Siri's: 36-point circles, a 36-point pill, 12 between them")
    check(S.Control.size + S.Control.gap + 292 + S.Control.gap + S.Control.size + 2 * S.Control.inset == S.Surface.width,
          "siri look: those sizes add up to Siri's 420-point panel with its 292-point pill")
    check(S.Control.bandSize(band: 37) == 28 && S.Control.bandSize(band: 44) == 33 && S.Control.bandSize(band: 38) == 29,
          "siri look: the band's round buttons are sized from the band they sit in: 28 in a 37-point band, 33 in a 44-point one")
    check(S.Control.bandSize(band: 400) == S.Control.size && S.Control.bandSize(band: 0) == 20 && [32.0, 37, 44].allSatisfy { S.Control.bandSize(band: $0) < $0 },
          "siri look: they never outgrow Siri's 36 points or the band itself")
    check(S.Bubble.height == 30 && S.Bubble.radius == 15 && S.Bubble.fontSize == 13 && S.Bubble.tailHeight < S.Bubble.tailWidth,
          "siri look: your words are a 30-point capsule of 13-point type with a small tail")
    check(S.Answer.fontSize == 15 && S.Answer.lineHeight == 18 && S.Answer.ink == 0.90, "siri look: the answer is 15-point type on an 18-point line at white .90")
    check(S.Card.radius == 32 && S.Card.inset == 16, "siri look: a card's corners are 32, as Siri's weather card's")
    check(S.Field.hintInk < S.Answer.ink && S.Field.fontSize == 15, "siri look: the field's hint is quieter than the answer and the same size")
}

private func siriLookDotsTests() {
    let now = (0..<S.Dots.count).map { S.Dots.dot($0, at: 0.3) }
    check(S.Dots.count == 6 && zip(now, now.dropFirst()).allSatisfy { near($1.angle - $0.angle, Double.pi / 3) },
          "siri look: the working mark is six dots evenly round a ring")
    let low = S.Dots.smallest / (2 * S.Dots.ringRadius), high = S.Dots.largest / (2 * S.Dots.ringRadius)
    var smooth = true, inRange = true, biggest = 0.0, smallest = 1.0
    for step in 0..<400 {
        let t = Double(step) / 30
        for index in 0..<S.Dots.count {
            let a = S.Dots.dot(index, at: t), b = S.Dots.dot(index, at: t + 1.0 / 30)
            if a.size < low - 0.0001 || a.size > high + 0.0001 { inRange = false }
            if abs(b.size - a.size) > 0.03 || abs(b.angle - a.angle) > 0.05 { smooth = false }
            biggest = max(biggest, a.size); smallest = min(smallest, a.size)
        }
    }
    check(inRange && smallest > 0.1, "siri look: no dot ever goes out: each stays between Siri's 3.8 and 9 points across (no blinking)")
    check(smooth, "siri look: from one frame to the next a dot only swells or moves a little: a travelling, breathing motion")
    check(near(biggest, high, 0.005) && near(smallest, low, 0.005), "siri look: over time every dot reaches both sizes")
    check(near(S.Dots.dot(0, at: S.Dots.turn).angle - S.Dots.dot(0, at: 0).angle, 2 * Double.pi), "siri look: the ring turns once in 7.6 seconds")
    check(near(S.Dots.dot(2, at: 0.4).size, S.Dots.dot(2, at: 0.4 + S.Dots.wave).size), "siri look: the swelling goes round once in 0.95 seconds")
    let peak = (0..<S.Dots.count).map { index in (0..<95).max { S.Dots.dot(index, at: Double($0) / 100).size < S.Dots.dot(index, at: Double($1) / 100).size } ?? 0 }
    check(zip(peak, peak.dropFirst()).allSatisfy { $1 > $0 }, "siri look: each dot swells a moment after the one before it, so the swelling travels round the ring")
    check((0..<S.Dots.count).allSatisfy { S.Dots.dot($0, at: 0, reduceMotion: true).size == S.Dots.dot($0, at: 5.3, reduceMotion: true).size
              && S.Dots.dot($0, at: 0, reduceMotion: true).angle == S.Dots.dot($0, at: 5.3, reduceMotion: true).angle },
          "siri look: with Reduce Motion the ring is one still picture")
}

private func siriLookMotionTests() {
    let grow = S.Motion.grow, shrink = S.Motion.shrink
    let samples = (0...100).map { grow.progress(at: Double($0) / 100) }
    let top = samples.max() ?? 0, at = Double(samples.firstIndex(of: top) ?? 0) / 100
    check(grow.progress(at: 0) == 0 && top > 1.015 && top < 1.04, "siri look: growing passes its size by a few percent, as Siri's panel does (about 2.7 %)")
    check(at > 0.2 && at < 0.36, "siri look: the overshoot comes about a quarter of a second in (Siri: 0.27 s)")
    check(abs(grow.progress(at: 0.6) - 1) < 0.01, "siri look: it is still by six tenths of a second")
    check((0...100).allSatisfy { shrink.progress(at: Double($0) / 100) <= 1.0001 } && shrink.progress(at: 0.3) > 0.97,
          "siri look: shrinking is faster and never overshoots, done in about 0.3 s")
    check(S.Motion.reveal.response > grow.response && S.Motion.appear.response < shrink.response,
          "siri look: the controls arrive more slowly than the panel grows, and the field appears faster than anything")
}

private func siriLookWiringTests() {
    let root = siriLookSource("Aris/private/Notch/ArisNotchRoot.swift")
    check(root.contains("ArisSiriLookGate.refresh(open: open") && root.contains("siri ? ArisSiriLookSurface(shape: shape, open: open, band: siriBand")
          && root.contains(".background(siri ? nil : ArisGlassSurface(shape: shape, open: open, hidden: hidden, safeTop: glassSafeTop,"),
          "siri look: the notch reads the look as its surface is built; the notch's own glass, private parts and all, is in the tree only when the look is off, and Siri's surface only when it is on")
    check(root.contains(".background(ArisSiriLookScrim())") && root.contains(".coordinateSpace(name: ArisSiriLookScrim.space)") && root.contains("isOpen ? vm.openBandHeight : displayedHeight"),
          "siri look: every open page stands on the scrim, which is told the surface's own height and band (no size is assumed)")
    check(!root.contains("440") && !siriLookSource("Aris/private/Aris/SiriLook/ArisSiriLookSurface.swift").contains("440")
          && !siriLookSource("Aris/private/Aris/SiriLook/ArisSiriLookControls.swift").contains("440"),
          "siri look: nothing the look draws assumes the notch's width")
    check(!root.contains("ArisSiriLookRim"), "siri look: the first attempt's coloured light round the outline is gone")
    let header = siriLookSource("Aris/private/Aris/Home/ArisNotchHeader.swift")
    check(header.contains("ArisLiveVoiceGlyph(mode: aris.session.phase.glyphMode)\n") && header.contains(".modifier(ArisSiriLookWorkingMark(phase: aris.session.phase))")
          && header.contains(".background { ArisMarkHalo(halo: halo) }") && header.contains(".frame(width: ArisVNotch.orbBox, height: ArisVNotch.orbBox)"),
          "siri look: the working mark's ring of dots sits on the band's own glyph, in its seat and box, with the halo behind it as ever")
    check(header.contains("ArisSiriLookRoundButton(symbol: \"xmark\"") && header.contains(".padding(.trailing, working ? Self.closeBesideStop : 0)\n")
          && header.contains("ArisHandsFreeLock { aris.stopFromTag() }") && header.contains("ArisMuteSwitch(shown: showsGlyph && ArisVNotch.voiceSwitchOffered("),
          "siri look: close and stop are Siri's round glass buttons in the band's own slot; the hands-free lock and the voice switch are untouched")
    let hooks = siriLookSource("Aris/private/Aris/SiriLook/ArisSiriLookHooks.swift")
    check(hooks.contains("phase.glyphMode == .loading") && hooks.contains(".opacity(dots ? 0 : 1)") && !hooks.contains("ArisLiveVoiceGlyph("),
          "siri look: only the working mark is replaced, by hiding it under the dots; listening and speaking keep Aris's own bars and star")
    let turn = siriLookSource("Aris/private/Aris/Home/ArisTurnView.swift")
    check(turn.contains("ArisSiriLookBubble(text: text") && turn.contains("ArisSiriLookNow.on && draft == nil && !previewEditing"),
          "siri look: your words are drawn as the bubble, and a request being edited goes back to the card and its editor")
    check(turn.contains("ArisPromptPencil { draft = text }.transition(.opacity)") && turn.contains("if case .edits = ArisPromptEdit.tap(lines: 1, offer: edit) { draft = text }"),
          "siri look: the bubble offers the card's own pencil under the pointer, and a tap edits where the card's tap would")
    check(turn.contains("if draft != nil, edit == .editable(saysDone: true) { ArisPromptDoneNote() }") && turn.contains(".onChange(of: draft != nil) { _, editing in ArisPromptEditing.shared.set(editing) }"),
          "siri look: the card's own done-note and editing rules are word for word as they were")
    check(siriLookSource("Aris/private/Aris/Currency/ArisCurrencyCardView.swift").contains("cornerRadius: ArisWidgetStyle.radius"),
          "siri look: the currency card takes the look's corner radius as the other cards do")
    check(siriLookSource("Aris/private/Aris/Home/ArisComposer.swift").contains("ArisSiriLookFieldRow("), "siri look: the field's row has the round + and microphone")
    check(siriLookSource("Aris/private/Aris/Home/ArisActivityTag.swift").contains("ArisSiriLookDots(size: 11)"), "siri look: a running tag carries the dots")
    let own = ["ArisSiriLook.swift", "ArisSiriLookSurface.swift", "ArisSiriLookControls.swift", "ArisSiriLookHooks.swift", "ArisSiriLookGate.swift", "ArisSiriLookAttach.swift"]
        .map { siriLookSource("Aris/private/Aris/SiriLook/" + $0) }
    check(own.allSatisfy { !$0.isEmpty } && own.allSatisfy { text in !["NSClassFromString", "perform(", "IntelligenceUI", "SiriUI", "metallib", "set_variant", "_setPath"].contains { text.contains($0) } },
          "siri look: the look is Aris's own drawing: no private class, selector, shader or asset of Apple's")
    check(own.allSatisfy { !$0.contains("repeatForever") }, "siri look: nothing in the look pulses on a repeating animation")
    for file in ["Aris/private/Aris/Design/ArisGlass.swift", "Aris/private/Aris/Design/ArisGlassRecipe.swift"] {
        check(!siriLookSource(file).contains("SiriLook"), "siri look: the glass files are another branch's and are not touched (\(file))")
    }
}

/// The scrim behind the content column, and what every kind of text then stands at over a pure white window.
private func siriLookScrimTests() {
    let base = S.Surface.clearBase
    var held = true, onlyDown = true, darkUntouched = true
    for (height, band) in [(160.0, 32.0), (203, 37), (300, 37), (540, 37), (300, 44), (640, 44)] {
        var last = 0.0
        for step in 0...60 {
            let y = band + (height - band) * Double(step) / 60
            let alpha = S.Scrim.alpha(at: y, height: height, band: band, base: base)
            if S.Scrim.through(at: y, height: height, band: band, base: base) * (1 - alpha) > 1 - S.Scrim.floor + 0.0001 { held = false }
            if alpha < last - 0.0001 { onlyDown = false }
            last = alpha
            let plain = S.Scrim.reads(at: y, height: height, band: band, behind: 0, base: base, scrim: false)
            if S.Scrim.reads(at: y, height: height, band: band, behind: 0, base: base, scrim: true) > plain + 0.0001 { darkUntouched = false }
        }
    }
    check(held, "siri look: behind the content never more than a tenth of a white window comes through, whatever the notch's height or band")
    check(onlyDown, "siri look: the scrim only ever thickens on the way down, as the fill thins")
    check(darkUntouched, "siri look: over a dark backdrop the scrim lightens nothing")
    check(S.Scrim.alpha(at: 60, height: 300, band: 37, base: base) == 0 && S.Scrim.alpha(at: 292, height: 300, band: 37, base: base) > 0.6,
          "siri look: high up, where Siri's own black is enough, there is no scrim at all; at the bottom it does most of the work")
    let stops = S.Scrim.stops(top: 39, bottom: 292, height: 300, band: 37, base: base)
    check(stops.count == 11 && stops[0].location == 0 && stops[10].location == 1 && near(stops[10].alpha, S.Scrim.alpha(at: 292, height: 300, band: 37, base: base)),
          "siri look: the scrim is drawn as eleven stops from the column's top to its bottom")

    // Every kind of text Aris draws, at the worst place (the bottom of the column) and through the heights between.
    let inks: [(name: String, ink: Double, glass: Bool, fill: Double, least: Double)] = [
        ("the answer's running text", S.Answer.ink, false, 0, 4.5), ("strong words and card titles", 0.95, false, 0.06, 4.5),
        ("secondary lines (music, shelf, day-end, first tries, receipts)", 0.5, false, 0, 4.5),
        ("secondary lines on a row's or a card's own fill (the timer row, cards)", 0.5, false, 0.06, 4.5),
        ("quoted and quiet document text", 0.65, false, 0, 4.5), ("a finished tag's words", 0.5, false, 0.06, 4.5),
        ("what is typed in the field", 0.95, true, 0, 4.5), ("the field's hint", S.Field.arisHintInk, true, 0, 4.5),
        ("a running tag's words", 0.74, true, 0, 4.5), ("your words in the bubble", S.Bubble.ink, true, 0, 4.5),
        ("the bubble's hint while listening", S.Bubble.quietInk, true, 0, 4.5), ("the round buttons' glyphs", S.Control.glyphInk, true, 0, 3),
    ]
    for item in inks {
        var worst = Double.infinity, bare = Double.infinity
        for (height, band) in [(160.0, 32.0), (203, 37), (300, 37), (540, 37), (300, 44)] {
            for step in 0...40 {
                let y = band + (height - 8 - band) * Double(step) / 40
                worst = min(worst, S.contrast(ink: item.ink, on: S.Scrim.reads(at: y, height: height, band: band, behind: 255, base: base, scrim: true), glass: item.glass, fill: item.fill))
                bare = min(bare, S.contrast(ink: item.ink, on: S.Scrim.reads(at: y, height: height, band: band, behind: 255, base: base, scrim: false), glass: item.glass, fill: item.fill))
            }
        }
        check(worst >= item.least, "siri look: over a pure white window \(item.name) keeps \(item.least):1 anywhere in the content (worst \(String(format: "%.1f", worst)):1; without the scrim \(String(format: "%.1f", bare)):1)")
    }
    let bottom = S.Scrim.reads(at: 292, height: 300, band: 37, behind: 255, base: base, scrim: true)
    check(S.contrast(ink: 0.42, on: bottom) >= 3 && S.contrast(ink: 0.38, on: bottom, fill: 0.06) >= 3 && S.contrast(ink: 0.43, on: 0) < 4.5,
          "siri look: Aris's quietest labels (white .38 to .43) keep 3:1 over white; they are under 4.5:1 even over black, which no fill can change")
    check(near(S.Scrim.reads(at: 250, height: 300, band: 37, behind: 255, base: base, scrim: true), 33, 8),
          "siri look: behind content over a white window the surface reads about 33 of 255 (the VM read 43 to 48 when the floor was .86)")
    check(S.Scrim.alpha(at: 292, height: 300, band: 37, base: S.Surface.frostBase) > 0 && S.Scrim.alpha(at: 292, height: 300, band: 37, base: S.Surface.frostBase) < S.Scrim.alpha(at: 292, height: 300, band: 37, base: base),
          "siri look: over the frosted glass, which holds more back itself, the scrim adds less")
    check(S.Bubble.quietInk > S.Bubble.restingInk && S.Field.arisHintInk > S.Field.hintInk, "siri look: hints Aris means to be read are stronger than Siri's resting ones")
}

func runSiriLookTests() {
    siriLookScrimTests()
    siriLookResolutionTests()
    siriLookSurfaceTests()
    siriLookControlTests()
    siriLookDotsTests()
    siriLookMotionTests()
    siriLookWiringTests()
}
