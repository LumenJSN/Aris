//
//  ArisHearScore.swift
//  Aris (Shared/Core, Foundation only)
//
//  How far a recogniser's text is from what was said, for the bench (tests/stt-bench): the character error rate, the
//  usual measure for Korean, where spacing is loose and a word is too coarse a unit. Letters and digits only, in any
//  case: punctuation and spacing are not errors.
//

import Foundation

enum ArisHearScore {
    static func letters(_ text: String) -> [Character] {
        Array(String(text.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains)))
    }

    /// Edits (a character added, dropped or changed) per character of what was said. Nothing to hear: 0 for silence, 1 for any words.
    static func cer(expected: String, heard: String) -> Double {
        let want = letters(expected), got = letters(heard)
        guard !want.isEmpty else { return got.isEmpty ? 0 : 1 }
        return Double(distance(want, got)) / Double(want.count)
    }

    static func distance<T: Equatable>(_ a: [T], _ b: [T]) -> Int {
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var row = Array(0...b.count)
        for (i, x) in a.enumerated() {
            var previous = row[0]
            row[0] = i + 1
            for (j, y) in b.enumerated() {
                let next = min(row[j] + 1, row[j + 1] + 1, previous + (x == y ? 0 : 1))
                previous = row[j + 1]
                row[j + 1] = next
            }
        }
        return row[b.count]
    }
}
