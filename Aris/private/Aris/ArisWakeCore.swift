//
//  ArisWakeCore.swift
//  Aris
//
//  What the wake word does with the microphone's audio, without the microphone: ArisWakeDetector opens the device
//  and hands every 16 kHz chunk here, so the same code runs in the app and from files in the tests and the bench.
//  Two stages, the way Siri's listening is built:
//  - Stage 1, always on, costs almost nothing: the loudness of each 10 ms (ArisVoiceGate). Nothing else looks at
//    the audio while the room is quiet. When a sound starts after a quiet moment, its first half second gets one
//    cheap look: is it a voice at all (ArisWakeVoice), and, when the user taught Aris their “아리스”, is it close to their
//    voice print (ArisWakeModel).
//  - Stage 2 runs only for a phrase stage 1 let through: the detector's owner starts the speech recognizer on the
//    buffered phrase (`candidate`), and that decides.
//  The last six seconds are kept in memory here and nowhere else: nothing is written to disk or sent anywhere, and
//  a sound stage 1 stopped is never looked at again. Foundation and Accelerate only.
//

import Accelerate
import Foundation

struct ArisWakeCore {
    enum Mode {
        case waiting(ArisWakeModel?)
        case training
    }

    enum Event: Equatable {
        /// Waiting: someone started (true) or stopped talking.
        case voice(Bool)
        /// Waiting: a phrase stage 1 let through, with its distance from the trained name (nil untrained) and `sure`
        /// when it is as close as the user's own recordings.
        case candidate(score: Float?, sure: Bool)
        /// Training: one phrase that was said, 16 kHz.
        case phrase([Float])
        /// Training: loudness 0...1 for the orb.
        case level(Float)
    }

    /// What stage 1 did, for the bench and the log (never any audio).
    struct Counts: Equatable {
        var phrases = 0
        /// Sounds stopped because nothing in them was a voice.
        var notVoice = 0
        var printChecks = 0
        var candidates = 0
    }

    static let kept = Int(ArisVoicePrint.sampleRate) * 6
    /// Audio kept from just before a phrase starts.
    static let lead = Int(ArisVoicePrint.sampleRate * 0.15)
    /// The voice check's frames that lie wholly inside that lead: the room before the phrase.
    static let leadFrames = (lead - ArisWakeVoice.frameLength) / ArisWakeVoice.hop + 1
    /// The voice check never needs more of a phrase than this.
    static let mostVoiceFrames = leadFrames + ArisWakeVoice.within

    let mode: Mode
    /// The voice check is on (ArisWakeVoice.enabled).
    let voiceCheck: Bool
    /// While the recognizer checks a candidate, or in a conversation: no candidates are handed on.
    var paused: Bool
    private(set) var counts = Counts()
    /// Samples ever received; `audio[0]` is sample `dropped`.
    private(set) var received = 0
    /// Where the last candidate's audio starts (from just before the phrase).
    private(set) var candidateStartSample: Int?
    /// The last voice-print distance measured, for the log.
    private(set) var lastScore: Float?
    private var gate = ArisVoiceGate()
    private var audio: [Float] = []
    private var dropped = 0
    private var hops = 0
    private var phraseStartSample: Int?
    private var checked = false
    private var voiceFrames: [ArisWakeVoice.Frame] = []
    /// The sample those frames start at.
    private var voiceFrom: Int?
    /// The open phrase was found to be a voice.
    private var isVoice = false

    init(mode: Mode, voiceCheck: Bool = true, paused: Bool = false) {
        self.mode = mode
        self.voiceCheck = voiceCheck
        self.paused = paused
    }

    /// One chunk from the microphone. `onHop`: called with each 10 ms loudness right after the gate saw it (the
    /// conversation's voice watch).
    mutating func take(_ samples: [Float], onHop: (Float) -> Void = { _ in }) -> [Event] {
        var events: [Event] = []
        audio += samples
        received += samples.count
        if audio.count > Self.kept * 2 {
            let extra = audio.count - Self.kept
            audio.removeFirst(extra)
            dropped += extra
        }
        let hop = ArisVoicePrint.hop
        while (hops + 1) * hop <= received {
            let level = Self.rms(audio, from: hops * hop - dropped, count: hop)
            if case .training = mode, hops % 5 == 0 { events.append(.level(min(1, level * 8))) }
            handle(gate.feed(level), &events)
            onHop(level)
            hops += 1
        }
        checkPhrase(ended: false, &events)
        return events
    }

    /// The last candidate phrase from its start, up to `seconds` long, for the second listen.
    func candidateAudio(seconds: Double) -> [Float] {
        guard let start = candidateStartSample.map({ max(dropped, $0) }), start < received else { return [] }
        let end = min(received, start + Int(ArisVoicePrint.sampleRate * seconds))
        return Array(audio[(start - dropped)..<(end - dropped)])
    }

    /// Everything from sample `from`, or with nil the latest phrase so far from just before it began: what the
    /// recognizer is handed first when it takes the microphone over, so no word after the name is lost.
    func audio(from: Int?) -> [Float] {
        let start = min(received, max(dropped, from ?? ((phraseStartSample ?? received) - Self.lead)))
        return Array(audio[(start - dropped)...])
    }

    /// The oldest sample still held.
    var oldestSample: Int { dropped }

    // MARK: - Stage 1

    private static func rms(_ audio: [Float], from: Int, count: Int) -> Float {
        var value: Float = 0
        audio.withUnsafeBufferPointer { vDSP_rmsqv($0.baseAddress! + from, 1, &value, vDSP_Length(count)) }
        return value
    }

    private mutating func handle(_ event: ArisVoiceGate.Event?, _ events: inout [Event]) {
        switch event {
        case .started(let frame):
            phraseStartSample = frame * ArisVoicePrint.hop
            checked = false
            voiceFrames = []
            voiceFrom = nil
            isVoice = false
            counts.phrases += 1
            if case .waiting = mode { events.append(.voice(true)) }
        case .ended(let from, let to):
            if case .training = mode {
                let start = max(dropped, from * ArisVoicePrint.hop - Self.lead)
                let end = min(received, to * ArisVoicePrint.hop + Self.lead)
                if end > start { events.append(.phrase(Array(audio[(start - dropped)..<(end - dropped)]))) }
            } else {
                checkPhrase(ended: true, &events)
                events.append(.voice(false))
            }
            phraseStartSample = nil
        case nil:
            break
        }
    }

    /// Waiting: the one look a new phrase gets. First whether it is a voice (decided within its first half second).
    /// Then, untrained, it is handed on at once; trained, the voice print is compared once enough of the phrase is in.
    private mutating func checkPhrase(ended: Bool, _ events: inout [Event]) {
        guard case .waiting(let model) = mode, !paused, !checked, let start = phraseStartSample else { return }
        let from = max(dropped, start - Self.lead)
        if !isVoice {
            switch voice(from: from, ended: ended) {
            case .wait: return
            case .notVoice:
                checked = true
                counts.notVoice += 1
                return
            case .voice: isVoice = true
            }
        }
        guard let model else { return hand(on: from, score: nil, sure: false, &events) }
        let needed = Int(Double(model.longestPrintSamples) * 1.6) + Self.lead
        guard ended || received - start >= needed else { return }
        let window = Array(audio[(from - dropped)..<min(audio.count, from - dropped + needed)])
        let score = model.score(ArisVoicePrint.features(window))
        counts.printChecks += 1
        lastScore = score
        guard score <= model.threshold else {
            checked = true
            return
        }
        hand(on: from, score: score, sure: score <= model.sure, &events)
    }

    private mutating func hand(on from: Int, score: Float?, sure: Bool, _ events: inout [Event]) {
        checked = true
        candidateStartSample = from
        counts.candidates += 1
        events.append(.candidate(score: score, sure: sure))
    }

    /// Whether the phrase that starts at `from` is a voice, reading only the frames that came in since the last look.
    private mutating func voice(from: Int, ended: Bool) -> ArisWakeVoice.Verdict {
        guard voiceCheck else { return .voice }
        // A phrase whose start has left the buffer (a long check held it back) is read again from what is left.
        if voiceFrom != from {
            voiceFrames = []
            voiceFrom = from
        }
        let hop = ArisWakeVoice.hop, length = ArisWakeVoice.frameLength
        audio.withUnsafeBufferPointer { all in
            while voiceFrames.count < Self.mostVoiceFrames {
                let begin = from + voiceFrames.count * hop - dropped
                guard begin >= 0, begin + length <= all.count else { break }
                voiceFrames.append(ArisWakeVoice.frame(UnsafeBufferPointer(rebasing: all[begin..<(begin + length)])))
            }
        }
        return ArisWakeVoice.verdict(voiceFrames, lead: Self.leadFrames, ended: ended)
    }
}
