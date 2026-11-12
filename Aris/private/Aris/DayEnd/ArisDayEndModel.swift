//
//  ArisDayEndModel.swift
//  Aris
//
//  The day-end summary (ArisDayEnd) as the notch holds it: the facts gathered from where the app already keeps them
//  (the 할 일 tab's reminders and deadlines and the ones ticked off today, the 캘린더 tab's events, the jobs and the 기록
//  list, the 확인 대기 cards, the agent's schedules, and the 한 일 tab's activity record), the list under its sentence,
//  what a press on it does (목록 opens and folds, 내일로 넘기기 puts a to-do off: ArisDayEndPush), and the evening
//  offer: once the user is at the Mac after six, a chip hangs under the closed notch for a few seconds and then waits in
//  the open notch until he opens it or the day ends. Nothing is said aloud and no window opens for the offer.
//

import AppKit
import Combine
import Defaults
import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "dayend")

extension Defaults.Keys {
    /// The evening chip that offers the day-end summary (ArisDayEndSetting); the summary itself can always be asked for.
    static let arisDayEndOffer = Key<Bool>("arisDayEndOffer", default: true)
}

@MainActor
final class ArisDayEndModel: ObservableObject {
    static let shared = ArisDayEndModel()

    /// The summary on screen, or parked behind the notch until the next answer.
    @Published private(set) var card: ArisDayEnd?
    /// 목록 is open (remembered for the day: ArisDayEndKept).
    @Published private(set) var open = false
    /// The rows whose 내일로 넘기기 didn't go through: they say so until the list is made again.
    @Published private(set) var notPushed: Set<String> = []
    /// The evening's offer, until the user opens it or its day ends.
    @Published private(set) var offer: ArisDayEnd?
    /// The offer's chip hangs under the closed notch now.
    @Published private(set) var peeking = false
    /// The pointer is on that chip (it stays while it is).
    var chipHovered = false
    /// The chip was clicked and its card is on the way: a second click does nothing.
    var opening = false

    private static let lastShownKey = "arisLastDayEnd"
    private static let keptKey = "arisDayEndKept"
    private var offerDay: Date?
    private var watching: Task<Void, Never>?
    /// The sentence the list came up under (the notch's answer, as it was said): the list shows only under it.
    private var said = ""
    /// What the card on screen was made from, and when, so a press makes it again without reading everything anew.
    private var facts: ArisDayEndFacts?
    private var madeAt = Date()
    private var todosWatch: AnyCancellable?

    private init() {}

    /// When a summary last showed, asked for or opened from the chip.
    private(set) var lastShown: Date? {
        get { UserDefaults.standard.object(forKey: Self.lastShownKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastShownKey) }
    }

    /// What the list remembers for the day `now` belongs to; another day's is forgotten.
    private func kept(now: Date) -> ArisDayEndKept {
        ArisDayEndKept.current(UserDefaults.standard.data(forKey: Self.keptKey), day: ArisDaySpan(now: now).today)
    }

    private func keep(_ kept: ArisDayEndKept) {
        UserDefaults.standard.set(kept.stored, forKey: Self.keptKey)
    }

    // MARK: - The list

    /// The list to draw for `session`: while its sentence is the notch's answer (said, or parked after), never over a
    /// question.
    func shown(for session: ArisSession) -> ArisDayEnd? {
        guard let card, isLine(session.reply), session.question == nil, session.phase == .speaking || session.phase == .idle else { return nil }
        return card
    }

    /// `reply` is the list's own sentence: drawn as the plain line above it (ArisWidgetLine), as a card's line is.
    func isLine(_ reply: String) -> Bool { card != nil && !said.isEmpty && reply == said }

    /// Puts a summary up: the evening's offer is used up with it. 목록 is as he left it today.
    func show(_ made: Made) {
        card = made.summary
        said = made.summary.sentence
        facts = made.facts
        madeAt = made.at
        open = kept(now: made.at).open
        notPushed = []
        lastShown = Date()
        offer = nil
        peeking = false
        opening = false
        watchTodos()
    }

    /// A summary with what it was made from.
    struct Made {
        let summary: ArisDayEnd
        let facts: ArisDayEndFacts
        let at: Date
    }

    /// Today's summary, from the facts as they are now.
    func compose(english: Bool, now: Date = Date()) async -> Made {
        let facts = await gather(now: now)
        let made = ArisDayEnd.make(facts, now: now, english: english)
        let read = facts.activity == nil ? ", activity unread" : ""
        log.notice("day end: \(made.counts.planned, privacy: .public) planned, \(made.counts.done, privacy: .public) done, \(made.counts.waiting, privacy: .public) waiting, \(made.counts.tomorrow, privacy: .public) for tomorrow\(read, privacy: .public)")
        return Made(summary: made, facts: facts, at: now)
    }

    /// 목록 was pressed: it opens or folds, and stays that way for the day.
    func toggle() {
        open.toggle()
        keep(kept(now: madeAt).opened(open))
    }

    /// 내일로 넘기기 on a to-do's row: its due date moves to tomorrow (ArisDayEndPush), the change goes in the activity
    /// record with its undo, and the receipt under the answer says so. One that couldn't be moved says so on its row.
    func push(_ item: ArisDayEnd.Item) {
        let todos = ArisTodoModel.shared
        guard item.pushes, let id = item.todo, let todo = todos.items.first(where: { $0.id == id }) else {
            notPushed.insert(item.id)
            return
        }
        var draft = ArisTodoDraft(todo)
        draft.due = ArisDayEndPush.due(after: todo.due, hasTime: todo.hasTime, tomorrow: ArisDaySpan(now: madeAt).tomorrow)
        // The receipt counts from this press, as it does from a turn's first word: the press is the user's own act.
        ArisReceiptModel.shared.turnBegan()
        keep(kept(now: madeAt).moving(id))
        // Reminders is changed off the main actor: the row follows when the change is back.
        Task {
            guard await todos.update(todo, draft) else {
                log.error("day end: a to-do couldn't be moved to tomorrow")
                notPushed.insert(item.id)
                return remake()
            }
            log.notice("day end: a to-do moved to tomorrow")
            ArisAgentClient.logLocalChange(kind: ArisDayEndPush.logKind, summary: ArisDayEndPush.logLine(todo.title), id: id,
                                           due: (todo.due ?? ArisDaySpan(now: madeAt).today).timeIntervalSince1970, timed: todo.hasTime)
            remake()
        }
    }

    /// The to-dos changed while the list is up (a press here, its undo, Reminders itself): the list is made again
    /// from them, and a to-do whose move was undone is an open row again.
    private func watchTodos() {
        guard todosWatch == nil else { return }
        todosWatch = ArisTodoModel.shared.$items.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.remake() }
        }
    }

    private func remake() {
        guard let card, var facts else { return }
        let span = ArisDaySpan(now: madeAt)
        facts.todos = Self.todos(open: ArisTodoModel.shared.items) + facts.todos.filter { $0.completed != nil }
        let settled = kept(now: madeAt).settled(open: facts.todos, tomorrow: span.tomorrow)
        keep(settled)
        facts.moved = Set(settled.moved)
        self.facts = facts
        let made = ArisDayEnd.make(facts, now: madeAt, english: card.english)
        if made != card { self.card = made }
    }

    // MARK: - The facts

    private static func todos(open items: [ArisTodoItem]) -> [ArisDayEndFacts.Todo] {
        items.map { ArisDayEndFacts.Todo(id: $0.id, title: $0.title, due: $0.due, hasTime: $0.hasTime) }
    }

    private func gather(now: Date) async -> ArisDayEndFacts {
        let span = ArisDaySpan(now: now)
        let todos = ArisTodoModel.shared
        var facts = ArisDayEndFacts()
        // The 할 일 tab's rows as it holds them (kept fresh every few minutes; the demo's samples while it is on).
        facts.todos = Self.todos(open: todos.items)
        facts.deadlines = todos.due.map { ArisDayEndFacts.Deadline(course: $0.course, title: $0.title, at: $0.at) }
        facts.moved = Set(kept(now: now).moved)
        // The side panels' demo shows samples only: nothing of the user's own is read into a recording.
        if let samples = ArisSideDemo.shared.samples {
            facts.activity = samples.activity
            facts.events = samples.events.filter(\.kind.isEvent).map { ArisDayEndFacts.Event(start: $0.start, end: $0.end, title: $0.title, allDay: $0.isAllDay) }
            return facts
        }
        // Past midnight the day being wrapped up began yesterday: the whole record is asked for and cut to the day here.
        async let activity = ArisAgentClient.activity(today: Calendar.current.isDate(span.today, inSameDayAs: now))
        async let schedules = ArisAgentClient.dayEndSchedules(span, now: now)
        // The to-dos ticked off today, by the user or by Aris: Reminders knows both.
        let ticked = await ArisReminders.shared.completed(from: span.today, to: max(now, span.tomorrow)) ?? []
        facts.todos += ticked.map { ArisDayEndFacts.Todo(id: $0.item.id, title: $0.item.title, due: $0.item.due, hasTime: $0.item.hasTime, completed: $0.at) }
        // Events only: a reminder with a date is one of the to-dos above.
        let events = await ArisCalendarStore.shared.events(from: span.today, to: span.afterTomorrow).filter(\.kind.isEvent)
        // One that began earlier and runs into tomorrow (a trip, a conference) is tomorrow's from its first minute.
        facts.events = events.map { event in
            let runsOn = event.start < span.tomorrow && event.end > span.tomorrow && (event.isAllDay || event.start < span.today)
            return ArisDayEndFacts.Event(start: runsOn ? span.tomorrow : event.start, end: event.end, title: event.title, allDay: event.isAllDay)
        }
        facts.activity = await activity
        let read = await schedules
        facts.schedules = read?.tomorrow ?? []
        facts.routines = read?.today ?? []
        let aris = ArisController.shared
        let waiting = ArisCardDesk.shared.waiting.cards
        facts.cards = waiting.map { ArisDayEndFacts.Card(id: $0.id, title: $0.title, action: $0.action) }
        facts.jobs = ArisDayEndJobs.facts(jobs: aris.jobs, parked: Set(waiting.map(\.id)), history: aris.pastTurns, span: span, now: now)
        return facts
    }

    // MARK: - The evening offer

    /// The offer still stands: made this evening, not opened yet, and the setting still on.
    var offerWaits: Bool {
        guard offer != nil, let offerDay, Defaults[.arisDayEndOffer] else { return false }
        return offerDay == ArisDaySpan(now: Date()).today
    }

    /// Looks at the evening from now on (called once, at launch).
    func watch() {
        guard watching == nil else { return }
        watching = Task { [weak self] in
            var quiet = false
            while !Task.isCancelled {
                let wait = ArisDayEndOffer.nextCheck(after: Date(), lastShown: self?.lastShown, quiet: quiet)
                try? await Task.sleep(for: .seconds(wait))
                guard let self, !Task.isCancelled else { return }
                // Yesterday's offer never outlives its day.
                if self.offer != nil, !self.offerWaits { self.offer = nil }
                quiet = await self.offerIfDue()
            }
        }
    }

    /// Offers the chip when its moment has come. True when the moment came with nothing to tell (looked at again later).
    private func offerIfDue() async -> Bool {
        guard offer == nil, isDue() else { return false }
        let made = await compose(english: ArisUILanguage.english).summary
        guard made.hasNews else { return true }
        // The user started something while the facts were read: the next look offers it.
        guard isDue() else { return false }
        log.notice("day end: offered")
        offer = made
        offerDay = ArisDaySpan(now: Date()).today
        lastShown = Date()
        peek()
        return false
    }

    private func isDue() -> Bool {
        let aris = ArisController.shared
        return ArisDayEndOffer.isDue(enabled: Defaults[.arisDayEndOffer], lastShown: lastShown, now: Date(), idle: Self.idleSeconds())
            && !aris.screenAway && aris.session.phase == .idle && aris.training == nil && !ArisSideDemo.shared.isOn
    }

    /// The chip hangs under the closed notch for a few seconds (longer while the pointer is on it), then steps back.
    private func peek() {
        peeking = true
        Task { [weak self] in
            repeat {
                try? await Task.sleep(for: ArisDayEndOffer.chipShows)
            } while self?.chipHovered == true
            self?.peeking = false
        }
    }

    /// Seconds since the user last touched the keyboard, the mouse or the trackpad.
    private static func idleSeconds() -> TimeInterval {
        let kinds: [CGEventType] = [.keyDown, .mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel, .leftMouseDragged]
        return kinds.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? .infinity
    }
}
