//
//  ArisWakeStrict.swift
//  Aris
//
//  The wake word over music (the owner, 2026-11-15, their music playing on this Mac, 18:11–18:28): their own calls scored 9.11,
//  9.82, 10.92 and 12.29 against his voice print; the music's false wakes 14.78 and up (15.00, 16.27 and 16.34 woke
//  Aris). Whisper is prompted with the name and, over lyrics with nothing like it, writes "아리스" anyway, so its text is
//  no evidence there: over this Mac's real playback (ArisOtherAudio.macPlays) only a voice print within half the
//  threshold (13.42 for the user's model, between the two) wakes Aris, the text path never does, and Whisper can only
//  veto (ArisWakeEvidence). Over music the room plays (ArisWakeMusic) the text path doesn't wake either, and a
//  borderline wake needs the same strong print. Nothing playing: everything as before. A wake that passes is the user's, so
//  the music is paused only once it is kept (its lap heard), never while its evidence waits.
//  Without a voice print (the name not trained) there is no print to lean on, and the strict rule made Aris deaf
//  whenever anything played (2026-11-18 audit). Over playback or music an untrained call now wakes Aris only when the
//  two listeners each heard the name on their own, as a call at the start and in its exact spelling: the recognizer
//  (not prompted with the name) and Whisper (prompted, so alone it is no evidence there). Lyrics that Whisper turns into
//  "아리스" are not enough; a song or a video that itself says "아리스" at a phrase's start still could be, and only the
//  echo checks (Aris's own voice) and the trained print rule out more. Without Whisper on the Mac it still can't wake. Pure.
//

import Foundation

enum ArisWakeStrict {
    /// The playback line as a share of the voice print's threshold: between the borderline cut (0.4) and the sure line (0.6).
    static let playbackFraction: Float = 0.5

    /// The farthest a print may be over real playback; nil without a voice print.
    static func playbackLine(threshold: Float?) -> Float? {
        threshold.map { $0 * playbackFraction }
    }

    /// The print is close enough to be the user's over music.
    static func isStrong(score: Float?, threshold: Float?) -> Bool {
        guard let score, let line = playbackLine(threshold: threshold) else { return false }
        return score <= line
    }

    /// Whether a candidate may go on to be checked at all: over real playback only a strong print, or, untrained, the
    /// two listeners' check (`textWakes`).
    static func admits(playing: Bool, score: Float?, threshold: Float?) -> Bool {
        !playing || threshold == nil || isStrong(score: score, threshold: threshold)
    }

    /// Whether the text heard so far (no sure print) wakes Aris: `recognizer` and `whisper` say whether each heard the
    /// name. In a quiet room either does; over music or playback never with a trained print (only a strong print wakes
    /// it then), and untrained only both.
    static func textWakes(trained: Bool, music: Bool, playing: Bool, recognizer: Bool, whisper: Bool) -> Bool {
        guard music || playing else { return recognizer || whisper }
        return !trained && recognizer && whisper
    }

    /// The music is paused once the wake is kept: its lap heard (a borderline one's only after its evidence).
    static func pausesMusic(lap: ArisQuietWake.State?) -> Bool { lap == .heard }
}
