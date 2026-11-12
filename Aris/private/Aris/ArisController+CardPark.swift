//
//  ArisController+CardPark.swift
//  Aris
//
//  A job's or a schedule's question, asked until the user answers it (audit card-1, card-2 = team-1, imp-3). The agent holds
//  such a question for a day. Its card comes up at a pause, read aloud once. When the user's turn covers it, or nobody
//  answers before the card's limit, nothing is sent for him: the question waits in 확인 대기 (a chip in the open notch,
//  ArisWaitingCards) and comes back on his click, or by itself once more when he is clearly there (ArisParkedAsk).
//  Only his own yes or no ever reaches the agent.
//

import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "turn")

/// How a held question was settled.
enum ArisCardSettled: Equatable {
    /// The user answered, and what the agent made of it.
    case answered(ArisConfirmResult)
    /// The agent no longer waits for it (answered elsewhere, expired, or its job ended).
    case gone
    /// The agent didn't say whether it still waits: asked again later, never dropped.
    case unreachable
    /// Its job was cancelled meanwhile.
    case cancelled
}

extension ArisController {
    /// Shows the card for `ask` until it is settled. `title`: the job's or the schedule's name. `streamEnded`: the job's
    /// stream is over (its question can't be answered any more).
    func settleCard(_ ask: ArisConfirmation, title: String, job: UUID?, handsFree: Bool, streamEnded: @escaping @MainActor () -> Bool) async -> ArisCardSettled {
        let desk = ArisCardDesk.shared
        defer { desk.remove(ask.id) }
        var shows = 0
        var quiet = false
        while true {
            guard !Task.isCancelled else { return .cancelled }
            // Expired, answered, or from an earlier run of the agent: the card never shows.
            guard !streamEnded() else { return .gone }
            switch await ArisAgentClient.stillWaits(ask.id) {
            case false?:
                log.notice("a parked question is gone")
                return .gone
            case nil: return .unreachable
            case true?: break
            }
            // Asked at a pause, in its turn among Aris's other news, with the user at the Mac.
            let quietNow = quiet
            let shown: CardWait?? = await announce(present: true) {
                desk.remove(ask.id)
                return await self.speakUp(title) { await self.askCard(ask, handsFree: handsFree, agentCard: true, quiet: quietNow) }
            }
            // The job was cancelled while the user was asked: its answer goes nowhere.
            guard let shown, !Task.isCancelled else { return .cancelled }
            let why: ArisWaitingCard.Why
            if let wait = shown {
                if !quietNow { shows += 1 }
                switch ArisParkedAsk.next(wait.end) {
                case .gone: return .gone
                case .send(let allow): return .answered(await send(allow, for: ask, title: title))
                case .park(let reason): why = reason
                }
            } else {
                // A turn of the user's took the moment before the card came up.
                why = .covered
            }
            log.notice("a question waits in 확인 대기 (\(why.rawValue, privacy: .public))")
            desk.park(ArisWaitingCard(id: ask.id, title: title, action: ask.title, job: job, why: why, since: Date()))
            guard let back = await waitParked(ask.id, why: why, shows: shows, streamEnded: streamEnded) else {
                return Task.isCancelled ? .cancelled : .gone
            }
            quiet = back
        }
    }

    /// The user's answer goes to the agent; a refusal (the agent couldn't tell this was the app) is said out loud.
    private func send(_ allow: Bool, for ask: ArisConfirmation, title: String) async -> ArisConfirmResult {
        let result = await ArisAgentClient.confirm(ask.id, allow: allow, shown: ask)
        if result == .refused {
            log.error("a held question's answer was refused")
            let said = ArisConfirmResult.refusedNotice(english: ArisUIWords.english)
            _ = await speakUp(title, saying: said) { await self.speak { await self.speaker.speak(said) } }
        }
        return result
    }

    /// A parked card waits for its way back (ArisParkedAsk.returns); the result is whether it comes back quietly (the user
    /// clicked its chip). Nil when its job was cancelled or the agent stopped waiting for it.
    private func waitParked(_ id: String, why: ArisWaitingCard.Why, shows: Int, streamEnded: @MainActor () -> Bool) async -> Bool? {
        var userTurn = false
        var checked = ContinuousClock.now
        while !Task.isCancelled {
            if session.phase == .listening || session.phase == .thinking { userTurn = true }
            if case .show(let quiet) = ArisParkedAsk.returns(why: why, shows: shows, opened: ArisCardDesk.shared.isOpened(id), userTurnSince: userTurn) {
                return quiet
            }
            if streamEnded() { return nil }
            if ContinuousClock.now - checked >= ArisParkedAsk.waiterCheck {
                checked = ContinuousClock.now
                if await ArisAgentClient.stillWaits(id) == false { return nil }
            }
            try? await Task.sleep(for: .milliseconds(300))
        }
        return nil
    }

    /// A click on a 확인 대기 chip.
    func openWaitingCard(_ id: String) {
        ArisCardDesk.shared.open(id)
    }
}
