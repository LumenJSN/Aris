//
//  ArisScribe.swift
//  Aris
//
//  A turn heard by ElevenLabs Scribe v2 Realtime, the recognizer behind Aris's 100 languages: the turn's
//  16 kHz audio streams over a WebSocket while you talk (the words so far come back for the notch), and when you
//  stop, a commit returns the whole turn and the language it was in. Uses the ElevenLabs key in
//  ~/.config/aris/elevenlabs-key. Anything going wrong returns nil, and Whisper on the Mac takes over.
//

import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "scribe")

final class ArisScribe: @unchecked Sendable {
    struct Heard: Equatable {
        let text: String
        let language: String?
    }

    static let sampleRate = 16_000
    /// A tenth of a second per message.
    private static let chunk = sampleRate / 10
    private static let maxKeyterms = 50
    /// Scribe ignores a commit with less than 0.3 s of audio it hasn't committed ("commit_throttled"); the commit
    /// is padded with silence to a little more, so it always counts.
    static let shortestCommit = sampleRate * 35 / 100

    /// Everything heard so far, on the main thread.
    var onText: (@MainActor (String) -> Void)?

    private let task: URLSessionWebSocketTask
    private let lock = NSLock()
    private let sendQueue = DispatchQueue(label: "com.lumenjsn.aris.scribe")
    // Under `lock`:
    private var pending: [Float] = []
    private var committed: [String] = []
    private var partial = ""
    private var language: String?
    private var commitRequested = false
    private var finished = false
    private var failed = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(key: String, languages: [String], keyterms: [String]) {
        var components = URLComponents(string: "wss://api.elevenlabs.io/v1/speech-to-text/realtime")!
        var items = [
            URLQueryItem(name: "model_id", value: "scribe_v2_realtime"),
            URLQueryItem(name: "audio_format", value: "pcm_\(Self.sampleRate)"),
            URLQueryItem(name: "commit_strategy", value: "manual"),
            URLQueryItem(name: "include_language_detection", value: "true"),
            URLQueryItem(name: "include_timestamps", value: "true"),
        ]
        // The first language turned on, and the rest as the only others it may hear.
        if let first = languages.first {
            items.append(URLQueryItem(name: "language_code", value: ArisLanguages.baseCode(first)))
            items += languages.dropFirst().map { URLQueryItem(name: "secondary_languages", value: ArisLanguages.baseCode($0)) }
        }
        items += keyterms.prefix(Self.maxKeyterms).map { URLQueryItem(name: "keyterms", value: $0) }
        components.queryItems = items
        var request = URLRequest(url: components.url!, timeoutInterval: 10)
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        task = URLSession.shared.webSocketTask(with: request)
    }

    /// With the key and the setting on; nil means Whisper does the listening.
    static func make(languages: [String], keyterms: [String], enabled: Bool) -> ArisScribe? {
        guard enabled, let key = ArisElevenLabs.loadKey() else { return nil }
        return ArisScribe(key: key, languages: languages, keyterms: keyterms)
    }

    func start() {
        task.resume()
        receive()
    }

    /// 16 kHz mono samples, from any thread.
    func append(_ samples: [Float]) {
        let chunks: [[Float]] = lock.withLock {
            guard !commitRequested, !failed else { return [] }
            pending.append(contentsOf: samples)
            var out: [[Float]] = []
            while pending.count >= Self.chunk {
                out.append(Array(pending.prefix(Self.chunk)))
                pending.removeFirst(Self.chunk)
            }
            return out
        }
        for chunk in chunks { send(chunk, commit: false) }
    }

    /// The whole turn, once Scribe has it; nil when it failed or took longer than `timeout`.
    func finish(timeout: Duration) async -> Heard? {
        let rest: [Float]? = lock.withLock {
            guard !commitRequested, !failed else { return nil }
            commitRequested = true
            let rest = pending
            pending = []
            return rest
        }
        if let rest { send(Self.commitAudio(rest), commit: true) }
        let deadline = Task { [weak self] in
            // Cancelled once the turn is in: only a real wait runs out.
            guard (try? await Task.sleep(for: timeout)) != nil else { return }
            self?.resolve(failing: true, reason: "timed out")
        }
        await withCheckedContinuation { continuation in
            let now: Bool = lock.withLock {
                if finished || failed { return true }
                waiters.append(continuation)
                return false
            }
            if now { continuation.resume() }
        }
        deadline.cancel()
        cancel()
        return lock.withLock {
            Self.outcome(committed: committed, partial: partial, failed: failed).map { Heard(text: $0, language: language) }
        }
    }

    /// The leftover audio with silence after it, so the commit carries at least `shortestCommit` samples.
    static func commitAudio(_ rest: [Float]) -> [Float] {
        rest + [Float](repeating: 0, count: max(0, shortestCommit - rest.count))
    }

    /// The turn's words: what Scribe committed, or its last partial when the commit came back empty (it had
    /// already shown those words). nil when the session failed before committing anything: Whisper has the
    /// whole recording, a partial may lack the last words.
    static func outcome(committed: [String], partial: String, failed: Bool) -> String? {
        let text = joined(committed, "")
        if !text.isEmpty { return text }
        return failed ? nil : partial.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() {
        // Closing it ourselves: the receive that fails next isn't a failure of the turn, and a finish still waiting
        // gets what was heard so far.
        let waiting: [CheckedContinuation<Void, Never>] = lock.withLock {
            if !failed { finished = true }
            let waiting = waiters
            waiters = []
            return waiting
        }
        task.cancel(with: .goingAway, reason: nil)
        waiting.forEach { $0.resume() }
    }

    private func send(_ samples: [Float], commit: Bool) {
        let message: [String: Any] = [
            "message_type": "input_audio_chunk",
            "audio_base_64": Self.pcm16(samples).base64EncodedString(),
            "commit": commit,
            "sample_rate": Self.sampleRate,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: message), let text = String(data: data, encoding: .utf8) else { return }
        sendQueue.async { [task] in
            task.send(.string(text)) { error in
                if let error { log.error("send failed: \(error.localizedDescription, privacy: .public)") }
            }
        }
    }

    private func receive() {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.resolve(failing: true, reason: error.localizedDescription)
            case .success(let message):
                if case .string(let text) = message { self.handle(text) }
                if case .data(let data) = message, let text = String(data: data, encoding: .utf8) { self.handle(text) }
                self.receive()
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["message_type"] as? String else { return }
        let words = object["text"] as? String ?? ""
        switch type {
        case "session_started":
            log.notice("session started")
        case "partial_transcript":
            let shown: String = lock.withLock {
                partial = words
                return Self.joined(committed, partial)
            }
            publish(shown)
        case "committed_transcript":
            let shown: String = lock.withLock {
                if !words.isEmpty { committed.append(words) }
                partial = ""
                return Self.joined(committed, partial)
            }
            publish(shown)
            // The timestamped copy carries the language; it follows at once. Don't wait for it for long.
            if lock.withLock({ commitRequested }) {
                Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(250))
                    self?.resolve(failing: false)
                }
            }
        case "committed_transcript_with_timestamps":
            let requested: Bool = lock.withLock {
                if let code = object["language_code"] as? String, !code.isEmpty { language = code }
                return commitRequested
            }
            if requested { resolve(failing: false) }
        case "commit_throttled":
            // Nothing new since the audio it already has: the turn is what it has heard.
            log.notice("commit throttled; using what Scribe already heard")
            resolve(failing: false)
        default:
            if object["error"] != nil || type.hasSuffix("error") {
                resolve(failing: true, reason: "\(type): \(object["error"] as? String ?? "")")
            }
        }
    }

    private func publish(_ text: String) {
        guard let onText else { return }
        Task { @MainActor in onText(text) }
    }

    private func resolve(failing: Bool, reason: String? = nil) {
        let waiting: [CheckedContinuation<Void, Never>]? = lock.withLock {
            guard !finished, !failed else { return nil }
            if failing { failed = true } else { finished = true }
            let waiting = waiters
            waiters = []
            return waiting
        }
        // Once the turn is in (or the socket was closed on purpose), a late error is no news.
        guard let waiting else { return }
        if failing, let reason { log.error("gave up: \(reason, privacy: .public)") }
        waiting.forEach { $0.resume() }
    }

    private static func joined(_ committed: [String], _ partial: String) -> String {
        (committed + [partial]).filter { !$0.isEmpty }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Little-endian 16-bit PCM, as Scribe takes it.
    static func pcm16(_ samples: [Float]) -> Data {
        var data = Data(capacity: samples.count * 2)
        for sample in samples {
            let value = Int16(max(-1, min(1, sample)) * Float(Int16.max))
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }
}
