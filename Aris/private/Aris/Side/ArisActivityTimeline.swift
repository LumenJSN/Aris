//
//  ArisActivityTimeline.swift
//  Aris
//
//  The 한 일 tab's logic, pure (the owner's pick D+): today's entries grouped by teammate (전체) or, for one teammate, under
//  one "<name> · 오늘" line; the strip's teammates with today's counts (every one gets a chip; the strip scrolls);
//  which rows are faded or offer 되돌리기; the card a 409 asks.
//

import Foundation

/// One entry of what Aris did, as aris-tools prints it (`activity --json`).
struct ArisActivityItem: Decodable, Identifiable, Equatable {
    let id: String
    let date: Date
    let job: String
    let worker: String
    let summary: String
    /// Whether an undo exists and hasn't been done.
    let undoable: Bool
    let undone: Bool
    /// The undo deletes a calendar event: it needs the user's yes first.
    let asks: Bool
    /// The teammate whose job it was (its id; nil for Aris's own and for older rows): its face is found by this.
    var teammate: String?
    /// What it did: made, removed, moved, done or changed (ArisUndo.action); nil for older rows.
    var action: String?
    /// The automatic check let it run (aris-agent's ArisAutoMarks): the row and its receipt carry "확인함".
    var checked: Bool?
}

/// Which timeline the tab shows: everyone's, by teammate, or one teammate's.
enum ArisActivityFilter: Hashable {
    case everyone
    case teammate(String)
}

enum ArisActivityTab {
    /// Main Aris's name in the tab; also what an entry without a teammate is filed under.
    static let mainName = "Aris"
    /// Workers that are Aris itself: none given (aris-tools' default), the user's own undo, Aris.
    private static let mainWorkers: Set<String> = ["", "aris", "aris-tools", "user"]
    /// The conversation's job (ArisAgentRunner): main Aris talking, whichever brain runs it.
    private static let conversationJob = "대화"

    /// What a row's tooltip says of the work it came from: the job's own title, and the conversation's (which the
    /// record writes as "대화") in the window's language (the English tab's tooltip read "대화").
    static func jobTip(_ job: String, english: Bool = ArisUIWords.english) -> String {
        job == conversationJob ? ArisUIWords.text("대화", "Conversation", english: english) : job
    }
    /// Inside a selected chip, either side of its icon and label: 7, so the icon stays exactly where it sits in an
    /// unselected 30-point chip and only the name and count slide in beside it.
    static let chipPadding: CGFloat = 7
    /// What the user hears and reads when the agent couldn't tell the undo came from the app (403).
    static var refusedNotice: String { refusedNotice() }
    static func refusedNotice(english: Bool = ArisUIWords.english) -> String {
        ArisUIWords.text("Aris 앱 확인이 안 돼서 되돌리지 못했어요 (actions.log 참고)",
                         "I couldn't undo it: Aris's helper couldn't confirm this was the Aris app (see actions.log).", english: english)
    }
    /// What to say to undo the last thing, under the list: a phrase Aris takes in that language.
    static func undoPhrase(english: Bool = ArisUIWords.english) -> String { ArisUIWords.text("“방금 거 취소해”", "“undo that”", english: english) }
    /// The row's own undo button.
    static func undoWord(english: Bool = ArisUIWords.english) -> String { ArisUIWords.text("되돌리기", "Undo", english: english) }

    struct Teammate: Equatable {
        let name: String
        /// Entries today.
        let today: Int
    }

    struct Section: Equatable, Identifiable {
        let id: String
        let title: String
        /// The teammate whose avatar heads the section (전체), by its whole name; nil for the quiet day line of one
        /// teammate. `title` shows the name capped (ArisTeammateName.display).
        let teammate: String?
        /// Newest first.
        let rows: [ArisActivityItem]
    }

    enum Style: Equatable {
        /// 되돌리기 is offered.
        case undo
        /// Already undone: faded, with 되돌림 where the button was.
        case undone
        /// No undo exists: no button.
        case plain

        var faded: Bool { self == .undone }
        /// Whether the row has the line under its title for the button (or its 되돌림 tag).
        var hasMeta: Bool { self != .plain }
    }

    /// Each name's teammate id, from its newest row that has one: a face is found by id, by name only for older rows.
    static func teammateIds(_ items: [ArisActivityItem]) -> [String: String] {
        items.sorted { $0.date < $1.date }.reduce(into: [String: String]()) { ids, item in
            if let id = item.teammate { ids[teammate(of: item)] = id }
        }
    }

    static func teammate(of item: ArisActivityItem) -> String {
        let worker = item.worker.trimmingCharacters(in: .whitespacesAndNewlines)
        if mainWorkers.contains(worker.lowercased()) || item.job == conversationJob { return mainName }
        return worker
    }

    /// Today's entries, newest first.
    static func today(_ items: [ArisActivityItem], now: Date, calendar: Calendar) -> [ArisActivityItem] {
        items.filter { calendar.isDate($0.date, inSameDayAs: now) }.sorted { $0.date > $1.date }
    }

    static func todayCount(_ items: [ArisActivityItem], now: Date, calendar: Calendar) -> Int {
        today(items, now: now, calendar: calendar).count
    }

    /// Who did something today, the most recent first, each with today's count.
    static func teammates(_ items: [ArisActivityItem], now: Date, calendar: Calendar) -> [Teammate] {
        let rows = today(items, now: now, calendar: calendar)
        let order = rows.map(teammate(of:)).reduce(into: [String]()) { names, name in
            if !names.contains(name) { names.append(name) }
        }
        return order.map { name in Teammate(name: name, today: rows.filter { teammate(of: $0) == name }.count) }
    }

    /// 전체: one section per teammate, in the strip's order. One teammate: their entries under one day line naming
    /// them (the strip's chips show only avatars until picked). `roles`: each teammate's role once the app can read
    /// the teammate list (a seam; empty for now).
    static func sections(_ items: [ArisActivityItem], filter: ArisActivityFilter, now: Date, calendar: Calendar,
                         roles: [String: String] = [:]) -> [Section] {
        let rows = today(items, now: now, calendar: calendar)
        switch filter {
        case .everyone:
            return teammates(items, now: now, calendar: calendar).map { mate in
                Section(id: "mate:\(mate.name)", title: ArisTeammateName.display(mate.name), teammate: mate.name,
                        rows: rows.filter { teammate(of: $0) == mate.name })
            }
        case .teammate(let name):
            let theirs = rows.filter { teammate(of: $0) == name }
            return theirs.isEmpty ? [] : [Section(id: "day:\(name)", title: dayTitle(name: ArisTeammateName.display(name), role: roles[name]), teammate: nil, rows: theirs)]
        }
    }

    /// "코디 · 오늘", or "코디 · Claude Code 담당 · 오늘" when the role is known.
    static func dayTitle(name: String, role: String?, english: Bool = ArisUIWords.english) -> String {
        let role = role?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let today = ArisUIWords.text("오늘", "Today", english: english)
        return role.isEmpty ? "\(name) · \(today)" : "\(name) · \(role) · \(today)"
    }

    /// The filter to show after a refresh: a teammate with nothing today any more falls back to 전체.
    static func resolved(_ filter: ArisActivityFilter, among teammates: [Teammate]) -> ArisActivityFilter {
        guard case .teammate(let name) = filter, teammates.contains(where: { $0.name == name }) else { return .everyone }
        return filter
    }

    /// The time column: "2:05". On an English Mac whose region keeps a 24-hour clock (en_GB) it is "14:05": a 12-hour
    /// "2:05" with no AM or PM there read as two in the morning. A 12-hour region keeps the short "2:05" (the column
    /// has no room for AM/PM), and Korean is as it was.
    static func time(_ date: Date, calendar: Calendar, english: Bool = ArisUIWords.english, locale: Locale? = nil) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        if english, usesDayClock(locale ?? ArisUIDates.englishLocale()) { return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0) }
        return String(format: "%d:%02d", twelveHour(parts.hour ?? 0), parts.minute ?? 0)
    }

    /// The locale writes the hour on a 24-hour clock (its own hour format has no AM/PM).
    static func usesDayClock(_ locale: Locale) -> Bool {
        !(DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? "a").contains("a")
    }

    private static func twelveHour(_ hour: Int) -> Int {
        hour % 12 == 0 ? 12 : hour % 12
    }

    /// `now`: a timer that has run out has nothing left to undo, so its row offers none (third VM run: 되돌리기 stood on
    /// timers that had ended).
    static func style(_ item: ArisActivityItem) -> Style { style(item, now: Date()) }

    static func style(_ item: ArisActivityItem, now: Date) -> Style {
        if item.undone { return .undone }
        return item.undoable && !timerEnded(item, now: now) ? .undo : .plain
    }

    /// Whether the row is a timer Aris set ("타이머: 5분", as aris-tools and the app log it) whose time is up. A line
    /// that isn't such a timer, or whose length can't be read, is never taken as ended.
    static func timerEnded(_ item: ArisActivityItem, now: Date) -> Bool {
        guard let length = ArisActivityWords.timerLength(item.summary) else { return false }
        return now >= item.date.addingTimeInterval(length)
    }

    /// The list as it is once `id` was undone (before the refresh confirms it); the rest unchanged.
    static func markingUndone(_ items: [ArisActivityItem], id: String) -> [ArisActivityItem] {
        items.map { item in
            guard item.id == id else { return item }
            return ArisActivityItem(id: item.id, date: item.date, job: item.job, worker: item.worker, summary: item.summary,
                                    undoable: false, undone: true, asks: item.asks)
        }
    }

    static func footer(teammates: Int, today: Int, english: Bool = ArisUIWords.english) -> String {
        ArisUIWords.text("팀원 \(teammates)명 · 오늘 \(today)개", "\(ArisUIDates.count(teammates, "teammate", "teammates")) · \(today) today", english: english)
    }

    /// The card a 409 from /undo asks before the undo goes ahead: deleting the event Aris made, or bringing back a
    /// removed schedule (it runs on its own again).
    static func confirmation(id: String, summary: String, revivesSchedule: Bool, english: Bool = ArisUIWords.english) -> ArisConfirmation {
        let title = revivesSchedule ? ArisUIWords.text("예약 다시 살리기", "Bring the schedule back", english: english) : ArisUIWords.text("일정 지우기", "Delete the event", english: english)
        // The detail is the log's own line: it goes back to the agent with the yes, which checks it is the same.
        return ArisConfirmation(id: "undo-\(id)", title: title, detail: summary)
    }

    /// A name's pick from a list (a teammate's character, ArisCharacterLook.forName), the same on every launch (Swift's
    /// `hashValue` is not).
    static func paletteIndex(_ name: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 9973 } % count
    }
}

/// A line of the activity log as the 한 일 tab draws it. aris-tools, the agent and the app write the log in Korean
/// ("할 일 추가: 우유 사기", "변환: 3개 → PNG"), and an undo is checked against that very line, so the log stays as it
/// is: on an English Mac the tab says what was done in English where it draws the row, the names as they are. A line
/// the table (ArisActivityWords) doesn't know is shown as it was written.
extension ArisActivityWords {
    static func shown(_ summary: String, english: Bool = ArisUIWords.english) -> String {
        english ? self.english(summary) : summary
    }
}
