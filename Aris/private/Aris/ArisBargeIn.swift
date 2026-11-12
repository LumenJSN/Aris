//
//  ArisBargeIn.swift
//  Aris
//
//  In a conversation, the user's voice on the wake detector's 10 ms hops (raw RMS) decides two things:
//  - Between turns, voice starts the next turn.
//  - While Aris talks, voice stops it and Aris listens (barge-in).
//  With headphones, the mic hears only the user, so a plain voice gate is enough: ~150 ms of it stops Aris.
//  Through the Mac's speakers, the mic also hears Aris itself. Voice then has to stand clearly above the echo,
//  4× (12 dB) over what Aris's own output, as the speaker measures it, makes the mic hear, for 300 ms. The echo's
//  strength is learned from the hops where only Aris plays: up fast, down slowly, and never from a hop well over it
//  (that may be the user), so it errs toward a louder echo. The output is the peak of the last 250 ms, so the room's
//  delay and tail are covered. There is no echo canceller: talking softly over a loud
//  Aris won't stop it, but talking in its pauses or clearly over it will.
//

import Foundation

struct ArisBargeIn: Equatable {
    enum Mode: Equatable {
        /// Listening between turns: nothing plays.
        case between
        case headphones
        case speakers
    }

    /// Frames are 10 ms.
    static let framesBetween = 10
    static let framesHeadphones = 15
    static let framesSpeakers = 30
    /// Dips this long inside speech (a consonant, a breath) don't break the run.
    static let allowedGap = 3
    /// Voice must be this many times the echo (12 dB).
    static let echoMargin: Float = 4
    /// The playback peak covers this many frames (the room's delay and tail).
    static let echoWindow = 25
    /// Quieter than this is never voice (ArisVoiceGate's own floor).
    static let quietestVoice: Float = 0.01
    static let overFloor: Float = 4
    /// The echo's strength before anything is learned: the mic hears Aris as loud as it plays (cautious).
    static let startingEchoGain: Float = 1
    /// How fast the echo's strength rises to a louder hop (~0.1 s) and falls to a quieter one (~1 s).
    static let echoUp: Float = 0.1
    static let echoDown: Float = 0.01
    /// A hop more than this many times the echo so far (but not yet voice) may be the user, not the room. It raises the
    /// echo only when such hops keep a steady ratio to the output (M3): a real jump in the echo (the volume turned up)
    /// follows Aris's own loudness, while the user's voice doesn't, so their never teaches the echo.
    static let echoLearnZone: Float = 1.5
    /// Hops over the zone it looks at, and how steady their ratio must be (spread / mean).
    static let steadyHops = 20
    static let steadySpread: Float = 0.25
    /// Between turns the turn's audio starts this much before the voice run, for a soft first syllable (nothing plays
    /// then); over Aris it starts where the voice did, so less of Aris's own voice reaches the recognizer.
    static let leadBetween = 0.25
    /// Output quieter than this is silence: no echo to learn from.
    static let silentPlayback: Float = 0.002

    /// Headphones or the Mac's speakers; nil when barge-in is off on speakers (the setting).
    static func mode(headphones: Bool, speakersAllowed: Bool) -> Mode? {
        headphones ? .headphones : speakersAllowed ? .speakers : nil
    }

    let mode: Mode
    private(set) var floor: Float = 0.005
    private(set) var echoGain: Float = startingEchoGain
    private var recentPlayback: [Float] = []
    private var run = 0
    private var gap = 0
    private var frame = 0
    /// The ratios of the latest run of hops over the learning zone.
    private var overZone: [Float] = []
    private var runStart = 0
    private(set) var fired = false
    /// Once fired: seconds before now that the voice run began (plus the lead between turns), where the turn starts.
    private(set) var lookback: Double = 0

    /// `floor`: the room's level as the last watch left it (a fan learned once stays learned).
    init(mode: Mode, floor: Float = 0.005) {
        self.mode = mode
        self.floor = floor
    }

    var framesNeeded: Int {
        switch mode {
        case .between: Self.framesBetween
        case .headphones: Self.framesHeadphones
        case .speakers: Self.framesSpeakers
        }
    }

    /// One hop: the mic's RMS and the speaker's output RMS. True once, the hop the voice is sure.
    mutating func feed(mic: Float, playback: Float) -> Bool {
        recentPlayback.append(playback)
        if recentPlayback.count > Self.echoWindow { recentPlayback.removeFirst(recentPlayback.count - Self.echoWindow) }
        let peak = mode == .speakers ? recentPlayback.max() ?? 0 : 0
        let voice = mic > threshold(playbackPeak: peak)
        learn(mic: mic, playbackPeak: peak, voice: voice)
        defer { frame += 1 }
        if voice {
            if run == 0 { runStart = frame }
            run += 1
            gap = 0
        } else if run > 0 {
            gap += 1
            if gap > Self.allowedGap {
                run = 0
                gap = 0
            }
        }
        guard !fired, run >= framesNeeded else { return false }
        fired = true
        lookback = Double(frame - runStart + 1) * 0.01 + (mode == .between ? Self.leadBetween : 0)
        return true
    }

    /// What the mic must exceed to be the user: above the room, and on speakers clearly above Aris's echo.
    func threshold(playbackPeak: Float) -> Float {
        max(Self.quietestVoice, floor * Self.overFloor, echoGain * playbackPeak * Self.echoMargin)
    }

    private mutating func learn(mic: Float, playbackPeak: Float, voice: Bool) {
        // The room: down quickly, up slowly (ArisVoiceGate's rule); a sound that never stops (a fan) creeps in too,
        // over a second or two, while a few seconds of talking barely move it.
        if mic < floor * Self.overFloor {
            floor = mic < floor ? floor * 0.9 + mic * 0.1 : floor * 0.99 + mic * 0.01
        } else {
            floor = floor * 0.999 + mic * 0.001
        }
        // The echo only from hops that aren't the user.
        guard !voice, mode == .speakers, playbackPeak > Self.silentPlayback else { return }
        let ratio = mic / playbackPeak
        if ratio <= echoGain {
            echoGain = echoGain * (1 - Self.echoDown) + ratio * Self.echoDown
        } else if ratio <= echoGain * Self.echoLearnZone {
            echoGain = echoGain * (1 - Self.echoUp) + ratio * Self.echoUp
        } else {
            overZone = Array((overZone + [ratio]).suffix(Self.steadyHops))
            guard overZone.count == Self.steadyHops else { return }
            let mean = overZone.reduce(0, +) / Float(overZone.count)
            let spread = (overZone.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(overZone.count)).squareRoot()
            if spread / mean < Self.steadySpread { echoGain = echoGain * (1 - Self.echoUp) + mean * Self.echoUp }
            return
        }
        overZone = []
    }
}
