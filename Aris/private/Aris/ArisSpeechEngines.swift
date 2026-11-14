//
//  ArisSpeechEngines.swift
//  Aris
//
//  Apple's two speech engines as ArisRecognizers. macOS 26: SpeechAnalyzer + SpeechTranscriber, its model installed
//  ahead of the first turn (what ArisListener did itself before). macOS 14 and 15 (or a 26 Mac held to it,
//  ArisListenEngine): SFSpeechRecognizer + SFSpeechAudioBufferRecognitionRequest with partial results, on the Mac when
//  it has the language's on-device model, else on Apple's servers (said once, ArisLegacyServerNotice). Its tasks are
//  swapped before Apple's one-minute limit by ArisRotatingRecognizer.
//

import AVFoundation
import Foundation
import os
import Speech

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "listen")

// MARK: - macOS 26: SpeechAnalyzer

@available(macOS 26.0, *)
@MainActor
final class ArisAnalyzerRecognizer: ArisRecognizer {
    var onHeard: ((_ kept: String, _ guess: String) -> Void)?
    var onProblem: ((String) -> Void)?

    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var results: Task<Void, Never>?

    private static func transcriber(_ locale: Locale) -> SpeechTranscriber {
        // Without .fastResults the guesses only arrive once listening stops; with it, about once a second.
        SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults, .fastResults], attributeOptions: [])
    }

    func modelMissing(locale: Locale) async throws -> Bool {
        let transcriber = Self.transcriber(locale)
        self.transcriber = transcriber
        // The language's model isn't installed yet (a first run): it downloads in the background, and this turn says so
        // instead of timing out while it waits (prepareSpeechAssets at launch makes this rare).
        let missing = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) != nil
        if missing { Task { await Self.prepareSpeechAssets(locale: locale) } }
        return missing
    }

    func start(locale: Locale, hints: [String]) async throws -> ArisRecognizerInput {
        let transcriber = self.transcriber ?? Self.transcriber(locale)
        self.transcriber = transcriber
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw ArisFailure(message: "Speech recognition isn't available for \(locale.identifier).")
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        if !hints.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = hints
            // Only hints: without them Aris still listens.
            do { try await analyzer.setContext(context) } catch { NSLog("Aris: vocabulary not used: \(error.localizedDescription)") }
        }
        let (stream, input) = AsyncStream<AnalyzerInput>.makeStream()
        self.analyzer = analyzer
        self.input = input
        results = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    if result.isFinal { self?.onHeard?(text, "") } else { self?.onHeard?("", text) }
                }
            } catch {
                NSLog("Aris: transcription ended: \(error.localizedDescription)")
            }
        }
        try await analyzer.start(inputSequence: stream)
        return ArisRecognizerInput(format: format, append: { input.yield(AnalyzerInput(buffer: $0)) })
    }

    func finish() async {
        input?.finish()
        input = nil
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        analyzer = nil
        await results?.value
        results = nil
    }

    /// Whether macOS's speech model for `locale` is on this Mac. Opens nothing: the wake word asks before its microphone.
    static func speechModelInstalled(locale: Locale) async -> Bool {
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [])
        do { return try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) == nil } catch { return false }
    }

    /// One install at a time, shared by the launch-time prepare and any turn that finds the model missing.
    nonisolated(unsafe) private static var assetInstall: (locale: String, task: Task<Void, Never>)?

    /// At launch: the language's speech model is installed ahead of the first turn, so that turn doesn't wait for it.
    /// A turn that finds it missing joins the same install.
    static func prepareSpeechAssets(locale: Locale) async {
        // Another language's install under way (the languages were just changed) is waited for, then this one starts.
        while let running = assetInstall {
            await running.task.value
            if assetInstall?.task == running.task { assetInstall = nil }
            if running.locale == locale.identifier { return }
        }
        let task = Task {
            let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [])
            guard let install = try? await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else { return }
            NSLog("Aris: installing the speech model for \(locale.identifier)")
            // The first listen says 음성 인식 준비 중 while this runs (③ B).
            await MainActor.run { ArisModelDownloader.shared.setAppleInstalling(true) }
            do { try await install.downloadAndInstall() } catch { NSLog("Aris: speech model not installed: \(error.localizedDescription)") }
            await MainActor.run { ArisModelDownloader.shared.setAppleInstalling(false) }
        }
        assetInstall = (locale.identifier, task)
        await task.value
        if assetInstall?.task == task { assetInstall = nil }
    }

    static func supportedLocales() async -> [String] {
        await SpeechTranscriber.supportedLocales.map { $0.identifier(.bcp47) }
    }
}

// MARK: - macOS 14 and 15: SFSpeechRecognizer

/// SFSpeechRecognizer's tasks for ArisRotatingRecognizer: 16 kHz mono buffers (what the listener records anyway),
/// partial results, on-device when the language's model is on the Mac.
@MainActor
final class ArisSFSpeechTasks: ArisSpeechTaskMaker {
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private(set) var place = ArisListenPlace.onDevice
    private var recognizer: SFSpeechRecognizer?

    /// The recogniser for `locale`, if the older engine has one.
    static func recognizer(_ locale: Locale) -> SFSpeechRecognizer? { SFSpeechRecognizer(locale: locale) }

    /// Where the older engine would hear `locale` (nil: it has no recogniser for it).
    static func place(_ locale: Locale) -> ArisListenPlace? {
        recognizer(locale).map { $0.supportsOnDeviceRecognition ? .onDevice : .server }
    }

    static func supportedLocales() -> [String] {
        SFSpeechRecognizer.supportedLocales().map(\.identifier).sorted()
    }

    func prepare(locale: Locale) throws {
        guard let recognizer = Self.recognizer(locale) else {
            throw ArisFailure(message: ArisListenEngineWords.unsupported(locale.identifier, english: ArisUIWords.english))
        }
        guard recognizer.isAvailable else { throw ArisFailure(message: ArisListenEngineWords.unavailable(english: ArisUIWords.english)) }
        recognizer.queue = .main
        place = recognizer.supportsOnDeviceRecognition ? .onDevice : .server
        self.recognizer = recognizer
    }

    func make(hints: [String], onText: @escaping @MainActor (String, Bool) -> Void, onEnd: @escaping @MainActor (String?) -> Void) -> ArisSpeechTask {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = place == .onDevice
        request.taskHint = .dictation
        request.addsPunctuation = true
        request.contextualStrings = hints
        let task = SpeechTask(request: request)
        guard let recognizer else {
            DispatchQueue.main.async { MainActor.assumeIsolated { onEnd(nil) } }
            return task
        }
        // On the recogniser's queue (main): each result is the task's whole text so far.
        task.task = recognizer.recognitionTask(with: request) { result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            let failed = error.map { ($0 as NSError).domain + " " + String(($0 as NSError).code) }
            let problem = error.flatMap { ArisListenEngineWords.problem(domain: ($0 as NSError).domain, code: ($0 as NSError).code, english: ArisUIWords.english) }
            ArisSFSpeechTasks.onMain {
                if let text { onText(text, final) }
                if let failed, !final {
                    log.notice("older engine: task ended (\(failed, privacy: .public))")
                    onEnd(problem)
                }
            }
        }
        return task
    }

    private nonisolated static func onMain(_ work: @escaping @MainActor () -> Void) {
        if Thread.isMainThread { MainActor.assumeIsolated { work() } } else { DispatchQueue.main.async { MainActor.assumeIsolated { work() } } }
    }

    private final class SpeechTask: ArisSpeechTask, @unchecked Sendable {
        let request: SFSpeechAudioBufferRecognitionRequest
        var task: SFSpeechRecognitionTask?
        init(request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }
        func append(_ buffer: AVAudioPCMBuffer) { request.append(buffer) }
        func endAudio() { request.endAudio() }
        func cancel() { task?.cancel() }
    }
}

/// The first time the older engine has to send the voice to Apple's servers it says so, once, on a card.
@MainActor
enum ArisLegacyServerNotice {
    static let saidKey = "arisLegacyServerNoticeSaid"

    static func sayOnce(locale: Locale, defaults: UserDefaults = .standard) {
        log.notice("older engine: \(locale.identifier, privacy: .public) has no on-device model; Apple's servers recognise it")
        guard !defaults.bool(forKey: saidKey) else { return }
        defaults.set(true, forKey: saidKey)
        let english = ArisUIWords.english
        let language = Locale(identifier: english ? "en" : "ko").localizedString(forIdentifier: locale.identifier) ?? locale.identifier
        let card = ArisNoticeRoute.announcement(title: ArisListenEngineWords.serverNoticeTitle(english: english),
                                                text: ArisListenEngineWords.serverNotice(language: language, english: english), kind: .system)
        Task { _ = await ArisController.shared.notify(card) }
    }
}
