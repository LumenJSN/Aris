//
//  ArisWhisper.swift
//  Aris
//
//  Whisper (through WhisperKit) on the Mac: the accurate second listen once you
//  stop talking, for Korean, English and both mixed. Never downloaded unasked
//  (the owner's ③ B): the notch offers the small or the large model and
//  ArisModelDownloader brings it in; this loads whichever the owner picked, or the large
//  one a Mac already has. Until one is ready Aris uses Apple's live transcript. A
//  turn longer than 30 seconds is read in windows (ArisLongTurn). An actor, so the
//  work stays off the main thread.
//

import Foundation
import os
import WhisperKit

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "whisper")

actor ArisWhisper {
    static let shared = ArisWhisper()
    /// Whisper's sample rate: what the recording must be in.
    static let sampleRate: Double = 16_000

    private var kit: WhisperKit?
    private var loaded: ArisSpeechModel?
    private var loading = false
    /// Failed loads of a complete model in a row.
    private var loadFailures = 0
    /// A download or load that failed (no network, a full disk) is tried again after a minute, then two, four … up to
    /// half an hour; never once per turn.
    private var retry = ArisRetryBackoff(first: .seconds(60), longest: .seconds(1800))

    /// Where the owner's pick is kept ("small", "large", or "later" after 나중에).
    static let storedKey = "arisSpeechModel"

    /// The model to load: the owner's pick, else the large one already on this Mac (ArisModelOffer.chosen).
    static var chosen: ArisSpeechModel? {
        // Apple 받아쓰기 picked in settings (AI 서비스 › 듣기): Whisper isn't loaded or asked, even with a model here.
        guard UserDefaults.standard.string(forKey: ArisAIPrefKey.hearEngine) != "apple" else { return nil }
        return ArisModelOffer.chosen(stored: UserDefaults.standard.string(forKey: storedKey), largeInstalled: installed(.large))
    }

    /// WhisperKit's snapshot folder for a model.
    static func modelFolder(_ model: ArisSpeechModel) -> URL? {
        folder?.appendingPathComponent("models/argmaxinc/whisperkit-coreml/\(model.variant)", isDirectory: true)
    }

    /// Every file WhisperKit loads is there (ArisModelInstall), not just one: a download cut short isn't installed.
    static func installed(_ model: ArisSpeechModel) -> Bool { installState(model) == .complete }

    static func installState(_ model: ArisSpeechModel) -> ArisModelInstall {
        guard let folder = modelFolder(model) else { return .none }
        let present = ArisModelInstall.required.filter { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
        return ArisModelInstall.state(present: Set(present))
    }

    /// Brings a model in (only ever after the user's 받기), reporting how far it is; files already in are kept.
    static func download(_ model: ArisSpeechModel, progress: @escaping @Sendable (Double) -> Void) async throws {
        _ = try await WhisperKit.download(variant: model.variant, downloadBase: folder) { progress($0.fractionCompleted) }
    }

    /// Loads the chosen model if it's on this Mac and not loaded yet (and the last failure isn't too recent). Never
    /// downloads.
    func prepare() async {
        guard let model = Self.chosen, Self.installed(model), loaded != model, !loading, retry.mayTry(at: .now) else { return }
        loading = true
        defer { loading = false }
        let start = ContinuousClock.now
        log.notice("loading \(model.variant, privacy: .public)")
        do {
            let config = WhisperKitConfig(model: model.variant, downloadBase: Self.folder, modelFolder: Self.modelFolder(model)?.path,
                                          verbose: false, load: true, download: false)
            kit = try await WhisperKit(config)
            loaded = model
            retry.succeeded()
            if loadFailures > 0 { await MainActor.run { ArisModelDownloader.shared.setLoadTrouble(nil) } }
            loadFailures = 0
            log.notice("ready in \(Int((ContinuousClock.now - start) / .seconds(1)), privacy: .public) s")
        } catch {
            retry.failed(at: .now)
            switch ArisModelLoadFailure.action(install: Self.installState(model)) {
            case .redownload:
                // Files are missing: its folder goes, and the notch offers it again.
                log.error("couldn't load an incomplete model: \(String(describing: error), privacy: .public); offered again")
                if let folder = Self.modelFolder(model) { try? FileManager.default.removeItem(at: folder) }
                await MainActor.run { ArisModelDownloader.shared.loadFailed(model) }
            case .retry:
                // Every file is there (memory pressure while it compiles, say): kept, loaded again after the backoff.
                loadFailures += 1
                let failures = loadFailures, wait = retry.wait(afterFailures: failures)
                log.error("couldn't load: \(String(describing: error), privacy: .public); kept, again in \(wait, privacy: .public)")
                if failures >= ArisModelOffer.troubleAfter { await MainActor.run { ArisModelDownloader.shared.setLoadTrouble(model) } }
                Task { [weak self] in
                    try? await Task.sleep(for: wait)
                    await self?.prepare()
                }
            }
        }
    }

    /// The words in a 16 kHz mono recording, or nil if Whisper isn't ready yet.
    func transcribe(_ samples: [Float]) async throws -> String? {
        guard Self.chosen != nil, let kit else {
            Task { await prepare() }
            return nil
        }
        // No language: Whisper works it out, which keeps English words in English.
        let options = DecodingOptions(task: .transcribe, language: nil, usePrefillPrompt: false,
                                      skipSpecialTokens: true, withoutTimestamps: true)
        let windows = ArisLongTurn.windows(of: samples, sampleRate: Self.sampleRate)
        guard windows.count > 1 else {
            let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
            return results.map(\.text).joined(separator: " ")
        }
        // Longer than Whisper reads at once: window by window, each cut where the turn was quietest (ArisLongTurn).
        var pieces: [String] = []
        for window in windows {
            // Given up on meanwhile (Aris went with the live transcript): the rest isn't read.
            try Task.checkCancellation()
            let audio = ArisTranscript.paddedForWhisper(Array(samples[window]), sampleRate: Self.sampleRate)
            let results = try await kit.transcribe(audioArray: audio, decodeOptions: options)
            pieces.append(results.map(\.text).joined(separator: " "))
        }
        return ArisLongTurn.joined(pieces)
    }

    static var folder: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Aris/Whisper", isDirectory: true)
    }
}
