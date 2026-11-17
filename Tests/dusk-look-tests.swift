// Tests for the hidden "dusk" look (arisVoiceLook): which look a preference means and when it is read, the surface's
// fill against what the system assistant's own panel read over a white window and over black in the owner's captures (macOS 27.2,
// 2026-11-11), the control glass solved from the same two readings, the sizes and type read from the screenshots,
// the working dots (a smooth turning and swelling, never a blink), the springs fitted to the recording, and the
// places the look is switched in. Called from main.swift; uses its check(). Nothing is drawn on screen.
import Foundation

private typealias S = ArisDuskLook

private func near(_ a: Double, _ b: Double, _ tolerance: Double = 0.001) -> Bool { abs(a - b) <= tolerance }

private func duskLookSource(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

private func duskLookResolutionTests() {
    check(ArisVoiceLook.resolve(nil) == .aris && ArisVoiceLook.resolve("") == .aris && ArisVoiceLook.resolve("orb") == .aris,
          "dusk look: with no preference, or one Aris doesn't know, Aris is drawn as today")
    check(ArisVoiceLook.resolve("dusk") == .dusk && ArisVoiceLook.resolve(" Dusk\n") == .dusk && ArisVoiceLook.resolve("aris") == .aris,
          "dusk look: arisVoiceLook dusk switches the look on, however it is capitalised; aris is today's")
    check(ArisVoiceLook.resolve("dusk-frost") == .duskFrost && ArisVoiceLook.duskFrost.isDusk && ArisVoiceLook.dusk.isDusk && !ArisVoiceLook.aris.isDusk,
          "dusk look: dusk-frost is the same look over the system's frosted glass, to compare on a real screen")
    check(ArisVoiceLook.resolve("dusk-screen") == .aris, "dusk look: there is no whole-screen light: dusk-screen is not a look and stays today's")
    check(ArisVoiceLook.key == "arisVoiceLook", "dusk look: the one preference is arisVoiceLook")
    check(ArisDuskLookNow.look == .aris && !ArisDuskLookNow.on, "dusk look: until the preference says otherwise the look in force is today's")

    var stored: String? = nil
    var reads = 0
    let latch = ArisVoiceLookLatch { reads += 1; return stored }
    let closedIdle = ArisDuskLookMoment.name(open: false, state: "idle"), openIdle = ArisDuskLookMoment.name(open: true, state: "idle")
    check(latch.look(entering: closedIdle) == .aris && reads == 1, "dusk look: the preference is read when a state begins")
    stored = "dusk"
    check(latch.look(entering: closedIdle) == .aris && reads == 1, "dusk look: it is not read again while nothing has changed")
    check(closedIdle != openIdle && latch.look(entering: openIdle) == .dusk && reads == 2,
          "dusk look: the notch opening is a moment the preference is read at, so a defaults write shows at the next open with no rebuild or restart")
    check(ArisDuskLookMoment.name(open: true, state: "thinking") != openIdle, "dusk look: a voice state beginning is such a moment too")
    stored = "aris"
    check(latch.look(entering: openIdle) == .dusk && latch.look(entering: closedIdle) == .aris,
          "dusk look: switching back takes effect at the next moment too, never halfway through one")
}

private func duskLookSurfaceTests() {
    let closed = S.Surface.stops(height: 300, band: 37, open: false, glass: true)
    let solid = S.Surface.stops(height: 300, band: 37, open: true, glass: false)
    check(closed.count == 4 && closed.allSatisfy { $0.coverage == 1 && $0.grey == 0 }, "dusk look: the closed notch is solid black, as today")
    check(solid.allSatisfy { $0.coverage == 1 && $0.grey == 0 }, "dusk look: with Reduce Transparency the open notch is solid black")
    let open = S.Surface.stops(height: 300, band: 37, open: true, glass: true)
    check(open.count == 4 && open[0].coverage == 1 && open[1].coverage == 1 && near(open[1].location, 37.0 / 300),
          "dusk look: the band beside the camera housing stays full black, so the notch still disappears into the hardware")
    check(zip(open, open.dropFirst()).allSatisfy { $0.coverage >= $1.coverage && $0.location <= $1.location && $0.grey <= $1.grey },
          "dusk look: under the band the black only ever thins, and lightens, on the way down")
    check(near(open[3].coverage, 0.40) && near(open[3].grey, 70.0 / 255), "dusk look: the bottom edge is the system assistant's clear end: .40 of a grey of 70")
    check([120.0, 172, 276, 600].allSatisfy { S.Surface.stops(height: $0, band: 37, open: true, glass: true).last == open.last },
          "dusk look: the fill ends the same however tall the notch is, as the system assistant's 172, 276 and 600-point panels do")
    check(S.Surface.stops(height: 20, band: 37, open: true, glass: true).allSatisfy { $0.location <= 1 },
          "dusk look: a notch shorter than its band (mid-way through opening) still has its stops in order")

    // The system assistant's own panel has no band: its readings are checked against a band of nothing.
    check(S.Surface.reads(at: 0, height: 172, band: 0, behind: 255) <= 8.5, "dusk look: the top reads black over a white window (the system assistant: 8 of 255)")
    check(near(S.Surface.reads(at: 300, height: 600, band: 0, behind: 255), 83, 5) && near(S.Surface.reads(at: 300, height: 600, band: 0, behind: 0), 11.6, 1),
          "dusk look: half-way down it reads what the system assistant's reads over white (83) and over black (11.6)")
    check(near(S.Surface.reads(at: 600, height: 600, band: 0, behind: 255), 182, 4) && near(S.Surface.reads(at: 600, height: 600, band: 0, behind: 0), 28, 1),
          "dusk look: at the bottom it reads what the system assistant's reads over white (182) and over black (28)")
    check(S.Surface.reads(at: 20, height: 300, band: 37, behind: 255) == 0, "dusk look: in Aris's band nothing of a white window shows")
    // Over Aris's clear glass, which already takes some of what is behind it, the fill is thinner by that much.
    let bottom = S.Surface.stops(height: 300, band: 37, open: true, glass: true, base: S.Surface.clearBase)[3]
    check(near(1 - (1 - S.Surface.clearBase) * (1 - bottom.coverage), S.Surface.bottomCoverage) && near(bottom.grey * bottom.coverage, S.Surface.bottomGrey * S.Surface.bottomCoverage),
          "dusk look: the glass and the fill over it together take what the system assistant's surface takes, and the fill keeps its light")
    check(near(S.Surface.reads(at: 600, height: 600, band: 0, behind: 255, base: S.Surface.clearBase), 182, 4)
          && near(S.Surface.reads(at: 600, height: 600, band: 0, behind: 0, base: S.Surface.clearBase), 28, 1),
          "dusk look: over Aris's clear glass the bottom still reads the system assistant's 182 over white and 28 over black")
    check(S.Surface.stops(height: 300, band: 37, open: true, glass: true, base: S.Surface.clearBase)[1].coverage == 1,
          "dusk look: the band is full black over the glass too")
    check(S.Surface.over(S.Surface.frostBase, S.Stop(location: 1, coverage: S.Surface.bottomCoverage, grey: S.Surface.bottomGrey)).coverage == 0,
          "dusk look: the frosted glass alone already takes more than the system assistant's bottom does, so nothing is drawn over it there (dusk-frost is darker than the system assistant)")
    check(S.Surface.over(0, open[3]) == open[3], "dusk look: with no glass under it the fill is the system assistant's own numbers")
    check(near(S.Surface.shadowAlpha * 0.5, 0.20, 0.01), "dusk look: the shadow darkens a white window by a fifth at the side edges, as the system assistant's does")
    check(S.Surface.rimBottom > S.Surface.rimTop && S.Surface.rimTop > S.Surface.rimSide && S.Surface.rimWidth == 0.5,
          "dusk look: the rim is half a point, strongest along the bottom")
}

private func duskLookControlTests() {
    func reads(_ behind: Double) -> Double { behind * (1 - S.Control.alpha) + 255 * S.Control.grey * S.Control.alpha }
    check(near(reads(3), 34, 2.5), "dusk look: a round button over the black top reads lighter than it, as the system assistant's does (34 over 3)")
    check(near(reads(169), 148, 2.5) && reads(169) < 169, "dusk look: over the light bottom on a white window the same glass reads darker than it (148 over 169)")
    check(S.Control.size == 36 && S.Control.inset == 16 && S.Control.gap == 12 && S.Field.height == 36,
          "dusk look: the field's row is the system assistant's: 36-point circles, a 36-point pill, 12 between them")
    check(S.Control.size + S.Control.gap + 292 + S.Control.gap + S.Control.size + 2 * S.Control.inset == S.Surface.width,
          "dusk look: those sizes add up to the system assistant's 420-point panel with its 292-point pill")
    check(S.Control.bandSize(band: 37) == 28 && S.Control.bandSize(band: 44) == 33 && S.Control.bandSize(band: 38) == 29,
          "dusk look: the band's round buttons are sized from the band they sit in: 28 in a 37-point band, 33 in a 44-point one")
    check(S.Control.bandSize(band: 400) == S.Control.size && S.Control.bandSize(band: 0) == 20 && [32.0, 37, 44].allSatisfy { S.Control.bandSize(band: $0) < $0 },
          "dusk look: they never outgrow the system assistant's 36 points or the band itself")
    check(S.Bubble.height == 30 && S.Bubble.radius == 15 && S.Bubble.fontSize == 13 && S.Bubble.tailHeight < S.Bubble.tailWidth,
          "dusk look: your words are a 30-point capsule of 13-point type with a small tail")
    check(S.Answer.fontSize == 15 && S.Answer.lineHeight == 18 && S.Answer.ink == 0.90, "dusk look: the answer is 15-point type on an 18-point line at white .90")
    check(S.Card.radius == 32 && S.Card.inset == 16, "dusk look: a card's corners are 32, as the system assistant's weather card's")
    check(S.Field.hintInk < S.Answer.ink && S.Field.fontSize == 15, "dusk look: the field's hint is quieter than the answer and the same size")
}

private func duskLookDotsTests() {
    let now = (0..<S.Dots.count).map { S.Dots.dot($0, at: 0.3) }
    check(S.Dots.count == 6 && zip(now, now.dropFirst()).allSatisfy { near($1.angle - $0.angle, Double.pi / 3) },
          "dusk look: the working mark is six dots evenly round a ring")
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
    check(inRange && smallest > 0.1, "dusk look: no dot ever goes out: each stays between the system assistant's 3.8 and 9 points across (no blinking)")
    check(smooth, "dusk look: from one frame to the next a dot only swells or moves a little: a travelling, breathing motion")
    check(near(biggest, high, 0.005) && near(smallest, low, 0.005), "dusk look: over time every dot reaches both sizes")
    check(near(S.Dots.dot(0, at: S.Dots.turn).angle - S.Dots.dot(0, at: 0).angle, 2 * Double.pi), "dusk look: the ring turns once in 7.6 seconds")
    check(near(S.Dots.dot(2, at: 0.4).size, S.Dots.dot(2, at: 0.4 + S.Dots.wave).size), "dusk look: the swelling goes round once in 0.95 seconds")
    let peak = (0..<S.Dots.count).map { index in (0..<95).max { S.Dots.dot(index, at: Double($0) / 100).size < S.Dots.dot(index, at: Double($1) / 100).size } ?? 0 }
    check(zip(peak, peak.dropFirst()).allSatisfy { $1 > $0 }, "dusk look: each dot swells a moment after the one before it, so the swelling travels round the ring")
    check((0..<S.Dots.count).allSatisfy { S.Dots.dot($0, at: 0, reduceMotion: true).size == S.Dots.dot($0, at: 5.3, reduceMotion: true).size
              && S.Dots.dot($0, at: 0, reduceMotion: true).angle == S.Dots.dot($0, at: 5.3, reduceMotion: true).angle },
          "dusk look: with Reduce Motion the ring is one still picture")
}

private func duskLookMotionTests() {
    let grow = S.Motion.grow, shrink = S.Motion.shrink
    let samples = (0...100).map { grow.progress(at: Double($0) / 100) }
    let top = samples.max() ?? 0, at = Double(samples.firstIndex(of: top) ?? 0) / 100
    check(grow.progress(at: 0) == 0 && top > 1.015 && top < 1.04, "dusk look: growing passes its size by a few percent, as the system assistant's panel does (about 2.7 %)")
    check(at > 0.2 && at < 0.36, "dusk look: the overshoot comes about a quarter of a second in (the system assistant: 0.27 s)")
    check(abs(grow.progress(at: 0.6) - 1) < 0.01, "dusk look: it is still by six tenths of a second")
    check((0...100).allSatisfy { shrink.progress(at: Double($0) / 100) <= 1.0001 } && shrink.progress(at: 0.3) > 0.97,
          "dusk look: shrinking is faster and never overshoots, done in about 0.3 s")
    check(S.Motion.reveal.response > grow.response && S.Motion.appear.response < shrink.response,
          "dusk look: the controls arrive more slowly than the panel grows, and the field appears faster than anything")
}

private func duskLookWiringTests() {
    let root = duskLookSource("Aris/private/Notch/ArisNotchRoot.swift")
    check(root.contains("ArisDuskLookGate.refresh(open: open") && root.contains("dusk ? ArisDuskLookSurface(shape: shape, open: open, band: duskBand")
          && root.contains(".background(dusk ? nil : ArisGlassSurface(shape: shape, open: open, hidden: hidden, safeTop: glassSafeTop,"),
          "dusk look: the notch reads the look as its surface is built; the notch's own glass, private parts and all, is in the tree only when the look is off, and the system assistant's surface only when it is on")
    check(root.contains(".background(ArisDuskLookScrim())") && root.contains(".coordinateSpace(name: ArisDuskLookScrim.space)") && root.contains("isOpen ? vm.openBandHeight : displayedHeight"),
          "dusk look: every open page stands on the scrim, which is told the surface's own height and band (no size is assumed)")
    check(!root.contains("440") && !duskLookSource("Aris/private/Aris/DuskLook/ArisDuskLookSurface.swift").contains("440")
          && !duskLookSource("Aris/private/Aris/DuskLook/ArisDuskLookControls.swift").contains("440"),
          "dusk look: nothing the look draws assumes the notch's width")
    check(!root.contains("ArisDuskLookRim"), "dusk look: the first attempt's coloured light round the outline is gone")
    let header = duskLookSource("Aris/private/Aris/Home/ArisNotchHeader.swift")
    check(header.contains("ArisLiveVoiceGlyph(mode: aris.session.phase.glyphMode)\n") && header.contains(".modifier(ArisDuskLookWorkingMark(phase: aris.session.phase))")
          && header.contains(".background { ArisMarkHalo(halo: halo) }") && header.contains(".frame(width: ArisVNotch.orbBox, height: ArisVNotch.orbBox)"),
          "dusk look: the working mark's ring of dots sits on the band's own glyph, in its seat and box, with the halo behind it as ever")
    check(header.contains("ArisDuskLookRoundButton(symbol: \"xmark\"") && header.contains(".padding(.trailing, working ? Self.closeBesideStop : 0)\n")
          && header.contains("ArisHandsFreeLock { aris.stopFromTag() }") && header.contains("ArisMuteSwitch(shown: showsGlyph && ArisVNotch.voiceSwitchOffered("),
          "dusk look: close and stop are the system assistant's round glass buttons in the band's own slot; the hands-free lock and the voice switch are untouched")
    let hooks = duskLookSource("Aris/private/Aris/DuskLook/ArisDuskLookHooks.swift")
    check(hooks.contains("phase.glyphMode == .loading") && hooks.contains(".opacity(dots ? 0 : 1)") && !hooks.contains("ArisLiveVoiceGlyph("),
          "dusk look: only the working mark is replaced, by hiding it under the dots; listening and speaking keep Aris's own bars and star")
    let turn = duskLookSource("Aris/private/Aris/Home/ArisTurnView.swift")
    check(turn.contains("ArisDuskLookBubble(text: text") && turn.contains("ArisDuskLookNow.on && draft == nil && !previewEditing"),
          "dusk look: your words are drawn as the bubble, and a request being edited goes back to the card and its editor")
    check(turn.contains("ArisPromptPencil { draft = text }.transition(.opacity)") && turn.contains("if case .edits = ArisPromptEdit.tap(lines: 1, offer: edit) { draft = text }"),
          "dusk look: the bubble offers the card's own pencil under the pointer, and a tap edits where the card's tap would")
    check(turn.contains("if draft != nil, edit == .editable(saysDone: true) { ArisPromptDoneNote() }") && turn.contains(".onChange(of: draft != nil) { _, editing in ArisPromptEditing.shared.set(editing) }"),
          "dusk look: the card's own done-note and editing rules are word for word as they were")
    check(duskLookSource("Aris/private/Aris/Currency/ArisCurrencyCardView.swift").contains("cornerRadius: ArisWidgetStyle.radius"),
          "dusk look: the currency card takes the look's corner radius as the other cards do")
    check(duskLookSource("Aris/private/Aris/Home/ArisComposer.swift").contains("ArisDuskLookFieldRow("), "dusk look: the field's row has the round + and microphone")
    check(duskLookSource("Aris/private/Aris/Home/ArisActivityTag.swift").contains("ArisDuskLookDots(size: 11)"), "dusk look: a running tag carries the dots")
    let own = ["ArisDuskLook.swift", "ArisDuskLookSurface.swift", "ArisDuskLookControls.swift", "ArisDuskLookHooks.swift", "ArisDuskLookGate.swift", "ArisDuskLookAttach.swift"]
        .map { duskLookSource("Aris/private/Aris/DuskLook/" + $0) }
    check(own.allSatisfy { !$0.isEmpty } && own.allSatisfy { text in !["NSClassFromString", "perform(", "IntelligenceUI", "metallib", "set_variant", "_setPath"].contains { text.contains($0) } },
          "dusk look: the look is Aris's own drawing: no private class, selector, shader or asset of Apple's")
    check(own.allSatisfy { !$0.contains("repeatForever") }, "dusk look: nothing in the look pulses on a repeating animation")
    for file in ["Aris/private/Aris/Design/ArisGlass.swift", "Aris/private/Aris/Design/ArisGlassRecipe.swift"] {
        check(!duskLookSource(file).contains("DuskLook"), "dusk look: the glass files are another branch's and are not touched (\(file))")
    }
}

/// The scrim behind the content column, and what every kind of text then stands at over a pure white window.
private func duskLookScrimTests() {
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
    check(held, "dusk look: behind the content never more than a tenth of a white window comes through, whatever the notch's height or band")
    check(onlyDown, "dusk look: the scrim only ever thickens on the way down, as the fill thins")
    check(darkUntouched, "dusk look: over a dark backdrop the scrim lightens nothing")
    check(S.Scrim.alpha(at: 60, height: 300, band: 37, base: base) == 0 && S.Scrim.alpha(at: 292, height: 300, band: 37, base: base) > 0.6,
          "dusk look: high up, where the system assistant's own black is enough, there is no scrim at all; at the bottom it does most of the work")
    let stops = S.Scrim.stops(top: 39, bottom: 292, height: 300, band: 37, base: base)
    check(stops.count == 11 && stops[0].location == 0 && stops[10].location == 1 && near(stops[10].alpha, S.Scrim.alpha(at: 292, height: 300, band: 37, base: base)),
          "dusk look: the scrim is drawn as eleven stops from the column's top to its bottom")

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
        check(worst >= item.least, "dusk look: over a pure white window \(item.name) keeps \(item.least):1 anywhere in the content (worst \(String(format: "%.1f", worst)):1; without the scrim \(String(format: "%.1f", bare)):1)")
    }
    let bottom = S.Scrim.reads(at: 292, height: 300, band: 37, behind: 255, base: base, scrim: true)
    check(S.contrast(ink: 0.42, on: bottom) >= 3 && S.contrast(ink: 0.38, on: bottom, fill: 0.06) >= 3 && S.contrast(ink: 0.43, on: 0) < 4.5,
          "dusk look: Aris's quietest labels (white .38 to .43) keep 3:1 over white; they are under 4.5:1 even over black, which no fill can change")
    check(near(S.Scrim.reads(at: 250, height: 300, band: 37, behind: 255, base: base, scrim: true), 33, 8),
          "dusk look: behind content over a white window the surface reads about 33 of 255 (the VM read 43 to 48 when the floor was .86)")
    check(S.Scrim.alpha(at: 292, height: 300, band: 37, base: S.Surface.frostBase) > 0 && S.Scrim.alpha(at: 292, height: 300, band: 37, base: S.Surface.frostBase) < S.Scrim.alpha(at: 292, height: 300, band: 37, base: base),
          "dusk look: over the frosted glass, which holds more back itself, the scrim adds less")
    check(S.Bubble.quietInk > S.Bubble.restingInk && S.Field.arisHintInk > S.Field.hintInk, "dusk look: hints Aris means to be read are stronger than the system assistant's resting ones")
}

func runDuskLookTests() {
    duskLookScrimTests()
    duskLookResolutionTests()
    duskLookSurfaceTests()
    duskLookControlTests()
    duskLookDotsTests()
    duskLookMotionTests()
    duskLookWiringTests()
}
