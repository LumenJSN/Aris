//
//  ArisTypeRequest.swift
//  aris-tools
//
//  `type '<text>' [--app X] [--title <window>] [--at end|start]` as the desktop engine's call (ninth VM pass: aris-tools typed by itself, at the start of the
//  field after "끝에", with a password dialog up, and said it typed at the end). aris-tools no longer types: it hands the
//  text to the agent as `desktop type --focused --app X --stdin`, and the engine looks at the app's window, takes the
//  field with the focus, and types the one way Aris types (its card, the desktop lock, the pause for a sign-in or
//  password window, the caret where the user's words put it, the read-back of where it landed). Pure (tested).
//

import Foundation

enum ArisTypeRequest {
    static let usage = "usage: type '<text>' [--app X] [--title <window>] [--at end|start]"
    static let noAppLine = "no app has the keyboard to type into (name it with --app)"
    static let oneTextLine = "type takes its text as one argument: put all of it in one pair of quotes. " + usage

    /// The flags `type` knows, each taking one value, each at most once.
    private static let flags: Set<String> = ["--app", "--title", "--at"]

    /// The engine's words and the text for `type`'s arguments, or why not. `keyboardApp`: the app that has the keyboard
    /// now (its bundle id or name), for a call that names none. The text is the one argument that isn't a flag or a
    /// flag's value (after `--`, whatever it is); any other word that starts like a flag is refused, never typed
    /// (eleventh VM pass: the card offered to type "둘 --title noteC.txt --at end").
    static func call(_ args: [String], keyboardApp: String?) -> Result<(words: [String], text: String), ArisTypeRequestError> {
        var values: [String: String] = [:]
        var texts: [String] = []
        var index = 0, flagsEnd = false
        while index < args.count {
            let word = args[index]
            index += 1
            if flagsEnd || !looksLikeFlag(word) {
                texts.append(word)
            } else if word == "--" {
                flagsEnd = true
            } else if flags.contains(word) {
                // A flag twice (a second --app would be typed into the first: review 6, H1), or with no value.
                guard values[word] == nil, index < args.count, !args[index].hasPrefix("--"), !args[index].isEmpty else { return .failure(ArisTypeRequestError(line: usage)) }
                values[word] = args[index]
                index += 1
            } else {
                return .failure(ArisTypeRequestError(line: "type doesn't take \(word). " + usage))
            }
        }
        if let at = values["--at"], ArisTypeRequest.places.contains(at) == false { return .failure(ArisTypeRequestError(line: usage)) }
        guard texts.count <= 1 else { return .failure(ArisTypeRequestError(line: oneTextLine)) }
        guard let text = texts.first, !text.isEmpty else { return .failure(ArisTypeRequestError(line: usage)) }
        guard let target = values["--app"] ?? keyboardApp, !target.trimmingCharacters(in: .whitespaces).isEmpty else { return .failure(ArisTypeRequestError(line: noAppLine)) }
        let title = values["--title"].map { ["--title", $0] } ?? []
        let at = values["--at"].map { ["--at", $0] } ?? []
        return .success((["type", "--focused", "--app", target] + title + at + ["--stdin"], text))
    }

    /// Where --at may put the caret.
    static let places: Set<String> = ["end", "start"]

    /// A word that is a flag, not text: `--` and anything after it, or one minus and a letter (`-x`). A minus before a
    /// digit, a space or nothing ("-5도", "- 항목", "-") is text.
    static func looksLikeFlag(_ word: String) -> Bool {
        if word.hasPrefix("--") { return true }
        guard word.hasPrefix("-"), let next = word.dropFirst().first else { return false }
        return next.isLetter
    }
}

struct ArisTypeRequestError: Error, Equatable {
    let line: String
}
