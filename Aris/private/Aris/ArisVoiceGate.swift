//
//  ArisVoiceGate.swift
//  Aris
//
//  Says when someone starts and stops talking, from the microphone's loudness every
//  10 ms. It's the only thing that runs while Aris waits for "아리스": nothing
//  else looks at the audio until a phrase starts after a quiet moment.
//

import Foundation

struct ArisVoiceGate {
    enum Event: Equatable {
        /// Talking started at this frame, after a quiet moment.
        case started(atFrame: Int)
        /// The phrase that started at `fromFrame` ended at `toFrame` (a pause).
        case ended(fromFrame: Int, toFrame: Int)
    }

    /// Frames are 10 ms.
    static let framesToStart = 5
    /// A dip this short inside a start does not break it: a voice from across the room hovers around the line, and
    /// one frame under it used to throw the whole word away (the quiet moment had to begin again).
    static let dipInStart = 2
    static let quietBeforeStart = 30
    static let pauseToEnd = 30
    static let longestPhrase = 1000

    private var floor: Float = 0.005
    private var frame = 0
    private var quietRun = 0
    private var loudRun = 0
    /// Where the loud run that may become a phrase began, and the frames under the line since its last loud one.
    private var runStart = 0
    private var dip = 0
    private var phraseStart: Int?

    /// Feeds one frame's loudness (RMS); returns what happened, if anything.
    mutating func feed(_ level: Float) -> Event? {
        defer { frame += 1 }
        let loud = level > max(0.01, floor * 4)
        // The floor follows the room: down quickly, up slowly. A sound that never stops (a fan, a hum)
        // pulls it up too, until that sound counts as quiet.
        if !loud {
            floor = level < floor ? floor * 0.9 + level * 0.1 : floor * 0.99 + level * 0.01
        } else if phraseStart == nil {
            floor = floor * 0.995 + level * 0.005
        }
        guard let start = phraseStart else {
            if loud {
                if loudRun == 0 { runStart = frame }
                loudRun += 1
                dip = 0
                if loudRun >= Self.framesToStart && quietRun >= Self.quietBeforeStart {
                    phraseStart = runStart
                    quietRun = 0
                    return .started(atFrame: runStart)
                }
            } else if loudRun > 0 && loudRun < Self.framesToStart && dip < Self.dipInStart {
                dip += 1
            } else {
                if loudRun > 0 && loudRun < Self.framesToStart { quietRun = 0 }
                loudRun = 0
                dip = 0
                quietRun += 1
            }
            return nil
        }
        quietRun = loud ? 0 : quietRun + 1
        if quietRun >= Self.pauseToEnd || frame - start >= Self.longestPhrase {
            phraseStart = nil
            loudRun = 0
            return .ended(fromFrame: start, toFrame: frame - quietRun + 1)
        }
        return nil
    }
}
