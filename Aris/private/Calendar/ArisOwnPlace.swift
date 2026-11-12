//
//  ArisOwnPlace.swift
//  Aris
//
//  Whether a calendar or a Reminders list is the user's own, for the automatic check (security review 9, L2): what an
//  automatic pass puts into a shared one is published to the people it is shared with, so the check applies only to
//  a place of his own, and every other write asks on today's card as before. EventKit on macOS does not say who a
//  calendar or a list is shared with (no sharees, no owner), so "his own" is the most it can tell: a local one, or one
//  in his iCloud account, that he may change and that is no subscription or birthday calendar. A calendar he shares
//  from iCloud (a family one) still counts as his: the limit of what EventKit says. Foundation only (tested).
//

import Foundation

enum ArisOwnPlace {
    /// Where a calendar lives.
    enum Source: Equatable {
        case local, iCloud, other
    }

    /// `plain`: a calendar of the ordinary kind (local or CalDAV), not a subscription, a birthday or an Exchange one.
    static func isOwn(source: Source, plain: Bool, subscribed: Bool, modifiable: Bool) -> Bool {
        plain && modifiable && !subscribed && source != .other
    }

    /// The source of a calendar whose account is of `type` ("local", "calDAV", …) and named `title`: only the account
    /// named iCloud is his iCloud one (another CalDAV account may be a work or a shared server's).
    static func source(type: String, title: String) -> Source {
        switch type {
        case "local": .local
        case "calDAV" where title == "iCloud": .iCloud
        default: .other
        }
    }

    /// What the app tells the helper with a turn (ArisAutoPlaces there). `calendars`: the titles of his own ones.
    static func body(list: Bool, calendar: Bool, calendars: [String]) -> [String: Any] {
        ["list": list, "calendar": calendar, "calendars": Array(calendars.prefix(200))]
    }
}
