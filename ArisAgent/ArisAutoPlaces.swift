//
//  ArisAutoPlaces.swift
//  aris-agent
//
//  Where a to-do or an event goes when the call names no list or calendar, and whether that place is the user's own
//  (security review 9, L2). A list or a calendar may be shared with his family or a team, so what an automatic pass puts
//  there is published to them: the automatic check applies to an unnamed place only when the app said, with this turn,
//  that the place is his own (ArisOwnPlace in the app: a local or iCloud one, his to change, not subscribed). Anything
//  else, or no word from the app (an older app, no Calendar or Reminders access), is today's card. The place is the
//  one the write would really use: a to-do goes to the list new to-dos go to; an event to the calendar `use-calendar`
//  saved, else Calendar's default for new events. Pure apart from `shared` and the saved choice's file.
//

import Foundation

struct ArisAutoPlaces: Equatable {
    /// The list new to-dos go to is his own.
    var list = false
    /// Calendar's default for new events is his own.
    var calendar = false
    /// The titles of his own calendars (for the one `use-calendar` saved).
    var calendars: Set<String> = []

    /// Nothing known: no unnamed place is his.
    static let unknown = ArisAutoPlaces()

    /// What the app sent with a turn (`ownPlaces`); unknown for anything else.
    init(json: Any?) {
        guard let object = json as? [String: Any] else { return }
        list = object["list"] as? Bool == true
        calendar = object["calendar"] as? Bool == true
        calendars = Set((object["calendars"] as? [Any] ?? []).compactMap { $0 as? String }.prefix(200))
    }

    init(list: Bool = false, calendar: Bool = false, calendars: Set<String> = []) {
        self.list = list
        self.calendar = calendar
        self.calendars = calendars
    }

    /// Whether the place `call` writes into without naming one is his own; true for a call that names its place (that
    /// rule is ArisAutoSend's) or that writes into no list or calendar. `saved`: the calendar `use-calendar` keeps.
    func ownsUnnamed(_ call: ArisAutoCall, saved: String?) -> Bool {
        guard ArisAutoSend.place(call) == nil else { return true }
        switch (call.kind.tool, call.kind.verb) {
        case ("todo", "add"): return list
        case ("event", "add"): return saved.map(calendars.contains) ?? calendar
        default: return true
        }
    }
}

/// The app's latest word on the user's places, set with each of its own conversation turns.
final class ArisAutoPlacesBox: @unchecked Sendable {
    static let shared = ArisAutoPlacesBox()
    private let lock = NSLock()
    private var told = ArisAutoPlaces.unknown

    func set(_ places: ArisAutoPlaces) { lock.withLock { told = places } }
    var now: ArisAutoPlaces { lock.withLock { told } }

    /// The calendar `aris-tools use-calendar` saved (aris-tools reads the same file when it adds an event).
    static func savedCalendar(_ file: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/aris/aris/calendar.json")) -> String? {
        guard let data = try? Data(contentsOf: file), let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let name = object["calendar"] as? String, !name.isEmpty else { return nil }
        return name
    }
}
