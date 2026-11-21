//
//  ArisRecognizerFeed.swift
//  Aris
//
//  The first word on the talk key (target 3). The microphone used to open only once the speech engine had started
//  (SpeechAnalyzer can take a few hundred ms), so what was said right after the press was lost. Now the microphone
//  opens first: its buffers go to the recording, the level and Scribe at once, and to the recogniser as soon as it is
//  ready, those held meanwhile first, in order. The wake word and a conversation's turn already hand over the
//  detector's audio and need none of this. AVFoundation only (tested).
//

import AVFoundation

/// Where the microphone's buffers go for the recogniser: held until `attach`, then converted and passed on. Called
/// on the audio thread (`take`) and the main one (`attach`).
final class ArisRecognizerFeed: @unchecked Sendable {
    /// At most this much is held before the recogniser is ready (it starts in well under a second).
    static let heldLimit: Double = 5

    private let lock = NSLock()
    private var input: ArisRecognizerInput?
    private var held: [AVAudioPCMBuffer] = []
    private var heldSeconds: Double = 0
    private var converter: AVAudioConverter?
    /// Buffers handed on since `attach` (held ones included), for the tests and the log.
    private(set) var passed = 0

    init(input: ArisRecognizerInput? = nil) {
        self.input = input
    }

    /// One buffer in the microphone's format.
    func take(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            guard let input else {
                guard heldSeconds < Self.heldLimit, let copy = Self.copy(buffer) else { return }
                held.append(copy)
                heldSeconds += Double(buffer.frameLength) / buffer.format.sampleRate
                return
            }
            pass(buffer, to: input)
        }
    }

    /// The recogniser is ready: what was held goes first, then everything live.
    func attach(_ input: ArisRecognizerInput) {
        lock.withLock {
            self.input = input
            let waiting = held
            held = []
            heldSeconds = 0
            for buffer in waiting { pass(buffer, to: input) }
        }
    }

    private func pass(_ buffer: AVAudioPCMBuffer, to input: ArisRecognizerInput) {
        if buffer.format == input.format {
            passed += 1
            return input.append(buffer)
        }
        // One converter per microphone format: a format change (ArisMicRestart) builds a new one.
        if converter?.inputFormat != buffer.format { converter = AVAudioConverter(from: buffer.format, to: input.format) }
        guard let converter, let converted = Self.convert(buffer, with: converter, to: input.format) else { return }
        passed += 1
        input.append(converted)
    }

    /// One buffer through `converter` (as ArisAudio.convert does; this file stands alone so the tests compile it).
    private static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate) + 1
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

    /// The engine may reuse a tap's buffer: one that is held is copied.
    private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return nil }
        copy.frameLength = buffer.frameLength
        let frames = Int(buffer.frameLength), channels = Int(buffer.format.channelCount)
        if let from = buffer.floatChannelData, let to = copy.floatChannelData {
            for channel in 0..<(buffer.format.isInterleaved ? 1 : channels) {
                to[channel].update(from: from[channel], count: frames * (buffer.format.isInterleaved ? channels : 1))
            }
        } else if let from = buffer.int16ChannelData, let to = copy.int16ChannelData {
            for channel in 0..<(buffer.format.isInterleaved ? 1 : channels) {
                to[channel].update(from: from[channel], count: frames * (buffer.format.isInterleaved ? channels : 1))
            }
        } else {
            return nil
        }
        return copy
    }
}
