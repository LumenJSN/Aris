//
//  ArisVoiceGate.swift
//  Aris
//
//  Says when someone starts and stops talking, from the microphone's loudness every
//  10 ms. It's the only thing that runs while Aris waits for "아리스": nothing
//  else looks at the audio until a phrase starts after a quiet moment.
//  The room is two numbers: the quietest 10 ms of the last two seconds, which a fan or a cooker hood sets within two
//  seconds while speech (whose gaps between words drop back to the room) never does, and the old average of the quiet
//  frames. Talking is 2.5 times the first and twice the second: over a steady hood a voice about 6 dB above it counts
//  (it had to be 12 dB above it before: four times an average the hood itself had pushed up).
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

    /// Talking is this many times the room's quietest moment, and `overAverage` times its quiet average.
    static let overQuietest: Float = 2.5
    static let overAverage: Float = 2
    /// Quieter than this is never talking, however quiet the room.
    static let quietestTalk: Float = 0.01
    /// The quietest moment is looked for over `blocks` blocks of `blockFrames` (two seconds).
    static let blockFrames = 50
    static let blocks = 4

    private var floor: Float = 0.005
    /// The quietest frame of each of the last `blocks` blocks, and of the one filling now.
    private var blockLows: [Float] = Array(repeating: 0.005, count: ArisVoiceGate.blocks)
    private var blockLow: Float = .greatestFiniteMagnitude
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
        noteQuietest(level)
        let loud = level > line
        // The average follows the quiet frames: down quickly, up slowly. A sound that never stops (a fan, a hum) is
        // taken in by the quietest moment within two seconds; from then on it is quiet, and the average follows it too.
        if !loud {
            floor = level < floor ? floor * 0.9 + level * 0.1 : floor * 0.99 + level * 0.01
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

    /// The room's quietest 10 ms in the last two seconds (the blocks held, and the one filling).
    var quietest: Float { min(blockLow, blockLows.min() ?? blockLow) }

    /// The loudness talking must pass now.
    var line: Float { max(Self.quietestTalk, quietest * Self.overQuietest, floor * Self.overAverage) }

    private mutating func noteQuietest(_ level: Float) {
        blockLow = min(blockLow, level)
        guard (frame + 1) % Self.blockFrames == 0 else { return }
        blockLows = Array(blockLows.dropFirst()) + [blockLow]
        blockLow = .greatestFiniteMagnitude
    }
}
