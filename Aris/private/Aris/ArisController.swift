//
//  ArisController.swift
//  Aris
//
//  Runs a turn with Aris: press the hotkey (or say "아리스") and talk. Everyday
//  requests run on the Mac; everything else goes to the chosen AI through aris-agent.
//  Music pauses while Aris listens and talks, and picks up again afterwards.
//

import AppKit
import AVFoundation
import Defaults
import EventKit
import os
import Speech
import SwiftUI

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "turn")

@MainActor
final class ArisController: ObservableObject {
    static let shared = ArisController()

    @Published var session = ArisSession() {
        didSet {
            lastActivity = Date()
            if oldValue.phase == .speaking, session.phase != .speaking {
                arisStoppedAt = .now
                // The silence between turns counts from the end of Aris's own speech (QA BUG-49).
                conversation = conversation.spoke(at: Self.uptime)
            }
            if session.phase != oldValue.phase || session.question != oldValue.question { updateVoiceWatch() }
            // The card's click hold follows the card: gone with it, and started for a card put up by any path (ArisCardHold).
            if session.question?.id != oldValue.question?.id { ArisCardStill.shared.follow(session.question?.id) }
            // So does what has been seen of it: the next card starts unread (ArisCardRead).
            if session.question?.id != oldValue.question?.id { ArisCardReadLive.shared.follow(session.question?.id) }
            guard session.phase == .idle, oldValue.phase != .idle else { return }
            // Whatever ended the turn, no overlay it put up stays on screen (QA BUG-44).
            closeGestureLeftovers()
            endedDictation = dictation != nil
            dictation = nil
            if dictationQueue.waiting { dictationQueue = ArisDictationQueue() }
            announcing = nil
            // The brief parked after it was said keeps its tiles (QA BUG-19b); any other end lets it go.
            if session.reply != brief?.summary { brief = nil }
            followingUp = false
            // In a conversation Aris listens again at once (ArisController+Conversation); only a turn that reached the AI
            // counts as speech for the silence clock.
            settleConversation(reachedAI: turnReachedAI, heard: turnHeard)
            turnReachedAI = false
            waitForWakeWordSoon(after: conversation.isOpen ? .zero : Self.wakeDelayAfterTurn)
            turnHeard = false
        }
    }
    /// The always-on conversation (ArisController+Conversation): its stage and silence clock.
    var conversation = ArisConversation() {
        didSet { if inConversation != conversation.isOpen { inConversation = conversation.isOpen } }
    }
    /// A conversation is open (published for the notch; `conversing` is its between-turns state).
    @Published var inConversation = false
    var conversationWatch: Task<Void, Never>?
    var escapeMonitors: [Any] = []
    /// Aris's own announcements waiting for a pause, first come, first said.
    var announcements = ArisAnnouncements()
    /// The user is talking now (the wake detector's gate), when their voice was last heard, and when Aris last stopped talking.
    var userTalking = false
    var lastHeardVoiceAt: ContinuousClock.Instant?
    var arisStoppedAt: ContinuousClock.Instant?
    /// Listening between turns of a conversation: the notch shows the calm listening state.
    var conversing: Bool { inConversation && session.phase == .idle }
    /// Dictating with the right ⌥ (ArisController+Dictation): the words go where the cursor is, not to an AI.
    @Published var dictation: ArisDictationStage?
    /// A right-⌥ press that came while the last dictation was still being typed: it starts once the words are in.
    @Published var dictationQueue = ArisDictationQueue()
    /// What Aris is telling you unasked (a timer ran out), shown without a voice.
    @Published var announcing: String?
    /// The morning brief on screen (ArisController+Brief).
    @Published var brief: ArisBrief?

    /// The brief's tiles show: while it is said, and parked after it, until the next answer (QA BUG-19b: parked, the
    /// spoken sentence replaced the tiles).
    var briefTilesShown: Bool {
        guard let brief else { return false }
        return session.phase == .speaking || (session.phase == .idle && session.reply == brief.summary)
    }
    /// The turn that just ended was dictation: the notch closes at once (its words are already in place).
    private(set) var endedDictation = false
    /// Loudness of whoever is talking (you, then Aris), 0...1, for the orb. Published on `audioLevel`, not here, so
    /// views observing the controller don't re-render at audio rate.
    let audioLevel = ArisAudioLevel()
    var level: Float {
        get { audioLevel.value }
        set { if audioLevel.value != newValue { audioLevel.value = newValue } }
    }

    var isActive: Bool { session.phase != .idle || training != nil }

    /// A streamed answer reaches the notch at most 30 times a second (showAnswer): the newest text waits in the pacer,
    /// stamped with its turn.
    private var answerPacer = ArisReplyPacer(interval: 1.0 / 30)
    private var answerFlush: DispatchWorkItem?

    /// Teaching Aris your "아리스" (shown in the notch): how many times you've said it, and what to say.
    struct Training: Equatable {
        var count = 0
        var message = ArisWakeWords.start()
        var done = false
    }
    @Published var training: Training?
    @Published var hasWakeModel = ArisController.loadWakeModel() != nil

    static var locale: Locale { ArisHearing.locale }
    static let lingerAfterAnswer: Duration = .seconds(1.5)
    static let lingerAfterFailure: Duration = .seconds(4)
    static let startTimeout: Duration = .seconds(8)
    static let stopTimeout: Duration = .seconds(5)
    static let speakTimeout: Duration = .seconds(40)
    /// Past this, Aris goes with Apple's transcript rather than keep you waiting.
    static let whisperTimeout: Duration = .seconds(3)
    /// Quiet this long while the AI works, Aris says it's on it.
    static let holdAfter: Duration = .milliseconds(1200)

    let speaker = ArisSpeaker()
    static let heardSound: NSSound? = {
        let sound = NSSound(named: "Tink")
        sound?.volume = 0.35
        return sound
    }()
    var listener: AnyObject?
    var starting: Task<Void, Never>?
    /// The running turn. When it ends by itself the notch is looked at once more (ArisController+Watch): a state it
    /// left behind is put back to idle.
    var turn: Task<Void, Never>? {
        didSet { watchTurnEnd(turn) }
    }
    /// The turn in progress, in numbers (ArisController+Stats), from when Aris stopped listening.
    var stats: ArisTurnStats?
    var resumeMusic = false
    /// The hotkey is down right now (the onboarding's 단축키 page lights its keycaps while it is).
    @Published var keyHeld = false
    /// You tapped the key instead of holding it: Aris listens until you pause.
    @Published var handsFree = false
    /// The circled shots' thumbnails for the prompt's chips, by badge: this turn's only, in memory, never saved.
    @Published var shotThumbs: [Int: NSImage] = [:]
    /// The skill this turn's answer follows (the brain read it: `aris-tools skill read`), shown as "<title> 스킬 사용 중".
    @Published var skillInUse: String?
    var keyDownAt: ContinuousClock.Instant?
    private var tapProbe: ArisTapProbe?
    /// The key press that is down now is the one that started listening.
    var pressStartedTurn = false
    var listeningSince: ContinuousClock.Instant?
    var lastWordsAt: ContinuousClock.Instant?
    var lastVoiceAt: ContinuousClock.Instant?
    /// Your loudest moment this turn (for the pause log, and Whisper alone: ArisTranscript.trustsAlone).
    var voicePeak: Float = 0
    /// Voice readings this turn: the evidence of speech when no recognizer wrote a word (QA BUG-30).
    var turnVoiceFrames = 0
    /// This listening began on the onboarding's 물어보기 page: its turn is answered read-only (QA BUG-31).
    var practiceTurn = false
    /// The room's noise this turn: voice is what stands well above it.
    var voiceFloor = ArisTalkKey.startingFloor
    /// Smart Turn's score for the pause after the voice heard at `voiceAt` (ArisController+Turn).
    var pauseScore: (voiceAt: ContinuousClock.Instant, score: Float)?
    var scoringPause = false
    /// Voice readings since the grace moment began (ArisController+Turn).
    var graceVoiceFrames = 0
    /// Whisper's reading of the turn, started during the grace moment; good only while no voice came after `voiceAt`.
    var preparedWhisper: (voiceAt: ContinuousClock.Instant?, task: Task<String?, Never>)?
    /// The turn streaming to ElevenLabs Scribe (ArisScribe), while it's being heard; nil: Whisper listens.
    var scribe: ArisScribe?
    /// Scribe has sent words this turn: they, not Apple's Korean-only ones, are what the notch shows.
    var scribeIsHearing = false
    /// A conversation's turn warms the brain and starts streaming to Scribe at its first words (ArisController+Conversation).
    var scribeOnWords = false
    /// This turn was heard hands-free: started by voice in a conversation, no key and no name (ArisHandsFree, agent side).
    var turnHandsFree = false
    /// This turn was typed in the composer (the user at the keyboard), not heard.
    var turnTyped = false
    /// This turn went to the AI (askAndSpeak): only such a turn restarts the conversation's silence clock.
    var turnReachedAI = false
    /// This turn's words were understood and answered (any path, local too): it restarts the silence clock (QA BUG-49).
    var turnHeard = false
    /// What Aris was saying when the user talked over it: words of it heard back are dropped from their turn (ArisEchoTrim).
    var arisWasSaying = ""
    /// Between-turn listening is paused while another app plays or records (ArisOtherAudio); the band shows it.
    @Published var pausedForOtherAudio = false
    /// How loud other apps are, while a conversation listens and one of them has output open.
    let outputMeter = ArisOutputMeter()
    /// The meter hears only zeros while an app that plays has output open: System Audio permission is likely missing
    /// (settings says so).
    @Published var systemAudioMissing = false
    /// Aris's own words that may come back at the start of a barge-in turn on speakers: at most this many (ArisEchoTrim).
    var echoWords = 0
    /// The language the last turn was in (Scribe's code), for the answer and the voice.
    var heardLanguage: String?
    /// When the last answer finished: the conversation carries on until 닫기 or this long without a turn.
    var lastTurnAt: ContinuousClock.Instant?
    /// When this conversation's first turn was recorded (nil before it): how far back "undo that" reaches (ArisUndoWords.reach).
    var conversationBeganAt: Date?
    /// The next question starts a new conversation: the agent drops the AI's thread (what it remembers of
    /// earlier turns, and the screen or web pages it read), so only `history` carries over.
    var freshConversation = true
    /// This conversation has seen the screen (the agent's untrusted reply said so): every later /ask says so too.
    var screenConversation = false
    /// This conversation has taken in outside text (the agent's untrusted reply said so): it never dispatches, and every
    /// later /ask says so, resumes too.
    var outsideConversation = false
    static var conversationLasts: Duration { .seconds(Defaults[.arisConversationMinutes] * 60) }
    var pauseWatch: Task<Void, Never>?
    /// Listening right after an answer: a follow-up needs no wake word, and silence ends the conversation.
    @Published var followingUp = false
    /// The answer on screen when Aris started listening for a follow-up: kept if nothing more is said.
    var answerBeforeFollowUp: (heard: String, reply: String)?
    /// The last few turns, so Claude can follow "그거" and "that one".
    var history: [ArisContext.Turn] = []
    /// Whether this turn's answer is in `history` and the 기록 tab yet (recorded once, before the voice reads it).
    var turnMemory = ArisTurnMemory()
    /// Long work handed to Aris ("조사해서 정리해 놔"), running in the background.
    @Published var jobs: [ArisJob] = [] {
        didSet {
            lastActivity = Date()
            director.update(jobs)
        }
    }
    /// The teammates' characters out of the notch: each job's teammate perches on its window (ArisDirector).
    let director = ArisDirector()
    /// When the turn or the jobs last changed: the star dozes off 10 minutes after (ArisCharacterMood).
    var lastActivity = Date()
    /// Which jobs run now and which wait (main actor only).
    var jobQueue = ArisWorkerQueue()
    /// How each job runs and its running task, by job id (main actor only).
    var jobRuns: [UUID: ArisJobRun] = [:]
    /// Jobs reported as not done, and how each ran: the card's 다시 시도 hands it out again (main actor only).
    var notDoneJobs: [UUID: ArisJobRun] = [:]
    /// Which Claude hook event ends a launched Claude Code teammate's job, and the jobs waiting for it (main actor only).
    var teammateWatch = ArisTeammateCompletion()
    var teammateWaits: [UUID: CheckedContinuation<ArisTeammateEnd, Never>] = [:]
    /// Delivering what scheduled jobs left in the agent's inbox (ArisController+Inbox), and whether to fetch again after.
    var inboxDelivery: Task<Void, Never>?
    var inboxAgain = false
    /// The history and context view of `jobs`.
    var tasks: [ArisBackgroundTask] { jobs.map(\.backgroundTask) }
    /// Finished tasks kept for "그거 어떻게 됐어?".
    static let keptTasks = 5
    /// Jobs that had finished when a conversation ended: no later conversation hears their words (ArisJobContext).
    var putAwayJobs: Set<UUID> = []
    /// Finished jobs the user marked seen (the open notch's "다 봤어요"): they leave its chip, not the 기록 tab (ArisDoneFold).
    @Published var seenDone: Set<UUID> = []
    /// The result file each finished job saved, for the chip's tray (main actor only).
    var jobFiles: [UUID: String] = [:]
    /// A task just finished: the closed notch shows a check for a moment.
    @Published var taskJustFinished = false
    /// Past turns and tasks for the Aris tab, newest first (kept across launches).
    @Published var pastTurns: [ArisHistoryEntry] = ArisHistory.load()
    /// The past turn put back in the notch from the 기록 tab (resume), for the line saying when it was.
    @Published var restored: ArisHistoryRestore.Shown?
    /// A yes or no given with a button or the Y/N keys while Aris asks.
    var typedAnswer: Bool?
    /// When a dictated message's countdown began (the confirm card's ring empties from here; ArisController+Countdown).
    @Published var countdownStarted: Date?
    /// The microphone while Aris is idle: loudness only, then a check against your trained "아리스".
    var detector: ArisWakeDetector?
    /// The recognizer checking a likely "아리스" (it becomes the turn's listener if it is).
    var wakeListener: AnyObject?
    var wakeRestart: Task<Void, Never>?
    /// Why the wake word last couldn't arm, said once per change (ArisWakeArm, QA BUG-38).
    var wakeArmLog = ArisWakeArm.Log()
    var wakeCheck: Task<Void, Never>?
    /// Whisper listening again to a likely "아리스" the recognizer may not write down.
    var wakeWhisper: Task<Void, Never>?
    var trainingRecordings: [[Float]] = []
    /// The Mac is locked or its screen is asleep.
    var screenAway = false
    var trainingTimeout: Task<Void, Never>?
    /// Audio recorded before the turn began (waiting for the wake word), for Whisper's timing.
    var recordingLead: Duration = .zero
    /// After a turn, so the end of Aris's own voice isn't heard as you.
    static let wakeDelayAfterTurn: Duration = .seconds(0.8)
    /// How long the recognizer has to find "아리스" in a likely phrase.
    static let wakeCheckTime: Duration = .seconds(3)
    /// The last card got no answer at all (it waited out its limit): what Aris says then isn't a "no" (QA BUG-39).
    var cardUnanswered = false
    /// How the open card's answer came (a click, a key, typed words, the band); nil while none did (ArisCardAnswer).
    var cardAnswerSource: ArisCardAnswer.Source?
    /// The open card's answer was heard, or its waiter left first: for the card's one log line.
    var cardHeardAnswer = false
    var cardEnded = false
    /// How much of a likely phrase Whisper hears: the name, and a little after it.
    static let wakeWhisperSeconds = 1.8
    static let trainingTimeLimit: Duration = .seconds(60)

    init() {
        speaker.onLevel = { [weak self] in self?.level = $0 }
        Task { await ArisWhisper.shared.prepare() }
        Task { await ArisListener.prepareHearing() }
        // The turn-end model loads now: a lazy load after an in-place update of the bundle would find no file.
        ArisTurnDetector.shared.warm()
        Task { [weak self] in
            for await _ in Defaults.updates(.arisWakeWord) { self?.waitForWakeWordSoon(after: .zero) }
        }
        watchScreen()
        watchForBrief()
        watchForDayEnd()
        watchInbox()
        watchTeammates()
        // The user's skills: the settings page and the notch's skill flows read the agent's status (ArisSkillsModel).
        ArisSkillsModel.shared.start()
    }

    // MARK: - Hotkey

    func keyDown() {
        guard training == nil else { return }
        if ArisConversation.keyPress(betweenTurns: listeningBetweenTurns, fromGesture: ArisGestureHooks.shared.gestureKeyPress) == .endConversation {
            pressStartedTurn = false
            return closeConversation(.key)
        }
        keyHeld = true
        keyDownAt = .now
        tapProbe = ArisTapProbe()
        let press = ArisTalkKey.press(listening: session.phase == .listening, handsFree: handsFree)
        pressStartedTurn = press == .start
        switch press {
        case .start:
            startListening()
            // Only once the microphone really opened: a turn that fails to start draws nothing.
            if session.phase == .listening, listener != nil {
                gestureKeyDown()
            }
        case .finish: stopListening()
        case .ignore: break
        }
    }

    func keyUp() {
        keyHeld = false
        guard pressStartedTurn, session.phase == .listening else {
            if pressStartedTurn { gestureKeyUpWithoutTurn() }
            return
        }
        pressStartedTurn = false
        // Starting the microphone can hold the main thread past the tap limit, so a quick tap would arrive here
        // looking like a long hold and end the turn at once; the probe saw the key itself.
        let heldFor = tapProbe?.wasTap == true ? .zero : (keyDownAt.map { ContinuousClock.now - $0 } ?? .zero)
        switch ArisTalkKey.release(heldFor: heldFor) {
        case .finish:
            stopListening()
        case .keepListening:
            listenHandsFree()
            gestureTapped()
        }
    }

    func startListening() {
        guard session.phase != .listening else { return }
        // A dictation whose "넣었어요" still lingers is over: this turn is Aris's own, so the dictation panel does not
        // show during it and the notch does not close at once when it ends.
        if dictation != nil { dictation = nil }
        seeTurnStarting()
        followingUp = false
        if let lastTurnAt, ContinuousClock.now - lastTurnAt > Self.conversationLasts { endConversation() }
        stopWaitingForWakeWord()
        // The user pressed the key: the screen is on, whatever a missed notice said (QA BUG-38).
        screenAway = false
        turn?.cancel()
        dropPendingAnswer()
        speaker.stop()
        handsFree = false
        pauseWatch?.cancel()
        if let problem = Self.permissionProblem() {
            log.notice("permissions not ready: \(problem.rawValue, privacy: .public)")
            return askForPermissions(problem)
        }
        pauseMusic()
        ArisAgentClient.warm(ArisBrain.named(Defaults[.arisBrain]))
        ArisTurnDetector.shared.warm()
        Self.listeningHaptic()
        openConversation()
        openMicrophone()
    }

    /// A fresh listening session: the counters reset, the recognizer and recording started.
    func openMicrophone() {
        session = session.listening()
        listeningSince = .now
        recordingLead = .zero
        lastWordsAt = nil
        lastVoiceAt = nil
        voicePeak = 0
        turnVoiceFrames = 0
        practiceTurn = onboardingTalk == .practice
        voiceFloor = ArisTalkKey.startingFloor
        pauseScore = nil
        preparedWhisper = nil
        scribeOnWords = false
        turnHandsFree = false
        arisWasSaying = ""
        let listener = ArisListener()
        listener.use = dictation == .listening ? .dictation : .talk
        follow(listener)
        self.listener = listener
        startScribe(for: listener)
        log.notice("listening")
        starting = Task {
            do {
                try await Self.within(Self.startTimeout) { try await listener.start(locale: Self.locale) }
                log.notice("microphone and recognizer running")
            } catch {
                // Abandoned: the turn was cancelled meanwhile (a ⌥⇧ press that turned out to be typing) or another started.
                // Nothing to report, and the listener now in use (if any) isn't this one (QA BUG-3).
                let abandoned = self.listener !== listener
                log.error("couldn't start listening\(abandoned ? " (abandoned)" : "", privacy: .public): \(String(describing: error), privacy: .public)")
                if !abandoned { self.listener = nil }
                // A start that timed out may still be opening the microphone: it closes as soon as it has (ArisListener.stopped).
                Task { _ = await listener.stop() }
                if let line = ArisStartFailure.line(error, timedOut: error is TimedOut, abandoned: abandoned) { fail(line) }
            }
        }
    }

    /// A turn's listener: the words and voice level drive the notch and the pause watch.
    func follow(_ listener: ArisListener) {
        listener.onText = { [weak self, weak listener] text in
            guard let self else { return }
            if text != self.session.heard, !ArisWakeWord.isOnlyTheName(text),
               text.unicodeScalars.contains(where: CharacterSet.alphanumerics.contains) {
                self.lastWordsAt = .now
                // A conversation's turn streams to Scribe only once it has words (noise never leaves the Mac).
                if self.scribeOnWords, let listener {
                    self.scribeOnWords = false
                    ArisAgentClient.warm(ArisBrain.named(Defaults[.arisBrain]))
                    self.startScribe(for: listener, replaying: listener.recordedSamples)
                }
            }
            guard !self.scribeIsHearing else { return }
            self.session = self.session.hearing(text)
        }
        listener.onLevel = { [weak self] level in
            guard let self else { return }
            self.level = level
            self.voicePeak = max(self.voicePeak, level)
            if ArisTalkKey.isVoice(level: level, floor: self.voiceFloor) {
                self.lastVoiceAt = .now
                self.graceVoiceFrames += 1
                self.turnVoiceFrames += 1
            }
            self.voiceFloor = ArisTalkKey.nextFloor(self.voiceFloor, level: level)
        }
        // The microphone changed or went away mid-turn (a headset connected, a device unplugged): the turn ends with a
        // reason, not on a silence timer with half the words.
        listener.onInterrupted = { [weak self] in
            guard let self, self.session.phase == .listening else { return }
            log.notice("microphone changed mid-turn")
            // A dictation's words are typed where the cursor is, never asked of the AI (audit voice-1).
            if self.dictation == .listening { return self.dictationInterrupted() }
            // Words already heard go on as the turn; nothing heard yet is a clean failure with a reason.
            if self.lastWordsAt != nil { self.stopListening() } else { self.fail(ArisUIWords.text("마이크가 바뀌어서 듣기를 멈췄어요. 다시 말해 주세요.", "The microphone changed, so I stopped listening. Please say it again.")) }
        }
        // The speech engine can't hear at all (the older engine with macOS Dictation off): said now, with what to do,
        // instead of an empty turn. Words already written go on as the turn or the dictation.
        listener.onProblem = { [weak self, weak listener] line in
            guard let self, let listener, self.listener === listener, self.session.phase == .listening else { return }
            log.notice("the speech engine can't hear: the turn ends with its reason")
            if self.dictation == .listening {
                return self.lastWordsAt != nil ? self.finishDictation() : self.failDictation(line, endsDictation: true)
            }
            if self.lastWordsAt != nil { self.stopListening() } else { self.fail(line) }
        }
    }

    /// Hands-free: send what you said once you pause.
    func listenHandsFree() {
        guard listener != nil else { return }
        handsFree = true
        log.notice("tapped: listening until you pause")
        pauseWatch = Task {
            while !Task.isCancelled && session.phase == .listening && handsFree {
                try? await Task.sleep(for: .milliseconds(200))
                let now = ContinuousClock.now
                let sinceStart = listeningSince.map { now - $0 } ?? .zero
                let said = ArisWakeWord.stripped(session.heard)
                let complete = ArisEndpoint.looksComplete(said), hanging = ArisEndpoint.isHanging(said)
                let sinceWords = lastWordsAt.map { now - $0 }, sinceVoice = lastVoiceAt.map { now - $0 }
                // Smart Turn only once there are words: a follow-up that's still only noise isn't scored.
                if !(followingUp && lastWordsAt == nil) { scorePauseIfNeeded(sinceVoice: sinceVoice) }
                let score = currentPauseScore
                if ArisTalkKey.heardEnough(sinceStart: sinceStart, sinceLastWords: sinceWords, sinceLastVoice: sinceVoice,
                                           waitForWords: followingUp ? ArisTalkKey.waitForFollowUp : ArisTalkKey.waitForWords,
                                           complete: complete, turnScore: score, hanging: hanging) {
                    let ms = { (gap: Duration?) in gap.map { Int($0 / .milliseconds(1)) } ?? -1 }
                    log.notice("you paused (loudest \(self.voicePeak, privacy: .public), quiet \(ms(sinceVoice), privacy: .public) ms, no new words \(ms(sinceWords), privacy: .public) ms, finished \(complete, privacy: .public), hanging \(hanging, privacy: .public), smart turn \(score.map { String(format: "%.2f", $0) } ?? "-", privacy: .public))")
                    logEndpoint(score: score, sinceVoice: sinceVoice, sinceWords: sinceWords, complete: complete, hanging: hanging, said: said)
                    // A follow-up that heard no words is over at once: no grace moment, so no Whisper on noise.
                    if followingUp, lastWordsAt == nil { return stopListening() }
                    // The cap, or no word in the longest wait: over now, whatever the room sounds like (audit voice-4).
                    if ArisTalkKey.mustEnd(sinceStart: sinceStart, heardWords: lastWordsAt != nil) { return stopListening() }
                    let confident = ArisTalkKey.isConfidentEnd(turnScore: score, complete: complete, hanging: hanging)
                    if await heldUpByGrace(confident: confident) { continue }
                    guard !Task.isCancelled else { return }
                    return stopListening()
                }
            }
        }
    }

    func stopListening() {
        gestureFinished()
        handsFree = false
        pauseWatch?.cancel()
        guard session.phase == .listening else { return }
        guard let listener = listener as? ArisListener else { return cancel() }
        // A follow-up where the recognizer never caught a word was noise or the tail of Aris's own voice
        // (2026-10-26 00:09: three letters of it went to Codex and got an answer). It ends the conversation.
        if followingUp && lastWordsAt == nil {
            log.notice("follow-up: nothing said")
            return conversation.isOpen ? dropFalseStart() : cancel()
        }
        let starting = self.starting
        log.notice("key released")
        // A soft tick the moment Aris stops listening, so you know it heard you (like Siri's).
        if lastVoiceAt != nil, ArisQuietLive.shared.heardUser() { Self.heardSound?.play() }
        stats = ArisTurnStats(startedAt: .now)
        turn = Task {
            // The drawing (if the user circled) is collected while the words are picked.
            async let drawn = collectGestureTurn()
            await starting?.value
            let apple = (try? await Self.within(Self.stopTimeout, cancelsWork: false) { await listener.stop() }) ?? session.heard
            let recording = listener.secondListenSamples
            self.listener = nil
            level = 0
            log.notice("heard \(apple.count, privacy: .public) characters")
            // Talking over Aris on speakers: its own words heard back at the start are dropped.
            let text = ArisEchoTrim.trimmed(ArisWakeWord.stripped(await secondListen(recording, apple: apple)), arisWasSaying: arisWasSaying,
                                            atMost: echoWords)
            arisWasSaying = ""
            echoWords = 0
            // The exact words, to tell a mishearing from a misunderstanding: in turns.jsonl (0600), private in the log.
            log.notice("you said “\(text, privacy: .private)” (Apple heard “\(apple, privacy: .private)”)")
            let gesture = await drawn
            guard session.phase == .listening, !Task.isCancelled else { return seeEnded() }
            if let gesture { attachGesture(gesture) }
            session = session.hearing(gesture?.display(text) ?? text).thinking()
            guard session.phase == .thinking else {
                // Nothing in the turn was speech (silence, noise, Whisper's made-up words): said so, nothing routed.
                if gesture == nil { return notHeard() }
                seeEnded()
                return resumeMusicIfPaused()
            }
            await answer(gesture == nil ? session.heard : text, gesture: gesture)
        }
    }

    /// Scribe's take on the turn when it streamed; else Whisper's when it's ready and quick enough; Apple's live one
    /// otherwise.
    func secondListen(_ recording: [Float], apple: String) async -> String {
        ArisHeardFix.corrected(await bestTranscript(recording, apple: apple))
    }

    private func bestTranscript(_ recording: [Float], apple: String) async -> String {
        let heardVoice = lastVoiceAt != nil
        let scribed = await finishScribe()
        heardLanguage = scribed?.language
        guard heardVoice, !recording.isEmpty else { return scribed?.text ?? apple }
        if let scribed {
            preparedWhisper?.task.cancel()
            preparedWhisper = nil
            stats?.recognized(apple: apple, whisper: scribed.text)
            return scribed.text
        }
        let start = ContinuousClock.now
        // Whisper read during the grace moment holds unless you talked again since (then it misses the end).
        let prepared = preparedWhisper.flatMap { $0.voiceAt == lastVoiceAt ? $0.task : nil }
        if prepared == nil { preparedWhisper?.task.cancel() }
        preparedWhisper = nil
        let whisper = if let prepared { await prepared.value } else { await whisperTranscript(recording) }
        let text = ArisTranscript.pick(whisper: whisper, apple: apple, heardVoice: heardVoice, voiceFrames: turnVoiceFrames, loudest: voicePeak,
                                       languages: Defaults[.arisLanguages], recognizer: Self.locale.identifier)
        stats?.recognized(apple: apple, whisper: whisper)
        let milliseconds = Int((ContinuousClock.now - start) / .milliseconds(1))
        log.notice("whisper: \(whisper == nil ? "not ready" : "\(text.count) characters", privacy: .public) in \(milliseconds, privacy: .public) ms\(prepared == nil ? "" : " (read during the grace moment)", privacy: .public)")
        if text.isEmpty, let whisper, !whisper.isEmpty {
            log.notice("whisper alone, taken for noise (\(whisper.count, privacy: .public) characters, \(self.turnVoiceFrames, privacy: .public) voice frames, loudest \(self.voicePeak, privacy: .public))")
        }
        return text
    }

    /// Whisper on the recording up to just after the last voice; nil when it isn't ready or too slow.
    func whisperTranscript(_ recording: [Float]) async -> String? {
        let voiceEnds = listeningSince.flatMap { since in lastVoiceAt.map { $0 - since + recordingLead } }
        let speech = ArisTranscript.trimmed(recording, voiceEndsAfter: voiceEnds, sampleRate: ArisWhisper.sampleRate)
        let limit = ArisLongTurn.whisperTimeout(samples: speech.count, sampleRate: ArisWhisper.sampleRate, first: Self.whisperTimeout)
        return (try? await Self.within(limit) { try await ArisWhisper.shared.transcribe(speech) }) ?? nil
    }

    // MARK: - The Aris tab

    func remember(_ entry: ArisHistoryEntry) {
        pastTurns = ArisHistory.adding(entry, to: pastTurns)
        ArisHistory.save(pastTurns)
    }

    /// Deletes past turns from the 기록 tab (its context menu, or the preview harness clearing its test turns).
    func forgetPastTurns(where remove: (ArisHistoryEntry) -> Bool) {
        pastTurns = ArisHistory.removing(pastTurns, where: remove)
        ArisHistory.save(pastTurns)
    }

    /// A past entry pressed in the 기록 tab: a saved result opens again; a conversation is shown again as it was
    /// (ArisHistoryRestore: your words, the answer, its card, when it was), with that turn as what "그거" means for
    /// whatever is said or typed next. Nothing is said aloud and the microphone stays shut.
    func resume(_ entry: ArisHistoryEntry) {
        if let file = entry.file {
            ArisBoard.shared.read(file: file)
            return
        }
        guard session.phase == .idle, training == nil else { return }
        history = [ArisContext.Turn(heard: entry.heard, reply: entry.reply)]
        lastAnswer = nil
        freshConversation = true
        screenConversation = entry.sawScreen == true
        outsideConversation = entry.sawOutside == true
        // The conversation picked up starts now: a last turn long ago must not end it as stale (the next turn would
        // clear the history and the marks just set: audit resume-1).
        lastTurnAt = nil
        let shown = ArisHistoryRestore.shown(entry)
        restored = shown
        ArisWidgetModel.shared.restore(ArisHistoryRestore.card(of: entry), reply: shown.reply)
        session = .parked(heard: shown.heard, reply: shown.reply)
        NotificationCenter.default.post(name: .arisHistoryRestored, object: nil)
    }

    /// A card's values arrived for the answer just recorded: kept with that turn (ArisHistoryRestore.attaching).
    func keepCard(_ card: ArisHistoryCard, forReply reply: String) {
        let next = ArisHistoryRestore.attaching(card, toReply: reply, in: pastTurns)
        guard next != pastTurns else { return }
        pastTurns = next
        ArisHistory.save(pastTurns)
    }

    /// Yes or no from the confirm card's buttons, the Y/N keys, typed words or the band (`source` says which: it is
    /// logged with the answer, ArisCardAnswer).
    func answerQuestion(_ allow: Bool, source: ArisCardAnswer.Source = .click) {
        guard let question = session.question else { return }
        // A click on yes counts only once the card has been still on screen for a moment: a click meant for the app
        // under a card that just came down is no yes (ArisCardHold; security review 3, L2). A no, a key, typed or
        // spoken words need no hold.
        if ArisCardHold.applies(allow: allow, source: source), !ArisCardStill.shared.clickCounts(card: question.id) {
            log.notice("a click on the card's yes came before the card had been still for a moment: ignored")
            return
        }
        // A pressed yes (the button, Y, Return) counts only once the card's end has been on screen: a card taller than its
        // room must be scrolled to its end first (ArisCardRead; security review 7, L1). A no and the user's own words need none.
        if ArisCardRead.applies(allow: allow, source: source, countdown: question.countdown), !ArisCardReadLive.shared.yesCounts(card: question.id) {
            log.notice("a pressed yes came before the card had been read to its end: ignored")
            return
        }
        if !question.fields.isEmpty {
            // The owner's ②A: typing ends first, so a Hangul syllable still being composed is in the value; a yes counts only
            // with every value readable and no change in the last second (ArisCardTiming).
            let changedBefore = ArisCardEditor.shared.changedAt
            NSApp.keyWindow?.makeFirstResponder(nil)
            if allow, !ArisCardEditor.shared.yesCounts(changedBefore: changedBefore) { return }
        }
        typedAnswer = allow
        cardAnswerSource = source
        speaker.stop()
    }

    /// A tap on the trackpad the moment Aris starts listening (felt with a finger on it).
    static func listeningHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    /// The turn's final reply, into the history the AI reads and the 기록 tab: once per turn (ArisTurnMemory), as
    /// soon as it's known and before the voice reads it. `job`: the one job a hand-out started, whose result updates it.
    func recordTurn(heard: String, reply: String, job: UUID? = nil) {
        guard turnMemory.record() else { return }
        if conversationBeganAt == nil { conversationBeganAt = Date() }
        history = ArisContext.remembering(ArisContext.Turn(heard: heard, reply: reply), after: history)
        remember(ArisHistoryEntry(date: Date(), heard: heard, reply: reply, sawScreen: screenConversation ? true : nil,
                                  sawOutside: outsideConversation ? true : nil, job: job))
        lastTurnAt = .now
    }

    /// 닫기 (ArisTurnClosing): the answer leaves the notch and a voice still reading it stops. An answer already
    /// delivered stays in the history and the turn logs "ok"; a turn still under way is dropped as Stop drops it.
    func dismissAnswer() {
        let closing = ArisTurnClosing.closing(phase: session.phase, remembered: turnMemory.remembered)
        if let outcome = closing.outcome { finishTurn(outcome) }
        if closing != .putAway { cancel() }
        // Files given to Aris go with 닫기 too, conversation or not: never with an unrelated next question.
        ArisAttachments.shared.clear()
        closeConversation(.dismissed)
        endConversation()
    }

    /// 닫기, or a long quiet: the answer is put away and the next turn starts a new conversation.
    func endConversation() {
        shotThumbs = [:]
        history = []
        lastAnswer = nil
        lastTurnAt = nil
        conversationBeganAt = nil
        freshConversation = true
        screenConversation = false
        outsideConversation = false
        putAwayJobs = ArisJobContext.puttingAway(tasks, into: putAwayJobs)
        if !isActive { session = ArisSession() }
    }

    /// Drops whatever Aris is doing (clicking the pill).
    func cancel() {
        log.notice("cancelled")
        gestureCancelled()
        finishTurn("cancelled")
        if training != nil { return endTraining() }
        handsFree = false
        pauseWatch?.cancel()
        turn?.cancel()
        dropPendingAnswer()
        starting?.cancel()
        speaker.stop()
        stopScribe()
        if let listener = listener as? ArisListener {
            Task { _ = await listener.stop() }
        }
        listener = nil
        level = 0
        // A follow-up that never came leaves the answer parked: the notch shows it again when
        // it opens, until 닫기 or the next turn.
        if followingUp, session.heard.isEmpty, let answer = answerBeforeFollowUp {
            session = .parked(heard: answer.heard, reply: answer.reply)
        } else {
            session = session.done()
        }
        answerBeforeFollowUp = nil
        resumeMusicIfPaused()
    }

    /// First use: macOS asks for the microphone and speech recognition, then the next press works.
    func askForPermissions(_ problem: PermissionProblem) {
        switch problem {
        case .denied:
            fail(ArisPermissionWords.turnOn)
        case .undecided:
            session = session.listening()
            turn = Task {
                let microphone = await AVCaptureDevice.requestAccess(for: .audio)
                let speech = await withCheckedContinuation { continuation in
                    SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
                }
                log.notice("permission answers: mic \(microphone, privacy: .public), speech \(speech.rawValue, privacy: .public)")
                // The calendar is never asked from a turn: onboarding's permission page or Settings does (QA BUG-55).
                guard microphone && speech == .authorized else {
                    return fail(ArisPermissionWords.turnOn)
                }
                // Granted while the key is still down (no dialog was needed): carry on listening.
                guard keyHeld else { return fail(ArisPermissionWords.ready) }
                session = session.done()
                startListening()
            }
        }
    }

    // MARK: - A turn

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
        // The onboarding's 물어보기: answered read-only here, nothing routed or done (QA BUG-31); files given to Aris
        // stay pending for a real turn.
        if practiceTurn { return await answerPractice(said) }
        // Never on a hands-free turn, nor while the notch is closed with no chips to see; gone after 5 minutes.
        let heard = ArisAttachments.shared.take(into: said, handsFree: turnHandsFree, shown: ArisNotchPresence.shared.isOpen)
        // What he asks of files he dropped is remembered by its shape, for the chips that learn (ArisDropLearned).
        ArisDropModel.shared.learn(from: heard)
        let shots = gesture?.hasShots == true
        // The files stand in for the screenshot; shots the user circled still go with their `[img N]` markers.
        if ArisPendingFiles.dropsTurnImages(heard, circledShots: shots) { seeEnded() }
        // The files' text came with it: outside text from here on, as anything read (QA BUG-35).
        if ArisAttachmentText.carriesText(heard) { outsideConversation = true }
        // "GPT한테 물어봐, …" goes straight to that AI; anything else tries the Mac first, then the default AI.
        let named = ArisBrain.pick(from: heard)
        // `whole` is what the AI or a job gets: the user's words, then the files they gave and their text. `unmarked` is their
        // own words alone, the only part ever read as a command, sent to the router or matched against a phrase (audit
        // files-1: a file named "timer 5 min.png" set a timer, and a document saying "in the background" became a job).
        let whole = named?.request ?? heard
        let unmarked = ArisPendingFiles.words(of: whole)
        let text = shots ? (gesture?.markedRequest(heard) ?? whole) : whole
        let brain = named?.brain ?? ArisBrain.named(Defaults[.arisBrain])
        // "응" or "아니" while the new-teammate card is up answers it first, on every path, before the done words and the
        // router (BUG-25c reopened: "응" went to the router and on to the brain, and the turn hung).
        let madeAnswer = !shots && named == nil ? ArisTeamMadeAnswer.reply(unmarked, cardUp: ArisTeamModel.shared.made != nil) : nil
        // A follow-up like "됐어" or "고마워" just ends the conversation.
        // "괜찮아" or "없어" right after Aris asked something answers it; it doesn't end the conversation.
        let afterQuestion = ArisFollowUp.asksSomething(history.last?.reply ?? "")
        if !shots, madeAnswer == nil, followingUp || conversation.isOpen, ArisFollowUp.isDone(ArisPendingFiles.words(of: text), afterQuestion: afterQuestion) {
            log.notice("follow-up: done")
            understood(text, path: "done", tier: .quick)
            finishTurn("ok")
            // The answer before "됐어" stays parked, as after a follow-up that never came.
            if let answer = answerBeforeFollowUp { session = .parked(heard: answer.heard, reply: answer.reply) } else { session = session.done() }
            answerBeforeFollowUp = nil
            closeConversation(.donePhrase)
            return resumeMusicIfPaused()
        }
        // A plain currency question ("100 위안 캐나다 달러로 얼마야") is read and answered here: never the router's or a brain's.
        let fx = !shots && named == nil && madeAnswer == nil ? currencyAsk(unmarked) : nil
        var intent = named == nil ? ArisGestureTurn.intent(unmarked: unmarked, marked: text, hasShots: shots) : .ask(text)
        var tier = ArisTier.quick
        var browserWork = false
        if named == nil, madeAnswer == nil, fx == nil, !ArisIntent.isRecurring(unmarked), needsSecondGuess(shots ? ArisIntent.parse(unmarked) : intent) {
            let routed = await route(unmarked)
            tier = routed.tier
            if !shots {
                // Several steps on websites go to the background for Aside on every brain; agy's job has no relay, so
                // agy hands it to Aside in the conversation instead (ArisAgyRelay).
                // Never Aris's own schedules, to-dos, memory, teammates, timers or settings: those are done in this turn
                // with their own tool and card (QA BUG-60: "… 예약 지워 줘" went to Aside as website work).
                browserWork = routed.browserWork && brain != .antigravity && !ArisOwnData.mentions(unmarked) && !ArisRoutineWords.mentions(unmarked)
                if let action = routed.intent { intent = action }
            }
        }
        // One guard for every local action, whichever matcher or router picked it (BUG-58 audit).
        if named == nil, !shots { intent = ArisIntent.guarded(intent, said: unmarked) }
        if ArisRouter.asksForCare(unmarked) { tier = .critical }
        let korean = ArisSpeech.language(of: unmarked) == "ko-KR"
        // Who the words are for is worked out before anything acts (the teammates' list may have to be read first).
        let plain = !shots && named == nil && madeAnswer == nil
        let link = plain ? ArisSkillIntent.link(in: unmarked) : nil
        let removal = plain && link == nil ? await teammateRemoval(unmarked) : nil
        let making = plain && link == nil && removal == nil ? ArisTeamMaking.parse(unmarked) : nil
        let called = plain && link == nil && removal == nil && making == nil ? await teammateCalled(unmarked) : nil
        // "<…> 다 했어": only an open item those words name exactly is ticked here; anything looser is the AI's (audit intent-2).
        var finishing: ArisTodoModel.Finishable?
        if case .finishTodo(let item) = intent { finishing = await ArisTodoModel.shared.finishable(item) }
        // Stopped or replaced while the router or the list was asked: this turn does nothing more (audit turn-2).
        guard !Task.isCancelled else { return }
        let reply: String
        if let yes = madeAnswer {
            // "응" or "아니" while the new-teammate card is up answers the card, never the brain (BUG-25c).
            understood(text, path: "local", tier: tier)
            reply = await answerMadeCard(yes)
        } else if let link {
            // "이 링크 스킬 추가해줘 <link>": Aris does it itself, no brain; the notch shows each step (ArisSkillFlowCard), and
            // the check goes on in aris-agent when the notch closes (the inbox says how it ended).
            understood(text, path: "local", tier: tier)
            let line = korean ? "스킬을 확인할게요." : "I'll check that skill."
            ArisSkillsModel.shared.startNotchFlow(request: session.heard, link: link)
            reply = korean ? "스킬 추가를 시작했어요." : "Started adding the skill."
            await sayLocal(reply, heard: unmarked, showing: line)
        } else if let removal {
            // "큐에이봇 팀원 지워 줘": asked with the settings' 빼기 card, removed only on yes; never a job (BUG-26).
            understood(text, path: "local", tier: tier)
            reply = await removeTeammate(removal)
        } else if let making {
            // "문서 정리하는 팀원 하나 만들어줘, 이름은 코디": made here, no brain; the notch shows it (ArisTeammateMadeCard).
            understood(text, path: "local", tier: tier)
            reply = await makeTeammate(making)
        } else if let job = called?.asking(whole) {
            // "큐에이봇, 17 곱하기 23은?": the teammate called by name takes it, on its own brain (BUG-25b), with the files
            // The user gave.
            understood(text, path: "task:teammate", tier: tier)
            stats?.firstSound(at: .now)
            let handed = handOut([job], turn: ArisHandOutPlan.Turn(words: unmarked, brain: brain, turnId: nil, screenConversation: screenConversation,
                                                                    outsideConversation: outsideConversation, handsFree: turnHandsFree),
                                 tier: tier, korean: korean)
            reply = handed.line
            session = session.answering(reply)
            // One 기록 entry, updated with the job's result (BUG-21).
            recordTurn(heard: unmarked, reply: reply, job: handed.job)
            await speak { await self.speaker.speak(reply) }
        } else if let fx {
            // The rate of exactly that pair, read through aris-agent; the line and the card are one number (ArisController+Currency).
            understood(text, path: "local", tier: tier)
            guard let told = await answerCurrency(fx, heard: unmarked, korean: korean) else { return }
            reply = told
        } else if let asked = ArisMemoryImportWords.asked(unmarked) {
            // "다른 AI에서 기억 가져올래": the import opens in Settings › 기억 (no AI); a named AI only fills in where it comes from.
            understood(text, path: "local", tier: tier)
            ArisMemoryImportModel.openFromWords(source: asked.source)
            reply = ArisMemoryImportWords.reply(korean: korean)
            await sayLocal(reply, heard: unmarked)
        } else if case .timerLeft = intent {
            understood(text, path: "local", tier: tier)
            reply = ArisTimerModel.shared.leftLine(korean: korean)
            await sayLocal(reply, heard: unmarked)
        } else if case .listTodos = intent {
            understood(text, path: "local", tier: tier)
            // Nil: the list could not be read (Reminders is off for Aris), and Aris says that, never "비어 있어요".
            let read = await ArisTodoModel.shared.summary(korean: korean)
            guard !Task.isCancelled else { return }
            // Canvas titles are other people's words: what's remembered for the AI is just that the list was read.
            reply = read == nil ? ArisLocalReply.todosUnread(korean: korean) : korean ? "할 일 목록을 읽어 줬어요." : "Read out the to-do list."
            await sayLocal(reply, heard: unmarked, showing: read)
        } else if case .addTodo(let item) = intent {
            understood(text, path: "local", tier: tier)
            // Said from what Reminders did with it (audit turn-1), and logged with its undo only when it was saved, so
            // "방금 한 거 되돌려" takes it back (QA BUG-18).
            reply = ArisLocalReply.todoAdded(await addTodo(item), korean: korean)
            guard !Task.isCancelled else { return }
            await sayLocal(reply, heard: unmarked)
        } else if let found = finishing {
            understood(text, path: "local", tier: tier)
            reply = await finishTodo(found, heard: unmarked, korean: korean)
        } else if case .brief = intent {
            understood(text, path: "local", tier: tier)
            guard await showBrief(inTurn: true) != nil else { return }
            // Canvas titles are other people's words: they stay out of the history the AI reads later.
            reply = ArisBrief.remembered(english: ArisUILanguage.english)
        } else if case .dayEnd = intent {
            // "오늘 정리해 줘": the day-end card, made here from the day's own records (ArisController+DayEnd).
            understood(text, path: "local", tier: tier)
            guard let told = await showDayEnd(heard: unmarked, korean: korean) else { return }
            reply = told
        } else if case .undo = intent {
            understood(text, path: "local", tier: tier)
            // Its one card names exactly what is undone (the newest of the kind the user named), on every path.
            reply = await undoLast(korean: korean, heard: unmarked)
        } else if case .readAgain = intent {
            understood(text, path: "local", tier: tier)
            reply = await readLastAnswer(heard: unmarked, korean: korean)
        } else if case .saveAnswer(let save) = intent {
            understood(text, path: "local", tier: tier)
            reply = await saveLastAnswer(save, heard: unmarked, korean: korean)
        } else if case .arrange(let app, let count) = intent {
            understood(text, path: "local", tier: tier)
            reply = await arrange(app, count: count, korean: korean)
        } else if case .media(let media) = intent {
            // What Aris says comes from the player's answer: never "틀게요" when it didn't (QA BUG-37's follow-up).
            understood(text, path: "local", tier: tier)
            let done = await performMedia(media)
            guard !Task.isCancelled else { return }
            if done { resumeMusic = false }
            reply = media.reply(done: done, korean: korean)
            await sayLocal(reply, heard: unmarked)
        } else if case .whatsPlaying = intent {
            // "지금 무슨 노래야?": from what is playing, here (never the AI).
            understood(text, path: "local", tier: tier)
            let now = await ArisNowPlaying.shared.currentPlayback()
            guard !Task.isCancelled else { return }
            reply = ArisIntent.nowPlayingLine(title: now?.title ?? "", artist: now?.artist ?? "", playing: now?.isPlaying ?? false, korean: korean)
            await sayLocal(reply, heard: unmarked)
        } else if let control = ArisControl(intent) {
            // Volume and brightness: said and logged from whether anything really moved (audit platform-1).
            understood(text, path: "local", tier: tier)
            reply = await performControl(control, korean: korean)
            guard !Task.isCancelled else { return }
            await sayLocal(reply, heard: unmarked)
        } else if let said = await doOnMac(intent, korean: korean) {
            // The time, the date, the timer, opening an app: done here, and said from what happened (audit turn-1).
            understood(text, path: "local", tier: tier)
            guard !Task.isCancelled else { return }
            reply = said
            await sayLocal(reply, heard: unmarked)
        } else if !shots, ArisHandoff.isHandoff(unmarked) || browserWork {
            // "해 놔", "끝나면 알려줘", or several steps on websites (for Aside): the work goes to the background and
            // the conversation is free again.
            understood(text, path: browserWork ? "task:browser" : "task", tier: tier)
            stats?.firstSound(at: .now)
            let handed = handOut([], turn: ArisHandOutPlan.Turn(words: text, brain: brain, turnId: nil, screenConversation: screenConversation,
                                                                outsideConversation: outsideConversation, handsFree: turnHandsFree),
                                 tier: tier, korean: korean, browser: browserWork)
            reply = handed.line
            session = session.answering(reply)
            recordTurn(heard: unmarked, reply: reply, job: handed.job)
            await speak { await self.speaker.speak(reply) }
        } else if !shots, ArisDeixis.refersToScreen(text) || ArisDeixis.refersToClipboard(unmarked) {
            log.notice("asking about the screen (\(tier.rawValue, privacy: .public))")
            understood(text, path: "screen", tier: tier)
            guard let answer = await answerAboutScreen(text, tier: tier, brain: brain) else { return }
            reply = answer
        } else {
            // "sent", not "asking": aris-agent may still answer this one itself (it then says so: "aris-agent answers this itself").
            log.notice("sent to aris-agent for \(brain.rawValue, privacy: .public) (\(tier.rawValue, privacy: .public))")
            understood(text, path: "brain:\(brain.rawValue)", tier: tier)
            // With markers in the words, the agent matches policy against the unmarked ones.
            guard let answer = await askAndSpeak(text, tier: tier, brain: brain, request: shots ? whole : nil) else { return }
            reply = answer
        }
        guard !Task.isCancelled else { return }
        // Paths that speak before they know their reply (the brief, arranging windows) are recorded here.
        recordTurn(heard: unmarked, reply: reply)
        // The conversation's quiet is counted from when the voice finished, as before.
        lastTurnAt = .now
        finishTurn("ok")
        // The answer stays up and the conversation stays open; the next ⌥Space or "아리스" carries it on.
        try? await Task.sleep(for: Self.lingerAfterAnswer)
        guard !Task.isCancelled else { return }
        session = session.done()
        resumeMusicIfPaused()
    }

    /// Asks the AI and speaks its answer while it's still being written: the notch shows what the AI is doing,
    /// then the answer as it grows, and each finished sentence goes to the voice at once. Nil when it failed
    /// (the failure is already showing) or the turn was cancelled.
    func askAndSpeak(_ text: String, tier: ArisTier, brain: ArisBrain, screen: String? = nil, request: String? = nil) async -> String? {
        var (sentences, voice) = AsyncStream.makeStream(of: String.self)
        defer {
            voice.finish()
            dropPendingAnswer()
        }
        var speaking: Task<Void, Never>?
        // Sentences go to the voice as they stream, up to a fence or JSON; the rest waits for the whole answer, and code
        // or data is never read (ArisSpeechStream).
        var speech = ArisSpeechStream()
        let askedAt = ContinuousClock.now
        var saidHold = false
        skillInUse = nil
        // The agent's id for this turn when its answer dispatches a Claude Code job (it vouches for that job).
        var turnId: String?
        // The agent counts this turn as outside content (the screen, or others' words): its answer dispatches only when
        // the agent says it may (a screen turn: every job untrusted, a Claude Code launch always asks the user).
        var untrustedTurn = false
        var dispatchAllowed = false
        // Something readable was said this turn (code and JSON never are: ArisSpeakable).
        var saidAnything = false
        // The agent took this turn's jobs block out (its refusedJobs line).
        var refusedJobs = false
        /// aris-agent said it answers this turn itself (ArisAgentReply.helperAnswers).
        var helperAnswers = false
        // A hands-free turn read the user's messages, mail or notes: shown, never spoken (its shownOnly line).
        var shownOnly = false
        // A card of this turn nobody answered, or one the user said no to: the reply is told in their terms (QA BUG-39, BUG-43).
        var cardUnansweredThisTurn = false, cardDeclinedThisTurn = false, cardApprovedThisTurn = false
        // The steps a no dropped in this turn, by their tool: a status for one of them is ignored until a later yes.
        var declinedTools: Set<String> = []
        turnReachedAI = true
        func say(_ lines: [String]) {
            let found = lines.map(ArisSpeakable.speakable).filter { !$0.isEmpty }
            guard !found.isEmpty else { return }
            saidAnything = true
            if speaking == nil {
                let aloud = !silentSpeech && ArisQuietGate.maySpeak(heard: session.heard)
                log.notice("\(ArisQuiet.voiceLog(aloud: aloud), privacy: .public)")
                stats?.firstSound(at: .now)
                // The preview harness reads the answer off the screen; the voice would play out loud.
                speaking = silentSpeech || !ArisQuietGate.maySpeak(heard: session.heard)
                    ? Task { for await _ in sentences {} }
                    : Task { await self.speaker.speak(sentences: sentences) }
                armBargeIn()
            }
            found.forEach { voice.yield($0) }
        }
        readTeammatesIfMissing()
        // The screenshot wait and the context build run together.
        async let taking = turnImages()
        async let gathering = currentContext()
        let (images, focus) = await taking
        let context = await gathering
        // A turn stopped during that wait never asked: the next one still starts the new conversation (audit turn-2).
        guard !Task.isCancelled else { return nil }
        let fresh = freshConversation
        freshConversation = false
        // A new conversation whose first turn never got an answer from the helper (it wasn't running, the stream failed)
        // is still new on the next turn: the helper then starts afresh too, the turns it kept for the automatic check
        // included (auto L7).
        var reachedHelper = false
        defer { if fresh, !reachedHelper { freshConversation = true } }
        if !images.isEmpty {
            // Defence in depth: the agent says so too, but an image turn is outside content from here on.
            untrustedTurn = true
            screenConversation = true
        }
        // An untrusted turn's <say> line is plain text: everything said is also shown (ArisSpeakable.SayHandling.keep).
        speech.honoursSay = !untrustedTurn && screen == nil
        let outgoing = ArisOutgoingImages(images)
        // The "working on this window" overlay never outlives the turn (an answer, a failure, a stop).
        defer { ArisOperatingOverlay.shared.end() }
        let asked = ArisAgentClient.ask(text, context: context, tier: tier, brain: brain, screen: screen, fresh: fresh,
                                        request: request, screenConversation: screenConversation, outsideConversation: outsideConversation,
                                        handsFree: turnHandsFree, images: outgoing, focus: focus)
        // Nothing at all back within a minute: a short failure line, never a turn that hangs (BUG-25c reopened).
        let failure = ArisAgentReply.failure(ArisTurnWatchdog.line(korean: ArisSpeech.language(of: text) == "ko-KR"))
        for await reply in ArisTurnWatchdog.guarded(asked, within: ArisTurnWatchdog.firstWord, failure: failure) {
            if case .failure = reply {} else { reachedHelper = true }
            guard !Task.isCancelled else {
                speaker.stop()
                return nil
            }
            switch reply {
            case .status(let status):
                // A late line about a step he just said no to is no step (ArisSession.ignoresStatus).
                guard !ArisSession.ignoresStatus(ArisUIWords.status(status), declined: declinedTools) else { break }
                session = session.working(ArisUIWords.status(status))
                // The AI went off to do something and nothing's been said yet: a word, so the silence isn't a mystery.
                if speaking == nil, !saidHold, ContinuousClock.now - askedAt > Self.holdAfter {
                    saidHold = true
                    say([ArisSpeech.language(of: text) == "ko-KR" ? "확인해 볼게요." : "One moment."])
                }
            case .file, .launched, .work:
                break
            case .stepFailed(let label):
                session = session.stepFailed(label.map { ArisUIWords.status($0) })
            case .operating(let target):
                // Computer use is working in that window: the overlay on it, and its line in the notch.
                ArisOperatingOverlay.shared.show(target)
                session = session.working(target.line)
            case .refusedJobs:
                refusedJobs = true
            case .shownOnly:
                shownOnly = true
            case .skill(let title):
                skillInUse = title
            case .helperAnswers:
                // aris-agent answers this one itself: no AI is asked, and the record says so (not "brain:api").
                helperAnswers = true
                stats?.answered(by: ArisTurnPath.helper)
                log.notice("aris-agent answers this itself (no AI asked)")
            case .savedSteps:
                // The request's saved steps were done again with no AI: the record says "saved-steps" (not "brain:api").
                helperAnswers = true
                stats?.answered(by: ArisTurnPath.savedSteps)
                log.notice("the saved steps answer this (no AI asked)")
            case .turn(let id):
                turnId = id
            case .untrusted(let sawScreen, let dispatch, let outside):
                untrustedTurn = true
                speech.honoursSay = false
                dispatchAllowed = dispatch
                if sawScreen { screenConversation = true }
                if outside { outsideConversation = true }
            case .confirm(let ask):
                // Finish what Aris was saying, ask, and carry on with a fresh voice for the rest of the answer.
                dropPendingAnswer()
                say(speech.finish(shown: ArisSpeakable.shown(speech.display, korean: ArisSpeech.language(of: text) == "ko-KR")))
                voice.finish()
                if let speaking { await speak { await speaking.value } }
                speaking = nil
                speech = ArisSpeechStream()
                speech.honoursSay = !untrustedTurn && screen == nil
                (sentences, voice) = AsyncStream.makeStream(of: String.self)
                let waiting = session.runningTools
                let allow = await askUser(ask, handsFree: turnHandsFree, waiter: true)
                guard !Task.isCancelled else { return nil }
                declinedTools = allow ? [] : declinedTools.union(waiting)
                // 그래도 하기 on the automatic check's stopped card approves nothing: the action's own card comes next.
                if !allow { if cardUnanswered { cardUnansweredThisTurn = true } else { cardDeclinedThisTurn = true } } else if !ask.stopped { cardApprovedThisTurn = true }
                // 하지 않기 there settles the card into its one line (ArisStoppedCard).
                if ask.stopped, !allow, !cardUnanswered {
                    session = session.stoppedSettled(english: ArisCardEnglish.isEnglish(request: session.heard) || ArisConfirmReply.isEnglish(ask))
                }
                stats?.asked(allowed: allow)
                // A yes on a desktop card: activation goes back to the process the card names before the agent acts
                // (the click on the card made Aris the active app).
                ArisActivationHandoff.yield(after: allow, on: ask)
                let delivered = await ArisAgentClient.confirm(ask.id, allow: allow, shown: ask, unanswered: !allow && cardUnanswered)
                log.notice("you said \(allow ? "yes" : "no", privacy: .public) to \(ask.title, privacy: .private)\(delivered == .ok ? "" : delivered == .refused ? " (refused)" : " (too late)", privacy: .public)")
                // On the size clock: the card's room goes as one eased resize of the surface, not a one-frame snap
                // (the notch's outline follows only animated layout changes).
                withAnimation(ArisGlass.resize) { session = session.answered(delivered: delivered == .ok, allowed: allow) }
                // The agent couldn't tell this was the app: the user's answer didn't arrive, and they hears so.
                if delivered == .refused { say([ArisConfirmResult.refusedNotice(english: ArisUIWords.english)]) }
            case .delta(let piece):
                // After a card nobody answered or the user said no to, the reply waits for the whole answer: it may be
                // rewritten in his terms (ArisCardWait.replyAfterCards), so none of it is said or shown before.
                guard !cardUnansweredThisTurn, !cardDeclinedThisTurn else { break }
                say(speech.add(piece))
                // A block never shows while it streams: the notch shows the text up to the hold point, without a source
                // link or label at its end.
                showAnswer(ArisSpeakable.streaming(speech.display))
            case .answer(let written):
                // A card the owner approved this turn: what happened to it (done, or why not) is in the brain's answer, which an
                // unanswered later card never replaces (QA retest: an approved batch that failed was told as "답이 없어서").
                let answer = ArisCardWait.replyAfterCards(written, unanswered: cardUnansweredThisTurn && !cardApprovedThisTurn, declined: cardDeclinedThisTurn && !cardApprovedThisTurn,
                                                          korean: ArisSpeech.language(of: text) == "ko-KR")
                log.notice("\(ArisTurnPath.answerer(brain: brain.rawValue, helper: helperAnswers), privacy: .public) answered (\(answer.count, privacy: .public) characters, \(speech.written.isEmpty ? "whole" : "streamed", privacy: .public))")
                let mayDispatch = ArisDispatch.mayDispatch(screenText: screen != nil, untrustedTurn: untrustedTurn, dispatchAllowed: dispatchAllowed)
                // The agent took the jobs out (outside text came into the conversation): the user's own words go as one job,
                // untrusted (ArisHandOutPlan).
                let refused = screen == nil && refusedJobs
                let specs = mayDispatch && !refusedJobs ? ArisDispatch.parse(answer, teammateIds: Self.teammateIds) : nil
                if specs != nil || refused {
                    // Only this turn dispatches; the jobs' own answers are never parsed (no recursive fan-out). An untrusted
                    // turn's jobs carry no turn id, so a Claude Code launch from it always asks the user.
                    say(speech.finish(shown: ""))
                    let handing = ArisHandOutPlan.Turn(words: request ?? text, brain: brain,
                                                       turnId: ArisDispatch.turnId(turnId, untrustedTurn: untrustedTurn),
                                                       untrustedTurn: untrustedTurn, screenConversation: screenConversation,
                                                       outsideConversation: outsideConversation || refused, handsFree: turnHandsFree)
                    let handed = handOut(specs ?? [], turn: handing, tier: tier, korean: ArisSpeech.language(of: text) == "ko-KR")
                    say([handed.line])
                    voice.finish()
                    showFinalAnswer(handed.line)
                    recordTurn(heard: request ?? text, reply: handed.line, job: handed.job)
                    if let speaking { await speak { await speaking.value } }
                    return handed.line
                }
                // A machine block (a jobs fence that wasn't dispatched, any JSON) is never shown, read aloud or stored:
                // a jobs block becomes one short line. Code the user asked for stays on screen but is never read.
                let korean = ArisSpeech.language(of: text) == "ko-KR"
                if shownOnly {
                    // Heard hands-free and it read the user's private data: on the screen only, and "읽어줘" has nothing to read.
                    let shown = ArisSpeakable.shown(answer, korean: korean, say: .keep)
                    lastAnswer = nil
                    say([ArisSpeakable.onScreen(korean: korean)])
                    voice.finish()
                    showFinalAnswer(shown)
                    recordTurn(heard: request ?? text, reply: shown)
                    if let speaking { await speak { await speaking.value } }
                    return shown
                }
                // An answer sent whole (nothing streamed) goes through the voice's stream first, so the voice and the
                // notch agree on its <say> line: honoured only as the voice took it, kept as written on an untrusted turn.
                if speech.written.isEmpty { say(speech.add(answer)) }
                let handling: ArisSpeakable.SayHandling = untrustedTurn || screen != nil ? .keep : speech.tookSayLine ? .honour : .unwrap
                // Nothing to show and no card (an empty answer, or only data): the reason is shown and said instead.
                let card = ArisWidget.presentation(in: answer, untrusted: untrustedTurn || screen != nil) != nil
                let shown = ArisSpeakable.visible(answer, shown: ArisSpeakable.shown(answer, korean: korean, say: handling), card: card, korean: korean)
                if shown == ArisSpeakable.emptyAnswer(korean: korean) { log.error("\(brain.rawValue, privacy: .public)'s answer left nothing to show") }
                lastAnswer = (shown, .now)
                // What streamed was said; the rest of what may be read is said now (a long answer: its <say> line or its
                // start, then "자세한 건 화면에"), its code and data taken out first.
                say(speech.finish(shown: shown, korean: korean))
                // All of it was code or data: one line says where it is.
                if !saidAnything { say([ArisSpeakable.onScreen(korean: korean)]) }
                voice.finish()
                showFinalAnswer(shown)
                // The card it asks for (pick B): named by the answer, read on the Mac, never acting on an untrusted turn.
                ArisWidgetModel.shared.present(answer: answer, reply: shown, untrusted: untrustedTurn || screen != nil, asked: request ?? text)
                // In the history before the voice reads it, so 닫기 mid-speech keeps it (a gesture turn's words unmarked).
                recordTurn(heard: request ?? text, reply: shown)
                if let speaking { await speak { await speaking.value } }
                return shown
            case .failure(let message):
                dropPendingAnswer()
                log.error("\(brain.rawValue, privacy: .public) failed: \(message, privacy: .public)")
                speaker.stop()
                fail(message)
                return nil
            }
        }
        return nil
    }

    /// "읽어줘": the last answer read whole (code and data still left out), as interruptible as any answer.
    private func readLastAnswer(heard: String, korean: Bool) async -> String {
        if let muted = await mutedReading(heard: heard, korean: korean) { return muted }
        let fresh = lastAnswer.flatMap { ArisSpeakable.stillReadable(since: $0.at) ? $0.text : nil }
        // Read as the notch showed it: a <say> line still in it (an untrusted turn's) is read as words, not honoured.
        let sentences = fresh.map { ArisSpeakable.fullReading($0, korean: korean, say: .keep) } ?? []
        guard let last = fresh, !sentences.isEmpty else {
            let none = korean ? "다시 읽어 드릴 답이 없어요." : "There's no answer to read."
            session = session.answering(none)
            stats?.firstSound(at: .now)
            recordTurn(heard: heard, reply: none)
            await speak { await self.speaker.speak(none) }
            return none
        }
        session = session.answering(last)
        stats?.firstSound(at: .now)
        let reply = korean ? "방금 답을 처음부터 다 읽어 줬어요." : "Read the last answer out in full."
        recordTurn(heard: heard, reply: reply)
        let (lines, voice) = AsyncStream.makeStream(of: String.self)
        sentences.forEach { voice.yield($0) }
        voice.finish()
        armBargeIn()
        await speak(timeout: ArisSpeakable.readingLimit(sentences)) { await self.speaker.speak(sentences: lines) }
        return reply
    }

    /// The answer so far, while it's being written (the streaming path above, and the preview harness's answer-stream).
    /// At most one update per 30th of a second reaches the notch, the newest text each time, so SwiftUI isn't
    /// invalidated for every token.
    func showAnswer(_ text: String) {
        let wait = answerPacer.offer(text, at: ProcessInfo.processInfo.systemUptime)
        guard answerFlush == nil else { return }
        guard wait > 0 else { return flushAnswer() }
        let flush = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.flushAnswer() } }
        answerFlush = flush
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: flush)
    }

    /// The whole answer, once the stream is over: whatever was still waiting is dropped.
    func showFinalAnswer(_ text: String) {
        dropPendingAnswer()
        session = session.answering(text)
    }

    private func flushAnswer() {
        answerFlush = nil
        // Nil when nothing waits or the turn it was written for was dropped since (cancelled, replaced, finished).
        guard let text = answerPacer.take(at: ProcessInfo.processInfo.systemUptime) else { return }
        guard session.question == nil, session.phase == .thinking || session.phase == .speaking else { return }
        session = session.answering(text)
    }

    /// Forgets the streamed text still waiting; called whenever a turn is cancelled, replaced or finished.
    func dropPendingAnswer() {
        answerFlush?.cancel()
        answerFlush = nil
        answerPacer.drop()
    }

    /// Waits for Aris to finish talking, but never longer than `speakTimeout`.
    /// The preview harness feeds transcripts through `answer` without audio.
    var silentSpeech = false
    /// The last brain answer as the notch showed it and when, for "읽어줘" (only its short part was said). Forgotten
    /// when the conversation starts over, and too old to read after 10 minutes (ArisSpeakable.stillReadable).
    var lastAnswer: (text: String, at: Date)?

    func speak(timeout: Duration = speakTimeout, _ talking: @escaping @MainActor () async -> Void) async {
        guard !silentSpeech else { return }
        guard ArisQuietGate.maySpeak(heard: session.heard) else { return }
        do {
            try await Self.within(timeout) { await talking() }
            log.notice("spoke")
        } catch is CancellationError {
            // The turn was stopped: whoever stopped it has the voice now.
        } catch {
            log.error("speaking took too long")
            speaker.stop()
        }
    }

    /// The rules found nothing to do here (or named an app the Mac doesn't have).
    func needsSecondGuess(_ intent: ArisIntent) -> Bool {
        switch intent {
        case .ask: return true
        case .openApp(let name), .arrange(let name, _): return Self.application(named: name) == nil
        default: return false
        }
    }

    /// Jev's guess at an everyday request; nil (ask Claude) when it's unsure, slow, or not set up.
    /// What the moment looks like, for the AI (the calendar covers the coming week).
    /// `conversation`: with the recent turns and the jobs (false: only the moment, for a job that must not hear them).
    func currentContext(conversation: Bool = true) async -> String {
        let music = ArisNowPlaying.shared
        let now = Date()
        // Never asked from here (QA BUG-55: a weather question popped the Calendar prompt): read only when already allowed.
        let upcoming = await ArisCalendarStore.shared.upcomingEvents(days: ArisContext.calendarDays)
        log.notice("calendar: \(upcoming.count, privacy: .public) events this week (access \(EKEventStore.authorizationStatus(for: .event).rawValue, privacy: .public))")
        return ArisContext.make(
            now: now, timeZone: .current,
            frontApp: NSWorkspace.shared.frontmostApplication?.localizedName,
            music: music.isPlayerIdle ? nil : ArisContext.Music(title: music.songTitle, artist: music.artistName, playing: music.isPlaying),
            events: upcoming.map { ArisContext.Event(start: $0.start, end: $0.end, title: $0.title, allDay: $0.isAllDay, outside: ArisOutsideItems.shared.contains($0.id),
                                                        todo: $0.kind.isReminder) },
            recent: conversation ? history : [], tasks: conversation ? contextTasks() : [],
            shelfFiles: ShelfStateViewModel.shared.items.filter { $0.fileURL != nil }.count, userName: ArisUserName.current)
    }

    /// The background tasks' context lines. A finished or failed one carries an untrusted job's words: from then on the
    /// conversation is outside text (outsideConversation, which the agent also sees from the line itself). Those put
    /// away when an earlier conversation ended are left out (ArisJobContext).
    private func contextTasks() -> [String] {
        let context = ArisJobContext.lines(tasks, putAway: putAwayJobs)
        if context.outside { outsideConversation = true }
        return context.lines
    }

    /// Jev's guess at an everyday request (nil intent: ask the AI), and how much work it is.
    func route(_ text: String) async -> (intent: ArisIntent?, tier: ArisTier, browserWork: Bool) {
        guard let key = ArisKeyFile.load(ArisRouter.keyName) else { return (nil, .quick, false) }
        let apps = await Self.installedApps.value
        let start = ContinuousClock.now
        do {
            let answers = try await Self.within(ArisRouter.timeout) { try await ArisRouter.ask(text, apps: apps, key: key) }
            let milliseconds = Int((ContinuousClock.now - start) / .milliseconds(1))
            let decided = ArisRouter.decide(answers, text: text)
            log.notice("router: \(answers.intent.rawValue, privacy: .public) \(answers.intentConfidence, privacy: .public) -> \(decided == nil ? "Claude" : "Mac", privacy: .public) in \(milliseconds, privacy: .public) ms")
            ArisRouter.record(text, answers, acted: decided != nil, milliseconds: milliseconds)
            return (decided, answers.tier, answers.browserWork)
        } catch {
            log.error("router skipped: \(String(describing: error), privacy: .public)")
            return (nil, .quick, false)
        }
    }

    /// Read once: what Jev may pick from when you ask to open an app.
    /// The names of the apps on this Mac, for the router: listed once, off the main actor (the folders' listings
    /// were read on the main thread at the first turn's start).
    nonisolated static let installedApps: Task<[String], Never> = Task.detached(priority: .userInitiated) {
        ArisRouter.installedApps(in: ArisRouter.appFolders)
    }

    /// A voice media command, done and answered: whether the player did it (next and previous then play).
    func performMedia(_ media: ArisIntent.Media) async -> Bool {
        let music = ArisNowPlaying.shared
        switch media {
        case .play: return await music.perform(.play)
        case .pause: return await music.perform(.pause)
        case .next:
            guard await music.perform(.next) else { return false }
            music.play()
            return true
        case .previous:
            guard await music.perform(.previous) else { return false }
            music.play()
            return true
        }
    }

    /// Nothing in the turn was speech: "못 들었어요" for a moment, never said aloud, routed or acted on (QA BUG-30).
    func notHeard() {
        log.notice("nothing heard")
        gestureCancelled()
        finishTurn("unheard")
        releaseListener()
        session = session.failing(ArisTranscript.notHeard(korean: !ArisUILanguage.english))
        level = 0
        turn = Task {
            try? await Task.sleep(for: Self.lingerAfterFailure)
            guard !Task.isCancelled else { return }
            // Nothing is parked: the next time the notch opens it doesn't say "못 들었어요" again.
            session = ArisSession()
            resumeMusicIfPaused()
        }
    }

    /// The helper answers again and the lost question is not asked again by Aris itself (ArisHelperWatch): the line
    /// that said it isn't running says what is true now. Only that line, and only while it still stands.
    func helperCameBack() {
        guard ArisHelperWatch.isLostLine(session.reply) else { return }
        session = session.corrected(ArisFixWords.helperBackLine(english: ArisUIWords.english))
    }

    func fail(_ message: String) {
        gestureCancelled()
        finishTurn("error")
        turn?.cancel()
        releaseListener()
        session = session.failing(message)
        level = 0
        turn = Task {
            try? await Task.sleep(for: Self.lingerAfterFailure)
            guard !Task.isCancelled else { return }
            session = session.done()
            resumeMusicIfPaused()
        }
    }

    // MARK: - Helpers

    /// Lets go of the turn's microphone and its Scribe stream, so a failure leaves Aris idle-clean: a listener left
    /// behind keeps the wake word, the conversation watches and every announcement waiting on `listener == nil`.
    func releaseListener() {
        handsFree = false
        pauseWatch?.cancel()
        starting?.cancel()
        stopScribe()
        if let listener = listener as? ArisListener {
            Task { _ = await listener.stop() }
        }
        listener = nil
    }

    func pauseMusic() {
        guard ArisNowPlaying.shared.isPlaying else { return }
        ArisNowPlaying.shared.pause()
        resumeMusic = true
    }

    func resumeMusicIfPaused() {
        // A conversation keeps the music paused until it ends.
        guard resumeMusic, !conversation.isOpen else { return }
        resumeMusic = false
        ArisNowPlaying.shared.play()
    }

    static func application(named name: String) -> URL? {
        ArisRouter.appFolders
            .map { URL(fileURLWithPath: $0).appendingPathComponent(name + ".app") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    enum PermissionProblem: String { case undecided, denied }

    static func permissionProblem() -> PermissionProblem? {
        let microphone = AVCaptureDevice.authorizationStatus(for: .audio)
        let speech = SFSpeechRecognizer.authorizationStatus()
        if microphone == .denied || microphone == .restricted || speech == .denied || speech == .restricted { return .denied }
        if microphone == .notDetermined || speech == .notDetermined { return .undecided }
        return nil
    }

    typealias TimedOut = ArisDeadline.TimedOut

    /// Runs `work`, giving up after `limit` so a stuck system call can't freeze Aris; stopping the caller stops the
    /// work too (ArisDeadline). `cancelsWork`: false for work that must run to its end anyway (a stop, which gives the
    /// device back).
    static func within<T>(_ limit: Duration, cancelsWork: Bool = true, _ work: @escaping @MainActor () async throws -> T) async throws -> T {
        try await ArisDeadline.within(limit, cancelsWork: cancelsWork, work)
    }

}
