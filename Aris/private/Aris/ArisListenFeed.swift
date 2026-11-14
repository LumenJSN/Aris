//
//  ArisListenFeed.swift
//  Aris
//
//  Listening without a microphone, for tests (a VM has neither a microphone nor sound): with the hidden setting
//  arisListenFeedFile naming an audio file (`defaults write com.lumenjsn.aris arisListenFeedFile /path/clip.wav`, no
//  UI), a listener that would open the microphone hears that file instead, at the pace it was spoken, then silence
//  until the turn ends (so a hands-free turn's pause is heard as one). Read at every listen: a new file needs no
//  restart, and deleting the setting gives the microphone back. The clips are made the wake bench's way, offline with
//  `say -o … --data-format=LEI16@16000` (tests/wake-bench/make-audio.py). AVFoundation only (tested).
//

import AVFoundation
import Foundation

final class ArisListenFeed: @unchecked Sendable {
    static let fileKey = "arisListenFeedFile"
    /// Each chunk handed on, as a microphone's tap would (100 ms).
    static let chunkSeconds = 0.1
    static let sampleRate = 16_000.0

    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: ArisListenFeed.sampleRate, channels: 1, interleaved: false)!
    let url: URL
    private let samples: [Float]
    private let lock = NSLock()
    private var position = 0
    private var timer: DispatchSourceTimer?

    /// The file the setting names, when there is one.
    static func configured(defaults: UserDefaults = .standard) -> URL? {
        guard let path = defaults.string(forKey: fileKey), !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    init(url: URL) throws {
        self.url = url
        samples = try Self.read(url, to: format)
    }

    /// Seconds of the file's own audio (silence follows).
    var duration: Double { Double(samples.count) / Self.sampleRate }

    /// The next `frames` samples: the file's, then silence.
    func next(frames: Int) -> AVAudioPCMBuffer? {
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)
        let start: Int = lock.withLock {
            let start = position
            position += frames
            return start
        }
        for index in 0..<frames {
            let at = start + index
            channel[index] = at < samples.count ? samples[at] : 0
        }
        return buffer
    }

    /// Hands a chunk to `deliver` every 100 ms on `queue` until stop().
    func start(on queue: DispatchQueue, deliver: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        let frames = Int(Self.sampleRate * Self.chunkSeconds)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.chunkSeconds, repeating: Self.chunkSeconds, leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in
            guard let buffer = self?.next(frames: frames) else { return }
            deliver(buffer)
        }
        lock.withLock { self.timer = timer }
        timer.resume()
    }

    func stop() {
        let timer: DispatchSourceTimer? = lock.withLock {
            let timer = self.timer
            self.timer = nil
            return timer
        }
        timer?.cancel()
    }

    /// The whole file as 16 kHz mono.
    private static func read(_ url: URL, to format: AVAudioFormat) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let source = file.processingFormat
        guard file.length > 0, let whole = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw ArisFailure(message: "The test audio file \(url.lastPathComponent) is empty.")
        }
        try file.read(into: whole)
        guard let converter = AVAudioConverter(from: source, to: format) else {
            throw ArisFailure(message: "The test audio file \(url.lastPathComponent) can't be converted.")
        }
        let capacity = AVAudioFrameCount(Double(whole.frameLength) * format.sampleRate / source.sampleRate) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return [] }
        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed {
                status.pointee = .endOfStream
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return whole
        }
        if let error { throw error }
        guard let channel = out.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
    }
}
