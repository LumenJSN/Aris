//
//  ArisTalkKey.swift
//  Aris
//
//  ⌥Space works two ways. Hold it while you talk and let go to send, or tap it
//  and just talk: Aris sends once you pause (or when you tap it again).
//

import Foundation

enum ArisTalkKey {
    /// A press shorter than this is a tap.
    static let tapLimit: Duration = .milliseconds(350)
    /// Hands-free: a pause this long after your last word ends the turn. The recognizer
    /// reports about once a second, so this leaves room for a breath between sentences.
    static let pauseAfterWords: Duration = .milliseconds(2400)
    /// Hands-free: give up if nothing is said for this long.
    static let waitForWords: Duration = .seconds(8)
    /// After an answer Aris keeps listening this long for a follow-up, without the wake word.
    static let waitForFollowUp: Duration = .seconds(5)
    /// Hands-free: send even if you're still going. Three minutes: a long instruction is taken to its end (the turn's
    /// recording holds five, ArisLongTurn), and a room that never goes quiet still can't hold the microphone for good.
    static let longestTurn: Duration = .seconds(180)
    /// Hands-free: with no word at all by now the turn is over, whatever the microphone hears.
    static let longestWaitForWords: Duration = .seconds(15)

    /// Hands-free: the turn ends now, with no grace moment (audit voice-4). A room with a TV, music or other people
    /// talking never goes quiet, so the grace moment after the cap or the give-up always "heard you talk again" and the
    /// turn never ended. Up to `longestWaitForWords` the grace moment may still hold a turn without words (a voice that
    /// began just before the give-up is a turn starting; its words come about a second behind it).
    static func mustEnd(sinceStart: Duration, heardWords: Bool) -> Bool {
        sinceStart >= longestTurn || (!heardWords && sinceStart >= longestWaitForWords)
    }

    enum Press: Equatable { case start, finish, ignore }
    enum Release: Equatable { case finish, keepListening }

    static func press(listening: Bool, handsFree: Bool) -> Press {
        guard listening else { return .start }
        return handsFree ? .finish : .ignore
    }

    static func release(heldFor: Duration) -> Release {
        heldFor < tapLimit ? .keepListening : .finish
    }

    /// Hands-free: once there are words, this much quiet from the microphone ends the turn.
    /// It's quicker than waiting on the text, which runs about a second behind your voice, and long
    /// enough for a pause to think mid-sentence.
    static let pauseAfterVoice: Duration = .milliseconds(1400)
    /// The same two pauses when what you said already sounds finished ("내일 날씨 알려줘"; ArisEndpoint).
    /// 0.7 s cut the user off mid-request (2026-10-26).
    static let pauseAfterVoiceWhenComplete: Duration = .milliseconds(900)
    static let pauseAfterWordsWhenComplete: Duration = .milliseconds(1200)
    /// Quieter than this never counts as voice, however quiet the room.
    static let quietestVoice: Float = 0.06
    /// Voice is anything this many times louder than the room. (A share of the turn's loudest moment made
    /// soft speech count as silence after one loud word or click, and the turn ended mid-sentence.)
    static let voiceOverFloor: Float = 3
    /// The room's level before anything has been measured.
    static let startingFloor: Float = 0.04

    /// Hands-free: are you done talking? Each "since" is nil until that has happened. `complete`: the words
    /// so far sound like a finished sentence. `turnScore`: Smart Turn's chance that your voice sounds finished
    /// (ArisTurnDetector), nil until this pause has been scored. `hanging`: the words so far need more ("…열고").
    static func heardEnough(sinceStart: Duration, sinceLastWords: Duration?, sinceLastVoice: Duration? = nil,
                            waitForWords: Duration = waitForWords, complete: Bool = false,
                            turnScore: Float? = nil, hanging: Bool = false) -> Bool {
        if sinceStart >= longestTurn { return true }
        guard let quiet = sinceLastWords else { return sinceStart >= waitForWords }
        let (voicePause, wordsPause) = pauses(complete: complete, turnScore: turnScore, hanging: hanging)
        if let silence = sinceLastVoice, silence >= voicePause { return true }
        return quiet >= wordsPause
    }

    /// Smart Turn's verdicts: finished, unsure, or mid-thought ("음…", a breath between clauses). Measured on real
    /// Korean speech (Zeroth test set): 97% of finished sentences scored ≥ 0.7 and none < 0.3, but 30% of
    /// mid-sentence pauses also scored ≥ 0.7. So a finished-sounding voice only ends the turn quickly when the
    /// words agree; a mid-thought voice is trusted to wait longer.
    static let finishedScore: Float = 0.7
    static let unsureScore: Float = 0.3
    static let pauseWhenFinished: Duration = .milliseconds(500)
    static let pauseMidThought: Duration = .seconds(3)
    static let pauseMidThoughtWordsFinished: Duration = .seconds(2)

    /// How much quiet (voice, then text) ends the turn.
    private static func pauses(complete: Bool, turnScore: Float?, hanging: Bool) -> (voice: Duration, words: Duration) {
        if hanging { return (pauseMidThought, pauseMidThought) }
        guard let score = turnScore else {
            return complete ? (pauseAfterVoiceWhenComplete, pauseAfterWordsWhenComplete) : (pauseAfterVoice, pauseAfterWords)
        }
        if score >= finishedScore && complete { return (pauseWhenFinished, .seconds(1)) }
        if score >= unsureScore { return (pauseAfterVoice, pauseAfterWords) }
        return complete ? (pauseMidThoughtWordsFinished, pauseMidThoughtWordsFinished) : (pauseMidThought, pauseMidThought)
    }

    /// After an end that wasn't certain, Aris listens this much longer before asking anyone (the notch still shows
    /// listening, as ChatGPT's "listening intently" does). Whisper reads the turn meanwhile, so it costs ~0.15 s.
    static let graceAfterUnsureEnd: Duration = .milliseconds(600)
    /// Voice readings (~43 ms each) in the grace moment that mean you're talking again: ~0.2 s, more than a click.
    static let framesToResume = 4

    static func grace(confident: Bool) -> Duration { confident ? .zero : graceAfterUnsureEnd }

    static func resumedTalking(voiceFrames: Int) -> Bool { voiceFrames >= framesToResume }

    /// Both your voice (Smart Turn) and your words sound finished: the turn ends without the grace moment.
    static func isConfidentEnd(turnScore: Float?, complete: Bool, hanging: Bool) -> Bool {
        guard let turnScore else { return false }
        return turnScore >= finishedScore && complete && !hanging
    }

    /// Smart Turn reads 8 s at 16 kHz: the turn's last 8 s, silence in front when it's shorter.
    static let turnWindowSamples = 128_000

    static func turnWindow(_ samples: [Float]) -> [Float] {
        let tail = samples.suffix(turnWindowSamples)
        return [Float](repeating: 0, count: turnWindowSamples - tail.count) + tail
    }

    /// Is this microphone level you talking, measured against the room's own noise?
    static func isVoice(level: Float, floor: Float) -> Bool {
        level >= max(quietestVoice, floor * voiceOverFloor)
    }

    /// The room's noise level after one more reading: it follows quiet quickly and loud sounds slowly,
    /// so talking barely moves it but a fan that never stops does, eventually (as ArisVoiceGate does).
    static func nextFloor(_ floor: Float, level: Float) -> Float {
        level < floor ? floor * 0.8 + level * 0.2 : floor * 0.995 + level * 0.005
    }
}
