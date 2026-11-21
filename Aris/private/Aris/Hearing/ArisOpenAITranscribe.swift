//
//  ArisOpenAITranscribe.swift
//  Aris
//
//  A finished turn read by OpenAI (gpt-transcribe): the recording goes up as one WAV file and the words come back
//  (ArisOpenAITranscribeWire). Nothing streams, so the notch shows Apple's live words while you talk. The key
//  ("openai-key", Keychain) is sent only to api.openai.com and is never logged; of an error only the status and
//  OpenAI's code are kept. No answer in time is nil, and the next engine reads the turn.
//

import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "openai-stt")

struct ArisOpenAITranscribe: ArisTurnRecogniser {
    static let keyName = "openai-key"
    static let sampleRate = 16_000

    let engine = ArisHearEngine.openai
    let key: String

    /// With the key; nil means another engine reads the turn.
    static func make() -> ArisOpenAITranscribe? { ArisKeyFile.load(keyName).map(ArisOpenAITranscribe.init(key:)) }

    func transcribe(_ samples: [Float], request: ArisHearRequest, timeout: Duration) async -> ArisHeard? {
        guard !samples.isEmpty, let url = URL(string: ArisOpenAITranscribeWire.endpoint) else { return nil }
        let boundary = "aris-\(UUID().uuidString)"
        let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
        var upload = URLRequest(url: url, timeoutInterval: seconds)
        upload.httpMethod = "POST"
        upload.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        upload.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let body = ArisOpenAITranscribeWire.body(wav: ArisOpenAITranscribeWire.wav(samples, sampleRate: Self.sampleRate),
                                                 languages: request.languages, keywords: request.hints, boundary: boundary)
        do {
            // Cancelling the task that waits (the turn was given up on) cancels the upload.
            let (data, response) = try await ArisNoStore.session.upload(for: upload, from: body)
            switch ArisOpenAITranscribeWire.heard(status: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data) {
            case .success(let heard): return heard
            case .failure(let failure):
                log.error("no transcript: \(failure.note, privacy: .public)")
                return nil
            }
        } catch {
            log.error("no transcript: \((error as? URLError)?.code == .timedOut ? "timed out" : "network \((error as NSError).code)", privacy: .public)")
            return nil
        }
    }
}
