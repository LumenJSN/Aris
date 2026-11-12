//
//  ArisCaretContext.swift
//  aris-agent
//
//  The words around the caret in the field the user dictates into: 200 before and 100 after (the window-text
//  context), for dictation polish only, as untrusted data. A selection, which the dictation will replace, is in
//  neither. Read through ArisFocusedField, never in terminals, password fields or password apps.
//  Foundation only (tested).
//

import Foundation

enum ArisCaretContext {
    static let wordsBefore = 200
    static let wordsAfter = 100

    /// The words before and after the caret (`caret` and `selected` in UTF-16 units, as Accessibility gives them).
    static func slice(_ value: String, caret: Int, selected: Int) -> (before: String, after: String) {
        let string = value as NSString
        let start = boundary(min(max(caret, 0), string.length), in: string)
        let end = boundary(min(start + max(selected, 0), string.length), in: string)
        let head = string.substring(to: start), tail = string.substring(from: end)
        let before = head.split(whereSeparator: \.isWhitespace).suffix(wordsBefore).joined(separator: " ")
        let after = tail.split(whereSeparator: \.isWhitespace).prefix(wordsAfter).joined(separator: " ")
        return (before, after)
    }

    /// An offset inside a character (half an emoji) moves back to its start.
    private static func boundary(_ offset: Int, in string: NSString) -> Int {
        offset < string.length ? string.rangeOfComposedCharacterSequence(at: offset).location : offset
    }
}
