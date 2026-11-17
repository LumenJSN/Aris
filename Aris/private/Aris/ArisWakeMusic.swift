//
//  ArisWakeMusic.swift
//  Aris
//
//  Is a wake candidate's sound music? Apple's built-in sound classifier (SoundAnalysis, SNClassifierIdentifier
//  .version1, on this Mac, nothing sent) reads the few seconds the wake detector already holds around the call: no new
//  microphone, no permission, and only around a candidate, never continuously (one read of 4 s is about 45 ms of CPU
//  on an M-series Mac, 2026-11-15). Music or singing there means the name may have come from a song, so a borderline
//  wake needs the name itself in Whisper's text (ArisWakeEvidence) and a near spelling never counts.
//  The labels are the classifier's own (`knownClassifications`, checked in the macOS 27 SDK): "music", "singing",
//  "choir_singing", "rapping", "yodeling". "humming" is left out (the user humming is still the user).
//

import AVFoundation
import Foundation
import SoundAnalysis

enum ArisWakeMusic {
    static let labels: Set<String> = ["music", "singing", "choir_singing", "rapping", "yodeling"]
    /// A window this sure of one of them is music. Speech alone peaked at 0.41 (singing) and noise at 0.35 (music) on
    /// the synthetic set; music, singing voices and speech over music read 0.5–0.94.
    static let sure: Double = 0.5
    /// Windows that must say so: two (of seven over 4 s), or every one of a shorter read.
    static let windowsNeeded = 2
    /// How much the classifier reads: the call, what came before it and what came after (the detector holds 6 s).
    static let seconds: Double = 4
    static let windowSeconds: Double = 1
    static let overlap: Double = 0.5

    /// One window's score: its surest music-like label.
    static func score(_ window: [String: Double]) -> Double {
        labels.map { window[$0] ?? 0 }.max() ?? 0
    }

    /// The classifier's windows say music: enough of them over the line.
    static func isMusic(_ windows: [[String: Double]]) -> Bool {
        guard !windows.isEmpty else { return false }
        let over = windows.filter { score($0) >= sure }.count
        return over >= min(windowsNeeded, windows.count)
    }

    /// The last `seconds` of what the detector holds.
    static func tail(_ samples: [Float], sampleRate: Double) -> [Float] {
        Array(samples.suffix(Int(sampleRate * seconds)))
    }

    /// Music in these samples (16 kHz mono). False when the classifier can't run: a read that fails decides nothing.
    /// Synchronous, about 45 ms for 4 s: call it off the main thread.
    static func heard(in samples: [Float], sampleRate: Double = ArisVoicePrint.sampleRate) -> Bool {
        guard let windows = classify(samples, sampleRate: sampleRate) else { return false }
        return isMusic(windows)
    }

    /// Each window's labels and confidences; nil when the classifier can't be made or the audio is too short.
    static func classify(_ samples: [Float], sampleRate: Double) -> [[String: Double]]? {
        guard samples.count >= Int(sampleRate * windowSeconds),
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let request = try? SNClassifySoundRequest(classifierIdentifier: .version1) else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData?[0].update(from: $0.baseAddress!, count: samples.count) }
        request.windowDuration = CMTime(seconds: windowSeconds, preferredTimescale: CMTimeScale(sampleRate))
        request.overlapFactor = overlap
        let analyzer = SNAudioStreamAnalyzer(format: format)
        let collector = Collector()
        guard (try? analyzer.add(request, withObserver: collector)) != nil else { return nil }
        analyzer.analyze(buffer, atAudioFramePosition: 0)
        analyzer.completeAnalysis()
        return collector.windows
    }

    /// The classifier's results, as they come (on the caller's thread, during analyze and completeAnalysis).
    private final class Collector: NSObject, SNResultsObserving {
        private(set) var windows: [[String: Double]] = []

        func request(_ request: SNRequest, didProduce result: SNResult) {
            guard let result = result as? SNClassificationResult else { return }
            windows.append(Dictionary(result.classifications.map { ($0.identifier, $0.confidence) }, uniquingKeysWith: max))
        }
    }
}
