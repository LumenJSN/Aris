//
//  ArisController+Brief.swift
//  Aris
//
//  The morning brief (ArisBrief): at the day's first unlock, or on "브리핑 해줘", the notch opens on three
//  tiles (weather, the next event, the soonest Canvas deadline) for a few seconds. Nothing is said out loud,
//  so music and calls carry on.
//

import Defaults
import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "brief")

extension ArisController {
    /// How long the tiles stay up before the notch is let go (hovering keeps it open longer).
    static let briefHold: Duration = .seconds(10)
    private static let lastBriefKey = "arisLastBrief"

    /// The day's first unlock brings the brief.
    func watchForBrief() {
        DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, ArisBrief.isDue(last: UserDefaults.standard.object(forKey: Self.lastBriefKey) as? Date, now: .now) else { return }
                Task { await self.briefOnItsOwn() }
            }
        }
    }

    private func briefOnItsOwn() async {
        // A moment for the desktop to come back first.
        try? await Task.sleep(for: .seconds(1.5))
        guard session.phase == .idle, training == nil else { return }
        UserDefaults.standard.set(Date(), forKey: Self.lastBriefKey)
        turn = Task {
            guard await showBrief(inTurn: false) != nil else { return }
            remember(ArisHistoryEntry(date: Date(), heard: ArisBrief.name(english: ArisUILanguage.english), reply: ArisBrief.remembered(english: ArisUILanguage.english)))
            guard !Task.isCancelled, brief != nil else { return }
            session = session.done()
        }
    }

    /// Something Aris tells you unasked (a timer ran out): shown in the notch for a few seconds, not said aloud.
    /// It is in the 기록 list at once, whatever Aris is doing; the notch line waits its turn for a pause, as a job's
    /// result does, so a timer that ends mid-turn is still told (audit imp-5: only the chimes played then).
    func announce(title: String, text: String, hold: Duration = .seconds(4)) {
        remember(ArisHistoryEntry(date: Date(), heard: title, reply: text))
        let asked = ContinuousClock.now
        Task {
            _ = await announce {
                // Idle again here (the pause rule); news that waited too long stays in the 기록 list only.
                guard session.phase == .idle, training == nil, ArisTimerNews.shows(waited: ContinuousClock.now - asked) else { return }
                announcing = title
                session = ArisSession.announcing(title, text)
                turn = Task {
                    try? await Task.sleep(for: hold)
                    guard !Task.isCancelled, session.phase == .speaking, session.question == nil else { return }
                    session = session.done()
                }
            }
        }
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
        session = inTurn ? session.answering(made.summary) : ArisSession.announcing(ArisBrief.name(english: ArisUILanguage.english), made.summary)
        try? await Task.sleep(for: Self.briefHold)
        return Task.isCancelled ? nil : made.summary
    }
}
