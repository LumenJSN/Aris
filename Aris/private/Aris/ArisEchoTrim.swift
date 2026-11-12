//
//  ArisEchoTrim.swift
//  Aris
//
//  Talking over Aris through the speakers: the turn's first words can be Aris's own, heard back by the microphone.
//  Leading words that are among what Aris was just saying are dropped (security review I3), and only as many as fit
//  in the audio from before the user's voice was sure (M2), so a word the user says themselves stays.
//

import Foundation

enum ArisEchoTrim {
    /// How many of Aris's last words count as "just saying".
    static let recentWords = 16

    /// How many words fit in `seconds` of Aris's speech (it says about three a second; one at least).
    static func words(in seconds: Double) -> Int { max(1, Int((seconds * 3.5).rounded(.up))) }

    /// `atMost`: the words that can have come from the lookback (0: nothing is trimmed, e.g. on headphones).
    static func trimmed(_ heard: String, arisWasSaying said: String, atMost limit: Int) -> String {
        let recent = Set(words(said).suffix(recentWords))
        guard !recent.isEmpty, limit > 0 else { return heard }
        let tokens = heard.split(whereSeparator: \.isWhitespace)
        let echo = tokens.prefix(limit).prefix { recent.contains(normalised($0)) }.count
        // Everything matched: that was Aris itself, and nothing of the user's is left.
        return tokens.dropFirst(echo).joined(separator: " ")
    }

    private static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(normalised).filter { !$0.isEmpty }
    }

    private static func normalised(_ word: Substring) -> String {
        word.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.symbols))
    }
}
