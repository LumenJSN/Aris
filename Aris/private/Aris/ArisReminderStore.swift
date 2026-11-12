//
//  ArisReminderStore.swift
//  Aris
//
//  The one owner of Aris's EKEventStore for Reminders, off the main actor. Every EventKit call the 할 일 tab, the
//  local to-do turns and aris-tools' to-do route make is made here, on a serial queue of its own; ArisReminders (the
//  main actor) keeps what the views read and waits for the answers. EventKit's calls are synchronous and can take
//  seconds (a save that commits, a first look at the lists): made on the main actor they stalled the whole app for
//  2 to 3 s, and with it everything else that answers there (final check on a new Mac; the hook server's timeouts on
//  the owner's Mac).
//
//  Nothing of EventKit leaves this actor: reminders and lists go out as values (ArisTodoItem, ArisReminderList), and
//  a change comes in as a draft and an id.
//

import AppKit
import EventKit

actor ArisReminderStore {
    /// Why a change was not made.
    enum Failure: Error, Equatable, Sendable {
        /// No reminder with that id (it was removed elsewhere).
        case notFound
        /// No list to put a new item in.
        case noList
        /// The title is empty.
        case noTitle
        /// EventKit refused; its own words.
        case store(String)
    }

    /// The lists, Reminders' own default list, and the open items of the lists the tab shows.
    struct Loaded: Sendable {
        var lists: [ArisReminderList] = []
        var storeDefault: String?
        var items: [ArisTodoItem] = []
    }

    /// An item as saved, and whether its list is one the tab shows.
    struct Saved: Sendable {
        let item: ArisTodoItem
        let shown: Bool
    }

    private let queue = DispatchSerialQueue(label: "com.lumenjsn.aris.reminders", qos: .userInitiated)
    /// Every call runs on that queue, never on the main thread and never on the shared pool (the calls block).
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    /// Made anew when access turns on: a store made before the grant may not see the lists (ArisRemindersAccess).
    private var store = EKEventStore()
    private var watch: NSObjectProtocol?
    private var changed: (@Sendable () -> Void)?

    // MARK: - The store itself

    /// Calls `changed` whenever Reminders changes, from any app.
    func watch(_ changed: @escaping @Sendable () -> Void) {
        self.changed = changed
        observe()
    }

    private func observe() {
        if let watch { NotificationCenter.default.removeObserver(watch) }
        guard let changed else { return }
        watch = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: nil) { _ in changed() }
    }

    /// A new store (after access was granted), watched as the old one was.
    func replace() {
        store = EKEventStore()
        observe()
    }

    /// macOS's own request; nil when it could not be made.
    func requestAccess() async -> Bool? {
        try? await store.requestFullAccessToReminders()
    }

    // MARK: - Reading

    private func existing() -> [EKCalendar] { store.calendars(for: .reminder) }

    private func calendar(_ id: String) -> EKCalendar? { id.isEmpty ? nil : store.calendar(withIdentifier: id) }

    private func reminder(_ id: String) -> EKReminder? { store.calendarItem(withIdentifier: id) as? EKReminder }

    private func included(_ prefs: ArisReminderPrefs, among lists: [EKCalendar]) -> [String] {
        ArisReminderLists.includedIDs(prefs, existing: lists.map(\.calendarIdentifier), storeDefault: store.defaultCalendarForNewReminders()?.calendarIdentifier)
    }

    /// The reminders that match, read into values where EventKit hands them over (its own queue): no reminder
    /// object crosses from there to here.
    private func fetch<Value: Sendable>(_ predicate: NSPredicate, _ read: @escaping @Sendable ([EKReminder]) -> Value) async -> Value {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { continuation.resume(returning: read($0 ?? [])) }
        }
    }

    func load(_ prefs: ArisReminderPrefs) async -> Loaded {
        let lists = existing()
        var loaded = Loaded(lists: lists.map(Self.list), storeDefault: store.defaultCalendarForNewReminders()?.calendarIdentifier)
        let calendars = included(prefs, among: lists).compactMap(calendar)
        guard !calendars.isEmpty else { return loaded }
        loaded.items = await fetch(store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars)) { $0.map(Self.item) }
        return loaded
    }

    /// The shown lists' reminders ticked off from `from` up to `to`, each with when.
    func completed(from: Date, to: Date, prefs: ArisReminderPrefs) async -> [(item: ArisTodoItem, at: Date)] {
        let calendars = included(prefs, among: existing()).compactMap(calendar)
        guard !calendars.isEmpty else { return [] }
        return await fetch(store.predicateForCompletedReminders(withCompletionDateStarting: from, ending: to, calendars: calendars)) { found in
            found.map { (item: Self.item($0), at: $0.completionDate ?? to) }
        }
    }

    /// The reminder as a draft (its words, date and list), for a change that starts from what is there.
    func draft(of id: String) -> ArisTodoDraft? {
        reminder(id).map { ArisTodoDraft(Self.item($0)) }
    }

    /// The reminder as a draft due tomorrow at the same time of day ("내일로 미루기").
    func draftForTomorrow(of id: String, now: Date) -> ArisTodoDraft? {
        guard let reminder = reminder(id), let components = ArisReminderLists.tomorrow(reminder.dueDateComponents, now: now) else { return nil }
        var draft = ArisTodoDraft(Self.item(reminder))
        draft.due = Calendar.current.date(from: components)
        draft.hasTime = components.hour != nil
        return draft
    }

    // MARK: - Writing

    /// A new reminder in the draft's list, else the list new items go to, else Reminders' own default.
    func add(_ draft: ArisTodoDraft, prefs: ArisReminderPrefs) -> Result<Saved, Failure> {
        let lists = existing()
        let fallback = ArisReminderLists.defaultListID(prefs, existing: lists.map(\.calendarIdentifier), storeDefault: store.defaultCalendarForNewReminders()?.calendarIdentifier)
        guard let list = calendar(draft.listID) ?? calendar(fallback) ?? store.defaultCalendarForNewReminders() else { return .failure(.noList) }
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = list
        return save(reminder, draft, new: true, prefs: prefs, lists: lists)
    }

    /// Whether the list a new to-do with no list goes to (as `add` picks it) is the user's own (ArisOwnPlace: review 9, L2).
    func newItemsListIsOwn(prefs: ArisReminderPrefs) -> Bool {
        let lists = existing()
        let fallback = ArisReminderLists.defaultListID(prefs, existing: lists.map(\.calendarIdentifier), storeDefault: store.defaultCalendarForNewReminders()?.calendarIdentifier)
        guard let list = calendar(fallback) ?? store.defaultCalendarForNewReminders() else { return false }
        return ArisOwnPlace.isOwn(list)
    }

    func update(_ id: String, _ draft: ArisTodoDraft, prefs: ArisReminderPrefs) -> Result<Saved, Failure> {
        guard let reminder = reminder(id) else { return .failure(.notFound) }
        if let target = calendar(draft.listID), target.calendarIdentifier != reminder.calendar.calendarIdentifier { reminder.calendar = target }
        return save(reminder, draft, new: false, prefs: prefs, lists: existing())
    }

    private func save(_ reminder: EKReminder, _ draft: ArisTodoDraft, new: Bool, prefs: ArisReminderPrefs, lists: [EKCalendar]) -> Result<Saved, Failure> {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return .failure(.noTitle) }
        let oldDue = reminder.dueDateComponents
        reminder.title = title
        let notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        reminder.notes = notes.isEmpty ? nil : notes
        reminder.dueDateComponents = draft.due.map {
            Calendar.current.dateComponents(draft.hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day], from: $0)
        }
        if new || oldDue != reminder.dueDateComponents {
            for alarm in reminder.alarms ?? [] { reminder.removeAlarm(alarm) }
            if let due = draft.due, draft.hasTime { reminder.addAlarm(EKAlarm(absoluteDate: due)) }
        }
        do { try store.save(reminder, commit: true) } catch { return .failure(.store(error.localizedDescription)) }
        let saved = Self.item(reminder)
        return .success(Saved(item: saved, shown: included(prefs, among: lists).contains(saved.listID)))
    }

    /// Ticked (`done`) or open again. Nil when it was saved.
    func setCompleted(_ id: String, _ done: Bool) -> Failure? {
        guard let reminder = reminder(id) else { return .notFound }
        let was = reminder.isCompleted
        reminder.isCompleted = done
        do { try store.save(reminder, commit: true) } catch {
            reminder.isCompleted = was
            return .store(error.localizedDescription)
        }
        return nil
    }

    func remove(_ id: String) -> Failure? {
        guard let reminder = reminder(id) else { return .notFound }
        do { try store.remove(reminder, commit: true) } catch { return .store(error.localizedDescription) }
        return nil
    }

    // MARK: - Lists

    func createList(named title: String) -> ArisReminderList? {
        let list = EKCalendar(for: .reminder, eventStore: store)
        list.title = title
        guard let source = store.defaultCalendarForNewReminders()?.source ?? store.sources.first(where: { $0.sourceType == .local }) else { return nil }
        list.source = source
        do { try store.saveCalendar(list, commit: true) } catch { return nil }
        return Self.list(list)
    }

    /// False when there is no such list (nothing was done).
    func deleteList(_ id: String) -> Bool {
        guard let list = calendar(id) else { return false }
        try? store.removeCalendar(list, commit: true)
        return true
    }

    // MARK: - The test harness's own

    /// Every reminder (open or done) whose title starts with `prefix`, in any list, removed; how many there were.
    func purge(titlePrefix prefix: String) async -> Int {
        let ids = await fetch(store.predicateForReminders(in: nil)) { found in
            found.filter { ($0.title ?? "").hasPrefix(prefix) }.map(\.calendarItemIdentifier)
        }
        for id in ids { if let reminder = reminder(id) { try? store.remove(reminder, commit: true) } }
        return ids.count
    }

    /// Title, due, list, notes and done state of every reminder starting with `prefix`.
    func describe(titlePrefix prefix: String) async -> [String] {
        await fetch(store.predicateForReminders(in: nil)) { found in
            found.filter { ($0.title ?? "").hasPrefix(prefix) }.map { reminder -> String in
                let due = reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }.map { ISO8601DateFormatter().string(from: $0) } ?? "-"
                let time = reminder.dueDateComponents?.hour != nil ? "time" : "day"
                return "\(reminder.title ?? "")|due=\(due)|\(time)|list=\(reminder.calendar.title)|notes=\(reminder.notes ?? "-")|done=\(reminder.isCompleted)"
            }
        }
    }

    // MARK: - Values out

    private static func list(_ calendar: EKCalendar) -> ArisReminderList {
        ArisReminderList(id: calendar.calendarIdentifier, name: calendar.title, source: calendar.source?.title ?? "", colorHex: hex(calendar.cgColor))
    }

    private static func item(_ reminder: EKReminder) -> ArisTodoItem {
        let components = reminder.dueDateComponents
        let due = components.flatMap { Calendar.current.date(from: $0) }
        return ArisTodoItem(id: reminder.calendarItemIdentifier, title: reminder.title ?? "", notes: reminder.notes, due: due,
                            hasTime: components?.hour != nil, listID: reminder.calendar.calendarIdentifier, listName: reminder.calendar.title,
                            colorHex: hex(reminder.calendar.cgColor), created: reminder.creationDate)
    }

    static func hex(_ color: CGColor?) -> String {
        guard let color, let rgb = NSColor(cgColor: color)?.usingColorSpace(.sRGB) else { return "#8e8e93" }
        return String(format: "#%02x%02x%02x", Int((rgb.redComponent * 255).rounded()), Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
    }
}
