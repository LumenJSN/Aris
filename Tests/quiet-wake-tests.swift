// Tests for quiet-wake (the owner's pick "C · 한 바퀴", 2026-11-14): the wake word no longer opens the notch. The closed
// band keeps its size, the star gives its seat to the bars, and the listening rim's light runs exactly one lap
// (ArisRimSweep.period, 2.6 s): the user's voice starting in that lap (the level over the gate, after the call) opens the
// notch with the light carrying on; a lap with no voice ends the turn without a word (false-wake's quiet close). Key
// presses and taps are unchanged. Called from main.swift.
import Foundation

private let quietRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private func quietSource(_ path: String) -> String { (try? String(contentsOf: quietRoot.appendingPathComponent(path), encoding: .utf8)) ?? "" }

func runQuietWakeTests() {
    quietWakeLapTests()
    quietWakeCallTailTests()
    quietWakeOnsetTests()
    quietWakeLapEndTests()
    quietWakeRimTests()
    quietWakeNotchTests()
    quietWakeQuietEndTests()
    quietWakeWiringTests()
}

private typealias Q = ArisQuietWake
private let reading = 0.043

/// Feeds `voice` readings every 43 ms from `from` until `to` (exclusive) and the lap's tick with each.
private func feed(_ q: inout Q, from: Double, to: Double, voice: (Double) -> Bool) {
    var t = from
    while t < to {
        q.level(voice: voice(t), at: t)
        q.tick(at: t)
        t += reading
    }
}

// MARK: - 1. The window is one lap of the rim

private func quietWakeLapTests() {
    check(Q.lap == ArisRimSweep.period && Q.lap == 2.6, "quiet wake: the quiet window is exactly one lap of the listening rim (2.6 s)")
    let q = Q(wokeAt: 10)
    check(q.state == .waiting && q.callOverAt == nil, "quiet wake: a wake starts waiting, the call not yet over")
    check(Q(wokeAt: 10, saidMore: true).state == .heard, "quiet wake: a check that already heard words after the name ('아리스 타이머 3분') opens at once")
    var ticked = Q(wokeAt: 10)
    check(ticked.tick(at: 12.59) == .waiting, "quiet wake: before the lap's end the clock alone changes nothing")
    check(ticked.tick(at: 12.6) == .unheard, "quiet wake: at the lap's end with nothing heard, the turn ends quietly")
    check(ticked.tick(at: 20) == .unheard && ticked.level(voice: true, at: 13) == .unheard && ticked.words(at: 13) == .unheard,
          "quiet wake: an ended lap stays ended (a later voice or word doesn't reopen it)")
}

// MARK: - 2. The call's own tail is never the onset

private func quietWakeCallTailTests() {
    // The wake fires mid-name: voice for 0.35 s more, then silence for the rest of the lap.
    var q = Q(wokeAt: 0)
    feed(&q, from: 0, to: 0.35) { _ in true }
    check(q.state == .waiting && q.callOverAt == nil, "call: the name's tail after the wake is not the user starting to talk")
    feed(&q, from: 0.35, to: 0.6) { _ in false }
    check(q.state == .waiting && q.callOverAt != nil, "call: 150 ms under the gate and the call is over")
    feed(&q, from: 0.6, to: 2.7) { _ in false }
    check(q.state == .unheard, "call: a call followed by silence for the whole lap ends unheard (a false wake, closed quietly)")

    // A long call (or the TV) voiced for the first second: still nothing heard while the call may be going.
    var long = Q(wokeAt: 0)
    feed(&long, from: 0, to: 0.95) { _ in true }
    check(long.state == .waiting, "call: voice within the first second is still taken as the call")

    // A short dip inside the name (under 150 ms) doesn't end the call.
    var dip = Q(wokeAt: 0)
    feed(&dip, from: 0, to: 0.2) { _ in true }
    feed(&dip, from: 0.2, to: 0.3) { _ in false }
    feed(&dip, from: 0.3, to: 0.5) { _ in true }
    check(dip.state == .waiting && dip.callOverAt == nil, "call: a 100 ms dip between syllables of the name isn't its end")
}

// MARK: - 3. Voice onset opens

private func quietWakeOnsetTests() {
    // "아리스" … a breath … "내일 아침 일곱 시에 깨워줘".
    var q = Q(wokeAt: 0)
    feed(&q, from: 0, to: 0.35) { _ in true }
    feed(&q, from: 0.35, to: 0.9) { _ in false }
    check(q.state == .waiting, "onset: quiet after the call still waits")
    var openedAt: Double?
    var t = 0.9
    while t < 1.5, openedAt == nil {
        if q.level(voice: true, at: t) == .heard { openedAt = t }
        t += reading
    }
    check(openedAt.map { $0 - 0.9 <= 0.1 } ?? false, "onset: the user talking after the call opens within ~0.1 s of his voice (\(openedAt.map { String(format: "%.3f", $0) } ?? "never"))")

    // A key clack or a click: one reading over the gate.
    var clack = Q(wokeAt: 0)
    feed(&clack, from: 0, to: 0.3) { _ in true }
    feed(&clack, from: 0.3, to: 1.2) { _ in false }
    clack.level(voice: true, at: 1.2)
    feed(&clack, from: 1.243, to: 2.0) { _ in false }
    check(clack.state == .waiting, "onset: a single loud reading (a click) after the call doesn't open")
    feed(&clack, from: 2.0, to: 2.7) { _ in false }
    check(clack.state == .unheard, "onset: … and the lap still ends quietly")

    // The call run straight into the request with no gap: past the first second, the voice is the user's request.
    var run = Q(wokeAt: 0)
    feed(&run, from: 0, to: 1.2) { _ in true }
    check(run.state == .heard, "onset: '아리스내일…' with no pause opens once the call can't still be going (1 s)")

    // Words beyond the call from the recognizer open even if the level never said so (a quiet voice).
    var words = Q(wokeAt: 0)
    feed(&words, from: 0, to: 1.0) { _ in false }
    check(words.words(at: 1.4) == .heard, "onset: words after the call open the notch whatever the level said")

    // Once heard, the turn is an ordinary listening turn: silence afterwards changes nothing here.
    feed(&q, from: 1.5, to: 4) { _ in false }
    check(q.state == .heard, "onset: once heard, the lap's end no longer ends the turn (the turn's own end rules apply)")
}

// MARK: - 4. The lap's end

private func quietWakeLapEndTests() {
    // The user starts at the very end of the lap: their run is still going at 2.6 s, so it's heard, not dropped.
    var late = Q(wokeAt: 0)
    feed(&late, from: 0, to: 0.3) { _ in true }
    feed(&late, from: 0.3, to: 2.58) { _ in false }
    late.level(voice: true, at: 2.58)
    check(late.tick(at: 2.6) == .heard, "lap end: a voice begun just before the lap's end is heard, never cut off")
    // The call's own tail never makes the lap's end 'heard'.
    var tail = Q(wokeAt: 0)
    tail.level(voice: true, at: 0.1)
    check(tail.tick(at: 2.6) == .unheard, "lap end: only the call was voiced: unheard")
}

// MARK: - 5. The rim's one lap

private func quietWakeRimTests() {
    let total = 400.0
    for t in stride(from: 0.0, to: ArisRimSweep.period, by: 0.05) {
        let looping = ArisRimSweep.head(at: t, total: total)
        guard let once = ArisRimSweep.head(at: t, total: total, once: true), abs(once - looping) < 1e-9 else {
            return check(false, "rim: the one lap follows the looping light exactly (t \(t))")
        }
    }
    check(true, "rim: the one lap follows the looping light exactly until its end, so a heard call carries on unbroken")
    check(ArisRimSweep.head(at: ArisRimSweep.period, total: total, once: true) == nil
          && ArisRimSweep.head(at: 5, total: total, once: true) == nil,
          "rim: after one lap the light is gone (no second pass begins)")
    check(ArisRimSweep.head(at: ArisRimSweep.period, total: total, once: false) == -ArisRimSweep.lead,
          "rim: not once, a second pass starts as before")
    // At the lap's end the light has left the outline: its tail at the far tip is down to 0.5 %.
    let last = ArisRimSweep.head(at: ArisRimSweep.period - 1e-6, total: total, once: true) ?? 0
    check(exp(-(last - total) / ArisRimSweep.tail) < 0.006, "rim: when the lap ends its light has already left the band")
}

// MARK: - 6. The notch

private func quietWakeNotchTests() {
    typealias N = ArisNotchDecisions
    check(!N.turnNeedsPanel(training: false, dictating: false, phase: .listening),
          "notch: a key press's listening keeps the closed band as today")
    check(!N.turnNeedsPanel(training: false, dictating: false, phase: .listening, wakeHeard: false),
          "notch: the wake word's lap keeps the closed band (270 × 32): nothing opens")
    check(N.turnNeedsPanel(training: false, dictating: false, phase: .listening, wakeHeard: true),
          "notch: the user's voice in the lap opens the notch while it still listens")
    check(!N.turnNeedsPanel(training: false, dictating: true, phase: .listening, wakeHeard: true),
          "notch: never for a dictation")
    check(N.turnNeedsPanel(training: false, dictating: false, phase: .thinking) && N.turnNeedsPanel(training: false, dictating: false, phase: .failed),
          "notch: thinking and a failure (못 들었어요 after a key press) open as before")

    let lap = ArisNotchSnapshot(session: ArisSession(phase: .listening), isTraining: false, isDictating: false, hasUnfinishedTask: false,
                                taskJustFinished: false, wakeLap: .waiting)
    check(lap.wakeLapRunning && !lap.wakeHeard, "snapshot: the lap is running while a wake turn listens")
    let heard = ArisNotchSnapshot(session: ArisSession(phase: .listening), isTraining: false, isDictating: false, hasUnfinishedTask: false,
                                  taskJustFinished: false, wakeLap: .heard)
    check(!heard.wakeLapRunning && heard.wakeHeard, "snapshot: heard, the rim loops on and the notch opens")
    let idle = ArisNotchSnapshot(session: ArisSession(), isTraining: false, isDictating: false, hasUnfinishedTask: false,
                                 taskJustFinished: false, wakeLap: .waiting)
    check(!idle.wakeLapRunning && !idle.wakeHeard, "snapshot: nothing of the lap shows once the turn is over")
    let key = ArisNotchSnapshot(session: ArisSession(phase: .listening), isTraining: false, isDictating: false, hasUnfinishedTask: false,
                                taskJustFinished: false)
    check(!key.wakeLapRunning && !key.wakeHeard, "snapshot: a key press's turn has no lap")
}

// MARK: - 7. The quiet end is false-wake's

private func quietWakeQuietEndTests() {
    check(ArisWakeDoubt.QuietEnd.quietLap.path == "quiet-lap" && ArisWakeDoubt.QuietEnd.quietLap.logLine.contains("one lap"),
          "quiet end: a lap with no voice is written to the wake log as quiet-lap")
    check(ArisWakeDoubt.unheardLine(byWakeWord: true, korean: true) == nil && ArisWakeDoubt.unheardLine(byWakeWord: false, korean: true) == "못 들었어요",
          "quiet end: no line for the wake word; a key press still says 못 들었어요")
}

// MARK: - 8. Wiring

private func quietWakeWiringTests() {
    let wake = quietSource("Aris/private/Aris/ArisController+Wake.swift")
    let controller = quietSource("Aris/private/Aris/ArisController.swift")
    let quiet = quietSource("Aris/private/Aris/ArisController+QuietWake.swift")
    let root = quietSource("Aris/private/Notch/ArisNotchRoot.swift")
    let behaviour = quietSource("Aris/private/Notch/ArisNotchRoot+Behaviour.swift")
    let activity = quietSource("Aris/private/Aris/ArisActivity.swift")
    let band = quietSource("Aris/private/Aris/Design/ArisBand.swift")
    check(wake.contains("startQuietLap(saidMore: saidMore, evidence: evidence)"), "wiring: a wake starts the lap (held for a borderline one)")
    check(controller.contains("quietLapLevel(voice:") && controller.contains("quietLapWords()"),
          "wiring: the turn's level and words feed the lap")
    check(controller.contains("endQuietLap()") && quietSource("Aris/private/Aris/ArisController+Conversation.swift").contains("endQuietLap()")
          && quietSource("Aris/private/Aris/ArisController+FalseWake.swift").contains("endQuietLap()"),
          "wiring: a key press's turn, a conversation's voice turn and a quiet close leave no lap behind")
    check(quiet.contains("closeWakeTurnQuietly(.quietLap)") && !quiet.contains("notHeard()"),
          "wiring: a lap with no voice ends through false-wake's quiet close, never 못 들었어요")
    check(root.contains("once: aris.wakeLapRunning"), "wiring: the rim makes one lap while the lap runs")
    check(behaviour.contains("wakeHeard: aris.wakeHeard") && behaviour.contains("onChange(of: root.aris.wakeHeard)"),
          "wiring: the user's voice in the lap opens the notch on the open curve")
    check(activity.contains("!quietLap"), "wiring: the hands-free lock waits for the lap (the band shows only the bars and the light)")
    check(band.contains("static func draw(in") && band.contains("once: once"), "wiring: the rim draws once through one function the renders share")
}
