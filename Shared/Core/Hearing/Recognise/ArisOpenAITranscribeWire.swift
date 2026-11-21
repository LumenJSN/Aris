//
//  ArisOpenAITranscribeWire.swift
//  Aris (Shared/Core, Foundation only)
//
//  OpenAI's file transcription for a finished turn (developers.openai.com/api/reference/resources/audio/
//  subresources/transcriptions/methods/create and /api/docs/guides/speech-to-text, read 2026-11-19): POST
//  /v1/audio/transcriptions, a multipart form with the recording as a WAV file. The model is gpt-transcribe, the one
//  OpenAI now recommends (gpt-4o-transcribe and whisper-1 shut down on 26 February 2027); it alone takes `languages`
//  (every language that may be in the audio) and `keywords` (words to expect).
//

import Foundation

enum ArisOpenAITranscribeWire {
    static let model = "gpt-transcribe"
    static let endpoint = "https://api.openai.com/v1/audio/transcriptions"

    struct Failure: Error, Equatable, Sendable {
        /// The status and the provider's error code; never its message, which can quote the key.
        let note: String
    }

    /// A 16-bit mono WAV file of the turn.
    static func wav(_ samples: [Float], sampleRate: Int) -> Data {
        let audio = ArisPCM16.data(samples)
        var data = Data()
        func append(_ text: String) { data.append(contentsOf: Array(text.utf8)) }
        func append32(_ value: Int) { withUnsafeBytes(of: UInt32(value).littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: Int) { withUnsafeBytes(of: UInt16(value).littleEndian) { data.append(contentsOf: $0) } }
        append("RIFF"); append32(36 + audio.count); append("WAVE")
        append("fmt "); append32(16); append16(1); append16(1); append32(sampleRate); append32(sampleRate * 2); append16(2); append16(16)
        append("data"); append32(audio.count)
        data.append(audio)
        return data
    }

    static func body(wav: Data, languages: [String], keywords: [String], boundary: String) -> Data {
        var data = Data()
        func field(_ name: String, _ value: String) {
            data.append(contentsOf: Array("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("model", model)
        field("response_format", "json")
        for language in languages { field("languages[]", language) }
        for keyword in ArisHearHints.build(.init(assistant: [], words: keywords), bounds: .openAI) { field("keywords[]", keyword) }
        data.append(contentsOf: Array("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"turn.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        data.append(wav)
        data.append(contentsOf: Array("\r\n--\(boundary)--\r\n".utf8))
        return data
    }

    /// The answer read: the words and the first language detected, or why there are none.
    static func heard(status: Int, data: Data) -> Result<ArisHeard, Failure> {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard status == 200 else {
            let code = (object?["error"] as? [String: Any])?["code"] as? String
            return .failure(Failure(note: ["\(status)", code].compactMap { $0 }.joined(separator: " ")))
        }
        guard let text = object?["text"] as? String else { return .failure(Failure(note: "unreadable reply")) }
        let language = (object?["languages"] as? [[String: Any]])?.first?["code"] as? String
        return .success(ArisHeard(text: text.trimmingCharacters(in: .whitespacesAndNewlines), language: language))
    }
}
