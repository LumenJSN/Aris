//
//  ArisController+Wake.swift
//  Aris
//
//  Calling Aris by name: the idle microphone and its wake-word checks, interrupting Aris while it talks,
//  and teaching it your "아리스".
//

import AppKit
import AVFoundation
import Defaults
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "turn")

extension ArisController {
    // MARK: - Wake word

    /// Reopens of the wake word's microphone in a row, and when it last opened (ArisAudioQuiet backs them off).
    private static var wakeRestarts = 0
    private static var wakeOpenedAt: ContinuousClock.Instant?
    /// macOS's speech model for Aris's language is on this Mac, as last asked: until it is, no check could hear the
    /// name, so the microphone isn't opened for one (fresh install F4).
    private static var wakeSpeechReady = false
    /// The wait for that model: one at a time.
    private static var wakeSpeechWait: Task<Void, Never>?
    /// Checks in a row whose recognizer couldn't start (ArisWakeArm.pause backs them off).
    private static var wakeListenFailures = 0
    /// The watch on the audio devices (ArisMicWatch), kept for the app's life once the wake word was first asked for.
    private static var micWatch: ArisMicWatch?

    static var wakeModelFile: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Aris/wake-model.json")
    }

    static func loadWakeModel() -> ArisWakeModel? {
        guard let file = wakeModelFile, let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(ArisWakeModel.self, from: data)
    }

    /// No microphone while the Mac is locked or its screen sleeps: nobody's there to call Aris.
    func watchScreen() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        let away: (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                self?.screenAway = true
                self?.closeConversation(.screenAway)
                self?.stopWaitingForWakeWord()
                ArisWakeRestLive.shared.screenWentAway(wakeWordOn: Defaults[.arisWakeWord])
            }
        }
        let back: (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                self?.screenAway = false
                self?.waitForWakeWordSoon()
            }
        }
        // Going to sleep mid-turn: the turn is dropped now, not left to its timers to find a dead microphone after waking.
        workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.closeConversation(.screenAway)
                guard self.isActive else { return }
                log.notice("sleeping mid-turn: cancelled")
                self.cancel()
            }
        }
        workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main, using: away)
        workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main, using: back)
        distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main, using: away)
        distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main, using: back)
    }

    /// The wake microphone changed: it comes back after `delay`, for the barge-in while Aris talks, else for the wake word.
    func restartDetectorSoon(after delay: Duration) {
        wakeRestart?.cancel()
        wakeRestart = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            if ArisAudioQuiet.restartArmsBargeIn(speaking: self.session.phase == .speaking, asking: self.session.question != nil) {
                self.armBargeIn()
            } else {
                self.waitForWakeWord()
            }
        }
    }

    func waitForWakeWordSoon(after delay: Duration = wakeDelayAfterTurn) {
        wakeRestart?.cancel()
        wakeRestart = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.waitForWakeWord()
        }
    }

    /// While idle (and the setting is on), the detector listens. Never asks for permissions: the first
    /// hotkey press does that. In a conversation it listens whatever the setting, for any voice (no name needed).
    func waitForWakeWord() {
        // A lock or a display's sleep whose "back" notice never came (a display unplugged mid-sleep) must not hold the
        // microphone off for good (QA BUG-38): the screen is asked directly.
        if screenAway, !Self.screenIsAwayNow() {
            log.notice("wake word: the screen is back (its notice never came)")
            screenAway = false
        }
        var state = ArisWakeArm.State(settingOn: Defaults[.arisWakeWord], conversationOpen: conversation.isOpen, idle: session.phase == .idle,
                                      training: training != nil, listenerOpen: listener != nil, screenAway: screenAway,
                                      permissionOK: Self.permissionProblem() == nil,
                                      onboardingSeen: UserDefaults.standard.bool(forKey: ArisOnboarding.seenKey),
                                      speechReady: Self.wakeSpeechReady)
        // The audio devices are watched from the first time the wake word is asked for: a headset that connects or
        // goes, or a lid that closes, is met by choosing the microphone again (micDevicesChanged).
        if Self.micWatch == nil { Self.micWatch = ArisMicWatch { [weak self] in self?.micDevicesChanged() } }
        let micPlan = ArisMicDevices.plan(for: .wake)
        state.headsetOnly = micPlan == .pause(.headsetOnly)
        // The lid, the power and another app's microphone, read now, before anything is opened (ArisWakeRest).
        ArisWakeRestLive.shared.fill(&state)
        // Another app plays or records (checked now, before anything is armed): a conversation doesn't listen between
        // turns until it stops (ArisOtherAudio).
        if ArisWakeArm.blocker(state) == nil, conversation.isOpen, !pausedForOtherAudio, otherAudioPresent() { pausedForOtherAudio = true }
        state.otherAudio = pausedForOtherAudio
        let blocker = ArisWakeArm.blocker(state)
        if let line = wakeArmLog.line(for: blocker) { log.notice("\(line, privacy: .public)") }
        ArisWakeRestLive.shared.note(state) { [weak self] in self?.wakeRestChanged() ?? true }
        switch blocker {
        case .settingOff?, .otherAudio?, .headsetOnly?: return stopWaitingForWakeWord()
        // Resting (ArisWakeRest): the microphone closes, and macOS's indicator with it, until the reason ends.
        case .lidClosed?, .micInUse?, .lowPower?: return stopWaitingForWakeWord()
        case .speechModel?:
            // Never the microphone for a check that can't succeed: it stays closed while the model is waited for.
            stopWaitingForWakeWord()
            return waitForSpeechModel()
        case .some: return
        case nil: break
        }
        // After a wake-word turn the detector is still on (it was the turn's microphone): just listen again.
        if let detector, !ArisMicPlan.mustReopen(openOn: detector.openDevice ?? micPlan.device, plan: micPlan) {
            detector.pause(conversation.isOpen)
            return updateVoiceWatch()
        }
        // The detector is on a device the plan no longer names (the devices changed under it): opened again.
        if detector != nil { stopWaitingForWakeWord() }
        startDetector(paused: conversation.isOpen)
        updateVoiceWatch()
        log.notice("\(self.conversation.isOpen ? "listening between turns" : "waiting for the wake word", privacy: .public) (\(self.hasWakeModel ? "trained" : "not trained", privacy: .public))")
    }

    /// The list of audio devices or the default input changed (ArisMicWatch). A wake word that waits idle is looked at
    /// again: paused when a headset's microphone is now the only one, opened again when the plan names another
    /// device, started when a microphone it may use is back. A turn under way is left alone (its own microphone ends
    /// with it); the next wait chooses again.
    func micDevicesChanged() {
        guard session.phase == .idle, training == nil, listener == nil, wakeListener == nil else { return }
        waitForWakeWord()
    }

    /// Waits, with no microphone open, until macOS's speech model for Aris's language is on this Mac, then arms the
    /// wake word. A missing model is installed (or its running install joined) and looked for again after half a
    /// minute, two minutes and ten; then it stops looking until waitForWakeWord() is next called (a turn, the setting,
    /// the screen coming back).
    func waitForSpeechModel() {
        guard Self.wakeSpeechWait == nil else { return }
        Self.wakeSpeechWait = Task { [weak self] in
            defer { Self.wakeSpeechWait = nil }
            var tries = 0
            while !(await ArisListener.speechModelInstalled(locale: Self.locale)) {
                await ArisListener.prepareSpeechAssets(locale: Self.locale)
                if await ArisListener.speechModelInstalled(locale: Self.locale) { break }
                guard let pause = ArisWakeArm.speechRecheck(after: tries) else {
                    log.notice("wake word: the speech model still isn't here; not looking again until something changes")
                    return
                }
                tries += 1
                try? await Task.sleep(for: pause)
                guard !Task.isCancelled else { return }
            }
            Self.wakeSpeechReady = true
            // After this task has ended (its slot is free for the next wait).
            Task { @MainActor [weak self] in self?.waitForWakeWord() }
        }
    }

    /// A wake check's recognizer couldn't start (the speech model went missing, or the recognizer failed): the check
    /// ends here and the microphone closes, instead of being handed back to the detector to fail again on the next
    /// sound. It opens again after a pause that grows with each failure in a row, and after the third stays closed.
    func wakeListenFailed(_ listener: ArisListener) {
        guard wakeListener === listener else { return }
        Self.wakeListenFailures += 1
        // Asked again before the microphone next opens.
        Self.wakeSpeechReady = false
        stopWaitingForWakeWord()
        guard let pause = ArisWakeArm.pause(afterListenFailures: Self.wakeListenFailures) else {
            return log.notice("wake word: \(Self.wakeListenFailures, privacy: .public) checks in a row couldn't listen; the microphone stays closed")
        }
        log.notice("wake word: the check couldn't listen; the microphone is closed for \(pause, privacy: .public)")
        waitForWakeWordSoon(after: pause)
    }

    /// The Mac is locked or its main display asleep, asked now (not from the notices).
    static func screenIsAwayNow() -> Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        let locked = session?["CGSSessionScreenIsLocked"] as? Bool ?? false
        return locked || CGDisplayIsAsleep(CGMainDisplayID()) != 0
    }

    /// The idle microphone: candidates wake Aris when it's idle, and interrupt it while it talks. `paused`: no
    /// candidates (a conversation listens for any voice through its voice watch).
    func startDetector(paused: Bool = false) {
        let detector = ArisWakeDetector()
        detector.onCandidate = { [weak self, weak detector] score, sure in
            guard let self, let detector, self.detector === detector else { return }
            // Between turns of a conversation any voice is a turn (voiceStarted); no name is checked.
            guard !self.conversation.isOpen || self.session.phase == .speaking else { return }
            if self.session.phase == .speaking {
                self.checkBargeIn(with: detector, score: score, sure: sure)
            } else {
                self.checkWakeWord(with: detector, score: score, sure: sure)
            }
        }
        detector.onVoiceStart = { [weak self, weak detector] sample, lookback in
            guard let self, self.detector === detector else { return }
            self.voiceStarted(from: sample, lookback: lookback)
        }
        detector.onVoice = { [weak self, weak detector] talking in
            guard let self, self.detector === detector else { return }
            self.heardVoice(talking)
            guard self.session.phase == .speaking else { return }
            // Talking over Aris turns it down at once (ChatGPT does the same); "아리스" still stops it.
            // Headphones only: through speakers the mic would hear Aris and keep turning it down.
            guard ArisDucking.outputIsHeadphones() else { return }
            if talking { self.speaker.duck() } else { self.speaker.unduck() }
        }
        detector.onInterrupted = { [weak self] in
            // Each reopen starts and stops the speakers' IO too: changes that keep coming are met with a growing pause.
            Self.wakeRestarts = ArisAudioQuiet.wakeRestarts(after: Self.wakeRestarts, ranFor: Self.wakeOpenedAt.map { ContinuousClock.now - $0 })
            let delay = ArisAudioQuiet.wakeRestartDelay(restarts: Self.wakeRestarts)
            log.notice("wake word: microphone changed, restarting in \(delay, privacy: .public) (\(Self.wakeRestarts, privacy: .public) in a row)")
            self?.stopWaitingForWakeWord()
            self?.restartDetectorSoon(after: delay)
        }
        // The microphone opens off the main thread (it can wait seconds for a Bluetooth device); its stop is queued
        // behind it.
        self.detector = detector
        Self.wakeOpenedAt = ContinuousClock.now
        let model = Self.loadWakeModel()
        ArisAudio.microphoneQueue.async {
            do {
                try detector.start(.waiting(model), paused: paused)
            } catch {
                log.error("wake word: couldn't listen: \(String(describing: error), privacy: .public)")
                Task { @MainActor [weak self] in
                    guard let self, self.detector === detector else { return }
                    self.detector = nil
                    // Tried again after a growing pause, a second to a minute: a microphone plugged in later, or audio
                    // that wasn't ready at login, is found without waiting for the next turn to end (audit voice-11).
                    Self.wakeRestarts = ArisAudioQuiet.wakeRestarts(afterFailedOpen: Self.wakeRestarts)
                    self.restartDetectorSoon(after: ArisAudioQuiet.wakeRestartDelay(restarts: Self.wakeRestarts))
                }
            }
        }
    }

    // MARK: - Interrupting

    /// While Aris talks, the detector listens for "아리스" (it needs a trained voice print: untrained, every
    /// phrase, Aris's own voice included, would be a candidate).
    /// In a conversation the voice watch stops Aris too (updateVoiceWatch); "아리스" in your trained voice still does.
    func armBargeIn() {
        guard !screenAway, training == nil else { return }
        if conversation.isOpen { updateVoiceWatch() }
        // Not while the wake word rests (a call is on, the battery is being saved): the talk key still stops Aris.
        guard Defaults[.arisWakeWord], hasWakeModel, !ArisWakeRestLive.shared.keepsMicrophoneClosed else { return }
        if let detector { return detector.pause(false) }
        startDetector()
    }

    /// A likely "아리스" while Aris is talking. Its own voice through the speakers reaches the microphone too,
    /// so only a sure match with your voice, or Whisper hearing the name, stops it.
    func checkBargeIn(with detector: ArisWakeDetector, score: Float?, sure: Bool) {
        // Its score against the voice print's threshold, so a check with the user's own voice is easy to read.
        let threshold = Self.loadWakeModel()?.threshold
        log.notice("barge-in: score \(score.map { String(format: "%.2f", $0) } ?? "none", privacy: .public) threshold \(threshold.map { String(format: "%.2f", Double($0)) } ?? "none", privacy: .public) sure \(sure, privacy: .public)")
        guard sure else {
            detector.pause(true)
            wakeWhisper?.cancel()
            wakeWhisper = Task {
                let audio = await Self.wakeClip(from: detector)
                let text = audio.isEmpty ? nil : (try? await ArisWhisper.shared.transcribe(audio)) ?? nil
                guard !Task.isCancelled, self.detector === detector, self.session.phase == .speaking else { return }
                guard let text, ArisWakeWord.heard(text) else { return detector.pause(false) }
                self.interrupt(with: detector, score: score, path: "whisper")
            }
            return
        }
        interrupt(with: detector, score: score, path: "voice")
    }

    /// How long to wait for a likely "아리스" to have enough sound for Whisper (it fires as soon as the voice print
    /// matches, often under a second in).
    static let wakeClipWait: Duration = .milliseconds(1200)

    /// The candidate phrase for Whisper: at least ~1.2 s of it when it comes in time, padded with silence to the
    /// length Whisper needs (it skips anything under a second).
    static func wakeClip(from detector: ArisWakeDetector) async -> [Float] {
        let enough = Int(ArisVoicePrint.sampleRate * 1.2)
        let deadline = ContinuousClock.now + wakeClipWait
        var audio = detector.candidateAudio(seconds: wakeWhisperSeconds)
        while audio.count < enough, ContinuousClock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
            audio = detector.candidateAudio(seconds: wakeWhisperSeconds)
        }
        return audio.isEmpty ? [] : ArisTranscript.paddedForWhisper(audio, sampleRate: ArisVoicePrint.sampleRate)
    }

    /// "아리스" while Aris talks: it stops and listens to the new request, as Siri does. Music stays paused.
    func interrupt(with detector: ArisWakeDetector, score: Float?, path: String) {
        guard session.phase == .speaking else { return }
        log.notice("interrupted (\(path, privacy: .public))")
        ArisTuningLog.append(["score": score.map(Double.init) ?? -1, "sure": path == "voice", "path": "interrupt-" + path,
                              "whisper": ""], to: "wake-log.jsonl")
        turn?.cancel()
        speaker.stop()
        pauseWatch?.cancel()
        handsFree = false
        followingUp = false
        session = session.done()
        checkWakeWord(with: detector, score: score, sure: true)
    }

    /// A likely "아리스". When the voice print is `sure` (as close as your own recordings), the notch opens
    /// now, like Siri. Otherwise the recognizer hears the phrase from its start, and Whisper hears its first
    /// second or so; either finding the name wakes Aris. (Voice prints alone can't tell a real call from
    /// other talk, and the recognizer rarely writes a lone short "아리스" down.)
    func checkWakeWord(with detector: ArisWakeDetector, score: Float?, sure: Bool) {
        guard wakeListener == nil, session.phase == .idle else { return }
        detector.pause(true)
        let listener = ArisListener()
        var whisperHeard: String?
        let note = { (path: String) in
            // What a phrase that was not the name said is never written down (ArisWakeRest.kept): only that one was checked.
            ArisTuningLog.append(["score": score.map(Double.init) ?? -1, "sure": sure, "path": path,
                                  "whisper": ArisWakeRest.kept(whisperHeard, path: path)], to: "wake-log.jsonl")
        }
        listener.onText = { [weak self, weak listener] text in
            guard let self, let listener else { return }
            guard ArisWakeWord.heard(text) else { return log.debug("wake word: checking, heard \(text.count, privacy: .public) characters") }
            guard self.wakeListener === listener else { return }
            note("recognizer")
            self.wake(listener, heard: text)
        }
        // The speech engine can't hear (the older engine with macOS Dictation off): the check ends as one that
        // couldn't listen, and the microphone closes for a while (wakeListenFailed).
        listener.onProblem = { [weak self, weak listener] line in
            guard let self, let listener, self.wakeListener === listener else { return }
            log.error("wake word: the speech engine can't hear: \(line, privacy: .public)")
            self.wakeListenFailed(listener)
        }
        wakeListener = listener
        let started = Task {
            do {
                try await Self.within(Self.startTimeout) {
                    // From just before the candidate phrase began, whatever was said since (ArisWakeDetector.forward).
                    try await listener.start(locale: Self.locale, waitingForWakeWord: true, source: detector, from: detector.candidateSample)
                }
                Self.wakeListenFailures = 0
            } catch {
                log.error("wake word: couldn't listen: \(String(describing: error), privacy: .public)")
                // Never carried on with a recogniser that isn't running (audit voice-7).
                switch ArisWakeStartFailure.after(isTurnListener: self.listener === listener, isWakeListener: self.wakeListener === listener) {
                case .failTurn:
                    // Aris already woke (your voice was sure): the turn says why, as a key press's does.
                    if let line = ArisStartFailure.line(error, timedOut: error is TimedOut, abandoned: false) { self.fail(line) }
                case .dropCheck:
                    // Whisper hearing the name must not open a turn nobody hears; the check ends as "not 아리스".
                    self.wakeWhisper?.cancel()
                case .nothing:
                    break
                }
                // While it was still only a check, the microphone also closes and opens again after a pause (fresh install F4).
                self.wakeListenFailed(listener)
            }
        }
        if sure {
            log.notice("wake word: your voice")
            note("voice")
            return wake(listener, heard: "", starting: started)
        }
        wakeWhisper = Task {
            let audio = await Self.wakeClip(from: detector)
            let start = ContinuousClock.now
            let heard = audio.isEmpty ? nil : (try? await ArisWhisper.shared.transcribe(audio)) ?? nil
            log.notice("wake word: Whisper on \(Double(audio.count) / ArisVoicePrint.sampleRate, privacy: .public) s heard “\(heard ?? "(nothing)", privacy: .private)” in \(Int((ContinuousClock.now - start) / .milliseconds(1)), privacy: .public) ms")
            guard let text = heard, !Task.isCancelled, self.wakeListener === listener else { return }
            whisperHeard = text
            guard ArisWakeWord.heard(text) else { return }
            log.notice("wake word: Whisper heard it")
            note("whisper")
            self.wake(listener, heard: "", starting: started)
        }
        wakeCheck = Task {
            await started.value
            try? await Task.sleep(for: Self.wakeCheckTime)
            guard self.wakeListener === listener else { return }
            log.notice("wake word: not 아리스 after all")
            note("rejected")
            self.wakeListener = nil
            _ = await listener.stop()
            self.detector?.pause(false)
        }
    }

    func stopWaitingForWakeWord() {
        wakeRestart?.cancel()
        wakeCheck?.cancel()
        wakeWhisper?.cancel()
        detector?.stop()
        detector = nil
        // Its gate can't say the user stopped talking any more.
        userTalking = false
        guard let listener = wakeListener as? ArisListener else { return }
        wakeListener = nil
        listener.onText = nil
        Task { _ = await listener.stop() }
    }

    // MARK: - Training "아리스"

    /// Settings → Aris → Train: the notch opens and you say "아리스" a few times.
    func startTraining() {
        guard session.phase == .idle, training == nil else { return }
        guard Self.permissionProblem() == nil else {
            return fail(ArisPermissionWords.pressKeyFirst())
        }
        stopWaitingForWakeWord()
        trainingRecordings = []
        training = Training()
        let detector = ArisWakeDetector()
        detector.onLevel = { [weak self] in self?.level = $0 }
        detector.onPhrase = { [weak self] phrase in self?.trainingHeard(phrase) }
        do {
            try detector.start(.training)
            self.detector = detector
            log.notice("training the wake word")
        } catch {
            endTraining()
            return fail(ArisStartFailure.line(error, timedOut: error is TimedOut, abandoned: false) ?? ArisStartFailure.tookTooLong)
        }
        trainingTimeout = Task { [weak self] in
            try? await Task.sleep(for: Self.trainingTimeLimit)
            guard !Task.isCancelled else { return }
            self?.endTraining()
        }
    }

    func trainingHeard(_ phrase: [Float]) {
        guard var current = training, !current.done else { return }
        let seconds = Double(phrase.count) / ArisVoicePrint.sampleRate
        guard (0.3...2.5).contains(seconds) else {
            current.message = ArisWakeWords.unclear(tooShort: seconds < 0.3)
            training = current
            return
        }
        trainingRecordings.append(phrase)
        current.count = trainingRecordings.count
        guard current.count >= ArisWakeModel.recordingsNeeded else {
            current.message = ArisWakeWords.again()
            training = current
            return
        }
        guard let model = ArisWakeModel.trained(from: trainingRecordings), let file = Self.wakeModelFile,
              (try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)) != nil,
              (try? JSONEncoder().encode(model).write(to: file, options: .atomic)) != nil else {
            trainingRecordings = []
            training = Training(count: 0, message: ArisWakeWords.restart())
            return
        }
        log.notice("wake word trained (wakes at \(model.threshold, privacy: .public))")
        hasWakeModel = true
        detector?.stop()
        detector = nil
        level = 0
        training = Training(count: current.count, message: ArisWakeWords.done(), done: true)
        Task {
            if ArisQuietGate.maySound(.user) { await speaker.speak(ArisWakeWords.doneSpoken()) }
            try? await Task.sleep(for: Self.lingerAfterAnswer)
            self.endTraining()
        }
    }

    func endTraining() {
        trainingTimeout?.cancel()
        detector?.stop()
        detector = nil
        trainingRecordings = []
        level = 0
        guard training != nil else { return }
        training = nil
        waitForWakeWordSoon()
    }

    /// "아리스" heard: the waiting listener carries on as this turn's, hands-free.
    func wake(_ listener: ArisListener, heard text: String, starting started: Task<Void, Never>? = nil) {
        guard session.phase == .idle, wakeListener === listener else { return }
        // Read before Aris pauses anything: another app's sound means the name may have come from it.
        let otherAudio = otherAudioPresent(forConversation: conversation.isOpen
                                           || ArisConversation.enabled(silenceSeconds: Defaults[.arisConversationSilence]))
        wakeListener = nil
        wakeCheck?.cancel()
        wakeWhisper?.cancel()
        log.notice("heard the wake word")
        // The 대화 이어가기 setting holds for a turn started by voice too: past it, a new conversation (QA BUG-49).
        if let lastTurnAt, ContinuousClock.now - lastTurnAt > Self.conversationLasts { endConversation() }
        turn?.cancel()
        speaker.stop()
        openConversation()
        listener.beginTurn()
        Self.listeningHaptic()
        ArisAgentClient.warm(ArisBrain.named(Defaults[.arisBrain]))
        recordingLead = .milliseconds(Int(listener.recordedSeconds * 1000))
        seeTurnStarting()
        session = session.listening().hearing(text)
        listeningSince = .now
        let saidMore = !text.isEmpty && !ArisWakeWord.isOnlyTheName(text)
        lastWordsAt = saidMore ? .now : nil
        lastVoiceAt = saidMore ? .now : nil
        voicePeak = 0
        turnVoiceFrames = 0
        practiceTurn = onboardingTalk == .practice
        voiceFloor = ArisTalkKey.startingFloor
        pauseScore = nil
        preparedWhisper = nil
        pauseMusic()
        scribeOnWords = false
        turnHandsFree = ArisConversation.wakeTurnIsHandsFree(otherAudio: otherAudio)
        arisWasSaying = ""
        follow(listener)
        self.listener = listener
        startScribe(for: listener, replaying: listener.recordedSamples)
        starting = started
        // Woken before the recogniser ran (your voice was sure): the phrase it takes over from the detector lands in
        // the recording ahead of the turn, and Whisper's timing counts it once it's there (audit voice-2).
        if let started {
            Task {
                await started.value
                guard self.listener === listener, let since = self.listeningSince else { return }
                self.recordingLead = ArisWakeHandOver.lead(recordedSeconds: listener.recordedSeconds, sinceTurnBegan: .now - since)
            }
        }
        listenHandsFree()
    }
}
