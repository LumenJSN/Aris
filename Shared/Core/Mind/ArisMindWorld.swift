//
//  ArisMindWorld.swift
//  Shared/Core (aris-agent, tests)
//
//  The World as the Mind uses it (ARCHITECTURE Part 2, Mind and Judgment): the snapshot (ArisWorldSnapshot, jv-world)
//  mapped into the facts the trust gate grounds the owner's words in (ArisWorldFacts: what is in front, the contacts
//  and their addresses, the apps and their nicknames, the folders), and the small structured context a turn starts
//  with in place of the old prose catalogue: the time, what is in front, the next events, the work in progress. Only
//  what the snapshot already holds goes in; nothing private (the selection, the screen's text) is read here. Pure.
//

import Foundation

enum ArisMindWorld {
    /// The trust gate's facts from the snapshot, with what the snapshot doesn't carry (the contacts, the apps' nicknames
    /// and the owner's addresses, read where they live) and the focus object when jv-focus supplies one.
    static func facts(_ snapshot: ArisWorldSnapshot?, contacts: [ArisWorldFacts.Contact] = [], apps: [String: [String]] = [:],
                      ownerAddresses: [String] = [], focus: ArisFocusObject? = nil, home: String = NSHomeDirectory()) -> ArisWorldFacts {
        var known = apps
        let front = snapshot?.frontApp?.name.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        if let front, known[front] == nil { known[front] = [] }
        return ArisWorldFacts(contacts: contacts, apps: known, frontApp: front, focus: focus, ownerAddresses: ownerAddresses, home: home)
    }

    /// How long the app's word on what is in front counts when the helper can't read it itself.
    static let appFrontFresh: TimeInterval = 120

    /// The trust gate's facts from what the helper reads itself (`live`: the app in front, from the window server) and
    /// the app's World of its last turn (`app`, from `appAt`): the contacts and the apps' nicknames are the app's; what is
    /// in front is the helper's own reading, else the app's while it is fresh.
    static func facts(live: ArisWorldSnapshot?, app: ArisWorldWire.Payload?, appAt: Date?, now: Date, home: String = NSHomeDirectory()) -> ArisWorldFacts {
        var snapshot = live ?? ArisWorldSnapshot()
        if snapshot.frontApp?.name == nil, let app, let at = appAt, now.timeIntervalSince(at) <= appFrontFresh, let name = app.frontApp {
            snapshot.frontApp = .init(name: name, bundleID: app.frontBundle, pid: 0)
        }
        return facts(snapshot, contacts: app?.contacts ?? [], apps: app?.apps ?? [:], home: home)
    }

    /// `facts` with the turn's focus laid over it (the focus desk's facts, jv-focus): its focus object, and the app it
    /// is in as what is in front (the owner pointed there with this turn). No focus: `facts` unchanged.
    static func facts(_ facts: ArisWorldFacts, focus: ArisWorldFacts) -> ArisWorldFacts {
        guard let object = focus.focus else { return facts }
        var merged = facts
        merged.focus = object
        if let app = focus.frontApp {
            merged.frontApp = app
            if merged.apps[app] == nil { merged.apps[app] = [] }
        }
        return merged
    }

    /// The context block a turn starts with: short lines. `work`: the work-in-progress block (ArisWorkInProgress, no
    /// outside text by its own rule); `memory`: facts the owner told Aris.
    static func context(_ snapshot: ArisWorldSnapshot?, now: Date, work: String? = nil, memory: [String] = [], timeZone: TimeZone = .current) -> String {
        var lines: [String] = []
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd EEE HH:mm"
        lines.append("Now: " + formatter.string(from: now))
        if let snapshot {
            // The app's name only: a window's title or an event's title can be others' words (an invite, a page), and
            // what others wrote reaches the model only as a tool result the provenance tracker sees.
            if let front = snapshot.frontApp?.name { lines.append("In front: " + clean(front, 60)) }
            if snapshot.screenAway { lines.append("The screen is locked or asleep: the owner may not see it.") }
            if snapshot.otherAppRecording != nil { lines.append("Another app is using the microphone (a call, likely): keep it short.") }
            if let next = snapshot.nextEvents.filter({ $0.end > now }).min(by: { $0.start < $1.start }) {
                lines.append("Next calendar event: " + formatter.string(from: next.start) + " (its details: list_events)")
            }
            if snapshot.runningJobs > 0 { lines.append("Background tasks running: \(snapshot.runningJobs)") }
        }
        if let work, !work.isEmpty { lines.append(work) }
        for fact in memory.prefix(8) { lines.append("Remembered: " + clean(fact, 160)) }
        return lines.joined(separator: "\n")
    }

    /// One line, cut: no line breaks or control characters.
    static func clean(_ text: String, _ limit: Int) -> String {
        let flat = String(text.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : Character($0) })
        return flat.count > limit ? String(flat.prefix(limit - 1)) + "…" : flat
    }
}
