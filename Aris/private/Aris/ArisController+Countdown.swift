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
    func countdownSend(_ ask: ArisConfirmation) async -> Bool {
        log.notice("sending after a countdown: \(ask.title, privacy: .private) “\(ask.detail, privacy: .private)”")
        typedAnswer = nil
        defer {
            typedAnswer = nil
            countdownStarted = nil
        }
        session = session.asking(ask)
        // A click on 보내기 counts only once the card has been still for a moment (ArisCardHold).
        ArisCardStill.shared.shown(ask.id)
        // The agent's own line when it sent one; else Aris's, in the language of the request this card answers.
        let english = ArisCardEnglish.isEnglish(request: session.heard)
        await speak { await self.speaker.speak(ask.spoken ?? (english ? "Sending it." : "보낼게요")) }
        if let typedAnswer { return ended(typedAnswer) }
        guard !Task.isCancelled else { return false }
        // No microphone before macOS 26: "취소" can't be heard, so the buttons ask (never a silent "not sent", QA BUG-54).
        guard #available(macOS 26.0, *) else {
            return await cardAnswer(ArisConfirmation(id: ask.id, title: "메시지 보내기", detail: "\(ask.title) \(ask.detail)"), handsFree: false, waiter: false)
        }
        let listener = ArisListener()
        var heard = ""
        listener.onText = { heard = $0 }
        listener.onLevel = { [weak self] in self?.level = $0 }
        do {
            let source = detector, from = detector?.currentSample
            try await Self.within(Self.startTimeout) { try await listener.start(locale: Self.locale, source: source, from: from) }
        } catch {
            // Without a microphone "취소" can't be heard: ask with the buttons instead of sending blind.
            log.error("countdown: couldn't listen, asking instead: \(String(describing: error), privacy: .public)")
            // A start that timed out may still be opening the microphone: it closes as soon as it has, and the
            // detector's audio is let go (audit voice-12: nothing closed it, and the microphone could stay open).
            Task { _ = await listener.stop() }
            level = 0
            return await cardAnswer(ArisConfirmation(id: ask.id, title: "메시지 보내기", detail: "\(ask.title) \(ask.detail)"), handsFree: false, waiter: false)
        }
        countdownStarted = Date()
        let deadline = ContinuousClock.now + .seconds(ArisConfirmReply.countdownSeconds)
        while ContinuousClock.now < deadline, !Task.isCancelled, ArisConfirmReply.countdown(typed: typedAnswer, heard: heard) == nil {
            try? await Task.sleep(for: .milliseconds(100))
        }
        // Stopped or sent by hand or voice: the card says so now, not once the microphone has closed.
        if !Task.isCancelled, let early = ArisConfirmReply.countdown(typed: typedAnswer, heard: heard) { _ = ended(early) }
        let final = (try? await Self.within(Self.stopTimeout, cancelsWork: false) { await listener.stop() }) ?? heard
        level = 0
        guard !Task.isCancelled else { return false }
        let outcome = ArisConfirmReply.countdown(typed: typedAnswer, heard: heard) ?? (ArisConfirmReply.parse(final) == false ? false : true)
        log.notice("countdown: \(outcome ? "let go, to be sent" : "stopped", privacy: .public) (heard “\(final, privacy: .private)”)")
        return ended(outcome)
    }

    /// The card's end state (stopped, or let go and on its way), on the size clock as the card's room changes.
    private func ended(_ sent: Bool) -> Bool {
        withAnimation(ArisGlass.resize) { session = session.counted(sent: sent) }
        return sent
    }
}
