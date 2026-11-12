//
//  ArisJob.swift
//  Aris
//
//  A teammate job: one piece of a request the main brain split off to run in parallel.
//

import Foundation

enum ArisJobAssignee: Codable, Equatable {
    case clone
    case teammate(String)
    /// A temporary helper (parallel work no teammate matches): the n-th of its hand-out, with a default face, gone with
    /// its job (ArisHelpers).
    case helper(Int)
}

enum ArisJobTarget: Codable, Equatable {
    case notch
    case window(pid: Int32, windowNumber: Int)
}

enum ArisJobState: Codable, Equatable {
    case queued
    case running(step: String)
    case awaitingApproval(id: String)
    case done(String)
    case failed(String)
    case cancelled
}

struct ArisJob: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let prompt: String
    let assignee: ArisJobAssignee
    let cwd: String?
    let appHint: String?
    var target: ArisJobTarget
    var state: ArisJobState
    let created: Date
}

/// What the main brain asked for, before a job exists.
struct ArisJobSpec: Equatable {
    let title: String
    let prompt: String
    let assignee: ArisJobAssignee
    let cwd: String?
    let appHint: String?
}

/// A background job's question parked until the user is at the Mac.
enum ArisParkedCard {
    /// How long a job's stream may go quiet (and last): longer than a question may park (24 h), so a night's sleep
    /// never drops it. The agent also sends a blank line every few minutes.
    static let streamTimeout: TimeInterval = 26 * 3_600
    /// How long a job's whole stream may last: a day parked plus the work before and after it.
    static let streamLifetime: TimeInterval = 48 * 3_600

    /// Shown only while the job's stream is still open and the agent still waits for that id: a stream that ended
    /// (the agent restarted, or the job finished) or an expired question never shows a card.
    static func shows(streamEnded: Bool, agentWaiting: Bool) -> Bool {
        !streamEnded && agentWaiting
    }
}

/// Cancelling a job in the agent (POST /cancel): tried a few times, since a lost cancel would leave its task running.
enum ArisJobCancel {
    static let attempts = 3
    /// What the job says when the agent never confirmed the cancel.
    static let unconfirmed = "중단됨 · 아직 돌고 있을 수 있어요"

    /// The wait before attempt `attempt` + 1: 0.5 s, 1 s, 2 s.
    static func delay(after attempt: Int) -> Duration {
        .milliseconds(500 * (1 << max(0, attempt - 1)))
    }
}

/// Aris's own things: its schedules (예약) and reminders, to-dos, memory, teammates, timers and settings. A request to
/// list, change or remove one is done in the main turn through its own aris-tools path and card: never handed out as
/// a job, and never given to Aside or computer use (QA BUG-60: "큐에이 예약 테스트 예약 지워 줘" became a job that asked
/// Aside to delete Aris's own schedule). Told from the user's words: one of Aris's nouns with a word that lists, changes or
/// removes it, and nothing that makes it somewhere else's (a place that takes bookings, a site, another app). Pure.
enum ArisOwnData {
    enum Kind: String, Equatable { case schedule, todo, memory, teammate, timer, settings }

    /// Listing, changing or removing (a schedule, a reminder, a to-do, a teammate).
    static let manage = ["지워", "지우", "취소", "삭제", "없애", "빼", "멈춰", "멈추", "중지", "꺼", "끄고", "바꿔", "바꾸", "수정", "미뤄", "변경", "추가", "목록", "보여", "뭐 있", "뭐있"]
    /// Changing or removing only: what a schedule named by its own title needs beside it.
    static let change = ["지워", "지우", "취소", "삭제", "없애", "빼", "멈춰", "멈추", "중지", "꺼", "끄고", "바꿔", "바꾸", "수정", "미뤄", "변경"]
    /// Somewhere else's booking, alert, list or setting: a place that takes bookings, a site, another app.
    static let elsewhere = ["식당", "레스토랑", "맛집", "카페", "호텔", "숙소", "펜션", "리조트", "병원", "치과", "의원", "진료", "검진", "미용실", "헤어", "네일",
                            "항공", "비행기", "기차", "ktx", "버스", "공연", "영화", "티켓", "좌석", "테이블", "예매", "골프", "캠핑", "렌터카", "택시", "회의실",
                            "네이버", "카카오", "카톡", "구글", "쿠팡", "배민", "야놀자", "여기어때", "에어비앤비", "캐치테이블", "사이트", "웹", "홈페이지", "브라우저",
                            "유튜브", "인스타", "슬랙", "디스코드", "노션", "지라", "트렐로", "깃허브", "메일", "문자", "시트", "엑셀", "문서", "캘린더", "달력"]
    static let elsewhereEnglish = #"\b(restaurant|hotel|flight|table|ticket|appointment|doctor|dentist|seat|booking|reservation|train|bus|class|work|conference|meeting|tv|game|release|payment|website|site|e-?mail|youtube|slack|notion|jira|trello|github|calendar|doc|document|sheet|spreadsheet)s?\b|\b[a-z0-9-]+\.(com|net|org|io|kr|co|app)\b"#
    /// Making one: a schedule, a scheduled run or a routine asked for by name, "remind me …", or anything asked for
    /// again and again at a time ("every day at 2:24 am, say good morning": final VM run, where it went out as a job
    /// that only said it was set up).
    static let englishMakeSchedule = #"\b(make|create|add|set up|set|start|schedule)\b[^.\n]*\b(schedules?|scheduled (tasks?|jobs?|runs?|reminders?)|reminders?)\b|\bremind me\b"#
    static let makeWords = ["만들", "걸어", "등록", "맞춰", "설정"]
    static let recurrence = #"(?i)(매일|매주|매달|매월|매년|평일마다|주말마다|[가-힣0-9]+\s*마다|every\s+(day|week|weekday|weekend|morning|evening|night|month|monday|tuesday|wednesday|thursday|friday|saturday|sunday|\d+\s*(minutes?|hours?|days?))|\bdaily\b|\bweekly\b|\bmonthly\b)"#
    static let timeOfDay = #"(?i)(\d{1,2}\s*시|\d{1,2}:\d{2}|아침|저녁|밤|오전|오후|새벽|점심|정오|자정|\d{1,2}\s*(am|pm)|\bat\s+\d{1,2}\b|morning|evening|night|noon|midnight|분마다|시간마다|minutes?|hours?)"#
    /// A repeating thing that belongs in the calendar, not in Aris's schedules.
    static let calendarWords = #"(?i)(캘린더|달력|일정|\b(calendar|events?|meetings?|appointments?|class(es)?)\b)"#

    /// A time by the clock ("2:24 am", "at 9", "8시", "noon"), or an interval that needs none ("every 30 minutes").
    static let clockTime = #"(?i)(\d{1,2}\s*시|\d{1,2}:\d{2}|\d{1,2}\s*(am|pm)\b|\bat\s+\d{1,2}\b|\b(noon|midnight)\b|정오|자정)"#
    static let interval = #"(?i)(\bevery\s+\d+\s*(minutes?|hours?|days?)\b|\d+\s*(분|시간|일)\s*마다)"#
    /// Words that only ask ("what do I have every day at 9?"): never a request to make a schedule.
    static let onlyAsks = #"(?i)^\s*(what|when|where|who|whom|why|how|which|is|are|was|were|do|does|did|am)\b|(뭐야|뭐지|뭔가요|인가요|나요|니|까)\s*\??\s*$"#

    /// A request to do something again and again at a time by the clock, or at an interval: a schedule of Aris's to
    /// make. Narrower than `isRecurring` on purpose (security review 6, L6): "daily" or "weekly" with "morning" or
    /// "hours" somewhere in an ordinary request ("a daily summary of the morning news", "I work 8 hours daily") is
    /// not one, and neither is a question.
    static func asksToRepeat(_ text: String) -> Bool {
        let reads = { (pattern: String) in text.range(of: pattern, options: .regularExpression) != nil }
        guard reads(recurrence), reads(clockTime) || reads(interval) else { return false }
        return !reads(onlyAsks) && !text.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?")
    }

    /// Asked for again and again, at a time: the app sends such words to the AI rather than doing a part of them
    /// itself (ArisIntent.isRecurring is this). Wider than `asksToRepeat`, which decides whose data it is.
    static func isRecurring(_ text: String) -> Bool {
        text.range(of: recurrence, options: .regularExpression) != nil && text.range(of: timeOfDay, options: .regularExpression) != nil
    }

    static let englishSchedule = #"\b(delete|cancel|remove|pause|stop|change|edit)\b[^.\n]*\b(schedules?|scheduled (tasks?|jobs?|runs?|reminders?)|reminders?)\b|\b(schedules?|reminders?)\b[^.\n]*\b(delete|cancel|remove|pause|stop)\b|\b(list|show)\b[^.\n]*\b(my|aris'?s?) (schedules?|scheduled (tasks?|jobs?|runs?)|reminders?)\b"#
    static let englishTodo = #"\bto-?do( list|s)?\b[^.\n]*\b(add|remove|delete|finish|complete|check|done|list|show)\b|\b(add|remove|delete|finish|complete|check off|list|show)\b[^.\n]*\bto-?do( list|s)?\b"#
    /// Not the user's memory: a computer's.
    static let machineMemory = ["사용량", "누수", "용량", "램", "ram", "카드", "usb", "캐시", "디스크", "서버", "프로세스", "크롬", "usage", "leak", "cache", "disk"]
    static let englishMemory = #"\b(forget|remember) (that|what|my|everything|about|this|it)\b|\b(delete|clear|erase|wipe)\b[^.\n]*\bmemor(y|ies)\b"#
    static let englishTeammate = #"\bteammates?\b[^.\n]*\b(remove|delete|add|make|create|list|show|rename)\b|\b(remove|delete|add|make|create|list|show|rename)\b[^.\n]*\bteammates?\b"#
    static let englishTimer = #"\btimers?\b[^.\n]*\b(cancel|stop|set|start|pause|left|remaining)\b|\b(cancel|stop|set|start|pause)\b[^.\n]*\btimers?\b"#

    /// Which of Aris's own things `text` asks to make, list, change or remove; nil when it is none (other work, or somewhere
    /// else's). `scheduleNames`: Aris's schedules' titles: a title said with a word that changes or removes it is one of
    /// them, whatever else the words say.
    /// `making`: also read a request to make one (a recurring run, "remind me", "make a schedule"). Without it only
    /// the listing, changing and removing of before: what a job's answer is read with, so that an answer which merely
    /// mentions a time every day is not taken for a claim about Aris's schedules (ArisOwnDataHonesty).
    static func kind(of text: String, scheduleNames: [String] = [], making: Bool = true) -> Kind? {
        let said = text.precomposedStringWithCanonicalMapping.lowercased()
        let has = { (words: [String]) in words.contains(where: said.contains) }
        let reads = { (pattern: String) in said.range(of: pattern, options: .regularExpression) != nil }
        if namesSchedule(text, scheduleNames: scheduleNames) { return .schedule }
        // Making a recurring run is Aris's own schedule whatever the run is about (a mail summary every morning at
        // 8), unless the words put it in the calendar.
        if making, asksToRepeat(said), !reads(calendarWords) { return .schedule }
        if making, reads(#"\bremind me\b"#) { return .schedule }
        let outside = has(elsewhere) || reads(elsewhereEnglish)
        if !outside {
            if has(["예약", "스케줄", "알림", "리마인더"]), has(making ? manage + makeWords : manage) { return .schedule }
            if reads(englishSchedule) || (making && reads(englishMakeSchedule)) { return .schedule }
            if has(["할 일", "할일", "투두"]), has(manage + ["넣어", "적어", "완료", "체크", "끝냈"]) { return .todo }
            if reads(englishTodo) { return .todo }
        }
        if !has(machineMemory) {
            if has(["기억", "메모리"]), has(["지워", "지우", "삭제", "잊어", "없애", "초기화", "기억해"]) { return .memory }
            if has(["잊어 줘", "잊어줘", "잊어버려", "잊지 마", "잊지마"]) || reads(englishMemory) { return .memory }
        }
        if has(["팀원"]), has(["지워", "지우", "삭제", "없애", "빼", "만들", "추가", "목록", "누구", "보여", "바꿔", "바꾸", "수정"]) { return .teammate }
        if reads(englishTeammate) { return .teammate }
        if has(["타이머"]), has(["꺼", "끄고", "취소", "지워", "멈춰", "멈추", "중지", "맞춰", "맞추", "설정", "시작", "몇", "남았", "얼마"]) { return .timer }
        if reads(englishTimer) { return .timer }
        if reads(#"(아리스|aris)[^.\n]{0,12}(설정|settings?)"#) { return .settings }
        return nil
    }

    /// One of Aris's schedules named by its own title (three characters or more), with a word that changes or removes
    /// it: Aris's for certain, where 예약 alone could still be a booking somewhere.
    static func namesSchedule(_ text: String, scheduleNames: [String]) -> Bool {
        let said = text.precomposedStringWithCanonicalMapping.lowercased()
        let compact = said.replacingOccurrences(of: " ", with: "")
        guard change.contains(where: said.contains) || said.range(of: #"\b(delete|cancel|remove|pause|stop|change|edit)\b"#, options: .regularExpression) != nil else { return false }
        return scheduleNames.contains { title in
            let name = title.precomposedStringWithCanonicalMapping.lowercased().replacingOccurrences(of: " ", with: "")
            return name.count >= 3 && compact.contains(name)
        }
    }

    /// The words ask for one of Aris's own things.
    static func mentions(_ text: String, scheduleNames: [String] = []) -> Bool { kind(of: text, scheduleNames: scheduleNames) != nil }

    /// What the user calls that kind of thing.
    static func noun(_ kind: Kind, korean: Bool) -> String {
        switch kind {
        case .schedule: return korean ? "예약" : "schedule"
        case .todo: return korean ? "할 일" : "to-do"
        case .memory: return korean ? "기억" : "memory"
        case .teammate: return korean ? "팀원" : "teammate"
        case .timer: return korean ? "타이머" : "timer"
        case .settings: return korean ? "설정" : "settings"
        }
    }
}
