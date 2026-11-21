//
//  ArisController+Brief.swift
//  Aris
//
//  The morning brief (ArisBrief): at the day's first unlock, or on "브리핑 해줘", the notch opens on three
//  tiles (weather, the next event, the soonest Canvas deadline) for a few seconds. Nothing is said out loud,
//  so music and calls carry on. At the unlock it opens only with something to tell, and not into a call or over
//  The user's voice (ArisBriefCheck, ArisInterruption): it waits for that moment for a while.
//

import Defaults
import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "brief")

extension ArisController {
    /// How long the tiles stay up before the notch is let go (hovering keeps it open longer).
    static let briefHold: Duration = .seconds(10)
    private static let lastBriefKey = "arisLastBrief"

    /// The day's first unlock brings the brief, when it has something to tell and the moment lets it (ArisBriefCheck).
    func watchForBrief() {
        ArisWorld.shared.subscribe([.screen]) { [weak self] change, _ in
            guard case .screenLocked(false) = change, let self,
                  ArisBrief.isDue(last: UserDefaults.standard.object(forKey: Self.lastBriefKey) as? Date, now: .now) else { return }
            Self.briefWait?.cancel()
            // It waits past any turn: it carries no turn's id.
            Self.briefWait = ArisTurnScope.outside { Task { await self.briefOnItsOwn() } }
        }
    }

    /// The brief waiting for its moment after an unlock (one at a time).
    private static var briefWait: Task<Void, Never>?

    private func briefOnItsOwn() async {
        // A moment for the desktop to come back first.
        try? await Task.sleep(for: .seconds(1.5))
        guard !Task.isCancelled, let facts = await briefFacts() else { return }
        let began = Date()
        while !Task.isCancelled {
            // A turn of the user's or a training took the notch since the unlock: the brief stays away, as before.
            guard session.phase == .idle, training == nil else { return }
            let due = ArisBrief.isDue(last: UserDefaults.standard.object(forKey: Self.lastBriefKey) as? Date, now: .now)
            switch ArisBriefCheck.step(isDue: due, facts: facts, moment: ArisWorld.shared.moment(mayMakeSound: true)) {
            case .notDue:
                return
            case .nothingToTell:
                log.notice("brief: nothing to tell today")
                UserDefaults.standard.set(Date(), forKey: Self.lastBriefKey)
                return
            case .wait(let condition):
                guard Date().timeIntervalSince(began) < ArisBriefCheck.longestWait else {
                    return log.notice("brief: no moment came (\(condition.rawValue, privacy: .public)); the next unlock tries again")
                }
                try? await Task.sleep(for: .seconds(ArisBriefCheck.recheck))
            case .show:
                UserDefaults.standard.set(Date(), forKey: Self.lastBriefKey)
                startTurn(.brief) {
                    guard await showBrief(inTurn: false) != nil else { return }
                    remember(ArisHistoryEntry(date: Date(), heard: ArisBrief.name(english: ArisUILanguage.english), reply: ArisBrief.remembered(english: ArisUILanguage.english)))
                    guard !Task.isCancelled, brief != nil else { return }
                    setSession(session.done())
                }
                return
            }
        }
    }

    /// What the brief would tell, counted; nil when neither the helper nor the calendar had anything to say about it (the
    /// helper may still be starting: the next unlock asks again).
    private func briefFacts() async -> ArisBriefCheck.Facts? {
        let agent = await ArisAgentClient.brief()
        let starts = await ArisCalendarStore.shared.upcomingEvents(days: 1).filter { !$0.isAllDay }.map(\.start)
        guard agent != nil || !starts.isEmpty else { return nil }
        return ArisBriefCheck.facts(agent: agent ?? [:], eventStarts: starts, now: .now)
    }

    /// Something Aris tells you unasked (a timer ran out): a card under the notch, not said aloud (the timer chimes on
    /// its own). It is in the 기록 list at once, whatever Aris is doing; the card waits its turn for a pause, as a job's
    /// result does, so a timer that ends mid-turn is still told (audit imp-5: only the chimes played then), and one
    /// that waited too long stays in the 기록 list only (ArisTimerNews). `kind`: its tile.
    func announce(title: String, text: String, kind: ArisNoticeKind = .system) {
        remember(ArisHistoryEntry(date: Date(), heard: title, reply: text))
        let card = kind == .reminder ? ArisNoticeRoute.timer(title: title, text: text)
            : ArisNoticeRoute.announcement(title: title, text: text, kind: kind)
        // It waits for its moment past the turn it may have come from: it carries no turn's id.
        ArisTurnScope.outside { Task { await notify(card, parking: text) } }
    }

    /// Puts the brief up and holds it; the summary line, or nil when cancelled meanwhile.
    func showBrief(inTurn: Bool) async -> String? {
        let facts = await ArisAgentClient.brief() ?? [:]
        let events = await ArisCalendarStore.shared.upcomingEvents(days: 1)
            .filter { !$0.isAllDay }
            .map { ArisBrief.Event(start: $0.start, title: $0.title) }
        guard !Task.isCancelled else { return nil }
        // English tiles when the app shows English (QA BUG-19).
        let made = ArisBrief.make(facts: facts, events: events, now: .now, english: ArisUILanguage.english)
        log.notice("brief: \(made.tiles.count, privacy: .public) tiles")
        brief = made
        setSession(inTurn ? session.answering(made.summary) : ArisSession.announcing(ArisBrief.name(english: ArisUILanguage.english), made.summary))
        try? await Task.sleep(for: Self.briefHold)
        return Task.isCancelled ? nil : made.summary
    }
}
