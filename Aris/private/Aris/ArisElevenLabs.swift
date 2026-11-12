//
//  ArisElevenLabs.swift
//  Aris
//
//  Aris's voice from ElevenLabs (Geaun on Eleven v4 Turbo), streamed as raw PCM
//  so playback starts with the first chunk. The API key lives in a private file,
//  ~/.config/aris/elevenlabs-key; without it Aris uses the system voice.
//

import Foundation

enum ArisElevenLabs {
    static let voiceID = "k5siOxi4qsPS2kASoRt7"  // Geaun garage - Calm & Friendly
    static let modelID = "eleven_v4_turbo"
    /// The models settings › AI 서비스 › 말하기 offers, and where the pick is kept; nothing stored: v4 Turbo, as before.
    static let models = ["eleven_flash_v2_5", modelID, "eleven_multilingual_v2"]
    static let modelKey = "arisVoiceModel"
    static func model(stored: String?) -> String { stored.flatMap { models.contains($0) ? $0 : nil } ?? modelID }
    static var chosenModel: String { model(stored: UserDefaults.standard.string(forKey: modelKey)) }
    static let sampleRate: Double = 24_000
    /// About a tenth of a second of 16-bit mono audio per scheduled buffer.
    private static let chunkBytes = Int(sampleRate / 10) * 2
    private static let timeout: TimeInterval = 15
    /// How long the first byte of audio (not the headers) may take; after that the system voice speaks instead of the
    /// notch staying silent.
    static let firstByte: Duration = .seconds(4)

    struct Failure: Error {
        let message: String
        /// The HTTP status ElevenLabs answered with; nil when it never answered (no network, the first byte too late).
        var status: Int?
    }

    static func loadKey() -> String? {
        ArisKeyFile.load("elevenlabs-key")
    }

    /// ElevenLabs' range for `voice_settings.speed`.
    static let speedRange: ClosedRange<Double> = 0.7...1.2

    /// The system voice's rate for a speed (1 is its default pace).
    static func systemRate(speed: Double, defaultRate: Float) -> Float { defaultRate * Float(speed) }

    struct Voice: Equatable {
        let id: String
        let name: String
        let detail: String
        let own: Bool
        let previewURL: URL?
    }

    /// `GET /v1/voices`: the account's voices, its own (not "premade") first, each group by name.
    static func voices(from data: Data) -> [Voice]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["voices"] as? [[String: Any]] else { return nil }
        let voices = list.compactMap { raw -> Voice? in
            guard let id = raw["voice_id"] as? String, let name = raw["name"] as? String else { return nil }
            let labels = raw["labels"] as? [String: Any] ?? [:]
            let detail = ["gender", "accent", "age", "description"].compactMap { labels[$0] as? String }.joined(separator: " · ")
            return Voice(id: id, name: name, detail: detail, own: (raw["category"] as? String ?? "premade") != "premade",
                         previewURL: (raw["preview_url"] as? String).flatMap(URL.init(string:)))
        }
        return voices.sorted { ($0.own ? 0 : 1, $0.name.lowercased()) < ($1.own ? 0 : 1, $1.name.lowercased()) }
    }

    static func voiceList(key: String) async -> [Voice]? {
        var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/voices")!, timeoutInterval: timeout)
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return voices(from: data)
    }

    static func request(text: String, key: String, voiceID: String = voiceID, speed: Double = 1, model: String = chosenModel) -> URLRequest {
        var components = URLComponents(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)/stream")!
        components.queryItems = [URLQueryItem(name: "output_format", value: "pcm_\(Int(sampleRate))")]
        var request = URLRequest(url: components.url!, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "text": text, "model_id": model,
            "voice_settings": ["speed": min(max(speed, speedRange.lowerBound), speedRange.upperBound)],
        ] as [String: Any])
        return request
    }

    /// The spoken audio as it arrives, in chunks of samples in -1...1.
    static func speech(for text: String, key: String, voiceID: String = voiceID, speed: Double = 1) -> AsyncThrowingStream<[Float], Error> {
        AsyncThrowingStream { continuation in
            // A first byte that doesn't come within firstByte cancels the request: the system voice speaks instead of
            // the notch staying silent for the whole timeout.
            let timedOut = ArisFlag(), responded = ArisFlag()
            let task = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request(text: text, key: key, voiceID: voiceID, speed: speed))
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200 else {
                        var body = Data()
                        for try await byte in bytes where body.count < 500 { body.append(byte) }
                        throw Failure(message: "ElevenLabs answered \(status): \(String(decoding: body, as: UTF8.self))", status: status)
                    }
                    var pending = Data()
                    for try await byte in bytes {
                        // The deadline is met by audio, not by headers.
                        if pending.isEmpty, !responded.isSet { responded.set() }
                        pending.append(byte)
                        guard pending.count >= chunkBytes else { continue }
                        let chunk = ArisPCM.floats(from: pending)
                        pending = chunk.leftover
                        continuation.yield(chunk.samples)
                    }
                    let last = ArisPCM.floats(from: pending)
                    if !last.samples.isEmpty { continuation.yield(last.samples) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: timedOut.isSet ? Failure(message: "ElevenLabs didn't answer within \(firstByte)") : error)
                }
            }
            let deadline = Task {
                try? await Task.sleep(for: firstByte)
                guard !Task.isCancelled, !responded.isSet else { return }
                timedOut.set()
                task.cancel()
            }
            continuation.onTermination = { _ in
                task.cancel()
                deadline.cancel()
            }
        }
    }
}

/// A flag set from one task and read from another.
final class ArisFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}

/// Raw little-endian 16-bit PCM, as ElevenLabs streams it.
enum ArisPCM {
    /// The whole samples in `data`, plus a trailing odd byte to put in front of the next chunk.
    static func floats(from data: Data) -> (samples: [Float], leftover: Data) {
        let bytes = [UInt8](data)
        let whole = bytes.count / 2
        var samples = [Float]()
        samples.reserveCapacity(whole)
        for i in 0..<whole {
            let value = Int16(bitPattern: UInt16(bytes[2 * i]) | UInt16(bytes[2 * i + 1]) << 8)
            samples.append(value < 0 ? Float(value) / 32_768 : Float(value) / 32_767)
        }
        return (samples, bytes.count % 2 == 1 ? Data([bytes[bytes.count - 1]]) : Data())
    }
}
