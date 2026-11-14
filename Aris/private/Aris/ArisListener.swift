//
//  ArisListener.swift
//  Aris
//
//  The microphone, transcribed on the Mac by Apple's speech engine (ArisRecognizer: SpeechAnalyzer on macOS 26,
//  SFSpeechRecognizer on macOS 14 and 15; ArisListenEngine picks). The listener owns the audio (the microphone, the
//  wake detector's, or a test file: ArisListenFeed) and hands it to the recognizer in the format it asks for.
//  Reports the text heard so far and how loud the voice is (for the orb), and
//  keeps a 16 kHz recording of the turn for Whisper's second listen.
//  While waiting for the wake word it keeps only the current phrase and the last
//  few seconds of audio; beginTurn() carries on into a turn without a restart, so
//  nothing said right after "아리스" is lost. The recording holds five minutes
//  (ArisLongTurn); Whisper reads a long one window by window.
//

import AVFoundation

@MainActor
final class ArisListener {
    /// Everything heard so far: finished phrases plus the recognizer's current guess.
    var onText: ((String) -> Void)?
    /// Voice loudness, 0...1. Can be set while listening (a wake-word listener becomes a turn's).
    var onLevel: ((Float) -> Void)? {
        didSet { levels.handler = onLevel }
    }
    private let levels = LevelRelay()
    /// Every 16 kHz chunk as it's recorded, on the audio thread (for Scribe).
    var onSamples: (([Float]) -> Void)? {
        get { samples.handler }
        set { samples.handler = newValue }
    }
    private let samples = SampleRelay()
    /// The same 16 kHz chunks for the gesture's voiced-time count (ArisSpeechActivity), on the audio thread. Its own
    /// relay, so it never displaces Scribe's `onSamples`.
    var onSpeechChunk: (([Float]) -> Void)? {
        get { speechChunks.handler }
        set { speechChunks.handler = newValue }
    }
    private let speechChunks = SampleRelay()
    /// The microphone changed or stopped (a device was plugged in, the Mac slept).
    var onInterrupted: (() -> Void)?
    /// The speech engine stopped hearing for good this listen, with the line that says why (ArisRecognizer.onProblem).
    var onProblem: ((String) -> Void)?
    /// Who this listener's own microphone is opened for (the log names it): a turn's talk key, or dictation.
    var use = ArisMicUse.talk
    /// Listening for the wake word, not yet in a turn.
    var waiting: Bool { heard.waiting }

    private let engine = AVAudioEngine()
    /// The speech engine hearing this listen (ArisListenEngine), and where its audio goes.
    private var recognizer: ArisRecognizer?
    private var input: ArisRecognizerInput?
    /// A test file heard instead of the microphone (ArisListenFeed).
    private var feed: ArisListenFeed?
    /// Finished phrases and the recognizer's current guess (ArisHeardText).
    private var heard = ArisHeardText()
    private let recording = Recording()
    private var configuration: NSObjectProtocol?
    private var source: ArisWakeDetector?

    /// The whole turn so far, 16 kHz mono, for Whisper.
    var recordedSamples: [Float] { recording.samples }

    /// The recording for the second listen once the turn is over: all of it, or nothing when the turn outran what
    /// the recording holds. Then only the live transcript and Scribe heard the whole turn, and Whisper's text of its
    /// start must not win over them (audit voice-5).
    var secondListenSamples: [Float] {
        ArisLongTurn.isWhole(recorded: recording.count, sampleRate: ArisWhisper.sampleRate) ? recording.samples : []
    }

    /// The last `count` samples recorded (Smart Turn reads the turn's last 8 s, not minutes of it).
    func recentSamples(_ count: Int) -> [Float] { recording.last(count) }

    /// Seconds of audio recorded so far (while waiting, at most the last few).
    var recordedSeconds: Double { Double(recording.count) / ArisWhisper.sampleRate }

    /// Whether beginTurn() came before start() (a sure voice match wakes Aris before the recogniser runs).
    private var handOver = ArisWakeHandOver()

    /// `source`: hear the wake detector's audio (the phrase it caught, then live) instead of opening the
    /// microphone a second time, so the hand-over loses nothing. `from`: the detector's sample to start at (a
    /// conversation's turn: from just before the voice watch was sure).
    func start(locale: Locale, waitingForWakeWord: Bool = false, source: ArisWakeDetector? = nil, from: Int? = nil) async throws {
        // A listener already woken into its turn stays a turn's: its phrases are kept and its recording whole
        // (audit voice-2).
        heard = ArisHeardText(waiting: handOver.startsWaiting(asked: waitingForWakeWord))
        recording.reset(rolling: waiting)
        let recognizer = Self.makeRecognizer(ArisListenEngine.current())
        recognizer.onHeard = { [weak self] kept, guess in self?.take(kept: kept, guess: guess) }
        recognizer.onProblem = { [weak self] line in self?.onProblem?(line) }
        self.recognizer = recognizer
        // A test file in place of the microphone, when the hidden setting names one (a VM has no microphone).
        let feed = source == nil ? Self.testFeed() : nil
        // The language's model isn't installed yet (a first run): it downloads in the background, and this turn says so
        // instead of timing out while it waits. With no microphone on this Mac at all, that is what is said, first:
        // "say it again in a moment" would change nothing (ArisListenStart).
        let modelMissing = try await recognizer.modelMissing(locale: locale)
        switch ArisListenStart.problem(usesMicrophone: source == nil && feed == nil, hasMicrophone: ArisMicChoice.hasMicrophone(), modelMissing: modelMissing) {
        case .noMicrophone: throw ArisFailure(message: ArisListenerWords.noMicrophone())
        case .modelPreparing: throw ArisFailure(message: ArisListenerWords.modelPreparing())
        case nil: break
        }
        let vocabulary = ArisHearingLocale.hints(vocabulary: ArisVocabulary.load(), locale: locale.identifier,
                                                 waitingForWakeWord: waitingForWakeWord)
        let input = try await recognizer.start(locale: locale, hints: vocabulary)
        self.input = input
        // The older engine without the language's on-device model: Apple's servers hear it, said once.
        if let older = recognizer as? ArisRotatingRecognizer, older.place == .server { ArisLegacyServerNotice.sayOnce(locale: locale) }
        if let source {
            self.source = source
            try listen(to: source, feeding: input, from: from)
        } else if let feed {
            try listen(to: feed, feeding: input)
        } else {
            try await startMicrophone(feeding: input)
        }
    }

    /// The engine's recognizer: SpeechAnalyzer's where ArisListenEngine says so and the macOS has it, else the older one.
    static func makeRecognizer(_ engine: ArisListenEngine) -> ArisRecognizer {
        if engine == .analyzer, #available(macOS 26.0, *) { return ArisAnalyzerRecognizer() }
        return ArisRotatingRecognizer(maker: ArisSFSpeechTasks())
    }

    /// The test file the hidden setting names, read; nil (the microphone) when there is none or it can't be read.
    private static func testFeed() -> ArisListenFeed? {
        guard let url = ArisListenFeed.configured() else { return nil }
        do { return try ArisListenFeed(url: url) } catch {
            NSLog("Aris: the test audio file \(url.lastPathComponent) can't be read (\(error.localizedDescription)); the microphone listens")
            return nil
        }
    }

    /// Whether macOS's speech model for `locale` is on this Mac. Opens nothing: the wake word asks before its microphone.
    /// The older engine has no model to install: it can hear `locale` when it has a recogniser for it that is ready.
    static func speechModelInstalled(locale: Locale) async -> Bool {
        if ArisListenEngine.current() == .analyzer, #available(macOS 26.0, *) {
            return await ArisAnalyzerRecognizer.speechModelInstalled(locale: locale)
        }
        return ArisSFSpeechTasks.recognizer(locale)?.isAvailable ?? false
    }

    /// At launch: the language's speech model is installed ahead of the first turn, so that turn doesn't wait for it.
    /// A turn that finds it missing joins the same install. Nothing to install for the older engine.
    static func prepareSpeechAssets(locale: Locale) async {
        guard ArisListenEngine.current() == .analyzer, #available(macOS 26.0, *) else { return }
        await ArisAnalyzerRecognizer.prepareSpeechAssets(locale: locale)
    }

    /// stop() was called while start() was still opening the microphone: the engine is closed as soon as it opened.
    private var stopped = false
    /// The engine has a tap and was started: only then is there anything to close.
    private var microphoneOpened = false
    /// The input device the turn opened (ArisMicChoice.device(of:)), to tell a device change (the turn ends) from a
    /// format, rate or output change on the same device (the tap is reinstalled and the engine started again).
    private var openedDevice: AudioDeviceID?
    private var restarts = 0
    /// What the microphone was opened with, kept for a restart.
    private var parts: MicrophoneParts?

    /// The wake word was heard: from here on this is a turn (the phrase with the name in it is kept).
    func beginTurn() {
        handOver.beginTurn()
        heard.waiting = false
        recording.stopRolling()
    }

    /// Stops listening and returns the whole utterance.
    func stop() async -> String {
        stopped = true
        source?.forward(to: nil)
        source = nil
        feed?.stop()
        feed = nil
        if let configuration { NotificationCenter.default.removeObserver(configuration) }
        configuration = nil
        // An engine that was never opened has no tap and no device to give back. Stopping waits on the device the
        // way starting does (a Bluetooth switch can take seconds): off the main thread, so the notch never freezes.
        if microphoneOpened {
            microphoneOpened = false
            await Self.close(engine, use: use)
        }
        input = nil
        await recognizer?.finish()
        recognizer = nil
        return heard.whole
    }

    /// What the recognizer heard: `kept` is finished, `guess` replaces the last guess.
    private func take(kept: String, guess: String) {
        onText?(heard.take(kept: kept, guess: guess))
    }

    /// Off the main thread: moving off a Bluetooth headset can wait seconds for the device (2026-11-01: 3 s), and
    /// on the main thread that froze the notch while it opened.
    private func startMicrophone(feeding input: ArisRecognizerInput) async throws {
        let parts = MicrophoneParts(engine: engine, use: use, input: input, levels: levels, recording: recording, samples: samples,
                                    speech: speechChunks)
        self.parts = parts
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ArisAudio.microphoneQueue.async {
                do {
                    try Self.openMicrophone(parts)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        microphoneOpened = true
        restarts = 0
        openedDevice = ArisMicChoice.device(of: engine)
        // Abandoned while opening (a start that took too long): no microphone stays open with nobody listening.
        if stopped {
            microphoneOpened = false
            await Self.close(engine, use: use)
            throw ArisFailure(message: ArisUIWords.text("듣기를 그만뒀어요.", "Stopped listening."))
        }
        configuration = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.configurationChanged() }
        }
    }

    /// The engine's configuration changed, which stops it. On the device the turn opened (a format, sample-rate or
    /// output change, AirPods flipping profile) the tap is reinstalled for the new format and the engine started
    /// again, at most twice a turn (ArisMicRestart); a different or vanished device, a third change, or a restart
    /// that fails ends the turn with what was heard (onInterrupted).
    private func configurationChanged() {
        guard microphoneOpened, let parts else { return }
        let decision = ArisMicRestart.decide(restarts: restarts, opened: openedDevice, current: ArisMicChoice.device(of: engine),
                                             present: ArisMicChoice.inputDeviceIds())
        guard decision == .reinstall else {
            NSLog("Aris: the input device changed or the engine changed too often; the turn ends with what was heard")
            onInterrupted?()
            return
        }
        restarts += 1
        ArisAudio.microphoneQueue.async { [weak self] in
            do {
                parts.engine.inputNode.removeTap(onBus: 0)
                try Self.installTap(parts)
                parts.engine.prepare()
                try parts.engine.start()
                NSLog("Aris: audio configuration changed on the same input; tap reinstalled and engine restarted")
            } catch {
                NSLog("Aris: engine couldn't restart after a configuration change: \(error.localizedDescription)")
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.onInterrupted?() } }
            }
        }
    }

    /// Removes the tap, stops the engine and gives the device back, on the microphone's queue.
    private static func close(_ engine: AVAudioEngine, use: ArisMicUse) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            ArisAudio.microphoneQueue.async {
                engine.inputNode.removeTap(onBus: 0)
                engine.stop()
                ArisAudio.retire(engine)
                ArisMicDevices.noteClosed(use, transport: nil)
                continuation.resume()
            }
        }
    }

    nonisolated private static func openMicrophone(_ parts: MicrophoneParts) throws {
        let engine = parts.engine
        // Bluetooth headphones: the Mac's own mic, so they stay in music mode (ArisMicChoice).
        // One device by its id, never the default input (ArisMicPlan). This is the user's own press, so a headset's
        // microphone is used when it is the only one, and closed the moment the turn ends.
        try ArisMicDevices.pin(engine, for: parts.use)
        try installTap(parts)
        engine.prepare()
        try engine.start()
    }

    /// The tap on the input in its current format, with both converters (the recognizer's format and Whisper's 16 kHz)
    /// built for it. Called at open and again after a format change.
    nonisolated private static func installTap(_ parts: MicrophoneParts) throws {
        let mic = parts.engine.inputNode
        guard let micFormat = ArisAudio.settledTapFormat(of: mic), let sink = TapSink(parts, from: micFormat) else {
            throw ArisFailure(message: "Couldn't read the microphone.")
        }
        mic.installTap(onBus: 0, bufferSize: 2048, format: micFormat) { buffer, _ in sink.take(buffer) }
    }
}

/// What opening the microphone needs, handed to the microphone's queue.
private struct MicrophoneParts: @unchecked Sendable {
    let engine: AVAudioEngine
    let use: ArisMicUse
    let input: ArisRecognizerInput
    let levels: LevelRelay
    let recording: Recording
    let samples: SampleRelay
    let speech: SampleRelay
}

/// One buffer of the microphone (or the test file) in its own format: its level to the orb, converted for the
/// recognizer, and at 16 kHz into the recording and to Scribe and the gesture's voice count. Both converters are
/// built for that format, once per tap.
private struct TapSink: @unchecked Sendable {
    let parts: MicrophoneParts
    let converter: AVAudioConverter
    let whisperConverter: AVAudioConverter
    let whisperFormat: AVAudioFormat

    init?(_ parts: MicrophoneParts, from format: AVAudioFormat) {
        let whisperFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: ArisWhisper.sampleRate,
                                          channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: format, to: parts.input.format),
              let whisperConverter = AVAudioConverter(from: format, to: whisperFormat) else { return nil }
        self.parts = parts
        self.converter = converter
        self.whisperConverter = whisperConverter
        self.whisperFormat = whisperFormat
    }

    func take(_ buffer: AVAudioPCMBuffer) {
        let level = ArisAudio.level(of: buffer), levels = parts.levels
        DispatchQueue.main.async { levels.handler?(level) }
        if let converted = ArisAudio.convert(buffer, with: converter, to: parts.input.format) {
            parts.input.append(converted)
        }
        if let forWhisper = ArisAudio.convert(buffer, with: whisperConverter, to: whisperFormat),
           let channel = forWhisper.floatChannelData?[0] {
            let chunk = UnsafeBufferPointer(start: channel, count: Int(forWhisper.frameLength))
            parts.recording.append(chunk)
            let floats = Array(chunk)
            parts.samples.handler?(floats)
            parts.speech.handler?(floats)
        }
    }
}

extension ArisListener {
    /// The test file (ArisListenFeed) in place of the microphone: its chunks at the pace they were spoken, through
    /// the microphone's own path (level, recognizer, recording), then silence until the turn ends.
    fileprivate func listen(to feed: ArisListenFeed, feeding input: ArisRecognizerInput) throws {
        let parts = MicrophoneParts(engine: engine, use: use, input: input, levels: levels, recording: recording, samples: samples,
                                    speech: speechChunks)
        guard let sink = TapSink(parts, from: feed.format) else { throw ArisFailure(message: "Couldn't read the test audio file.") }
        self.feed = feed
        NSLog("Aris: listening to the test file \(feed.url.lastPathComponent) (\(String(format: "%.1f", feed.duration)) s), not the microphone")
        feed.start(on: ArisAudio.microphoneQueue) { sink.take($0) }
    }

    /// The wake detector's 16 kHz audio, to the recognizer, the recording and the level, as the microphone would.
    fileprivate func listen(to source: ArisWakeDetector, feeding input: ArisRecognizerInput, from: Int? = nil) throws {
        let detectorFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: ArisVoicePrint.sampleRate,
                                           channels: 1, interleaved: false)!
        let format = input.format
        guard let converter = AVAudioConverter(from: detectorFormat, to: format) else {
            throw ArisFailure(message: "Couldn't read the microphone.")
        }
        let recording = recording, levels = levels, relay = self.samples, speech = speechChunks
        source.forward(to: { samples, level in
            guard !samples.isEmpty, let buffer = AVAudioPCMBuffer(pcmFormat: detectorFormat, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { chunk in
                buffer.floatChannelData?[0].update(from: chunk.baseAddress!, count: samples.count)
                recording.append(chunk)
            }
            relay.handler?(samples)
            speech.handler?(samples)
            if let converted = ArisAudio.convert(buffer, with: converter, to: format) {
                input.append(converted)
            }
            DispatchQueue.main.async { levels.handler?(level) }
        }, from: from)
    }
}

/// Hands each level to whoever listens now; set and called on the main thread only.
private final class LevelRelay: @unchecked Sendable {
    var handler: ((Float) -> Void)?
}

/// Hands each recorded chunk on; set on the main thread, called on the audio thread.
private final class SampleRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: (([Float]) -> Void)?
    var handler: (([Float]) -> Void)? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

/// The turn's audio, filled on the microphone's thread and read on the main one.
private final class Recording: @unchecked Sendable {
    /// Five minutes (ArisLongTurn): Whisper reads a long turn window by window.
    private static let limit = ArisLongTurn.recordedLimit(sampleRate: ArisWhisper.sampleRate)
    /// While waiting for the wake word: enough to hold "아리스" and what came right after.
    private static let rollingLimit = Int(ArisWhisper.sampleRate) * 4
    private let lock = NSLock()
    private var stored: [Float] = []
    private var rolling = false

    var samples: [Float] { lock.withLock { stored } }

    var count: Int { lock.withLock { stored.count } }

    func last(_ count: Int) -> [Float] { lock.withLock { Array(stored.suffix(count)) } }

    func reset(rolling: Bool) {
        lock.withLock {
            stored.removeAll(keepingCapacity: true)
            self.rolling = rolling
        }
    }

    func stopRolling() { lock.withLock { rolling = false } }

    func append(_ chunk: UnsafeBufferPointer<Float>) {
        lock.withLock {
            if rolling {
                stored.append(contentsOf: chunk)
                if stored.count > Self.rollingLimit * 2 { stored.removeFirst(stored.count - Self.rollingLimit) }
                return
            }
            guard stored.count < Self.limit else { return }
            stored.append(contentsOf: chunk.prefix(Self.limit - stored.count))
        }
    }
}

/// Audio buffer helpers shared by listening and speaking.
enum ArisAudio {
    /// Where microphones are opened and stopped, away from the main thread.
    static let microphoneQueue = DispatchQueue(label: "com.lumenjsn.aris.microphone", qos: .userInitiated)

    /// How long a stopped engine is kept before it may be freed.
    private static let retirement: TimeInterval = 10

    /// Keeps a stopped engine alive a little longer: CoreAudio can still deliver a device change to it (headphones
    /// plugged in, AirPods switching), and a freed engine crashes the app when that arrives (2026-10-25 03:39).
    static func retire(_ engine: AVAudioEngine) {
        DispatchQueue.main.asyncAfter(deadline: .now() + retirement) { withExtendedLifetime(engine) {} }
    }

    /// Loudness of a buffer, scaled so normal speech lands around 0.3...0.8.
    static func level(of buffer: AVAudioPCMBuffer) -> Float {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        var sum: Float = 0
        if let samples = buffer.floatChannelData?[0] {
            for i in 0..<frames { sum += samples[i] * samples[i] }
        } else if let samples = buffer.int16ChannelData?[0] {
            for i in 0..<frames { let s = Float(samples[i]) / Float(Int16.max); sum += s * s }
        } else {
            return 0
        }
        let rms = (sum / Float(frames)).squareRoot()
        return min(1, rms * 8)
    }

    /// tapFormat, once the input has settled: right after the device changes (the Mac's microphone picked over a
    /// Bluetooth headset, AirPods switching) the node can still report the old rate for a moment, and a tap installed
    /// then throws an Objective-C exception Swift can't catch (crashed 2026-11-01 20:10). Waits up to half a second
    /// for the two to agree, on the microphone's queue only.
    static func settledTapFormat(of mic: AVAudioInputNode) -> AVAudioFormat? {
        for _ in 0..<5 {
            let hardware = mic.inputFormat(forBus: 0), node = mic.outputFormat(forBus: 0)
            if hardware.sampleRate > 0, hardware.sampleRate == node.sampleRate { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return tapFormat(of: mic)
    }

    static func tapFormat(of mic: AVAudioInputNode) -> AVAudioFormat? {
        let hardware = mic.inputFormat(forBus: 0), node = mic.outputFormat(forBus: 0)
        guard hardware.sampleRate > 0, hardware.channelCount > 0, node.channelCount > 0 else { return nil }
        if node.sampleRate == hardware.sampleRate { return node }
        return AVAudioFormat(commonFormat: node.commonFormat, sampleRate: hardware.sampleRate,
                             channels: node.channelCount, interleaved: node.isInterleaved)
    }

    static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil && out.frameLength > 0 ? out : nil
    }
}
