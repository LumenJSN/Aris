// The user's first-run onboarding v4 (mockups/onboarding2, approved 2026-11-07): the intro's score (sunrise, star, name,
// CTA, the flight into the notch), the notch's morphs, the narration and caption clocks, the audio analysis that syncs
// captions and cues, the setup window's flow and model, the window rules (levels, Esc, the exits), the launch rules
// (resume once a day, never at login), every delayed beat stopping on close, and the language choice.
import AppKit
import Foundation

@MainActor
func runOnboardingTests() {
    onboardingScoreTests()
    onboardingFlightTests()
    onboardingNotchTests()
    onboardingNarrationTests()
    onboardingCaptionTests()
    onboardingAudioTests()
    onboardingFlowTests()
    onboardingModelTests()
    onboardingStageTests()
    onboardingDisplayTests()
    onboardingLaunchTests()
    onboardingClockTests()
    onboardingLanguageTests()
}

private func near(_ a: Double, _ b: Double, _ eps: Double = 1e-6) -> Bool { abs(a - b) <= eps }
private func near(_ a: CGFloat, _ b: CGFloat, _ eps: CGFloat = 1e-6) -> Bool { abs(a - b) <= eps }

// MARK: - The intro's score (intro.js)

@MainActor private func onboardingScoreTests() {
    typealias S = ArisOnboardingScore
    let screen = CGSize(width: 1512, height: 982), word = CGSize(width: 160, height: 76)
    let L = S.layout(screen: screen, word: word)
    let vis = 96 * 0.8, total = vis + 22 + 160, left = 756 - total / 2
    check(near(L.vis, vis) && near(L.lockX, left + vis / 2) && near(L.lockY, 491), "onboarding v4: the lockup's star sits left of the word, centred as one")
    check(near(L.wordX, left + vis + 22) && near(L.wordY, 491 - 12 - 38 + 3), "onboarding v4: the wordmark 22 right of the star")
    check(near(L.ctaX, 756 - 140) && near(L.ctaY, 491 + 104 - 12), "onboarding v4: 시작하기 at centre + 104, 280 wide")
    check(near(L.sunS, 982 / vis), "onboarding v4: the sun is the screen's height")

    let f0 = S.frame(at: 0, layout: L, reduced: false)
    check(f0.veil == 0 && f0.hero.opacity == 0 && f0.cta.opacity == 0 && f0.letters.allSatisfy { $0.opacity == 0 }, "onboarding v4: t=0 is black")
    check(S.frame(at: 1800, layout: L, reduced: false).veil == 1, "onboarding v4: the veil is in by 1.8 s (sineInOut)")
    let rising = S.frame(at: 1000, layout: L, reduced: false)
    check(rising.hero.scale > 10 && rising.hero.blur > 30 && rising.hero.y > 491, "onboarding v4: the star rises as a defocused sun from below")
    check(S.frame(at: 3000, layout: L, reduced: false).tagline.opacity > 0.99, "onboarding v4: the kicker and tagline are in by 1.8 s")
    let lock = S.frame(at: S.lock, layout: L, reduced: false)
    check(near(lock.hero.scale, 1) && near(lock.hero.y, L.lockY - 12) && lock.hero.blur == 0 && near(lock.hero.x, 756),
          "onboarding v4: LOCK at 5.4 s: in focus, at size, at centre")
    check(S.frame(at: 5300, layout: L, reduced: false).tagline.opacity < 0.01, "onboarding v4: the tagline is gone before the lock")
    let settled = S.frame(at: 8600, layout: L, reduced: false)
    check(near(settled.hero.x, L.lockX) && settled.cta.opacity == 1 && settled.cta.y == 0 && near(settled.cta.scale, 1)
          && settled.letters.allSatisfy { $0.opacity == 1 && $0.blur == 0 && $0.dx == 0 }, "onboarding v4: by 8.6 s the lockup and 시작하기 rest")
    check(S.frame(at: 6460 + 3 * 70, layout: L, reduced: false).letters[3].opacity == 0 && S.frame(at: 6460, layout: L, reduced: false).letters[0].opacity == 0,
          "onboarding v4: the letters set one by one, 70 ms apart")
    check(S.glint(at: 5450) == 0 && near(S.glint(at: 5800), 0.5) && S.glint(at: 6200) == -1 && near(S.glint(at: 8600), 0.5) && S.glint(at: 100) == -1,
          "onboarding v4: the glint (D) catches the tip on the focus frame and as 시작하기 arrives, 700 ms each")
    check(S.skip == 12000 && S.lock == 5400 && S.ctaIn == 8100...8600, "onboarding v4: skip at 12 s, chime at the lock, CTA at 8.1 s")

    let calm = S.frame(at: 1200, layout: L, reduced: true)
    check(calm.cta.opacity == 1 && calm.hero.scale == 1 && calm.hero.blur == 0 && calm.tagline.opacity == 0 && calm.letters.allSatisfy { $0.opacity == 1 }
          && near(calm.hero.x, L.lockX), "onboarding v4: Reduce Motion: no travel, everything cross-fades in 1.2 s")
}

@MainActor private func onboardingFlightTests() {
    typealias S = ArisOnboardingScore
    let screen = CGSize(width: 1512, height: 982), from = CGPoint(x: 665, y: 479), to = CGPoint(x: 644, y: 16)
    let start = S.flight(at: 0, from: from, to: to, screen: screen)
    check(near(start.x, from.x) && near(start.sy, 1), "onboarding v4: the flight starts where the star is")
    let crouch = S.flight(at: 239.9999, from: from, to: to, screen: screen)
    check(near(crouch.x, from.x + 6, 1e-3) && near(crouch.y, from.y + 12, 1e-3) && near(crouch.sx, 1.08, 1e-4) && near(crouch.sy, 0.9, 1e-4) && crouch.anchor == .bottom,
          "onboarding v4: anticipation: pulled down, squashed against the floor (240 ms)")
    let mid = S.flight(at: 600, from: from, to: to, screen: screen)
    check(mid.y < from.y - 100 && mid.sx > 1 && mid.scale < 1, "onboarding v4: in flight it climbs, stretches along its path and shrinks")
    let landed = S.flight(at: S.flightTimes.land, from: from, to: to, screen: screen)
    check(near(landed.x, to.x) && near(landed.y, to.y) && near(landed.scale, S.dock / S.base) && landed.anchor == .top,
          "onboarding v4: it lands on the notch's left slot at the notch star's size")
    let pop = S.flight(at: S.flightTimes.land + 70, from: from, to: to, screen: screen)
    check(near(pop.sx, 1 + 0.24 * exp(-70 / 110.0), 1e-9) && pop.sy < 1, "onboarding v4: the landing pop squashes against the band")
    let trail = S.trail(at: 600, from: from, to: to, screen: screen, size: 76.8)
    check(trail.count == 11 && near(trail[0].x, mid.x) && near(trail[0].y, mid.y), "onboarding v4: the trail is the last 170 ms of the same curve, head first")
    check(S.trail(at: 250, from: from, to: to, screen: screen, size: 76.8).count == 1, "onboarding v4: no trail before the launch")
    check(S.flightTimes.whoosh == 600 && S.flightTimes.notch == 520 && S.flightTimes.voice == 1450, "onboarding v4: whoosh peak, notch open, voice after")
}

// MARK: - The notch (notch.js)

@MainActor private func onboardingNotchTests() {
    typealias F = ArisNotchForm
    let closed = CGSize(width: 185, height: 32)
    check(F.hardware(closed: closed, hasNotch: true) == F(w: 185, h: 32, r: 8) && F.hardware(closed: closed, hasNotch: false).w == 0,
          "onboarding v4: the camera's own notch; none to draw on a display without one")
    check(F.talk(band: 270, height: 32) == F(w: 270, h: 32, r: 13) && F.rest(band: 270, height: 32) == F(w: 262, h: 32, r: 13)
          && F.message(height: 32) == F(w: 440, h: 69, r: 31), "onboarding v4: talk 270, rest 262, message 440 × 69 r31")
    check(F.message(height: 38).h == 75, "onboarding v4: a taller camera keeps the line under it")
    check(F.talk(band: 270, height: 32).slot(cx: 756) == CGPoint(x: 756 - 135 + 23, y: 16), "onboarding v4: the star's slot 23 in, on the band's line")
    check(F.message(height: 32).slot(cx: 756).y == 18.5, "onboarding v4: in the message the star stays on the band (37) line")

    var morph = ArisNotchMorph(F.hardware(closed: closed, hasNotch: true))
    morph.go(to: F.talk(band: 270, height: 32), at: 10, reduced: false)
    check(morph.ms == 280 && morph.form(at: 10) == F.hardware(closed: closed, hasNotch: true) && morph.form(at: 10.3) == F.talk(band: 270, height: 32),
          "onboarding v4: growing opens in 280 ms (.2,.8,.2,1)")
    morph.go(to: F.rest(band: 270, height: 32), at: 11, reduced: false)
    check(morph.ms == 200, "onboarding v4: shrinking closes in 200 ms (.45,0,.55,1)")
    morph.go(to: F.message(height: 32), at: 12, reduced: true)
    check(morph.ms == 120, "onboarding v4: Reduce Motion: 120 ms")
    let mid = morph.form(at: 12.06)
    check(mid.w > 262 && mid.w < 440, "onboarding v4: the outline morphs between forms")
    morph.kick(at: 20, amp: 8)
    check(morph.form(at: 20).w == 440 && morph.form(at: 20.065).w > 440 && near(morph.form(at: 21).w, 440, 0.01), "onboarding v4: the landing flexes the band, then settles")
    let path = F.talk(band: 270, height: 32).outline(cx: 756)
    check(near(path.boundingBox.minX, 756 - 135 - 13, 0.01) && near(path.boundingBox.maxX, 756 + 135 + 13, 0.01) && near(path.boundingBox.maxY, 32, 0.01),
          "onboarding v4: the silhouette: flat top, concave ears r, convex corners r")
}

// MARK: - Narration and captions, as clocks

@MainActor private func onboardingNarrationTests() {
    let n = ArisNarration(text: "세 가지만 허락해 주시면 바로 일할 수 있어요.", start: 100, reduced: false)
    check(n.words.count == 8, "onboarding v4: the line is lit word by word")
    check(n.lit(at: 100.1) == 0 && n.lit(at: 100.22) == 1 && n.lit(at: 100.22 + 0.26) == 2 && n.lit(at: 105) == 8,
          "onboarding v4: words light every 0.26 s after 220 ms")
    check(n.opacity(at: 100.14) == 0 && near(n.opacity(at: 100.32), 1) && n.opacity(at: n.foldAt + 0.17) == 0, "onboarding v4: the line fades in (140 + 180) and out (160)")
    check(near(n.foldAt, 100 + 0.22 + 8 * 0.26 + 2.6 + 0.16), "onboarding v4: the band holds 2.6 s after the last word, then folds")
    let calm = ArisNarration(text: "a b c", start: 0, reduced: true)
    check(calm.lit(at: 0) == 3 && calm.opacity(at: 0.2) == 1, "onboarding v4: Reduce Motion: the line is lit at once")
}

@MainActor private func onboardingCaptionTests() {
    let c = ArisCaptions(sentences: ["안녕하세요, 저는 Aris예요.", "뭐라고 불러드릴까요?"], start: 10, starts: [0.1, 1.9], duration: 3)
    check(near(c.revealAt[0], 10.25) && near(c.revealAt[1], 12.05), "onboarding v4: each sentence resolves 150 ms after its voice starts")
    check(c.progress(0, at: 10.2) == 0 && near(c.progress(0, at: 10.26 + 0.56), 1) && c.progress(1, at: 11) == 0, "onboarding v4: the reveal is 560 ms (blur → 0)")
    check(c.endsAt == 13 && c.speaking(at: 12) && !c.speaking(at: 13.1), "onboarding v4: the bars speak while the voice does")
    let synth = ArisCaptions.estimated(sentences: ["ab cd", "efg"], start: 0)
    check(near(synth.starts[0], 0.08) && near(synth.starts[1], 0.08 + 4 * 0.155 + 0.32) && synth.duration > synth.starts[1],
          "onboarding v4: a missing clip is paced from the text (0.155 s a syllable)")
    check(ArisCaptions.cleanName("  Al\u{0007}ex   Kim  ") == "Alex Kim" && ArisCaptions.cleanName(String(repeating: "가", count: 40)).count == 24
          && ArisCaptions.cleanName("   ").isEmpty, "onboarding v4: a typed name: no control characters, single spaces, ≤ 24")
    check(ArisCaptions.sentence(containing: 3, in: ["Hi, I'm Aris.", "What should I call you?"]) == 0
          && ArisCaptions.sentence(containing: 15, in: ["Hi, I'm Aris.", "What should I call you?"]) == 1,
          "onboarding v4: the speech synthesizer's ranges map to their sentence")
}

// MARK: - Audio analysis (audio.js)

@MainActor private func onboardingAudioTests() {
    typealias A = ArisOnboardingAudioPlan
    let rate = 1000.0
    // 0.2 s of silence, a 0.05 s click, 0.3 s quiet, a loud 0.1 s peak, silence.
    var samples = [Float](repeating: 0, count: 1000)
    for i in 200..<250 { samples[i] = 0.4 }
    for i in 550..<650 { samples[i] = 0.9 }
    let m = A.analyse(samples, rate: rate)
    check(near(m.hit, 0.2, 0.011) && near(m.peak, 0.55, 0.011) && near(m.from, 0.2, 0.011) && near(m.to, 0.65, 0.011),
          "onboarding v4: a cue's transient (−12 dB of peak), loudest moment and active region")
    // Two words, a long gap, a third: the two longest gaps split three sentences.
    var voice = [Float](repeating: 0, count: 3000)
    for r in [100..<500, 560..<900, 1500..<2600] { for i in r { voice[i] = 0.5 } }
    let runs = A.speechRuns(voice, rate: rate)
    check(runs.count == 2 && near(runs[0].start, 0.1, 0.021) && near(runs[1].start, 1.5, 0.021), "onboarding v4: speech runs join gaps under 140 ms")
    let starts = A.sentenceStarts(runs: runs, duration: 3, sentences: ["안녕하세요.", "뭐라고 불러드릴까요?"])
    check(starts.count == 2 && near(starts[0], 0.1, 0.021) && near(starts[1], 1.5, 0.021), "onboarding v4: sentence starts sit on the voice's own pauses")
    let even = A.sentenceStarts(runs: [A.Run(start: 0, end: 2)], duration: 2, sentences: ["ab", "cd"])
    check(near(even[0], 0) && near(even[1], 1), "onboarding v4: no pause to split on: proportional to length")
    let early = A.cueStart(at: 5, offset: 0.2, now: 1), late = A.cueStart(at: 5, offset: 0.2, now: 4.9)
    check(near(early?.when ?? 0, 4.8) && early?.skip == 0 && near(late?.when ?? 0, 4.9) && near(late?.skip ?? 0, 0.1)
          && A.cueStart(at: 5, offset: 0.05, now: 5.2) == nil, "onboarding v4: a cue lands its hit on the beat; late by more than 80 ms is dropped")
    check(!A.audible(muted: true, micListening: false) && !A.audible(muted: false, micListening: true) && A.audible(muted: false, micListening: false),
          "onboarding v4: never plays while muted or while the mic listens")
    check(A.cueGain == 0.5 && A.ambientGain == 0.55 && near(Double(A.duck), 0.4, 1e-6), "onboarding v4: the mix: cues −6 dB, the bed ducked −8 dB under the voice")
    let loop = A.loopCrossfade(count: 100, fade: 10)
    check(loop.count == 10 && near(Double(loop[0].rise), 0) && near(Double(loop[9].rise), 1) && near(Double(loop[9].fall), 0, 1e-6)
          && loop.allSatisfy { near(Double($0.rise * $0.rise + $0.fall * $0.fall), 1, 1e-5) }, "onboarding v4: the bed loops on an equal-power crossfade")
    let levels = A.barLevels(envelope: [0, 0.5, 1], at: 0.15, window: 0.1, bars: 5)
    check(levels.count == 5 && levels.allSatisfy { $0 >= 0 && $0 <= 1 } && levels.contains { $0 > 0.3 }, "onboarding v4: the notch's bars follow the voice")
}

// MARK: - The setup window's flow (setup.js, perms.js)

@MainActor private func onboardingFlowTests() {
    typealias C = ArisPermissionCard
    var flow = ArisSetupFlow()
    check(flow.page == .permissions && ArisSetupPage.allCases.count == 5, "onboarding v4: 권한 → 눌러서 말하기 → AI 고르기 → 아리스라고 부르기 → 받아쓰기 (fresh install F2, F4; picks of 2026-11-11)")
    flow.begin(granted: [.mic: true])
    check(flow.active == .accessibility && flow.state(.mic, granted: true) == .granted, "onboarding v4: a permission already on is checked; the first left opens")
    flow.ask(.accessibility)
    check(flow.state(.accessibility, granted: false) == .waiting, "onboarding v4: 허용: the card waits for macOS")
    check(!flow.continueShown(granted: [.mic: true]), "onboarding v4: 계속 waits for the mic and Accessibility (or all decided)")
    flow.settle(granted: [.mic: true, .accessibility: true])
    check(flow.active == .screen && flow.continueShown(granted: [.mic: true, .accessibility: true]), "onboarding v4: granted: on to the next; 계속 shows")
    flow.putOff(.screen)
    check(flow.state(.screen, granted: false) == .later && flow.active == nil && flow.allDecided(granted: [.mic: true, .accessibility: true]),
          "onboarding v4: 나중에 marks it for later")
    check(near(flow.progress(granted: [.mic: true, .accessibility: true]), 1.0 / 5), "onboarding v4: the rail: an equal share per page, the permissions by thirds")
    var none = ArisSetupFlow()
    none.begin(granted: [:])
    check(near(none.progress(granted: [:]), 0) && none.active == .mic, "onboarding v4: nothing decided: the rail is empty, the mic opens")
    none.putOff(.mic)
    check(near(none.progress(granted: [:]), 1.0 / 5 / 3), "onboarding v4: each decision advances the rail")
    check(none.next() && none.page == .ask && near(none.progress(granted: [:]), 1.0 / 5), "onboarding v4: 계속 → 눌러서 말하기")
    check(none.next() && none.next() && none.next() && none.page == .dictation && !none.next() && none.finished, "onboarding v4: 마치기 on the last page finishes")
    check(near(none.progress(granted: [:]), 1), "onboarding v4: finished: the rail is full")
    var back = ArisSetupFlow(page: .brain)
    back.back()
    check(back.page == .ask && back.backShown, "onboarding v4: 뒤로 one page")
    back.back(); back.back()
    check(back.page == .permissions && !back.backShown, "onboarding v4: no 뒤로 on the first page")
    check(C.mic.steps == [.mic, .speech] && C.accessibility.steps == [.accessibility] && C.screen.steps == [.screen],
          "onboarding v4: the mic card asks for the mic and on-device speech recognition (Aris needs both to hear)")
    check(C.mic.way == .ask && C.accessibility.way == .settings && C.screen.way == .settings, "onboarding v4: a dialog, or System Settings with the drag panel")
    check(ArisSetupPage.resume(saved: 3) == .ask && ArisSetupPage.resume(saved: 9) == .permissions && ArisSetupPage.resume(saved: 5) == .dictation,
          "onboarding v4: a saved page resumes (the old question page is the try page now); anything else starts at 권한")
}

@MainActor private func onboardingModelTests() {
    var grants: [ArisOnboardingStep: ArisGrant] = [.mic: .granted, .speech: .undecided]
    var asked: [ArisOnboardingStep] = []
    let actions = ArisOnboardingModel.Actions(grant: { grants[$0] ?? .undecided }, request: { asked.append($0) }, stop: { _ in },
                                              talkKeys: { ["⌥", "Space"] })
    let model = ArisOnboardingModel(actions: actions)
    check(!model.granted(.mic), "onboarding v4: the mic card is on only with the mic and speech recognition both")
    model.begin()
    check(model.flow.active == .mic, "onboarding v4: begin opens the first card left")
    var popped: [ArisPermissionCard] = []
    model.onGranted = { popped.append($0) }
    model.allow(.mic)
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    check(asked == [.speech], "onboarding v4: 허용 asks macOS only for what isn't decided yet")
    grants[.speech] = .granted
    model.refresh()
    check(model.granted(.mic) && popped == [.mic] && model.flow.active == .accessibility, "onboarding v4: granted: the check pops, the next card opens")
    model.refresh()
    check(popped == [.mic], "onboarding v4: one pop per card")
    model.allow(.accessibility)
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    check(model.flow.state(.accessibility, granted: false) == .waiting, "onboarding v4: System Settings is open; the card waits")
    model.later(.accessibility)
    check(model.flow.state(.accessibility, granted: false) == .later && model.flow.active == .screen, "onboarding v4: 나중에 while waiting moves on")
    model.start()
    check(model.polling, "onboarding v4: the 1 s check runs while open")
    model.stop()
    check(!model.polling, "onboarding v4: closing stops the check")
    grants[.mic] = .denied
    let denied = ArisOnboardingModel(actions: actions)
    denied.begin()
    denied.allow(.mic)
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    denied.refresh()
    check(denied.flow.state(.mic, granted: false) == .later, "onboarding v4: a no in macOS's dialog is put off (Aris asks again when needed)")
}

// MARK: - Windows, levels, Esc, exits (the hard-won behaviour of E)

@MainActor private func onboardingStageTests() {
    typealias S = ArisOnboardingStage
    check(S.mainMenuLevel == Int(CGWindowLevelForKey(.mainMenuWindow)), "onboarding v4: the main menu level is macOS's")
    check(S.overlayLevel > Int(CGWindowLevelForKey(.mainMenuWindow)) && S.overlayLevel > Int(CGWindowLevelForKey(.dockWindow)),
          "onboarding v4: the veil covers the menu bar and Dock")
    check(S.yieldLevel < Int(CGWindowLevelForKey(.normalWindow)), "onboarding v4: stepping aside, the veil is under every window")
    for phase in [ArisOnboardingPhase.intro, .flight, .talk] {
        check(S.overlay(phase: phase, active: true) == .init(level: S.overlayLevel, clickThrough: false), "onboarding v4: the veil leads (\(phase))")
        check(S.overlay(phase: phase, active: false) == .init(level: S.yieldLevel, clickThrough: true), "onboarding v4: inactive, the veil steps aside (\(phase))")
    }
    check(S.overlay(phase: .handoff, active: true).clickThrough && S.overlay(phase: .setup, active: true) == .init(level: S.yieldLevel, clickThrough: true),
          "onboarding v4: from the handoff the veil passes every click")
    check(S.windowLevel(handingOff: true) == S.overlayLevel + 1 && S.windowLevel(handingOff: false) == Int(CGWindowLevelForKey(.normalWindow)),
          "onboarding v4: the window rides over the lifting veil, then is an ordinary window (alerts and System Settings above it)")
    for phase in [ArisOnboardingPhase.intro, .flight, .talk, .handoff, .setup, .finish] {
        check(S.escapeCloses(phase: phase, guideKey: true), "onboarding v4: Esc closes (\(phase))")
    }
    check(!S.escapeCloses(phase: .setup, guideKey: false) && !S.escapeCloses(phase: .closed, guideKey: true), "onboarding v4: Esc from another window is left alone")
    check(S.exitShown(phase: .intro) && S.exitShown(phase: .talk) && !S.exitShown(phase: .finish), "onboarding v4: a mouse-reachable ✕ on the veil")
    check(S.skipShown(phase: .intro, elapsedMs: 12_000) && !S.skipShown(phase: .intro, elapsedMs: 11_000) && S.skipShown(phase: .talk, elapsedMs: 20_000)
          && !S.skipShown(phase: .setup, elapsedMs: 20_000), "onboarding v4: 건너뛰기 from 12 s, in the intro and the talk")
    check(S.muteShown(phase: .intro, veil: 0.6) && !S.muteShown(phase: .intro, veil: 0.4) && !S.muteShown(phase: .setup, veil: 1),
          "onboarding v4: the mute sits bottom-left once the veil is in")
    check(S.skipTarget(phase: .intro) == .setup && S.skipTarget(phase: .talk) == .setup && S.ctaTarget == .talk,
          "onboarding v4: 시작하기 flies to the talk; 건너뛰기 goes straight to the window")
    check(S.ownsNotch(phase: .setup, realActive: false) && !S.ownsNotch(phase: .setup, realActive: true) && !S.ownsNotch(phase: .closed, realActive: false),
          "onboarding v4: the guide hands the notch back while Aris really listens, answers or dictates")
    check(S.realHolds(active: true, dictating: false, notchOpen: false) && S.realHolds(active: false, dictating: true, notchOpen: false)
          && S.realHolds(active: false, dictating: false, notchOpen: true, holding: true) && !S.realHolds(active: false, dictating: false, notchOpen: true, holding: false)
          && !S.realHolds(active: false, dictating: false, notchOpen: false, holding: true), "onboarding v4: the real notch keeps it until its answer closes")
}

@MainActor private func onboardingDisplayTests() {
    typealias D = ArisOnboardingStage.Display
    let builtIn = D(uuid: "B", hasNotch: true), ext = D(uuid: "E", hasNotch: false), ext2 = D(uuid: "F", hasNotch: false)
    check(ArisOnboardingStage.display([ext, builtIn], windowed: ["E", "B"], primary: "E") == "B", "onboarding v4: the notched display wins")
    check(ArisOnboardingStage.display([ext, ext2], windowed: ["E", "F"], primary: "F") == "F", "onboarding v4: no notch: the primary's band display")
    check(ArisOnboardingStage.display([builtIn], windowed: [], primary: "B") == nil, "onboarding v4: no notch window: nil (the window alone)")
    check(ArisOnboardingStage.display([], windowed: [], primary: nil) == nil, "onboarding v4: no displays: nil")
}

// MARK: - Launches, quitting, later

@MainActor private func onboardingLaunchTests() {
    typealias O = ArisOnboarding
    check(O.replayKey == "arisOnboardingReplay" && O.seenKey == "arisOnboardingSeen" && O.laterKey == "arisOnboardingLater",
          "onboarding v4: -arisOnboardingReplay YES; the launch smoke's -arisOnboardingSeen YES")
    // The owner's ruling of 2026-11-11: the × (a dismissed close) means "later" too; only finishing marks it done (onboard2-tests.swift).
    check(O.afterClose(.finished) == .init(seen: true, later: false) && O.afterClose(.dismissed) == .init(seen: false, later: true)
          && O.afterClose(.later) == .init(seen: false, later: true), "onboarding v4: 나중에 할게요 and the × leave it unseen to resume")
    check(O.persisted(phase: .setup) == .init(seen: false, later: true) && O.persisted(phase: .finish) == .init(seen: true, later: false)
          && O.persisted(phase: .intro) == nil, "onboarding v4: mid-setup a quit or crash keeps the pages left")
    check(O.closeOnQuit(phase: .setup) == .later && O.closeOnQuit(phase: .talk) == .later && O.closeOnQuit(phase: .finish) == .finished,
          "onboarding v4: quitting mid-way is later; at the finish it's done")
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    func launch(seen: Bool = false, later: Bool = false, replay: Bool = false, login: Bool = false, last: Date? = nil, count: Int = 0,
                quit: Date? = nil) -> O.Launch {
        O.launch(seen: seen, later: later, replay: replay, loginItem: login, lastResume: last, resumes: count, quitAt: quit, now: now)
    }
    check(launch() == .intro && launch(seen: true) == .none && launch(seen: true, replay: true) == .intro, "onboarding v4: first launch, seen, replay")
    check(launch(later: true) == .resume && launch(later: true, login: true) == .none, "onboarding v4: later resumes, never for a login item")
    check(launch(later: true, last: now.addingTimeInterval(-3600)) == .none && launch(later: true, last: now.addingTimeInterval(-25 * 3600)) == .resume,
          "onboarding v4: at most once a day")
    check(launch(later: true, last: now.addingTimeInterval(-3600), quit: now.addingTimeInterval(-60)) == .resume,
          "onboarding v4: Quit & Reopen mid-setup resumes the same day")
    check(launch(later: true, count: 3) == .none, "onboarding v4: auto-resumes stop after 3 (crash guard)")
    check(O.resumes(later: true, replay: false) && !O.resumes(later: true, replay: true), "onboarding v4: a replay starts from the intro")
    check(O.pageKey == "arisOnboardingPage" && O.nameKey == "arisOnboardingName" && O.mutedKey == "arisOnboardingMuted", "onboarding v4: what it keeps")
}

@MainActor private func onboardingClockTests() {
    let clocks = ArisOnboardingClocks()
    var ran: [String] = []
    clocks.after(0.05) { ran.append("a") }
    clocks.after(0.05, name: "x") { ran.append("old") }
    clocks.after(0.05, name: "x") { ran.append("x") }
    check(clocks.pending == 2, "onboarding v4: a named beat replaces the one still waiting")
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    check(ran.sorted() == ["a", "x"] && clocks.pending == 0, "onboarding v4: beats run once")
    clocks.after(0.05) { ran.append("late") }
    clocks.cancelAll()
    RunLoop.main.run(until: Date().addingTimeInterval(0.15))
    check(clocks.pending == 0 && !ran.contains("late"), "onboarding v4: nothing fires after close")
}

// MARK: - Language

@MainActor private func onboardingLanguageTests() {
    typealias L = ArisOnboardingLanguage
    let have: Set<String> = ["ko", "en"]
    check(L.choose(preferred: ["en-US", "ko-KR"], available: have) == "en" && L.choose(preferred: ["ko-KR"], available: have) == "ko",
          "onboarding v4: the app's language")
    check(L.choose(preferred: ["de-DE", "en-GB"], available: have) == "en", "onboarding v4: the first preferred language that has the onboarding")
    check(L.choose(preferred: ["de-DE", "fr"], available: have) == "en" && L.choose(preferred: [], available: have) == "en",
          "onboarding v4: English when the system is neither, as everywhere else in the app (fresh install F5; it was Korean here alone)")
    check(L.choose(preferred: ["de-DE"], available: ["ko", "en", "de"]) == "de", "onboarding v4: a language added later is used")
    check(L.synthesizerVoice(for: "en") == "en-US" && L.synthesizerVoice(for: "ko") == "ko-KR" && L.synthesizerVoice(for: "de") == "de-DE",
          "onboarding v4: a missing recording speaks in the UI's own language")
    check(L.voiceFile("greet", language: "en") == "OnboardingAudio/voice/en/greet" && L.voiceFile("greet-name", language: "ko") == "OnboardingAudio/voice/ko/greet-name",
          "onboarding v4: voice lines by language")
}
