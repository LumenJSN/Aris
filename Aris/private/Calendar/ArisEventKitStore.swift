//
//  ArisEventKitStore.swift
//  Aris
//
//  The app's own EventKit for `aris-tools event …` (ArisEventEdit's store), and POST /aris/events: the app holds the
//  Calendar grant, aris-tools never does (QA BUG-53 retest: find ran inside aris-tools, which has no grant, and the
//  brain told the user to allow one while the app already had full access).
//

import EventKit
import Foundation

final class ArisLiveEventStore: ArisEventStore, @unchecked Sendable {
    private let store = EKEventStore()

    static var granted: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    private func record(_ event: EKEvent) -> ArisEventRecord {
        ArisEventRecord(id: event.eventIdentifier ?? "", title: event.title ?? "", start: event.startDate, end: event.endDate,
                        calendar: event.calendar?.title ?? "", allDay: event.isAllDay)
    }

    /// The occurrence of event `id` that starts at `start`: looked up among the events of that minute, because the id
    /// alone gives a repeating event's first occurrence only (audit calendar-1: every other occurrence was refused as
    /// "not that event", and the first was deleted and then told as still there).
    private func occurrence(id: String, at start: Date) -> EKEvent? {
        let predicate = store.predicateForEvents(withStart: start.addingTimeInterval(-60), end: start.addingTimeInterval(60), calendars: nil)
        return store.events(matching: predicate).first { $0.eventIdentifier == id && abs($0.startDate.timeIntervalSince(start)) < 60 }
    }

    func event(id: String, at start: Date) -> ArisEventRecord? {
        store.refreshSourcesIfNecessary()
        return occurrence(id: id, at: start).map(record)
    }

    func remove(id: String, at start: Date) throws {
        guard let event = occurrence(id: id, at: start) else { throw ArisEventKitError.gone }
        try store.remove(event, span: .thisEvent, commit: true)
    }

    func move(id: String, at: Date, start: Date, end: Date, title: String?) throws -> ArisEventRecord? {
        guard let event = occurrence(id: id, at: at) else { throw ArisEventKitError.gone }
        event.startDate = start
        event.endDate = end
        if let title { event.title = title }
        try store.save(event, span: .thisEvent, commit: true)
        // The saved event itself: a moved occurrence of a repeating event is an event of its own now, with another id.
        return event.refresh() ? record(event) : nil
    }

    func events(from: Date, to: Date) -> [ArisEventRecord] {
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        return store.events(matching: predicate).filter { $0.eventIdentifier != nil }.map(record)
    }

    func event(id: String) -> ArisEventRecord? {
        // A fresh read, never the store's cached copy (the read-back must see what Calendar has now).
        store.refreshSourcesIfNecessary()
        return store.event(withIdentifier: id).map(record)
    }

    func remove(id: String) throws {
        guard let event = store.event(withIdentifier: id) else { throw ArisEventKitError.gone }
        try store.remove(event, span: .thisEvent, commit: true)
    }

    func move(id: String, start: Date, end: Date, title: String?) throws {
        guard let event = store.event(withIdentifier: id) else { throw ArisEventKitError.gone }
        event.startDate = start
        event.endDate = end
        if let title { event.title = title }
        try store.save(event, span: .thisEvent, commit: true)
    }

    /// A new event in the named calendar (or macOS's default for new events); throws only when it isn't saved.
    func add(title: String, start: Date, end: Date, calendar: String?) throws -> ArisEventRecord {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        if let calendar {
            guard let named = store.calendars(for: .event).first(where: { $0.title == calendar && $0.allowsContentModifications }) else {
                throw ArisEventKitError.noCalendar(calendar)
            }
            event.calendar = named
        } else {
            guard let fallback = store.defaultCalendarForNewEvents else { throw ArisEventKitError.noCalendar("default") }
            event.calendar = fallback
        }
        try store.save(event, span: .thisEvent, commit: true)
        var made = record(event)
        made.external = event.calendarItemExternalIdentifier
        return made
    }
}

enum ArisEventKitError: LocalizedError {
    case gone
    case noCalendar(String)

    var errorDescription: String? {
        switch self {
        case .gone: return "the event isn't there"
        case .noCalendar(let name): return "no calendar “\(name)” that can be changed"
        }
    }
}


/// POST /aris/events {op: find|delete|change|add|list, title, start, id?, to?, rename?, minutes?, calendar?, from?}: run in the app.
enum ArisEventRoute {
    /// The app may use the calendars; nothing is ever asked here (a permission belongs in onboarding or Settings).
    static func handle(_ object: [String: Any], store: @autoclosure () -> ArisEventStore = ArisLiveEventStore(),
                       granted: Bool = ArisLiveEventStore.granted, add: ((String, Date, Date, String?) throws -> ArisEventRecord)? = nil) -> Data {
        guard granted else { return reply(ok: false, line: noAccessLine, noAccess: true) }
        let store = store()
        // Never cut: a title or rename longer than the card can honestly show is refused, not shortened.
        let title = object["title"] as? String ?? ""
        guard title.count <= 200, (object["rename"] as? String).map({ $0.count <= 200 }) ?? true else {
            return reply(ok: false, line: "That title is longer than 200 characters, so nothing was done. Use a shorter one.")
        }
        // The events of some days: a read, with days of its own (`from`, `to`).
        if object["op"] as? String == "list" {
            guard let from = object["from"] as? String else { return reply(ok: false, line: ArisEventEdit.usage) }
            let listed = ArisEventEdit.listLine(from: from, to: object["to"] as? String, store: store)
            return reply(ok: listed.ok, line: listed.line)
        }
        let start = (object["start"] as? String).flatMap { ArisEventEdit.moment($0) }
        // A day that doesn't exist (11월 31일) is said as that; nothing is made or changed on another day instead.
        for key in ["start", "to"] {
            if let text = object[key] as? String, let why = ArisEventEdit.noSuchDay(text) { return reply(ok: false, line: why) }
        }
        let result: (ok: Bool, line: String)
        switch object["op"] as? String {
        case "find":
            guard let start, !title.isEmpty else { return reply(ok: false, line: ArisEventEdit.usage) }
            result = ArisEventEdit.findLine(title: title, start: start, store: store)
        case "delete":
            guard let start, let id = object["id"] as? String, !title.isEmpty else { return reply(ok: false, line: ArisEventEdit.usage) }
            result = ArisEventEdit.delete(id: id, title: title, start: start, store: store)
        case "change":
            guard let start, let id = object["id"] as? String, !title.isEmpty else { return reply(ok: false, line: ArisEventEdit.usage) }
            let to = (object["to"] as? String).flatMap { ArisEventEdit.moment($0) }
            result = ArisEventEdit.change(id: id, title: title, start: start, to: to, rename: object["rename"] as? String, store: store)
        case "add":
            guard let start, !title.isEmpty else { return reply(ok: false, line: ArisEventEdit.usage) }
            // The length asked for, never cut (audit tools-4: three days became 24 hours without a word).
            let minutes = object["minutes"] as? Int ?? 60
            guard ArisEventEdit.lengths.contains(minutes) else {
                return reply(ok: false, line: "An event is from 5 minutes to 31 days long, not \(minutes) minutes. Nothing was added.")
            }
            let calendar = object["calendar"] as? String
            let save = add ?? { title, begin, end, calendar in
                guard let live = store as? ArisLiveEventStore else { throw ArisEventKitError.noCalendar("default") }
                return try live.add(title: title, start: begin, end: end, calendar: calendar)
            }
            let added = ArisEventEdit.add(title: title, start: start, store: store) { try save(title, start, start.addingTimeInterval(TimeInterval(minutes * 60)), calendar) }
            var body: [String: Any] = ["ok": added.ok, "line": added.line]
            if let made = added.made { body["id"] = made.id; body["uid"] = made.external ?? ""; body["calendar"] = made.calendar }
            return (try? JSONSerialization.data(withJSONObject: body)) ?? Data("{}".utf8)
        default:
            return reply(ok: false, line: ArisEventEdit.usage)
        }
        return reply(ok: result.ok, line: result.line)
    }

    /// The fixed line when the app has no Calendar grant: it names the process, and nothing else is to be guessed.
    static let noAccessLine = "The Aris app has no full access to Calendars, so nothing was found or changed. Tell the user exactly this: Aris (the app) " +
        "needs Calendars turned on in System Settings → Privacy & Security → Calendars. " +
        "Never mention aris-tools or any other program."

    static func reply(ok: Bool, line: String, noAccess: Bool = false) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["ok": ok, "line": line, "noAccess": noAccess])) ?? Data("{}".utf8)
    }
}
