//
//  ArisAudioQuiet.swift
//  Aris
//
//  When Aris's own audio lets go of the Mac's audio device. The voice's output engine stops soon after the voice
//  ends: left running, it kept Aris in the built-in speakers' IO cycle for the rest of the session (silence, and a
//  level tap hopping to the main thread ~47 times a second; one context ran 2027 s, until Aris quit, on 2026-11-05),
//  next to whatever else was playing. And the wake word's microphone, when its configuration keeps changing, reopens
//  after a growing pause instead of every second: macOS runs it as an aggregate clocked by the built-in speakers, so
//  each reopen starts and stops their IO too. Pure, so the policy is tested without audio hardware.
//

import Foundation

enum ArisAudioQuiet {
    /// How long after the voice ends its engine keeps running (a reply right after reuses it).
    static let speakerIdle: Duration = .seconds(2)

    /// Stop the voice's engine now? `scheduledFor`: the speak() generation the stop was scheduled in; `current`: the
    /// generation now; `voicePending`: a voice is still waiting to finish.
    static func mayStopSpeaker(scheduledFor: Int, current: Int, voicePending: Bool) -> Bool {
        scheduledFor == current && !voicePending
    }

    /// The first pause before the wake word's microphone reopens after a change.
    static let firstWakeRestart: Duration = .seconds(1)
    /// The longest pause between reopens while the changes keep coming.
    static let longestWakeRestart: Duration = .seconds(60)
    /// A microphone that ran this long before a change starts the count again.
    static let settledWake: Duration = .seconds(30)

    /// Reopens in a row, counting this one. `ranFor`: how long the microphone ran before this change (nil: unknown).
    static func wakeRestarts(after previous: Int, ranFor: Duration?) -> Int {
        guard let ranFor, ranFor < settledWake else { return 1 }
        return max(0, previous) + 1
    }

    /// The wake word's microphone couldn't open at all (no input device yet, audio not ready after login): counted as
    /// a reopen that ran for no time, so the tries back off the same way, a second to a minute apart, until it opens
    /// (audit voice-11: it was never tried again until the next turn ended).
    static func wakeRestarts(afterFailedOpen previous: Int) -> Int { wakeRestarts(after: previous, ranFor: .zero) }

    /// The pause before reopen number `restarts`: 1 s, doubling, at most a minute.
    /// The wake microphone came back after a change: while Aris talks (not asking), it comes back as the barge-in
    /// watch; otherwise it waits for the wake word, which only listens when idle (bug hunt 11-06 #11: the barge-in
    /// died at the start of an answer and stayed dead until it ended).
    static func restartArmsBargeIn(speaking: Bool, asking: Bool) -> Bool { speaking && !asking }

    static func wakeRestartDelay(restarts: Int) -> Duration {
        let doublings = min(max(restarts, 1) - 1, 6)
        return min(firstWakeRestart * (1 << doublings), longestWakeRestart)
    }
}

/// How far one speak()'s buffers have played, by its generation: `player.stop()` fires every pending completion, and
/// those reach the main queue after the next speak() started, so a completion from another generation never counts
/// (bug hunt 11-06 #9: the next voice ended early, or waited out the 40 s timeout).
struct ArisVoiceProgress: Equatable {
    private(set) var generation = 0
    private(set) var scheduled = 0
    private(set) var played = 0
    private(set) var written = false

    /// A speak() of `generation` starts playing: nothing scheduled, played or sent yet.
    mutating func start(_ generation: Int) {
        self = ArisVoiceProgress()
        self.generation = generation
    }

    mutating func schedule() { scheduled += 1 }

    /// A buffer of `generation` finished playing. True when this voice is done.
    mutating func played(_ generation: Int) -> Bool {
        guard generation == self.generation else { return false }
        played += 1
        return isDone
    }

    /// The voice sent everything. True when it's done.
    mutating func wroteAll() -> Bool {
        written = true
        return isDone
    }

    var isDone: Bool { written && played == scheduled }
}
