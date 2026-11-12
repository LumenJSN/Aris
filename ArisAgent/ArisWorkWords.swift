//
//  ArisWorkWords.swift
//  aris-agent
//
//  The work memory in the user's words, Korean or English: what a lesson says and what it is based on (설정 › 기억 and
//  "…잊어"), and when something was done. Commands stay as they are (they are what Aris ran); everything around them
//  is said plainly. Foundation only (tested).
//

import Foundation

enum ArisWorkWords {
    private static func chain(_ steps: [ArisWorkStep]) -> String { steps.map { "`\($0.line)`" }.joined(separator: " → ") }


    /// What a lesson says, as one or two short sentences.
    static func sentence(_ lesson: ArisWorkLesson, korean: Bool) -> String {
        let target = lesson.works.first?.args.last?.value ?? ""
        switch lesson.kind {
        case .way:
            let failed = lesson.distinctFails.map { "`\($0.line)`" }.joined(separator: ", ")
            if korean { return "‘\(lesson.asked)’ 같은 요청은 \(chain(lesson.works)) 순서로 하면 돼요." + (failed.isEmpty ? "" : " \(failed) 방법은 여기서 안 됐어요.") }
            return "For a request like “\(lesson.asked)”, \(chain(lesson.works)) works here." + (failed.isEmpty ? "" : " \(failed) failed here.")
        case .flag:
            // A failed form that reads like the one that works says nothing: only what works.
            let other = lesson.distinctFails.first?.line ?? (lesson.fails.isEmpty ? lesson.key : nil)
            let failed = "`\(other ?? "")`"
            if other == nil || lesson.works.map(\.line).joined(separator: " → ") == other {
                return korean ? "이 Mac에서는 이렇게 하면 돼요: \(chain(lesson.works))" : "On this Mac \(chain(lesson.works)) works."
            }
            return korean ? "이 Mac에서는 \(failed) 대신 이렇게 해야 돼요: \(chain(lesson.works))" : "On this Mac \(chain(lesson.works)) works where \(failed) fails."
        case .place:
            return korean ? "`\(lesson.key)`의 결과는 보통 \(target)에 둬요." : "`\(lesson.key)` usually goes to \(target)."
        case .name:
            return korean ? "요청에 나오는 ‘\(lesson.key)’ 이름의 경로: \(target)" : "“\(lesson.key)” means \(target)."
        }
    }

    /// What a lesson rests on: how many times, the latest of them, and how sure it is.
    static func basis(_ lesson: ArisWorkLesson, latest: ArisWorkEpisode?, korean: Bool, calendar: Calendar = .current) -> String {
        let sure = Int((lesson.confidence * 100).rounded())
        let last = latest.map { episode in
            korean ? "최근 \(day(episode.at, korean: true, calendar: calendar)) ‘\(episode.asked)’" : "last on \(day(episode.at, korean: false, calendar: calendar)): “\(episode.asked)”"
        }
        let count = korean ? "\(lesson.evidence.count)번 해 본 것" : lesson.evidence.count == 1 ? "seen once" : "seen \(lesson.evidence.count) times"
        return ([count] + (last.map { [$0] } ?? []) + [korean ? "확신 \(sure)%" : "\(sure)% sure"]).joined(separator: " · ")
    }

    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// "11월 10일" / "Nov 10".
    static func day(_ date: Date, korean: Bool, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.month, .day], from: date)
        let month = parts.month ?? 1, day = parts.day ?? 1
        return korean ? "\(month)월 \(day)일" : "\(months[max(0, min(11, month - 1))]) \(day)"
    }

    /// "어제 오후 3:12", "11월 10일 오전 9:05" / "yesterday at 3:12 PM", "Nov 10 at 9:05 AM".
    static func when(_ date: Date, now: Date, korean: Bool, calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 99
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0, minute = parts.minute ?? 0
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        let time = korean ? "\(hour < 12 ? "오전" : "오후") \(twelve):\(String(format: "%02d", minute))" : "\(twelve):\(String(format: "%02d", minute)) \(hour < 12 ? "AM" : "PM")"
        let named: String? = days == 0 ? (korean ? "오늘" : "today") : days == 1 ? (korean ? "어제" : "yesterday") : days == 2 ? (korean ? "그제" : "two days ago") : nil
        let dayWords = named ?? day(date, korean: korean, calendar: calendar)
        return korean ? "\(dayWords) \(time)" : "\(dayWords) at \(time)"
    }
}
