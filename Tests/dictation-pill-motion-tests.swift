// Tests for the dictation pill re-measured from the reference pill (2026-11-17, the user: it should work and move like it): the
// curve every change runs on (0.1 s cubic-bezier(0.05, 0.6, 0.4, 0.95)) and its CSS reversal shortening, the hover's
// 100 ms hold (at once, then held; a flickering edge never jolts it) and its hot area, the level (adaptive floor in dB,
// 150 ms average, 0.85 easing in .01 steps at 60 Hz, max(1, 5 × it)), the 10 bars (2 wide, 2 apart, the bulge, the
// staggered 1 s wave), the 8-spoke spinner, and the wiring (one animated size for the outline, the content and its
// clip; Reduce Motion fallbacks). Called from main.swift. Nothing is drawn.
import CoreGraphics
import Foundation

private typealias R = ArisDictationPillRules
private typealias W = ArisDictationPillWave
private typealias S = ArisDictationPillSpinner

private func dictationMotionSource(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

private func near(_ a: Double, _ b: Double, _ e: Double = 1e-3) -> Bool { abs(a - b) <= e }

func runDictationPillMotionTests() {
    dictationCurveTests()
    dictationReversalTests()
    dictationHoverLockTests()
    dictationLevelTests()
    dictationWaveTests()
    dictationSpinnerTests()
    dictationMotionWiringTests()
}

// MARK: - The curve

private func dictationCurveTests() {
    check(R.sizeDuration == 0.1 && R.sizeCurve == ArisDictationPillCurve(0.05, 0.6, 0.4, 0.95),
          "dictation motion: every change 0.1 s on cubic-bezier(0.05, 0.6, 0.4, 0.95)")
    check(R.showDuration == 0.1 && R.showCurve == .ease, "dictation motion: show / hide 0.1 s ease (opacity alone)")
    let c = R.sizeCurve
    check(c.value(at: 0) == 0 && c.value(at: 1) == 1, "dictation curve: 0 → 0, 1 → 1")
    var last = -1.0, rising = true
    for step in 0...100 { let v = c.value(at: Double(step) / 100); if v < last - 1e-9 { rising = false }; last = v }
    check(rising, "dictation curve: it only rises")
    // A fast start: past half the way by a fifth of the time (y1 .6 at x1 .05).
    check(c.value(at: 0.2) > 0.5 && c.value(at: 0.5) > 0.85, "dictation curve: half-way by 20 ms, 85 % by 50 ms (\(c.value(at: 0.2)), \(c.value(at: 0.5)))")
    // Checked against the curve's own parametric form at t = .5: x = .29375 (3·.25·.5·.05 + 3·.5·.25·.4 + .125), y = .70625.
    check(near(c.value(at: 0.29375), 0.70625, 1e-4), "dictation curve: solved at a known point")
    check(near(ArisDictationPillCurve.easeInOut.value(at: 0.5), 0.5, 1e-6) && near(ArisDictationPillCurve.ease.value(at: 0.25), 0.4094, 2e-3),
          "dictation curve: CSS ease-in-out .5 → .5, ease .25 → .41")
}

// MARK: - A reversal mid-way (CSS's reversing shortening factor)

private func dictationReversalTests() {
    var r = R.Reversal()
    r = r.changing(to: .idle, at: 0)
    r = r.changing(to: .hover, at: 1)
    check(r.duration == 0.1 && r.factor == 1, "dictation reversal: a fresh change takes 0.1 s")
    let back = r.changing(to: .idle, at: 1.05)
    let share = R.sizeCurve.value(at: 0.5)
    check(near(back.factor, share, 1e-9) && near(back.duration, 0.1 * share, 1e-9),
          "dictation reversal: turned back at 50 ms → only the share covered (\(Int((back.duration * 1000).rounded())) ms)")
    let again = back.changing(to: .hover, at: 1.05 + back.duration / 2)
    let expected = R.sizeCurve.value(at: 0.5) * back.factor + (1 - back.factor)
    check(near(again.factor, expected, 1e-9), "dictation reversal: a second turn compounds as CSS does")
    let late = r.changing(to: .idle, at: 1.2)
    check(late.duration == 0.1, "dictation reversal: once the change is over, a new one takes the full 0.1 s")
    let other = r.changing(to: .recording(handsFree: false), at: 1.05)
    check(other.duration == 0.1, "dictation reversal: a change elsewhere (not back) takes the full 0.1 s")
}

// MARK: - The hover's hold

private func dictationHoverLockTests() {
    var lock = R.HoverLock()
    check(R.HoverLock.hold == 0.1, "dictation hover: held 100 ms after each change")
    let due = lock.point(true, at: 0)
    check(lock.shown && due == 0.1, "dictation hover: on at once (no wait to grow)")
    // Off and on again inside the hold: the hover stays; the hold restarts from each move.
    check(lock.point(false, at: 0.03) == 0.13 && lock.shown, "dictation hover: off during the hold → still on, the hold restarts")
    check(lock.point(true, at: 0.06) == 0.16 && lock.shown, "dictation hover: back on → still on")
    check(lock.expire(at: 0.16) == nil && lock.shown, "dictation hover: the hold ends on the pointer's last word (on): stays")
    // Off after the hold: at once, then held.
    check(lock.point(false, at: 0.5) == 0.6 && !lock.shown, "dictation hover: off after the hold → folds at once")
    check(lock.point(true, at: 0.55) == 0.65 && !lock.shown, "dictation hover: on 50 ms later → waits for the hold")
    check(lock.expire(at: 0.6) == 0.65, "dictation hover: an early call isn't the end")
    _ = lock.expire(at: 0.65)
    check(lock.shown, "dictation hover: the hold's end follows the pointer (on)")
    // An edge that flickers every 20 ms for 200 ms moves it once, then not until it is quiet.
    var flicker = R.HoverLock()
    var changes = 0, shown = false
    var due2: Double? = flicker.point(true, at: 0)
    if flicker.shown != shown { changes += 1; shown = flicker.shown }
    var t = 0.02
    while t < 0.2 {
        due2 = flicker.point(Int((t * 50).rounded()) % 2 == 0, at: t)
        if flicker.shown != shown { changes += 1; shown = flicker.shown }
        t += 0.02
    }
    if let d = due2 { _ = flicker.expire(at: d) }
    if flicker.shown != shown { changes += 1; shown = flicker.shown }
    check(changes <= 2, "dictation hover: a flickering edge moves it at most twice (\(changes))")
    var cleared = lock
    cleared.clear()
    check(!cleared.shown && cleared.lockedUntil == nil, "dictation hover: cleared with the pill gone")

    // The hot area: the pill and 10 / 6 around it, 12 more once grown.
    check(R.hotPadding == CGSize(width: 10, height: 6) && R.hoverHold == 12, "dictation hover: hot area 10 / 6 around, 12 more on the hover")
    check(R.pointerZone(.idle, size: R.idleSize) == CGSize(width: 60, height: 20), "dictation hover: the sliver's zone 60 × 20")
    check(R.pointerZone(.hover, size: R.hoverSize) == CGSize(width: 94, height: 66), "dictation hover: the hover's zone 94 × 66")
    let zone = R.pointerRect(.idle, size: R.idleSize), pill = R.pillRect(R.idleSize)
    check(zone.midX == pill.midX && zone.midY == pill.midY && zone.contains(pill), "dictation hover: the zone is centred on the pill")
}

// MARK: - The level

private func dictationLevelTests() {
    typealias L = ArisDictationPillLevel
    check(L.floorLimit == -60 && L.range == 20 && L.window == 0.15 && L.keep == 0.85 && L.quantum == 0.01 && L.gain == 5,
          "dictation level: floor ≥ -60 dB over 20 dB, 150 ms average, .85 easing in .01 steps, ×5")
    let level = L()
    check(level.level(db: -10) == 0, "dictation level: above the first floor (0 dB) nothing counts")
    check(level.level(db: -50) == 0 && level.floor == -50, "dictation level: a quieter sample lowers the floor to it")
    check(level.level(db: -40) == 0.5 && level.level(db: -20) == 1, "dictation level: 10 dB over the floor → .5, 20+ → 1")
    check(level.level(db: -90) == 0 && level.floor == -60, "dictation level: the floor never under -60")
    check(L.ease(0, toward: 1) == 0.15 && L.ease(0.01, toward: 0) == 0, "dictation level: one frame .85 / .15, floored to .01")
    check(L.audioScale(0) == 1 && L.audioScale(0.5) == 2.5 && L.audioScale(1) == 5, "dictation level: the bars' scale max(1, 5 × level)")
    check(near(L.decibels(rms: 0.1), -20, 1e-6) && L.decibels(rms: 0) < -190, "dictation level: RMS in dB")

    // Silence then a steady tone: nothing moves for the first window, then it eases up; a 120 Hz display eases at 60 Hz.
    let run = L()
    var t = 0.0, scale = 1.0
    for _ in 0..<30 { scale = run.step(at: t, rms: 0.001); t += 1.0 / 60 }
    check(scale == 1, "dictation level: silence → the bars stand at 1")
    for _ in 0..<9 { scale = run.step(at: t, rms: 0.1); t += 1.0 / 60 }
    check(scale < 2, "dictation level: the first loud samples wait for the window's average, then ease (\(scale))")
    for _ in 0..<60 { scale = run.step(at: t, rms: 0.1); t += 1.0 / 60 }
    check(scale > 4 && scale <= 5, "dictation level: a loud voice → near 5 (\(scale))")
    let fast = L(), slow = L()
    var a = 0.0, b = 0.0
    for i in 0..<240 { a = fast.step(at: Double(i) / 120, rms: i < 30 ? 0.001 : 0.05) }
    for i in 0..<120 { b = slow.step(at: Double(i) / 60, rms: i < 15 ? 0.001 : 0.05) }
    check(abs(a - b) < 0.3, "dictation level: the same easing at 120 Hz as at 60 Hz (\(a) vs \(b))")
    run.reset()
    check(run.floor == 0 && run.smoothed == 0 && run.startedAt == nil, "dictation level: a new dictation starts over")
}

// MARK: - The bars

private func dictationWaveTests() {
    check(W.count == 10 && W.barWidth == 2 && W.gap == 2 && W.barRadius == 0.5 && W.baseHeight == 2 && W.boxHeight == 18,
          "dictation bars: 10 bars 2 wide, 2 apart, radius .5, 2 tall at rest, in an 18 box")
    check(W.width == 46, "dictation bars: 4 + 10 × 2 + 9 × 2 + 4 = 46 wide")
    let profile = (0..<10).map { W.heightScale($0) }
    check(near(profile[0], 0.578125, 1e-9) && near(profile[4], 0.994792, 1e-5) && profile == profile.reversed(),
          "dictation bars: the bulge 1 - d²/48, .578 at the ends, symmetric")
    check((0..<10).map { W.delay($0) }.enumerated().allSatisfy { near($0.element, [0, 0.1, 0.2, 0.3, 0.4, -0.5, -0.4, -0.3, -0.2, -0.1][$0.offset], 1e-9) },
          "dictation bars: staggered 0, .1 … .4, then -.5 … -.1 s")
    check(W.keyframes.map(\.scale) == [1, 1.2, 1.5, 1.1, 1.3, 1] && W.keyframes.map(\.at) == [0, 0.2, 0.4, 0.8, 0.9, 1] && W.period == 1,
          "dictation bars: the wave 1 → 1.2 → 1.5 → 1.1 → 1.3 → 1 over 1 s")
    check(near(W.multiplier(at: 0.4, bar: 0), 1.5, 1e-9) && near(W.multiplier(at: 0.2, bar: 0), 1.2, 1e-9) && near(W.multiplier(at: 0.3, bar: 0), 1.35, 1e-6),
          "dictation bars: on the keys exactly, ease-in-out half-way between")
    check(W.multiplier(at: 0.05, bar: 3) == 1, "dictation bars: a late bar stands at 1 until it starts")
    check(near(W.multiplier(at: 0, bar: 5), W.multiplier(at: 0.5, bar: 0), 1e-9), "dictation bars: an early bar is already .5 s in")
    check(near(W.multiplier(at: 1.4, bar: 0), W.multiplier(at: 0.4, bar: 0), 1e-9), "dictation bars: the wave repeats every second")
    check(W.height(bar: 4, audioScale: 1, t: 0.4, waving: false) == CGFloat(2 * W.heightScale(4)), "dictation bars: still → 2 × the bulge")
    let tallest = (0..<10).map { W.height(bar: $0, audioScale: 5, t: 0.4 + W.delay($0), waving: true) }.max() ?? 0
    check(tallest <= 15 && tallest > 14.8, "dictation bars: at most 2 × 5 × .995 × 1.5 ≈ 14.9 tall (\(tallest))")
}

// MARK: - The spinner

private func dictationSpinnerTests() {
    check(S.size == 16 && S.spokes == 8 && S.spokeWidth == 2 && S.spokeLength == 5 && S.spokeRadius == 1 && S.reach == 6,
          "dictation spinner: 8 spokes 2 × 5 round 1, 6 out, in 16")
    check(near(S.red, 163.0 / 255, 1e-9) && near(S.green, 148.0 / 255, 1e-9) && near(S.blue, 199.0 / 255, 1e-9) && S.brightest == 0.88
          && S.faintest == 0.15 && S.period == 1.1, "dictation spinner: rgb(163, 148, 199) fading .88 → .15 over 1.1 s")
    check((0..<8).map(S.angle) == [0, 45, 90, 135, 180, 225, 270, 315], "dictation spinner: a spoke every 45°")
    check(near(S.delay(7), 0, 1e-12) && near(S.delay(0), -0.9625, 1e-12), "dictation spinner: delay -0.1375 × (7 - spoke)")
    check(near(S.alpha(7, at: 0), 0.88, 1e-9), "dictation spinner: the last spoke starts brightest")
    check(S.alpha(7, at: 0) > S.alpha(6, at: 0) && S.alpha(6, at: 0) > S.alpha(5, at: 0), "dictation spinner: the brightness trails round")
    check(near(S.alpha(3, at: 0.3), S.alpha(3, at: 1.4), 1e-9), "dictation spinner: it repeats every 1.1 s")
    check((0..<8).allSatisfy { S.alpha($0, at: 0.77) >= 0.15 - 1e-9 && S.alpha($0, at: 0.77) <= 0.88 + 1e-9 }, "dictation spinner: between .15 and .88")
}

// MARK: - Wiring

private func dictationMotionWiringTests() {
    let view = dictationMotionSource("Aris/private/Aris/Dictation/ArisDictationPillView.swift")
    let parts = dictationMotionSource("Aris/private/Aris/Dictation/ArisDictationPillParts.swift")
    let center = dictationMotionSource("Aris/private/Aris/Dictation/ArisDictationPillCenter.swift")
    check(view.contains("ArisDictationPillSizing(size: sizePreset ?? size)") && view.contains(".clipShape(ArisDictationPillOutline())"),
          "dictation wiring: one animated size for the body, the content's frame and the clip")
    check(view.contains(".animation(reduceMotion ? nil : sizeAnimation, value: size)") && view.contains(".animation(reduceMotion ? nil : sizeAnimation, value: kind)"),
          "dictation wiring: size and colours on the curve, at once with Reduce Motion")
    check(view.contains("Self.curve(R.sizeCurve, display.sizeDuration)"), "dictation wiring: the size's length is the reversal's")
    check(view.contains(".opacity(shown ? 1 : 0)") && !view.contains("scaleEffect(shown"), "dictation wiring: show / hide by opacity, no scale")
    check(parts.contains("waving: !reduceMotion") && parts.contains("paused: preset != nil || reduceMotion"),
          "dictation wiring: Reduce Motion keeps the voice in the bars but not the wave, and the spinner still")
    check(center.contains("hoverLock.point(on, at: Self.clock())") && center.contains("hoverLock.expire(at: Self.clock())"),
          "dictation wiring: the center feeds the pointer to the hold")
    check(center.contains("ArisDictationPillRules.pointerRect(phase, size: display.size)"), "dictation wiring: the hover counts on the hot area")
    check(center.contains("reversal = reversal.changing(to: phase, at: Self.clock())") && center.contains("shown.sizeDuration = reversal.duration"),
          "dictation wiring: a phase change sets its length from the reversal")
    check(center.contains("level.reset()"), "dictation wiring: the level starts over with each dictation")
    check(!center.contains("ArisHoverIntent") && !center.contains("typedHoldTask"), "dictation wiring: no intent wait and no typed hold (the reference has neither)")
    // No blinking or pulsing dots anywhere in the pill.
    for (name, text) in [("view", view), ("parts", parts)] {
        check(!text.contains("repeatForever") && !text.lowercased().contains("pulse") && !text.lowercased().contains("blink"),
              "dictation wiring: no pulsing or blinking in the \(name)")
    }
}
