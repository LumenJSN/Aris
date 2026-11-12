//
//  ArisModelDownloader.swift
//  Aris
//
//  Runs ③ B against the real thing: downloads the owner's pick through WhisperKit with its progress, only on Wi-Fi (an
//  expensive network or none: it waits, then goes on by itself), pauses and cancels, and has ArisWhisper load it once
//  it's in. The model is asked for on the setup's 받아쓰기 page (one line under the practice note, ArisModelLine: the user's
//  pick 9-A, 2026-11-11) and in Settings › AI services; the card that used to drop under the notch when the first turn
//  ended is no longer scheduled anywhere (the card itself still shows a download's progress, and offers the download
//  again for a model on disk that would not load). Also carries whether Apple's speech model is installing, for the
//  first listen's 음성 인식 준비 중. State changes only; the progress arrives at most a few times a second.
//

import Combine
import Foundation
import Network
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "speech-model")

@MainActor
final class ArisModelDownloader: ObservableObject {
    static let shared = ArisModelDownloader()

    @Published private(set) var state: ArisModelDownload = .idle
    /// What comes in (the owner's pick), or what the offer has selected.
    @Published var model: ArisSpeechModel = .small
    @Published private(set) var offering = false
    @Published private(set) var cardOpen = false
    @Published private(set) var appleInstalling = false
    @Published private(set) var remaining: TimeInterval?
    /// A complete model that keeps failing to load (ArisModelOffer.troubleAfter): the ear says 오류, its card why.
    @Published private(set) var loadTrouble: ArisSpeechModel?

    private var task: Task<Void, Never>?
    private var started: (at: Date, fraction: Double)?
    private var online = true
    private var expensive = false
    private let path = NWPathMonitor()
    private var clearDone: Task<Void, Never>?
    /// A failure that isn't the network (a full disk, a bad file) is tried again after 1 min, 2, 4 … up to 30.
    private let backoff = ArisRetryBackoff(first: .seconds(60), longest: .seconds(1800))
    private var failures = 0
    private var retryLater: Task<Void, Never>?

    /// How long 준비 끝 stays in the ear.
    static let doneHold: TimeInterval = 6

    private var stored: String? {
        get { UserDefaults.standard.string(forKey: ArisWhisper.storedKey) }
        set { UserDefaults.standard.set(newValue, forKey: ArisWhisper.storedKey) }
    }

    private init() {
        path.pathUpdateHandler = { [weak self] p in
            Task { @MainActor in self?.network(online: p.status == .satisfied, expensive: p.isExpensive) }
        }
        path.start(queue: .main)
        // A pick whose download didn't finish (the app quit): it goes on.
        if let pick = stored.flatMap(ArisSpeechModel.init(rawValue:)), !ArisWhisper.installed(pick) {
            model = pick
            begin()
        }
    }

    // MARK: the user

    func choose(_ pick: ArisSpeechModel) { model = pick }

    /// 받기.
    func accept() {
        stored = model.rawValue
        offering = false
        log.notice("download \(self.model.variant, privacy: .public) accepted")
        begin()
    }

    /// 나중에: never asked again (the settings can bring it in).
    func later() {
        stored = ArisModelOffer.later
        offering = false
    }

    func openCard() { cardOpen = state != .idle || loadTrouble != nil }

    func setLoadTrouble(_ model: ArisSpeechModel?) {
        loadTrouble = model
        if model == nil, state == .idle { cardOpen = false }
    }
    func hideCard() { cardOpen = false }

    func togglePause() {
        switch state {
        case let .running(f):
            task?.cancel()
            state = .paused(f)
        case .paused:
            begin()
        default: break
        }
    }

    /// 취소: back to Apple's transcript; the model can be asked for again in Settings › AI services.
    func cancel() {
        task?.cancel()
        retryLater?.cancel()
        state = .idle
        cardOpen = false
        stored = nil
    }

    func setAppleInstalling(_ on: Bool) { appleInstalling = on }

    /// 다시 받기: at once, not after the backoff.
    func retryNow() {
        guard state.retries else { return }
        begin()
    }

    /// The model was on disk but wouldn't load (ArisWhisper removed it): the notch offers the download again.
    func loadFailed(_ model: ArisSpeechModel) {
        task?.cancel()
        retryLater?.cancel()
        self.model = model
        stored = nil
        state = .idle
        cardOpen = false
        offering = true
    }

    // MARK: running

    private func network(online: Bool, expensive: Bool) {
        self.online = online
        self.expensive = expensive
        let may = ArisModelOffer.mayDownload(online: online, expensive: expensive)
        switch state {
        case let .running(f) where !may:
            task?.cancel()
            state = .waiting(f)
        case .waiting where may:
            begin()
        default: break
        }
    }

    private func begin() {
        task?.cancel()
        retryLater?.cancel()
        let from = state.fraction
        guard ArisModelOffer.mayDownload(online: online, expensive: expensive) else {
            state = .waiting(from)
            return
        }
        state = .running(from)
        started = (Date(), from)
        remaining = nil
        let model = self.model
        task = Task { [weak self] in
            do {
                try await ArisWhisper.download(model) { fraction in
                    Task { @MainActor in self?.progress(fraction) }
                }
                guard !Task.isCancelled, let self else { return }
                // WhisperKit returned, but every file must be there (ArisModelInstall), or it's a failure to retry.
                guard ArisWhisper.installed(model) else {
                    log.error("download returned without every file of \(model.variant, privacy: .public)")
                    self.failedNotNetwork()
                    return
                }
                self.finished()
            } catch {
                guard !Task.isCancelled, let self else { return }
                log.error("download failed: \(String(describing: error), privacy: .public)")
                if ArisModelOffer.waitsForNetwork(error) {
                    // The network went: wait for it, then go on (network(online:expensive:)).
                    self.state = .waiting(self.state.fraction)
                } else {
                    self.failedNotNetwork()
                }
            }
        }
    }

    /// 실패 in the ear, 다시 받기 in the card, and another try after the backoff.
    private func failedNotNetwork() {
        state = .failed(state.fraction)
        failures += 1
        let wait = backoff.wait(afterFailures: failures)
        retryLater?.cancel()
        retryLater = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled, let self, self.state.retries else { return }
            self.begin()
        }
    }

    private func progress(_ fraction: Double) {
        guard case let .running(old) = state else { return }
        let f = max(old, min(fraction, 0.999))
        state = .running(f)
        if let started {
            remaining = ArisModelOffer.remaining(fraction: f, elapsed: Date().timeIntervalSince(started.at), from: started.fraction)
        }
    }

    private func finished() {
        failures = 0
        state = .done
        remaining = nil
        log.notice("\(self.model.variant, privacy: .public) is in")
        Task { await ArisWhisper.shared.prepare() }
        clearDone?.cancel()
        clearDone = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.doneHold))
            guard !Task.isCancelled, let self, self.state == .done, !self.cardOpen else { return }
            self.state = .idle
        }
    }

    func closeDone() {
        cardOpen = false
        if state == .done { state = .idle }
    }
}
