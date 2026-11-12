//
//  ArisEventKitSource.swift
//  Aris
//
//  The calendar store's EventKit side: access, calendars, and events / reminders turned into Aris's plain values.
//  Nothing of EventKit is called on the main actor: the EKEventStore belongs to ArisCalendarReader, an actor on a
//  serial queue of its own, and the source the store talks to only passes questions on and waits for the values.
//  (Listing the calendars used to be asked on the main thread at every reload; EventKit's calls block, at times for
//  seconds, and with them everything else that answers on the main actor. ArisReminderStore is the same shape for
//  Reminders.)
//

import AppKit
import EventKit
import Foundation

@MainActor
final class ArisEventKitSource: ArisCalendarSource {
    private let reader = ArisCalendarReader()

    func authorization(for type: EKEntityType) -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: type)
    }

    func requestFullAccess(to type: EKEntityType) async -> Bool { await reader.requestFullAccess(to: type) }

    func calendars(for type: EKEntityType) async -> [ArisCalendarInfo] { await reader.calendars(for: type) }

    func events(from start: Date, to end: Date, calendars ids: [String]) async -> [ArisCalendarEvent] {
        await reader.events(from: start, to: end, calendars: ids)
    }

    func reminders(from start: Date, to end: Date, lists ids: [String]) async -> [ArisCalendarEvent] {
        await reader.reminders(from: start, to: end, lists: ids)
    }

    // MARK: Converting

    nonisolated static func info(_ calendar: EKCalendar) -> ArisCalendarInfo {
        ArisCalendarInfo(id: calendar.calendarIdentifier,
                         account: ArisCalendarInfo.account(sourceType: calendar.source?.sourceType, calendarType: calendar.type,
                                                           title: calendar.source?.title),
                         title: calendar.title,
                         color: calendar.cgColor.flatMap { NSColor(cgColor: $0) } ?? .systemGray,
                         isSubscribed: calendar.type == .subscription,
                         isReminderList: calendar.allowedEntityTypes.contains(.reminder))
    }

    nonisolated static func attendance(_ status: EKParticipantStatus) -> ArisAttendance {
        switch status {
        case .accepted: .accepted
        case .tentative: .maybe
        case .pending: .pending
        case .declined: .declined
        default: .unknown
        }
    }

    nonisolated static func event(_ event: EKEvent) -> ArisCalendarEvent {
        let organizer = event.organizer
        var participants = (event.attendees ?? []).map { person in
            ArisParticipant(name: ArisParticipant.displayName(name: person.name, address: person.url),
                            attendance: attendance(person.participantStatus),
                            isOrganizer: organizer.map { person.url == $0.url } ?? false, isCurrentUser: person.isCurrentUser)
        }
        // The organizer is often missing from the attendee list; they still take part.
        if let organizer, !participants.contains(where: \.isOrganizer) {
            participants.insert(ArisParticipant(name: ArisParticipant.displayName(name: organizer.name, address: organizer.url),
                                                attendance: .accepted, isOrganizer: true, isCurrentUser: organizer.isCurrentUser), at: 0)
        }
        let kind: ArisEventKind
        if event.birthdayContactIdentifier != nil {
            kind = .birthday
        } else {
            kind = .event(participants.first(where: \.isCurrentUser)?.attendance ?? .unknown)
        }
        return ArisCalendarEvent(
            id: event.calendarItemIdentifier, start: event.startDate, end: event.endDate, title: event.title ?? "", location: event.location, notes: event.notes,
            url: event.url,
            isAllDay: event.isAllDay || ArisCalendarEvent.spansWholeDays(start: event.startDate, end: event.endDate),
            kind: kind, calendar: info(event.calendar), participants: participants, timeZone: event.timeZone,
            hasRecurrence: event.hasRecurrenceRules, isDetached: event.isDetached, priority: nil,
            meetingLink: ArisMeetingLink.find(url: event.url, location: event.location, notes: event.notes))
    }

    /// A reminder due inside the range, as an event; nil when it has no due date or is due outside.
    nonisolated static func reminder(_ reminder: EKReminder, from start: Date, to end: Date) -> ArisCalendarEvent? {
        guard let due = reminder.dueDateComponents,
              let when = ArisReminderDate.resolve(due, fallback: reminder.timeZone ?? .current),
              ArisReminderDate.isDue(when.start, from: start, to: end) else { return nil }
        return ArisCalendarEvent(
            id: reminder.calendarItemIdentifier, start: when.start, end: when.end, title: reminder.title ?? "",
            location: reminder.location, notes: reminder.notes, url: reminder.url, isAllDay: when.allDay,
            kind: .reminder(completed: reminder.isCompleted), calendar: info(reminder.calendar), participants: [],
            timeZone: due.timeZone ?? reminder.timeZone, hasRecurrence: reminder.hasRecurrenceRules, isDetached: false,
            priority: reminder.priority, meetingLink: ArisMeetingLink.find(url: reminder.url, location: reminder.location, notes: reminder.notes))
    }
}

/// The one owner of the calendar store's EKEventStore, off the main actor: every EventKit call for the calendar tab,
/// the brief, the widgets and the AI's context is made here, on a serial queue of its own. Only values leave it.
actor ArisCalendarReader {
    private let queue = DispatchSerialQueue(label: "com.lumenjsn.aris.calendar", qos: .userInitiated)
    /// Every call runs on that queue, never on the main thread and never on the shared pool (the calls block).
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    private let store = EKEventStore()

    func requestFullAccess(to type: EKEntityType) async -> Bool {
        do {
            return type == .reminder ? try await store.requestFullAccessToReminders() : try await store.requestFullAccessToEvents()
        } catch {
            return false
        }
    }

    func calendars(for type: EKEntityType) -> [ArisCalendarInfo] {
        store.calendars(for: type).map(ArisEventKitSource.info)
    }

    func events(from start: Date, to end: Date, calendars ids: [String]) -> [ArisCalendarEvent] {
        let wanted = Set(ids)
        let calendars = store.calendars(for: .event).filter { wanted.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate).map(ArisEventKitSource.event)
    }

    func reminders(from start: Date, to end: Date, lists ids: [String]) async -> [ArisCalendarEvent] {
        let wanted = Set(ids)
        let lists = store.calendars(for: .reminder).filter { wanted.contains($0.calendarIdentifier) }
        guard !lists.isEmpty else { return [] }
        let predicate = store.predicateForReminders(in: lists)
        // Turned into values inside EventKit's callback, so no EKReminder leaves its thread.
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let found = (reminders ?? []).compactMap { ArisEventKitSource.reminder($0, from: start, to: end) }
                continuation.resume(returning: found)
            }
        }
    }
}
