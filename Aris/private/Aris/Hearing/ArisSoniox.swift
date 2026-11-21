//
//  ArisSoniox.swift
//  Aris
//
//  A turn heard by Soniox (stt-rt-v6), the engine built for speech that switches language inside a sentence: the
//  turn's 16 kHz audio streams over a WebSocket while you talk (the words so far come back for the notch), and when
//  you stop, the stream is ended and Soniox finishes every word. What is sent and how the answers are read is
//  ArisSonioxWire. The key ("soniox-key", Keychain) goes with the connection and is never logged. Anything going wrong
//  returns nil, and the next engine takes over.
//

import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "soniox")

final class ArisSoniox: ArisLiveHearing, @unchecked Sendable {
    static let keyName = "soniox-key"
    static let sampleRate = 16_000
    /// A fifth of a second per frame.
    private static let chunk = sampleRate / 5

    let engine = ArisHearEngine.soniox
    var onText: (@MainActor (String) -> Void)?

    private let task: URLSessionWebSocketTask
    private let startMessage: String
    private let lock = NSLock()
    private let sendQueue = DispatchQueue(label: "com.lumenjsn.aris.soniox")
    // Under `lock`:
    private var pending: [Float] = []
    private var transcript = ArisSonioxWire.Transcript()
    private var ending = false
    private var finished = false
    private var failed = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init?(key: String, request: ArisHearRequest) {
        guard let url = URL(string: ArisSonioxWire.endpoint),
              let data = try? JSONSerialization.data(withJSONObject: ArisSonioxWire.start(languages: request.languages, terms: request.hints,
                                                                                         sampleRate: Self.sampleRate)),
              let start = String(data: data, encoding: .utf8) else { return nil }
        var upgrade = URLRequest(url: url, timeoutInterval: 10)
        upgrade.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        task = ArisNoStore.session.webSocketTask(with: upgrade)
        startMessage = start
    }

    /// With the key; nil means another engine does the listening.
    static func make(_ request: ArisHearRequest) -> ArisSoniox? {
        ArisKeyFile.load(keyName).flatMap { ArisSoniox(key: $0, request: request) }
    }

    func start() {
        task.resume()
        send(.string(startMessage))
        receive()
    }

    func append(_ samples: [Float]) {
        let chunks: [[Float]] = lock.withLock {
            guard !ending, !failed else { return [] }
            pending.append(contentsOf: samples)
            var out: [[Float]] = []
            while pending.count >= Self.chunk {
                out.append(Array(pending.prefix(Self.chunk)))
                pending.removeFirst(Self.chunk)
            }
            return out
        }
        for chunk in chunks { send(.data(ArisPCM16.data(chunk))) }
    }

    func finish(timeout: Duration) async -> ArisHeard? {
        let rest: [Float]? = lock.withLock {
            guard !ending, !failed else { return nil }
            ending = true
            let rest = pending
            pending = []
            return rest
        }
        if let rest {
            if !rest.isEmpty { send(.data(ArisPCM16.data(rest))) }
            // An empty text frame ends the stream: Soniox finishes every word, says `finished` and closes.
            send(.string(""))
        }
        let deadline = Task { [weak self] in
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
        return lock.withLock { failed ? nil : ArisHeard(text: transcript.text, language: transcript.language) }
    }

    func cancel() {
        let waiting: [CheckedContinuation<Void, Never>] = lock.withLock {
            if !failed { finished = true }
            let waiting = waiters
            waiters = []
            return waiting
        }
        task.cancel(with: .goingAway, reason: nil)
        waiting.forEach { $0.resume() }
    }

    private func send(_ message: URLSessionWebSocketTask.Message) {
        sendQueue.async { [task] in
            task.send(message) { error in
                if let error { log.error("send failed: \((error as NSError).code, privacy: .public)") }
            }
        }
    }

    private func receive() {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.resolve(failing: true, reason: "socket \((error as NSError).code)")
            case .success(let message):
                if case .string(let text) = message { self.handle(text) }
                if case .data(let data) = message, let text = String(data: data, encoding: .utf8) { self.handle(text) }
                self.receive()
            }
        }
    }

    private func handle(_ message: String) {
        let (step, shown): (ArisSonioxWire.Step, String) = lock.withLock {
            let step = transcript.take(message)
            return (step, transcript.text)
        }
        switch step {
        case .words:
            if let onText { Task { @MainActor in onText(shown) } }
        case .finished:
            resolve(failing: false)
        case .failed(let note):
            resolve(failing: true, reason: note)
        case .ignored:
            break
        }
    }

    private func resolve(failing: Bool, reason: String? = nil) {
        let waiting: [CheckedContinuation<Void, Never>]? = lock.withLock {
            guard !finished, !failed else { return nil }
            if failing { failed = true } else { finished = true }
            let waiting = waiters
            waiters = []
            return waiting
        }
        guard let waiting else { return }
        if failing, let reason { log.error("gave up: \(reason, privacy: .public)") }
        waiting.forEach { $0.resume() }
    }
}
