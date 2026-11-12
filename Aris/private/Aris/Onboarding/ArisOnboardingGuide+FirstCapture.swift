//
//  ArisOnboardingGuide+FirstCapture.swift
//  Aris
//
//  Screen Recording's second question from macOS, taken in the setup (ArisFirstCapture decides; the model takes the
//  capture through ArisOnboardingSystem): when the guide starts it, and what it does once macOS has its answer.
//

import AppKit

extension ArisOnboardingGuide {
    /// The permissions page shows with Screen Recording on: the app's first real capture is taken now, so macOS's
    /// second question comes here (ArisFirstCapture). A moment later, so the setup window is in front first.
    func takeFirstCaptureSoon(after seconds: Double) {
        after(seconds, name: "firstCapture") { guide in
            guard guide.phase == .setup || guide.phase == .handoff, guide.model?.takeFirstCaptureIfDue() == true else { return }
            guide.starWorking = true
        }
    }

    /// macOS's second question is over: after a yes the setup window is in front again, as after the microphone's.
    func firstCaptureEnded(_ outcome: ArisFirstCapture.Outcome) {
        if model?.flow.waiting.isEmpty ?? true { starWorking = false }
        if ArisFirstCapture.comesForward(after: outcome) { comeForward(after: .promptAnswered) }
    }
}
