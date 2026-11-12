//
//  ArisDayEnd.swift
//  Aris
//
//  The day-end summary, the other side of the morning brief (ArisBrief): what the user meant to do today set against what
//  got done. It comes on "오늘 정리해 줘" or "wrap up my day" as one sentence (said aloud and shown) with a folded 목록
//  row under it, and is offered once in the evening as a quiet chip (ArisDayEndOffer). Opened, the row is a checklist:
//  everything planned for today with a mark, what waits for his answer, and what tomorrow starts with. Every word is
//  made here from facts this Mac already holds (Reminders, the calendar, the jobs he handed over, the schedules, the
//  확인 대기 cards and the activity record), so it is whole and true with no AI at all. Nothing counts who did how much.
//  Here: the day it is about, the facts it is made from, and the made summary. Foundation only, so it is tested.
//

import Foundation

/// The day a summary is about. Until 5 in the morning (when the morning brief's day begins) "today" is still the day
/// before, and "tomorrow" the day that has just started: "오늘 정리해 줘" at half past midnight is about the day the user is
/// finishing.
struct ArisDaySpan: Equatable {
    static let startHour = 5

    /// Midnight at the start of the day being wrapped up, and of the day after it.
    let today: Date
    let tomorrow: Date
    let afterTomorrow: Date

    init(now: Date, calendar: Calendar = .current) {
        let midnight = calendar.startOfDay(for: now)
        let late = calendar.component(.hour, from: now) < Self.startHour
        today = late ? calendar.date(byAdding: .day, value: -1, to: midnight) ?? midnight : midnight
        tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        afterTomorrow = calendar.date(byAdding: .day, value: 1, to: tomorrow) ?? tomorrow
    }

    /// Past midnight the day being wrapped up runs on until now.
    func isToday(_ date: Date, now: Date) -> Bool { date >= today && date <= max(now, tomorrow) }
    func isTomorrow(_ date: Date) -> Bool { date >= tomorrow && date < afterTomorrow }
}

/// What the summary is made from, as the app holds it (ArisDayEndModel gathers these; the tests pass their own).
struct ArisDayEndFacts: Equatable {
    /// Something the user handed to Aris or a teammate today.
    struct Job: Equatable {
        enum Outcome: Equatable {
            case done
            /// It failed, and why.
            case failed(String)
            /// He stopped it himself.
            case stopped
            case running
            /// It waits for a yes whose card is on its way to the screen.
            case asking
        }

        let id: String
        let title: String
        let outcome: Outcome
    }

    /// A question parked as 확인 대기 (ArisWaitingCard).
    struct Card: Equatable {
        let id: String
        let title: String
        let action: String
    }

    struct Event: Equatable {
        let start: Date
        let end: Date
        let title: String
        var allDay = false
    }

    /// A reminder: open, or ticked off (`completed` says when).
    struct Todo: Equatable {
        let id: String
        let title: String
        var due: Date? = nil
        var hasTime = false
        var completed: Date? = nil
    }

    struct Deadline: Equatable {
        let course: String
        let title: String
        let at: Date
    }

    /// One of Aris's schedules as it runs tomorrow. `every`: it repeats this many seconds apart all day. `repeats`: it
    /// comes back every day or week (a routine), where a one-time one is something he asked for once.
    struct Schedule: Equatable {
        let title: String
        let at: Date
        var every: Int? = nil
        var repeats = true
    }

    /// One of Aris's schedules that was due today, and how its run went.
    struct Routine: Equatable {
        enum State: String, Equatable {
            case done, failed, running
            /// It hasn't run today: its time is still ahead, or it was missed.
            case pending
        }

        let title: String
        let at: Date
        let state: State
        var repeats = true
    }

    /// The activity record; nil when aris-agent didn't answer.
    var activity: [ArisActivityItem]? = []
    var jobs: [Job] = []
    var cards: [Card] = []
    var events: [Event] = []
    var todos: [Todo] = []
    var deadlines: [Deadline] = []
    var schedules: [Schedule] = []
    var routines: [Routine] = []
    /// The to-dos the user put off until tomorrow from this list today (ArisDayEndKept): they stay on it, marked 넘겼어요.
    var moved: Set<String> = []
}

struct ArisDayEnd: Equatable {
    /// The mark a row or a count is drawn with (ArisDayEndMark).
    enum Mark: Equatable { case done, part, none, wait }

    enum Kind: Equatable { case todo, event, deadline, job, routine }

    /// How a planned thing stands. `part`: under way (a job still running, a meeting going on). `moved`: put off until
    /// tomorrow from this list.
    enum State: Equatable { case done, part, none, moved }

    /// One thing planned for today.
    struct Item: Equatable, Identifiable {
        let id: String
        let title: String
        let kind: Kind
        let state: State
        /// The reminder behind a to-do (its id in Reminders).
        var todo: String? = nil
        /// Why it didn't finish, for the row's tooltip (a failed job's reason).
        var note: String? = nil

        var mark: Mark { state == .done ? .done : state == .part ? .part : .none }
        /// 내일로 넘기기 shows: an open to-do, which is his to move with one press. An event or a routine never has it.
        var pushes: Bool { todo != nil && state == .none }
    }

    /// Something that waits for the user's answer. `card`: the 확인 대기 card 보기 brings back; nil while it is on its way.
    struct Waiting: Equatable, Identifiable {
        let id: String
        let title: String
        var card: String? = nil
    }

    /// One of tomorrow's first things. `time`: its time as the UI writes it, 종일, how often it repeats, or nothing.
    struct Later: Equatable, Identifiable {
        let id: String
        let time: String
        let title: String
        let kind: Kind
    }

    /// Something done today that wasn't planned (a timer, a conversion asked for on the spot), by the record's own line.
    struct Extra: Equatable, Identifiable {
        let id: String
        let title: String
    }

    struct Counts: Equatable {
        var planned = 0
        var done = 0
        /// Planned and neither done nor put off: not started, or under way.
        var left = 0
        var moved = 0
        var waiting = 0
        /// Done without having been planned.
        var extra = 0
        var tomorrow = 0
    }

    let english: Bool
    let planned: [Item]
    let waiting: [Waiting]
    /// Tomorrow's first rows; `counts.tomorrow` counts them all.
    let tomorrow: [Later]
    /// The unplanned work's first rows; `counts.extra` counts them all.
    let extras: [Extra]
    /// The activity record couldn't be read: the unplanned work is said to be missing, never told as none.
    let activityUnread: Bool
    let counts: Counts

    /// The one sentence that stands for the list: said when the user asked by voice, and the notch's answer text.
    var sentence: String { ArisDayEndCopy.sentence(counts, unread: activityUnread, english: english) }
    /// The evening chip's words, and the same without their title (the open notch's chip shows the title apart).
    var chip: String { ([ArisDayEndCopy.title(english: english)] + ArisDayEndCopy.chipCounts(counts, english: english)).joined(separator: " · ") }
    var chipDetail: String { ArisDayEndCopy.chipCounts(counts, english: english).map { "· " + $0 }.joined(separator: " ") }
    /// There is something to tell (the chip is only offered then).
    var hasNews: Bool { counts.planned > 0 || counts.extra > 0 || counts.waiting > 0 || counts.tomorrow > 0 }
    /// The 목록 row shows: there is at least one row to open.
    var hasList: Bool { hasNews || activityUnread }
    /// The small counts on the 목록 row: done, not done, waiting; none that is zero. With nothing planned, what was
    /// done anyway is the done count (as the sentence and the chip count it).
    var marks: [(mark: Mark, count: Int)] {
        let done = counts.planned > 0 ? counts.done : counts.extra
        return [(Mark.done, done), (Mark.none, counts.left), (Mark.wait, counts.waiting)].filter { $0.1 > 0 }.map { (mark: $0.0, count: $0.1) }
    }

    static func make(_ facts: ArisDayEndFacts, now: Date, calendar: Calendar = .current, english: Bool = false, locale: Locale? = nil) -> ArisDayEnd {
        let span = ArisDaySpan(now: now, calendar: calendar)
        let time = { (date: Date) in ArisUIDates.time(date, english: english, calendar: calendar, locale: locale) }
        let planned = ArisDayEndPlan.planned(facts, span: span, now: now, time: time)
        let waiting = ArisDayEndPlan.waiting(facts)
        let later = ArisDayEndPlan.tomorrow(facts, span: span, english: english, time: time)
        let extras = ArisDayEndPlan.extras(facts, span: span, now: now, planned: planned, english: english)
        let counts = Counts(planned: planned.count, done: planned.filter { $0.state == .done }.count,
                            left: planned.filter { $0.state == .none || $0.state == .part }.count,
                            moved: planned.filter { $0.state == .moved }.count, waiting: waiting.count, extra: extras.count, tomorrow: later.count)
        return ArisDayEnd(english: english, planned: planned, waiting: waiting, tomorrow: Array(later.prefix(ArisDayEndPlan.tomorrowShown)),
                          extras: Array(extras.prefix(ArisDayEndPlan.extrasShown)), activityUnread: facts.activity == nil, counts: counts)
    }

    /// One line of at most `limit` letters, ending in "…" when it was cut.
    static func short(_ text: String, limit: Int = 80) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard flat.count > limit else { return flat }
        return flat.prefix(limit - 1).trimmingCharacters(in: .whitespaces) + "…"
    }
}
