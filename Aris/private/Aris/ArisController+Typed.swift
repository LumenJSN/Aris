//
//  ArisController+Typed.swift
//  Aris
//
//  A request typed into the notch's input row: the same turn a spoken one gets, minus the microphone.
//

import Foundation

extension ArisController {
    /// `again`: the fix button asking the last request once more (ArisFixModel). It is asked as it was heard: a request
    /// heard hands-free stays hands-free, and never becomes his typed words by being repeated (auto L7).
    func submitTyped(_ text: String, again: Bool = false) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // "응, 지워" typed while a card is up answers that card (the user at the keyboard, as a click or Y), never a new turn
        // (QA BUG-40).
        if let yes = ArisCardWait.typedAnswer(text, cardUp: session.question != nil) {
            return answerQuestion(yes, source: .typed)
        }
        guard session.phase != .listening, session.phase != .thinking else { return }
        // The same quiet that ends a spoken conversation ends a typed one (startListening's rule), so a typed session
        // starts afresh too.
        if let lastTurnAt, ContinuousClock.now - lastTurnAt > Self.conversationLasts { endConversation() }
        let overAnswer = notchShowsAnswerNow() // before anything changes what the notch shows
        turn?.cancel()
        // The cancelled turn's last streamed piece must not land in this one.
        dropPendingAnswer()
        speaker.stop()
        stats = ArisTurnStats(startedAt: .now)
        turnHandsFree = again && turnHandsFree
        // Files given to Aris are what "이거" means: no screenshot (BUG-23).
        if ArisPendingFiles.carriesFiles(text) { seeEnded() } else { seeTyped(notchShowsAnswer: overAnswer) }
        session = ArisSession().listening().hearing(text).thinking()
        guard session.phase == .thinking else { return seeEnded() }
        let heard = session.heard
        // On the onboarding's 물어보기 a typed turn is a practice turn too, and anywhere else never one (QA follow-up).
        practiceTurn = onboardingTalk == .practice
        turn = Task { await answer(heard, typed: true) }
    }
}
