//
//  ArisSetupTry.swift
//  Aris
//
//  The setup's 눌러서 말하기 page as rules (the owner's picks 1-A and 4-A, qa/design-1111/PICKS.md): the shortcut's practice
//  and the first request are one page. Holding the talk key lights its keycaps and listens; the request on the page is
//  "3분 타이머 맞춰 줘" / "Set a 3 minute timer", which the app does itself (no AI) and which leaves a running timer
//  in the notch. The page is done when that really happened: the practice turn (ArisOnboardingPractice) set a timer
//  that is running, or answered the time, the date or the calendar; a line that only says the practice does nothing
//  else is not an answer. When Aris can't hear (this Mac has no microphone, the microphone card was put off, or a
//  start failed) the page says so in the sentence the notch uses and offers the same request typed. Pure, so the tests
//  run every case; ArisTryPage draws it and ArisController+Practice reports how each turn ended.
//

import Foundation

enum ArisSetupTry {
    /// The request the page shows, lit word by word as it is heard, and typed in advance where typing is offered.
    static func line(english: Bool) -> String { english ? "Set a 3 minute timer" : "3분 타이머 맞춰 줘" }

    // MARK: - Whether Aris can hear

    enum Hearing: Equatable {
        case can
        /// This Mac has no audio input at all.
        case noMicrophone
        /// The microphone card (the microphone and speech recognition) is not on.
        case notAllowed
        /// The last press could not start listening: the notch's own sentence about it.
        case failed(String)
    }

    /// No microphone comes first (allowing one that isn't there changes nothing), then the permission, then what the
    /// last start said.
    static func hearing(micGranted: Bool, hasMicrophone: Bool, lastFailure: String?) -> Hearing {
        if !hasMicrophone { return .noMicrophone }
        if !micGranted { return .notAllowed }
        if let lastFailure { return .failed(lastFailure) }
        return .can
    }

    /// The request can be typed on the page whenever it can't simply be said.
    static func typedOffered(_ hearing: Hearing) -> Bool { hearing != .can }

    /// What the page says under the keys when Aris can't hear: with no microphone the line every other place uses
    /// (ArisListenStart), then that typing works.
    static func sentence(_ hearing: Hearing, english: Bool) -> String? {
        switch hearing {
        case .can: nil
        case .noMicrophone: ArisListenStart.line(.noMicrophone, english: english) + " " + ArisSetupWords.tryTypeInstead(english: english)
        case .notAllowed: ArisSetupWords.tryNotAllowed(english: english)
        case .failed(let said): said + " " + ArisSetupWords.tryTypeInstead(english: english)
        }
    }

    /// What a turn that failed to start leaves on the page: the notch's sentence. Nil when nothing failed, and for the
    /// line that only says the microphone has just been allowed ("Ready. Press ⌥Space and talk."): that is good news.
    static func failure(failed: Bool, reply: String) -> String? {
        guard failed, !reply.isEmpty else { return nil }
        if reply == ArisPermissionWords.ready(english: true) || reply == ArisPermissionWords.ready(english: false) { return nil }
        return reply
    }

    // MARK: - How a practice turn ended

    enum Outcome: Equatable {
        /// The request was done: a timer is running, or the time, the date or the calendar was answered.
        case done
        /// Something else was said: the practice did nothing with it.
        case notUnderstood
    }

    /// `timerRunning`: a timer exists now, read after the turn acted. A timer request counts only when a timer really
    /// runs afterwards; one that left none (a timer stopped) is neither an answer nor a miss.
    static func outcome(of question: ArisOnboardingPractice.Question, timerRunning: Bool) -> Outcome? {
        switch question {
        case .timer: timerRunning ? .done : nil
        case .time, .date, .calendar: .done
        case .other: .notUnderstood
        }
    }

    /// How long the page stays on "that's it" before it moves on by itself (계속 is there meanwhile).
    static let advanceAfter: TimeInterval = 1.8

    // MARK: - What the page draws

    enum Button: Equatable {
        /// Press and hold: the same as holding the talk key.
        case hold
        /// Sends what is typed.
        case send
        /// 계속.
        case next
    }

    static func button(done: Bool, hearing: Hearing) -> Button { done ? .next : typedOffered(hearing) ? .send : .hold }

    /// How many of the line's words are lit: all once it is done, else as many as have been heard while listening.
    static func lit(words: Int, heard: String, listening: Bool, done: Bool) -> Int {
        if done { return words }
        guard listening else { return 0 }
        return min(words, heard.split(whereSeparator: \.isWhitespace).count)
    }

    enum Note: Equatable {
        /// Before anything: what letting go does.
        case hold
        /// 아니요, 키를 바꿀게요 was pressed: where to change it.
        case changed
        /// A turn ended with nothing done.
        case again
        case done
    }

    static func note(done: Bool, lastOutcome: Outcome?, changedKey: Bool, hearing: Hearing) -> Note? {
        if done { return .done }
        if lastOutcome == .notUnderstood { return .again }
        if changedKey { return .changed }
        return typedOffered(hearing) ? nil : .hold
    }
}

// MARK: - The page's words

extension ArisSetupWords {
    /// `keys`: the talk shortcut as it is set ("⌥ Space").
    static func tryTitle(_ keys: String, english: Bool = english) -> String { say("\(keys)를 누른 채 말해 보세요", "Hold \(keys) and say it", english) }
    static func tryNarration(_ keys: String, english: Bool = english) -> String { say("\(keys)를 누른 채 말해 보세요.", "Hold \(keys) and talk to me.", english) }
    static func tryHow(english: Bool = english) -> String {
        say("누르는 동안 키가 파랗게 켜지고 제가 들어요. 이렇게 말해 보세요.", "The keys light up blue while you hold them, and I listen. Try saying:", english)
    }
    static func tryHoldNote(english: Bool = english) -> String { say("손을 떼면 답해요.", "Let go, and I answer.", english) }
    static func tryDone(english: Bool = english) -> String { say("됐어요. 이렇게 부르면 돼요.", "That's it. That's how you call me.", english) }
    static func tryAgain(english: Bool = english) -> String {
        say("그건 설정을 마친 다음에 해 드릴게요. 지금은 위의 말을 그대로 해 보세요.", "I'll do that once setup is done. For now, try the line above as it is.", english)
    }
    static func tryNotAllowed(english: Bool = english) -> String {
        say("마이크를 허용하지 않아서 지금은 듣지 못해요. 글로 써서 보내도 돼요.", "The microphone isn't allowed, so I can't hear you yet. You can type it instead.", english)
    }
    static func tryTypeInstead(english: Bool = english) -> String { say("글로 써서 보내도 돼요.", "You can type it instead.", english) }
    static func trySend(english: Bool = english) -> String { say("보내기", "Send", english) }
    static func tryFieldLabel(english: Bool = english) -> String { say("Aris에게 보낼 말", "What to ask Aris", english) }
    static func tryNote(_ note: ArisSetupTry.Note, english: Bool = english) -> String {
        switch note {
        case .hold: tryHoldNote(english: english)
        case .changed: ArisOnboardingCopy.shortcutChanged
        case .again: tryAgain(english: english)
        case .done: tryDone(english: english)
        }
    }
}

/// What the setup's practice turn leaves behind, and what becomes of it (final check on a new Mac: the practice's
/// "Set a 3 minute timer" rang after the setup's Finish, and the notch showed "Timer / 3 minutes is up." where the
/// line and the three things to try belong). The practice belongs to the setup:
///  · when the setup finishes or is put off, the timer the practice set is cancelled without a word if it is still
///    that timer (one he paused, lengthened or set anew since is his own and stays);
///  · the reply the practice or its timer left in the notch is put away, unless Aris is listening, working or asking;
///  · when the page moves on from the practice, its answer is put away and the notch closes, so it does not lie over
///    the next page's heading; and coming back to the practice page gives a page that can be tried again.
enum ArisPracticeLeftovers {
    /// Whether the timer running now is cancelled: only the very timer the practice set.
    static func cancelsTimer(practice: ArisTimerState?, running: ArisTimerState?) -> Bool {
        guard let practice, let running else { return false }
        return practice == running
    }

    /// Whether the notch's reply is put away: never under a turn that is listening, working or asking on a card.
    static func clearsReply(listening: Bool, thinking: Bool, asking: Bool) -> Bool { !listening && !thinking && !asking }

    /// Whether the practice page is made fresh (its field back, no "done" state): when the setup comes back to it.
    static func startsOver(returningTo page: ArisSetupPage) -> Bool { page == .ask }

    /// Whether the notch is closed and the practice's answer put away as the setup shows `next`: on leaving the
    /// practice page forwards.
    static func putsAwayAnswer(leaving page: ArisSetupPage, for next: ArisSetupPage) -> Bool { page == .ask && next != .ask }
}

