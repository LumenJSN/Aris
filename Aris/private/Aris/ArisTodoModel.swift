//
//  ArisTodoModel.swift
//  Aris
//
//  The 할 일 tab's data (Apple Reminders through ArisReminders; Canvas deadlines through aris-agent) and the deadline alerts: every few minutes the Canvas
//  deadlines are checked, and one coming up in 24 hours (blue) or 3 hours (red) drops a card under the closed
//  notch for a few seconds, once each.
//

import AppKit
import Combine
import SwiftUI
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "todo")

@MainActor
final class ArisTodoModel: ObservableObject {
    static let shared = ArisTodoModel()

    /// Incomplete reminders of the included lists (ArisReminders).
    @Published private(set) var items: [ArisTodoItem] = []
    @Published private(set) var due: [ArisDue] = []
    /// The composer in the panel: nil closed, "" a new item, else the id of the one being edited.
    @Published var composing: String?
    /// A composer step for the preview harness ("date", "settitle=…", "submit"…), run by the composer itself.
    @Published var chipRequest: String?
    /// A row to tick (the preview's way of pressing its ring).
    @Published var completeRequest: String?
    /// The deadline alert showing under the closed notch.
    @Published private(set) var alert: (due: ArisDue, kind: ArisDueAlert)?

    private static let checkEvery: Duration = .seconds(300)
    private static let alertShowsFor: Duration = .seconds(8)
    private static let shownKey = "arisDueAlertsShown"
    private static let importedKey = "arisTodosImportedToReminders"
    private var watching: Task<Void, Never>?
    private var mirror: AnyCancellable?
    private var legacy: [ArisTodo] = []

    private var reminders: ArisReminders { .shared }
    /// The side panels' demo (ArisSideDemo): while on, the rows are its samples and nothing real is read or written.
    private var demo: ArisSideDemo { .shared }

    /// Reminders for the items, aris-agent only for the Canvas deadlines (and the old to-do file, imported once).
    /// During the demo nothing is read; a read already under way when it began is dropped.
    func refresh() async {
        guard !demo.isOn else { return }
        reminders.start()
        if mirror == nil {
            mirror = reminders.$items.receive(on: DispatchQueue.main).sink { [weak self] in
                guard let self, !self.demo.isOn, self.items != $0 else { return }
                self.items = $0
            }
        }
        await reminders.reload()
        guard !demo.isOn else { return }
        items = reminders.items
        if let reply = await ArisAgentClient.todos("list"), !demo.isOn {
            due = reply.due
            legacy = reply.todos.filter { !$0.done }
            await importLegacy()
        }
    }

    /// The demo went on (its samples, the composer and alert put away) or off (back to the real lists, read again).
    func demoChanged() {
        composing = nil
        alert = nil
        if let samples = demo.samples {
            items = samples.todos
            due = samples.deadlines
        } else {
            items = []
            due = []
            Task { await refresh() }
        }
    }

    /// Items of the old to-do file go into Reminders' default list, once.
    private func importLegacy() async {
        guard !demo.isOn, reminders.authorized, !UserDefaults.standard.bool(forKey: Self.importedKey) else { return }
        // Marked first: a second refresh that comes while these are being added must not add them again.
        UserDefaults.standard.set(true, forKey: Self.importedKey)
        for todo in legacy {
            var draft = ArisTodoDraft()
            draft.title = todo.text
            draft.due = todo.due
            draft.hasTime = todo.due.map { Self.hasTime($0) } ?? false
            await reminders.add(draft)
        }
    }

    /// "내일까지" gives the end of the day (23:59): a date without a time.
    static func hasTime(_ due: Date, calendar: Calendar = .current) -> Bool {
        !(calendar.component(.hour, from: due) == 23 && calendar.component(.minute, from: due) == 59)
    }

    /// A draft from what was typed or said: "내일 3시 보고서" becomes title 보고서, due tomorrow 15:00.
    /// A to-do exactly as a tool's call named it (the AI's `todo add`): its title is never read for dates, so what is
    /// stored is what the card showed; a due date comes only from `--due` (second upgrade run, bug 5).
    static func draft(title text: String) -> ArisTodoDraft {
        var draft = ArisTodoDraft()
        draft.title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.listID = ArisReminders.shared.defaultListID
        return draft
    }

    static func draft(from text: String, now: Date = .now) -> ArisTodoDraft {
        let (title, due) = ArisTodoDate.titled(text, now: now)
        var draft = ArisTodoDraft()
        draft.title = title
        draft.due = due
        draft.hasTime = due.map { hasTime($0) } ?? false
        draft.listID = ArisReminders.shared.defaultListID
        return draft
    }

    /// How a spoken "할 일 추가해 …" ended, with the saved item's id for its undo.
    enum Added: Equatable {
        case saved(title: String, id: String)
        case notSaved(ArisTodoAdded)

        /// As Aris tells it.
        var told: ArisTodoAdded {
            switch self {
            case .saved(let title, _): return .saved(title: title)
            case .notSaved(let why): return why
            }
        }
    }

    /// Adds what was said and says how it ended: never "saved" for an item Reminders did not take (audit turn-1).
    func addSaying(_ text: String) async -> Added {
        guard !demo.isOn else { return .notSaved(.demo) }
        reminders.start()
        // Read from macOS now, never from an earlier look (ArisRemindersAccess).
        guard await reminders.accessForRequest() else { return .notSaved(.noAccess) }
        let draft = Self.draft(from: text)
        guard !draft.title.isEmpty else { return .notSaved(.noTitle) }
        guard let saved = await reminders.add(draft) else { return .notSaved(.failed(why: reminders.lastError)) }
        return .saved(title: saved.title, id: saved.id)
    }

    // Reminders is changed off the main actor (ArisReminderStore), so a change is awaited; the list here follows it
    // as soon as it is back, not a hop later through the publisher.
    @discardableResult
    func add(_ draft: ArisTodoDraft) async -> Bool {
        guard !demo.isOn else { return false }
        let saved = await reminders.add(draft) != nil
        items = reminders.items
        return saved
    }
    @discardableResult
    func update(_ item: ArisTodoItem, _ draft: ArisTodoDraft) async -> Bool {
        guard !demo.isOn else { return false }
        let saved = await reminders.update(item.id, draft) != nil
        items = reminders.items
        return saved
    }
    /// A ticked item leaves the list at once (the caller may be inside withAnimation: the row animates away under
    /// the press); Reminders is told right after, and an item it would not tick comes back. During the demo a ticked
    /// or deleted sample only leaves the list in memory.
    func complete(_ item: ArisTodoItem) {
        items.removeAll { $0.id == item.id }
        guard !demo.isOn else { return }
        Task {
            _ = await reminders.complete(item.id)
            items = reminders.items
        }
    }
    @discardableResult
    func remove(_ item: ArisTodoItem) async -> Bool {
        guard !demo.isOn else { items.removeAll { $0.id == item.id }; return true }
        let removed = await reminders.remove(item.id)
        items = reminders.items
        return removed
    }

    /// "할 일 뭐 있어": the open items (with when they're due) and the Canvas deadlines, in one or two sentences.
    /// Nil when Aris may not read Reminders: a list it could not read is never told as empty (audit turn-1).
    func summary(korean: Bool) async -> String? {
        await refresh()
        var allowed = demo.isOn
        if !allowed { allowed = await reminders.accessForRequest() }
        guard allowed else { return nil }
        let open = items
        let canvas = due.prefix(3).map { $0.spoken() }
        guard korean else { return ArisTodoSpeech.line(open, korean: false) }
        var lines: [String] = []
        lines.append(ArisTodoSpeech.line(open, korean: true))
        if !canvas.isEmpty { lines.append("Canvas 마감은 \(canvas.joined(separator: ", "))예요.") }
        return lines.joined(separator: " ")
    }

    func hide(_ due: ArisDue) async {
        guard !demo.isOn else { return withAnimation(.easeInOut(duration: 0.28)) { self.due.removeAll { $0.id == due.id } } }
        if let reply = await ArisAgentClient.todos("hide", id: due.id) { withAnimation(.easeInOut(duration: 0.28)) { self.due = reply.due } }
    }

    /// What "<…> 다 했어" names: one open reminder of yours, else one Canvas deadline (which is only hidden).
    enum Finishable: Equatable {
        case reminder(ArisTodoItem)
        case deadline(ArisDue)

        /// As a card shows it. A deadline's title is other people's words: it is shown to the user, never remembered.
        var shown: String {
            switch self {
            case .reminder(let item): return item.title
            case .deadline(let due): return due.title
            }
        }
    }

    /// The open item those words name exactly (ArisTodoMatch.named): nil when they name none or several, which is
    /// the AI's to settle, or when the turn was stopped while the lists were read.
    func finishable(_ words: String) async -> Finishable? {
        if !demo.isOn { await refresh() }
        guard !Task.isCancelled else { return nil }
        if let item = ArisTodoMatch.named(words, in: items) { return .reminder(item) }
        let deadlines = due.filter { ArisTodoMatch.names(words, title: $0.title) }
        return deadlines.count == 1 ? .deadline(deadlines[0]) : nil
    }

    /// Ticks it off: what to call it in the reply and, for a reminder, its id for the activity log's undo. Nil when
    /// it could not be ticked (ArisReminders.lastError says why).
    func finish(_ found: Finishable) async -> (title: String, id: String?)? {
        switch found {
        case .reminder(let item):
            if demo.isOn {
                complete(item)
                return (item.title, nil)
            }
            guard await reminders.complete(item.id) else { return nil }
            items = reminders.items
            return (item.title, item.id)
        case .deadline(let due):
            if demo.isOn {
                await hide(due)
                return (ArisTodoList.dueTicked, nil)
            }
            guard let reply = await ArisAgentClient.todos("hide", id: due.id) else { return nil }
            self.due = reply.due
            return (ArisTodoList.dueTicked, nil)
        }
    }

    func open(_ due: ArisDue) {
        guard !demo.isOn, let link = due.url, let url = URL(string: link), url.scheme == "https" else { return }
        NSWorkspace.shared.open(url)
    }

    func dismissAlert() { alert = nil }

    /// Checks the deadlines now and every 5 minutes.
    func watchDeadlines() {
        watching?.cancel()
        watching = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                self?.alertIfDue()
                try? await Task.sleep(for: Self.checkEvery)
            }
        }
    }

    private func alertIfDue() {
        // The demo's samples never alert, and its marks of what was shown are never written.
        guard alert == nil, !demo.isOn else { return }
        var shown = Set(UserDefaults.standard.stringArray(forKey: Self.shownKey) ?? [])
        let now = Date()
        // Canvas deadlines and your own dated to-dos alike.
        let deadlines = due + items.compactMap { item in item.due.map { ArisDue(id: ArisTodoWords.ownPrefix + item.id, course: ArisTodoWords.own(), title: item.title, at: $0, url: nil) } }
        guard let (next, kind) = deadlines.lazy.compactMap({ due in ArisDueAlert.pending(for: due, now: now, shown: shown).map { (due, $0) } }).first else { return }
        shown.insert(ArisDueAlert.key(next, kind))
        // Keys of deadlines long gone are let go.
        let current = Set(deadlines.flatMap { [ArisDueAlert.key($0, .dayBefore), ArisDueAlert.key($0, .hoursBefore)] })
        UserDefaults.standard.set(Array(shown.intersection(current)), forKey: Self.shownKey)
        alert = (next, kind)
        log.notice("deadline alert: \(kind.rawValue, privacy: .public)")
        Task {
            try? await Task.sleep(for: Self.alertShowsFor)
            if alert?.due.id == next.id { alert = nil }
        }
    }
}
