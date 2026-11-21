//
//  ArisController+Conversation.swift
//  Aris
//
//  The always-on conversation (ArisConversation). A turn opens it. After each answer Aris goes straight back to
//  listening, with no wake word or key: the wake detector is the only thing on the microphone, and it measures
//  loudness only. Its voice watch (ArisBargeIn) starts the next turn when the user talks, and stops Aris when they talks
//  over it. The recognizer, Scribe, Whisper and Smart Turn start only once there is voice. Esc, ⌥Space between turns,
//  an end phrase, the silence setting, or the screen going away ends it, and then the wake word is back.
//  Aris's own news (a job is done, a job asks) waits its turn and for a pause (announce).
//  A turn started by voice was hands-free (security review C1) until 2026-11-15; now it goes through the risk gate and
//  its cards as any turn does, and a card is answered by voice too. While another app plays or records, listening
//  between turns pauses.
//

import AppKit
import Defaults
import os
import SwiftUI

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "conversation")

extension ArisController {
    /// The clock the conversation's rules count on.
    static var uptime: Double { ProcessInfo.processInfo.systemUptime }

    /// Listening between turns, or a turn started by voice that hasn't heard a word yet: nobody is really talking.
    var listeningBetweenTurns: Bool {
        guard conversation.isOpen else { return false }
        return session.phase == .idle || (session.phase == .listening && followingUp && lastWordsAt == nil)
    }

    // MARK: - Opening and ending

    /// A turn of the user's started (the wake word, ⌥Space, the gesture, a resume): the conversation opens, unless the
    /// setting turned it off.
    func openConversation() {
        guard ArisConversation.enabled(silenceSeconds: Defaults[.arisConversationSilence]) else { return }
        let wasOpen = conversation.isOpen
        conversation = conversation.opened(at: Self.uptime)
        guard !wasOpen else { return }
        if ArisDuplexSwitch.isOn { ArisDuplexAudio.conversation(open: true) }
        echoLoop = ArisEchoLoop()
        log.notice("conversation open")
        watchEscape()
        watchSilence()
    }

    /// The session went idle: in a conversation, Aris is between turns. `reachedAI`: the turn went to the AI (only
    /// that restarts the silence clock).
    func settleConversation(reachedAI: Bool, heard: Bool = false) {
        guard conversation.isOpen else { return }
        conversation = conversation.settled(at: Self.uptime, reachedAI: reachedAI, heard: heard)
    }

    /// Ends the conversation: a turn under way stops (Esc, the key, the screen going away), the music comes back, and
    /// the wake word listens again (or the microphone closes).
    func closeConversation(_ reason: ArisConversation.EndReason) {
        guard conversation.isOpen else { return }
        log.notice("conversation over (\(reason.rawValue, privacy: .public))")
        if ArisPendingFiles.clearedWhenConversationEnds(reason) { ArisAttachments.shared.clear() }
        conversation = conversation.closed()
        ArisDuplexAudio.conversation(open: false)
        conversationWatch?.cancel()
        conversationWatch = nil
        echoTailWatch?.cancel()
        echoTailWatch = nil
        echoLoop = ArisEchoLoop()
        escapeMonitors.forEach(NSEvent.removeMonitor)
        escapeMonitors = []
        pausedForOtherAudio = false
        outputMeter.stop()
        detector?.watchVoice(nil)
        if session.phase != .idle, session.question == nil { cancel() }
        followingUp = false
        resumeMusicIfPaused()
        waitForWakeWordSoon(after: .zero)
    }

    /// A tap on the band: a pending question is answered no; the turn stops, and the conversation with it.
    func stopFromBand() {
        if session.question != nil { answerQuestion(false, source: .band) }
        if conversation.isOpen { return closeConversation(.tapped) }
        if session.question == nil { cancel() }
    }

    /// Esc anywhere ends it (a confirm card's own Esc is the card's: it means no there).
    private func watchEscape() {
        let escape: (NSEvent) -> Void = { event in
            guard event.keyCode == 53 else { return }
            MainActor.assumeIsolated {
                let aris = ArisController.shared
                guard aris.session.question == nil, aris.dictation == nil else { return }
                // Esc in a request's editor only throws the edit away (ArisPromptEdit); the next Esc ends it.
                guard !ArisPromptEdit.escIsEditors(editing: ArisPromptEditing.shared.active) else { return }
                aris.closeConversation(.escape)
            }
        }
        let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: escape)
        let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            escape(event)
            return event
        }
        escapeMonitors = [global, local].compactMap { $0 }
    }

    /// Between turns, the silence setting's seconds without a turn to the AI (or the 10-minute cap) end it, and
    /// another app's sound or microphone pauses listening.
    private func watchSilence() {
        conversationWatch?.cancel()
        // The conversation outlives the turn that opened it: its watch works for no turn.
        conversationWatch = ArisTurnScope.outside { Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.conversation.isOpen else { return }
                guard self.session.phase == .idle, self.listener == nil else { continue }
                if self.conversation.timedOut(at: Self.uptime, silenceSeconds: Defaults[.arisConversationSilence]) {
                    return self.closeConversation(.silence)
                }
                self.checkOtherAudio()
            }
        } }
    }

    /// Pauses listening between turns while another app plays or records, and resumes once it stops.
    /// While paused, the name still wakes Aris (ArisWakeArm.listensForName): the detector stays on for it.
    private func checkOtherAudio() {
        let apps = otherAudioApps()
        let present = !apps.isEmpty
        guard present != pausedForOtherAudio else { return }
        pausedForOtherAudio = present
        if present {
            noteOtherAudio(apps)
        } else {
            log.notice("other audio stopped: listening again")
        }
        waitForWakeWord()
    }

    /// Which apps paused listening, once per pause.
    func noteOtherAudio(_ apps: [String]) {
        log.notice("another app's audio: listening paused (\(apps.joined(separator: ", "), privacy: .public)); the name still wakes Aris")
    }

    /// Whether another app plays (audibly, by the output meter) or records right now. The meter runs (made off the main
    /// thread) while another app has output open, and stops otherwise; until it has read real sound, an open stream
    /// counts (ArisOtherAudio.isPresent), so a denied permission fails closed.
    /// `forConversation`: the check is for a conversation (open, or opening with this turn); only then may the meter
    /// run, since only closing one stops it.
    func otherAudioPresent(forConversation: Bool = true) -> Bool { !otherAudioApps(forConversation: forConversation).isEmpty }

    /// The apps that make otherAudioPresent true (ArisOtherAudio.culprits), by bundle id; empty: none.
    func otherAudioApps(forConversation: Bool = true) -> [String] {
        let own = ProcessInfo.processInfo.processIdentifier
        let processes = ArisOtherAudio.processes()
        switch ArisOtherAudio.meterStep(processes, ownPid: own, forConversation: forConversation) {
        case .ensure: outputMeter.ensure(leavingOut: ArisOtherAudio.ownObjects(processes, ownPid: own))
        case .stop: outputMeter.stop()
        case .leave: break
        }
        let missing = ArisOtherAudio.permissionMissing(onlyZeros: outputMeter.onlyZeros, processes, ownPid: own)
        if missing != systemAudioMissing { systemAudioMissing = missing }
        return ArisOtherAudio.culprits(processes, ownPid: own, outputLevel: outputMeter.level,
                                       pausedPlayers: ArisOtherAudio.pausedPlayers(nowPlaying: ArisNowPlaying.shared.isPlaying))
    }

    /// A hands-free turn's local change (an undo, ticking a to-do) asks first on the card, yes by a click or Y only
    /// (security review M1). True when it may go ahead (always, for a turn that wasn't hands-free); nil when the turn
    /// ended before an answer (nothing more is done or said).
    func confirmHandsFree(_ title: String, _ detail: String) async -> Bool? {
        guard turnHandsFree else { return true }
        guard let allow = await askUser(ArisConfirmation(id: "hands-free-" + UUID().uuidString, title: title, detail: detail), handsFree: true) else { return nil }
        withAnimation(ArisGlass.resize) { setSession(session.answered()) }
        return allow
    }

    /// Said when a hands-free card was answered no.
    func saidNotDone(korean: Bool, declined: String? = nil) async -> String {
        let reply = cardUnanswered ? ArisCardWait.unansweredLine(korean: korean) : declined ?? (korean ? "안 했어요." : "I left it.")
        // The user started another turn over the card: nothing is shown or said over it (audit card-1).
        guard !Task.isCancelled else { return reply }
        setSession(session.answering(reply))
        stats?.firstSound(at: .now)
        await speak { await self.speaker.speak(reply) }
        return reply
    }

    // MARK: - Listening between turns, and over Aris

    /// The voice watch for the moment: between turns any voice starts a turn; while Aris talks (not while it asks a
    /// question, whose answer the question listens for) voice stops it, by the output's rules (ArisBargeIn.mode);
    /// otherwise none.
    func updateVoiceWatch() {
        let mode = voiceWatchMode()
        detector?.watchVoice(mode, playback: speaker.meter.read)
        // Paused for another app's sound between turns: no voice watch, and the detector listens for the name instead.
        if pausedForOtherAudio, conversation.isOpen, session.phase == .idle, listener == nil, wakeListener == nil { detector?.pause(false) }
    }

    private func voiceWatchMode() -> ArisBargeIn.Mode? {
        guard conversation.isOpen, training == nil, dictation == nil else { return nil }
        switch session.phase {
        case .idle where listener == nil && wakeListener == nil:
            // Checked now, before arming: another app's sound pauses listening between turns.
            let apps = otherAudioApps()
            if !apps.isEmpty {
                if !pausedForOtherAudio {
                    pausedForOtherAudio = true
                    noteOtherAudio(apps)
                }
                return nil
            }
            // Not while Aris's own voice may still be in the room (the speaker's end plus the output's tail).
            guard echoTailOver() else { return nil }
            return .between
        case .speaking where session.question == nil:
            // Over another app's sound the barge-in watch would hear it, not the user.
            if otherAudioPresent() { return nil }
            // On speakers only with an echo canceller (there is none): Aris's own voice must never stop it or become a turn.
            let mode = ArisBargeIn.mode(headphones: ArisDucking.outputIsHeadphones(), speakersAllowed: Defaults[.arisBargeInOnSpeakers], echoCancelled: ArisBargeIn.echoCancellerOn)
                // The duplex engine's canceller hears past Aris's line (arisDuplexAudio): armed on speakers, stricter.
                ?? ArisBargeIn.cancelledMode(headphones: ArisDucking.outputIsHeadphones(), speakersAllowed: Defaults[.arisBargeInOnSpeakers],
                                             voiceCancelled: speaker.voiceIsEchoCancelled)
            // After a ⌥Space turn the listener had the microphone: the detector opens now, for the barge-in.
            if mode != nil, detector == nil, !screenAway, listener == nil { startDetector(paused: true) }
            return mode
        default:
            return nil
        }
    }

    /// Whether Aris's own voice is out of the room: the speaker finished and the output's tail (ArisOutputLatency,
    /// ArisEchoGuard.tail) has passed. Until then the watch is looked at again when the tail ends.
    func echoTailOver() -> Bool {
        let since = speaker.stoppedAt.map { (ContinuousClock.now - $0) / .seconds(1) }
        let wait = ArisEchoGuard.waitBeforeListening(playing: speaker.isPlaying, sinceStopped: since, tail: ArisOutputLatency.tail())
        guard wait > 0 else { return true }
        echoTailWatch?.cancel()
        echoTailWatch = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, let self else { return }
            self.echoTailWatch = nil
            self.updateVoiceWatch()
        }
        return false
    }

    /// Aris's own voice may still reach the microphone: it plays, or stopped within the tail and a name's length.
    var ownVoiceAudible: Bool {
        let since = speaker.stoppedAt.map { (ContinuousClock.now - $0) / .seconds(1) }
        return ArisEchoGuard.ownVoiceAudible(playing: speaker.isPlaying, sinceStopped: since,
                                             window: ArisOutputLatency.tail() + ArisEchoGuard.candidateLength)
    }

    /// A heard turn was Aris's own words (ArisEchoGuard.verdict): nothing is routed or answered. In a conversation it
    /// listens again (the answer still parked); two in a row, or a sentence of Aris's own, end the conversation
    /// (ArisEchoLoop) so it can't loop. A wake turn closes quietly.
    func echoHeard(_ verdict: ArisEchoGuard.Verdict) {
        log.notice("heard Aris's own words (\(verdict == .ownWords ? "its sentence" : "echo", privacy: .public)): not a turn")
        ArisTuningLog.append(["path": "echo", "verdict": verdict == .ownWords ? "own-words" : "echo",
                              "headphones": ArisDucking.outputIsHeadphones()], to: "wake-log.jsonl")
        if turnByWakeWord, !conversation.isOpen { return closeWakeTurnQuietly(.nothingSaid) }
        echoLoop = echoLoop.after(verdict)
        dropFalseStart()
        if echoLoop.stops { closeConversation(.echo) }
    }

    /// The voice watch is sure the user is talking; the turn's audio starts at the detector's sample `from`, `lookback`
    /// seconds ago.
    func voiceStarted(from sample: Int, lookback: Double) {
        guard conversation.isOpen, training == nil, dictation == nil else { return }
        switch session.phase {
        case .idle where listener == nil && wakeListener == nil:
            log.notice("you're talking: listening")
            startConversationTurn(from: sample, lookback: lookback)
        case .speaking where session.question == nil:
            log.notice("you talked over Aris: it stops and listens")
            ArisTuningLog.append(["path": "barge-in", "headphones": ArisDucking.outputIsHeadphones()], to: "wake-log.jsonl")
            startConversationTurn(from: sample, lookback: lookback)
        default:
            break
        }
    }

    /// A turn of the conversation, heard through the wake detector from just before the voice was sure (nothing said
    /// is lost to the hand-over). Hands-free, as a follow-up: no words within a few seconds was noise.
    func startConversationTurn(from sample: Int, lookback: Double) {
        guard let detector else { return }
        // A new turn: the one before is over. Everything below, and every task it starts, works for the new one.
        ArisTurnScope.within(openTurn(.voice)) { startConversationTurn(detector, from: sample, lookback: lookback) }
    }

    private func startConversationTurn(_ detector: ArisWakeDetector, from sample: Int, lookback: Double) {
        wakeRestart?.cancel()
        dropPendingAnswer()
        speaker.stop()
        pauseWatch?.cancel()
        announcing = nil
        brief = nil
        // Talking over Aris through the speakers: what it was saying, so its own words heard back can be dropped (only
        // as many as the lookback holds; with headphones the mic can't hear it).
        let overSpeakers = session.phase == .speaking && !ArisDucking.outputIsHeadphones()
        arisWasSaying = overSpeakers ? session.reply : ""
        echoWords = overSpeakers ? ArisEchoTrim.words(in: lookback) : 0
        // Not hands-free (2026-11-15): what it asks goes through the gate and its cards, answered by voice or a click.
        turnHandsFree = false
        turnByWakeWord = false
        wakeDoubleCheck?.cancel()
        endQuietLap()
        // The answer on screen stays parked if this turn comes to nothing.
        answerBeforeFollowUp = session.reply.isEmpty || session.question != nil ? nil : (session.heard, session.reply)
        detector.watchVoice(nil)
        detector.pause(true)
        let since = ContinuousClock.now - .milliseconds(Int(lookback * 1000))
        let listener = ArisListener()
        seeTurnStarting()
        conversation = conversation.turnStarted()
        setSession(session.listening())
        listeningSince = since
        recordingLead = .zero
        lastWordsAt = nil
        lastVoiceAt = .now
        voicePeak = 0
        turnVoiceFrames = 0
        practiceTurn = onboardingTalk == .practice
        voiceFloor = ArisTalkKey.startingFloor
        pauseScore = nil
        followingUp = true
        pauseMusic()
        // The brain is warmed and Scribe streams only once there are words (follow): noise wakes neither.
        follow(listener)
        self.listener = listener
        stopScribe()
        scribeOnWords = true
        starting = Task {
            do {
                try await Self.within(Self.startTimeout) { try await listener.start(locale: Self.locale, source: detector, from: sample) }
            } catch {
                log.error("couldn't listen to the turn: \(String(describing: error), privacy: .public)")
                guard self.listener === listener else { return }
                self.dropFalseStart()
            }
        }
        listenHandsFree()
    }

    /// A turn started by voice heard no words: Aris listens between turns again, the answer still parked, and the
    /// silence clock where it was.
    func dropFalseStart() {
        log.notice("nothing said: listening again")
        handsFree = false
        pauseWatch?.cancel()
        scribeOnWords = false
        stopScribe()
        seeEnded()
        if let listener = listener as? ArisListener { Task { _ = await listener.stop() } }
        listener = nil
        level = 0
        if let answer = answerBeforeFollowUp {
            setSession(.parked(heard: answer.heard, reply: answer.reply))
        } else {
            setSession(session.done())
        }
        answerBeforeFollowUp = nil
    }

    /// The detector's gate: the user talking or not (for the pause rule).
    func heardVoice(_ talking: Bool) {
        userTalking = talking
        lastHeardVoiceAt = .now
        // Outside a conversation too: nothing Aris says on its own starts over the user's voice (ArisInterruption).
        ArisWorld.shared.heardVoice(talking)
    }

    // MARK: - Speaking up at a pause

    /// Aris's own news waits its turn (first come, first said) and for a pause (ArisPause): in a conversation, a
    /// moment when neither the user nor Aris is talking; otherwise whenever Aris is idle, as before. `present`: and the user is
    /// at the Mac (a question). `when`: and this holds too (a card under the notch: the notch is closed), looked at every
    /// `recheck`. Nil when cancelled before its turn came.
    func announce<T>(present: Bool = false, recheck: Duration = .milliseconds(250), when ready: () -> Bool = { true },
                     _ body: () async -> T) async -> T? {
        let (queue, ticket) = announcements.adding()
        announcements = queue
        defer { announcements = announcements.removing(ticket) }
        while !(announcements.isFirst(ticket) && isPause(present: present) && ready()) {
            guard !Task.isCancelled else { return nil }
            try? await Task.sleep(for: recheck)
        }
        guard !Task.isCancelled else { return nil }
        return await body()
    }

    func isPause(present: Bool) -> Bool {
        let seconds = { (instant: ContinuousClock.Instant?) in instant.map { (ContinuousClock.now - $0) / .seconds(1) } }
        return (!present || !screenAway)
            && ArisPause.isPause(idle: session.phase == .idle && listener == nil && wakeListener == nil, training: training != nil,
                                 conversationOpen: conversation.isOpen, userTalking: userTalking,
                                 sinceVoice: seconds(lastHeardVoiceAt), sinceAris: seconds(arisStoppedAt))
    }
}
