//
//  ArisVoiceProcessingHardware.swift
//  Aris
//
//  The real AVFoundation side of the duplex engine (ArisDuplexHardware). Decisions, and the documentation they rest on
//  (AVFAudio's AVAudioIONode.h in the macOS 27.2 SDK, AVAudioEngine.h, and the developer forum threads noted):
//  - Voice processing is switched on with `setVoiceProcessingEnabled(true)` on the input node of a fresh, stopped
//    engine, before anything is connected or tapped: "Voice processing can only be enabled or disabled when the engine
//    is in a stopped state", and "Enabling this mode on either of the IO nodes automatically enables it on the other",
//    so the output node is in the same IO unit and Aris's voice, played there, is the canceller's reference ("taking
//    out any of the audio that is played from the device"). Both nodes are checked to report it on; if not, the start
//    throws and the old path takes over (ArisDuplexLifetime.markFailed).
//  - The format change it forces: once on, the input node's output format can carry several channels at another rate
//    (forum 710151: 1 ch 44.1 kHz becomes "3 ch, 44100 Hz, Float32, deinterleaved"; others report 7 ch at 96 kHz). The
//    format is read after switching it on, the tap takes the node's own format (format nil: a mismatched format raises
//    an Objective-C exception Swift can't catch), and only channel 0, the processed uplink, is used: mixing the
//    channels down would add the unprocessed ones back, echo and all. Then 16 kHz mono, as every consumer wants.
//    The log line names the format the Mac gave, so a wrong channel shows up there.
//  - `isVoiceProcessingBypassed` is set false (bypass "all processing for microphone uplink": no cancelling at all).
//  - `isVoiceProcessingAGCEnabled` is set false ("Enabled by default"): the wake word's loudness gates, the voice watch
//    and the trained voice print are tuned on the raw microphone's level; a gain that moves under them would move every
//    threshold. (An Apple engineer, forum 733733: "A slight gain change is expected when enabling voice processing".)
//  - `voiceProcessingOtherAudioDuckingConfiguration` (macOS 14+, the deployment target) is set to advanced ducking off
//    and level `.min`: "If not set, the default ... ducking level set to ...Default", which turns other apps' sound
//    well down for as long as the engine runs. `.min` is the least ducking the API offers; there is no "none". The user's
//    rule is that music never cuts out unless Aris was called, so how this sounds is the first thing to judge by ear.
//  - Devices: voice processing joins the default input and the default output into an aggregate of its own
//    ("AUVPAggregate ... couldn't create the aggregate device (err=-10876)" when it can't, forum 128518). So the input
//    is not pinned here: ArisDuplexRoute only lets the engine run when the microphone Aris would pin is the default
//    input, never on an aggregate, virtual or Continuity device, and never with headphones out (no echo to cancel, and
//    voice processing stays away from Bluetooth headsets). A failed join throws from start(); the old path takes over.
//  - Configuration changes stop the engine ("the engine stops itself ... and issues this notification"; "the engine
//    must not be deallocated from within the client's notification handler"): the handler only reports; the owner's
//    queue rebuilds a fresh engine, and the old one is retired (ArisAudio.retire), never freed at once.
//  - Aris's voice: one player into the main mixer at a fixed 24 kHz mono (ElevenLabs' own rate); the system voice's
//    buffers are converted to it, one converter per source format so its state carries across buffers, instead of
//    reconnecting the player while the engine runs.
//

import AudioToolbox
import AVFoundation

final class ArisVoiceProcessingHardware: ArisDuplexHardware, @unchecked Sendable {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static let voiceFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000, channels: 1, interleaved: false)!
    private static let streamFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: ArisAudioFanout.sampleRate,
                                                    channels: 1, interleaved: false)!

    private let lock = NSLock()
    // Under `lock`:
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var observer: NSObjectProtocol?
    private var voiceConverters: [AVAudioFormat: AVAudioConverter] = [:]
    private var configurationHandler: (@Sendable () -> Void)?
    private var levelHandler: (@Sendable (Float, Float) -> Void)?

    var onConfigurationChange: (@Sendable () -> Void)? {
        get { lock.withLock { configurationHandler } }
        set { lock.withLock { configurationHandler = newValue } }
    }

    var onVoiceLevel: (@Sendable (Float, Float) -> Void)? {
        get { lock.withLock { levelHandler } }
        set { lock.withLock { levelHandler = newValue } }
    }

    var isRunning: Bool { lock.withLock { engine?.isRunning ?? false } }

    func start(frames: @escaping @Sendable ([Float]) -> Void) throws -> String {
        stop()
        let engine = AVAudioEngine()
        let mic = engine.inputNode
        // Stopped and unconnected: the only moment voice processing may be switched on.
        try mic.setVoiceProcessingEnabled(true)
        guard mic.isVoiceProcessingEnabled, engine.outputNode.isVoiceProcessingEnabled else {
            throw Failure(description: "voice processing didn't come on for both nodes")
        }
        mic.isVoiceProcessingBypassed = false
        mic.isVoiceProcessingAGCEnabled = false
        mic.voiceProcessingOtherAudioDuckingConfiguration = AVAudioVoiceProcessingOtherAudioDuckingConfiguration(
            enableAdvancedDucking: false, duckingLevel: .min)
        let processed = mic.outputFormat(forBus: 0)
        guard processed.sampleRate > 0, processed.channelCount > 0 else {
            throw Failure(description: "no input after voice processing came on (\(processed))")
        }
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: Self.voiceFormat)
        let tap = ArisFirstChannelTap(to: Self.streamFormat, frames: frames)
        mic.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in tap.take(buffer) }
        player.installTap(onBus: 0, bufferSize: 1024, format: Self.voiceFormat) { [weak self] buffer, _ in
            guard let report = self?.onVoiceLevel else { return }
            report(ArisAudio.level(of: buffer), ArisPlaybackMeter.rms(of: buffer))
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            mic.removeTap(onBus: 0)
            player.removeTap(onBus: 0)
            ArisAudio.retire(engine)
            throw error
        }
        // Only reports: the engine must not be torn down from inside the notification's handler.
        let observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                                                              queue: nil) { [weak self] _ in self?.onConfigurationChange?() }
        lock.withLock {
            self.engine = engine
            self.player = player
            self.observer = observer
            voiceConverters = [:]
        }
        return "voice processing on, \(processed.channelCount) ch at \(Int(processed.sampleRate)) Hz (channel 0 used), AGC off, other audio ducked at the minimum"
    }

    func stop() {
        let (engine, player, observer) = lock.withLock { () -> (AVAudioEngine?, AVAudioPlayerNode?, NSObjectProtocol?) in
            defer { self.engine = nil; self.player = nil; self.observer = nil; voiceConverters = [:] }
            return (self.engine, self.player, self.observer)
        }
        if let observer { NotificationCenter.default.removeObserver(observer) }
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        player?.removeTap(onBus: 0)
        player?.stop()
        engine.stop()
        // Off again on the stopped engine, so its aggregate is let go now rather than whenever the engine is freed.
        try? engine.inputNode.setVoiceProcessingEnabled(false)
        ArisAudio.retire(engine)
    }

    func play(_ buffer: AVAudioPCMBuffer, done: @escaping @Sendable () -> Void) -> Bool {
        guard let (engine, player) = lock.withLock({ () -> (AVAudioEngine, AVAudioPlayerNode)? in
            guard let engine, let player else { return nil }
            return (engine, player)
        }), engine.isRunning, let converted = voiceBuffer(buffer) else { return false }
        player.scheduleBuffer(converted) { done() }
        if !player.isPlaying { player.play() }
        return true
    }

    func stopVoice() { lock.withLock { player }?.stop() }

    func setVoiceVolume(_ volume: Float) { lock.withLock { player }?.volume = volume }

    /// `buffer` in the player's fixed format.
    private func voiceBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let target = Self.voiceFormat
        if buffer.format == target { return buffer }
        let converter = lock.withLock { () -> AVAudioConverter? in
            if let known = voiceConverters[buffer.format] { return known }
            let made = AVAudioConverter(from: buffer.format, to: target)
            voiceConverters[buffer.format] = made
            return made
        }
        guard let converter else { return nil }
        return ArisAudio.convert(buffer, with: converter, to: target)
    }
}

/// The input tap's work: channel 0 of the processed format, at 16 kHz mono. The converter is made from the first
/// buffer's own format (the tap takes the node's format as it is) and again if it ever changes.
private final class ArisFirstChannelTap: @unchecked Sendable {
    private let target: AVAudioFormat
    private let frames: @Sendable ([Float]) -> Void
    // On the tap's thread only:
    private var mono: AVAudioFormat?
    private var converter: AVAudioConverter?

    init(to target: AVAudioFormat, frames: @escaping @Sendable ([Float]) -> Void) {
        self.target = target
        self.frames = frames
    }

    func take(_ buffer: AVAudioPCMBuffer) {
        guard let first = firstChannel(of: buffer), let converter = converterFor(first.format),
              let converted = ArisAudio.convert(first, with: converter, to: target),
              let channel = converted.floatChannelData?[0] else { return }
        frames(Array(UnsafeBufferPointer(start: channel, count: Int(converted.frameLength))))
    }

    private func converterFor(_ format: AVAudioFormat) -> AVAudioConverter? {
        if let converter, mono == format { return converter }
        guard let made = AVAudioConverter(from: format, to: target) else { return nil }
        mono = format
        converter = made
        return made
    }

    /// Channel 0 alone, as a mono Float32 buffer at the buffer's rate (interleaved or not).
    private func firstChannel(of buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let frames = Int(buffer.frameLength)
        guard frames > 0, let source = buffer.floatChannelData?[0],
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: buffer.format.sampleRate, channels: 1, interleaved: false),
              let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let destination = out.floatChannelData?[0] else { return nil }
        let stride = buffer.stride
        for i in 0..<frames { destination[i] = source[i * stride] }
        out.frameLength = AVAudioFrameCount(frames)
        return out
    }
}
