//
//  ArisController+Practice.swift
//  Aris
//
//  The onboarding's 눌러서 말하기 turn, sandboxed (QA BUG-31): answered here (ArisOnboardingPractice). Nothing goes to the
//  router, a hand-off or an AI with tools, and the only thing done on the Mac is Aris's own timer (the owner's pick 1-A:
//  the first request sets one, with no AI); the calendar is only read. How the turn ended is told to the guide, whose
//  page moves on when the request was really done (ArisSetupTry).
//

import EventKit
import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "onboarding")

extension ArisController {
    /// What ⌥Space does now, by the onboarding's page.
    var onboardingTalk: ArisOnboardingTalk {
        ArisOnboardingTalk.mode(phase: ArisOnboardingGuide.shared.phase, page: ArisOnboardingGuide.shared.page)
    }

    func answerPractice(_ heard: String) async {
        let korean = ArisSpeech.language(of: heard) == "ko-KR"
        let question = ArisOnboardingPractice.question(heard)
        log.notice("practice turn: \(String(describing: question), privacy: .public)")
        understood(heard, path: "practice", tier: .quick)
        let reply: String
        switch question {
        // The timer is set for real, by the same code a turn outside the setup runs, and said from what happened.
        case .timer(let intent): reply = await doOnMac(intent, korean: korean) ?? ArisOnboardingPractice.answersOnly(korean: korean)
        case .time: reply = ArisIntent.tellTime.acknowledgement(korean: korean) ?? ""
        case .date: reply = ArisIntent.tellDate.acknowledgement(korean: korean) ?? ""
        case .calendar(let day, let part): reply = await practiceAgenda(day: day, part: part, korean: korean)
        case .other: reply = ArisOnboardingPractice.answersOnly(korean: korean)
        }
        guard !Task.isCancelled else { return }
        // The timer it set is the setup's own: it goes with the setup (ArisPracticeLeftovers).
        if case .timer = question { ArisOnboardingGuide.shared.practiceTimer = ArisTimerModel.shared.state }
        session = session.answering(reply)
        // The page is done only by what really happened: a timer that is running now, or an answer.
        ArisOnboardingGuide.shared.tryEnded(ArisSetupTry.outcome(of: question, timerRunning: ArisTimerModel.shared.isRunning))
        stats?.firstSound(at: .now)
        recordTurn(heard: heard, reply: reply)
        await speak { await self.speaker.speak(reply) }
        guard !Task.isCancelled else { return }
        lastTurnAt = .now
        finishTurn("ok")
        try? await Task.sleep(for: Self.lingerAfterAnswer)
        guard !Task.isCancelled else { return }
        session = session.done()
        resumeMusicIfPaused()
    }

    /// The setup finished or was put off (`timer`: the one its practice set), or its page moved on from the practice
    /// (`timer` nil: the timer stays, only the answer goes): what the practice left in the notch is put away
    /// (ArisPracticeLeftovers). A turn that is listening, working or asking is never touched.
    func clearPracticeLeftovers(timer practice: ArisTimerState?) {
        if ArisPracticeLeftovers.cancelsTimer(practice: practice, running: ArisTimerModel.shared.state) {
            log.notice("the setup's practice timer goes with the setup")
            ArisTimerModel.shared.cancel()
        }
        guard ArisPracticeLeftovers.clearsReply(listening: session.phase == .listening, thinking: session.phase == .thinking, asking: session.question != nil) else { return }
        turn?.cancel()
        speaker.stop()
        dropPendingAnswer()
        announcing = nil
        endConversation()
        session = ArisSession()
    }

    /// The calendar for that part of the day, read through EventKit (never asks for access, never changes anything).
    private func practiceAgenda(day: Int, part: ArisOnboardingPractice.Part, korean: Bool) async -> String {
        let store = ArisCalendarStore.shared
        await store.loadIfAuthorized()
        guard store.access == .fullAccess else { return ArisOnboardingPractice.noCalendar(korean: korean) }
        let window = ArisOnboardingPractice.window(day: day, part: part, now: Date())
        let events = await store.events(from: window.start, to: window.end)
            .map { ArisOnboardingPractice.Event(title: $0.title, start: $0.start, isAllDay: $0.isAllDay) }
        return ArisOnboardingPractice.agenda(events, day: day, part: part, korean: korean)
    }
}
