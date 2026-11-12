//
//  ArisGestureMarkers.swift
//  Aris
//
//  `[img N]` markers: where in the user's words each circled shot belongs. A marker goes at the word the user was
//  saying when they circled, and the transcript moves the markers to sentence ends for display. Offsets are
//  UTF-16 (NSString). Pure, so the tests run it.
//

import Foundation

struct ArisMarkedShot {
    let badge: Int
    let voicedMsAtCapture: Double
    let capturedAtMs: Double
}

enum ArisGestureMarkers {
    /// Below this much voiced audio, place markers by wall-clock time instead.
    static let minVoicedTotalMs = ArisGestureConstants.Speech.minVoicedTotalMs

    /// Inserts `[img N]` for each shot, in badge order, at `round(frac * wordCount)` words, never before an earlier
    /// badge's marker.
    static func insert(_ transcript: String, shots: [ArisMarkedShot],
                       speech: (startedAtMs: Double, endedAtMs: Double, totalVoicedMs: Double)) -> String {
        guard !shots.isEmpty else { return transcript }
        let fractions = shots.sorted { $0.badge < $1.badge }.map { (badge: $0.badge, frac: fraction($0, speech)) }
        return insertAtWordFractions(transcript, fractions)
    }

    /// The badges named by markers in `text`, in order (`[img 3]`, `[ img 3 ]`, `[Screenshot 12]`, any case).
    static func badges(in text: String) -> [Int] {
        split(text).compactMap { if case .shot(let badge) = $0 { badge } else { nil } }
    }

    /// For display: each marker moves forward to the end of its sentence (or line), keeping their order.
    static func movedToSentenceEnds(_ text: String) -> String {
        let parts = split(text)
        guard parts.contains(where: { if case .shot = $0 { true } else { false } }) else { return text }
        var clean = "" as NSString
        var pending: [(badge: Int, at: Int)] = []
        var afterShot = false
        for part in parts {
            switch part {
            case .shot(let badge):
                pending.append((badge, clean.length))
                afterShot = true
            case .text(let raw):
                var piece = raw
                if afterShot && (clean.length == 0 || endsWithSpace(clean)) { piece = replacing(piece, leadingBlanks) }
                if afterShot && matches(clean, trailingBlanks) && matches(prefix(piece, 1), cjkChar) {
                    let trimmed = replacing(clean as String, trailingBlanks) as NSString
                    if matches(suffix(trimmed, 1), cjkChar) { clean = trimmed }
                }
                afterShot = false
                clean = clean.appending(piece) as NSString
            }
        }
        clean = replacing(clean as String, trailingBlanks) as NSString
        var floor = 0
        let targets = pending.map { item -> (badge: Int, offset: Int) in
            let at = min(item.at, clean.length)
            let target = max(floor, sitsAtSentenceEnd(clean, at) ? at : sentenceEnd(after: at, in: clean))
            floor = target
            return (item.badge, target)
        }
        return place(targets, in: clean)
    }

    // MARK: - Placing

    /// Voiced time when there is enough of it, else wall-clock time; clamped to 0...1.
    private static func fraction(_ shot: ArisMarkedShot,
                                 _ speech: (startedAtMs: Double, endedAtMs: Double, totalVoicedMs: Double)) -> Double {
        if speech.totalVoicedMs >= minVoicedTotalMs { return clamp01(shot.voicedMsAtCapture / speech.totalVoicedMs) }
        let duration = speech.endedAtMs - speech.startedAtMs
        if duration <= 0 { return 1 }
        return clamp01((shot.capturedAtMs - speech.startedAtMs) / duration)
    }

    private static func clamp01(_ v: Double) -> Double { max(0, min(1, v.isFinite ? v : 1)) }

    private static func insertAtWordFractions(_ transcript: String, _ items: [(badge: Int, frac: Double)]) -> String {
        let text = transcript as NSString
        let words = wordPattern.matches(in: transcript, range: NSRange(location: 0, length: text.length))
        func offset(afterWords k: Int) -> Int {
            if k <= 0 { return 0 }
            if k >= words.count { return text.length }
            return NSMaxRange(words[k - 1].range)
        }
        var lastIndex = 0
        let targets = items.map { item -> (badge: Int, offset: Int) in
            let index = max(lastIndex, Int((clamp01(item.frac) * Double(words.count)).rounded(.toNearestOrAwayFromZero)))
            lastIndex = index
            return (item.badge, offset(afterWords: index))
        }
        return place(targets, in: text)
    }

    /// Writes each marker at its offset with one space on each side unless whitespace is already there.
    private static func place(_ targets: [(badge: Int, offset: Int)], in text: NSString) -> String {
        var out = "" as NSString
        var cursor = 0
        for target in targets {
            out = out.appending(text.substring(with: NSRange(location: cursor, length: target.offset - cursor))) as NSString
            cursor = target.offset
            let spaceBefore = out.length > 0 && !endsWithSpace(out)
            let spaceAfter = cursor < text.length && !matches(text.substring(with: NSRange(location: cursor, length: 1)), whitespace)
            out = out.appending((spaceBefore ? " " : "") + marker(target.badge) + (spaceAfter ? " " : "")) as NSString
        }
        return (out as String) + text.substring(from: cursor)
    }

    private static func marker(_ badge: Int) -> String { "[img \(badge)]" }

    // MARK: - Sentence ends

    /// `sitsAtSentenceEnd`: the text before `at`, minus trailing blanks, ends a sentence or a line.
    private static func sitsAtSentenceEnd(_ text: NSString, _ at: Int) -> Bool {
        let before = replacing(text.substring(to: at), trailingBlanks)
        if before.isEmpty { return false }
        if (before as NSString).hasSuffix("\n") { return true } // UTF-16, so a CRLF line end counts
        return matches(before, endsASentence)
    }

    /// The end of the first terminator run after `at` that is followed by whitespace, the end of
    /// the text, or is a CJK terminator; otherwise the end of the line, minus trailing blanks.
    private static func sentenceEnd(after at: Int, in text: NSString) -> Int {
        let newline = text.range(of: "\n", range: NSRange(location: at, length: text.length - at)).location
        let lineEnd = newline == NSNotFound ? text.length : newline
        let runs = terminatorRun.matches(in: text as String, range: NSRange(location: at, length: text.length - at))
        for run in runs {
            if run.range.location >= lineEnd { break }
            let end = NSMaxRange(run.range)
            if matches(text.substring(with: run.range), cjkTerminator) || end == text.length
                || matches(text.substring(with: NSRange(location: end, length: 1)), whitespace) {
                return end
            }
        }
        return (replacing(text.substring(to: lineEnd), trailingBlanks) as NSString).length
    }

    // MARK: - Splitting

    enum Part: Equatable { case text(String), shot(Int) }

    /// The text for display (markers at sentence ends), split into text and shot parts (the transcript chips).
    static func displayParts(_ text: String) -> [Part] {
        split(movedToSentenceEnds(text))
    }

    private static func split(_ text: String) -> [Part] {
        let ns = text as NSString
        var parts: [Part] = []
        var cursor = 0
        for match in markerPattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if match.range.location > cursor {
                parts.append(.text(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))))
            }
            parts.append(.shot(Int(ns.substring(with: match.range(at: 1))) ?? 0))
            cursor = NSMaxRange(match.range)
        }
        if cursor < ns.length { parts.append(.text(ns.substring(from: cursor))) }
        return parts.isEmpty ? [.text(text)] : parts
    }

    // MARK: - Patterns (ICU regexes)

    private static func regex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        // The patterns are constants; a typo is a programmer error caught by the tests.
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    // [0-9], not \d: ICU's \d also matches non-ASCII digits.
    private static let markerPattern = regex(#"\[\s*(?:img|Screenshot)\s+([0-9]{1,3})\s*\]"#, [.caseInsensitive])
    private static let wordPattern = regex(#"\S+"#)
    private static let whitespace = regex(#"^\s\z"#)
    private static let trailingSpace = regex(#"\s\z"#)
    private static let leadingBlanks = regex(#"^[ \t]+"#)
    private static let trailingBlanks = regex(#"[ \t]+\z"#)
    private static let cjkChar = regex(#"[\u3000-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uff01-\uff9f]"#)
    private static let terminatorRun = regex(#"[.!?…。！？]+["'”’)\]]*"#)
    private static let endsASentence = regex(#"[.!?…。！？]["'”’)\]]*\z"#)
    private static let cjkTerminator = regex(#"[。！？]"#)

    private static func matches(_ s: String, _ re: NSRegularExpression) -> Bool {
        re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }

    private static func matches(_ s: NSString, _ re: NSRegularExpression) -> Bool { matches(s as String, re) }

    private static func endsWithSpace(_ s: NSString) -> Bool { matches(s, trailingSpace) }

    private static func replacing(_ s: String, _ re: NSRegularExpression) -> String {
        re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: "")
    }

    private static func prefix(_ s: String, _ n: Int) -> String {
        let ns = s as NSString
        return ns.substring(to: min(n, ns.length))
    }

    private static func suffix(_ s: NSString, _ n: Int) -> String {
        s.substring(from: max(0, s.length - n))
    }
}
