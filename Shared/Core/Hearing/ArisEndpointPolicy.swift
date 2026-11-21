//
//  ArisEndpointPolicy.swift
//  Aris (Shared/Core, Foundation only)
//
//  Has the user finished talking? One pure function of the pause so far: how long the voice has been quiet, how long
//  the words have not changed, Smart Turn's score for the pause and whether the words look finished or hanging. It says
//  keep listening, a plausible end (start the rest of the turn while the microphone keeps listening: the speculative
//  turn) or a firm end (commit).
//
//  Every waiting time lives in `rows`. The firm end of each case is never earlier than the end Aris used before the
//  speculative turn (`Row.before`: the old pause plus its 0.6 s grace moment), except where Smart Turn and the words
//  both say finished, which already ended without a grace moment. What changed is when the work starts: the old grace
//  moment is now the speculation window, and a confident pause starts it at 0.25 s instead of 0.5 s.
//

import Foundation

/// Where the end of a spoken turn stands.
enum ArisEndpointDecision: Int, Comparable, Sendable {
    case keepListening = 0, plausibleEnd, firmEnd

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The kinds of pause, each with its own waiting times (ArisEndpointPolicy.rows).
enum ArisEndpointCase: String, CaseIterable, Sendable {
    /// Smart Turn says finished (≥ 0.7) and the words look finished ("내일 날씨 알려줘").
    case confident
    /// Smart Turn says finished, the words don't (yet): 30% of mid-sentence pauses also score ≥ 0.7 (Zeroth test set).
    case finishedVoice
    /// Smart Turn is unsure (0.3 ..< 0.7).
    case unsure
    /// Smart Turn says mid-thought (< 0.3): real finished sentences never scored this low.
    case midThought
    /// Smart Turn says mid-thought but the words look finished.
    case midThoughtWordsFinished
    /// The words so far need more ("엑셀 네 개 열고"), whatever the voice says.
    case hanging
    /// Not scored (yet, or the model can't run), the words look finished.
    case noScoreComplete
    /// Not scored, the words don't look finished.
    case noScore
    /// No word heard yet.
    case noWords
}

/// The pause so far. Each "since" is nil until that has happened.
struct ArisEndpointInput: Equatable, Sendable {
    var sinceStart: Duration
    var sinceVoice: Duration?
    var sinceWords: Duration?
    var score: Float?
    var complete = false
    var hanging = false
    var waitForWords: Duration = ArisEndpointPolicy.Caps.standard.waitForWords
    var caps = ArisEndpointPolicy.Caps.standard
}

enum ArisEndpointPolicy {
    /// Smart Turn's verdicts (as ArisTalkKey measured them on real Korean speech).
    static let finishedScore: Float = 0.7
    static let unsureScore: Float = 0.3
    /// The old grace moment after an unsure end. Now the speculation window of every unsure case.
    static let window: Duration = .milliseconds(600)
    /// Voice readings (~43 ms each) after a plausible end that mean the user is talking again: ~0.2 s, more than a
    /// click (ArisTalkKey.framesToResume).
    static let framesToResume = 4

    /// The hard limits of a hands-free turn (ArisTalkKey keeps the app's copies; a test holds them equal).
    struct Caps: Equatable, Sendable {
        /// Give up if nothing is said for this long.
        var waitForWords: Duration
        /// Send even if the user is still going.
        var longestTurn: Duration
        /// With no word at all by now the turn is over, whatever the microphone hears.
        var longestWaitForWords: Duration

        static let standard = Caps(waitForWords: .seconds(8), longestTurn: .seconds(180), longestWaitForWords: .seconds(15))
    }

    /// Quiet needed on the voice (level) clock and on the words clock; whichever comes first counts. The words clock
    /// runs about a second behind the voice and only matters where the room never goes quiet.
    struct Wait: Equatable, Sendable {
        let voice: Duration
        let words: Duration
    }

    struct Row: Equatable, Sendable {
        /// The request may go out now; the microphone keeps listening.
        let plausible: Wait
        /// The turn is over.
        let firm: Wait
        /// When Aris committed before (the old pause on the voice clock, plus the 0.6 s grace moment when the end
        /// wasn't confident): the firm end is never earlier, except for `confident`, whose old end it keeps.
        let before: Duration
    }

    static func row(_ endCase: ArisEndpointCase) -> Row {
        func ms(_ value: Int) -> Duration { .milliseconds(value) }
        switch endCase {
        case .confident:
            // Request at 0.25 s: Smart Turn scores at 0.2 s and takes ~4 ms. Commit where it always did (0.5 s).
            return Row(plausible: Wait(voice: ms(250), words: ms(600)), firm: Wait(voice: ms(500), words: ms(1000)), before: ms(500))
        case .finishedVoice:
            // The voice sounds finished, so the request goes early (0.8 s); the commit waits as long as before.
            return Row(plausible: Wait(voice: ms(800), words: ms(2400)), firm: Wait(voice: ms(2000), words: ms(3000)), before: ms(2000))
        case .unsure, .noScore:
            return Row(plausible: Wait(voice: ms(1400), words: ms(2400)), firm: Wait(voice: ms(2000), words: ms(3000)), before: ms(2000))
        case .noScoreComplete:
            return Row(plausible: Wait(voice: ms(900), words: ms(1200)), firm: Wait(voice: ms(1500), words: ms(1800)), before: ms(1500))
        case .midThoughtWordsFinished:
            return Row(plausible: Wait(voice: ms(2000), words: ms(2000)), firm: Wait(voice: ms(2600), words: ms(2600)), before: ms(2600))
        case .midThought, .hanging:
            return Row(plausible: Wait(voice: ms(3000), words: ms(3000)), firm: Wait(voice: ms(3600), words: ms(3600)), before: ms(3600))
        case .noWords:
            // Measured on the turn's own clock (`waitForWords`); the window is quiet on the voice clock after it.
            return Row(plausible: Wait(voice: .zero, words: .zero), firm: Wait(voice: window, words: window), before: window)
        }
    }

    static func endCase(score: Float?, complete: Bool, hanging: Bool, heardWords: Bool = true) -> ArisEndpointCase {
        guard heardWords else { return .noWords }
        if hanging { return .hanging }
        guard let score else { return complete ? .noScoreComplete : .noScore }
        if score >= finishedScore { return complete ? .confident : .finishedVoice }
        if score >= unsureScore { return .unsure }
        return complete ? .midThoughtWordsFinished : .midThought
    }

    /// The decision for this pause, and which case it is.
    static func decide(_ input: ArisEndpointInput) -> (decision: ArisEndpointDecision, endCase: ArisEndpointCase) {
        let heardWords = input.sinceWords != nil
        let endCase = endCase(score: input.score, complete: input.complete, hanging: input.hanging, heardWords: heardWords)
        // The caps come first: a room that never goes quiet can't hold the turn open (audit voice-4).
        if mustEnd(input) { return (.firmEnd, endCase) }
        guard let sinceWords = input.sinceWords else {
            guard input.sinceStart >= input.waitForWords else { return (.keepListening, endCase) }
            let quiet = input.sinceVoice.map { $0 >= window } ?? true
            return (quiet ? .firmEnd : .plausibleEnd, endCase)
        }
        let row = row(endCase)
        func reached(_ wait: Wait) -> Bool {
            if let voice = input.sinceVoice, voice >= wait.voice { return true }
            return sinceWords >= wait.words
        }
        if reached(row.firm) { return (.firmEnd, endCase) }
        if reached(row.plausible) { return (.plausibleEnd, endCase) }
        return (.keepListening, endCase)
    }

    /// The cap, or no word in the longest wait: over now, whatever the room sounds like.
    static func mustEnd(_ input: ArisEndpointInput) -> Bool {
        input.sinceStart >= input.caps.longestTurn || (input.sinceWords == nil && input.sinceStart >= input.caps.longestWaitForWords)
    }

    /// How long until `decide` could change with no new event (no voice, no words, no score): when a timer armed in a
    /// pause should look again. Nil when nothing is left to wait for.
    static func untilChange(_ input: ArisEndpointInput) -> Duration? {
        var waits: [Duration] = [input.caps.longestTurn - input.sinceStart]
        if let sinceWords = input.sinceWords {
            let row = row(endCase(score: input.score, complete: input.complete, hanging: input.hanging))
            for wait in [row.plausible, row.firm] {
                waits.append(wait.words - sinceWords)
                if let voice = input.sinceVoice { waits.append(wait.voice - voice) }
            }
        } else {
            waits.append(input.waitForWords - input.sinceStart)
            waits.append(input.caps.longestWaitForWords - input.sinceStart)
            if let voice = input.sinceVoice { waits.append(window - voice) }
        }
        return waits.filter { $0 > .zero }.min()
    }
}
