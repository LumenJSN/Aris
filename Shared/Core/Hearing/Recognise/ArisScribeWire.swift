//
//  ArisScribeWire.swift
//  Aris (Shared/Core, Foundation only)
//
//  What Aris says to ElevenLabs' realtime speech-to-text socket and how it reads the answers, as the API reference
//  gives them (elevenlabs.io/docs/api-reference/speech-to-text/v-1-speech-to-text-realtime, read 2026-11-19).
//  The model is Scribe v3 Live, the successor of Scribe v2 Realtime on the same socket and key. With more than one
//  language turned on, `multilang_mode` has each language written in its own script, switches inside a sentence
//  included: an English word in a Korean sentence comes back in English letters, not as Hangul.
//

import Foundation

enum ArisScribeWire {
    static let model = "scribe_v3_live"
    static let endpoint = "wss://api.elevenlabs.io/v1/speech-to-text/realtime"

    /// The socket's query. `languages`: the base codes turned on, the first being the main one ("ko", "en").
    static func query(languages: [String], keyterms: [String], sampleRate: Int) -> [URLQueryItem] {
        var items = [
            URLQueryItem(name: "model_id", value: model),
            URLQueryItem(name: "audio_format", value: "pcm_\(sampleRate)"),
            URLQueryItem(name: "commit_strategy", value: "manual"),
            URLQueryItem(name: "include_language_detection", value: "true"),
            URLQueryItem(name: "include_timestamps", value: "true"),
        ]
        if let first = languages.first {
            items.append(URLQueryItem(name: "language_code", value: first))
            // The only other languages it may hear: language identification stays inside the set.
            items += languages.dropFirst().map { URLQueryItem(name: "secondary_languages", value: $0) }
        }
        if languages.count != 1 { items.append(URLQueryItem(name: "multilang_mode", value: "true")) }
        // More than 50 keyterms, or one over 20 characters, and the whole session is refused.
        let terms = ArisHearHints.build(.init(assistant: [], words: keyterms), bounds: .scribe)
        items += terms.map { URLQueryItem(name: "keyterms", value: $0) }
        return items
    }

    enum Event: Equatable, Sendable {
        case started
        case partial(String)
        case committed(String)
        /// The delayed copy of a commit: it carries the language.
        case timestamps(language: String?)
        /// A commit with too little new audio: what Scribe already heard stands.
        case throttled
        /// By its message type only (the text of an error is the provider's, and is not logged).
        case failed(String)
        case other
    }

    static func event(_ message: String) -> Event? {
        guard let data = message.data(using: .utf8), let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = object["message_type"] as? String else { return nil }
        let words = object["text"] as? String ?? ""
        switch type {
        case "session_started": return .started
        case "partial_transcript": return .partial(words)
        case "committed_transcript": return .committed(words)
        case "committed_transcript_with_timestamps":
            let code = object["language_code"] as? String
            return .timestamps(language: code?.isEmpty == false ? code : nil)
        case "commit_throttled": return .throttled
        default: return object["error"] != nil || type.hasSuffix("error") ? .failed(type) : .other
        }
    }
}

enum ArisPCM16 {
    /// Little-endian 16-bit PCM, as every engine here takes it.
    static func data(_ samples: [Float]) -> Data {
        var data = Data(capacity: samples.count * 2)
        for sample in samples {
            let value = Int16(max(-1, min(1, sample)) * Float(Int16.max))
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }
}
