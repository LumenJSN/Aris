//
//  ArisOnboardingAudio.swift
//  Aris
//
//  The onboarding's sound (mockups/onboarding2/js/audio.js), on AVAudioEngine and one clock with the picture: the
//  media clock (CACurrentMediaTime, mach host time underneath). Each cue is scheduled at host time so its own
//  transient or loudest moment (ArisOnboardingAudioPlan, measured from the decoded file) lands on the beat, less the
//  output's latency. Voice lines play now and report when each sentence starts, so the captions trail the voice; a
//  language with no recording speaks through AVSpeechSynthesizer in that language, its captions timed by the
//  synthesizer's own callbacks. The bed loops on an equal-power crossfade, ducked under the voice.
//
//  Files: Resources/OnboardingAudio/{sfx,voice/<lang>}/*.mp3 (swap them there; HANDOFF.md has the licensing note).
//  It plays through the system's output device (and follows it when that changes), honours the onboarding's mute,
//  and never plays while Aris's microphone listens (it falls silent, and stays so, until the mic closes).
//

import AVFoundation
import Foundation
import QuartzCore
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "onboarding")

@MainActor
final class ArisOnboardingAudio: NSObject, AVSpeechSynthesizerDelegate {
    typealias Plan = ArisOnboardingAudioPlan

    enum Cue: String, CaseIterable { case swell, chime, whoosh, pop, check, resolve }
    enum Align { case hit, peak, start }

    /// Whether Aris's microphone is listening right now (the controller sets it).
    var micListening: () -> Bool = { false }

    private(set) var muted: Bool
    private var engine: AVAudioEngine?
    private var master: AVAudioMixerNode?
    private var cuePlayers: [AVAudioPlayerNode] = []
    private var nextCuePlayer = 0
    private var voicePlayer: AVAudioPlayerNode?
    private var ambientPlayer: AVAudioPlayerNode?
    private var ambientMixer: AVAudioMixerNode?
    private var cues: [Cue: (buffer: AVAudioPCMBuffer, meta: Plan.Meta)] = [:]
    private var voices: [String: (buffer: AVAudioPCMBuffer, envelope: [Float])] = [:]
    private var ambientLoop: AVAudioPCMBuffer?
    private var ambientOn = false
    private var configObserver: NSObjectProtocol?
    private var silenced = false

    /// The voice playing now: when it started (media seconds) and its 20 ms envelope, for the notch's bars.
    private(set) var speaking: (start: Double, duration: Double, envelope: [Float])?
    private let synthesizer = AVSpeechSynthesizer()
    private var synthSentences: [String] = []
    private var synthStart = 0.0
    private var synthDone: ((Double) -> Void)?
    /// Sentence starts reported by the synthesizer (media seconds), for the captions.
    private(set) var synthStarts: [Double] = []

    init(muted: Bool) {
        self.muted = muted
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Clock

    /// The shared clock (seconds).
    static func now() -> Double { CACurrentMediaTime() }

    // MARK: - Setup

    /// Builds the engine and decodes every clip. Missing files stay silent.
    func start() {
        guard engine == nil else { return }
        let engine = AVAudioEngine(), master = AVAudioMixerNode(), ambientMixer = AVAudioMixerNode()
        engine.attach(master)
        engine.attach(ambientMixer)
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return log.notice("onboarding audio: no output device") }
        engine.connect(master, to: engine.mainMixerNode, format: nil)
        engine.connect(ambientMixer, to: master, format: nil)
        ambientMixer.outputVolume = 0
        for cue in Cue.allCases { load(cue) }
        load(ambient: "ambient")
        let stereo = Self.format
        for _ in 0..<4 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: master, format: stereo)
            player.volume = Plan.cueGain
            cuePlayers.append(player)
        }
        let voice = AVAudioPlayerNode(), ambient = AVAudioPlayerNode()
        engine.attach(voice)
        engine.attach(ambient)
        engine.connect(voice, to: master, format: stereo)
        engine.connect(ambient, to: ambientMixer, format: stereo)
        self.engine = engine
        self.master = master
        self.ambientMixer = ambientMixer
        voicePlayer = voice
        ambientPlayer = ambient
        applyVolume()
        run()
        // The output device changed (headphones, a display's speakers): the engine stops; start it again on the new one.
        configObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.run() }
        }
    }

    private func run() {
        guard let engine, !engine.isRunning else { return }
        do {
            try engine.start()
            (cuePlayers + [voicePlayer, ambientPlayer].compactMap { $0 }).forEach { $0.play() }
            // A stopped engine drops what was scheduled: the bed goes back on.
            ambientScheduled = false
            if ambientOn { scheduleAmbient() }
        } catch {
            log.error("onboarding audio: the engine wouldn't start: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        synthDone = nil
        speaking = nil
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        engine?.stop()
        engine = nil
        ramp?.invalidate()
        ramp = nil
        cuePlayers = []
        voicePlayer = nil
        ambientPlayer = nil
        ambientMixer = nil
        master = nil
        ambientOn = false
        ambientScheduled = false
    }

    private static func url(_ path: String) -> URL? {
        let p = path as NSString
        return Bundle.main.url(forResource: p.lastPathComponent, withExtension: "mp3", subdirectory: p.deletingLastPathComponent)
    }

    /// Every clip is played in one format (44.1 kHz stereo float), whatever the file is (the voice is mono), so a
    /// player's connection always matches and a swapped file can't break it.
    static let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!

    private static func decode(_ url: URL) -> AVAudioPCMBuffer? {
        do {
            let file = try AVAudioFile(forReading: url)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { return nil }
            try file.read(into: buffer)
            return convert(buffer)
        } catch {
            log.error("onboarding audio: can't decode \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else { return nil }
        let ratio = format.sampleRate / buffer.format.sampleRate
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024) else { return nil }
        nonisolated(unsafe) var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        if let error { log.error("onboarding audio: can't convert: \(error.localizedDescription, privacy: .public)") }
        return error == nil ? out : nil
    }

    private static func mono(_ buffer: AVAudioPCMBuffer) -> [Float] {
        guard let data = buffer.floatChannelData else { return [] }
        let n = Int(buffer.frameLength), channels = Int(buffer.format.channelCount)
        var out = [Float](repeating: 0, count: n)
        for c in 0..<channels { for i in 0..<n { out[i] += data[c][i] } }
        if channels > 1 { for i in 0..<n { out[i] /= Float(channels) } }
        return out
    }

    private func load(_ cue: Cue) {
        guard let url = Self.url(ArisOnboardingLanguage.cueFile(cue.rawValue)), let buffer = Self.decode(url) else { return }
        cues[cue] = (buffer, Plan.analyse(Self.mono(buffer), rate: buffer.format.sampleRate))
    }

    /// The bed's active region with its last 2 s crossfaded into its first, so it loops without a seam.
    private func load(ambient name: String) {
        guard let url = Self.url(ArisOnboardingLanguage.cueFile(name)), let buffer = Self.decode(url),
              let data = buffer.floatChannelData else { return }
        let rate = buffer.format.sampleRate, meta = Plan.analyse(Self.mono(buffer), rate: rate)
        let from = Int(meta.from * rate), to = min(Int(buffer.frameLength), Int(meta.to * rate))
        let fade = Int(Plan.loopFade * rate), length = to - from - fade
        guard length > fade, let loop = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: AVAudioFrameCount(length)),
              let out = loop.floatChannelData else { return }
        loop.frameLength = AVAudioFrameCount(length)
        let curve = Plan.loopCrossfade(count: length, fade: fade)
        for c in 0..<Int(buffer.format.channelCount) {
            for i in 0..<length {
                var v = data[c][from + i]
                if i < curve.count { v = v * curve[i].rise + data[c][from + length + i] * curve[i].fall }
                out[c][i] = v
            }
        }
        ambientLoop = loop
    }

    private func voice(_ name: String, language: String) -> (buffer: AVAudioPCMBuffer, envelope: [Float])? {
        let key = "\(language)/\(name)"
        if let cached = voices[key] { return cached }
        guard let url = Self.url(ArisOnboardingLanguage.voiceFile(name, language: language)), let buffer = Self.decode(url) else { return nil }
        let entry = (buffer, Plan.envelope(Self.mono(buffer), rate: buffer.format.sampleRate, window: 0.02))
        voices[key] = entry
        return entry
    }

    // MARK: - Mute and the mic

    var audible: Bool { Plan.audible(muted: muted, micListening: micListening()) }

    func setMuted(_ on: Bool) {
        muted = on
        applyVolume()
    }

    /// Called whenever the mic may have opened or closed: silent at once while it listens.
    func micChanged() {
        let wasSilenced = silenced
        silenced = micListening()
        if silenced && !wasSilenced {
            voicePlayer?.stop()
            voicePlayer?.play()
            synthesizer.stopSpeaking(at: .immediate)
        }
        applyVolume()
    }

    private func applyVolume() {
        master?.outputVolume = audible ? 1 : 0
        updateAmbient()
    }

    // MARK: - Cues

    /// Schedules `cue` so its hit / peak / start sounds at `at` (media seconds). Too late: dropped.
    func cue(_ cue: Cue, at: Double, align: Align = .hit, length: Double = 0, fade: Double = 0.06) {
        guard audible, let engine, engine.isRunning, let (buffer, meta) = cues[cue], !cuePlayers.isEmpty else { return }
        let offset = align == .peak ? meta.peak : align == .start ? meta.from : meta.hit
        let latency = engine.outputNode.presentationLatency
        guard let start = Plan.cueStart(at: at - latency, offset: offset, now: Self.now() + 0.01) else { return }
        let rate = buffer.format.sampleRate
        let skipFrames = Int(start.skip * rate)
        let total = length > 0 ? min(Int(length * rate), Int(buffer.frameLength) - skipFrames) : Int(buffer.frameLength) - skipFrames
        guard total > 0, let slice = Self.slice(buffer, from: skipFrames, count: total, fadeOut: length > 0 ? Int(fade * rate) : 0) else { return }
        let player = cuePlayers[nextCuePlayer % cuePlayers.count]
        nextCuePlayer += 1
        player.scheduleBuffer(slice, at: AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: start.when)), options: [])
    }

    private static func slice(_ buffer: AVAudioPCMBuffer, from: Int, count: Int, fadeOut: Int) -> AVAudioPCMBuffer? {
        guard let out = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: AVAudioFrameCount(count)),
              let src = buffer.floatChannelData, let dst = out.floatChannelData else { return nil }
        out.frameLength = AVAudioFrameCount(count)
        for c in 0..<Int(buffer.format.channelCount) {
            for i in 0..<count {
                let tail = count - i
                let gain: Float = fadeOut > 0 && tail < fadeOut ? Float(tail) / Float(fadeOut) : 1
                dst[c][i] = src[c][from + i] * gain
            }
        }
        return out
    }

    // MARK: - The bed

    func ambient(_ on: Bool, fade seconds: Double) {
        ambientOn = on
        if on { scheduleAmbient() }
        rampAmbient(over: seconds)
    }

    private func scheduleAmbient() {
        guard !ambientScheduled, let loop = ambientLoop, let ambientPlayer, engine?.isRunning == true else { return }
        ambientPlayer.scheduleBuffer(loop, at: nil, options: [.loops])
        ambientScheduled = true
    }

    private var ambientScheduled = false
    private var ramp: Timer?

    private func ambientTarget() -> Float {
        guard ambientOn, audible else { return 0 }
        return speaking != nil || synthesizer.isSpeaking ? Plan.ambientGain * Plan.duck : Plan.ambientGain
    }

    private func updateAmbient() { rampAmbient(over: 0.25) }

    /// A short linear ramp of the bed's level; the timer stops as soon as it arrives.
    private func rampAmbient(over seconds: Double) {
        guard let mixer = ambientMixer else { return }
        let from = mixer.outputVolume, to = ambientTarget(), start = Self.now()
        ramp?.invalidate()
        guard abs(to - from) > 0.001, seconds > 0 else { mixer.outputVolume = to; return }
        ramp = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                let p = Float(min(1, (Self.now() - start) / seconds))
                mixer.outputVolume = from + (to - from) * p
                if p >= 1 { self?.ramp?.invalidate(); self?.ramp = nil }
            }
        }
    }

    // MARK: - Voice

    struct Spoken {
        /// When the voice starts (media seconds), each sentence's start in it, and its length.
        var start: Double
        var starts: [Double]
        var duration: Double
        /// Timed by the synthesizer's callbacks (its starts arrive as it speaks).
        var synthesized: Bool
    }

    /// Plays a voice line now: the recording for `language`, else the system's voice in that language.
    func say(_ name: String, language: String, sentences: [String], done: @escaping (Double) -> Void) -> Spoken {
        ambientDuck()
        if let (buffer, envelope) = voice(name, language: language), let voicePlayer, engine?.isRunning == true, audible {
            let start = Self.now() + 0.06
            let duration = Double(buffer.frameLength) / buffer.format.sampleRate
            let runs = Plan.speechRuns(Self.mono(buffer), rate: buffer.format.sampleRate)
            let starts = Plan.sentenceStarts(runs: runs, duration: duration, sentences: sentences)
            let latency = engine?.outputNode.presentationLatency ?? 0
            voicePlayer.scheduleBuffer(buffer, at: AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: start - latency)), options: [.interrupts])
            speaking = (start, duration, envelope)
            finish(after: start + duration, done)
            return Spoken(start: start, starts: starts, duration: duration, synthesized: false)
        }
        if voice(name, language: language) != nil {
            // Recorded but silent (muted, or the mic is open): the captions keep the recording's own pacing.
            let (buffer, _) = voice(name, language: language)!
            let duration = Double(buffer.frameLength) / buffer.format.sampleRate
            let starts = Plan.sentenceStarts(runs: Plan.speechRuns(Self.mono(buffer), rate: buffer.format.sampleRate), duration: duration, sentences: sentences)
            let start = Self.now() + 0.06
            finish(after: start + duration, done)
            return Spoken(start: start, starts: starts, duration: duration, synthesized: false)
        }
        return synthesize(sentences, language: language, done: done)
    }

    private func finish(after end: Double, _ done: @escaping (Double) -> Void) {
        let delay = max(0, end - Self.now())
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self else { return }
            if let speaking = self.speaking, speaking.start + speaking.duration <= Self.now() + 0.02 { self.speaking = nil }
            self.updateAmbient()
            done(end)
        }
    }

    private func ambientDuck() { rampAmbient(over: 0.08) }

    /// No recording for this language: AVSpeechSynthesizer in the same language (never another language's voice);
    /// muted or while the mic listens it still runs, silently, so the captions keep their timing.
    private func synthesize(_ sentences: [String], language: String, done: @escaping (Double) -> Void) -> Spoken {
        synthesizer.stopSpeaking(at: .immediate)
        let text = sentences.joined(separator: " ")
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: ArisOnboardingLanguage.synthesizerVoice(for: language))
        utterance.volume = audible ? 1 : 0
        synthSentences = sentences
        synthStart = Self.now()
        synthStarts = [synthStart]
        synthDone = done
        synthesizer.speak(utterance)
        let estimate = ArisCaptions.estimated(sentences: sentences, start: synthStart)
        return Spoken(start: synthStart, starts: [0], duration: estimate.duration, synthesized: true)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString range: NSRange, utterance: AVSpeechUtterance) {
        MainActor.assumeIsolated {
            let index = ArisCaptions.sentence(containing: range.location, in: synthSentences)
            while synthStarts.count <= index { synthStarts.append(Self.now()) }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        MainActor.assumeIsolated { endSynth() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        MainActor.assumeIsolated { endSynth() }
    }

    private func endSynth() {
        let now = Self.now()
        while synthStarts.count < synthSentences.count { synthStarts.append(now) }
        updateAmbient()
        let done = synthDone
        synthDone = nil
        done?(now)
    }

    func stopVoice() {
        voicePlayer?.stop()
        if engine?.isRunning == true { voicePlayer?.play() }
        speaking = nil
        synthDone = nil
        synthesizer.stopSpeaking(at: .immediate)
        updateAmbient()
    }

    /// The notch's five bars, 0…1, from the voice playing now (a paced stand-in while the synthesizer speaks).
    func levels(at now: Double) -> [Float] {
        if let speaking, now >= speaking.start, now <= speaking.start + speaking.duration {
            return Plan.barLevels(envelope: speaking.envelope, at: now - speaking.start, window: 0.02, bars: 5)
        }
        if synthesizer.isSpeaking {
            let k = now * 9
            return (0..<5).map { i in Float(0.35 + 0.35 * sin(k + Double(i) * 1.7) * sin(k * 0.37 + Double(i))) }
        }
        return Array(repeating: 0, count: 5)
    }
}
