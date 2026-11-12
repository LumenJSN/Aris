//
//  ArisAgentCopy.swift
//  Aris
//
//  What the user reads when aris-agent can't be reached (never a script name), in the UI's language (ArisUIWords).
//  Shared by the agent client and by the places that explain a job lost with the agent (ArisJobLoss).
//

import Foundation

enum ArisAgentCopy {
    /// No helper on this Mac: said with what to do about it (ArisPrerequisites).
    static var notSetUp: String { ArisPrerequisites.full(.helper) }
    static var notRunning: String { notRunning(english: ArisUIWords.english) }
    static func notRunning(english: Bool) -> String {
        // No "in Settings": under this line in the notch is the button that restarts it there and then (ArisFixWords).
        ArisUIWords.text("Aris 에이전트가 꺼져 있어요. 에이전트를 다시 시작해 주세요.", "Aris's helper isn't running. Restart the helper.", english: english)
    }
    static var notAnswering: String {
        ArisUIWords.text("Aris 에이전트가 응답하지 않아요. 잠시 뒤에 다시 해 주세요.", "Aris's helper isn't answering. Please try again in a moment.")
    }
    static var refused: String { ArisUIWords.text("Aris 에이전트가 요청을 받지 않았어요.", "Aris's helper didn't take the request.") }
    /// The most characters of his own words one request may have (the helper's maxText).
    static let requestLimit = 20_000
    /// His words are over the limit: the helper will refuse them, so nothing is done for them first (the third VM run: a
    /// 25,000-character request took a 4-second look at the screen, then was refused).
    static func overLimit(_ text: String) -> Bool { text.count > requestLimit }
    /// A request longer than that (the helper answers 413): said as too long, with the limit (second upgrade run, bug 3).
    static func tooLong(english: Bool = ArisUIWords.english) -> String {
        let limit = requestLimit.formatted(.number.locale(Locale(identifier: english ? "en_US" : "ko_KR")))
        return ArisUIWords.text("요청이 너무 길어요. 한 번에 \(limit)자까지 받아요. 나눠서 보내 주세요.",
                                "That request is too long: Aris takes up to \(limit) characters at a time. Please send it in parts.", english: english)
    }
    /// The stream ended with no last line from the AI.
    static func noAnswer(_ brain: String, english: Bool = ArisUIWords.english) -> String {
        ArisUIWords.text("\(brain)가 답하지 않았어요.", "\(brain) didn't answer.", english: english)
    }
    /// The turn's stream was stopped from this side. It says only that: whether the work was undone isn't known here
    /// (it used to say "취소됐어요.", which claims the work was called off).
    static var stopped: String { stopped(english: ArisUIWords.english) }
    static func stopped(english: Bool) -> String { ArisUIWords.text("멈췄어요.", "Stopped.", english: english) }
    /// Any other transport error, with the system's words after it.
    static var errorPrefix: String { ArisUIWords.text("Aris 에이전트 오류: ", "Aris's helper had a problem: ") }
}
