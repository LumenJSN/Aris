//
//  ArisEchoGuard.swift
//  Aris
//
//  Aris must never take its own voice for the user's (2026-11-16: through the speakers it heard its own answer as a new
//  turn and answered that, over and over). In layers:
//  - Listening between turns starts only once Aris's voice is really out of the room: when the speaker says it has
//    finished, plus a tail for the output's latency (Bluetooth is long) and the room, never under `floor`; and the
//    turn's audio never reaches back before the moment listening started (no pre-roll of Aris's tail).
//  - Over the speakers, Aris's name heard while its own voice plays (or in the tail) is its own when it just said it.
//  - A whole heard turn that is mostly what Aris said in its last replies is echo: it never starts a turn and is
//    never answered (ArisEchoTrim still trims leading words of a real barge-in).
//  - Two echo turns in a row, or a turn that is a sentence of Aris's own, end the conversation (ArisEchoLoop): Aris
//    goes back to waiting for its name instead of looping.
//

import Foundation

enum ArisEchoGuard {
    // MARK: - When the microphone may listen again

    /// Never listen sooner than this after Aris's voice ended (the room's own tail and the microphone's buffer).
    static let floor: Double = 0.35
    /// Added to the output's own latency: the room's reverb and the microphone's hop.
    static let roomTail: Double = 0.2
    /// Bluetooth's delay, when it reports less (it often does): at least this.
    static let bluetoothFloor: Double = 0.6
    /// A latency read wrong never holds listening off for long.
    static let longest: Double = 1.5

    /// How long after the speaker says it finished Aris's voice may still be heard: the output's latency (`outputLatency`
    /// seconds, nil when it couldn't be read) plus the room, at least `floor` (`bluetoothFloor` on Bluetooth).
    static func tail(outputLatency: Double?, bluetooth: Bool) -> Double {
        let measured = max(0, outputLatency ?? 0) + roomTail
        return min(longest, max(bluetooth ? bluetoothFloor : floor, measured))
    }

    /// Seconds still to wait before the microphone may listen for a turn; 0: now. `playing`: Aris's voice is still
    /// being played; `sinceStopped`: seconds since it stopped (nil: it never played).
    static func waitBeforeListening(playing: Bool, sinceStopped: Double?, tail: Double) -> Double {
        if playing { return tail }
        guard let sinceStopped else { return 0 }
        return max(0, tail - sinceStopped)
    }

    /// The sample a turn's audio starts at: the voice watch's lookback (`reached` - `lookback` samples), never before the
    /// sample the watch was armed at (what came before it may be Aris's own tail).
    static func turnStart(reached: Int, lookback: Int, armedAt: Int?) -> Int {
        max(0, armedAt ?? 0, reached - lookback)
    }

    // MARK: - Aris's name in its own voice

    /// A name candidate lasts about this long before it is handed on: its start can lie this much before it fires.
    static let candidateLength: Double = 1.0

    /// Aris's own voice may still be in the microphone: it plays, or stopped less than `window` seconds ago.
    static func ownVoiceAudible(playing: Bool, sinceStopped: Double?, window: Double) -> Bool {
        playing || (sinceStopped.map { $0 < window } ?? false)
    }

    /// Aris's name anywhere in what it said ("아리스가 할게요", "I'm Aris"), however it is joined to the words around it.
    static func namesAris(_ text: String) -> Bool {
        let folded = text.lowercased()
        return ["아리스", "아리쓰", "aris"].contains { folded.contains($0) }
    }

    /// "아리스" heard over the speakers while Aris's own voice may be in the microphone, when Aris itself just said its
    /// name, is Aris's own voice: it neither wakes nor stops it. With headphones the microphone can't hear Aris.
    static func ignoresName(headphones: Bool, ownVoiceAudible: Bool, saidName: Bool) -> Bool {
        !headphones && ownVoiceAudible && saidName
    }

    // MARK: - A heard turn that is Aris's own words

    enum Verdict: Equatable {
        /// The user's: the turn goes on.
        case user
        /// Mostly Aris's recent words: dropped, never answered.
        case echo
        /// A sentence of Aris's own, word for word: dropped, and the conversation stops listening (ArisEchoLoop).
        case ownWords
    }

    /// Shorter than this (letters, spaces and punctuation left out) is never judged: "네", "응", "그래" stay the user's.
    static let shortest = 4
    /// This share of the heard words found among Aris's makes the turn echo.
    static let echoShare = 0.7
    /// A run of this many letters in a row from one of Aris's replies, covering `runShare` of the turn, is echo too.
    static let longRun = 8
    static let runShare = 0.6
    /// A turn of this many words that is a piece of Aris's reply, word for word, is its own sentence.
    static let ownWordsTokens = 3

    /// Whether `heard` is the user's or Aris's own voice heard back, against what Aris said lately (`recent`, its last
    /// replies). Case, spacing and punctuation never matter; Korean words are matched inside Aris's words too, so a
    /// recognizer that spaced them otherwise still matches.
    static func verdict(_ heard: String, recent: [String]) -> Verdict {
        let words = tokens(heard)
        let compact = words.joined()
        let said = recent.map(tokens).filter { !$0.isEmpty }
        guard compact.count >= shortest, !said.isEmpty else { return .user }
        let saidWords = Set(said.joined())
        let saidCompact = said.map { $0.joined() }
        let run = saidCompact.map { longestRun(compact, $0) }.max() ?? 0
        if run == compact.count { return words.count >= ownWordsTokens ? .ownWords : .echo }
        let found = words.filter { word in saidWords.contains(word) || (word.count >= 2 && saidCompact.contains { $0.contains(word) }) }
        if words.count >= 2, Double(found.count) / Double(words.count) >= echoShare { return .echo }
        if run >= longRun, Double(run) >= runShare * Double(compact.count) { return .echo }
        return .user
    }

    /// The words of `text`, lower-cased, without punctuation or symbols.
    static func tokens(_ text: String) -> [String] {
        let cut = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).union(.symbols)
        return text.lowercased().components(separatedBy: cut).filter { !$0.isEmpty }
    }

    /// The longest run of characters `a` and `b` share (at most the first 400 of each are compared).
    static func longestRun(_ a: String, _ b: String) -> Int {
        let x = Array(a.prefix(400)), y = Array(b.prefix(400))
        guard !x.isEmpty, !y.isEmpty else { return 0 }
        var previous = [Int](repeating: 0, count: y.count + 1)
        var best = 0
        for i in 1...x.count {
            var row = [Int](repeating: 0, count: y.count + 1)
            for j in 1...y.count where x[i - 1] == y[j - 1] {
                row[j] = previous[j - 1] + 1
                best = max(best, row[j])
            }
            previous = row
        }
        return best
    }
}

/// What Aris said lately, for ArisEchoGuard.verdict: its last `kept` utterances, each forgotten `lasts` seconds after it
/// was last added to. Times are seconds on one clock (the system's uptime).
struct ArisEchoMemory: Equatable {
    struct Said: Equatable {
        let text: String
        let at: Double
    }

    static let kept = 2
    static let lasts: Double = 90

    private(set) var said: [Said] = []

    /// A new utterance starts (a line, or an answer whose sentences follow).
    func starting(_ text: String, at now: Double) -> ArisEchoMemory {
        var next = self
        next.said = Array((said + [Said(text: text, at: now)]).suffix(Self.kept))
        return next
    }

    /// The utterance under way says one more sentence.
    func adding(_ sentence: String, at now: Double) -> ArisEchoMemory {
        guard let last = said.last else { return starting(sentence, at: now) }
        var next = self
        next.said[next.said.count - 1] = Said(text: last.text.isEmpty ? sentence : last.text + " " + sentence, at: now)
        return next
    }

    /// What was said within `lasts` seconds of `now`, oldest first.
    func recent(at now: Double) -> [String] {
        said.filter { now - $0.at <= Self.lasts && !$0.text.isEmpty }.map(\.text)
    }
}

/// Echo turns in a row in one conversation: two (or one that is Aris's own sentence) end its listening.
struct ArisEchoLoop: Equatable {
    static let stopsAfter = 2

    private(set) var inARow = 0

    var stops: Bool { inARow >= Self.stopsAfter }

    func after(_ verdict: ArisEchoGuard.Verdict) -> ArisEchoLoop {
        switch verdict {
        case .user: return ArisEchoLoop()
        case .echo: return ArisEchoLoop(inARow: inARow + 1)
        case .ownWords: return ArisEchoLoop(inARow: max(inARow + 1, Self.stopsAfter))
        }
    }
}
