//
//  ArisSideDemoSamples.swift
//  Aris
//
//  The side panels' demo mode (ArisPreview `side-demo:on|off`, for recording): built-in sample rows for 할 일 (to-dos
//  and deadlines), 캘린더, 기록 and 한 일, at believable times around now, so nothing of the user's own Reminders, Canvas,
//  calendars, history or activity log is read or shown. Pure, so the tests run it; the switch lives in memory only
//  (ArisSideDemo), so it never outlasts the app.
//

import AppKit
import Foundation

/// Every panel's sample rows, made once when the demo turns on.
struct ArisSideDemoSamples {
    let todos: [ArisTodoItem]
    let deadlines: [ArisDue]
    let events: [ArisCalendarEvent]
    let history: [ArisHistoryEntry]
    let activity: [ArisActivityItem]

    /// Every id starts with this, so a demo row is never taken for a real one.
    static let idPrefix = "aris-demo-"

    init(now: Date, calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: now)
        func at(_ days: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let base = calendar.date(byAdding: .day, value: days, to: day) ?? day
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
        }
        let hour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        todos = Self.todos(now: now, at: at)
        deadlines = Self.deadlines(now: now, calendar: calendar, at: at)
        events = Self.events(hour: hour, at: at)
        history = Self.history(now: now, day: day)
        activity = Self.activity(now: now, day: day)
    }

    private static func todos(now: Date, at: (Int, Int, Int) -> Date) -> [ArisTodoItem] {
        // Two hours from now, on the half hour: still today in the evening, as a real draft would be.
        let soon = Date(timeIntervalSinceReferenceDate: ((now.timeIntervalSinceReferenceDate + 7200) / 1800).rounded(.down) * 1800)
        func item(_ n: Int, _ title: String, due: Date?, time: Bool, list: (String, String), notes: String? = nil) -> ArisTodoItem {
            ArisTodoItem(id: idPrefix + "todo-\(n)", title: title, notes: notes, due: due, hasTime: time,
                         listID: idPrefix + "list-" + list.0, listName: list.0, colorHex: list.1)
        }
        let work = ("업무", "#ff9f0a"), school = ("학교", "#0a84ff"), home = ("개인", "#30d158")
        return [item(1, "보고서 초안 쓰기", due: soon, time: true, list: work, notes: "팀장님께 보낼 초안"),
                item(2, "디자인 리뷰 준비", due: at(1, 10, 0), time: true, list: work),
                item(3, "발표 자료 정리", due: at(2, 23, 59), time: false, list: school),
                item(4, "독서 모임 책 읽기", due: at(4, 23, 59), time: false, list: home),
                item(5, "장보기", due: nil, time: false, list: home)]
    }

    private static func deadlines(now: Date, calendar: Calendar, at: (Int, Int, Int) -> Date) -> [ArisDue] {
        // The coming Friday (a week on when today is Friday), so the row reads "금".
        let weekday = calendar.component(.weekday, from: now)
        let toFriday = (6 - weekday + 7) % 7
        return [ArisDue(id: idPrefix + "due-1", course: "경영학", title: "과제 제출", at: at(toFriday == 0 ? 7 : toFriday, 23, 59), url: nil),
                ArisDue(id: idPrefix + "due-2", course: "마케팅", title: "팀 프로젝트 중간 발표", at: at(3, 14, 0), url: nil)]
    }

    private static func events(hour: Date, at: (Int, Int, Int) -> Date) -> [ArisCalendarEvent] {
        let work = ArisCalendarInfo(id: idPrefix + "cal-work", account: "데모", title: "업무", color: .systemOrange, isSubscribed: false, isReminderList: false)
        let mine = ArisCalendarInfo(id: idPrefix + "cal-me", account: "데모", title: "개인", color: .systemBlue, isSubscribed: false, isReminderList: false)
        func event(_ n: Int, _ title: String, _ start: Date, minutes: Double, _ cal: ArisCalendarInfo, place: String? = nil) -> ArisCalendarEvent {
            ArisCalendarEvent(id: idPrefix + "event-\(n)", start: start, end: start.addingTimeInterval(minutes * 60), title: title, location: place,
                              notes: nil, url: nil, isAllDay: false, kind: .event(.accepted), calendar: cal, participants: [], timeZone: nil,
                              hasRecurrence: false, isDetached: false, priority: nil, meetingLink: nil)
        }
        let h = 3600.0
        return [event(1, "스터디 모임", hour.addingTimeInterval(-2 * h), minutes: 90, mine, place: "도서관 3층"),
                event(2, "디자인 리뷰", hour.addingTimeInterval(h), minutes: 60, work, place: "회의실 B"),
                event(3, "점심 약속", at(1, 12, 30), minutes: 60, mine),
                event(4, "팀 회의", at(1, 15, 0), minutes: 60, work, place: "큰 회의실"),
                event(5, "주간 보고", at(2, 10, 0), minutes: 30, work),
                event(6, "팀 회의", at(3, 15, 0), minutes: 60, work)]
    }

    /// Never before today's midnight, so a demo right after it still has a today.
    private static func ago(_ minutes: Double, now: Date, day: Date) -> Date {
        max(now.addingTimeInterval(-minutes * 60), min(now, day.addingTimeInterval(60)))
    }

    private static func history(now: Date, day: Date) -> [ArisHistoryEntry] {
        let turns: [(Double, String, String)] = [
            (4, "내일 오후 일정 알려줘", "내일 오후 3시에 팀 회의가 있어요. 그 전에 12시 반 점심 약속이 있고요."),
            (6, "보고서 초안 쓰기 할 일에 넣어줘", "‘보고서 초안 쓰기’를 할 일에 넣었어요."),
            (9, "디자인 리뷰 몇 시였지?", "디자인 리뷰는 한 시간 뒤, 회의실 B예요."),
            (95, "발표 자료 정리할 시간 잡아줘", "모레 오전이 비어 있어서 거기에 넣어 둘게요."),
            (100, "오늘 날씨 어때?", "맑고 낮 최고 14도예요. 저녁엔 조금 쌀쌀해요."),
            (60 * 26, "회의록 요약해줘", "핵심은 세 가지예요. 일정 확정, 역할 분담, 다음 주 중간 점검."),
        ]
        return turns.enumerated().map { n, turn in
            ArisHistoryEntry(id: Self.uuid(n), date: turn.0 > 60 * 24 ? now.addingTimeInterval(-turn.0 * 60) : ago(turn.0, now: now, day: day),
                             heard: turn.1, reply: turn.2)
        }
    }

    private static func activity(now: Date, day: Date) -> [ArisActivityItem] {
        let rows: [(Double, String, String, String, Bool, String?)] = [
            (6, "대화", "Aris", "할 일에 ‘보고서 초안 쓰기’ 추가", true, nil),
            (22, "리뷰 노트 정리", "Claude Code", "디자인 리뷰 노트를 문서 한 장으로 정리", false, "claude-code"),
            (48, "대화", "Aris", "캘린더에 ‘팀 회의’ 일정 추가", true, nil),
            (70, "대화", "Aris", "타이머 25분 맞춤", false, nil),
            (130, "자료 조사", "Aris", "발표 자료용 참고 링크 5개 모음", false, nil),
        ]
        return rows.enumerated().map { n, row in
            ArisActivityItem(id: idPrefix + "activity-\(n)", date: ago(row.0, now: now, day: day), job: row.1, worker: row.2, summary: row.3,
                             undoable: row.4, undone: false, asks: false, teammate: row.5)
        }
    }

    /// Fixed ids, so the rows keep their identity while the demo runs.
    private static func uuid(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "A215DE30-0000-4000-8000-%012d", n)) ?? UUID()
    }
}

/// Whether the demo is on, and its samples while it is. Never stored anywhere: a new launch starts with it off.
struct ArisSideDemoSwitch {
    private(set) var samples: ArisSideDemoSamples?
    var isOn: Bool { samples != nil }

    /// `side-demo:on` / `side-demo:off` (any case); nil for anything else.
    static func wanted(_ command: String) -> Bool? {
        switch command.trimmingCharacters(in: .whitespaces).lowercased() {
        case "side-demo:on": true
        case "side-demo:off": false
        default: nil
        }
    }

    /// Turns it on (fresh samples around `now`) or off; true when that changed anything.
    mutating func set(_ on: Bool, now: Date) -> Bool {
        guard on != isOn else { return false }
        samples = on ? ArisSideDemoSamples(now: now) : nil
        return true
    }
}
