//
//  ArisWakeRecorderMic.swift
//  Aris
//
//  The microphone for 호출어 녹음, open only while its sheet records: pinned the way the name's training is (the
//  Mac's own microphone unless that is all there is, ArisMicPlan `.setup`), or for the AirPods group to the headset's.
//  It hands on every 16 kHz chunk and its loudness on the main thread; ArisWakeRecorderModel cuts the takes out of
//  them. It records nothing itself and keeps nothing.
//

import AVFoundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "wake-record")

final class ArisWakeRecorderMic: @unchecked Sendable {
    struct NoHeadset: Error {}

    /// Every chunk (16 kHz mono) and its loudness 0…1 (main thread).
    var onAudio: (([Float], Float) -> Void)?
    /// The microphone changed under it (main thread).
    var onInterrupted: (() -> Void)?
    /// The kind of device it opened (ArisAudioDevice.Transport's raw value), for the manifest.
    private(set) var device: String?
    private var engine: AVAudioEngine?
    private var configuration: NSObjectProtocol?

    /// Opens the microphone; `headset`: the AirPods' (throws NoHeadset when none is connected).
    func start(headset: Bool) throws {
        let engine = AVAudioEngine()
        let pinned = try headset ? ArisMicDevices.pinHeadset(engine) : ArisMicDevices.pin(engine, for: .setup)
        if headset, pinned == nil { throw NoHeadset() }
        device = pinned?.transport.rawValue
        let mic = engine.inputNode
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: ArisVoicePrint.sampleRate, channels: 1, interleaved: false)!
        guard let micFormat = ArisAudio.settledTapFormat(of: mic), let converter = AVAudioConverter(from: micFormat, to: format) else {
            throw ArisFailure(message: "Couldn't read the microphone.")
        }
        mic.installTap(onBus: 0, bufferSize: 1600, format: micFormat) { [weak self] buffer, _ in
            guard let converted = ArisAudio.convert(buffer, with: converter, to: format), let channel = converted.floatChannelData?[0] else { return }
            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(converted.frameLength)))
            let level = min(1, ArisVoicePrint.rms(samples[...]) * 8)
            DispatchQueue.main.async { self?.onAudio?(samples, level) }
        }
        engine.prepare()
        try engine.start()
        self.engine = engine
        configuration = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                                                               queue: .main) { [weak self] _ in self?.onInterrupted?() }
        log.notice("recording the wake word's takes (\(self.device ?? "unknown", privacy: .public))")
    }

    func stop() {
        guard let engine else { return }
        self.engine = nil
        if let configuration { NotificationCenter.default.removeObserver(configuration) }
        configuration = nil
        let device = self.device
        ArisAudio.microphoneQueue.async {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            ArisAudio.retire(engine)
            ArisMicDevices.noteClosed(.setup, transport: device.flatMap(ArisAudioDevice.Transport.init(rawValue:)))
        }
    }
}
