//
//  ArisRemindersAccess.swift
//  Aris
//
//  Whether Aris may use Reminders, decided from what macOS says now and never from what was read earlier (third VM
//  run, new install, bug 2: after the first-ever "Allow" the running app went on saying "Aris can't use Reminders yet"
//  to "Try again", to the same words typed again and to "show my to-do list", until it was restarted). Three things
//  can keep a running app from seeing a grant: a status kept from before, an event store made before the grant (a
//  known EventKit behaviour: it may have to be replaced), and a process that still reads "not asked yet" although
//  macOS's own prompt was answered in this very run. Each has its rule here. Foundation only, so it is tested.
//

import Foundation

enum ArisRemindersAccess {
    /// macOS's answer for Reminders, in plain cases.
    enum Status: Equatable {
        case notAsked, denied, restricted, writeOnly, full
    }

    /// Whether Reminders may be used. `grantedByRequest`: macOS's own prompt came back with a yes in this run of the
    /// app; that yes counts while the status still reads "not asked yet" (a status that says no is always a no).
    static func allowed(status: Status, grantedByRequest: Bool) -> Bool {
        status == .full || (grantedByRequest && status == .notAsked)
    }

    /// A fresh read against what was known: the event store is made anew when access has just turned on (one made
    /// before the grant may not see the lists), and the lists are read again whenever the answer changed.
    static func seen(known: Status, fresh: Status) -> (newStore: Bool, reload: Bool) {
        (fresh == .full && known != .full, fresh != known)
    }

    /// A request was just refused for want of access: whether macOS is asked again first. Only when its prompt was
    /// already answered in this run and this process still reads "not asked yet": macOS has the answer, so it shows
    /// nothing a second time and only tells this process what the answer was. Never for a fresh "not asked yet" that
    /// nobody answered (that prompt belongs to the button), and never after a no.
    static func asksAgain(fresh: Status, answeredThisRun: Bool) -> Bool {
        fresh == .notAsked && answeredThisRun
    }
}
