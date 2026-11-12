//
//  ArisOnboardingGuide+Intro.swift
//  Aris
//
//  The beats on the veil (mockups/onboarding2/js/main.js): the intro's score with its sound cues on the same clock
//  (the swell from the first frame, the chime on the lock), the flight into the notch (anticipation, the whoosh at its
//  fastest, the notch opening at 520 ms, the landing pop at 1 s), the talk (the greeting, the name, the greeting by
//  name), and the handoff to the setup window (the veil lifts in 0.8 s while the window settles in 920 ms).
//

import AppKit
import SwiftUI

extension ArisOnboardingGuide {
    typealias Score = ArisOnboardingScore

    /// The wordmark's measured size: "Aris" in SF Pro Display 76 semibold, −.045 em.
    static var wordSize: CGSize {
        let font = NSFont.systemFont(ofSize: 76, weight: .semibold)
        let size = ("Aris" as NSString).size(withAttributes: [.font: font, .kern: -0.045 * 76])
        return CGSize(width: ceil(size.width), height: 76)
    }

    var layout: Score.Layout { Score.layout(screen: screenSize, word: Self.wordSize) }

    /// Story time (ms) now.
    func storyMs(_ now: Double) -> Double { (now - t0) * 1000 }

    func startIntro() {
        t0 = Self.now() + 0.12
        morph = ArisNotchMorph(.hardware(closed: CGSize(width: closedSize.width, height: bandHeight), hasNotch: hasNotch))
        applyNotch()
        audio?.cue(.swell, at: t0, align: .start)
        audio?.cue(.chime, at: t0 + (reduced ? 0.4 : Score.lock / 1000), align: .hit)
        audio?.ambient(true, fade: 3)
    }

    /// 시작하기.
    func startTapped() { startFlight(next: ArisOnboardingStage.ctaTarget) }

    /// 건너뛰기: in the intro the star still flies, then the window; later, straight to the window.
    func skipTapped() {
        if phase == .intro { startFlight(next: ArisOnboardingStage.skipTarget(phase: phase)) } else { toWindow() }
    }

    private func startFlight(next: ArisOnboardingStage.Next) {
        guard phase == .intro else { return }
        let now = Self.now(), tc = storyMs(now)
        let frame = Score.frame(at: tc, layout: layout, reduced: reduced)
        let from = CGPoint(x: frame.hero.x, y: frame.hero.y)
        flight = ArisOnboardingFlight(start: now, tc: tc, from: from, to: notchSlot(talkForm), next: next)
        phase = .flight
        applyOverlay()
        let times = Score.flightTimes
        if reduced {
            audio?.cue(.pop, at: now + 0.3, align: .hit, length: 0.35, fade: 0.12)
            morph.go(to: talkForm, at: now, reduced: true)
            after(0.25) { $0.docked = true }
        } else {
            audio?.cue(.whoosh, at: now + times.whoosh / 1000, align: .peak)
            audio?.cue(.pop, at: now + times.land / 1000, align: .hit, length: 0.35, fade: 0.12)
            after(times.notch / 1000) { guide in guide.morph.go(to: guide.talkForm, at: Self.now(), reduced: false) }
            after(times.land / 1000) { guide in
                let landed = Self.now()
                guide.morph.kick(at: landed, amp: 8)
                guide.popAt = landed
                guide.docked = true
            }
        }
        after(reduced ? 0.6 : times.voice / 1000) { guide in
            guard guide.phase == .flight else { return }
            if next == .talk { guide.converse() } else { guide.toWindow() }
        }
    }

    // MARK: - The talk

    private func converse() {
        phase = .talk
        say("greet", ArisOnboardingCopy.greet) { guide in
            // The composer opens 180 ms after the voice completes.
            guide.after(0.18) { guide in guide.composerAt = Self.now() }
        }
    }

    /// Speaks a voice line with its captions; `done` once the voice has finished.
    func say(_ clip: String, _ sentences: [String], done: @escaping @MainActor (ArisOnboardingGuide) -> Void) {
        captionsClearAt = nil
        guard let audio else { return }
        let line = audio.say(clip, language: ArisOnboardingCopy.language, sentences: sentences) { [weak self] end in
            guard let self, self.showing else { return }
            self.spoken?.done = true
            self.spoken?.duration = end - (self.spoken?.start ?? end)
            done(self)
        }
        spoken = ArisOnboardingSpoken(sentences: sentences, start: line.start, starts: line.starts, duration: line.duration, synthesized: line.synthesized)
    }

    /// The name's send button (or Return).
    func submitName() {
        guard phase == .talk, !nameSent else { return }
        let name = ArisCaptions.cleanName(nameText)
        guard !name.isEmpty else { nameError = true; return }
        nameText = name
        nameError = false
        nameSent = true
        ArisUserName.set(name)
        after(0.32) { guide in
            guide.captionsClearAt = Self.now()
            guide.after(guide.reduced ? 0.12 : 0.24) { guide in
                guide.composerAt = nil
                guide.say("greet-name", ArisOnboardingCopy.greetName) { guide in
                    guide.after(guide.reduced ? 0 : 0.4) { $0.toWindow() }
                }
            }
        }
    }

    // MARK: - The handoff

    /// The veil lifts (0.8 s) while the setup window settles in (920 ms); the window rides over the veil meanwhile.
    func toWindow() {
        guard [.intro, .flight, .talk].contains(phase) else { return }
        audio?.stopVoice()
        captionsClearAt = Self.now()
        phase = .handoff
        applyOverlay()
        after(reduced ? 0.12 : 0.24) { guide in
            guide.spoken = nil
            guide.composerAt = nil
            guide.lift = (Self.now(), guide.reduced ? 0.3 : 0.8)
            guide.morph.go(to: guide.restForm, at: Self.now(), reduced: guide.reduced)
            guide.docked = true
            guide.openSetup(page: .permissions, handingOff: true)
            guide.after(guide.reduced ? 0.3 : 0.8) { guide in
                guide.overlay?.orderOut(nil)
                guide.overlay?.close()
                guide.overlay = nil
                guide.lift = nil
            }
        }
    }

    // MARK: - The veil's value

    /// The veil's opacity now: the score's in the intro, full in the flight and the talk, lifting at the handoff.
    func veil(at now: Double) -> Double {
        switch phase {
        case .intro: return Score.frame(at: storyMs(now), layout: layout, reduced: reduced).veil
        case .flight, .talk: return 1
        case .handoff:
            guard let lift else { return 1 }
            return 1 - ArisOnboardingMotion.veilLift(ArisOnboardingMotion.span(now, lift.start, lift.start + lift.seconds))
        default: return 0
        }
    }
}

extension ArisController {
    /// Aris's microphone is listening (a turn or a dictation): the onboarding is silent then.
    var micListening: Bool { session.phase == .listening || dictation == .listening }
}
