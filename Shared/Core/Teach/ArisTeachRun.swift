//
//  ArisTeachRun.swift
//  Shared/Core/Teach (aris-agent, tests, swift test)
//
//  Where a stretch of typing sits in its text element, followed change by change (ninth VM run, item 1: "Wrap memo"
//  typed at the start of "Wrap seed " was saved as ‘memoWrap ’, three times out of three). One comparison of the text
//  before his first key with the text after his last can't tell where a run went in when it begins like the text right
//  after it; the eighth run's fix told it by the first change's one character, and the real change notices don't
//  always come one character at a time (a notice handled after two keys, one that came with nothing changed yet, or
//  the value read once at the lesson's end: each left no first character and the old cut). So the run is built from
//  the sequence of changes: each change is small and says where it happened, and a change that goes on where the run
//  ended narrows the places the run can have begun. What is still open at the end is settled by the caret the element
//  reported after the change, when it was read; else by the old rule (the latest place). A run that can't be followed
//  (he typed in two places, the app rewrote the text) is nil, and the text is told from the two values as before.
//  Offsets count Characters of the element's value. Pure.
//

import Foundation

struct ArisTeachRun: Codable, Equatable, Sendable {
    /// The earliest and the latest place the run can begin, as the changes so far allow.
    var low: Int
    var high: Int
    /// How many characters the run holds now.
    var length: Int

    /// Nothing typed yet.
    static let none = ArisTeachRun(low: 0, high: 0, length: 0)

    /// The run after one more change of the element's text from `old` to `new`. `caret`: the end of the element's
    /// selection as it reported it after the change (UTF-16, as Accessibility counts), when it was read. Nil: the
    /// change can't be part of one run.
    func after(old: String, new: String, caret: Int? = nil) -> ArisTeachRun? {
        guard old != new else { return self }
        let was = Array(old), now = Array(new)
        var prefix = 0
        while prefix < was.count, prefix < now.count, was[prefix] == now[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < was.count - prefix, suffix < now.count - prefix, was[was.count - 1 - suffix] == now[now.count - 1 - suffix] { suffix += 1 }
        var tail = 0
        while tail < was.count, tail < now.count, was[was.count - 1 - tail] == now[now.count - 1 - tail] { tail += 1 }
        let removed = was.count - prefix - suffix, added = now.count - prefix - suffix
        var next: ArisTeachRun?
        if removed == 0 {
            // Characters put in, at any place from `first` to `prefix` (the same text results from each of them).
            let first = was.count - tail
            if length == 0 {
                next = ArisTeachRun(low: first, high: prefix, length: added)
            } else {
                // Going on where the run ended; else somewhere inside the run.
                next = narrowed(max(low, first - length), min(high, prefix - length), length: length + added)
                    ?? narrowed(max(low, first - length), min(high, prefix), length: length + added)
            }
        } else if added == 0 {
            // Characters taken out, at any place from `first` to `prefix`: only ones of the run (a typo taken back).
            let first = now.count - tail
            guard removed <= length else { return nil }
            if removed == length, narrowed(max(low, first), min(high, prefix), length: 0) != nil { return ArisTeachRun.none }
            next = narrowed(max(low, first + removed - length), min(high, prefix + removed - length), length: length - removed)
                ?? narrowed(max(low, first + removed - length), min(high, prefix), length: length - removed)
        } else {
            // Characters of the run replaced by others (a syllable still being composed).
            guard removed <= length else { return nil }
            next = narrowed(max(low, prefix + removed - length), min(high, prefix), length: length + added - removed)
        }
        guard var told = next else { return nil }
        // Still open: the run ends where the caret is now.
        if told.low < told.high, let caret, let end = Self.characters(upTo: caret, in: new), (told.low...told.high).contains(end - told.length) {
            told.low = end - told.length
            told.high = told.low
        }
        return told
    }

    private func narrowed(_ from: Int, _ to: Int, length: Int) -> ArisTeachRun? {
        from <= to && length >= 0 ? ArisTeachRun(low: from, high: to, length: length) : nil
    }

    /// The run's text in the element's last value, checked against the value before his first key (`before` with the
    /// run put in is `value`); nil when it doesn't hold. A beginning still open is the latest place.
    func text(in value: String, before: String) -> (text: String, atEnd: Bool)? {
        let all = Array(value)
        let start = high
        guard length > 0, start >= 0, start + length <= all.count else { return nil }
        guard String(all[..<start] + all[(start + length)...]) == before else { return nil }
        return (String(all[start..<(start + length)]), start + length == all.count)
    }

    /// How many Characters of `text` lie before the UTF-16 offset `offset`; nil when it is outside the text or inside
    /// a character.
    static func characters(upTo offset: Int, in text: String) -> Int? {
        guard offset >= 0, offset <= text.utf16.count else { return nil }
        let index = String.Index(utf16Offset: offset, in: text)
        if index == text.endIndex { return text.count }
        guard text.rangeOfComposedCharacterSequence(at: index).lowerBound == index else { return nil }
        return text.distance(from: text.startIndex, to: index)
    }
}
