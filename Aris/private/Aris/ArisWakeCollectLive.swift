//
//  ArisWakeCollectLive.swift
//  Aris
//
//  하루 소리 모으기 at work (the rules are ArisWakeCollect's). The waiting wake word tells it when a phrase of speech
//  starts and ends and when stage 1 hands a phrase on; while the switch is on (and only while Aris waits, never in a
//  turn or a conversation) it takes those few seconds out of the detector's memory and keeps them through
//  ArisWakeCorpusLive. The candidate's clip gets the wake check's outcome once known. Detection is untouched: this
//  only reads what the detector already holds. Off, every call here returns at once.
//

import Foundation

@MainActor
final class ArisWakeCollectLive {
    static let shared = ArisWakeCollectLive()

    /// The phrase now open (its first sample, about), and whether it was already kept as a candidate.
    private var phraseStart: Int?
    private var phraseIsCandidate = false
    /// The candidate clip waiting for its check's outcome.
    private var pendingFile: String?
    /// Listened time: the detector it was counted on and the sample counted up to.
    private var counted: (detector: ObjectIdentifier, sample: Int)?
    /// An outcome that came before its candidate's clip was taken (a sure voice wakes at once).
    private var earlyOutcome: String?
    /// The last candidate clip kept, and whether its clip is still to be taken: a wake that turns out false later
    /// (ArisController.closeWakeTurnQuietly) is written onto it.
    private var lastCandidateFile: String?
    private var candidatePending = false

    private var on: Bool { ArisWakeRecordLive.shared.collecting }

    /// Someone started (true) or stopped talking. `waiting`: Aris is idle and no conversation is open.
    func voice(_ talking: Bool, detector: ArisWakeDetector, waiting: Bool) {
        guard on, waiting else {
            phraseStart = nil
            return
        }
        count(detector)
        if talking {
            phraseStart = detector.currentSample
            phraseIsCandidate = false
            return
        }
        defer { phraseStart = nil }
        guard let start = phraseStart, !phraseIsCandidate else { return }
        let held = detector.held()
        guard let window = ArisWakeCollect.speechWindow(start: start, end: detector.currentSample, oldest: held.start) else { return }
        keep(held, window, candidate: false, score: nil)
    }

    /// Stage 1 handed a phrase on (`start`: its first sample), while Aris waits. Its clip is taken once the check had
    /// time to hear the words after it.
    func candidate(detector: ArisWakeDetector, start: Int?, score: Float?) {
        guard on else { return }
        count(detector)
        phraseIsCandidate = true
        earlyOutcome = nil
        candidatePending = true
        let from = start ?? detector.currentSample
        Task { [weak self, weak detector] in
            try? await Task.sleep(for: .seconds(ArisWakeCollect.candidateSeconds - 0.5))
            guard let self, let detector, self.on else { return }
            let held = detector.held()
            guard let window = ArisWakeCollect.candidateWindow(start: from, received: detector.currentSample, oldest: held.start) else { return }
            self.keep(held, window, candidate: true, score: score)
        }
    }

    /// The wake check ended down `path` ("voice", "whisper", "recognizer", "rejected").
    func outcome(_ path: String) {
        guard on else { return }
        guard let file = pendingFile else { return earlyOutcome = path }
        pendingFile = nil
        ArisWakeCorpusLive.shared.note(outcome: ArisWakeCollect.outcome(path: path), for: file)
    }

    /// A wake that opened a turn came to nothing (no words, or Whisper said it wasn't the name): its clip becomes a
    /// labelled false wake, the negative a trained detector learns most from.
    func falseWake() {
        guard on else { return }
        if candidatePending { return earlyOutcome = ArisWakeCollect.falseWake }
        guard let file = lastCandidateFile else { return }
        pendingFile = nil
        ArisWakeCorpusLive.shared.note(outcome: ArisWakeCollect.falseWake, for: file)
    }

    /// The detector stops: the time it listened is counted.
    func stopped(_ detector: ArisWakeDetector) {
        guard on else { return counted = nil }
        count(detector)
        counted = nil
    }

    private func count(_ detector: ArisWakeDetector) {
        let id = ObjectIdentifier(detector), now = detector.currentSample
        if let counted, counted.detector == id, now > counted.sample {
            ArisWakeCorpusLive.shared.listened(Double(now - counted.sample) / Double(ArisWakeCollect.sampleRate))
        }
        counted = (id, now)
    }

    private func keep(_ held: (start: Int, samples: [Float]), _ window: Range<Int>, candidate: Bool, score: Float?) {
        let summary = ArisWakeRecordLive.shared.summary
        guard ArisWakeCollect.mayKeep(clips: summary.ambient, bytes: summary.bytes) else { return }
        let lower = window.lowerBound - held.start, upper = min(held.samples.count, window.upperBound - held.start)
        guard lower >= 0, upper > lower else { return }
        let samples = Array(held.samples[lower..<upper])
        let now = Date()
        let file = ArisWakeCollect.file(at: now, candidate: candidate)
        var entry = ArisWakeManifest.Entry(file: file, label: candidate ? .ambientCandidate : .ambientSpeech,
                                           seconds: Double(samples.count) / Double(ArisWakeCollect.sampleRate),
                                           recordedAt: ArisWakeManifest.timestamp(now))
        entry.score = score.map(Double.init)
        if candidate {
            if let early = earlyOutcome { entry.outcome = ArisWakeCollect.outcome(path: early) } else { pendingFile = file }
            earlyOutcome = nil
            lastCandidateFile = file
            candidatePending = false
        }
        ArisWakeCorpusLive.shared.save(samples, as: entry)
    }
}
