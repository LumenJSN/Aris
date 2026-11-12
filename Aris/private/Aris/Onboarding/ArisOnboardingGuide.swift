//
//  ArisOnboardingGuide.swift
//  Aris
//
//  The user's first-run onboarding v4 (mockups/onboarding2, approved 2026-11-07), the director: one clock (the media
//  clock, shared with the sound), one star, the beats in order:
//    intro on a full-screen veil (the star rises like a sunrise, the glint, the kicker and tagline, 시작하기)
//    → flight (anticipation, a curved throw with a shooting-star trail into the real notch, the landing pop)
//    → talk (Aris speaks from the notch, captions trailing the voice; the name; a greeting by name)
//    → handoff (the veil lifts in 0.8 s while the setup window settles in, 920 ms)
//    → setup (권한, 눌러서 말하기, AI 고르기, 아리스라고 부르기, 받아쓰기: the ones this person will see, ArisSetupPlan;
//      each narrated by the notch; every page does the real thing)
//    → finish (the window closes; the real notch opens with three things to try, ArisFirstTries).
//  The views are pure functions of this state and the clock (ArisOnboardingOverlay, …Notch, …Window); every delayed
//  beat runs through ArisOnboardingClocks, so closing stops them all. The beats are in ArisOnboardingGuide+Intro and
//  ArisOnboardingGuide+Setup.
//
//  E's hard-won behaviour stays: nothing covers macOS's alerts or System Settings (the veil leads only in the intro and
//  steps aside whenever Aris isn't active; the setup window is an ordinary window); Esc closes and a mouse-reachable ✕
//  is always there, and both mean "later" until the last page is finished (ArisOnboarding.closing); 나중에 할게요
//  resumes later quietly (at most once a day, never at login); Quit & Reopen resumes the
//  page; Reduce Motion is cross-fades only; nothing keeps running after close; a display without a notch, or several,
//  still host it.
//
//  While one of its windows is open Aris is an app with a Dock icon and its own menu bar, and the setup window keeps
//  the front through macOS's prompts and when Aris is opened again (ArisOnboardingFront, ArisOnboardingGuide+Front).
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class ArisOnboardingGuide: ObservableObject {
    static let shared = ArisOnboardingGuide()

    /// The notch that hosts the onboarding and its display (the app delegate sets it once the notch windows exist).
    var notch: @MainActor () -> (model: ArisNotchModel, screen: NSScreen)? = { nil }

    @Published var phase: ArisOnboardingPhase = .closed {
        didSet { if phase != oldValue { persist() } }
    }
    @Published var reduced = false
    /// Aris is the active app; when it isn't, the veil steps aside.
    @Published var active = true
    /// Resumed after 나중에 할게요: no veil, no sound, straight into the setup window.
    @Published var quiet = false
    @Published var muted = false

    // The host display.
    @Published var screenSize = CGSize(width: 1512, height: 982)
    @Published var closedSize = CGSize(width: 185, height: 32)
    @Published var hasNotch = true

    // The intro's clock: story time 0 (media seconds).
    @Published var t0: Double = 0
    @Published var flight: ArisOnboardingFlight?
    /// The veil lifting at the handoff: when it starts and how long it takes.
    @Published var lift: (start: Double, seconds: Double)?

    // The talk.
    @Published var spoken: ArisOnboardingSpoken?
    @Published var captionsClearAt: Double?
    @Published var composerAt: Double?
    @Published var nameText = ""
    @Published var nameError = false
    @Published var nameSent = false

    // The notch.
    @Published var morph = ArisNotchMorph(ArisNotchForm(w: 185, h: 32, r: 8))
    @Published var popAt: Double = -1e9
    @Published var docked = false
    @Published var narration: ArisNarration?
    @Published var starWorking = false

    // The setup.
    @Published var model: ArisOnboardingModel?
    @Published var page: ArisSetupPage = .permissions
    /// The pages this person sees, decided as the window opens (ArisSetupPlan); the rail's steps are these.
    @Published var plan = ArisSetupPlan.everyPage
    /// 눌러서 말하기: the first request was really done (계속 shows; kept if the user goes back and forth).
    /// The timer the practice turn set, as it was set, until the setup is over (ArisPracticeLeftovers).
    var practiceTimer: ArisTimerState?
    @Published var askAnswered = false
    /// 눌러서 말하기: how the last practice turn ended (the page's note says so).
    @Published var tryOutcome: ArisSetupTry.Outcome?
    /// AI 고르기: the API key's form is open under its row.
    @Published var brainKeyOpen = false
    /// AI 고르기: what the last press of Check again found (the page says so).
    @Published var brainChecked: ArisOnboardingBrainRows.Checked?
    /// AI 고르기: at some point of this setup no AI was set up here, so the page keeps the key field first.
    @Published var brainStartedEmpty = false
    /// AI 고르기: a key was saved and the helper's check of it failed; what the form says about it.
    @Published var brainKeyTrouble: String?
    /// The setup window's size and place on its display (ArisOnboardingStage.fit).
    @Published var fit = ArisOnboardingStage.designFit

    let clocks = ArisOnboardingClocks()
    let watch = ArisOnboardingWatch()
    var audio: ArisOnboardingAudio?
    var overlay: ArisOnboardingOverlayWindow?
    var window: ArisOnboardingSetupWindow?
    weak var notchModel: ArisNotchModel?
    var watchers: Set<AnyCancellable> = []
    /// The host notch's state, watched once: a new host (a Space change, wake, a display change) replaces it.
    var notchWatch: AnyCancellable?
    /// Which AIs are set up, watched while the setup window is open (the plan learns from it).
    var brainWatch: AnyCancellable?
    /// The real notch is in use (a turn, a dictation, or the answer it left open): the guide stays out of it.
    var realHolds = false
    /// This onboarding opened ArisPermissionGuide's drag panel (closing closes it).
    var openedDragPanel = false
    /// It opened within minutes of a quit mid-setup (Quit & Reopen after Screen Recording): the user came back for it.
    var reopened = false
    var hostScreen: NSScreen?
    /// When the setup window last came forward on purpose (ArisOnboardingFront.holds); nil when it never did, or
    /// System Settings was opened for a permission since.
    var forwardAt: Double?
    /// How many times in a row it took the front back from another app since then.
    var frontHolds = 0
    /// System Settings as the setup opened it, and the app the user last had (ArisOnboardingGuide+Leave).
    var leave = ArisSetupLeave()
    /// The app to bring forward once the closing window is gone.
    var handBackTo: String?
    /// Aris is quitting with the guide open (Quit & Reopen comes back to it).
    var quitting = false
    /// The setup had been finished before this showing (a replay): closing it leaves it finished.
    var doneBefore = false

    var showing: Bool { phase != .closed }
    var bandWidth: Double { Double(ArisBand.bodyWidth(notchWidth: closedSize.width)) }
    var bandHeight: Double { Double(max(closedSize.height, 24)) }
    var talkForm: ArisNotchForm { .talk(band: bandWidth, height: bandHeight) }
    var restForm: ArisNotchForm { .rest(band: bandWidth, height: bandHeight) }
    /// The message band for a line (14 medium, −.01 em, as the notch draws it).
    func messageForm(for line: String) -> ArisNotchForm {
        let width = (line as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 14, weight: .medium), .kern: -0.14]).width
        return .message(height: bandHeight, lineWidth: Double(width))
    }

    static func now() -> Double { ArisOnboardingAudio.now() }

    // MARK: - Opening

    /// At launch (ArisOnboarding.launch): the intro the first time or with `-arisOnboardingReplay YES` (read once,
    /// then cleared); after 나중에 할게요 the pages left, quietly, at most once a day, never for a login item, at most 3
    /// times in a row.
    func showAtLaunch(loginItem: Bool) {
        let defaults = UserDefaults.standard
        let replay = defaults.bool(forKey: ArisOnboarding.replayKey)
        defaults.removeObject(forKey: ArisOnboarding.replayKey)
        let resumes = defaults.integer(forKey: ArisOnboarding.resumeCountKey)
        switch ArisOnboarding.launch(seen: defaults.bool(forKey: ArisOnboarding.seenKey), later: defaults.bool(forKey: ArisOnboarding.laterKey),
                                     replay: replay, loginItem: loginItem, lastResume: defaults.object(forKey: ArisOnboarding.lastResumeKey) as? Date,
                                     resumes: resumes, quitAt: defaults.object(forKey: ArisOnboarding.quitAtKey) as? Date, now: Date()) {
        case .none: return
        case .intro: show(replay: true)
        case .resume:
            defaults.set(resumes + 1, forKey: ArisOnboarding.resumeCountKey)
            defaults.set(Date(), forKey: ArisOnboarding.lastResumeKey)
            show()
        }
    }

    /// From the intro on a replay (settings › 처음 안내 다시 보기); after 나중에 할게요 or the × quietly at the page left.
    /// `asked`: the user asked for it (the ✦ menu), so it opens in front with the keyboard. Already showing: brings it
    /// forward.
    func show(replay: Bool = false, asked: Bool = false) {
        if showing { return surface() }
        let defaults = UserDefaults.standard
        // Read before this showing writes anything: closing a setup that was already finished leaves it finished.
        doneBefore = ArisOnboarding.doneBefore(seen: defaults.bool(forKey: ArisOnboarding.seenKey), later: defaults.bool(forKey: ArisOnboarding.laterKey))
        let resuming = ArisOnboarding.resumes(later: defaults.bool(forKey: ArisOnboarding.laterKey), replay: replay)
        reopened = (defaults.object(forKey: ArisOnboarding.quitAtKey) as? Date).map { Date().timeIntervalSince($0) < ArisOnboarding.reopenWindow } ?? false
        defaults.removeObject(forKey: ArisOnboarding.quitAtKey)
        // The intro counts as seen from the moment it shows (a crash in it doesn't bring it back at every launch).
        if !resuming { defaults.set(true, forKey: ArisOnboarding.seenKey) }
        ArisOnboardingCopy.use(ArisUILanguage.code)
        reduced = ArisOnboardingWatch.reduceMotion
        quiet = resuming && !asked
        muted = defaults.bool(forKey: ArisOnboarding.mutedKey)
        active = true
        let audio = ArisOnboardingAudio(muted: muted)
        audio.micListening = { ArisController.shared.micListening }
        self.audio = audio
        watchReal()
        startWatching()
        beginLeave()
        // A notch already open (an approval) stays the real one's until it closes (N3).
        realHolds = ArisOnboardingStage.holdingAtStart
        // The intro lands in a camera notch. A display without one (an external monitor, a Mac with no notch, a VM) gets
        // the setup window at once, and the real notch is left as it is (QA BUG-56: the intro's notch drew at zero width,
        // so nothing showed and the notch itself was gone).
        let found = notch()
        let host = found.flatMap { ArisOnboardingStage.introHost(hasNotch: $0.screen.safeAreaInsets.top > 0) ? $0 : nil }
        if let host { attach(host) }
        updateReal()
        if resuming || host == nil {
            let saved = ArisSetupPage.resume(saved: defaults.integer(forKey: ArisOnboarding.pageKey))
            return openSetup(page: resuming ? saved : .permissions, handingOff: false)
        }
        audio.start()
        overlay = ArisOnboardingOverlayWindow(screen: host!.screen, guide: self)
        applyPolicy()
        phase = .intro
        startIntro()
        applyOverlay()
        overlay?.makeKeyAndOrderFront(nil)
        // Over the app that was in front at launch (a plain activate() may be refused while another app is active).
        NSApp.activate(ignoringOtherApps: true)
        // Activation can still be refused (macOS 14's cooperative activation): then the veil steps aside at once.
        after(0.3) { $0.setActive(NSApp.isActive) }
    }

    /// The status item, the notch's hot key, 처음 안내 다시 보기, Aris opened again or its settings window closed while
    /// it shows: forward. The setup window goes in front of the other apps' windows (VM bug 6: it stayed behind
    /// Terminal's when the settings window closed).
    func surface() {
        guard showing else { return }
        if ArisOnboardingStage.surfaceReopensSetup(phase: phase) { return reopenSetup() }
        applyPolicy()
        if let window {
            claimFront()
            window.bringForward()
        } else {
            overlay?.orderFrontRegardless()
            if active { overlay?.makeKey() }
            NSApp.activate()
        }
    }

    func attach(_ host: (model: ArisNotchModel, screen: NSScreen)) {
        if notchModel !== host.model { notchModel?.guide = nil }
        notchModel = host.model
        hostScreen = host.screen
        screenSize = host.screen.frame.size
        closedSize = host.model.closedNotchSize
        hasNotch = host.screen.safeAreaInsets.top > 0
        notchWatch = host.model.$notchState.sink { [weak self] _ in DispatchQueue.main.async { MainActor.assumeIsolated { self?.updateReal() } } }
        applyNotch()
    }

    // MARK: - Closing

    /// The setup put off (its ×, Esc or 나중에 할게요) is continued at the page that was left: the ✦ menu's entry.
    func continueSetup() { show(asked: true) }

    /// Finished, Esc or ✕ (dismissed), 나중에 할게요 or quitting mid-way (later): everything goes and no clock keeps
    /// running. Esc and the ✕ before the last page is finished mean "later" (ArisOnboarding.closing).
    func close(_ how: ArisOnboarding.Close = .dismissed) {
        guard showing else { return }
        let reason = ArisOnboarding.closing(how, phase: phase, doneBefore: doneBefore)
        let defaults = UserDefaults.standard, after = ArisOnboarding.afterClose(reason)
        defaults.set(after.seen, forKey: ArisOnboarding.seenKey)
        defaults.set(after.later, forKey: ArisOnboarding.laterKey)
        if reason != .later {
            defaults.removeObject(forKey: ArisOnboarding.resumeCountKey)
            defaults.removeObject(forKey: ArisOnboarding.lastResumeKey)
            defaults.removeObject(forKey: ArisOnboarding.pageKey)
        }
        // Put off, or closed before its end: the practice's timer and reply go with the setup. (Finish did this
        // itself, before the three things to try came up: nothing of theirs is cleared here.)
        if phase != .finish { ArisController.shared.clearPracticeLeftovers(timer: practiceTimer) }
        practiceTimer = nil
        clocks.cancelAll()
        watchers.removeAll()
        notchWatch = nil
        brainWatch = nil
        watch.stop()
        model?.stop()
        model = nil
        audio?.stop()
        audio = nil
        if openedDragPanel { ArisPermissionGuide.shared.close() }
        // A System Settings that is only there because the setup opened it is not what the user is left looking at.
        if window != nil { stepBackFromSettings() }
        if !quitting { forgetLeave() }
        overlay?.orderOut(nil)
        overlay?.close()
        overlay = nil
        window?.orderOut(nil)
        window?.close()
        window = nil
        handBack()
        applyPolicy()
        notchModel?.guide = nil
        notchModel = nil
        reset()
        // The wake word waits for the guide's permission page (ArisWakeArm): now that the guide is gone, one turned
        // on in it (or on from before) starts listening, without waiting for a first turn to end.
        ArisController.shared.waitForWakeWordSoon()
    }

    /// The app is quitting: mid-way that's 나중에 할게요 (Quit & Reopen after Screen Recording resumes the page).
    func closeForQuit() {
        guard showing else { return }
        let reason = ArisOnboarding.closeOnQuit(phase: phase)
        if reason == .later { UserDefaults.standard.set(Date(), forKey: ArisOnboarding.quitAtKey) }
        // Quit & Reopen comes back to the same System Settings: nothing is hidden, and what the setup started stays kept.
        quitting = true
        close(reason)
    }

    private func persist() {
        guard let keys = ArisOnboarding.persisted(phase: phase) else { return }
        UserDefaults.standard.set(keys.seen, forKey: ArisOnboarding.seenKey)
        UserDefaults.standard.set(keys.later, forKey: ArisOnboarding.laterKey)
    }

    private func reset() {
        phase = .closed
        quiet = false
        active = true
        flight = nil
        lift = nil
        spoken = nil
        captionsClearAt = nil
        composerAt = nil
        nameText = ""
        nameError = false
        nameSent = false
        popAt = -1e9
        docked = false
        narration = nil
        starWorking = false
        page = .permissions
        plan = .everyPage
        askAnswered = false
        tryOutcome = nil
        brainKeyOpen = false
        brainChecked = nil
        brainStartedEmpty = false
        brainKeyTrouble = nil
        leave = ArisSetupLeave()
        handBackTo = nil
        quitting = false
        doneBefore = false
        fit = ArisOnboardingStage.designFit
        realHolds = false
        openedDragPanel = false
        reopened = false
        hostScreen = nil
        forwardAt = nil
        frontHolds = 0
    }

    // MARK: - Watching

    private func startWatching() {
        watch.start(.init(
            escape: { [weak self] in
                guard let self else { return false }
                let key = NSApp.keyWindow
                let ours = key != nil && (key === self.overlay || key === self.window)
                guard ArisOnboardingStage.escapeCloses(phase: self.phase, guideKey: ours) else { return false }
                self.close(.dismissed)
                return true
            },
            active: { [weak self] in self?.setActive($0) },
            front: { [weak self] bundleID, regular in
                self?.noteFront(bundleID: bundleID, regular: regular)
                self?.appCameForward(bundleID: bundleID, regular: regular)
            },
            // Displays, wake, Space: the notch windows are rebuilt on the next main turn; look again a moment later.
            host: { [weak self] in self?.after(0.3, name: "host") { $0.hostChanged() } },
            reduceMotion: { [weak self] now in self?.reduced = now }))
    }

    private func hostChanged() {
        refitWindow()
        guard let host = notch(), ArisOnboardingStage.introHost(hasNotch: host.screen.safeAreaInsets.top > 0) else {
            // No notch window anywhere: the intro can't land; the setup window carries on alone.
            notchModel?.guide = nil
            notchModel = nil
            notchWatch = nil
            if [.intro, .flight, .talk].contains(phase) { toWindow() }
            return
        }
        attach(host)
        overlay?.place(on: host.screen)
        screenSize = host.screen.frame.size
    }

    func setActive(_ now: Bool) {
        guard showing, now != active else { return }
        active = now
        applyOverlay()
        if now { overlay?.makeKey() }
    }

    /// The veil's level and mouse for this beat.
    func applyOverlay() {
        let w = ArisOnboardingStage.overlay(phase: phase, active: active)
        overlay?.level = NSWindow.Level(rawValue: w.level)
        overlay?.ignoresMouseEvents = w.clickThrough
    }

    /// ArisController and the host notch: hand the notch back while it is really in use, take it again once it closes.
    private func watchReal() {
        let controller = ArisController.shared
        controller.objectWillChange
            .sink { [weak self] _ in DispatchQueue.main.async { MainActor.assumeIsolated { self?.updateReal() } } }
            .store(in: &watchers)
    }

    func updateReal() {
        guard showing else { return }
        let c = ArisController.shared
        let holds = ArisOnboardingStage.realHolds(active: c.session.phase != .idle, dictating: c.dictation != nil,
                                                  notchOpen: notchModel?.notchState == .open, holding: realHolds)
        if holds && !realHolds {
            clocks.cancel(name: "narrate")
            narration = nil
            morph.snap(restForm)
        }
        realHolds = holds
        audio?.micChanged()
        applyNotch()
    }

    func applyNotch() {
        guard let notchModel else { return }
        let own = ArisOnboardingStage.ownsNotch(phase: phase, realActive: realHolds)
        if own, notchModel.guide !== self { notchModel.guide = self } else if !own, notchModel.guide != nil { notchModel.guide = nil }
    }

    // MARK: - Helpers

    func after(_ seconds: Double, name: String? = nil, _ work: @escaping @MainActor (ArisOnboardingGuide) -> Void) {
        clocks.after(seconds, name: name) { [weak self] in
            guard let self, self.showing else { return }
            work(self)
        }
    }

    func setMuted(_ on: Bool) {
        muted = on
        UserDefaults.standard.set(on, forKey: ArisOnboarding.mutedKey)
        audio?.setMuted(on)
    }

    /// The flight's target: the notch's left slot, in the veil's coordinates.
    func notchSlot(_ form: ArisNotchForm) -> CGPoint { form.slot(cx: Double(screenSize.width) / 2) }
}

/// The flight after 시작하기 (or 건너뛰기 in the intro): when it started, the story time then, and its two ends.
struct ArisOnboardingFlight: Equatable {
    var start: Double
    var tc: Double
    var from: CGPoint
    var to: CGPoint
    var next: ArisOnboardingStage.Next
}

/// A voice line on screen: its captions' clock (the synthesizer's starts arrive as it speaks).
struct ArisOnboardingSpoken: Equatable {
    var sentences: [String]
    var start: Double
    var starts: [Double]
    var duration: Double
    var synthesized: Bool
    var done = false

    /// The captions now (a synthesized line takes the starts the synthesizer has reported so far).
    func captions(synthStarts: [Double]) -> ArisCaptions {
        guard synthesized else { return ArisCaptions(sentences: sentences, start: start, starts: starts, duration: duration) }
        let reported = synthStarts.map { $0 - start }
        let padded = sentences.indices.map { $0 < reported.count ? reported[$0] : 1e9 }
        return ArisCaptions(sentences: sentences, start: start, starts: padded, duration: done ? duration : 1e9)
    }
}
