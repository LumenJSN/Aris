//
//  ArisActivityWords.swift
//  Aris (also built into aris-agent)
//
//  A line of the activity log in English. aris-tools, the agent and the app write the log in Korean ("할 일 추가: 우유
//  사기", "변환: 3개 → PNG"), and an undo is checked against that very line, so the log stays as it is. Wherever one of
//  its lines is shown or said in English, this one table says it: the 한 일 tab and the day-end card in the app
//  (ArisActivityWords.shown), and aris-agent's answer to "why did you do that?" (VM run 2026-11-11: its English answer
//  quoted “새 폴더: qa-1111”). The names in a line stay as they are; a line the table doesn't know is left as it was
//  written. Foundation only (tested).
//

import Foundation

enum ArisActivityWords {
    static func english(_ summary: String) -> String {
        if let known = whole[summary] { return known }
        for (lead, said, counted) in leads where summary.hasPrefix(lead) {
            let rest = String(summary.dropFirst(lead.count))
            if scheduled.contains(lead) { return said + when(rest) }
            return said + (counted ? counts(rest) : rest)
        }
        return summary
    }

    /// The kinds whose line ends with when the schedule runs, in brackets, as aris-agent writes it (ArisSchedule.describe).
    private static let scheduled: Set<String> = ["예약: ", "예약 취소: "]
    private static let weekdays = ["일": "Sunday", "월": "Monday", "화": "Tuesday", "수": "Wednesday", "목": "Thursday", "금": "Friday", "토": "Saturday"]

    /// A schedule's line with its time in English: "standup (매일 09:00)" → "standup (every day at 09:00)", "(매주 금
    /// 18:00)" → "(every Friday at 18:00)", "(30분마다)" → "(every 30 minutes)", "(11월 3일 14:05에 한 번)" → "(once,
    /// 11/3 at 14:05)". Only the brackets that end the line, and only when they hold one of those forms: the title, and
    /// brackets of its own, stay as they are (the English undo card and Activity rows read "(매일 09:00)").
    static func when(_ rest: String) -> String {
        guard rest.hasSuffix(")"), let open = rest.range(of: " (", options: .backwards) else { return rest }
        let inside = String(rest[open.upperBound...].dropLast())
        func groups(_ pattern: String) -> [String]? {
            guard let regex = try? NSRegularExpression(pattern: "^" + pattern + "$"),
                  let match = regex.firstMatch(in: inside, range: NSRange(inside.startIndex..., in: inside)) else { return nil }
            return (1..<match.numberOfRanges).map { Range(match.range(at: $0), in: inside).map { String(inside[$0]) } ?? "" }
        }
        let said: String
        if let found = groups(#"매일 (\d{2}:\d{2})"#) {
            said = "every day at \(found[0])"
        } else if let found = groups(#"매주 ([일월화수목금토]) (\d{2}:\d{2})"#), let day = weekdays[found[0]] {
            said = "every \(day) at \(found[1])"
        } else if let found = groups(#"(\d+)분마다"#) {
            said = "every \(found[0]) minutes"
        } else if let found = groups(#"(\d+)시간마다"#) {
            said = found[0] == "1" ? "every hour" : "every \(found[0]) hours"
        } else if let found = groups(#"(\d{1,2})월 (\d{1,2})일 (\d{2}:\d{2})에 한 번"#) {
            said = "once, \(found[0])/\(found[1]) at \(found[2])"
        } else {
            return rest
        }
        return rest[..<open.lowerBound] + " (" + said + ")"
    }

    private static let whole: [String: String] = [
        "뽀모도로": "Pomodoro", "타이머 끔": "Timer off", "볼륨 올림": "Volume up", "볼륨 낮춤": "Volume down", "음소거 바꿈": "Mute changed",
        "메모 저장": "Note saved",
    ]

    /// What a line starts with; `counted`: what follows is counts written by the tool ("3개 → PNG"), never a name.
    private static let leads: [(String, String, Bool)] = [
        ("할 일 추가: ", "To-do added: ", false), ("할 일 완료: ", "To-do done: ", false), ("할 일 지움: ", "To-do removed: ", false),
        ("내일로 넘김: ", "Moved to tomorrow: ", false),
        ("옮김: ", "Moved: ", false), ("이름 바꿈: ", "Renamed: ", false), ("새 폴더: ", "New folder: ", false), ("휴지통으로: ", "To the Trash: ", false),
        ("일정 추가: ", "Event added: ", false), ("집 위치: ", "Home: ", false), ("예약 취소: ", "Schedule cancelled: ", false), ("예약: ", "Scheduled: ", false),
        ("변환: ", "Converted: ", true), ("합침: ", "Merged: ", true), ("나눔: ", "Split: ", true), ("압축: ", "Made smaller: ", true),
        ("창 배치: ", "Windows arranged: ", true), ("타이머: ", "Timer: ", true), ("볼륨 ", "Volume ", false),
        // The log's other lines (ArisActSummary, the calendar's changes, a mail reply's draft): they were drawn as written.
        ("일정 삭제: ", "Event deleted: ", false), ("일정 변경: ", "Event changed: ", false), ("메시지 보냄: ", "Message sent: ", false),
        ("미리 알림 추가: ", "Reminder added: ", false), ("메모 저장: ", "Note saved: ", false), ("기억함: ", "Remembered: ", false),
        ("기억 지움: ", "Memories cleared: ", true), ("기본 캘린더: ", "Default calendar: ", false), ("메일 답장 초안: ", "Mail reply drafted: ", false),
    ]

    /// The kinds a line can start with, as the log writes them ("할 일 추가", "예약 취소"): for whoever words a kind
    /// (ArisUndoWords.doneNouns).
    static var kinds: [String] { leads.map(\.0).filter { $0.hasSuffix(": ") }.map { String($0.dropLast(2)) } }

    /// The length a logged timer line names: "타이머: 5분", "타이머: 90초", "타이머: 1시간 30분", "타이머: 25" (minutes).
    static func timerLength(_ summary: String) -> TimeInterval? {
        guard summary.hasPrefix("타이머: ") else { return nil }
        let words = String(summary.dropFirst("타이머: ".count))
        var seconds = 0.0, found = false
        for (unit, each) in [("시간", 3_600.0), ("분", 60.0), ("초", 1.0)] {
            guard let match = words.range(of: "(\\d+)\\s*" + unit, options: .regularExpression),
                  let number = Double(words[match].filter(\.isNumber)) else { continue }
            seconds += number * each
            found = true
        }
        if !found, let minutes = Double(words.trimmingCharacters(in: .whitespaces)) { return minutes * 60 }
        return found ? seconds : nil
    }

    /// What follows a counted lead, in English: "3개 → PNG" → "3 → PNG", "a.pdf 외 2개 → b.pdf" → "a.pdf and 2 more →
    /// b.pdf", "25분" → "25 min", "Safari 3개" → "Safari 3". Only the tool's own counts are put into English, by where
    /// the tool writes them: a side of "a → b" that is nothing but a count, the " 외 2개" that ends the left side, the
    /// count that ends a line with no arrow. A file's name is never touched: "보고서 3개 최종.pdf" stays as it is (it
    /// used to lose its 개 on an English card: security review 3, I2).
    private static func counts(_ text: String) -> String {
        let stopped = " (중간에 멈춤)"
        let partway = text.hasSuffix(stopped)
        let body = partway ? String(text.dropLast(stopped.count)) : text
        let said: String
        if let arrow = body.range(of: " → ", options: .backwards) {
            said = from(String(body[..<arrow.lowerBound])) + " → " + count(String(body[arrow.upperBound...]))
        } else {
            said = last(body)
        }
        return said + (partway ? " (stopped partway)" : "")
    }

    /// A side that is only a count ("3개", "PDF 1개") without its 개; anything else (a name, a kind) as it is.
    private static func count(_ side: String) -> String {
        side.range(of: #"^(PDF )?\d+개$"#, options: .regularExpression) == nil ? side : String(side.dropLast())
    }

    /// What was converted: a count, or the first file's name and how many more ("a.pdf 외 2개").
    private static func from(_ side: String) -> String {
        guard let more = side.range(of: #" 외 \d+개$"#, options: .regularExpression) else { return count(side) }
        let number = side[more].filter(\.isNumber)
        return side[..<more.lowerBound] + " and \(number) more"
    }

    /// A line with no arrow: a timer's minutes, a bare count, or a name and then its count ("Safari 3개").
    private static func last(_ text: String) -> String {
        if text.range(of: #"^\d+분$"#, options: .regularExpression) != nil { return text.dropLast() + " min" }
        return text.range(of: #"(^| )\d+개$"#, options: .regularExpression) == nil ? text : String(text.dropLast())
    }
}
