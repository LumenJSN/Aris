//
//  ArisWakeRecorderModel.swift
//  Aris
//
//  호출어 녹음's sheet at work: one block of ArisWakeScript at a time, its line shown first, then each take — “준비하세요”
//  for a moment, “지금 말해 주세요” for the take's window, the take judged (ArisWakeTake), kept through
//  ArisWakeCorpusLive with its labels, the next one. The microphone is open only while a block records, and the wake
//  word stays closed meanwhile (ArisController.beginRecordingCalls). It can stop at any take and continue later from
//  the first one missing; an optional block (music, AirPods) can be skipped for this time.
//

import AVFoundation
import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "wake-record")

@MainActor
final class ArisWakeRecorderModel: ObservableObject {
    static let shared = ArisWakeRecorderModel()

    enum Phase: Equatable {
        /// Before anything: how much is done, start or continue.
        case intro
        /// A block's instruction, before its first take.
        case block
        case ready
        case listening
        case saved
        /// The take was not kept: the line says why, and it is asked again.
        case retry(String)
        case failed(String)
        case done
    }

    @Published private(set) var phase = Phase.intro
    @Published private(set) var step: ArisWakeStep?
    @Published private(set) var level: Float = 0
    @Published private(set) var recorded: Set<String> = []
    /// Blocks left out this time.
    private var skipped: Set<String> = []
    private var mic: ArisWakeRecorderMic?
    private var micBlock: String?
    private var take: [Float] = []
    private var capturing = false
    private var flow: Task<Void, Never>?

    static let readyTime: Duration = .milliseconds(700)
    static let savedTime: Duration = .milliseconds(450)
    static let retryTime: Duration = .milliseconds(1600)

    var done: Int { recorded.count }
    var total: Int { ArisWakeScript.totalTakes }

    /// The sheet opened.
    func open() {
        stopFlow()
        skipped = []
        recorded = ArisWakeRecordLive.shared.recordedTakes
        step = ArisWakeScript.next(recorded: recorded)
        phase = step == nil && !recorded.isEmpty ? .done : .intro
    }

    /// 시작하기 / 이어서 하기 on the intro: the first missing take's block. With everything recorded, from the start again.
    func begin() {
        if ArisWakeScript.next(recorded: recorded, skipping: skipped) == nil { recorded = [] }
        showNextBlock()
    }

    /// 시작하기 on a block's line: its takes, one after another.
    func startBlock() {
        guard let step else { return }
        let access = AVCaptureDevice.authorizationStatus(for: .audio)
        guard access != .denied, access != .restricted else { return phase = .failed(ArisWakeRecordRows.Sheet.micFailed) }
        guard ArisController.shared.recordingCalls || ArisController.shared.beginRecordingCalls() else { return phase = .failed(ArisWakeRecordRows.Sheet.busy) }
        do {
            try openMic(for: step.block)
        } catch is ArisWakeRecorderMic.NoHeadset {
            return phase = .failed(ArisWakeRecordRows.Sheet.noHeadset)
        } catch {
            log.error("wake record: couldn't open the microphone: \(String(describing: error), privacy: .public)")
            return phase = .failed(ArisWakeRecordRows.Sheet.micFailed)
        }
        runTake()
    }

    /// 이 묶음 건너뛰기 (optional blocks only).
    func skipBlock() {
        guard let step, step.block.optional else { return }
        skipped.insert(step.block.id)
        closeMic()
        showNextBlock()
    }

    /// 다시 녹음 after a failure: the block's line again.
    func retryBlock() { showNextBlock() }

    /// 멈추기, the sheet's × or Esc: whatever is under way stops; what was kept stays.
    func stop() {
        stopFlow()
        closeMic()
        ArisController.shared.endRecordingCalls()
        level = 0
        if phase != .done { phase = .intro }
        step = ArisWakeScript.next(recorded: recorded)
    }

    // MARK: - The flow

    private func showNextBlock() {
        stopFlow()
        step = ArisWakeScript.next(recorded: recorded, skipping: skipped)
        guard step != nil else {
            closeMic()
            ArisController.shared.endRecordingCalls()
            return phase = .done
        }
        phase = .block
    }

    private func runTake() {
        flow?.cancel()
        flow = Task { [weak self] in
            guard let self, let step = self.step else { return }
            self.phase = .ready
            try? await Task.sleep(for: Self.readyTime)
            guard !Task.isCancelled else { return }
            self.take = []
            self.capturing = true
            self.phase = .listening
            try? await Task.sleep(for: .milliseconds(Int(step.prompt.seconds * 1000)))
            guard !Task.isCancelled else { return }
            self.capturing = false
            self.finish(step, self.take)
        }
    }

    private func finish(_ step: ArisWakeStep, _ samples: [Float]) {
        guard ArisController.shared.session.phase == .idle else {
            stop()
            return phase = .failed(ArisWakeRecordRows.Sheet.busy)
        }
        let verdict = ArisWakeTake.verdict(samples, prompt: step.prompt)
        if let line = ArisWakeTake.retryLine(verdict) {
            phase = .retry(line)
            flow = Task { [weak self] in
                try? await Task.sleep(for: Self.retryTime)
                guard !Task.isCancelled else { return }
                self?.runTake()
            }
            return
        }
        ArisWakeCorpusLive.shared.save(samples, as: entry(step, seconds: Double(samples.count) / ArisVoicePrint.sampleRate)) { [weak self] ok in
            guard let self, self.step == step else { return }
            guard ok else {
                self.stop()
                return self.phase = .failed(ArisWakeRecordRows.Sheet.saveFailed)
            }
            self.recorded.insert(step.key)
            self.phase = .saved
            self.flow = Task { [weak self] in
                try? await Task.sleep(for: Self.savedTime)
                guard !Task.isCancelled, let self else { return }
                let next = ArisWakeScript.next(recorded: self.recorded, skipping: self.skipped)
                if let next, next.block.id == step.block.id {
                    self.step = next
                    self.runTake()
                } else {
                    self.closeMic()
                    self.showNextBlock()
                }
            }
        }
    }

    private func entry(_ step: ArisWakeStep, seconds: Double) -> ArisWakeManifest.Entry {
        let prompt = step.prompt
        var entry = ArisWakeManifest.Entry(file: "calls/\(step.key).wav", label: prompt.label == .call ? .call : .confusable,
                                           seconds: seconds, recordedAt: ArisWakeManifest.timestamp(Date()))
        entry.phrase = prompt.phrase
        entry.prompt = prompt.id
        entry.take = step.take
        entry.style = prompt.style.rawValue
        entry.distance = prompt.distance.rawValue
        entry.background = prompt.background.rawValue
        entry.mic = prompt.mic.rawValue
        entry.device = mic?.device
        return entry
    }

    // MARK: - The microphone

    private func openMic(for block: ArisWakeBlock) throws {
        if mic != nil, micBlock == block.id { return }
        closeMic()
        let mic = ArisWakeRecorderMic()
        // Both are called on the main thread (ArisWakeRecorderMic).
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
                log.notice("wake record: the microphone changed; stopped")
                self.stop()
                self.phase = .failed(ArisWakeRecordRows.Sheet.micFailed)
            }
        }
        try mic.start(headset: block.prompts.contains { $0.mic == .airPods })
        self.mic = mic
        micBlock = block.id
    }

    private func closeMic() {
        capturing = false
        mic?.stop()
        mic = nil
        micBlock = nil
        level = 0
    }

    private func stopFlow() {
        flow?.cancel()
        flow = nil
        capturing = false
    }
}
