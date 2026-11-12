//
//  ArisCalendarEvent.swift
//  Aris
//
//  What the side panel, the brief and the AI's context see of the calendar: plain values made from EventKit's
//  events and reminders (ArisEventKitSource does the converting).
//

import AppKit
import EventKit
import Foundation

/// A calendar or a reminder list. (NSColor is immutable here, so the value is safe to pass between threads.)
struct ArisCalendarInfo: Identifiable, Hashable, @unchecked Sendable {
    let id: String
    /// The account it belongs to (iCloud, Google, …).
    let account: String
    let title: String
    let color: NSColor
    let isSubscribed: Bool
    let isReminderList: Bool

    /// Shown under a calendar's name: the account, or "기타" (Other) for local, subscribed and birthday calendars.
    static var otherAccount: String { otherAccount(english: ArisUIWords.english) }
    static func otherAccount(english: Bool) -> String { ArisUIWords.text("기타", "Other", english: english) }

    static func account(sourceType: EKSourceType?, calendarType: EKCalendarType, title: String?) -> String {
        if [.local, .subscription, .birthday].contains(calendarType) { return otherAccount }
        if let sourceType, [.local, .subscribed, .birthdays].contains(sourceType) { return otherAccount }
        return title ?? otherAccount
    }
}

/// How the current user answered an invitation, in the order lists sort by.
enum ArisAttendance: Int, Comparable, Hashable, Sendable {
    case accepted, maybe, pending, declined, unknown

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum ArisEventKind: Hashable, Sendable {
    case event(ArisAttendance)
    case birthday
    case reminder(completed: Bool)

    var isEvent: Bool { if case .event = self { true } else { false } }
    var isBirthday: Bool { self == .birthday }
    var isReminder: Bool { if case .reminder = self { true } else { false } }
}

struct ArisParticipant: Hashable, Sendable {
    let name: String
    let attendance: ArisAttendance
    let isOrganizer: Bool
    let isCurrentUser: Bool

    /// The participant's name, else their address without the "mailto:" scheme.
    static func displayName(name: String?, address: URL) -> String {
        let shown = name.flatMap { $0.isEmpty ? nil : $0 } ?? address.absoluteString
        return shown.lowercased().hasPrefix("mailto:") ? String(shown.dropFirst("mailto:".count)) : shown
    }
}

struct ArisCalendarEvent: Identifiable, Sendable {
    enum Status { case upcoming, inProgress, ended }

    /// EventKit's calendar item identifier (a plain UUID), for events and reminders alike; Calendar.app's links
    /// open it.
    let id: String
    let start: Date
    let end: Date
    let title: String
    let location: String?
    let notes: String?
    let url: URL?
    let isAllDay: Bool
    let kind: ArisEventKind
    let calendar: ArisCalendarInfo
    let participants: [ArisParticipant]
    let timeZone: TimeZone?
    let hasRecurrence: Bool
    /// An occurrence of a repeating event that was edited on its own.
    let isDetached: Bool
    let priority: Int?
    let meetingLink: ArisMeetingLink?

    var isMeeting: Bool { !participants.isEmpty }

    func status(at now: Date) -> Status {
        if now < start { return .upcoming }
        return now < end ? .inProgress : .ended
    }

    /// Opens the item in Calendar (or Reminders). An occurrence of a repeating event (detached ones too) is named by
    /// its start, in UTC unless it's all-day.
    func calendarAppURL() -> URL? {
        guard let path = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        if kind.isReminder { return URL(string: "x-apple-reminderkit://remcdreminder/\(path)") }
        var occurrence = ""
        if hasRecurrence || isDetached {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            formatter.timeZone = isAllDay ? .current : TimeZone(identifier: "UTC")
            occurrence = "/" + formatter.string(from: start)
        }
        return URL(string: "ical://ekevent\(occurrence)/\(path)?method=show&options=more")
    }

    /// A timed event running exactly from one midnight to a later one counts as all-day.
    static func spansWholeDays(start: Date, end: Date, calendar: Calendar = .current) -> Bool {
        end > start && calendar.startOfDay(for: start) == start && calendar.startOfDay(for: end) == end
    }

    /// Events and reminders together, earliest first.
    static func merged(_ events: [ArisCalendarEvent], _ reminders: [ArisCalendarEvent]) -> [ArisCalendarEvent] {
        (events + reminders).sorted { $0.start < $1.start }
    }
}

/// When a reminder is due. A timed reminder's date components are read in their own time zone (else the
/// reminder's, else the local one); a reminder with a day but no time is all-day from local midnight. Either way
/// it is shown until the end of its start's local day.
enum ArisReminderDate {
    static func resolve(_ due: DateComponents, fallback: TimeZone,
                        local: TimeZone = .current) -> (start: Date, end: Date, allDay: Bool)? {
        guard due.year != nil, due.month != nil, due.day != nil else { return nil }
        var reading = Calendar(identifier: .gregorian)
        reading.timeZone = due.hour == nil ? local : due.timeZone ?? fallback
        var parts = due
        parts.calendar = nil
        parts.timeZone = nil
        if due.hour == nil { parts.hour = 0; parts.minute = 0; parts.second = 0 }
        guard let start = reading.date(from: parts) else { return nil }
        var day = Calendar(identifier: .gregorian)
        day.timeZone = local
        guard let end = day.dateInterval(of: .day, for: start)?.end else { return nil }
        return (start, end, due.hour == nil)
    }

    /// A reminder belongs in the window `[from, to)` when it is due inside it: one due yesterday never shows today.
    static func isDue(_ start: Date, from: Date, to: Date) -> Bool {
        start >= from && start < to
    }
}
