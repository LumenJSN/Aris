//
//  ArisController+Countdown.swift
//  Aris
//
//  A message you dictated isn't asked about: Aris says it ("엄마한테 ‘곧 갈게’ 보낼게요"), the ring beside the confirm
//  card's 보내기 empties over three seconds (ArisCountdown), and it goes unless you say "취소" or press esc or 취소 (a yes,
//  ↩ or 보내기 sends at once). Then the card settles into one line: on its way ("보내는 중…"), or not sent. The card
//  never says "보냈어요": the countdown's end only hands the yes to the agent, whose aris-tools then answers `sent to …`,
//  `NOT SENT: …` or `NOT CONFIRMED: …`, and that outcome is told in the turn's answer. The agent decides when the
//  countdown applies (ArisRiskPolicy+Dictation); anything else is still asked.
//

import Foundation
import SwiftUI
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "turn")

extension ArisController {
    /// Nil when the card's turn ended before the message went or was stopped: never a send, never a no.
    func countdownSend(_ ask: ArisConfirmation) async -> Bool? {
        log.notice("sending after a countdown: \(ask.title, privacy: .private) “\(ask.detail, privacy: .private)”")
        // A turn that is over sends nothing and shows no card.
        guard turnIsCurrent else { return nil }
        // The card's wait is the kernel's (ArisController+Tasks): ↩, 보내기, esc or 취소 resume it at once.
        let key = kernel.showCard(ask.id, turn: ArisTurnScope.current)
        ArisCountdownMic.shared.listening = true
        defer {
            kernel.closeCard(key)
            countdownStarted = nil
            ArisCountdownMic.shared.listening = true
        }
        setSession(session.asking(ask))
        // Its click hold starts now (ArisCardHold): a click on 보내기 a moment after it came up is no yes.
        ArisCardStill.shared.shown(ask.id)
        // Said in the request's language, as the card is drawn (ArisCardEnglish).
        let english = ArisCardEnglish.isEnglish(request: session.heard)
        await speak { await self.speaker.speak(ask.spoken ?? (english ? "Sending it." : "보낼게요")) }
        if let early = kernel.takeOutcome(key) { return await counted(ArisCountdownStep(early), ask, key: key) }
        guard !Task.isCancelled, turnIsCurrent else { return nil }
        let listener = ArisListener()
        // A spoken no counts at once; a yes once its words held still (a streaming "보내" can still become "보내지 마").
        var heard = ArisSpokenAnswer()
        listener.onText = { heard = heard.heard($0, at: Self.uptime) }
        listener.onLevel = { [weak self] in self?.level = $0 }
        do {
            let source = detector, from = detector?.currentSample
            try await Self.within(Self.startTimeout) { try await listener.start(locale: Self.locale, source: source, from: from) }
        } catch {
            // Without a microphone "취소" can't be heard: nothing goes blind. The same card stays up, its ring still and
            // its hint asking for a press (VM run 2026-11-19, D7: a second card with other words came up in its place).
            log.error("countdown: couldn't listen, the card waits for a press: \(String(describing: error), privacy: .public)")
            // A start that timed out may still be opening the microphone: it closes as soon as it has, and the
            // detector's audio is let go (audit voice-12: nothing closed it, and the microphone could stay open).
            Task { _ = await listener.stop() }
            level = 0
            ArisCountdownMic.shared.listening = false
            return await pausedCountdown(ask, key: key)
        }
        countdownStarted = Date()
        let deadline = ContinuousClock.now + .seconds(ArisConfirmReply.countdownSeconds)
        var outcome: ArisCardOutcome?
        var paused = false
        while ContinuousClock.now < deadline, heard.answer(at: Self.uptime, voiceYes: true) == nil {
            // "잠깐만", "wait": words that are no clear yes or no stop the ring at once (ArisConfirmReply.countdownPauses).
            if ArisConfirmReply.countdownPauses(heard.text, heldFor: Self.uptime - heard.since) {
                paused = true
                break
            }
            outcome = await kernel.waitForCard(key, atMost: .milliseconds(100))
            if outcome != nil { break }
        }
        // One decision for every way the ring stopped (ArisCountdownStep), asked before the microphone closes and after.
        let said = heard.answer(at: Self.uptime, voiceYes: true)
        let soon = ArisCountdownStep.decide(outcome: outcome, said: said, paused: paused, final: nil, current: !Task.isCancelled && turnIsCurrent)
        // Stopped or sent by hand or voice: the card says so now, not once the microphone has closed.
        if let sent = soon?.sent { _ = ended(sent) }
        let final = (try? await Self.within(Self.stopTimeout, cancelsWork: false) { await listener.stop() }) ?? heard.text
        level = 0
        // Sent only on silence until the ring ran out, or a clear yes; a clear no stops it; anything else pauses it.
        let step = soon ?? ArisCountdownStep.decide(outcome: outcome, said: said, paused: paused, final: ArisConfirmReply.countdownWords(final),
                                                    current: !Task.isCancelled && turnIsCurrent) ?? .turnEnded
        log.notice("countdown: \(step.logLine, privacy: .public) (heard “\(final, privacy: .private)”)")
        return await counted(step, ask, key: key)
    }

    /// What the countdown's step comes to: true sent, false not sent, nil its turn ended (nothing follows).
    private func counted(_ step: ArisCountdownStep, _ ask: ArisConfirmation, key: ArisCardKey) async -> Bool? {
        switch step {
        case .send: return ended(true)
        case .stop: return ended(false)
        case .pause: return await pausedCountdown(ask, key: key)
        case .covered:
            cardUnanswered = true
            return false
        case .turnEnded: return nil
        }
    }

    /// Words that were no clear yes or no: the ring stops and the card stays up for ↩, 보내기, esc, 취소, Y or N, up to a
    /// card's limit. Nothing goes by itself: with no answer it is not sent, and the turn says nobody answered.
    private func pausedCountdown(_ ask: ArisConfirmation, key: ArisCardKey) async -> Bool? {
        countdownStarted = nil
        let longest = ContinuousClock.now + .seconds(ArisCardTiming.longestWait)
        while ContinuousClock.now < longest, ArisCardCover.isUp(card: ask.id, shown: session.question?.id) {
            if let outcome = await kernel.waitForCard(key, atMost: .milliseconds(200)) { return await counted(ArisCountdownStep(outcome), ask, key: key) }
        }
        guard !Task.isCancelled, turnIsCurrent else { return nil }
        cardUnanswered = true
        return ended(false, unanswered: true)
    }

    /// The card settles into its one line (on its way, or not sent), with one eased resize of the notch.
    private func ended(_ sent: Bool, unanswered: Bool = false) -> Bool {
        withAnimation(ArisGlass.resize) { setSession(session.counted(sent: sent, unanswered: unanswered)) }
        return sent
    }
}
