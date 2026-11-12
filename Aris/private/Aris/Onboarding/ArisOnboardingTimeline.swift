//
//  ArisOnboardingTimeline.swift
//  Aris
//
//  The two spoken things of the onboarding as clocks, so the views are pure functions of time and nothing keeps
//  running once they're off screen (mockups/onboarding2/js/narrate.js, talk.js):
//  - ArisNarration: the notch voices each setup page in one line, as spoken-word karaoke (dim .38 → lit .97,
//    160 ms ease-out), a word every 0.26 s, held 2.6 s after the last, then the band folds back.
//  - ArisCaptions: Aris speaks first; each sentence resolves 150 ms after its voice starts (measured from the clip, or
//    from the speech synthesizer's callbacks), 560 ms blur → 0 on the house ease.
//

import Foundation

struct ArisNarration: Equatable {
    static let firstWord = 0.22
    static let wordStep = 0.26
    static let hold = 2.6
    static let fadeOut = 0.16

    let words: [String]
    /// Seconds (the media clock).
    let start: Double
    let reduced: Bool

    init(text: String, start: Double, reduced: Bool) {
        words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        self.start = start
        self.reduced = reduced
    }

    /// How many words are lit.
    func lit(at now: Double) -> Int {
        if reduced { return words.count }
        let x = now - start - Self.firstWord
        guard x >= -1e-6 else { return 0 }
        return min(words.count, 1 + Int(((x + 1e-6) / Self.wordStep).rounded(.down)))
    }

    /// When the line starts fading (after the hold).
    var fadeAt: Double { start + (reduced ? 0 : Self.firstWord + Double(words.count) * Self.wordStep) + Self.hold }
    /// When the band folds back to rest.
    var foldAt: Double { fadeAt + Self.fadeOut }

    /// The line's opacity: in over 180 ms after 140 ms (at once under Reduce Motion), out over 160 ms.
    func opacity(at now: Double) -> Double {
        let fadeIn = reduced ? 1 : ArisOnboardingMotion.span(now, start + 0.14, start + 0.32)
        return fadeIn * (1 - ArisOnboardingMotion.span(now, fadeAt, foldAt))
    }
}

struct ArisCaptions: Equatable {
    static let lag = 0.15
    static let reveal = 0.56
    static let syllable = 0.155

    let sentences: [String]
    /// When the voice starts (media seconds).
    let start: Double
    /// Each sentence's start inside the voice.
    var starts: [Double]
    let duration: Double

    var revealAt: [Double] { starts.map { start + $0 + Self.lag } }
    var endsAt: Double { start + duration }

    /// 0…1 of a sentence's reveal, on the house ease.
    func progress(_ index: Int, at now: Double) -> Double {
        guard index < starts.count else { return 0 }
        return ArisOnboardingMotion.settle(ArisOnboardingMotion.span(now, revealAt[index], revealAt[index] + Self.reveal))
    }

    func speaking(at now: Double) -> Bool { now >= start && now <= endsAt }

    /// No clip and no synthesizer: paced from the text.
    static func estimated(sentences: [String], start: Double) -> ArisCaptions {
        var t = 0.08
        let starts = sentences.map { sentence -> Double in
            let at = t
            t += Double(sentence.filter { !$0.isWhitespace }.count) * syllable + 0.32
            return at
        }
        return ArisCaptions(sentences: sentences, start: start, starts: starts, duration: t)
    }

    /// The sentence a speech synthesizer range starts in (UTF-16 offsets into the sentences joined by spaces).
    static func sentence(containing location: Int, in sentences: [String]) -> Int {
        var end = 0
        for (i, s) in sentences.enumerated() {
            end += s.utf16.count + 1
            if location < end { return i }
        }
        return max(0, sentences.count - 1)
    }

    /// A typed name: no control characters, single spaces, at most 24 characters.
    static func cleanName(_ raw: String) -> String {
        let folded = raw.precomposedStringWithCompatibilityMapping
        let visible = String(folded.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(Character.init))
        let single = visible.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(single.prefix(24)).trimmingCharacters(in: .whitespaces)
    }
}
