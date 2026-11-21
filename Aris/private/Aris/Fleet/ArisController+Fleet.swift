//
//  ArisController+Fleet.swift
//  Aris
//
//  The fleet's place in the app: which sessions are Aris's teammates (their job reports their news), which finishes
//  ClaudeSessionWatch already says, where the fleet's news goes (notify, which asks the interruption policy), and the
//  turn's fleet block (the context's coding-sessions lines: states and strict names only, no session's own words).
//

import Foundation

extension ArisController {
    func watchFleet() {
        let fleet = ArisFleetStore.shared
        fleet.isTeammate = { [weak self] id in self?.teammateWatch.isTeammate(session: id) ?? false }
        fleet.finishSaid = { id in ClaudeSessionWatch.shared.saysFinish(of: id) }
        fleet.announce = { [weak self] sentence, kind in
            let notice = ArisFleetStore.notice(sentence, kind: kind, english: ArisUIWords.english)
            Task { [weak self] in _ = await self?.notify(notice, saying: sentence) }
        }
        // After the teammate watch's own subscription, so a teammate's session is known as one when the fleet hears it.
        ArisWorld.shared.subscribe([.claude]) { change, _ in
            guard case .claude(let heard) = change, let event = ArisWorld.shared.lastHook else { return }
            fleet.heard(event, at: heard.at)
        }
        fleet.start()
    }

    /// The fleet block for this turn's context (ArisFleetContext): never a session's own words.
    func contextFleet() -> [String] {
        ArisFleetContext.lines(ArisFleetStore.shared.withCards(ClaudeStore.shared.approvals), now: Date(), home: UserHome.path)
    }
}
