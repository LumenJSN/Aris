//
//  ArisContinuity.swift
//  Shared/Core (Aris, tests)
//
//  When the next turn carries the conversation on and when it starts a new one, in one place. A follow-up within the
//  대화 이어가기 setting (5 minutes by default) of the last answer carries on: the same brain thread in the warm process,
//  the recent turns and the conversation's marks (screen seen, outside text). That holds whatever ended the
//  always-on listening in between (30 s of silence, "됐어", Esc, the talk key, the notch closing): those stop the
//  microphone, not the conversation. A new conversation starts only
//  - after a long gap: more than the setting since the last answer;
//  - when the user puts the answer away themselves (닫기), picks a past entry in 기록, ends practice, or gives a file by
//    dropping it (each calls endConversation directly);
//  - on the first turn, or when the last fresh start never reached the helper.
//  A topic change is the user's to make with 닫기: nothing guesses it from their words. Foundation only.
//

import Foundation

enum ArisContinuity {
    /// Why the next turn starts fresh (nil: it carries on).
    enum Fresh: String, Equatable {
        case longGap = "long gap"
    }

    /// The setting's minutes as seconds (0 or less: every turn starts fresh).
    static func window(minutes: Int) -> Double { Double(max(0, minutes)) * 60 }

    /// Decided as a turn starts, from the seconds since the last answer finished (nil: no answer yet in this
    /// conversation, or one picked up from 기록, which starts its own count).
    static func startsFresh(secondsSinceLastAnswer: Double?, windowMinutes: Int) -> Fresh? {
        guard let gap = secondsSinceLastAnswer else { return nil }
        return gap > window(minutes: windowMinutes) ? .longGap : nil
    }
}
