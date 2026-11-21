//
//  ArisReplyLanguage.swift
//  Aris (Shared/Core)
//
//  The language of a line Aris says by itself, with no model: the language of the request it answers, as the model's
//  answers already are (tenth VM run, English UI: "지금 몇 시야?" was answered "It's 3:10 AM.", "볼륨 30으로 해 줘"
//  "Volume set to 30."). A request with Hangul in it is answered in Korean, one in Latin letters in English, and one
//  with neither (a number, a symbol, nothing heard) in the UI's language. What is shown with buttons of its own (a
//  card) keeps the UI's language, so a card is never in two languages.
//  The turn's words are kept here while it runs, because the lines are built in many places that only ask "Korean?".
//  Foundation only (swift test).
//

import Foundation

enum ArisReplyLanguage {
    /// Whether a reply to `request` is in Korean. `uiEnglish`: the UI's language, for a request that shows neither.
    static func korean(request: String, uiEnglish: Bool) -> Bool {
        var latin = false
        for scalar in request.unicodeScalars {
            // Hangul syllables and jamo: Korean, whatever else is in the sentence ("Safari 열어 줘").
            if (0xAC00...0xD7A3).contains(scalar.value) || (0x3131...0x318E).contains(scalar.value) || (0x1100...0x11FF).contains(scalar.value) { return true }
            if (0x41...0x5A).contains(scalar.value) || (0x61...0x7A).contains(scalar.value) { latin = true }
        }
        return latin ? false : !uiEnglish
    }

    private final class Turn: @unchecked Sendable {
        private let lock = NSLock()
        private var words: String?
        func set(_ value: String?) { lock.withLock { words = value } }
        func get() -> String? { lock.withLock { words } }
    }

    private static let turn = Turn()

    /// The owner's own words of the turn that begins (nil: no turn, a button was pressed).
    static func heard(_ words: String?) { turn.set(words) }

    /// Whether this turn's own lines are in Korean: by its words, else by the UI.
    static func korean(uiEnglish: Bool) -> Bool {
        guard let words = turn.get() else { return !uiEnglish }
        return korean(request: words, uiEnglish: uiEnglish)
    }
}
