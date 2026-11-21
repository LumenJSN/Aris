//
//  ArisVoiceEnrolModel.swift
//  Aris
//
//  내 목소리 등록하기 at work (F1): five sentences, one at a time — "준비하세요" for a moment, "지금 읽어 주세요" for the
//  take's window, the take judged (ArisVoiceEnrolment.keeps), the next one. The microphone is open only while the sheet
//  records, the wake word stays closed meanwhile (ArisController.beginRecordingCalls, as 호출어 녹음 does), and the takes
//  stay in memory: at the end they go into the print with 호출어 녹음's own calls (ArisVoiceID.enrol), and are dropped.
//  Nothing is written to disk but the print.
//

import AVFoundation
import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "voiceid")

@MainActor
final class ArisVoiceEnrolModel: ObservableObject {
    static let shared = ArisVoiceEnrolModel()

    enum Phase: Equatable {
        case intro, ready, listening, saved
        /// The take had too little voice: asked again.
        case retry
        case learning, done
        case failed(String)
    }

    @Published private(set) var phase = Phase.intro
    @Published private(set) var index = 0
    @Published private(set) var level: Float = 0
    private(set) var sentences = ArisVoiceEnrolment.sentences(english: false)
    private var takes: [[Float]] = []
    private var take: [Float] = []
    private var capturing = false
    private var mic: ArisWakeRecorderMic?
    private var flow: Task<Void, Never>?

    static let readyTime: Duration = .milliseconds(700)
    static let savedTime: Duration = .milliseconds(450)
    static let retryTime: Duration = .milliseconds(1400)

    var total: Int { sentences.count }
    var sentence: String { sentences.indices.contains(index) ? sentences[index] : "" }

    func open() {
        stop()
        sentences = ArisVoiceEnrolment.sentences(english: ArisUILanguage.english)
        takes = []
        index = 0
        phase = .intro
    }

    /// 시작하기.
    func begin() {
        let access = AVCaptureDevice.authorizationStatus(for: .audio)
        guard access != .denied, access != .restricted else { return phase = .failed(ArisVoiceIDRows.Sheet.micFailed) }
        guard ArisController.shared.recordingCalls || ArisController.shared.beginRecordingCalls() else { return phase = .failed(ArisVoiceIDRows.Sheet.busy) }
        do {
            try openMic()
        } catch {
            log.error("voice id: couldn't open the microphone: \(String(describing: error), privacy: .public)")
            ArisController.shared.endRecordingCalls()
            return phase = .failed(ArisVoiceIDRows.Sheet.micFailed)
        }
        takes = []
        index = 0
        runTake()
    }

    /// 멈추기, the sheet's × or Esc: whatever is under way stops, and nothing is kept.
    func stop() {
        flow?.cancel()
        flow = nil
        closeMic()
        ArisController.shared.endRecordingCalls()
        takes = []
        if phase != .done, phase != .learning { phase = .intro }
    }

    private func runTake() {
        flow?.cancel()
        flow = Task { [weak self] in
            guard let self else { return }
            self.phase = .ready
            try? await Task.sleep(for: Self.readyTime)
            guard !Task.isCancelled else { return }
            self.take = []
            self.capturing = true
            self.phase = .listening
            try? await Task.sleep(for: .milliseconds(Int(ArisVoiceEnrolment.takeSeconds * 1000)))
            guard !Task.isCancelled else { return }
            self.capturing = false
            self.finish(self.take)
        }
    }

    private func finish(_ samples: [Float]) {
        guard ArisVoiceEnrolment.keeps(samples) else {
            phase = .retry
            flow = Task { [weak self] in
                try? await Task.sleep(for: Self.retryTime)
                guard !Task.isCancelled else { return }
                self?.runTake()
            }
            return
        }
        takes.append(samples)
        phase = .saved
        flow = Task { [weak self] in
            try? await Task.sleep(for: Self.savedTime)
            guard !Task.isCancelled, let self else { return }
            if self.index + 1 < self.total {
                self.index += 1
                self.runTake()
            } else {
                self.learn()
            }
        }
    }

    /// The takes and 호출어 녹음's calls into the print, off the main thread.
    private func learn() {
        closeMic()
        ArisController.shared.endRecordingCalls()
        phase = .learning
        let clips = takes
        takes = []
        Task.detached(priority: .userInitiated) {
            let calls = Self.wakeCallClips()
            let kept = ArisVoiceID.shared.enrol(clips)
            let fromCalls = calls.isEmpty ? 0 : ArisVoiceID.shared.enrol(calls)
            log.notice("voice id: enrolled \(kept, privacy: .public) sentence(s) and \(fromCalls, privacy: .public) call(s)")
            await MainActor.run {
                self.phase = kept >= ArisVoiceEnrolment.leastKept ? .done : .failed(ArisVoiceIDRows.Sheet.failed)
            }
        }
    }

    /// 호출어 녹음's own calls of the name (ArisVoiceEnrolment.wakeCalls), read from its folder.
    nonisolated private static func wakeCallClips() -> [[Float]] {
        guard let store = ArisWakeCorpusStore.standard else { return [] }
        return ArisVoiceEnrolment.wakeCalls(store.load()).compactMap { file in
            (try? Data(contentsOf: store.folder.appendingPathComponent(file))).flatMap(ArisWAV.decode)
        }
    }

    // MARK: - The microphone

    private func openMic() throws {
        closeMic()
        let mic = ArisWakeRecorderMic()
        mic.onAudio = { [weak self] samples, level in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.level = level
                if self.capturing { self.take += samples }
            }
        }
        mic.onInterrupted = { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                log.notice("voice id: the microphone changed; stopped")
                self.stop()
                self.phase = .failed(ArisVoiceIDRows.Sheet.micFailed)
            }
        }
        try mic.start(headset: false)
        self.mic = mic
    }

    private func closeMic() {
        capturing = false
        mic?.stop()
        mic = nil
        level = 0
    }
}
