//
//  ArisEndpointDriver.swift
//  Aris (Shared/Core, Foundation only)
//
//  The hands-free turn's end, driven by events (each voice reading, new words, Smart Turn's score, a timer armed only
//  in a pause) instead of a 200 ms poll. It runs ArisEndpointPolicy and keeps the speculative turn's state:
//
//  - listening → plausible end: `.speculate(id)`. The microphone keeps listening; the app finalises the transcript
//    and may send the request (ArisHeldStream holds its replies). While pending, the pause is measured from where it
//    was when the end became plausible, so a click or a breath (fewer than `framesToResume` voice readings) does not
//    restart it, as the old grace moment did.
//  - voice resumes (≥ `framesToResume` readings) before anything irreversible: `.cancel(id)` and back to listening;
//    the same utterance goes on and its words are joined (the recogniser and the recording never stopped).
//  - firm end: `.commit(id)`. A reply that may have acted (a step, a card) also commits at once: it can't be cancelled.
//
//  Times are Durations since the turn began listening, so the tests can play a turn without a clock.
//

import Foundation

/// What the request's stream said, for the speculative turn: `inert` changes nothing, `output` would be seen or heard
/// (held until the turn commits), `action` may have done something (a step started, a card is up): no cancel after it.
enum ArisReplyKind: Equatable, Sendable { case inert, output, action }

struct ArisEndpointDriver: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case listening
        /// A plausible end; `id` names its speculation.
        case pending(id: Int)
        case committed
    }

    enum Effect: Equatable, Sendable {
        /// Finalise the transcript and (when the request may go early) send it, still listening.
        case speculate(id: Int)
        /// The user talked again: drop that speculation (its request, if any) and listen on.
        case cancel(id: Int)
        /// The turn is over; `id` is the speculation it commits (nil: none ran).
        case commit(id: Int?)
    }

    /// One look at the turn: `now` and the last voice and words, as times since the turn began.
    struct Snapshot: Equatable, Sendable {
        var now: Duration
        /// This reading is voice.
        var voiceNow = false
        var lastVoice: Duration?
        var lastWords: Duration?
        var score: Float?
        var complete = false
        var hanging = false
    }

    var waitForWords: Duration = ArisEndpointPolicy.Caps.standard.waitForWords
    var caps = ArisEndpointPolicy.Caps.standard

    private(set) var phase = Phase.listening
    private(set) var lastId = 0
    /// Speculations started and cancelled this turn (turns.jsonl).
    private(set) var speculations = 0
    private(set) var cancellations = 0
    /// The pending speculation's request said something that may have acted.
    private(set) var locked = false
    private(set) var lastCase = ArisEndpointCase.noWords
    private var resumeFrames = 0
    private var anchor: (voice: Duration?, words: Duration?)?

    init(waitForWords: Duration = ArisEndpointPolicy.Caps.standard.waitForWords, caps: ArisEndpointPolicy.Caps = .standard) {
        self.waitForWords = waitForWords
        self.caps = caps
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.phase == rhs.phase && lhs.lastId == rhs.lastId && lhs.speculations == rhs.speculations && lhs.cancellations == rhs.cancellations
            && lhs.locked == rhs.locked && lhs.resumeFrames == rhs.resumeFrames
    }

    var pendingId: Int? {
        if case .pending(let id) = phase { return id }
        return nil
    }

    /// The policy's input for this snapshot: while pending, the pause as it stood at the plausible end.
    func input(_ snapshot: Snapshot) -> ArisEndpointInput {
        let voice = anchor.map { $0.voice } ?? snapshot.lastVoice
        let words = anchor.flatMap { $0.words } ?? snapshot.lastWords
        return ArisEndpointInput(sinceStart: snapshot.now, sinceVoice: voice.map { snapshot.now - $0 }, sinceWords: words.map { snapshot.now - $0 },
                                 score: snapshot.score, complete: snapshot.complete, hanging: snapshot.hanging,
                                 waitForWords: waitForWords, caps: caps)
    }

    /// Every voice reading, new words, a score or the pause timer.
    mutating func observe(_ snapshot: Snapshot) -> [Effect] {
        guard phase != .committed else { return [] }
        var effects: [Effect] = []
        if case .pending(let id) = phase, snapshot.voiceNow {
            resumeFrames += 1
            if resumeFrames >= ArisEndpointPolicy.framesToResume, !locked { effects.append(dropPending(id)) }
        }
        let (decision, endCase) = ArisEndpointPolicy.decide(input(snapshot))
        lastCase = endCase
        switch (phase, decision) {
        case (.listening, .plausibleEnd):
            lastId += 1
            speculations += 1
            phase = .pending(id: lastId)
            anchor = (snapshot.lastVoice, snapshot.lastWords)
            resumeFrames = 0
            locked = false
            effects.append(.speculate(id: lastId))
        case (.listening, .firmEnd):
            phase = .committed
            effects.append(.commit(id: nil))
        case (.pending(let id), .firmEnd):
            phase = .committed
            effects.append(.commit(id: id))
        case (.pending(let id), .keepListening):
            // The words turned hanging under it (the recogniser caught up): this is no end after all.
            if !locked { effects.append(dropPending(id)) }
        default:
            break
        }
        return effects
    }

    /// What the speculation's request said. An action commits the turn at once: it can't be taken back.
    mutating func reply(_ kind: ArisReplyKind, id: Int) -> [Effect] {
        guard case .pending(let pending) = phase, pending == id, kind == .action else { return [] }
        locked = true
        phase = .committed
        return [.commit(id: id)]
    }

    /// The key was pressed again, or the turn has to end now for another reason.
    mutating func finish() -> [Effect] {
        switch phase {
        case .committed: return []
        case .listening:
            phase = .committed
            return [.commit(id: nil)]
        case .pending(let id):
            phase = .committed
            return [.commit(id: id)]
        }
    }

    /// When a timer armed in this pause should look again.
    func untilChange(_ snapshot: Snapshot) -> Duration? {
        ArisEndpointPolicy.untilChange(input(snapshot))
    }

    /// Looked at again when nothing else is due.
    static let fallbackLook: Duration = .milliseconds(250)

    /// The look after this one, armed on every look, a voice reading too: if the audio feed stops (a stalled device, a
    /// route change), no reading comes to look again, and the firm end, the first-words wait and the 180 s cap would
    /// never fire. Readings that keep coming re-arm it first. Nil once the turn is over.
    func nextLook(_ snapshot: Snapshot) -> Duration? {
        guard phase != .committed else { return nil }
        return untilChange(snapshot) ?? Self.fallbackLook
    }

    private mutating func dropPending(_ id: Int) -> Effect {
        phase = .listening
        anchor = nil
        resumeFrames = 0
        cancellations += 1
        return .cancel(id: id)
    }
}
