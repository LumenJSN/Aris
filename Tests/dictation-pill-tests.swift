// Tests for dictation-pill (re-measured from the reference pill, 2026-11-17): dictation shows in its own pill at
// the bottom of the screen being typed on, sized as measured (ArisDictationPillRules), with the measured level bars and
// spinner (ArisDictationPillMotion, its own tests in dictation-pill-motion-tests.swift); the top notch stays
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
    check(R.phase(i) == .transcribing(.charging), "pill: let go, Whisper writing → the spinner")
    i.stage = .cleaning
    check(R.phase(i) == .transcribing(.releasing), "pill: the words in hand, going in → still the spinner")
    i.stage = .typed
    i.typedHold = true
    check(R.phase(i) == .transcribing(.done), "pill: typed with a hold asked (renders only) → the spinner")
    i.typedHold = false
    check(R.phase(i) == .idle, "pill: typed → straight back to the sliver (the reference has no done state)")
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
        (.idle, CGSize(width: 40, height: 8), "idle 40 × 8"),
        (.hidden, CGSize(width: 40, height: 8), "hidden leaves at the sliver's size"),
        (.hover, CGSize(width: 50, height: 30), "hover 50 × 30"),
        (.recording(handsFree: false), CGSize(width: 73, height: 30), "held recording 73 × 30"),
        (.recording(handsFree: true), CGSize(width: 102.5, height: 30), "hands-free / pill-click recording 102.5 × 30"),
        (.transcribing(.charging), CGSize(width: 98, height: 30), "writing 98 × 30"),
        (.transcribing(.releasing), CGSize(width: 98, height: 30), "going in 98 × 30"),
        (.transcribing(.done), CGSize(width: 98, height: 30), "typed 98 × 30"),
    ]
    for (phase, size, name) in sizes { check(R.size(phase) == size, "pill size: \(name)") }
    recoveredCardTests()
    check(R.radius == 22.5 && R.idleRadius == 6 && R.lineWidth == 1 && R.errorLineWidth == 1.5,
          "pill: radius 22.5 (6 on the sliver), a 1 px line (1.5 with an error)")
    check(R.cornerRadius(R.idleSize) == 4 && R.cornerRadius(R.hoverSize) == 15 && R.cornerRadius(R.handsFreeSize) == 15,
          "pill: the sliver's 6 fits its 8 as 4 (CSS shrinks radii that overlap), everything 30 high a capsule")
    check(abs(R.cornerRadius(CGSize(width: 45, height: 19)) - 9.5) < 1e-9, "pill: half-way up the corners are half-way and clamped to half the height")
    check(R.windowSize == CGSize(width: 540, height: 700) && R.parkAfter == .seconds(12), "pill: window at most 540 × 700, parked after 12 s")
    check(R.look(.idle) == .sliver && R.look(.hidden) == .sliver && R.look(.hover) == .hovered && R.look(.recording(handsFree: false)) == .solid
          && R.look(.transcribing(.charging)) == .solid && R.look(.error("x")) == .failed, "pill: the sliver, the hover, solid, and an error's red line")
    check(R.hintDelay == 0.15 && R.buttonHintDelay == 0.05 && R.hintFade == 0.12 && R.hintGap == 4 && R.buttonHintGap == 10,
          "pill: tooltips after 150 ms (50 over a button), a 120 ms fade, 4 above the pill, 10 above a button")
}

// MARK: - The inline error's width

private func pillErrorWidthTests() {
    typealias R = ArisDictationPillRules
    check(R.errorTextWidth("ab") == 14.8, "pill error: 7.4 a Latin character")
    check(R.errorTextWidth("a b") == 18.8, "pill error: 4 a space")
    check(R.errorTextWidth("입력") == 28, "pill error: 14 a CJK character")
    check(R.errorTextWidth("\u{2E80}\u{2E7F}") == 14 + 7.4, "pill error: CJK from U+2E80 (U+2E7F is not)")
    check(R.errorWidth("") == 91, "pill error: never under the reference's 91")
    // 14 Latin (103.6) + 2 spaces (8) + 24 = 135.6 → 136.
    check(R.errorWidth("Couldn't type it") == 136, "pill error: ceil(clamp(91, textW + 24, 280)): Couldn't type it → 136")
    // 8 CJK (112) + 1 space (4) + 24 = 140.
    check(R.errorWidth("입력하지 못했어요") == 140, "pill error: 입력하지 못했어요 → 140")
    check(R.errorWidth(String(repeating: "가", count: 40)) == 280, "pill error: never over 280")
    check(R.size(.error("입력하지 못했어요")).height == 30, "pill error: 30 tall")
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
    check(window == CGRect(x: 486, y: 65, width: 540, height: 700), "pill place: the window centred on the visible frame, its bottom 5 under the Dock's top")
    check(R.windowFrame(frame: screen, visible: side).midX == side.midX, "pill place: centred on the visible frame (a side Dock moves it)")
    let second = CGRect(x: 1512, y: -200, width: 1920, height: 1080)
    check(R.windowFrame(frame: second, visible: CGRect(x: 1512, y: -200, width: 1920, height: 1055)).minX == 1512 + 690,
          "pill place: on a second screen, its own centre")
    check(R.pillRect(CGSize(width: 73, height: 30)) == CGRect(x: 233.5, y: 6, width: 73, height: 30), "pill place: the pill's rect centred 6 up in its window")
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
    typealias W = ArisDictationPillWave
    // The rows add up to their pills (the reference's flex rows, inside the 1 px line).
    let handsFree = 18 + 4 + W.width + 4 + 18
    check(handsFree == 90 && handsFree + 2 * 1 + 2 * 5.25 == ArisDictationPillRules.handsFreeSize.width,
          "pill rows: ✕ 18 · 4 · bars 46 · 4 · ■ 18 = 90, 5.25 in at each end of 102.5")
    check(W.width + 2 * 1 <= ArisDictationPillRules.holdSize.width, "pill rows: the 46 bars fit the 73 hold")
    let writing = W.width + 6 + ArisDictationPillSpinner.size
    check(writing + 2 * 12 <= ArisDictationPillRules.transcribingSize.width, "pill rows: bars · 6 · spinner inside 12 at each end of 98")
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
    check(view.contains("accessibilityReduceMotion") && view.contains("reduceMotion ? nil : sizeAnimation") && view.contains(".opacity(shown ? 1 : 0)"),
          "pill: Reduce Motion fades only (sizes at once; show / hide is opacity for everyone)")

    let builder = pillSource("Aris/components/Settings/ArisSettingsBuilder.swift")
    check(builder.contains("id: \"dictation.pill\"") && builder.contains("받아쓰기 알약 보이기") && builder.contains(".toggle(.dictationPill, s.dictationPill"),
          "settings: 받아쓰기 › 받아쓰기 알약 보이기 switch")
    check(ArisSettingsSnapshot().dictationPill, "settings: the pill is on by default")
    let strings = pillSource("Aris/components/Settings/Settings.xcstrings")
    check(strings.contains("\"받아쓰기 알약 보이기\"") && strings.contains("Show the dictation pill"), "settings: the switch in English")
    let center = pillSource("Aris/private/Aris/Dictation/ArisDictationPillCenter.swift")
    check(center.contains("Key<Bool>(\"arisDictationPill\", default: true)"), "settings: arisDictationPill defaults on")

    // The reference apps' names are never written in the pill's files ("the reference pill" instead).
    let files = ["ArisDictationPillRules", "ArisDictationPillMotion", "ArisDictationPillPanel", "ArisDictationPillCenter", "ArisDictationPillView",
                 "ArisDictationPillParts", "ArisDictationPillRecoveredCard", "ArisDictationPillRecoveredLayout"]
    let word = try? NSRegularExpression(pattern: "\\b(" + "fl" + "ow|fl" + "ow" + "bar)\\b")
    for file in files {
        let text = pillSource("Aris/private/Aris/Dictation/\(file).swift").lowercased()
        let range = NSRange(text.startIndex..., in: text)
        check(!text.isEmpty && !text.contains("voice" + "os") && !text.contains("wis" + "pr") && word?.firstMatch(in: text, range: range) == nil,
              "pill: \(file) says 'the reference pill', never a reference app's name")
    }
}

// MARK: - The recovered words' card (pick B: fitted to its words)

private func recoveredCardTests() {
    typealias C = ArisDictationPillRecoveredLayout
    typealias R = ArisDictationPillRules
    let short = "인성이식 되는... 안녕."
    let medium = "내일 오후 세 시에 디자인 리뷰 있으니까 슬라이드 미리 보내 줘."
    let long = "오늘 회의 정리예요. 출시 날짜는 다음 달 둘째 주로 미뤄요. 온보딩은 권한 세 가지만 먼저 묻기로 했어요. 알림 카드는 노치 아래에 띄우고, 받아쓰기 알약은 화면 아래 가운데에 둬요."
    let veryLong = String(repeating: long + " ", count: 2)

    check(C.minContentWidth == 220 && C.maxContentWidth == 340 && C.radius == 18, "recovered card: content 220 to 340 wide, radius 18")
    check(C.paddingTop == 11 && C.paddingTrailing == 10 && C.paddingBottom == 13 && C.paddingLeading == 16 && C.gap == 6,
          "recovered card: padding 11 10 13 16, 6 between header and words")
    check(C.closeSize == 22 && C.checkSize == 12 && C.headerFontSize == 12 && C.keyMinWidth == 22 && C.keyHeight == 18
          && C.keyPadding == 4 && C.keyRadius == 5 && C.keyFontSize == 11, "recovered card: 22 ✕, 12 check, 12 / 500 header, ⌘V key ≥ 22 × 18, 0 4, r5, 11 / 600")
    check(C.bodyFontSize == 14 && abs(C.lineHeight - 20.3) < 0.001 && C.maxLines == 4 && C.fadeMax == 16 && C.bodyRadius == 8 && C.bodyOutset == 6,
          "recovered card: words 14 / 500 ×1.45, at most 4 lines (81), 16 fade, hover r8 6 past the words")
    check(C.growDuration == 0.3 && C.startSize == CGSize(width: 98, height: 30) && C.startRadius == 15 && C.contentFade == 0.16
          && C.contentDelay == 0.11 && C.leaveDuration == 0.16 && C.leaveScale == 0.96,
          "recovered card: grows from the 98 × 30 writing pill r15 in 300 ms, contents in 160 ms after 110 ms, leaves in 160 ms to .96")

    // Fitted to the words: no fixed boxes.
    for (name, text) in [("short", short), ("medium", medium), ("long", long), ("very long", veryLong), ("one word", "네"),
                         ("English", "Can you tidy up two drafts and send them over before the design review at three tomorrow?")] {
        for english in [false, true] {
            let fit = C.fit(text, english: english, again: false)
            let w = fit.size.width - C.paddingLeading - C.paddingTrailing
            check(w >= 220 && w <= 340, "recovered card: \(name) content width \(Int(w)) within 220…340 (\(english ? "en" : "ko"))")
            check(fit.size.width >= C.headerWidth(english: english, again: false) + 26 || w == 340,
                  "recovered card: \(name) as wide as its header (\(english ? "en" : "ko"))")
            // No copy button: the card is exactly header + 6 + the words' box, inside its padding.
            let words = CGFloat(min(fit.lines, 4)) * C.lineHeight + 4
            check(abs(fit.size.height - (11 + 22 + 6 + words + 13)) < 0.001, "recovered card: \(name) height is header + words, nothing else (\(english ? "en" : "ko"))")
            check(R.size(.recovered(text), english: english) == fit.size, "recovered card: the pill's size is the card's (\(name))")
        }
    }
    let one = C.fit(short, english: false, again: false)
    check(one.lines == 1 && abs(one.size.height - (56 + 20.3)) < 0.001, "recovered card: the owner's words → one line, 76.3 tall")
    check(one.size.width < 300, "recovered card: short words make a narrow card (\(Int(one.size.width)))")
    let longFit = C.fit(long, english: false, again: false)
    check(longFit.size.width == 366 && longFit.lines == 3 && !longFit.scrolls, "recovered card: long words → 340 wide, 3 lines, no scroll")
    let veryFit = C.fit(veryLong, english: false, again: false)
    check(veryFit.scrolls && abs(veryFit.bodyHeight - (4 * 20.3 + 4)) < 0.001 && abs(veryFit.size.height - (56 + 81.2)) < 0.001,
          "recovered card: past 4 lines it scrolls at 81 (the card stops growing)")
    check(C.fit("", english: false, again: false).size.height >= 76, "recovered card: never shorter than one line")

    // Hangul wraps at spaces (keep-all), never inside a word.
    let broken = C.lines(long, width: 340)
    check(broken.count == 3 && broken.dropLast().allSatisfy { $0.hasSuffix(" ") }, "recovered card: Korean lines break after a space")
    let words = Set(long.split(separator: " ").map(String.init))
    for line in broken {
        let pieces = line.split(separator: " ").map(String.init)
        check(pieces.allSatisfy(words.contains), "recovered card: no Korean word cut across lines (\(line.prefix(8))…)")
    }
    check(C.lines(String(repeating: "가", count: 60), width: 220).count > 1, "recovered card: a word longer than the line still wraps")

    // The label swap after a click (the card stays; nothing closes it).
    check(C.label(english: false, again: false) == "복사해 뒀어요" && C.label(english: false, again: true) == "다시 복사했어요",
          "recovered card: 복사해 뒀어요 → 다시 복사했어요 after a click")
    check(C.label(english: true, again: false) == "Copied" && C.label(english: true, again: true) == "Copied again"
          && C.tail(english: true) == "to paste" && C.tail(english: false) == "로 붙여 넣기" && C.key == "⌘V",
          "recovered card: English header Copied · ⌘V to paste / Copied again")
    check(C.againLinger == .milliseconds(1200), "recovered card: the swapped label holds 1.2 s")
    check(C.headerWidth(english: false, again: true) > C.headerWidth(english: false, again: false), "recovered card: the longer label widens the header")
    check(C.size(short, english: false, again: true).width >= C.size(short, english: false, again: false).width,
          "recovered card: the card refits to the longer label")

    // The bottom fade: only while there is more below, at most 16.
    check(C.fade(offset: 0, visible: 85, content: 60) == 0, "recovered card: words that fit don't fade")
    check(C.fade(offset: 0, visible: 85, content: 200) == 16, "recovered card: more below → 16")
    check(C.fade(offset: 105, visible: 85, content: 200) == 10, "recovered card: near the end the fade shrinks to what is left")
    check(C.fade(offset: 115, visible: 85, content: 200) == 0, "recovered card: at the end, no fade")

    // Where it stands and what takes the pointer: the card's own rect, centred where the pill stands.
    let rect = R.pillRect(longFit.size)
    check(rect.minY == R.bottomPadding && abs(rect.midX - R.windowSize.width / 2) < 0.001 && rect.size == longFit.size,
          "recovered card: centred, its bottom where the pill's is, the pointer area the card")
}
