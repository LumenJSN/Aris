//
//  ArisListener.swift
//  Aris
//
//  The microphone, transcribed on the Mac by SpeechAnalyzer (macOS 26+).
//  Reports the text heard so far and how loud the voice is (for the orb), and
//  keeps a 16 kHz recording of the turn for Whisper's second listen.
//  While waiting for the wake word it keeps only the current phrase and the last
//  few seconds of audio; beginTurn() carries on into a turn without a restart, so
//  nothing said right after "아리스" is lost. The recording holds five minutes
//  (ArisLongTurn); Whisper reads a long one window by window.
//

import AVFoundation
import Speech

@available(macOS 26.0, *)
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
    /// Who this listener's own microphone is opened for (the log names it): a turn's talk key, or dictation.
    var use = ArisMicUse.talk
    /// Listening for the wake word, not yet in a turn.
    private(set) var waiting = false

    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var results: Task<Void, Never>?
    private var finished = ""
    private var guess = ""
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
        finished = ""
        guess = ""
        // A listener already woken into its turn stays a turn's: its phrases are kept and its recording whole
        // (audit voice-2).
        waiting = handOver.startsWaiting(asked: waitingForWakeWord)
        recording.reset(rolling: waiting)
        // Without .fastResults the guesses only arrive once listening stops; with it, about once a second.
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [],
                                            reportingOptions: [.volatileResults, .fastResults], attributeOptions: [])
        // The language's model isn't installed yet (a first run): it downloads in the background, and this turn says so
        // instead of timing out while it waits (prepareSpeechAssets at launch makes this rare). With no microphone on
        // this Mac at all, that is what is said, first: "say it again in a moment" would change nothing (ArisListenStart).
        let modelMissing = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) != nil
        if modelMissing { Task { await Self.prepareSpeechAssets(locale: locale) } }
        switch ArisListenStart.problem(usesMicrophone: source == nil, hasMicrophone: ArisMicChoice.hasMicrophone(), modelMissing: modelMissing) {
        case .noMicrophone: throw ArisFailure(message: ArisListenerWords.noMicrophone())
        case .modelPreparing: throw ArisFailure(message: ArisListenerWords.modelPreparing())
        case nil: break
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw ArisFailure(message: "Speech recognition isn't available for \(locale.identifier).")
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let vocabulary = ArisHearingLocale.hints(vocabulary: ArisVocabulary.load(), locale: locale.identifier,
                                                 waitingForWakeWord: waitingForWakeWord)
        if !vocabulary.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = vocabulary
            // Only hints: without them Aris still listens.
            do { try await analyzer.setContext(context) } catch { NSLog("Aris: vocabulary not used: \(error.localizedDescription)") }
        }
        let (stream, input) = AsyncStream<AnalyzerInput>.makeStream()
        self.analyzer = analyzer
        self.input = input

        results = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    self?.take(String(result.text.characters), final: result.isFinal)
                }
            } catch {
                NSLog("Aris: transcription ended: \(error.localizedDescription)")
            }
        }
        try await analyzer.start(inputSequence: stream)
        if let source {
            self.source = source
            try listen(to: source, feeding: input, as: format, from: from)
        } else {
            try await startMicrophone(feeding: input, as: format)
        }
    }

    /// Whether macOS's speech model for `locale` is on this Mac. Opens nothing: the wake word asks before its microphone.
    static func speechModelInstalled(locale: Locale) async -> Bool {
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [])
        do { return try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) == nil } catch { return false }
    }

    /// At launch: the language's speech model is installed ahead of the first turn, so that turn doesn't wait for it.
    /// A turn that finds it missing joins the same install.
    static func prepareSpeechAssets(locale: Locale) async {
        // Another language's install under way (the languages were just changed) is waited for, then this one starts.
        while let running = assetInstall {
            await running.task.value
            if assetInstall?.task == running.task { assetInstall = nil }
            if running.locale == locale.identifier { return }
        }
        let task = Task {
            let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [])
            guard let install = try? await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else { return }
            NSLog("Aris: installing the speech model for \(locale.identifier)")
            // The first listen says 음성 인식 준비 중 while this runs (③ B).
            await MainActor.run { ArisModelDownloader.shared.setAppleInstalling(true) }
            do { try await install.downloadAndInstall() } catch { NSLog("Aris: speech model not installed: \(error.localizedDescription)") }
            await MainActor.run { ArisModelDownloader.shared.setAppleInstalling(false) }
        }
        assetInstall = (locale.identifier, task)
        await task.value
        if assetInstall?.task == task { assetInstall = nil }
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

    /// One install at a time, shared by the launch-time prepare and any turn that finds the model missing.
    nonisolated(unsafe) private static var assetInstall: (locale: String, task: Task<Void, Never>)?

    /// The wake word was heard: from here on this is a turn (the phrase with the name in it is kept).
    func beginTurn() {
        handOver.beginTurn()
        waiting = false
        recording.stopRolling()
    }

    /// Stops listening and returns the whole utterance.
    func stop() async -> String {
        stopped = true
        source?.forward(to: nil)
        source = nil
        if let configuration { NotificationCenter.default.removeObserver(configuration) }
        configuration = nil
        // An engine that was never opened has no tap and no device to give back. Stopping waits on the device the
        // way starting does (a Bluetooth switch can take seconds): off the main thread, so the notch never freezes.
        if microphoneOpened {
            microphoneOpened = false
            await Self.close(engine, use: use)
        }
        input?.finish()
        input = nil
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        analyzer = nil
        await results?.value
        results = nil
        return (finished + guess).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func take(_ text: String, final: Bool) {
        if final {
            finished += text
            guess = ""
        } else {
            guess = text
        }
        onText?(finished + guess)
        // While waiting, a finished phrase without the name is forgotten.
        if waiting && final { finished = "" }
    }

    /// Off the main thread: moving off a Bluetooth headset can wait seconds for the device (2026-11-01: 3 s), and
    /// on the main thread that froze the notch while it opened.
    private func startMicrophone(feeding input: AsyncStream<AnalyzerInput>.Continuation, as format: AVAudioFormat) async throws {
        let parts = MicrophoneParts(engine: engine, use: use, input: input, format: format, levels: levels, recording: recording, samples: samples,
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
        let engine = parts.engine, input = parts.input, format = parts.format
        let mic = engine.inputNode
        let whisperFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: ArisWhisper.sampleRate,
                                          channels: 1, interleaved: false)!
        guard let micFormat = ArisAudio.settledTapFormat(of: mic),
              let converter = AVAudioConverter(from: micFormat, to: format),
              let whisperConverter = AVAudioConverter(from: micFormat, to: whisperFormat) else {
            throw ArisFailure(message: "Couldn't read the microphone.")
        }
        let levels = parts.levels, recording = parts.recording, samples = parts.samples, speech = parts.speech
        mic.installTap(onBus: 0, bufferSize: 2048, format: micFormat) { buffer, _ in
            let level = ArisAudio.level(of: buffer)
            DispatchQueue.main.async { levels.handler?(level) }
            if let converted = ArisAudio.convert(buffer, with: converter, to: format) {
                input.yield(AnalyzerInput(buffer: converted))
            }
            if let forWhisper = ArisAudio.convert(buffer, with: whisperConverter, to: whisperFormat),
               let channel = forWhisper.floatChannelData?[0] {
                let chunk = UnsafeBufferPointer(start: channel, count: Int(forWhisper.frameLength))
                recording.append(chunk)
                let floats = Array(chunk)
                samples.handler?(floats)
                speech.handler?(floats)
            }
        }
    }
}

/// What opening the microphone needs, handed to the microphone's queue.
@available(macOS 26.0, *)
private struct MicrophoneParts: @unchecked Sendable {
    let engine: AVAudioEngine
    let use: ArisMicUse
    let input: AsyncStream<AnalyzerInput>.Continuation
    let format: AVAudioFormat
    let levels: LevelRelay
    let recording: Recording
    let samples: SampleRelay
    let speech: SampleRelay
}

@available(macOS 26.0, *)
extension ArisListener {
    /// The wake detector's 16 kHz audio, to the recognizer, the recording and the level, as the microphone would.
    fileprivate func listen(to source: ArisWakeDetector, feeding input: AsyncStream<AnalyzerInput>.Continuation,
                            as format: AVAudioFormat, from: Int? = nil) throws {
        let detectorFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: ArisVoicePrint.sampleRate,
                                           channels: 1, interleaved: false)!
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
                input.yield(AnalyzerInput(buffer: converted))
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
