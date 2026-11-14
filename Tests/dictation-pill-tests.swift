// Tests for dictation-pill: dictation shows in its own pill at the bottom of the screen being typed on, sized as
// measured (ArisDictationPillRules), with the measured level bars and ring (ArisDictationPillMotion); the top notch stays
// quiet for a dictation the pill has (ArisNotchSnapshot's dictationQuiet), never for talking to Aris; the pill's panel
// never takes the keyboard or focus (source checks: it can't compile here without the app's packages); the pill's click
// start is hands-free; the Settings switch. Called from main.swift; uses its check().
import CoreGraphics
import Foundation

private let pillRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private func pillSource(_ path: String) -> String { (try? String(contentsOf: pillRoot.appendingPathComponent(path), encoding: .utf8)) ?? "" }

func runDictationPillTests() {
    pillPhaseTests()
    pillSizeTests()
    pillErrorWidthTests()
    pillPlacementTests()
    pillMotionTests()
    pillNotchQuietTests()
    pillPanelFlagTests()
    pillWiringTests()
}

// MARK: - State → what it shows

private func pillPhaseTests() {
    typealias R = ArisDictationPillRules
    var i = R.Inputs()
    check(R.phase(i) == .idle, "pill: dictation ready, nothing happening → the idle sliver")
    i.hovered = true
    check(R.phase(i) == .hover, "pill: the pointer on the sliver → hover")
    i.hovered = false
    i.enabled = false
    check(R.phase(i) == .hidden, "pill: the switch off → hidden")
    i.enabled = true
    i.screenLocked = true
    check(R.phase(i) == .hidden, "pill: the screen locked → hidden")
    i.screenLocked = false
    i.fullScreen = true
    check(R.phase(i) == .hidden, "pill: a full-screen app → no idle sliver")
    i.stage = .listening
    check(R.phase(i) == .recording(handsFree: false), "pill: a dictation in a full-screen app still shows")
    i.fullScreen = false
    check(R.phase(i) == .recording(handsFree: false), "pill: holding the key → the held recording")
    i.handsFree = true
    check(R.phase(i) == .recording(handsFree: true), "pill: hands-free (double tap or a click on the pill) → the hands-free row")
    i.stage = .writing
    check(R.phase(i) == .transcribing(.charging), "pill: let go, Whisper writing → the ring charging")
    i.stage = .cleaning
    check(R.phase(i) == .transcribing(.releasing), "pill: the words in hand, going in → the ring sweeping on")
    i.stage = .typed
    i.typedHold = true
    check(R.phase(i) == .transcribing(.done), "pill: typed → the ring full for its hold")
    i.typedHold = false
    check(R.phase(i) == .idle, "pill: after the hold → back to the sliver")
    i.recovered = "복사된 말"
    check(R.phase(i) == .recovered("복사된 말"), "pill: nowhere to type → the copied words")
    i.recovered = nil
    i.error = "입력하지 못했어요"
    check(R.phase(i) == .error("입력하지 못했어요"), "pill: a failure → the line in place")
    i.stage = .listening
    check(R.phase(i) == .error("입력하지 못했어요"), "pill: an error comes before the recording rows (measured cascade)")
    i.recovered = "x"
    check(R.phase(i) == .recovered("x"), "pill: the recovered words come before an error (measured cascade)")
    i.error = ""
    i.recovered = ""
    check(R.phase(i) == .recording(handsFree: true), "pill: empty lines don't count")
}

private func pillSizeTests() {
    typealias R = ArisDictationPillRules
    let sizes: [(ArisDictationPillPhase, CGSize, String)] = [
        (.idle, CGSize(width: 36, height: 8), "idle 36 × 8"),
        (.hidden, CGSize(width: 36, height: 8), "hidden leaves at the sliver's size"),
        (.hover, CGSize(width: 50, height: 30), "hover 50 × 30"),
        (.recording(handsFree: false), CGSize(width: 80, height: 30), "hold recording 80 × 30"),
        (.recording(handsFree: true), CGSize(width: 102, height: 30), "hands-free / pill-click recording 102 × 30"),
        (.transcribing(.charging), CGSize(width: 30, height: 30), "transcribing 30 × 30"),
        (.transcribing(.releasing), CGSize(width: 30, height: 30), "awaiting insertion 30 × 30"),
        (.transcribing(.done), CGSize(width: 30, height: 30), "typed hold 30 × 30"),
    ]
    for (phase, size, name) in sizes { check(R.size(phase) == size, "pill size: \(name)") }
    check(R.size(.recovered(String(repeating: "a", count: 41))) == CGSize(width: 282, height: 92), "pill size: recovered under 42 → 282 × 92")
    check(R.size(.recovered(String(repeating: "a", count: 42))) == CGSize(width: 326, height: 110), "pill size: recovered 42 → 326 × 110")
    check(R.size(.recovered(String(repeating: "a", count: 89))) == CGSize(width: 326, height: 110), "pill size: recovered 89 → 326 × 110")
    check(R.size(.recovered(String(repeating: "a", count: 90))) == CGSize(width: 364, height: 130), "pill size: recovered 90 → 364 × 130")
    check(R.size(.recovered(String(repeating: "😀", count: 21))) == CGSize(width: 326, height: 110), "pill size: recovered counts UTF-16 as measured (21 emoji = 42)")
    check(R.radius == 24 && R.showDuration == 0.15 && R.hiddenScale == 0.8 && R.sizeDuration == 0.15, "pill: radius 24, show/hide 0.15 s from 0.8, sizes 0.15 s")
    check(R.windowSize == CGSize(width: 540, height: 700) && R.parkAfter == .seconds(12), "pill: window at most 540 × 700, parked after 12 s")
    check(R.gradientBorder(.idle) && R.gradientBorder(.recording(handsFree: false)) && !R.gradientBorder(.error("x")),
          "pill: the gradient ring except with an error (solid .18)")
}

// MARK: - The inline error's width

private func pillErrorWidthTests() {
    typealias R = ArisDictationPillRules
    check(R.errorTextWidth("ab") == 14.8, "pill error: 7.4 a Latin character")
    check(R.errorTextWidth("a b") == 18.8, "pill error: 4 a space")
    check(R.errorTextWidth("입력") == 28, "pill error: 14 a CJK character")
    check(R.errorTextWidth("\u{2E80}\u{2E7F}") == 14 + 7.4, "pill error: CJK from U+2E80 (U+2E7F is not)")
    check(R.errorWidth("") == 136, "pill error: never under 136")
    // 14 Latin (103.6) + 2 spaces (8) + 44 = 155.6 → 156.
    check(R.errorWidth("Couldn't type it") == 156, "pill error: ceil(clamp(136, textW + 44, 280)): Couldn't type it → 156")
    // 8 CJK (112) + 1 space (4) + 44 = 160.
    check(R.errorWidth("입력하지 못했어요") == 160, "pill error: 입력하지 못했어요 → 160")
    check(R.errorWidth(String(repeating: "가", count: 40)) == 280, "pill error: never over 280")
    check(R.size(.error("입력하지 못했어요")).height == 38, "pill error: 38 tall")
}

// MARK: - Where it sits

private func pillPlacementTests() {
    typealias R = ArisDictationPillRules
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let dockBottom = CGRect(x: 0, y: 70, width: 1512, height: 879)
    check(R.usableBottom(frame: screen, visible: dockBottom) == 70, "pill place: a Dock showing at the bottom → its top")
    check(R.pillBottom(frame: screen, visible: dockBottom) == 71, "pill place: the pill 1 above the Dock (window 5 under, pill 6 up)")
    let hidden = CGRect(x: 0, y: 4, width: 1512, height: 945)
    check(R.usableBottom(frame: screen, visible: hidden) == 0 && R.pillBottom(frame: screen, visible: hidden) == 1,
          "pill place: a hidden Dock (4 reserved) → the screen's bottom, the pill 1 above it")
    let side = CGRect(x: 80, y: 0, width: 1432, height: 949)
    check(R.usableBottom(frame: screen, visible: side) == 0, "pill place: a Dock at the side → the screen's bottom")
    let window = R.windowFrame(frame: screen, visible: dockBottom)
    check(window == CGRect(x: 486, y: 65, width: 540, height: 700), "pill place: the window centred on the visible frame, bottom 5 under the Dock's top")
    check(R.windowFrame(frame: screen, visible: side).midX == side.midX, "pill place: centred on the visible frame (a side Dock moves it)")
    let second = CGRect(x: 1512, y: -200, width: 1920, height: 1080)
    check(R.windowFrame(frame: second, visible: CGRect(x: 1512, y: -200, width: 1920, height: 1055)).minX == 1512 + 690,
          "pill place: on a second screen, its own centre")
    check(R.pillRect(CGSize(width: 80, height: 30)) == CGRect(x: 230, y: 6, width: 80, height: 30), "pill place: the pill's rect centred 6 up in its window")
    check(R.isFullScreen(window: CGRect(x: 0, y: 0, width: 1512, height: 982), screen: screen), "pill: a window covering the screen is full screen")
    check(!R.isFullScreen(window: CGRect(x: 0, y: 0, width: 1512, height: 949), screen: screen), "pill: a zoomed window (menu bar showing) is not")
    check(!R.isFullScreen(window: nil, screen: screen), "pill: no window, not full screen")
    check(R.screenIndex(for: CGRect(x: 1700, y: 100, width: 400, height: 300), screens: [screen, second]) == 1, "pill: the front window's centre picks the screen")
    check(R.screenIndex(for: CGRect(x: 1400, y: 100, width: 400, height: 300), screens: [screen, second]) == 1, "pill: across two screens, its centre's")
    check(R.screenIndex(for: CGRect(x: 5000, y: 5000, width: 10, height: 10), screens: [screen, second]) == nil, "pill: off every screen → none")
    check(R.appKitRect(cg: CGRect(x: 10, y: 20, width: 100, height: 50), primaryHeight: 982) == CGRect(x: 10, y: 912, width: 100, height: 50),
          "pill: a CG window rect in AppKit's coordinates")
}

// MARK: - The marks

private func pillMotionTests() {
    typealias Ring = ArisDictationPillRing
    check(Ring.size == 16 && Ring.stroke == 2.5 && Ring.completeHold == .milliseconds(100), "pill ring: 16 across, stroke 2.5, holds 100 ms")
    check(Ring.profile(recordingSeconds: 5).target == 1.6 && Ring.profile(recordingSeconds: 45).target == 2.25
          && abs(Ring.profile(recordingSeconds: 135).target - 3.7) < 1e-9 && Ring.profile(recordingSeconds: 900).target == 12,
          "pill ring: the charge's length follows the measured anchors (5 s → 1.6, 45 → 2.25, 135 → 3.7, past 600 → 12)")
    let p = Ring.profile(recordingSeconds: 3)
    check(abs(Ring.charge(at: Ring.joinSeconds, profile: p) - Ring.joinProgress) < 1e-12, "pill ring: the opening joins at 0.4 s")
    check(abs(Ring.charge(at: Ring.joinSeconds + Ring.settleSeconds, profile: p) - (Ring.cruiseEnd - p.cruiseVelocity * (p.target - 0.65))) < 1e-6,
          "pill ring: the settle meets the cruise")
    check(abs(Ring.charge(at: p.target, profile: p) - Ring.cruiseEnd) < 1e-9, "pill ring: 0.88 at the target time")
    check(Ring.charge(at: 600, profile: p) < Ring.asymptote && Ring.charge(at: 600, profile: p) > 0.97, "pill ring: never past 0.975 while charging")
    var last = 0.0, rising = true
    for step in 0...400 { let v = Ring.charge(at: Double(step) * 0.02, profile: p); if v < last - 1e-12 { rising = false }; last = v }
    check(rising, "pill ring: the charge only rises")
    let motion = ArisDictationPillRingMotion(recordingSeconds: 3)
    var t = 0.0
    for _ in 0..<60 { motion.step(at: t, stage: .charging); t += 1.0 / 60 }
    let charged = motion.progress
    var frames = 0
    while !motion.swept, frames < 600 { motion.step(at: t, stage: .releasing); t += 1.0 / 60; frames += 1 }
    check(charged > 0.5 && motion.swept && motion.progress == 1 && frames < 60, "pill ring: the release sweeps to full within a second (\(frames) frames)")
    let done = ArisDictationPillRingMotion(recordingSeconds: 3)
    check(done.step(at: 0, stage: .done) == 1, "pill ring: typed → full at once")
    check(Ring.cappedArc(0.5, circumference: 10, stroke: 2.5) == 0.25 && Ring.cappedArc(1, circumference: 10, stroke: 2.5) == 1,
          "pill ring: the round caps are taken off the arc, except when full")

    let bars = ArisDictationPillBars()
    check(ArisDictationPillBars.count == 7 && ArisDictationPillBars.width == 38.5 && ArisDictationPillBars.slotHeight == 18,
          "pill bars: 7 bars of 2.5 with 1.5 either side (38.5) in an 18 slot")
    bars.step(at: 1, level: 0, jitter: { 1 })
    check(bars.heights.allSatisfy { $0 == 2 }, "pill bars: silence → all at 2")
    for k in 0..<20 { bars.step(at: 1 + Double(k + 1) * 0.06, level: 8, jitter: { 1 }) }
    check(bars.heights.last == 17 && bars.heights.allSatisfy { $0 <= 17 }, "pill bars: loud → 17 at most, the newest on the right")
    check(ArisDictationPillBars.grey(2) == 110.0 / 255 && ArisDictationPillBars.grey(17) == 1, "pill bars: grey 110 at rest, white at full")
    // 80 = 6 + icon 20 + 4.5 + bars 38.5 + 10.5 (the measured hold row adds up to its pill).
    check(6 + 20 + 4.5 + ArisDictationPillBars.width + 10.5 == ArisDictationPillRules.holdSize.width - 0.5,
          "pill bars: the hold row's parts fill its 80 (79.5 + the border's half)")
}

// MARK: - The notch stays quiet

private func pillNotchQuietTests() {
    typealias R = ArisDictationPillRules
    check(R.notchQuiet(pillOn: true, dictating: true, endedDictation: false, idle: false), "notch quiet: dictating with the pill on")
    check(R.notchQuiet(pillOn: true, dictating: false, endedDictation: true, idle: true), "notch quiet: after a dictation, until the next turn")
    check(!R.notchQuiet(pillOn: true, dictating: false, endedDictation: true, idle: false), "notch quiet: a new turn (talking to Aris) shows again")
    check(!R.notchQuiet(pillOn: true, dictating: false, endedDictation: false, idle: false), "notch quiet: talking to Aris is never quiet")
    check(!R.notchQuiet(pillOn: false, dictating: true, endedDictation: false, idle: false), "notch quiet: the pill off → the notch shows dictation as before")

    let listening = ArisSession().listening()
    let quiet = ArisNotchSnapshot(session: listening, isTraining: false, isDictating: true, hasUnfinishedTask: false, taskJustFinished: false,
                                  dictationCopied: true, dictationQuiet: true)
    check(quiet.phase == .idle && !quiet.isActive && !quiet.isDictating && !quiet.dictationCopied && !quiet.holdsNotch,
          "notch quiet: the snapshot sees no turn while the pill has the dictation (no band, no panel, no hold)")
    let parked = ArisNotchSnapshot(session: ArisSession().listening().hearing("말").thinking().answering("말").done(), isTraining: false,
                                   isDictating: false, hasUnfinishedTask: false, taskJustFinished: false, dictationQuiet: true)
    check(!parked.hasReply, "notch quiet: the typed words aren't parked in the notch")
    let loud = ArisNotchSnapshot(session: listening, isTraining: false, isDictating: true, hasUnfinishedTask: false, taskJustFinished: false)
    check(loud.phase == .listening && loud.isActive && loud.isDictating, "notch quiet: without the pill the snapshot is as before")
    let agent = ArisNotchSnapshot(session: listening, isTraining: false, isDictating: false, hasUnfinishedTask: false, taskJustFinished: false,
                                  dictationQuiet: R.notchQuiet(pillOn: true, dictating: false, endedDictation: true, idle: false))
    check(agent.phase == .listening && agent.isActive, "notch quiet: agent listening keeps the notch's listening state")
    let training = ArisNotchSnapshot(session: listening, isTraining: true, isDictating: true, hasUnfinishedTask: false, taskJustFinished: false,
                                     dictationQuiet: true)
    check(training.isActive, "notch quiet: wake-word training still shows")
}

// MARK: - The panel never takes focus

private func pillPanelFlagTests() {
    let panel = pillSource("Aris/private/Aris/Dictation/ArisDictationPillPanel.swift")
    check(panel.contains("override var canBecomeKey: Bool { false }") && panel.contains("override var canBecomeMain: Bool { false }"),
          "pill panel: never key, never main")
    check(panel.contains("[.borderless, .nonactivatingPanel]"), "pill panel: borderless and non-activating (a click never activates Aris)")
    check(panel.contains("ignoresMouseEvents = true"), "pill panel: click-through by default")
    check(panel.contains("override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }"), "pill panel: the pill takes the first click")
    check(panel.contains(".canJoinAllSpaces") && panel.contains(".fullScreenAuxiliary") && panel.contains("hidesOnDeactivate = false"),
          "pill panel: on every space, over full-screen apps, never hidden on deactivate")
    check(panel.contains("becomesKeyOnlyIfNeeded = true") && panel.contains("isFloatingPanel = true"), "pill panel: a floating panel")
    let center = pillSource("Aris/private/Aris/Dictation/ArisDictationPillCenter.swift")
    for call in ["makeKey", "makeKeyAndOrderFront", "makeMain", "NSApp.activate", "activate(ignoringOtherApps", ".activate("] {
        check(!center.contains(call), "pill center: never calls \(call) (the app being typed into keeps focus)")
    }
    check(center.contains("orderFrontRegardless()"), "pill center: shows the panel without activating")
    check(center.contains("panel.ignoresMouseEvents == on") && center.contains("rect.contains(NSEvent.mouseLocation)"),
          "pill center: takes the pointer only on the pill")
}

// MARK: - Wiring

private func pillWiringTests() {
    var state = ArisDictationKey.State()
    let now = ContinuousClock.now
    state.lockFromPill(at: now)
    check(state.isLocked, "pill click: the key's state is hands-free")
    var finish = state
    check(finish.handle(.down(alone: true), at: now + .milliseconds(10)) == .finish, "pill click: the key's next press puts it in (not a triple-tap cancel)")
    check(state.handle(.escape, at: now) == .cancel, "pill click: Esc cancels")

    let controller = pillSource("Aris/private/Aris/ArisController+Dictation.swift")
    check(controller.contains("func startDictationFromPill()") && controller.contains("lockDictation()") && controller.contains("ArisDictationKeyTap.shared.lockFromPill()"),
          "pill click: starts a hands-free dictation")
    check(controller.contains("ArisDictationState.shared.showPillError(line)") && controller.contains("guard ArisDictationPillGate.on else"),
          "pill: a dictation's failure is said in the pill when it is on, in the notch otherwise")
    let notchState = pillSource("Aris/private/Aris/ArisNotchState.swift")
    check(notchState.contains("dictationQuiet: ArisDictationPillRules.notchQuiet(pillOn: ArisDictationPillGate.on"),
          "notch quiet: the notch's snapshot asks the pill's rule")
    check(notchState.contains("Defaults.publisher(.arisDictationPill"), "notch quiet: the switch is watched")
    let entry = pillSource("Aris/private/App/ArisEntry.swift")
    check(entry.contains("ArisDictationPillCenter.shared.start()"), "pill: started with the app")
    let view = pillSource("Aris/private/Aris/Dictation/ArisDictationPillView.swift")
    check(view.contains("accessibilityReduceMotion") && view.contains("reduceMotion ? nil : ease") && view.contains("shown || reduceMotion ? 1 : ArisDictationPillRules.hiddenScale"),
          "pill: Reduce Motion fades only (no scale, sizes at once)")

    let builder = pillSource("Aris/components/Settings/ArisSettingsBuilder.swift")
    check(builder.contains("id: \"dictation.pill\"") && builder.contains("받아쓰기 알약 보이기") && builder.contains(".toggle(.dictationPill, s.dictationPill)"),
          "settings: 받아쓰기 › 받아쓰기 알약 보이기 switch")
    check(ArisSettingsSnapshot().dictationPill, "settings: the pill is on by default")
    let strings = pillSource("Aris/components/Settings/Settings.xcstrings")
    check(strings.contains("\"받아쓰기 알약 보이기\"") && strings.contains("Show the dictation pill"), "settings: the switch in English")
    let center = pillSource("Aris/private/Aris/Dictation/ArisDictationPillCenter.swift")
    check(center.contains("Key<Bool>(\"arisDictationPill\", default: true)"), "settings: arisDictationPill defaults on")

    // The measured app's name is never written in the pill's files.
    let files = ["ArisDictationPillRules", "ArisDictationPillMotion", "ArisDictationPillPanel", "ArisDictationPillCenter", "ArisDictationPillView", "ArisDictationPillParts"]
    for file in files {
        let text = pillSource("Aris/private/Aris/Dictation/\(file).swift").lowercased()
        check(!text.isEmpty && !text.contains("voice" + "os"), "pill: \(file) says 'measured', never the reference app's name")
    }
}
