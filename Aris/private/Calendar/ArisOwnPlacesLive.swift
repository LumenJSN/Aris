//
//  ArisOwnPlacesLive.swift
//  Aris
//
//  Reads, for each conversation turn, whether the places an unnamed to-do or event would go into are the user's own
//  (ArisOwnPlace): Calendar's default for new events, his own calendars by title (for the one `use-calendar` saved) and
//  the list new to-dos go to. Only when access is already given; never asks. No access: nothing is his, and the
//  automatic check leaves those writes on today's card.
//

import EventKit
import Foundation

extension ArisOwnPlace {
    static func isOwn(_ calendar: EKCalendar) -> Bool {
        let type: String = switch calendar.source?.sourceType {
        case .local?: "local"
        case .calDAV?: "calDAV"
        default: "other"
        }
        return isOwn(source: source(type: type, title: calendar.source?.title ?? ""), plain: [.local, .calDAV].contains(calendar.type),
                     subscribed: calendar.isSubscribed, modifiable: calendar.allowsContentModifications)
    }
}

enum ArisOwnPlacesLive {
    /// One store, made once access is there (a store made before the grant may not see the calendars).
    private static let lock = NSLock()
    nonisolated(unsafe) private static var made: EKEventStore?

    private static func store() -> EKEventStore {
        lock.withLock {
            if let made { return made }
            let store = EKEventStore()
            made = store
            return store
        }
    }

    /// The body's `ownPlaces`, read off the main thread.
    static func current() async -> [String: Any] {
        let events = await Task.detached(priority: .userInitiated) { () -> (Bool, [String]) in
            guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return (false, []) }
            let store = store()
            let own = store.calendars(for: .event).filter(ArisOwnPlace.isOwn).map(\.title)
            return (store.defaultCalendarForNewEvents.map(ArisOwnPlace.isOwn) ?? false, own)
        }.value
        let list = await ArisReminders.shared.newItemsListIsOwn()
        return ArisOwnPlace.body(list: list, calendar: events.0, calendars: events.1)
    }
}
