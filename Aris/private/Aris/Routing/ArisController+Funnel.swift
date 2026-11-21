//
//  ArisController+Funnel.swift
//  Aris
//
//  answer(), every turn's way in, as the funnel (ARCHITECTURE.md 3.1, migration step 3): the request is built, the
//  handlers in ArisTurnFunnel are asked in order, the first claim is done (ArisController+TurnRuns) and the turn ends
//  as every turn always ended. The controller is the funnel's host: it reads the request further when a handler needs
//  it and does the look-ups that need the app.
//

import Defaults
import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "turn")

extension ArisController: ArisTurnHost {
    /// `gesture`: the turn's drawing. With circled shots the words carry `[img N]` markers and the brain answers
    /// whatever a local intent would have made of them (the router may still set the tier); the AI named up front is
    /// picked from the unmarked words. A drawing without shots keeps every local path (which then drops its images).
    /// Files given to Aris ride along with this turn however it was asked (typed, the talk key, the wake word, a
    /// follow-up) and are no longer pending; with them, "이거" is the files: no screenshot, no look at the screen.
    func answer(_ said: String, gesture: ArisGestureTurn? = nil, typed: Bool = false) async {
        turnMemory.start()
        turnTyped = typed
        // The button under a failure follows every turn from its start: whether it had begun a tool or a card decides
        // if a question lost to a stopped helper is asked again by itself (ArisHelperWatch).
        ArisFixModel.shared.watch()
        let request = ArisTurnRequest(said: said, origin: turnOrigin(typed: typed), typed: typed, gesture: gesture,
                                      context: ArisTurnRequest.Context(practice: practiceTurn, handsFree: turnHandsFree))
        guard let found = await ArisTurnFunnel.claim(request, host: self) else { return }
        log.notice("funnel: \(found.claim.branch, privacy: .public)")
        guard let reply = await run(found.claim, found.request), let heard = found.request.heard else { return }
        await answered(reply, heard: heard.unmarked)
    }

    /// The end of every turn that answered: recorded, the conversation's quiet counted, the answer left up a while.
    private func answered(_ reply: String, heard: String) async {
        guard !Task.isCancelled else { return }
        // Paths that speak before they know their reply (the brief, arranging windows) are recorded here.
        recordTurn(heard: heard, reply: reply)
        // The conversation's quiet is counted from when the voice finished, as before.
        lastTurnAt = .now
        finishTurn("ok")
        // The answer stays up and the conversation stays open; the next ⌥Space or "아리스" carries it on.
        // A hand-off's turn ends as its line ends: the notch goes and the jobs' pill tells how the work goes.
        try? await Task.sleep(for: ArisNotch.linger(handedOff: handedOff))
        guard !Task.isCancelled else { return }
        setSession(session.done())
        resumeMusicIfPaused()
    }

    /// What opened the turn, for the log.
    private func turnOrigin(typed: Bool) -> ArisTurnOrigin {
        if practiceTurn { return .practice }
        if typed { return .typed }
        return turnByWakeWord ? .wake : .key
    }

    // MARK: - The host

    func hear(_ request: ArisTurnRequest) async -> ArisTurnRequest.Heard {
        // Never on a hands-free turn, nor while the notch is closed with no chips to see; gone after 5 minutes.
        let heard = ArisAttachments.shared.take(into: request.said, handsFree: turnHandsFree, shown: ArisNotchPresence.shared.isOpen)
        // What he asks of files he dropped is remembered by its shape, for the chips that learn (ArisDropLearned).
        ArisDropModel.shared.learn(from: heard)
        let shots = request.gesture?.hasShots == true
        // The files stand in for the screenshot; shots the user circled still go with their `[img N]` markers.
        if ArisPendingFiles.dropsTurnImages(heard, circledShots: shots) { seeEnded() }
        // The files' text came with it: outside text from here on, as anything read (QA BUG-35).
        if ArisAttachmentText.carriesText(heard) { outsideConversation = true }
        // "아니 그냥 클로드 시켜": an AI (or a teammate) named as the one to do it takes the work as a background job
        // (ArisBrainHandOff), decided before an AI is picked to answer this turn; never "no such teammate".
        let handOff = shots ? nil : await brainHandOff(ArisPendingFiles.words(of: heard))
        let made = ArisTurnRequest.Heard.make(heard: heard, gesture: request.gesture, handOff: handOff, moment: ArisTurnRequest.Heard.Moment(
            conversationOpen: followingUp || conversation.isOpen, afterQuestion: ArisFollowUp.asksSomething(history.last?.reply ?? ""),
            teammateCardUp: ArisTeamModel.shared.made != nil, defaultBrain: ArisBrain.named(Defaults[.arisBrain]), currencyHome: ArisCurrencyHome.code()))
        // "클로드 앱으로 해", "ChatGPT 열어서 물어봐": the apps on this Mac the words name, for the context (ArisProgramMention).
        turnPrograms = handOff == nil && !shots ? await programsLine(made.unmarked) : nil
        // "세션 읽어줘", "뭐 기다려?", "클로드 뭐 하고 있어?": answered from the sessions Aris's hooks know, not a look at the
        // screen (the owner, 2026-11-14: "클로드 코드 저거, 세션 … 읽어줘" got "I can't see any session on the screen").
        turnAsksSessions = made.asksSessions
        return made
    }

    func routed(_ words: String) async -> ArisTurnRequest.Routed {
        // Asked side by side with the router: what Aris reaches without a browser, for website work (ArisServiceReach).
        async let reach = ArisReachableServices.shared.current()
        let routed = await route(words)
        return ArisTurnRequest.Routed(intent: routed.intent, tier: routed.tier, browserWork: routed.browserWork, reach: await reach)
    }

    func finishable(_ item: String) async -> ArisTodoFinishable? { await ArisTodoModel.shared.finishable(item) }

    func application(_ name: String) -> URL? { Self.application(named: name) }
}
