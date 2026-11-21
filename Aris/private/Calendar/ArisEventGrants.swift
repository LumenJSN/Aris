//
//  ArisEventGrants.swift
//  Aris
//
//  The one answer, for every part of the app, to "may Aris use Calendars (or Reminders) now". After the first-ever
//  "Allow Full Access" this process can go on reading "not asked yet" from EventKit's class status for minutes (third
//  VM run, B13; VM run 2026-11-19, A2: the calendar route said "no access" right after the yes, the permission layer
//  read the same and put up "Calendars is off", and only a try four minutes later worked). The calendar tab and
//  Reminders kept this run's yes to themselves; the route, the permission layer, the setup and the fix buttons read
//  the class status alone. Now the yes macOS's prompt gave in this run is kept here, read from any thread, and every
//  one of them reads the same merged status (ArisCalendarAccess.merged: a status that says no is always a no).
//

import EventKit
import Foundation

final class ArisEventGrants: @unchecked Sendable {
    static let shared = ArisEventGrants()

    enum Kind: Sendable { case events, reminders }

    private let lock = NSLock()
    private var granted: Set<Kind> = []

    init() {}

    /// macOS's prompt for `kind` came back in this run: a yes is kept, a no forgets an earlier yes.
    func note(_ kind: Kind, granted yes: Bool) {
        lock.withLock { if yes { granted.insert(kind) } else { granted.remove(kind) } }
    }

    /// The status as read (`read`), with this run's yes kept while the read still says "not asked yet".
    func status(_ kind: Kind, read: EKAuthorizationStatus) -> EKAuthorizationStatus {
        ArisCalendarAccess.merged(read: read, grantedByRequest: lock.withLock { granted.contains(kind) })
    }

    /// The status now: EventKit's class status, merged.
    func status(_ kind: Kind) -> EKAuthorizationStatus {
        status(kind, read: EKEventStore.authorizationStatus(for: kind == .events ? .event : .reminder))
    }

    /// Whether Aris may read and write `kind` now.
    func allowed(_ kind: Kind) -> Bool { status(kind) == .fullAccess }
}
