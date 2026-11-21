//
//  ArisController+Endpoint.swift
//  Aris
//
//  The hands-free turn's end, from its audio and words (each voice reading, new words, Smart Turn's score; a timer is
//  armed only in a pause, for the moment the next threshold is due), and the speculative turn: at a plausible end the
//  words are finalised and, for a plain question to the brain, the request goes to aris-agent while the microphone
//  keeps listening. Its replies are held (nothing is shown or said). The user talking again before anything
//  irreversible cancels it (the /ask connection is dropped, aris-agent abandons that turn) and the utterance goes on;
//  the firm end commits and the brain's turn takes the request already sent (askAndSpeak). The policy and the
//  speculation are pure (Shared/Core/Hearing); this file wires them to the listener, Scribe, Whisper and the helper.
//

import Defaults
import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "turn")

extension ArisController {
    // MARK: - The turn's clock

    /// A turn began listening (the talk key, a wake word, a conversation's voice): its clock starts and what the last
    /// turn left (a request it never took) goes. Called again for the same turn, it changes nothing.
    func beginTurnHearing() {
        guard let since = listeningSince else { return }
        if turnHearing.since != since {
            dropEarlyRequest()
            turnHearing.begin(since: since)
        }
        // The kernel's turn this listening is for (the one opened for the key, the wake word or the voice).
        if turnHearing.turnId == nil { turnHearing.turnId = ArisTurnScope.current ?? kernel.current }
        turnHearing.stageSink = { [weak self] turn, stage, ms in self?.kernel.send(.turnStage(turn, name: stage.rawValue, ms: ms)) }
    }

    /// The end that commits: the firm end of a hands-free turn, the key's release, a stop.
    func markFirmEnd() {
        let clock = turnHearing.clock
        turnHearing.mark(.firmEnd, again: true)
        // A speculation already marked where the speech ended; any other end, at the last voice.
        if turnHearing.turn?.committedSpeculation != true || clock.marks[.voiceEnd] == nil {
            turnHearing.mark(.voiceEnd, at: lastVoiceAt ?? .now, again: true)
        }
    }

    // MARK: - Hands-free: the end, from events

    /// Hands-free listening starts: the end is looked at on every voice reading and change of words from here on.
    func beginEndpointing() {
        beginTurnHearing()
        let driver = ArisEndpointDriver(waitForWords: followingUp ? ArisTalkKey.waitForFollowUp : ArisTalkKey.waitForWords,
                                        caps: .init(waitForWords: ArisTalkKey.waitForWords, longestTurn: ArisTalkKey.longestTurn,
                                                    longestWaitForWords: ArisTalkKey.longestWaitForWords))
        turnHearing.turn?.drop()
        turnHearing.turn = ArisTurnHearing.Turn(driver: driver, hooks: .init(
            finalWords: { [weak self] id in await self?.speculativeWords(id) },
            requestKey: { [weak self] heard in await self?.earlyRequestKey(heard) },
            ask: { [weak self] _, key in self?.sendEarly(key) ?? AsyncStream { $0.finish() } },
            kind: { $0.speculationKind },
            commit: { [weak self] id in self?.endpointCommitted(id) },
            cancelled: { [weak self] id in self?.speculationCancelled(id) },
            speculated: { [weak self] id in self?.speculated(id) },
            firstOutput: { [weak self] at in self?.turnHearing.mark(.firstDelta, at: at) }))
        endpointLook()
    }

    /// One look at the pause (a voice reading, a score, the pause timer).
    func endpointLook(voiceNow: Bool = false) {
        guard handsFree, session.phase == .listening, let turn = turnHearing.turn, !turn.committed, let since = listeningSince,
              kernel.state.admits(turnHearing.turnId) else { return }
        let now = ContinuousClock.now
        let sinceVoice = lastVoiceAt.map { now - $0 }
        // Smart Turn only once there are words: a follow-up that's still only noise isn't scored.
        if !(followingUp && lastWordsAt == nil) { scorePauseIfNeeded(sinceVoice: sinceVoice) }
        let said = turnByWakeWord ? ArisWakeWord.strippedCall(session.heard) : ArisWakeWord.stripped(session.heard)
        let pending = turn.driver.pendingId != nil
        let snapshot = ArisEndpointDriver.Snapshot(now: now - since, voiceNow: voiceNow, lastVoice: lastVoiceAt.map { $0 - since },
                                                   lastWords: lastWordsAt.map { $0 - since },
                                                   score: currentPauseScore ?? (pending ? turnHearing.pendingScore : nil),
                                                   complete: ArisEndpoint.looksComplete(said), hanging: ArisEndpoint.isHanging(said))
        // A follow-up that heard no words is over at its first end: no window, so no Whisper on noise.
        if followingUp, lastWordsAt == nil, ArisEndpointPolicy.decide(turn.driver.input(snapshot)).decision >= .plausibleEnd {
            return stopListening()
        }
        // In the turn's own scope: a speculation it starts (its words, its request) belongs to that turn, and whatever it
        // does once the turn is over is dropped by the kernel's guard.
        ArisTurnScope.within(turnHearing.turnId) { turn.observe(snapshot) }
        armEndpointTimer(snapshot)
    }

    /// A look exactly when the next threshold is due, armed on every look (voice readings normally come every ~43 ms
    /// first and re-arm it): a feed that stops on a voice reading still ends the turn (ArisEndpointDriver.nextLook).
    private func armEndpointTimer(_ snapshot: ArisEndpointDriver.Snapshot) {
        pauseWatch?.cancel()
        guard let turn = turnHearing.turn, !turn.committed, let wait = turn.driver.nextLook(snapshot) else { return }
        pauseWatch = Task { [weak self] in
            guard (try? await Task.sleep(for: wait + .milliseconds(5))) != nil else { return }
            self?.endpointLook()
        }
    }

    private func speculated(_ id: Int) {
        turnHearing.mark(.plausibleEnd, again: true)
        turnHearing.mark(.voiceEnd, at: lastVoiceAt ?? .now, again: true)
        turnHearing.pendingScore = currentPauseScore
        logPause(decision: "plausible")
    }

    private func endpointCommitted(_ id: Int?) {
        if id == nil { logPause(decision: "firm") }
        stopListening()
    }

    private func speculationCancelled(_ id: Int) {
        turnHearing.clock.forgetSpeculation()
        turnHearing.pendingScore = nil
        turnHearing.router?.task.cancel()
        turnHearing.router = nil
        restoreEarlyFresh()
        // Scribe finished its take at the plausible end: it hears the whole utterance again, the start replayed.
        if turnHearing.scribeWasOn, scribe == nil, let listener = listener as? ArisListener {
            startScribe(for: listener, replaying: listener.recordedSamples)
        }
        turnHearing.scribeWasOn = false
        log.notice("kept talking: listening on (speculation \(id, privacy: .public) dropped)")
        ArisTuningLog.append(["graceResumed": true, "followUp": followingUp, "speculation": id], to: "endpoint-log.jsonl")
    }

    private func logPause(decision: String) {
        let now = ContinuousClock.now
        let sinceVoice = lastVoiceAt.map { now - $0 }, sinceWords = lastWordsAt.map { now - $0 }
        let said = turnByWakeWord ? ArisWakeWord.strippedCall(session.heard) : ArisWakeWord.stripped(session.heard)
        let complete = ArisEndpoint.looksComplete(said), hanging = ArisEndpoint.isHanging(said)
        let score = currentPauseScore ?? turnHearing.pendingScore
        let endCase = turnHearing.turn?.driver.lastCase
        turnHearing.endCase = endCase
        let ms = { (gap: Duration?) in gap.map { Int($0 / .milliseconds(1)) } ?? -1 }
        log.notice("you paused (\(decision, privacy: .public) end, \(endCase?.rawValue ?? "-", privacy: .public), loudest \(self.voicePeak, privacy: .public), quiet \(ms(sinceVoice), privacy: .public) ms, no new words \(ms(sinceWords), privacy: .public) ms, finished \(complete, privacy: .public), hanging \(hanging, privacy: .public), smart turn \(score.map { String(format: "%.2f", $0) } ?? "-", privacy: .public))")
        logEndpoint(score: score, sinceVoice: sinceVoice, sinceWords: sinceWords, complete: complete, hanging: hanging, said: said,
                    endCase: endCase?.rawValue, decision: decision)
    }

    // MARK: - The speculation's words and request

    /// The words at the plausible end: the second listen within its budget, the microphone still open.
    private func speculativeWords(_ id: Int) async -> String? {
        guard lastWordsAt != nil, let listener = listener as? ArisListener else { return nil }
        turnHearing.scribeWasOn = scribe != nil
        let heard = await secondListen(listener.secondListenSamples, apple: turnHearing.appleText.isEmpty ? session.heard : turnHearing.appleText,
                                       budgeted: true)
        guard turnIsCurrent else { return nil }
        turnHearing.mark(.transcriptFinal, again: true)
        return heard
    }

    /// The words as the turn will take them (stopListening: the call stripped, Aris's own echo trimmed, as `thinking()` keeps them).
    func turnWords(_ heard: String, wasSaying: String, echoWords: Int) -> String {
        ArisEchoTrim.trimmed(turnByWakeWord ? ArisWakeWord.strippedCall(heard) : ArisWakeWord.stripped(heard), arisWasSaying: wasSaying, atMost: echoWords)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// What the request would be sent as, when it may go before the turn is over; nil when it waits (ArisSpeculationGate).
    private func earlyRequestKey(_ heard: String) async -> ArisEarlyKey? {
        let text = turnWords(heard, wasSaying: arisWasSaying, echoWords: echoWords)
        if turnHearing.secondPassLate { noteWordsWentOn(text, wasSaying: arisWasSaying, echoWords: echoWords) }
        if let block = speculationBlock(text) {
            log.notice("speculation: the request waits for the end (\(block.rawValue, privacy: .public))")
            return nil
        }
        // Heard without the key, with a voice print: only the owner's voice sends early (F1); any other waits for the end.
        guard await voiceAllowsEarlyRequest() else {
            log.notice("speculation: the request waits for the end (the voice isn't known to be the owner's yet)")
            return nil
        }
        let brain = ArisBrain.named(Defaults[.arisBrain])
        // The router, as answer() will ask it, now: answer's route() takes this answer instead of waiting for its own.
        let task = Task { await self.routeNow(text) }
        turnHearing.router = (text, task)
        let routed = await task.value
        guard routed.intent == nil, !routed.browserWork, !Task.isCancelled else {
            log.notice("speculation: the router has it for the Mac or a job; the request waits for the end")
            return nil
        }
        let tier = ArisRouter.asksForCare(text) ? .critical : routed.tier
        // The context the brain's turn builds (its apps line and the sessions question first, as answer() sets them).
        readTeammatesIfMissing()
        turnPrograms = await programsLine(text)
        turnAsksSessions = ClaudeSessionsContext.asks(text)
        turnHearing.earlyContext = withCutOffNote(await currentContext(sessions: true))
        await settleAfterCancelledRequest()
        // The turn ended meanwhile (a stop, a new turn): nothing of it goes out.
        guard turnIsCurrent else { return nil }
        return ArisEarlyKey(text: text, brain: brain.rawValue, tier: tier.rawValue, screenConversation: screenConversation,
                            outsideConversation: outsideConversation, handsFree: turnHandsFree, voiceOwner: voiceOwnerTag())
    }

    /// Why these words wait for the firm end, or nil: only a plain question to the brain may go early.
    func speculationBlock(_ text: String) -> ArisSpeculationGate.Block? {
        let team = ArisTeamModel.shared
        let intent = ArisIntent.parse(text)
        var plain = false
        if case .ask = intent { plain = true }
        // The same matchers, in the same words, as answer() asks before it reaches the brain.
        plain = plain && team.load == .ready && pendingHandOff == nil && ArisBrain.pick(from: text) == nil
            && ArisBrainHandOff.parse(text, teammates: team.teammates) == nil && currencyAsk(text) == nil && !ArisIntent.isRecurring(text)
            && ArisSkillIntent.link(in: text) == nil && ArisTeamRemoval.parse(text, teammates: team.teammates + [.claudeCode]) == nil
            && !text.contains("팀원") && text.range(of: #"(?i)\bteammate\b"#, options: .regularExpression) == nil
            && ArisTeamMaking.parse(text) == nil && ArisTeamRouting.directJob(text, teammates: team.teammates) == nil
            && ArisMemoryImportWords.asked(text) == nil && !ArisHandoff.isHandoff(text)
            && !ArisDeixis.refersToScreen(text) && !ArisDeixis.refersToClipboard(text)
        let afterQuestion = ArisFollowUp.asksSomething(history.last?.reply ?? "")
        let heardWithoutKey = followingUp || turnByWakeWord
        return ArisSpeculationGate.block(ArisSpeculationGate.Turn(
            words: text, plainBrainPath: plain,
            pointsAtScreen: ArisScreenNeed.pointsAtScreen(text, apps: ArisScreenCapture.visibleApps()),
            gesture: ArisGestureHooks.shared.gestureKeyPress || !shotThumbs.isEmpty,
            filesWaiting: !ArisAttachments.shared.pending.files.isEmpty,
            cardUp: session.question != nil || team.made != nil,
            wakeEvidence: wakeEvidence != nil,
            echoDoubt: heardWithoutKey && ArisEchoGuard.verdict(text, recent: speaker.recentlySaid) != .user,
            followUpDone: (followingUp || conversation.isOpen) && ArisFollowUp.isDone(text, afterQuestion: afterQuestion),
            typed: turnTyped, practice: practiceTurn, dictation: dictation != nil))
    }

    /// Sends the request early, as askAndSpeak would (no images: the gate let no screen turn through).
    private func sendEarly(_ key: ArisEarlyKey) -> AsyncStream<ArisAgentReply> {
        let fresh = freshConversation
        freshConversation = false
        turnHearing.earlyFresh = fresh
        turnHearing.mark(.requestSent, again: true)
        log.notice("speculation: the request goes now, still listening (\(key.brain, privacy: .public), \(key.tier, privacy: .public))")
        return ArisAgentClient.ask(turnHearing.late.send(key.text), context: turnHearing.earlyContext ?? "", tier: ArisTier.named(key.tier),
                                   brain: ArisBrain.named(key.brain), fresh: fresh, screenConversation: key.screenConversation,
                                   outsideConversation: key.outsideConversation, handsFree: key.handsFree, images: ArisOutgoingImages([]))
    }

    /// A request of this turn that was sent and then cancelled (the user went on talking) is still in the brain's thread: the
    /// helper interrupts that turn and keeps the conversation (ArisTurnInterrupt), so the whole question says the
    /// half one is not to be answered.
    static let cutOffNote = "Note: the user's previous message in this conversation was cut off while they were still speaking and got no answer. The message below is the whole of it: answer only this one, and treat the cut-off one as not said."

    /// Only for the turn whose hearing cancelled the request (ArisCutOffNote): a later turn, typed or spoken, has none.
    func withCutOffNote(_ context: String) -> String {
        guard ArisCutOffNote.applies(cancelled: turnHearing.turn?.requestsCancelled ?? 0, hearingTurn: turnHearing.turnId,
                                     turn: ArisTurnScope.current ?? kernel.current) else { return context }
        return context.isEmpty ? Self.cutOffNote : context + "\n" + Self.cutOffNote
    }

    // MARK: - The committed turn

    /// The words of a turn that committed on a speculation (nil: none, the turn listens again as before).
    func committedSpeculationWords() async -> String? {
        guard let turn = turnHearing.turn, turn.committedSpeculation else { return nil }
        return await turn.committedWords()
    }

    /// The brain's turn: the request already sent for exactly these words, or nil (it sends its own; one sent for
    /// other words is cancelled first, and the helper given a moment to end it).
    func takeEarlyRequest(_ text: String, tier: ArisTier, brain: ArisBrain, screen: String?, request: String?, images: Bool) async -> ArisEarlyRequest? {
        guard let turn = turnHearing.turn else { return nil }
        let key = ArisEarlyKey(text: text, brain: brain.rawValue, tier: tier.rawValue, screenConversation: screenConversation,
                               outsideConversation: outsideConversation, handsFree: turnHandsFree, voiceOwner: voiceOwnerTag())
        if screen == nil, request == nil, !images || turn.locked, let replies = turn.takeRequest(for: key) {
            let fresh = turnHearing.earlyFresh ?? false
            turnHearing.earlyFresh = nil
            log.notice("speculation: the turn takes the request sent at the plausible end")
            return ArisEarlyRequest(replies: replies, fresh: fresh)
        }
        dropEarlyRequest()
        await settleAfterCancelledRequest()
        return nil
    }

    /// The words the brain's own request goes with: a better transcript that came after the budget, while still unsent.
    func sendingWords(_ text: String) -> String {
        turnHearing.mark(.requestSent, again: true)
        return turnHearing.late.send(text)
    }

    /// The turn ended (answered here, stopped, failed) without the request sent early: it goes, and the conversation
    /// it took is new again.
    func dropEarlyRequest() {
        turnHearing.turn?.drop()
        restoreEarlyFresh()
    }

    private func restoreEarlyFresh() {
        if let fresh = turnHearing.earlyFresh, fresh { freshConversation = true }
        turnHearing.earlyFresh = nil
    }

    private func settleAfterCancelledRequest() async {
        guard let at = turnHearing.turn?.lastCancelAt else { return }
        let left = ArisTurnHearing.Turn.settle - (ContinuousClock.now - at)
        if left > .zero { try? await Task.sleep(for: left) }
    }

    /// The router for `text`: its answer asked during the pause when there is one, else asked now.
    func route(_ text: String) async -> (intent: ArisIntent?, tier: ArisTier, browserWork: Bool) {
        if let asked = turnHearing.routed(text) { return await asked.value }
        return await routeNow(text)
    }

    // MARK: - The second listen's budget

    /// Scribe's whole turn within its budget: nil when the budget ran out (its take still comes, as a late transcript).
    func scribeWithinBudget() async -> ArisHeard?? {
        let heard = await ArisSecondPass.within(ArisSecondPass.scribeBudget, { await self.finishScribe() },
                                                late: { [weak self] late in self?.secondPassCameLate(late?.text) })
        if heard == nil {
            turnHearing.secondPassLate = true
            log.notice("Scribe: not back within \(Int(ArisSecondPass.scribeBudget / .milliseconds(1)), privacy: .public) ms; the turn goes on with its live words")
        }
        return heard
    }

    /// Whisper within its budget: nil when it ran out (or Whisper isn't ready); a late reading still counts while unsent.
    func whisperWithinBudget(_ recording: [Float], apple: String) async -> String? {
        let frames = turnVoiceFrames, loudest = voicePeak, heardVoice = lastVoiceAt != nil
        let read = await ArisSecondPass.within(ArisSecondPass.whisperBudget, { await self.whisperTranscript(recording) }, late: { [weak self] late in
            guard let late else { return }
            let text = ArisTranscript.pick(whisper: late, apple: apple, heardVoice: heardVoice, voiceFrames: frames, loudest: loudest,
                                           languages: Defaults[.arisLanguages], recognizer: Self.locale.identifier)
            if text != apple { self?.secondPassCameLate(text) }
        })
        if read == nil {
            turnHearing.secondPassLate = true
            log.notice("whisper: not back within \(Int(ArisSecondPass.whisperBudget / .milliseconds(1)), privacy: .public) ms; the turn goes on with Apple's words")
        }
        return read ?? nil
    }

    /// The turn went on with `text` because the second listen was late: a better one may still replace it.
    func noteWordsWentOn(_ text: String, wasSaying: String, echoWords: Int) {
        guard turnHearing.secondPassLate else { return }
        turnHearing.late.wentOn(with: text)
        // A late transcript gets the owner's pairs too; there is no time left to repair it.
        let pairs = ArisVocabulary.loadPairs()
        turnHearing.lateClean = { [weak self] raw in
            self?.turnWords(ArisHeardFix.corrected(ArisHeardPairs.applied(raw, pairs: pairs)), wasSaying: wasSaying, echoWords: echoWords) ?? raw
        }
    }

    private func secondPassCameLate(_ raw: String?) {
        guard let raw, !raw.isEmpty, let clean = turnHearing.lateClean else { return }
        let kept = turnHearing.late.arrived(clean(raw))
        log.notice("second listen came late: \(kept ? "its words go with the request" : "the request had gone (or nothing changed), ignored", privacy: .public)")
    }

    /// What each recogniser wrote, for turns.jsonl (a speculation's comes before the turn's numbers exist).
    func noteRecognized(apple: String, whisper: String?) {
        stats?.recognized(apple: apple, whisper: whisper)
        turnHearing.recognized = (apple, whisper)
    }
}
