//
//  ArisSpeaker.swift
//  Aris
//
//  Aris's voice: the chosen ElevenLabs voice (Geaun by default) when the key is set up, otherwise (or when
//  ElevenLabs can't be reached) the best installed system voice. Either way it plays
//  through an audio engine so the orb can follow how loud it is, and an answer is read sentence by sentence as it
//  arrives. ElevenLabs dropping out mid-answer hands the rest to the system voice (ArisVoiceFallback); after two
//  failures in a row it isn't asked for a few minutes (ArisCloudBreaker).
//

import AVFoundation
import Defaults
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "voice")

/// What Aris's voice plays right now, as raw RMS, for the barge-in watch on the microphone's queue (ArisBargeIn).
final class ArisPlaybackMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var rms: Float = 0

    func set(_ value: Float) { lock.withLock { rms = value } }
    @Sendable func read() -> Float { lock.withLock { rms } }

    static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        let frames = Int(buffer.frameLength)
        guard frames > 0, let samples = buffer.floatChannelData?[0] else { return 0 }
        var sum: Float = 0
        for i in 0..<frames { sum += samples[i] * samples[i] }
        return (sum / Float(frames)).squareRoot()
    }
}

@MainActor
final class ArisSpeaker {
    /// Voice loudness while speaking, 0...1.
    var onLevel: ((Float) -> Void)?
    /// The output's RMS now, readable off the main thread.
    let meter = ArisPlaybackMeter()

    private static let cloudFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: ArisElevenLabs.sampleRate,
                                                   channels: 1, interleaved: false)!

    private let synthesizer = AVSpeechSynthesizer()
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var format: AVAudioFormat?
    /// The current voice's buffers (ArisVoiceProgress): a stopped voice's completions don't count.
    private var progress = ArisVoiceProgress()
    private var finished: CheckedContinuation<Void, Never>?
    private var cloud: Task<Void, Never>?
    /// Fetching the voice for the sentences of an answer that is still arriving.
    private var cloudFetch: Task<Void, Never>?
    private var cloudSamples = 0
    /// An answer's sentences that were sent to the voice, in case the system voice has to say them instead.
    private var cloudSentences: [String] = []
    /// The sentences ElevenLabs gave up on: the system voice reads them and the rest of the answer (ArisVoiceFallback).
    private var cloudHandOver: [String]?
    /// Which speak() is current: a call that was stopped or overtaken never speaks late or takes a newer call's
    /// `finished` continuation.
    private var generation = 0
    /// When someone started talking over the voice (it's turned down until they stop; ArisDucking).
    private var duckedAt: ContinuousClock.Instant?
    private var restoring: Task<Void, Never>?
    /// Stops the engine a moment after the voice ends, so Aris isn't in the speakers' IO cycle between replies
    /// (ArisAudioQuiet).
    private var idleStop: Task<Void, Never>?
    private var outputWatch: NSObjectProtocol?
    /// The voice's own way out while a headset is the default input (ArisOwnOutput), and which way it goes now.
    private let ownOutput = ArisOwnOutput()
    private var route = ArisVoiceRoute.engine
    /// The own output couldn't be set up or started in this run: the engine's is used from then on.
    private var ownOutputFailed = false
    init() {
        engine.attach(player)
        outputWatch = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                                                             queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.outputChanged() }
        }
    }

    /// The output changed under the voice (AirPods connected, headphones unplugged) and the engine stopped: buffers
    /// already scheduled would never finish, so speak() would wait out its timeout in silence (bug hunt 11-06 #10).
    /// They're dropped (their completions end the line once everything was sent), and the next buffer reconnects the
    /// player and starts the engine on the new output.
    private func outputChanged() {
        guard !engine.isRunning else { return }
        format = nil
        guard finished != nil else { return }
        log.notice("the output changed while speaking: the rest of this line is dropped")
        player.stop()
    }

    /// Speaks the start of `text` and returns when the voice has finished. A muted Aris says nothing (the voice that
    /// was speaking still stops); `preview`: the Settings window's 미리 듣기, the one thing that plays while muted
    /// (ArisQuiet.voiceMayPlay).
    func speak(_ text: String, preview: Bool = false) async {
        stop()
        guard ArisQuiet.voiceMayPlay(muted: ArisQuietGate.muted, preview: preview) else { return }
        let spoken = ArisSpeech.spokenPart(of: text)
        guard !spoken.isEmpty else { return }
        if let key = Self.cloudKey() {
            let mine = generation
            if await speakWithElevenLabs(spoken, key: key) { return }
            // Stopped meanwhile (a new turn, the pill): nothing is said late in the other voice.
            guard mine == generation, !Task.isCancelled else { return }
            log.notice("ElevenLabs sent no audio; using the system voice")
        }
        await speakWithSystemVoice(spoken)
    }

    /// The ElevenLabs key when there is one and ElevenLabs may be asked now; nil: the system voice speaks. After two
    /// failures in a row it isn't asked for a few minutes, so an answer doesn't start with four seconds of silence
    /// each time (audit voice-imp-4).
    private static func cloudKey() -> String? {
        // macOS 목소리 picked in settings (AI 서비스 › 말하기): ElevenLabs isn't asked even with a key.
        guard UserDefaults.standard.string(forKey: ArisAIPrefKey.speakEngine) != "macos" else { return nil }
        guard let key = ArisElevenLabs.loadKey() else { return nil }
        guard ArisCloudHealth.voice.mayTry(at: .now) else {
            log.notice("ElevenLabs is resting after failures; the system voice speaks")
            return nil
        }
        return key
    }

    /// Whether a failed request counts towards resting ElevenLabs (ArisCloudBreaker.counts).
    private static func countsAgainstElevenLabs(_ error: Error) -> Bool {
        ArisCloudBreaker.counts(status: (error as? ArisElevenLabs.Failure)?.status)
    }

    /// Speaks an answer's sentences as they arrive (it's still being written), every one of them: what of a long
    /// answer is read is ArisSpeechStream's call. Each sentence's audio is requested when its turn to play comes, so
    /// they play back to back. Returns when the voice is done.
    func speak(sentences: AsyncStream<String>) async {
        stop()
        // Muted: the answer's sentences are taken and none is said; it returns when the answer is whole, as the voice would.
        guard ArisQuiet.voiceMayPlay(muted: ArisQuietGate.muted, preview: false) else {
            for await _ in sentences {}
            return
        }
        let mine = generation
        // No key (or ElevenLabs resting): the system voice, each sentence as it arrives (audit voice-imp-1: it used
        // to wait for the whole answer, silent for as long as the AI worked), and never after a stop (audit voice-3:
        // stopped or overtaken while the answer was still being written, it then read the abandoned answer aloud).
        guard let key = Self.cloudKey() else { return await speakWithSystemVoice(then: sentences, of: mine) }
        startPlayback()
        cloudSamples = 0
        cloudSentences = []
        cloudHandOver = nil
        // Sentences, not requests: each request is made only when its turn to play comes, so after a fallback no
        // request is left in flight for a sentence the system voice is already reading.
        let (voices, nextVoice) = AsyncStream.makeStream(of: String.self)
        cloudFetch = Task { [weak self] in
            for await sentence in sentences {
                guard let self else { continue }
                let spoken = ArisSpeech.spoken(sentence)
                guard !spoken.isEmpty else { continue }
                self.cloudSentences.append(spoken)
                nextVoice.yield(spoken)
            }
            nextVoice.finish()
        }
        await withCheckedContinuation { continuation in
            finished = continuation
            cloud = Task { [weak self] in
                // The sentence before this one broke off part-way; and every sentence asked for so far.
                var lastBroke = false
                var asked: [String] = []
                sentences: for await spoken in voices {
                    asked.append(spoken)
                    // A sentence that fails once audio has played is asked for once more, so a long reading doesn't
                    // lose a sentence to one dropped request; what happens after a failure is ArisVoiceFallback's call.
                    attempts: for attempt in 1...2 {
                        var got = 0
                        do {
                            for try await samples in Self.cloudSpeech(spoken, key: key, after: asked.dropLast()) {
                                guard let self, let buffer = Self.buffer(of: samples) else { return }
                                self.cloudSamples += samples.count
                                got += samples.count
                                self.play(buffer, of: mine)
                            }
                            if got > 0, !Task.isCancelled {
                                ArisCloudHealth.voice.succeeded()
                                lastBroke = false
                            }
                            break attempts
                        } catch is CancellationError {
                            return
                        } catch {
                            log.error("ElevenLabs failed (try \(attempt, privacy: .public)): \(String(describing: error), privacy: .public)")
                            guard let self, !Task.isCancelled else { return }
                            if Self.countsAgainstElevenLabs(error) { ArisCloudHealth.voice.failed(at: .now) }
                            switch ArisVoiceFallback.afterFailure(attempt: attempt, playedOfSentence: got > 0, playedAnything: self.cloudSamples > 0,
                                                                  lastSentenceBroke: lastBroke) {
                            case .retry:
                                continue attempts
                            case .skipSentence:
                                lastBroke = true
                                break attempts
                            case .systemVoice:
                                // What already plays is let finish; then the system voice has this sentence and the
                                // rest (with nothing played at all, every sentence so far).
                                self.cloudHandOver = self.cloudSamples > 0 ? [spoken] : asked
                                break sentences
                            }
                        }
                    }
                    guard !Task.isCancelled else { return }
                }
                if let end = Self.buffer(of: []) { self?.play(end, of: mine) }
            }
        }
        // ElevenLabs gave up on a sentence (it never answered, or dropped out mid-answer): the system voice reads that
        // sentence and the rest as they arrive, instead of skipping them without a word (audit voice-8). Not when this
        // call was stopped or overtaken meanwhile.
        if let failed = cloudHandOver {
            cloudHandOver = nil
            guard mine == generation, !Task.isCancelled else { return }
            log.notice("ElevenLabs gave up; the system voice reads the rest")
            return await speakWithSystemVoice(first: failed, then: voices, of: mine)
        }
        guard cloudSamples == 0, cloud != nil, mine == generation else { return }
        // The rest of the answer's sentences are still being collected; the system voice reads them all, unless this
        // call was stopped or overtaken meanwhile (then a newer call owns the voice).
        await cloudFetch?.value
        guard mine == generation, !Task.isCancelled, !cloudSentences.isEmpty else { return }
        log.notice("ElevenLabs sent no audio; using the system voice")
        await speakWithSystemVoice(cloudSentences.joined(separator: " "))
    }

    /// Someone started talking over Aris: 10 dB down at once.
    func duck() {
        restoring?.cancel()
        restoring = nil
        duckedAt = .now
        player.volume = ArisDucking.duckedVolume
    }

    /// They stopped: back to full over a second, once it has been down long enough.
    func unduck() {
        guard let duckedAt else { return }
        restoring?.cancel()
        restoring = Task { [weak self] in
            let wait = ArisDucking.shortestDuck - (ContinuousClock.now - duckedAt)
            if wait > .zero { try? await Task.sleep(for: wait) }
            let start = ContinuousClock.now
            while !Task.isCancelled {
                let elapsed = ContinuousClock.now - start
                self?.player.volume = ArisDucking.volume(restoringFor: elapsed)
                if elapsed >= ArisDucking.restoreTime {
                    self?.duckedAt = nil
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    func stop() {
        generation += 1
        restoring?.cancel()
        restoring = nil
        duckedAt = nil
        player.volume = 1
        cloudFetch?.cancel()
        cloudFetch = nil
        cloud?.cancel()
        cloud = nil
        synthesizer.stopSpeaking(at: .immediate)
        player.stop()
        onLevel?(0)
        meter.set(0)
        resume()
    }

    /// The one way a line is asked of ElevenLabs, for an answer's sentences, a single line and the Settings window's
    /// 미리 듣기 alike: the chosen voice (with its saved settings), model and speed, and the sentences of the same answer
    /// said before it (`said`), so the answer reads as one flow.
    private static func cloudSpeech(_ text: String, key: String, after said: ArraySlice<String> = []) -> AsyncThrowingStream<[Float], Error> {
        let previous = said.suffix(2).joined(separator: " ")
        return ArisElevenLabs.speech(for: text, key: key, voiceID: Defaults[.arisVoiceID], speed: Defaults[.arisVoiceSpeed],
                                     previous: previous.isEmpty ? nil : previous)
    }

    /// Streams Geaun's voice. False when no audio came, so the system voice can take over.
    private func speakWithElevenLabs(_ text: String, key: String) async -> Bool {
        startPlayback()
        let mine = generation
        cloudSamples = 0
        await withCheckedContinuation { continuation in
            finished = continuation
            cloud = Task { [weak self] in
                do {
                    for try await samples in Self.cloudSpeech(text, key: key) {
                        guard let self, let buffer = Self.buffer(of: samples) else { return }
                        self.cloudSamples += samples.count
                        self.play(buffer, of: mine)
                    }
                    if !Task.isCancelled, (self?.cloudSamples ?? 0) > 0 { ArisCloudHealth.voice.succeeded() }
                } catch is CancellationError {
                    return
                } catch {
                    log.error("ElevenLabs failed: \(String(describing: error), privacy: .public)")
                    if !Task.isCancelled, Self.countsAgainstElevenLabs(error) { ArisCloudHealth.voice.failed(at: .now) }
                }
                if let end = Self.buffer(of: []) { self?.play(end, of: mine) }
            }
        }
        return cloudSamples > 0
    }

    /// The system voice reads an answer sentence by sentence: `first` now, then each of `sentences` as it arrives,
    /// until the stream ends or this speak() (`mine`) is stopped or overtaken; after that nothing more is said. One
    /// voice for the whole answer (ArisAnswerVoice).
    private func speakWithSystemVoice(first: [String] = [], then sentences: AsyncStream<String>, of mine: Int) async {
        var voice = ArisAnswerVoice()
        await ArisSentenceReader.read(first: first, then: sentences, isCurrent: { mine == self.generation && !Task.isCancelled }) { sentence in
            let spoken = ArisSpeech.spoken(sentence)
            guard !spoken.isEmpty else { return }
            await self.speakWithSystemVoice(spoken, in: voice.language(for: spoken, among: Defaults[.arisLanguages]))
        }
    }

    /// `language`: the voice's locale when the caller already knows it; nil: worked out from the words.
    private func speakWithSystemVoice(_ spoken: String, in language: String? = nil) async {
        let utterance = AVSpeechUtterance(string: spoken)
        utterance.voice = Self.voice(for: language ?? ArisSpeech.language(of: spoken, among: Defaults[.arisLanguages]))
        utterance.rate = ArisElevenLabs.systemRate(speed: Defaults[.arisVoiceSpeed], defaultRate: AVSpeechUtteranceDefaultSpeechRate)
        startPlayback()
        let mine = generation
        await withCheckedContinuation { continuation in
            finished = continuation
            // Buffers that arrive after a stop() belong to the stopped voice, not the next one.
            synthesizer.write(utterance) { [weak self] buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                DispatchQueue.main.async { self?.play(pcm, of: mine) }
            }
        }
    }

    private func startPlayback() {
        idleStop?.cancel()
        idleStop = nil
        if duckedAt == nil { player.volume = 1 }
        progress.start(generation)
    }

    /// Schedules one buffer of the speak() `voice` (a generation); an empty buffer means the voice has sent
    /// everything. Another generation's buffer is dropped.
    private func play(_ buffer: AVAudioPCMBuffer, of voice: Int) {
        guard finished != nil, voice == generation else { return }
        guard buffer.frameLength > 0 else {
            if progress.wroteAll() { resume() }
            return
        }
        guard prepare(for: buffer.format) else { return resume() }
        progress.schedule()
        player.scheduleBuffer(buffer) { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.progress.played(voice) { self.resume() }
            }
        }
        if !player.isPlaying { player.play() }
    }

    /// Connects the player for the voice's format and starts the engine. Which way the sound leaves is chosen here,
    /// each time the engine starts from rest (ArisVoiceRoute): while the default input is a Bluetooth headset's, through
    /// an output with no input side, so speaking never opens the headset's microphone.
    private func prepare(for bufferFormat: AVAudioFormat) -> Bool {
        let stale = format != bufferFormat
        if stale || !engine.isRunning {
            let now = ArisMicDevices.voiceRoute()
            let wanted = ownOutputFailed ? ArisVoiceRoute.engine : now.route
            if stale || wanted != route {
                stopOutput()
                player.removeTap(onBus: 0)
                setRoute(wanted, input: now.input)
                engine.connect(player, to: engine.mainMixerNode, format: bufferFormat)
                let report = onLevel, meter = meter
                player.installTap(onBus: 0, bufferSize: 1024, format: bufferFormat) { buffer, _ in
                    let level = ArisAudio.level(of: buffer)
                    meter.set(ArisPlaybackMeter.rms(of: buffer))
                    DispatchQueue.main.async { report?(level) }
                }
                format = bufferFormat
            }
        }
        guard !engine.isRunning else { return true }
        do {
            if route == .own { try ownOutput.start(engine) } else { try engine.start() }
            return true
        } catch {
            log.error("couldn't start audio: \(String(describing: error), privacy: .public)")
            // The own output couldn't start: the engine's own output says this line, and the rest of this run.
            guard route == .own else { return false }
            ownOutputFailed = true
            format = nil
            return prepare(for: bufferFormat)
        }
    }

    /// Takes the stopped engine off the hardware (its own output) or gives it back (the engine's).
    private func setRoute(_ wanted: ArisVoiceRoute, input: ArisAudioDevice.Transport?) {
        var next = wanted
        if wanted == .own {
            do {
                try ArisOwnOutput.detach(engine)
            } catch {
                log.error("the voice's own output couldn't be set up: \(String(describing: error), privacy: .public)")
                ownOutputFailed = true
                next = .engine
            }
        }
        if next == .engine { ArisOwnOutput.attach(engine) }
        if next != route { ArisMicDevices.noteVoice(next, input: input) }
        route = next
    }

    /// Stops the output unit (when the voice has its own) and the engine.
    private func stopOutput() { ownOutput.stop(engine) }

    private func resume() {
        guard let continuation = finished else { return }
        finished = nil
        onLevel?(0)
        meter.set(0)
        continuation.resume()
        stopEngineSoon()
    }

    /// The voice is done: the engine stops after ArisAudioQuiet.speakerIdle unless another speak() began.
    private func stopEngineSoon() {
        idleStop?.cancel()
        let mine = generation
        idleStop = Task { [weak self] in
            try? await Task.sleep(for: ArisAudioQuiet.speakerIdle)
            guard !Task.isCancelled, let self,
                  ArisAudioQuiet.mayStopSpeaker(scheduledFor: mine, current: self.generation, voicePending: self.finished != nil)
            else { return }
            self.idleStop = nil
            self.player.stop()
            self.stopOutput()
        }
    }

    private static func buffer(of samples: [Float]) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: cloudFormat, frameCapacity: AVAudioFrameCount(max(1, samples.count))),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            if let start = source.baseAddress { channel.update(from: start, count: source.count) }
        }
        return buffer
    }

    private static func voice(for language: String) -> AVSpeechSynthesisVoice? {
        let installed = AVSpeechSynthesisVoice.speechVoices()
        let choices = installed.map { ArisSpeech.Voice(identifier: $0.identifier, language: $0.language, quality: $0.quality.rawValue) }
        let preferred = UserDefaults.standard.string(forKey: ArisAIPrefKey.systemVoice) ?? ""
        if let identifier = ArisSpeech.pickVoice(from: choices, language: language, preferred: preferred) {
            return AVSpeechSynthesisVoice(identifier: identifier)
        }
        return AVSpeechSynthesisVoice(language: language)
    }
}
