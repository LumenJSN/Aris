//
//  ArisOnboardingGuide+Setup.swift
//  Aris
//
//  The setup window's beats (mockups/onboarding2/js/setup.js, narrate.js, main.js finish; the owner's picks of 2026-11-11):
//  the window opens on the first page this person has something to do on (ArisSetupPlan), each page is narrated by the
//  notch in one line (AI 고르기 and 아리스라고 부르기 are Aris's own, fresh install F2 and F4), the permission cards ask
//  macOS for real (ArisOnboardingSystem: the mic's and speech recognition's own dialogs; System Settings with the drag
//  panel for Accessibility and Screen Recording) with the check's sound when one turns on, the try page moves on once
//  its request was really done, and the finish closes the window and hands the notch back, open, with three things to
//  try (ArisFirstTries).
//

import AppKit
import Defaults
import SwiftUI

extension ArisOnboardingGuide {
    func openSetup(page wanted: ArisSetupPage, handingOff: Bool) {
        let actions = ArisOnboardingSystem.live
        makePlan(actions)
        let page = plan.opening(at: wanted)
        watchBrains()
        let model = ArisOnboardingModel(actions: actions, page: page)
        model.onGranted = { [weak self] card in
            // The check grows from +50 ms; its sound on contact.
            self?.audio?.cue(.check, at: Self.now() + 0.05, align: .hit)
            // Back in front: at once after macOS's own prompt, once the drag panel has shown its check after System Settings.
            self?.after(card.way == .settings ? 1.2 : 0) { $0.comeForward(after: .granted) }
            // Screen Recording just turned on: macOS's second question comes now, once the setup is in front again.
            self?.takeFirstCaptureSoon(after: card.way == .settings ? 1.6 : 0.4)
        }
        model.onFirstCapture = { [weak self] outcome in self?.firstCaptureEnded(outcome) }
        model.onAsked = { [weak self] _, prompted in
            // One refused before opens its System Settings list instead of a prompt: that stays in front.
            if prompted { self?.comeForward(after: .promptAnswered) } else { self?.comeForward(after: .settingsOpened) }
        }
        model.begin()
        model.start()
        self.model = model
        self.page = page
        if phase == .closed || !handingOff { phase = .setup }
        if !docked {
            morph = ArisNotchMorph(restForm)
            docked = true
        }
        // Sized to the display that shows it: whole inside its visible frame, centred (a 1024 × 768 display included).
        let screen = hostScreen ?? NSScreen.main ?? NSScreen.screens.first
        if let visible = screen?.visibleFrame { fit = ArisOnboardingStage.fit(in: visible) }
        let window = ArisOnboardingSetupWindow(guide: self, fit: fit, placed: screen != nil)
        self.window = window
        // An app of its own before it comes forward, so macOS takes Aris for the app in front (VM bug 5).
        applyPolicy()
        let front = ArisOnboardingFront.front(after: .opened(quiet: quiet, reopened: reopened), phase: phase)
        if front == .guide { claimFront() }
        window.present(handingOff: handingOff, reduced: reduced, activate: front == .guide)
        if handingOff {
            after(reduced ? 0.3 : 0.92) { guide in
                guide.window?.level = NSWindow.Level(rawValue: ArisOnboardingStage.windowLevel(handingOff: false))
                guide.phase = .setup
                guide.applyNotch()
            }
        }
        applyNotch()
        narrate(for: page)
        save(page)
        // Back from Quit & Reopen with Screen Recording on: macOS's second question comes here, on this page.
        takeFirstCaptureSoon(after: handingOff ? 1.4 : 0.8)
    }

    private func save(_ page: ArisSetupPage) { UserDefaults.standard.set(page.rawValue, forKey: ArisOnboarding.pageKey) }

    /// The pages this person will see, decided as the window opens: the rail's steps are these (ArisSetupPlan).
    private func makePlan(_ actions: ArisOnboardingModel.Actions) {
        let cardsOn = ArisPermissionCard.allCases.allSatisfy { card in card.steps.allSatisfy { actions.grant($0) == .granted } }
        plan = ArisSetupPlan.make(permissionsSettled: cardsOn && actions.captureAllowed() && ArisPrerequisites.current().isEmpty,
                                  readyAIs: ArisSetupPlan.readyCount(ArisBrainSetup.shared.ready))
    }

    /// The displays changed (a resolution, a monitor plugged in or out, the Dock): the window is fitted again to the
    /// display it is on.
    func refitWindow() {
        guard let window, let visible = (window.screen ?? hostScreen ?? NSScreen.main)?.visibleFrame else { return }
        let next = ArisOnboardingStage.fit(in: visible)
        guard next != fit else { return }
        fit = next
        window.apply(next)
    }

    // MARK: - Pages

    func next() {
        guard let model else { return }
        let left = model.flow.page
        if model.next(skipping: plan.skipped) {
            // The practice's answer does not lie over the next page's heading: it is put away and the notch closes.
            if ArisPracticeLeftovers.putsAwayAnswer(leaving: left, for: model.flow.page) {
                ArisController.shared.clearPracticeLeftovers(timer: nil)
                notchModel?.close()
            }
            show(model.flow.page)
        } else {
            finish()
        }
    }

    func back() {
        guard let model, model.flow.backShown else { return }
        model.back(skipping: plan.skipped)
        // Back on the practice page it can be tried again: the field is there, not the page's done state.
        if ArisPracticeLeftovers.startsOver(returningTo: model.flow.page) {
            clocks.cancel(name: "try")
            askAnswered = false
            tryOutcome = nil
        }
        show(model.flow.page)
    }

    /// Which AIs are set up is asked now and followed while the window is open: the AI page is in the plan or out of
    /// it by what the helper says, for as long as that page is still ahead (ArisSetupPlan.learning).
    private func watchBrains() {
        brainWatch = ArisBrainSetup.shared.$ready.sink { [weak self] ready in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.learn(ready) } }
        }
        Task { await ArisBrainSetup.shared.refresh() }
    }

    private func learn(_ ready: [ArisBrain: Bool]?) {
        guard phase == .setup || phase == .handoff else { return }
        let learned = plan.learning(readyAIs: ArisSetupPlan.readyCount(ready), at: page)
        if learned != plan { plan = learned }
    }

    private func show(_ page: ArisSetupPage) {
        clocks.cancel(name: "try")
        withAnimation(reduced ? ArisOBCurve.fade : ArisOBCurve.card) { self.page = page }
        save(page)
        narrate(for: page)
        if page == .permissions { takeFirstCaptureSoon(after: 0.4) }
        // One more look before the page after this one is chosen (the AI page is left out when one AI is set up).
        if page == .ask { Task { await ArisBrainSetup.shared.refresh() } }
    }

    // MARK: - 눌러서 말하기

    /// A practice turn ended (ArisController+Practice). The request really done: 계속 shows, the rail fills this page's
    /// share, and the page moves on by itself a moment later. Anything else: the page says to try the line as it is.
    func tryEnded(_ outcome: ArisSetupTry.Outcome?) {
        guard phase == .setup, page == .ask, let outcome else { return }
        tryOutcome = outcome
        guard outcome == .done, !askAnswered else { return }
        withAnimation(reduced ? ArisOBCurve.fade : ArisOBCurve.card) { askAnswered = true }
        after(ArisSetupTry.advanceAfter, name: "try") { guide in
            guard guide.phase == .setup, guide.page == .ask else { return }
            guide.next()
        }
    }

    func narration(for page: ArisSetupPage) -> String {
        let keys = talkKeysText
        switch page {
        case .permissions: return ArisOnboardingCopy.permsNarration(name: ArisUserName.current)
        case .ask: return ArisSetupWords.tryNarration(keys)
        case .brain: return ArisOnboardingCopy.brainNarration
        case .wake: return ArisOnboardingCopy.wakeNarration
        case .dictation: return ArisOnboardingCopy.dictateNarration
        }
    }

    /// The talk shortcut as text ("⌥ Space").
    var talkKeysText: String { (model?.actions.talkKeys() ?? ArisOnboardingSystem.talkKeys()).joined(separator: " ") }

    /// The notch voices the page in one line (lit word by word), then folds back to rest; not while the real notch
    /// is in use.
    private func narrate(for page: ArisSetupPage) {
        guard notchModel != nil, !realHolds else { return }
        let now = Self.now()
        let text = narration(for: page), line = ArisNarration(text: text, start: now, reduced: reduced)
        narration = line
        morph.go(to: messageForm(for: text), at: now, reduced: reduced)
        after(line.foldAt - now, name: "narrate") { guide in
            guide.morph.go(to: guide.restForm, at: Self.now(), reduced: guide.reduced)
            guide.after(0.3, name: "narrate") { $0.narration = nil }
        }
    }

    // MARK: - 아리스라고 부르기

    /// The wake word page's answer: stored as the user's own choice (a new install starts with it off), then on.
    func chooseWakeWord(_ on: Bool) {
        Defaults[.arisWakeWord] = on
        next()
    }

    // MARK: - Permission cards

    func allow(_ card: ArisPermissionCard) {
        if card.way == .settings { openedDragPanel = true }
        sendingToSettings(for: card)
        starWorking = true
        model?.allow(card)
    }

    func later(_ card: ArisPermissionCard) {
        model?.later(card)
        starWorking = false
    }

    // MARK: - The finish

    /// 시작 안내로 돌아가기 during the finish beat (N11): the beat stops, the three things to try go, and the setup
    /// window comes back on its last page.
    func reopenSetup() {
        guard phase == .finish else { return }
        clocks.cancelAll()
        ArisFirstTries.shared.cancel()
        window?.orderOut(nil)
        window?.close()
        window = nil
        morph.go(to: restForm, at: Self.now(), reduced: reduced)
        audio?.ambient(true, fade: 1)
        openSetup(page: page, handingOff: false)
    }

    /// 마치기: the window leaves quickly (ArisOnboardingStage.windowOut) and the guide lets go of the notch; then the
    /// real notch opens with three things to try and the left side notch shows itself once (the owner's pick 5-A,
    /// ArisFirstTries), on the resolve's sound; the bed fades under it and the guide is over.
    func finish() {
        guard phase == .setup || phase == .handoff else { return }
        phase = .finish
        // The practice belongs to the setup: its timer, if still running, is cancelled without a word, and what it
        // left in the notch is put away, so the line and the three things to try have the notch (ArisPracticeLeftovers).
        ArisController.shared.clearPracticeLeftovers(timer: practiceTimer)
        practiceTimer = nil
        audio?.stopVoice()
        clocks.cancel(name: "narrate")
        clocks.cancel(name: "try")
        narration = nil
        starWorking = false
        model?.stop()
        if openedDragPanel { ArisPermissionGuide.shared.close() }
        // System Settings, if it is only there because the setup opened it, goes as the window fades, so what is in
        // front afterwards is what the user had (VM run 2026-11-11, bug 5).
        stepBackFromSettings()
        // From here the notch is the real one's (ArisOnboardingStage.ownsNotch).
        applyNotch()
        window?.dismiss(reduced: reduced)
        after((reduced ? ArisOnboardingStage.windowOutReduced : ArisOnboardingStage.windowOut) + ArisOnboardingStage.notchAfterWindow) { guide in
            guide.window?.orderOut(nil)
            guide.window?.close()
            guide.window = nil
            guide.handBack()
            guide.applyPolicy()
            guide.audio?.ambient(false, fade: ArisOnboardingStage.bedFade)
            guide.audio?.cue(.resolve, at: Self.now() + 0.02, align: .hit)
            ArisFirstTries.shared.begin(on: guide.notch(), noAI: ArisBrainSetup.shared.noneReady, name: ArisUserName.current, reduced: guide.reduced)
            guide.after(ArisOnboardingStage.bedFade + 0.1) { $0.close(.finished) }
        }
    }
}
