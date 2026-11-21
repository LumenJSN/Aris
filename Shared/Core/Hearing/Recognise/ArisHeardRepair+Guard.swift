//
//  ArisHeardRepair+Guard.swift
//  Aris (Shared/Core, Foundation only)
//
//  "Changed too much: keep the raw words." A repair is taken only when every difference from what the recogniser
//  wrote is one a repair may make: spacing; a word one sound off ("로션" → "노션"); a word the owner listed, or that
//  another engine heard; a term respelled in the other script ("깃허브에" → "GitHub에"). A word that is simply
//  different, added or dropped is not a repair, and the raw words stand: the model answered, translated or rewrote.
//  It is a coarse net under the instructions, not a proof: one sound can turn a meaning ("켜 줘", "꺼 줘").
//

import Foundation

extension ArisHeardRepair {
    /// The share of the words that may differ with no reason the guard knows (none in a short request).
    static let unexplainedShare = 0.2
    /// A repair this many times longer or shorter than the raw words (in letters) is something else.
    static let lengthRange = 0.4...2.5

    static func accepts(raw: String, repaired: String, context: Context) -> Bool {
        guard !repaired.contains(where: \.isNewline) else { return false }
        let before = words(raw), after = words(repaired)
        guard !before.isEmpty, !after.isEmpty else { return false }
        if before.joined() == after.joined() { return true }
        let ratio = Double(after.joined().count) / Double(before.joined().count)
        guard lengthRange.contains(ratio) else { return false }

        let known = Set((context.hints + context.pairs.map(\.meant)).map { words($0).joined() })
        let alsoHeard = Set(context.readings.flatMap(words))
        var unexplained = 0, respelled = 0
        for gap in gaps(before, after) {
            let (old, new) = gap
            if old.joined() == new.joined() || known.contains(new.joined()) { continue }
            guard old.count == new.count else { unexplained += max(old.count, new.count); continue }
            for (a, b) in zip(old, new) {
                if known.contains(b) || known.contains(latinStem(b)) || alsoHeard.contains(b) { continue }
                let aLatin = hasLatin(a), bLatin = hasLatin(b)
                if aLatin != bLatin {
                    // Wholly in the other script (not a Hangul ending kept on a respelled term): only so many of these.
                    if !(hasHangul(a) && hasHangul(b)) { respelled += 1 }
                } else if ArisHearScore.distance(Array(a), Array(b)) > max(1, a.count / 3) {
                    unexplained += 1
                }
            }
        }
        return unexplained <= Int(Double(before.count) * unexplainedShare) && respelled <= max(1, before.count / 2)
    }

    /// The stretches where the two word lists differ, in order (what stands between their common words).
    static func gaps(_ a: [String], _ b: [String]) -> [(old: [String], new: [String])] {
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var out: [(old: [String], new: [String])] = []
        var old: [String] = [], new: [String] = []
        var i = 0, j = 0
        func close() { if !old.isEmpty || !new.isEmpty { out.append((old, new)); old = []; new = [] } }
        while i < a.count, j < b.count {
            if a[i] == b[j] { close(); i += 1; j += 1 }
            else if table[i + 1][j] >= table[i][j + 1] { old.append(a[i]); i += 1 }
            else { new.append(b[j]); j += 1 }
        }
        old += a[i...]
        new += b[j...]
        close()
        return out
    }

    private static func hasLatin(_ word: String) -> Bool { word.unicodeScalars.contains { (0x41...0x7A).contains($0.value) && $0.properties.isAlphabetic } }
    private static func hasHangul(_ word: String) -> Bool { word.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) } }

    /// "github에" → "github": a respelled term with its Korean ending taken off.
    private static func latinStem(_ word: String) -> String {
        String(String.UnicodeScalarView(word.unicodeScalars.filter { !(0xAC00...0xD7A3).contains($0.value) }))
    }
}
