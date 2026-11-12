//
//  ArisSentenceSplitter.swift
//  Aris
//
//  Cuts an answer into sentences while it is still arriving, so Aris can start
//  speaking the first one before the AI has finished the rest.
//

import Foundation

struct ArisSentenceSplitter {
    /// Shorter sentences ("네.") wait for the next one, so the voice doesn't stutter.
    private static let shortest = 3
    private static let enders: Set<Character> = [".", "?", "!", "。", "？", "！"]

    private var buffer = ""
    private var held = ""

    /// The sentences this piece of the answer completes.
    mutating func add(_ piece: String) -> [String] {
        buffer += piece
        var sentences: [String] = []
        var start = buffer.startIndex
        var index = buffer.startIndex
        while index < buffer.endIndex {
            let character = buffer[index]
            let next = buffer.index(after: index)
            // An ender counts once the next character shows it isn't "3.5"; a new line always ends one.
            let ends = character == "\n"
                || (Self.enders.contains(character) && next < buffer.endIndex && buffer[next].isWhitespace
                    && !(character == "." && ArisSpeech.endsWithAbbreviation(String(buffer[start..<next]))))
            if ends {
                let end = character == "\n" ? index : next
                sentences += release(String(buffer[start..<end]))
                start = next
            }
            index = next
        }
        buffer = String(buffer[start...])
        return sentences
    }

    /// The words still waiting for their sentence to end, exactly as they came.
    var waiting: String { buffer }

    /// Keeps only the first `count` characters of the waiting words (the rest was taken out of the answer).
    mutating func keepWaiting(first count: Int) {
        buffer = String(buffer.prefix(max(0, count)))
    }

    /// Whatever is left once the answer is complete.
    mutating func finish() -> [String] {
        let rest = (held.isEmpty ? "" : held + " ") + buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        held = ""
        let sentence = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        return sentence.isEmpty ? [] : [sentence]
    }

    private mutating func release(_ raw: String) -> [String] {
        let sentence = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty else { return [] }
        let joined = held.isEmpty ? sentence : held + " " + sentence
        guard joined.count >= Self.shortest else {
            held = joined
            return []
        }
        held = ""
        return [joined]
    }
}
