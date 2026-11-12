//
//  ArisCardRevise.swift
//  Aris
//
//  The owner's ②A by voice: while an editable card waits, "내일로 바꿔", "7시로", "아빠한테 보내" or "내용은 곧 갈게로 바꿔"
//  changes that field on the card, in place, read by these rules (no model). A change only re-shows the card: it is never
//  a yes, and the yes after it follows the card's usual rules (a click or Y in a conversation or for a hands-free card; a
//  spoken yes only once its words held still). Also the ledger that carries a card's changes to POST /confirm.
//

import Foundation

enum ArisCardRevise {
    /// The new values the words give the card's fields; nil when they change nothing.
    static func parse(_ said: String, fields: [ArisCardField], values: [String: String], now: Date, calendar: Calendar) -> [String: String]? {
        let fields = fields.filter { !$0.fixed }
        let words = said.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: ".!?~,。"))
        guard !words.isEmpty else { return nil }
        let change = text(words, fields: fields) ?? recipient(words, fields: fields) ?? time(words, fields: fields, values: values, now: now, calendar: calendar)
        guard let change, change.contains(where: { values[$0.key] != $0.value }) else { return nil }
        return change
    }

    /// The ending that asks for a change: 로/으로, then perhaps 바꿔 (줘).
    private static let ask = #"\s*(?:(?:바꿔|해|고쳐|옮겨|미뤄|변경해|수정해)\s*(?:줘|주세요|줄래|요)?)?$"#

    private static func groups(_ pattern: String, _ text: String) -> [String?]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } }
    }

    /// "내용은 곧 갈게로 바꿔", "제목을 치과 예약으로".
    private static func text(_ words: String, fields: [ArisCardField]) -> [String: String]? {
        guard let found = groups(#"^(내용|메시지|문자|제목)\s*(?:은|는|을|를)?\s*["'“‘]?(.+?)["'”’]?\s*(?:으로|로|라고)"# + ask, words),
              let label = found[1], let value = found[2]?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        let texts = fields.filter { $0.role == .text }
        guard let field = texts.first(where: { $0.label == (label == "제목" ? "제목" : "내용") }) ?? texts.first else { return nil }
        return [field.key: value]
    }

    /// "아빠한테 보내", "받는 사람 민지로 바꿔".
    private static func recipient(_ words: String, fields: [ArisCardField]) -> [String: String]? {
        guard let field = fields.first(where: { $0.role == .recipient }) else { return nil }
        let found = groups(#"^받는\s*사람\s*(?:은|을|를)?\s*(.+?)\s*(?:으로|로)"# + ask, words)
            ?? groups(#"^(\S+?)\s*(?:한테|에게|께)\s*(?:로\s*)?(?:보내|바꿔|해)\s*(?:줘|주세요|요)?$"#, words)
        guard let name = found?[1]?.trimmingCharacters(in: .whitespaces), !name.isEmpty, name.count <= 30 else { return nil }
        return [field.key: name]
    }

    /// "내일로", "7시로", "오전 9시 반으로", "내일 오후 3시로", "18:30으로": the first time field.
    private static func time(_ words: String, fields: [ArisCardField], values: [String: String], now: Date, calendar: Calendar) -> [String: String]? {
        guard let field = fields.first(where: { $0.role == .time }), let current = ArisCardTime.parse(values[field.key] ?? field.value, calendar: calendar),
              let cue = words.range(of: #"(?:으로|로)"# + ask, options: .regularExpression) ?? words.range(of: #"\s*(?:바꿔|옮겨|미뤄)\s*(?:줘|주세요|요)?$"#, options: .regularExpression),
              !words[cue].isEmpty else { return nil }
        let core = words[..<cue.lowerBound].trimmingCharacters(in: .whitespaces)
        let pattern = #"^(?:(오늘|내일|모레|글피)\s*)?(?:(오전|오후|아침|저녁|밤|새벽)?\s*(\d{1,2})\s*시(?:\s*(반|(\d{1,2})\s*분))?|(\d{1,2}):(\d{2}))?$"#
        guard !core.isEmpty, let found = groups(pattern, core) else { return nil }
        var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: current)
        if let day = found[1], let shift = ["오늘": 0, "내일": 1, "모레": 2, "글피": 3][day],
           let date = calendar.date(byAdding: .day, value: shift, to: calendar.startOfDay(for: now)) {
            let target = calendar.dateComponents([.year, .month, .day], from: date)
            (parts.year, parts.month, parts.day) = (target.year, target.month, target.day)
        }
        if let hourText = found[3], let hour = Int(hourText) {
            parts.hour = hourOf(hour, period: found[2], current: parts.hour ?? 0)
            parts.minute = found[4] == "반" ? 30 : found[5].flatMap { Int($0) } ?? 0
        } else if let hourText = found[6], let hour = Int(hourText), let minute = found[7].flatMap({ Int($0) }) {
            (parts.hour, parts.minute) = (hour, minute)
        }
        guard (0..<24).contains(parts.hour ?? -1), (0..<60).contains(parts.minute ?? -1),
              let date = calendar.date(from: parts) else { return nil }
        return [field.key: ArisCardTime.format(date, calendar: calendar)]
    }

    /// A spoken hour on the 24-hour clock: 오후 adds 12; with no word for the time of day it stays in the half the card had.
    private static func hourOf(_ hour: Int, period: String?, current: Int) -> Int {
        switch period {
        case "오후", "저녁", "밤": return hour < 12 ? hour + 12 : hour
        case "오전", "아침", "새벽": return hour == 12 ? 0 : hour
        default: return current >= 12 && hour < 12 ? hour + 12 : hour
        }
    }
}

/// A card's time value ("2026-11-05 18:00", as aris-tools takes it), and how it reads ("오늘 오후 6:00").
enum ArisCardTime {
    private static func formatter(_ calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.isLenient = false
        return formatter
    }

    static func parse(_ value: String, calendar: Calendar = .current) -> Date? {
        let formatter = formatter(calendar)
        return formatter.date(from: value).flatMap { formatter.string(from: $0) == value ? $0 : nil }
    }

    static func format(_ date: Date, calendar: Calendar = .current) -> String { formatter(calendar).string(from: date) }

    /// The time in words under the field: "내일 오후 6:00"; on an English card "Tomorrow 6:00 PM", "Nov 14 at 6:00 PM".
    static func friendly(_ value: String, now: Date = Date(), calendar: Calendar = .current, english: Bool = false, locale: Locale? = nil) -> String? {
        guard let date = parse(value, calendar: calendar) else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 99
        if english {
            let time = ArisUIDates.time(date, english: true, calendar: calendar, locale: locale)
            if let day = [0: "Today", 1: "Tomorrow"][days] { return "\(day) \(time)" }
            return ArisUIDates.string(date, korean: "", template: "MMMdjmm", english: true, calendar: calendar, locale: locale)
        }
        let parts = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
        let day = [0: "오늘", 1: "내일", 2: "모레"][days] ?? "\(parts.month ?? 0)월 \(parts.day ?? 0)일"
        let hour = parts.hour ?? 0
        return "\(day) \(hour < 12 ? "오전" : "오후") \(hour % 12 == 0 ? 12 : hour % 12):\(String(format: "%02d", parts.minute ?? 0))"
    }
}

/// What the microphone heard while an editable card waits: a change of a field once its words held still, then a yes or
/// no from what came after it only. A change is never an answer: the "해 줘" or "바꿔" that goes on from it is dropped,
/// and a spoken yes counts only when its words began `yesHold` after the change (a no counts at once, as always).
struct ArisCardListening: Equatable {
    /// After a spoken change, a spoken yes waits this long (security review I1).
    static let yesHold: Double = 2

    private(set) var text = ""
    /// How much of the transcript a change already used.
    private(set) var used = 0
    private(set) var spoken = ArisSpokenAnswer()
    /// When the last spoken change was made.
    private(set) var changedAt: Double?

    /// What was said since the last change, without the words that only finish asking for it ("7시로… 해 줘").
    var rest: String {
        let tail = String(text.dropFirst(min(used, text.count))).trimmingCharacters(in: .whitespaces)
        guard used > 0, let ending = tail.range(of: #"^[\s,.…~]*(?:해|바꿔|고쳐|변경해|수정해|옮겨)\s*(?:줘|주세요|줄래|요)?(?=[\s,.!?~…]|$)[\s,.!?~…]*"#,
                                                  options: .regularExpression) else { return tail }
        return String(tail[ending.upperBound...])
    }

    func heard(_ text: String, at now: Double) -> ArisCardListening {
        var next = self
        next.text = text
        next.spoken = spoken.heard(next.rest, at: now)
        return next
    }

    /// Yes, no or nothing yet, as ArisSpokenAnswer says, but never a yes that began within `yesHold` of a change.
    func answer(at now: Double, voiceYes: Bool) -> Bool? {
        guard let answer = spoken.answer(at: now, voiceYes: voiceYes) else { return nil }
        return answer && !yesMayCount ? nil : answer
    }

    /// The last words when listening stopped: a no, or a yes as `answer` allows it.
    func final(_ text: String, at now: Double, voiceYes: Bool) -> Bool? {
        let next = heard(text, at: now)
        guard let answer = ArisConfirmReply.spoken(next.rest, voiceYes: voiceYes) else { return nil }
        return answer && !next.yesMayCount ? nil : answer
    }

    private var yesMayCount: Bool {
        changedAt.map { spoken.since - $0 >= Self.yesHold } ?? true
    }

    /// The change the words since the last one make, once they held still for `ArisSpokenAnswer.stableFor` and aren't
    /// a yes or no.
    func revision(at now: Double, fields: [ArisCardField], values: [String: String], now date: Date = Date(),
                  calendar: Calendar = .current) -> [String: String]? {
        guard !rest.isEmpty, now - spoken.since >= ArisSpokenAnswer.stableFor, ArisConfirmReply.parse(rest) == nil else { return nil }
        return ArisCardRevise.parse(rest, fields: fields.filter { !$0.fixed }, values: values, now: date, calendar: calendar)
    }

    /// The change was made at `now`: what follows is heard on its own.
    func consumed(at now: Double) -> ArisCardListening {
        var next = self
        next.used = text.count
        next.spoken = ArisSpokenAnswer()
        next.changedAt = now
        return next
    }
}

/// How long an editable card waits, and when a click or Y on it counts (the owner's ②A, review I2 and I5).
enum ArisCardTiming {
    /// A click or Y within this long of any change is ignored (the card moved under the pointer).
    static let clickHold: Double = 1
    /// Typing, or a change this recent, keeps the card waiting.
    static let typingGrace: Double = 5
    /// The longest the app waits on an editable card: just under the agent's own limit for it.
    static let longestWait: Double = ArisCardEdit.questionTimeout - ArisCardEdit.appMargin

    static func clickCounts(changedAt: Double?, now: Double) -> Bool {
        changedAt.map { now - $0 >= clickHold } ?? true
    }

    static func keepsWaiting(typing: Bool, changedAt: Double?, now: Double) -> Bool {
        typing || changedAt.map { now - $0 < typingGrace } ?? false
    }
}

/// A card's changes, kept from the moment the user answers until POST /confirm sends them (ArisAgentClient.confirm), for
/// every way a card is answered (a turn, a job's question, the inbox).
enum ArisCardEditLedger {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var entries: [String: (edits: [String: String], shown: String)] = [:]

    static func record(id: String, fields: [ArisCardField], values: [String: String]) {
        let edits = ArisCardEdit.edits(fields, values)
        lock.withLock {
            if entries.count > 50 { entries = [:] }
            entries[id] = edits.isEmpty ? nil : (edits, ArisCardEdit.shown(fields, values))
        }
    }

    static func take(_ id: String) -> (edits: [String: String], shown: String)? {
        lock.withLock { entries.removeValue(forKey: id) }
    }
}
