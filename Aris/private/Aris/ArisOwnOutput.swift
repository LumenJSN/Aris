//
//  ArisOwnOutput.swift
//  Aris
//
//  Aris's voice through an output that has no input side. An AVAudioEngine that plays binds itself to the default
//  output and the default input together, so with Bluetooth headphones as both, each sentence Aris said opened the
//  headset's microphone and dropped it from music to call quality (ArisMicPlan). Here the engine is taken off the
//  hardware (manual rendering: it only mixes), and one output-only audio unit on the default output pulls what the
//  engine mixed. Nothing of any microphone is opened, so the headset stays in music mode while Aris talks.
//  The player, its taps and its buffers' completions work as before: only where the sound leaves the engine changed.
//

import AudioToolbox
import AVFoundation

final class ArisOwnOutput {
    /// What the engine mixes to and the unit takes: 48 kHz stereo floats (the unit converts to the device's own rate).
    static let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
    /// The most frames one pull may ask for.
    static let mostFrames: AVAudioFrameCount = 4_096

    /// What the unit's callback holds: the engine's own render block, taken once (never looked up while rendering).
    final class Source {
        let block: AVAudioEngineManualRenderingBlock
        init(_ block: @escaping AVAudioEngineManualRenderingBlock) { self.block = block }
    }

    private var unit: AudioUnit?
    private var source: Unmanaged<Source>?

    var isRunning: Bool { unit != nil }

    /// Takes a stopped `engine` off the hardware, so it only mixes. Call before its mixer is connected.
    static func detach(_ engine: AVAudioEngine) throws {
        guard !engine.isInManualRenderingMode else { return }
        try engine.enableManualRenderingMode(.realtime, format: format, maximumFrameCount: mostFrames)
    }

    /// Gives a stopped `engine` back its own hardware output.
    static func attach(_ engine: AVAudioEngine) {
        if engine.isInManualRenderingMode { engine.disableManualRenderingMode() }
    }

    /// Fills `data` with the next `frames` the engine mixed; silence when it has nothing or can't render.
    static func pull(_ source: Source, frames: UInt32, into data: UnsafeMutablePointer<AudioBufferList>) {
        var status = noErr
        guard source.block(frames, data, &status) != .success else { return }
        for buffer in UnsafeMutableAudioBufferListPointer(data) {
            if let bytes = buffer.mData { memset(bytes, 0, Int(buffer.mDataByteSize)) }
        }
    }

    private static let render: AURenderCallback = { context, _, _, _, frames, data in
        guard let data else { return noErr }
        ArisOwnOutput.pull(Unmanaged<Source>.fromOpaque(context).takeUnretainedValue(), frames: frames, into: data)
        return noErr
    }

    /// Starts the engine (already detached and connected) and the unit that plays what it mixes.
    func start(_ engine: AVAudioEngine) throws {
        stopUnit()
        try engine.start()
        var description = AudioComponentDescription(componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_DefaultOutput,
                                                    componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        guard let component = AudioComponentFindNext(nil, &description) else { throw Failure(step: "find", status: -1) }
        var made: AudioUnit?
        try check(AudioComponentInstanceNew(component, &made), "make")
        guard let made else { throw Failure(step: "make", status: -1) }
        let held = Unmanaged.passRetained(Source(engine.manualRenderingBlock))
        do {
            var stream = Self.format.streamDescription.pointee
            try check(AudioUnitSetProperty(made, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &stream,
                                           UInt32(MemoryLayout<AudioStreamBasicDescription>.size)), "format")
            var most = Self.mostFrames
            try check(AudioUnitSetProperty(made, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &most,
                                           UInt32(MemoryLayout<UInt32>.size)), "slice")
            var callback = AURenderCallbackStruct(inputProc: Self.render, inputProcRefCon: held.toOpaque())
            try check(AudioUnitSetProperty(made, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback,
                                           UInt32(MemoryLayout<AURenderCallbackStruct>.size)), "callback")
            try check(AudioUnitInitialize(made), "initialize")
            try check(AudioOutputUnitStart(made), "start")
        } catch {
            AudioUnitUninitialize(made)
            AudioComponentInstanceDispose(made)
            held.release()
            engine.stop()
            throw error
        }
        unit = made
        source = held
    }

    /// Stops the unit, then the engine.
    func stop(_ engine: AVAudioEngine) {
        stopUnit()
        if engine.isRunning { engine.stop() }
    }

    private func stopUnit() {
        guard let unit else { return }
        AudioOutputUnitStop(unit)
        AudioUnitUninitialize(unit)
        AudioComponentInstanceDispose(unit)
        self.unit = nil
        source?.release()
        source = nil
    }

    deinit { stopUnit() }

    struct Failure: Error, CustomStringConvertible {
        let step: String
        let status: OSStatus
        var description: String { "own output: \(step) failed (\(status))" }
    }

    private func check(_ status: OSStatus, _ step: String) throws {
        if status != noErr { throw Failure(step: step, status: status) }
    }
}
