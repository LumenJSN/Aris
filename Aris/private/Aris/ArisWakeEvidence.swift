//
//  ArisWakeEvidence.swift
//  Aris
//
//  What keeps a doubtful wake open (the owner, 2026-11-15: a song that wakes Aris goes on singing). A sure wake in the
//  upper part of the sure band (ArisWakeDoubt.opening == .checkAfterOpening) opens at once, but until there is
//  evidence that it was the user calling Aris the notch stays closed, nothing is streamed to Scribe and the turn's request
//  is never run. Sound going on is no evidence: a song's vocals, the TV and other people talking go on too.
//  - Whisper heard the name in the candidate (near spellings only with a close print): kept.
//  - Whisper heard something else: nothing said yet closes it, as before; words after the name are kept only when
//    they read as a request addressed to the assistant (ArisWakeAddressed).
//  - Whisper not ready (not downloaded): nothing is decided on a guess.
//  - Over music or this Mac's own playback (2026-11-15) Whisper's text is no evidence: prompted with the name, it
//    writes "아리스" over lyrics with nothing like it. Only a strong print (ArisWakeStrict) keeps such a wake, and
//    Whisper can only veto it (it heard something that is not the name); a weaker print closes, whatever was said.
//  Pure, so the tests drive it; the controller feeds it (ArisController+WakeEvidence).
//

import Foundation

struct ArisWakeEvidence: Equatable {
    enum Whisper: Equatable {
        /// Its check of the candidate hasn't come back yet.
        case waiting
        /// Whisper isn't on this Mac (or had no audio): it can't say.
        case unavailable
        case heard(String)
    }

    enum Judged: Equatable { case addressed, notAddressed, unknown }

    struct Judgement: Equatable {
        /// The words that were judged: a judgement holds only while they are still the words.
        let text: String
        let verdict: Judged
    }

    enum Verdict: Equatable {
        /// Not decided yet: the notch stays closed and the turn waits.
        case pending
        /// Words came: the judge must read them (ArisWakeAddressed).
        case judge
        case keep
        case close(ArisWakeDoubt.QuietEnd)
    }

    /// Which doubtful wake this is (a late answer for an earlier one changes nothing).
    let id: UUID
    /// A near spelling counts with this candidate's print (ArisWakeDoubt.nearAllowed).
    let nearAllowed: Bool
    /// This Mac played media (or carried a call) at the wake (ArisOtherAudio, Now Playing).
    let playing: Bool
    /// The voice print is within the playback line (ArisWakeStrict.isStrong): over music it alone says it was the user.
    let strongPrint: Bool
    var whisper: Whisper = .waiting
    /// SoundAnalysis heard music or singing around the call (ArisWakeMusic).
    var music = false
    /// The words after the call so far (ArisWakeWord.strippedCall).
    var said = ""
    /// The detector's gate hears voice now (it waits for words, never keeps on its own).
    var voiceGoing = false
    /// The turn stopped listening: this is the last look before its request would run.
    var final = false
    var judged: Judgement?

    init(id: UUID = UUID(), nearAllowed: Bool, playing: Bool, strongPrint: Bool = false) {
        self.id = id
        self.nearAllowed = nearAllowed
        self.playing = playing
        self.strongPrint = strongPrint
    }

    /// Music, singing or this Mac's own sound: only the name itself counts.
    var strict: Bool { music || playing }

    /// How a strict wake that wasn't the name closes, for the wake log.
    var strictEnd: ArisWakeDoubt.QuietEnd { music ? .music : .playing }

    var verdict: Verdict {
        if strict, whisper != .waiting { return strictVerdict }
        switch whisper {
        case .waiting:
            return .pending
        case .heard(let text) where ArisWakeWord.verified(text, nearAllowed: nearAllowed):
            return .keep
        case .unavailable:
            return .keep
        case .heard:
            break
        }
        guard Self.hasWords(said) else {
            return voiceGoing && !final ? .pending : .close(.notAris)
        }
        guard let judged, judged.text == said else { return .judge }
        switch judged.verdict {
        case .addressed: return .keep
        // Cut-off words ("내일 아침") read as nothing: only the turn's whole words close it.
        case .notAddressed: return final ? .close(.notAddressed) : .pending
        // No judge in time: kept only when Whisper's text has the name somewhere.
        case .unknown: return final ? (whisperNamesAris ? .keep : .close(.notAddressed)) : .pending
        }
    }

    /// Over music or playback: a strong print is kept unless Whisper heard something that is not the name (its veto);
    /// a weaker one closes, whatever Whisper or the words after it say.
    private var strictVerdict: Verdict {
        guard strongPrint else { return .close(strictEnd) }
        guard case .heard(let text) = whisper else { return .keep }
        return ArisWakeWord.verified(text, nearAllowed: nearAllowed) ? .keep : .close(strictEnd)
    }

    /// Whisper's text names Aris anywhere ("그래서 아리스가…"), not only as a call at its start: any spelling of the wake
    /// name (ArisWakeName), a Latin one as a whole word.
    var whisperNamesAris: Bool {
        guard case .heard(let text) = whisper else { return false }
        let alternatives = ArisWakeName.current.spellings.map { spelling in
            let escaped = NSRegularExpression.escapedPattern(for: spelling)
            return spelling.unicodeScalars.allSatisfy(\.isASCII) ? #"\b"# + escaped + #"\b"# : escaped
        }
        return text.range(of: "(?i)" + alternatives.joined(separator: "|"), options: .regularExpression) != nil
    }

    /// What Whisper wrote of the candidate, for the wake log (nil: it didn't come back or couldn't run).
    var whisperText: String? {
        guard case .heard(let text) = whisper else { return nil }
        return text
    }

    /// Enough words to be worth judging before the turn ends (a judgement that says yes opens the notch early).
    static let judgeableLetters = 4

    static func judgeable(_ said: String) -> Bool {
        said.unicodeScalars.filter(CharacterSet.letters.contains).count >= judgeableLetters
    }

    static func hasWords(_ said: String) -> Bool {
        said.unicodeScalars.contains(where: CharacterSet.alphanumerics.contains)
    }

    // MARK: - Waits

    /// The turn's end waits at most this long for Whisper's check of the candidate (then it counts as not ready).
    static let whisperWait: Duration = .seconds(3)
}
