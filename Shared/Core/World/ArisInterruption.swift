//
//  ArisInterruption.swift
//  Aris
//
//  The one rule for when Aris may speak up on its own (ARCHITECTURE.md 3.5). Everything it wants to tell unasked (a
//  job's result, a teammate's question, a deadline, a timer, the morning brief, an update, its own news, a problem)
//  asks here with what it is and the world as it is now, and is told: say it now, show it on the pill without a
//  sound, hold it until something ends (the user's voice, Aris's own, a call, the lock), or drop it.
//
//  Today's behaviour is the baseline (ArisController.notify, ArisNoticeGate, ArisQuietGate): a notice waits for a
//  pause and for the notch to be free, comes up, and its line is said unless Aris is muted, in quiet hours or the
//  screen is away. On top of that: nothing starts while the user is talking, even before a wake word was heard (an
//  announcement used to start over "아리스, ..."); nothing comes up while the screen is away, where no one sees it
//  (it waits for the unlock instead of using up its time on a locked screen); in a call nothing is said, and what can
//  wait waits for the call to end; the brief, which has nothing to say or comes into a call, no longer opens the notch.
//  Foundation only.
//

import Foundation

enum ArisInterruption {
    enum Kind: String, CaseIterable, Sendable {
        /// The answer to a question the user is waiting on.
        case answer
        case jobDone
        /// A teammate (or a job) asks the user something.
        case teammateAsks
        case deadline
        case timer
        case brief
        case update
        /// Aris's own word about itself or something it noticed.
        case news
        /// Something is wrong and needs the user (the helper is down, a permission is missing).
        case problem
    }

    enum Urgency: Int, Comparable, Sendable {
        case low, normal, high
        static func < (lhs: Urgency, rhs: Urgency) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// What Aris wants to say.
    struct Want: Equatable, Sendable {
        var kind: Kind
        var urgency: Urgency = .normal
        /// The user is asked something and the question waits for them.
        var needsAnswer = false
        /// There is a line to say aloud (most notices only show).
        var spoken = false
        /// There is nothing in it (a brief with nothing to tell).
        var empty = false
    }

    enum Condition: String, Equatable, Sendable {
        case userStopsSpeaking, arisStopsSpeaking, callEnds, unlock
    }

    enum Decision: Equatable, Sendable {
        case speak
        /// On the pill (or, for the brief, its tiles in the notch), without a sound.
        case show
        case hold(Condition)
        case drop

        /// It may come up now (said or not).
        var comesUp: Bool { self == .speak || self == .show }
    }

    /// The world as the policy needs it.
    struct Moment: Equatable, Sendable {
        var screenAway = false
        /// Another app has a microphone open: a call, most likely.
        var inCall = false
        var userSpeaking = false
        var arisSpeaking = false
        /// Music or a video plays.
        var otherAudio = false
        var headphones = false
        /// Aris may make a sound on its own: not muted, not in quiet hours (ArisQuietGate).
        var mayMakeSound = true
    }

    static func moment(_ world: ArisWorldSnapshot, now: Double, mayMakeSound: Bool) -> Moment {
        Moment(screenAway: world.screenAway, inCall: world.otherAppRecording != nil, userSpeaking: world.userSpeaking(now: now),
               arisSpeaking: world.arisSpeaking, otherAudio: world.otherAudioPlaying,
               headphones: world.audio?.output.isHeadphones ?? false, mayMakeSound: mayMakeSound)
    }

    static func decide(_ want: Want, _ moment: Moment) -> Decision {
        if want.empty { return .drop }
        // Nobody would see it: it waits for the unlock rather than using up its time on a locked screen.
        if moment.screenAway { return .hold(.unlock) }
        // Never over the user, never over itself.
        if moment.userSpeaking { return .hold(.userStopsSpeaking) }
        if moment.arisSpeaking { return .hold(.arisStopsSpeaking) }
        if moment.inCall {
            // Nothing is said into a call. What cannot wait shows quietly; the rest (the brief's open notch above
            // all, and anything a shared screen would show) waits for the call to end.
            if want.kind == .brief { return .hold(.callEnds) }
            return mayWaitOutACall(want) ? .hold(.callEnds) : .show
        }
        guard want.spoken, want.kind != .brief, moment.mayMakeSound else { return .show }
        // Low news does not pause the music to be said.
        if moment.otherAudio, want.urgency == .low { return .show }
        return .speak
    }

    /// What can wait for a call to end: neither urgent, nor a question that waits for the user, nor their own answer.
    static func mayWaitOutACall(_ want: Want) -> Bool {
        want.urgency < .high && !want.needsAnswer && want.kind != .answer
    }
}
