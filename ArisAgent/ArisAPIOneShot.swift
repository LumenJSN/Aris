//
//  ArisAPIOneShot.swift
//  aris-agent
//
//  One question to an API brain with no tools at all, answered in full: the read judge and main Aris's judgement of a
//  job's action when the brain the owner chose is an API brain (the judge runs on the chosen brain, in a no-tools mode), and
//  the smoke check's probes. Its own request, its own time limit; the key comes from the Keychain in this process.
//

import Foundation

enum ArisAPIOneShot {
    /// Asks once; `done` is called exactly once, on a background queue, with the answer or why there's none.
    /// `images`: pictures the question is about (computer use's look-and-click on a model that takes them).
    static func ask(profile: ArisAPIProfile, model: String? = nil, system: String, user: String, images: [ArisAPIImage] = [], functions: [ArisAPIFunction] = [],
                    timeout: TimeInterval, key: String?, maxTokens: Int = 512, strictOrigin: Bool = true, testServer: String? = nil,
                    done: @escaping (Result<(text: String, calls: [ArisAPIToolCall]), ArisAPIError>) -> Void) {
        guard let preset = profile.preset else { return done(.failure(ArisAPIError(kind: .unsupported, message: "unknown provider"))) }
        guard !preset.needsKey || key?.isEmpty == false else { return done(.failure(ArisAPIError(kind: .auth, message: "no key saved"))) }
        let spec = ArisAPIRequestSpec(dialect: preset.dialect, base: testServer ?? profile.base, model: model ?? profile.quick, key: key, headers: preset.headers,
                                      system: system, entries: [.user(text: user, images: images)], functions: functions, maxTokens: maxTokens,
                                      preset: preset.id, strictOrigin: strictOrigin)
        guard let request = ArisAPIDialects.request(spec) else {
            return done(.failure(ArisAPIError(kind: .unsupported, message: "the provider's address or model isn't usable")))
        }
        let queue = DispatchQueue(label: "com.lumenjsn.aris.api-oneshot")
        let decoder = ArisAPIStreamDecoder(dialect: preset.dialect)
        let holder = ArisAPIOneShotHolder()
        let task = ArisAPIStreamTask(request: request, totalTimeout: timeout, idleTimeout: timeout, queue: queue, onEvents: { events in
            for event in events { _ = decoder.feed(event) }
        }, onDone: { error in
            holder.task = nil
            if var error = error ?? decoder.error {
                error = ArisAPIError(kind: error.kind, message: ArisAPISecrets.redacted(error.message, secrets: [key].compactMap { $0 }), retryAt: error.retryAt)
                return done(.failure(error))
            }
            done(.success((decoder.text, decoder.calls)))
        })
        holder.task = task
        task.start()
    }

    /// The same, waiting (never on the main queue or a runner's).
    static func askNow(profile: ArisAPIProfile, model: String? = nil, system: String, user: String, functions: [ArisAPIFunction] = [],
                       timeout: TimeInterval, key: String?) -> Result<(text: String, calls: [ArisAPIToolCall]), ArisAPIError> {
        let box = ArisAPIResultBox()
        let waiting = DispatchSemaphore(value: 0)
        ask(profile: profile, model: model, system: system, user: user, functions: functions, timeout: timeout, key: key) { result in
            box.value = result
            waiting.signal()
        }
        _ = waiting.wait(timeout: .now() + timeout + 5)
        return box.value ?? .failure(ArisAPIError(kind: .timeout, message: "no answer in time"))
    }
}

/// Keeps a one-shot request alive until it ends.
final class ArisAPIOneShotHolder: @unchecked Sendable {
    var task: ArisAPIStreamTask?
}

final class ArisAPIResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Result<(text: String, calls: [ArisAPIToolCall]), ArisAPIError>?
    var value: Result<(text: String, calls: [ArisAPIToolCall]), ArisAPIError>? {
        get { lock.withLock { stored } }
        set { lock.withLock { if stored == nil { stored = newValue } } }
    }
}

/// The read judge on an API brain (ArisReadJudge): the same instruction and input as on every brain, one no-tools call
/// on the quick model. An HTTP failure (quota, key, network) means it couldn't be had; a late or odd answer is a block.
final class ArisAPIReadJudge: ArisReadJudging {
    let profile: ArisAPIProfile
    private let key: () -> String?
    private let timeout: TimeInterval
    private let strictOrigin: Bool
    private let testServer: String?

    /// `testServer`: the tests' fake provider (strictOrigin off); the agent never sets it.
    init(profile: ArisAPIProfile, key: @escaping () -> String?, timeout: TimeInterval = ArisReadGate.timeout, strictOrigin: Bool = true,
         testServer: String? = nil) {
        self.profile = profile
        self.key = key
        self.timeout = timeout
        self.strictOrigin = strictOrigin
        self.testServer = testServer
    }

    func judge(_ call: ArisReadCall, request: String, source: ArisReadSource, done: @escaping (ArisReadVerdict) -> Void) {
        judgeRun(call, request: request, source: source) { done($0.verdict) }
    }

    func judgeRun(_ call: ArisReadCall, request: String, source: ArisReadSource, done: @escaping (ArisJudgeRun) -> Void) {
        ArisAPIOneShot.ask(profile: profile, system: ArisReadJudge.instruction,
                           user: ArisReadJudge.input(request: request, call: call, source: source), timeout: timeout, key: key(),
                           strictOrigin: strictOrigin, testServer: testServer) { result in
            switch result {
            case .success(let answer): done(.answered(ArisReadJudge.parse(answer.text)))
            case .failure(let error): done(error.kind == .timeout ? .answered(.blocked(.undecided)) : .unavailable)
            }
        }
    }
}

/// The active API profile as the agent reads it (nil when none, or when the list was changed outside Aris).
enum ArisAPIActive {
    static func profile(store: ArisAPIStore = ArisAPISecrets.store) -> ArisAPIProfile? { store.load().activeProfile }

    static func key(for profile: ArisAPIProfile) -> String? {
        profile.preset?.needsKey == false ? nil : ArisAPISecrets.live.secret(for: profile.id)
    }

    /// Whether an API brain is set up to answer (a profile, and its key when it needs one).
    static var isReady: Bool {
        guard let profile = profile(), let preset = profile.preset else { return false }
        return !preset.needsKey || key(for: profile) != nil
    }

    /// Whether the API brain counts as an AI that can answer: set up, and not a key that has never answered
    /// (ArisAPIBrains.neverAnswered). This is what the app is told ("which brains are set up"), and so what the setup,
    /// the status line, the AI services page and the first things to try all read. A turn is still sent to a brain
    /// that is only set up: the first answer makes it ready.
    static func answers(store: ArisAPIStore = ArisAPISecrets.store) -> Bool { isReady && !needsCheck(store: store) }

    /// Set up with a key that has never answered: kept (he may be offline), and shown as needing a check.
    static func needsCheck(store: ArisAPIStore = ArisAPISecrets.store) -> Bool {
        guard isReady, let profile = profile(store: store), profile.preset?.needsKey == true else { return false }
        return store.load().neverAnswered(profile.id)
    }

    private static let notedLock = NSLock()
    nonisolated(unsafe) private static var noted: Set<String> = []

    /// A key was saved for `id`: its first answer is looked for afresh (security review 6, L5: after one answered turn
    /// a replaced key's first answer was not written down until a check by hand passed, and it stayed "isn't
    /// answering yet" though it answered).
    static func keySaved(_ id: String) {
        notedLock.withLock { _ = noted.remove(id) }
    }

    /// A turn got its answer from the API brain: a key that had never answered has now (looked at once per profile
    /// in this process, so an ordinary turn pays nothing).
    static func noteAnswered(store: ArisAPIStore = ArisAPISecrets.store) {
        guard let profile = profile(store: store), notedLock.withLock({ noted.insert(profile.id).inserted }) else { return }
        guard store.load().neverAnswered(profile.id) else { return }
        _ = store.update { $0.answered(profile.id, model: profile.quick, at: Date()) }
    }
}
