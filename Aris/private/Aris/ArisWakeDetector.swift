//
//  ArisWakeDetector.swift
//  Aris
//
//  The microphone while Aris waits. It opens the one device ArisMicPlan names and hands every 16 kHz chunk to
//  ArisWakeCore, which holds the two stages: every 10 ms only loudness is measured; when a sound starts after a quiet
//  moment its first half second is checked for a voice and, trained, against your “아리스”; a likely match is handed
//  on (`onCandidate`) so the recognizer can check the words. In training it hands on each phrase you say instead.
//  The last few seconds are kept in memory only, and the detector stays the only one on the microphone: the
//  recognizer is fed from it (everything from just before the candidate phrase, then live), so nothing you said is
//  lost to the hand-over.
//

import AVFoundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "wake")

final class ArisWakeDetector: @unchecked Sendable {
    typealias Mode = ArisWakeCore.Mode

    /// A phrase that may be "아리스" (main thread): its distance from your recordings (nil untrained), and
    /// `sure` when it's as close as your own recordings.
    var onCandidate: ((_ score: Float?, _ sure: Bool) -> Void)?
    /// Training: one phrase you said, 16 kHz (main thread).
    var onPhrase: (([Float]) -> Void)?
    /// Loudness 0...1 for the orb while training (main thread).
    var onLevel: ((Float) -> Void)?
    /// The microphone changed or stopped (main thread).
    var onInterrupted: (() -> Void)?
    /// Someone started (true) or stopped (false) talking, while waiting (main thread): Aris ducks under it.
    var onVoice: ((Bool) -> Void)?
    /// In a conversation: the voice watch (watchVoice) is sure the user is talking (main thread), with the sample the turn's
    /// audio should start from (for forward(to:from:)).
    var onVoiceStart: ((_ fromSample: Int, _ lookback: Double) -> Void)?
    private var configuration: NSObjectProtocol?

    private let engine = AVAudioEngine()
    /// Who opened the microphone (the wake word, or the name's training) and the kind of device it is on, for the log.
    private var use = ArisMicUse.wake
    private var transport: ArisAudioDevice.Transport?
    /// The device it was pinned to (on `queue`).
    private var device: UInt32?
    private let queue = DispatchQueue(label: "com.lumenjsn.aris.wake")
    // On `queue`:
    private var core = ArisWakeCore(mode: .waiting(nil))
    /// Who else gets every chunk (16 kHz) and its loudness: the recognizer checking a phrase, then its turn.
    private var forwarder: (([Float], Float) -> Void)?
    /// In a conversation: the user's voice on each hop, between turns or over Aris (ArisBargeIn), and what Aris plays now.
    private var voiceWatch: ArisBargeIn?
    private var playbackLevel: (@Sendable () -> Float)?
    /// The room as the last watch learned it, for the next one.
    private var roomFloor: Float = 0.005

    /// `paused`: start without handing on candidates (a conversation listens for any voice, not the name).
    func start(_ mode: Mode, paused: Bool = false) throws {
        let voiceCheck = ArisWakeVoice.enabled(setting: UserDefaults.standard.string(forKey: ArisWakeVoice.key))
        queue.sync {
            core = ArisWakeCore(mode: mode, voiceCheck: voiceCheck, paused: paused)
            forwarder = nil
        }
        // Pinned to one device by its id (ArisMicPlan): never the default input, which a headset connecting later
        // would become; with only a headset's microphone the wake word opens nothing (ArisMicPaused is thrown).
        if case .training = mode { use = .setup } else { use = .wake }
        let pinned = try ArisMicDevices.pin(engine, for: use)
        transport = pinned?.transport
        queue.sync { device = pinned?.id }
        let mic = engine.inputNode
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: ArisVoicePrint.sampleRate, channels: 1, interleaved: false)!
        // A detector that was started before (a restart after the microphone changed) has a tap already.
        mic.removeTap(onBus: 0)
        guard let micFormat = ArisAudio.settledTapFormat(of: mic), let converter = AVAudioConverter(from: micFormat, to: format) else {
            throw ArisFailure(message: "Couldn't read the microphone.")
        }
        mic.installTap(onBus: 0, bufferSize: 1600, format: micFormat) { [weak self] buffer, _ in
            guard let converted = ArisAudio.convert(buffer, with: converter, to: format), let channel = converted.floatChannelData?[0] else { return }
            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(converted.frameLength)))
            // On the tap's own thread, under the queue's lock: one wake-up per buffer instead of two.
            self?.queue.sync { self?.take(samples) }
        }
        engine.prepare()
        try engine.start()
        configuration = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                                                               queue: .main) { [weak self] _ in self?.onInterrupted?() }
    }

    /// On the microphone's queue, after a start still under way there.
    func stop() {
        ArisAudio.microphoneQueue.async { [self] in
            if let configuration { NotificationCenter.default.removeObserver(configuration) }
            configuration = nil
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            ArisAudio.retire(engine)
            ArisMicDevices.noteClosed(use, transport: transport)
        }
    }

    /// The device the engine's microphone is on now (nil before it opened): the controller opens it again when the
    /// plan names another (ArisMicPlan.mustReopen).
    var openDevice: UInt32? { queue.sync { device } }

    /// The sample the detector has reached: a listener started `from:` it hears only what comes next.
    var currentSample: Int { queue.sync { core.received } }

    /// Where the last candidate phrase starts (from just before it): the recognizer that checks it is fed from here.
    var candidateSample: Int? { queue.sync { core.candidateStartSample } }

    /// The last candidate phrase from its start, up to `seconds` long (16 kHz), for Whisper to check.
    func candidateAudio(seconds: Double) -> [Float] {
        queue.sync { core.candidateAudio(seconds: seconds) }
    }

    /// While the recognizer checks a candidate, don't hand on another.
    func pause(_ paused: Bool) {
        queue.async { self.core.paused = paused }
    }

    /// Watches for the user's voice (`mode`, nil stops) against what Aris plays (`playback`, its output RMS now); once sure
    /// it calls onVoiceStart once. A new watch starts from the room level the last one learned.
    func watchVoice(_ mode: ArisBargeIn.Mode?, playback: (@Sendable () -> Float)? = nil) {
        queue.async {
            self.voiceWatch = mode.map { ArisBargeIn(mode: $0, floor: self.roomFloor) }
            self.playbackLevel = playback
        }
    }

    /// Sends `sink` everything from sample `from` (the candidate phrase from just before it began; a conversation's
    /// turn from just before the voice watch was sure), or with nil the latest phrase so far, then every chunk from
    /// now on, in order; nil stops. Called on the detector's own queue.
    func forward(to sink: (([Float], Float) -> Void)?, from: Int? = nil) {
        queue.sync {
            if let sink { sink(core.audio(from: from), 0) }
            forwarder = sink
        }
    }

    // MARK: - On `queue`

    private func take(_ samples: [Float]) {
        forwarder?(samples, min(1, ArisVoicePrint.rms(samples[...]) * 8))
        let reached = core.received + samples.count
        let checksBefore = core.counts.printChecks
        let events = core.take(samples) { level in self.watch(level, reached: reached) }
        if core.counts.printChecks != checksBefore, let score = core.lastScore, case .waiting(let model?) = core.mode {
            log.notice("phrase scored \(score, privacy: .public) (wakes at \(model.threshold, privacy: .public))")
        }
        for event in events {
            switch event {
            case .voice(let talking): DispatchQueue.main.async { self.onVoice?(talking) }
            case .candidate(let score, let sure): DispatchQueue.main.async { self.onCandidate?(score, sure) }
            case .phrase(let phrase): DispatchQueue.main.async { self.onPhrase?(phrase) }
            case .level(let shown): DispatchQueue.main.async { self.onLevel?(shown) }
            }
        }
    }

    private func watch(_ level: Float, reached: Int) {
        guard var watching = voiceWatch else { return }
        let sure = watching.feed(mic: level, playback: playbackLevel?() ?? 0)
        roomFloor = watching.floor
        voiceWatch = sure ? nil : watching
        guard sure else { return }
        let lookback = watching.lookback
        // The detector's buffer holds far more than the lookback; forward(to:from:) keeps it inside what is held.
        let from = max(0, reached - Int(ArisVoicePrint.sampleRate * lookback))
        DispatchQueue.main.async { self.onVoiceStart?(from, lookback) }
    }
}
