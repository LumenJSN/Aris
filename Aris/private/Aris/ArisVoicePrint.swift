//
//  ArisVoicePrint.swift
//  Aris
//
//  A trained "아리스", the way Siri's setup works: you say it a few times, the
//  Mac keeps those as voice prints (MFCC frames), and live speech is compared to
//  them with dynamic time warping. Comparing one short window when someone starts
//  talking costs next to nothing, so the full recognizer only wakes for a likely
//  match (and then double-checks the words). Prints come from your voice, so other
//  people and videos match worse, though this isn't real speaker verification.
//

import Accelerate
import Foundation

enum ArisVoicePrint {
    static let sampleRate: Double = 16_000
    /// 25 ms frames every 10 ms.
    static let frameLength = 400
    static let hop = 160
    private static let fftLength = 512
    private static let melBands = 26
    /// Cepstral coefficients 1...12 (0 is loudness, which shouldn't matter).
    private static let coefficients = 12
    /// A match may start this many frames into the window (the silence before the word).
    private static let startSlack = 25

    /// Voice-print frames for 16 kHz mono audio.
    static func features(_ samples: [Float]) -> [[Float]] {
        guard samples.count >= frameLength else { return [] }
        var emphasized = samples
        for index in stride(from: samples.count - 1, to: 0, by: -1) { emphasized[index] -= 0.97 * samples[index - 1] }
        let window = vDSP.window(ofType: Float.self, usingSequence: .hamming, count: frameLength, isHalfWindow: false)
        let setup = vDSP_create_fftsetup(vDSP_Length(log2(Double(fftLength))), FFTRadix(kFFTRadix2))!
        defer { vDSP_destroy_fftsetup(setup) }
        var frames: [[Float]] = []
        for start in stride(from: 0, through: samples.count - frameLength, by: hop) {
            var frame = [Float](repeating: 0, count: fftLength)
            vDSP.multiply(emphasized[start..<(start + frameLength)], window, result: &frame[0..<frameLength])
            let power = powerSpectrum(frame, setup: setup)
            let mel = filterbank.map { filter in max(1e-10, zip(filter, power).reduce(0) { $0 + $1.0 * $1.1 }) }.map(log)
            frames.append(dct(mel))
        }
        return frames
    }

    /// How far a window of live speech is from a print (lower is closer). The window must begin with the
    /// word (give or take its leading silence) but may go on after it, so "아리스, 내일…" still matches.
    static func distance(print: [[Float]], window: [[Float]]) -> Float {
        let rows = print.count, columns = window.count
        guard rows > 0, columns > 0 else { return .infinity }
        var previous = [Float](repeating: .infinity, count: columns)
        var current = previous
        for row in 0..<rows {
            for column in 0..<columns {
                let cost = euclidean(print[row], window[column])
                if row == 0 {
                    let fromLeft = column > 0 ? current[column - 1] : .infinity
                    current[column] = column < startSlack ? cost : cost + fromLeft
                } else {
                    let left = column > 0 ? current[column - 1] : .infinity
                    let diagonal = column > 0 ? previous[column - 1] : .infinity
                    current[column] = cost + min(previous[column], left, diagonal)
                }
            }
            swap(&previous, &current)
        }
        // The word ends somewhere between 0.6 and 1.6 times the print's length.
        let earliest = min(columns - 1, Int(Double(rows) * 0.6)), latest = min(columns - 1, Int(Double(rows) * 1.6) + startSlack)
        return (earliest...latest).map { previous[$0] / Float(rows + $0 + 1) }.min() ?? .infinity
    }

    /// The audio from the first to the last loud frame (the word without the silence around it).
    static func trimmed(_ samples: [Float]) -> [Float] {
        let energies = stride(from: 0, to: max(0, samples.count - frameLength), by: hop).map { start in
            rms(samples[start..<(start + frameLength)])
        }
        guard let loudest = energies.max(), loudest > 0 else { return samples }
        let floor = loudest * 0.1
        guard let first = energies.firstIndex(where: { $0 > floor }), let last = energies.lastIndex(where: { $0 > floor }) else { return samples }
        return Array(samples[(first * hop)..<min(samples.count, last * hop + frameLength)])
    }

    static func rms(_ samples: ArraySlice<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        return (samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)).squareRoot()
    }

    // MARK: - Pieces

    private static func euclidean(_ a: [Float], _ b: [Float]) -> Float {
        var sum: Float = 0
        for index in 0..<min(a.count, b.count) { let d = a[index] - b[index]; sum += d * d }
        return sum.squareRoot()
    }

    private static func powerSpectrum(_ frame: [Float], setup: FFTSetup) -> [Float] {
        var real = [Float](repeating: 0, count: fftLength / 2), imaginary = real
        var power = [Float](repeating: 0, count: fftLength / 2 + 1)
        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imaginaryPointer.baseAddress!)
                frame.withUnsafeBufferPointer { input in
                    input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftLength / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(fftLength / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, vDSP_Length(log2(Double(fftLength))), FFTDirection(FFT_FORWARD))
                // Packed format: DC in real[0], Nyquist in imaginary[0].
                power[0] = split.realp[0] * split.realp[0]
                power[fftLength / 2] = split.imagp[0] * split.imagp[0]
                for bin in 1..<(fftLength / 2) {
                    power[bin] = split.realp[bin] * split.realp[bin] + split.imagp[bin] * split.imagp[bin]
                }
            }
        }
        return power
    }

    /// Triangular mel filters over the 257 power bins, 0 Hz to 8 kHz.
    private static let filterbank: [[Float]] = {
        func mel(_ hz: Double) -> Double { 2595 * log10(1 + hz / 700) }
        func hz(_ mel: Double) -> Double { 700 * (pow(10, mel / 2595) - 1) }
        let bins = fftLength / 2 + 1
        let edges = (0...(melBands + 1)).map { hz(mel(0) + (mel(sampleRate / 2) - mel(0)) * Double($0) / Double(melBands + 1)) }
            .map { $0 / (sampleRate / 2) * Double(bins - 1) }
        return (0..<melBands).map { band in
            (0..<bins).map { bin in
                let x = Double(bin), low = edges[band], peak = edges[band + 1], high = edges[band + 2]
                if x <= low || x >= high { return 0 }
                return Float(x < peak ? (x - low) / (peak - low) : (high - x) / (high - peak))
            }
        }
    }()

    private static func dct(_ values: [Float]) -> [Float] {
        let count = Float(values.count)
        return (1...coefficients).map { k in
            values.enumerated().reduce(0) { sum, item in
                sum + item.element * cos(Float.pi * Float(k) * (Float(item.offset) + 0.5) / count)
            }
        }
    }
}

/// The trained wake word: your recordings' prints and how close live speech must come.
struct ArisWakeModel: Codable, Equatable {
    let prints: [[[Float]]]
    /// Closer than this: worth asking the recognizer.
    let threshold: Float
    /// Closer than this: about as close as your own recordings are to each other, so it's you calling and
    /// the notch opens at once. Between this and `threshold` the recognizer must hear the name first
    /// (it often skips a lone short word, so it can't be the only judge).
    var sure: Float { threshold * 0.6 }

    /// How many times you say it in training.
    static let recordingsNeeded = 5

    /// Each print is compared with the others; live speech may be a bit further off than the furthest pair.
    static func trained(from recordings: [[Float]]) -> ArisWakeModel? {
        let prints = recordings.map { ArisVoicePrint.features(ArisVoicePrint.trimmed($0)) }.filter { $0.count >= 20 }
        guard prints.count >= 3 else { return nil }
        let spread = prints.indices.map { index in
            prints.indices.filter { $0 != index }.map { ArisVoicePrint.distance(print: prints[index], window: prints[$0]) }.min() ?? 0
        }
        // Room to spare: a phrase said in one breath ("아리스, 내일…") runs the short word into the next
        // (about 2.4x further in tests, as far as "아이스"), and the recognizer double-checks every match.
        let widest = spread.max() ?? 0
        return ArisWakeModel(prints: prints, threshold: widest * 2.5)
    }

    /// The closest print's distance to this window of speech.
    func score(_ window: [[Float]]) -> Float {
        prints.map { ArisVoicePrint.distance(print: $0, window: window) }.min() ?? .infinity
    }

    /// The longest print, in samples (how much speech to collect before comparing).
    var longestPrintSamples: Int {
        (prints.map(\.count).max() ?? 0) * ArisVoicePrint.hop + ArisVoicePrint.frameLength
    }
}
