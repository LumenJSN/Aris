//
//  ArisVoiceEmbedder.swift
//  Aris
//
//  The owner's voice (F1): an utterance turned into 256 numbers by an on-device speaker-embedding model, so two
//  utterances of one person point the same way whatever was said. Two Core ML models in the app
//  (Hearing/VoiceIDModel, CC BY 4.0, VoiceID-LICENSE.txt): pyannote community-1's 80-band filterbank, then its WeSpeaker
//  ResNet34. Both read a fixed 10 s; ArisVoiceClip trims the silence and repeats a shorter clip to fill it. About 60 ms
//  on the CPU for one utterance, off the main thread. Nothing it reads or makes leaves the Mac.
//

import CoreML
import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "voiceid")

final class ArisVoiceEmbedder: @unchecked Sendable {
    /// The models a print is made with: a print from other models is not used (ArisVoiceProfile.model).
    static let modelID = "pyannote-community-1/fluid-1ed7a662"
    static let fbankName = "ArisVoiceFBank"
    static let embeddingName = "ArisVoiceEmbedding"
    /// The embedding model's frames over the 10 s, weighed equally (the whole window is the utterance).
    static let weightFrames = 589

    static let shared = ArisVoiceEmbedder()

    private let lock = NSLock()
    private let folder: URL?
    private var models: (fbank: MLModel, embedding: MLModel)?
    private var loaded = false

    /// `folder`: where the two .mlmodelc are (the tests); nil: the app's bundle.
    init(folder: URL? = nil) {
        self.folder = folder
    }

    /// Loads the models ahead of the first utterance.
    func warm() {
        DispatchQueue.global(qos: .utility).async { _ = self.loadedModels() }
    }

    /// The vector of 16 kHz mono audio that is already trimmed (ArisVoiceClip.trimmed); nil when the models can't run.
    func vector(_ trimmed: [Float]) -> [Float]? {
        guard let window = ArisVoiceClip.filled(trimmed), let models = loadedModels() else { return nil }
        do {
            let audio = try MLMultiArray(shape: [1, 1, NSNumber(value: window.count)], dataType: .float32)
            window.withUnsafeBufferPointer { source in
                audio.dataPointer.assumingMemoryBound(to: Float.self).update(from: source.baseAddress!, count: window.count)
            }
            let weights = try MLMultiArray(shape: [1, NSNumber(value: Self.weightFrames)], dataType: .float32)
            let pointer = weights.dataPointer.assumingMemoryBound(to: Float.self)
            for index in 0..<Self.weightFrames { pointer[index] = 1 }
            let output: [Float]? = try lock.withLock {
                let bank = try models.fbank.prediction(from: MLDictionaryFeatureProvider(dictionary: ["audio": audio]))
                guard let features = bank.featureValue(for: "fbank_features")?.multiArrayValue else { return nil }
                let embedded = try models.embedding.prediction(from: MLDictionaryFeatureProvider(dictionary: ["fbank_features": features, "weights": weights]))
                guard let vector = embedded.featureValue(for: "embedding")?.multiArrayValue else { return nil }
                return (0..<vector.count).map { vector[$0].floatValue }
            }
            guard let output, ArisVoiceProfile.sizes.contains(output.count) else {
                log.error("voice id: the model gave no vector")
                return nil
            }
            return ArisVoiceVector.normalized(output)
        } catch {
            log.error("voice id: the model failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Whether the models are in the app (and load).
    var available: Bool { loadedModels() != nil }

    private func url(_ name: String) -> URL? {
        if let folder { return folder.appendingPathComponent(name + ".mlmodelc") }
        return Bundle.main.url(forResource: name, withExtension: "mlmodelc")
    }

    private func loadedModels() -> (fbank: MLModel, embedding: MLModel)? {
        lock.withLock {
            if loaded { return models }
            loaded = true
            guard let fbankURL = url(Self.fbankName), let embeddingURL = url(Self.embeddingName) else {
                log.error("voice id: the models are missing from the app")
                return nil
            }
            // On the CPU, both: the filterbank is written for it (its own metadata), and the lines in ArisVoiceMatcher were
            // measured there (the Neural Engine's half precision would move the scores a little).
            let cpu = MLModelConfiguration()
            cpu.computeUnits = .cpuOnly
            let start = ContinuousClock.now
            guard let fbank = try? MLModel(contentsOf: fbankURL, configuration: cpu),
                  let embedding = try? MLModel(contentsOf: embeddingURL, configuration: cpu) else {
                log.error("voice id: couldn't load the models")
                return nil
            }
            models = (fbank, embedding)
            log.notice("voice id: ready in \(Int((ContinuousClock.now - start) / .milliseconds(1)), privacy: .public) ms")
            return models
        }
    }
}
