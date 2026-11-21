//
//  ArisSonioxWire.swift
//  Aris (Shared/Core, Foundation only)
//
//  Soniox's real-time socket as its docs give it (docs.soniox.com/api-reference/stt/websocket-api and
//  /authentication/websocket-authentication, read 2026-11-19): the key goes with the connection (Authorization:
//  Bearer; `api_key` in the start message is refused from 15 January 2027), one JSON start message, audio as binary
//  frames, an empty text frame to end. Answers are tokens (pieces of words) marked final or not; the turn is every
//  final token so far and then the newest non-final ones. Model stt-rt-v6 (3 November 2026): language switches
//  inside a sentence, hints for the languages expected, and `context.terms` for words to spell the owner's way.
//

import Foundation

enum ArisSonioxWire {
    static let model = "stt-rt-v6"
    static let endpoint = "wss://stt-rt.soniox.com/transcribe-websocket"

    /// The start message. `languages`: the base codes turned on (hints only: another language is still written).
    static func start(languages: [String], terms: [String], sampleRate: Int) -> [String: Any] {
        var start: [String: Any] = ["model": model, "audio_format": "pcm_s16le", "sample_rate": sampleRate, "num_channels": 1,
                                    "enable_language_identification": true]
        if !languages.isEmpty { start["language_hints"] = languages }
        let known = ArisHearHints.build(.init(assistant: [], words: terms), bounds: .soniox)
        if !known.isEmpty { start["context"] = ["terms": known] }
        return start
    }

    enum Step: Equatable, Sendable {
        case words
        case finished
        /// The error's type and status only.
        case failed(String)
        case ignored
    }

    struct Transcript: Equatable, Sendable {
        private var final = ""
        private var tail = ""
        private var languages: [String: Int] = [:]

        var text: String { (final + tail).trimmingCharacters(in: .whitespacesAndNewlines) }

        /// The language most of the turn's pieces were in (pieces, not letters: Korean says more in fewer letters).
        var language: String? { languages.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key }

        mutating func take(_ message: String) -> Step {
            guard let data = message.data(using: .utf8), let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return .ignored }
            if let code = object["error_code"] as? Int {
                return .failed("\(object["error_type"] as? String ?? "error") (\(code))")
            }
            var newTail = ""
            for token in object["tokens"] as? [[String: Any]] ?? [] {
                guard let text = token["text"] as? String, token["translation_status"] as? String != "translation",
                      !(text.hasPrefix("<") && text.hasSuffix(">")) else { continue }
                if token["is_final"] as? Bool == true {
                    final += text
                    if let language = token["language"] as? String { languages[language, default: 0] += 1 }
                } else {
                    newTail += text
                }
            }
            tail = newTail
            return object["finished"] as? Bool == true ? .finished : .words
        }
    }
}
