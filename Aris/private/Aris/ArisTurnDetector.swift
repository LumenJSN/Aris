//
//  ArisTurnDetector.swift
//  Aris
//
//  Does your voice sound finished? Smart Turn v3.2 (pipecat, BSD-2-Clause, SmartTurn/SmartTurn-LICENSE.txt)
//  hears it in the audio itself: pitch, pace, a trailing "음…", in Korean too. It reads the turn's last 8 s and
//  takes ~4 ms. The CoreML conversion (aufklarer/Smart-Turn-v3.2-CoreML @75f0697) was checked against the
//  upstream ONNX on pipecat's Korean test clips: largest difference 0.002, 94 of 94 right with the silence in
//  front (the upstream example's silence-after scored 87%).
//

import CoreML
import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "turn")

final class ArisTurnDetector: @unchecked Sendable {
    static let shared = ArisTurnDetector()

    private let lock = NSLock()
    private var model: MLModel?
    private var loaded = false

    /// Loads the model ahead of the first pause (Aris started listening).
    func warm() {
        DispatchQueue.global(qos: .userInitiated).async { _ = self.loadedModel() }
    }

    /// The chance (0...1) that the turn in `samples` (16 kHz) has ended; nil when the model can't run.
    func score(_ samples: [Float]) -> Float? {
        guard let model = loadedModel(), !samples.isEmpty else { return nil }
        let window = ArisTalkKey.turnWindow(samples)
        do {
            let audio = try MLMultiArray(shape: [1, NSNumber(value: window.count)], dataType: .float32)
            window.withUnsafeBufferPointer { source in
                audio.dataPointer.assumingMemoryBound(to: Float.self).update(from: source.baseAddress!, count: window.count)
            }
            let output = try lock.withLock { try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["audio": audio])) }
            return output.featureValue(for: "probability")?.multiArrayValue.map { $0[0].floatValue }
        } catch {
            log.error("smart turn failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func loadedModel() -> MLModel? {
        lock.withLock {
            if loaded { return model }
            loaded = true
            guard let url = Bundle.main.url(forResource: "ArisSmartTurn", withExtension: "mlmodelc") else {
                log.error("smart turn: model missing from the app")
                return nil
            }
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .cpuAndNeuralEngine
            let start = ContinuousClock.now
            model = try? MLModel(contentsOf: url, configuration: configuration)
            if model == nil { log.error("smart turn: couldn't load the model") } else {
                log.notice("smart turn: ready in \(Int((ContinuousClock.now - start) / .milliseconds(1)), privacy: .public) ms")
            }
            return model
        }
    }
}
