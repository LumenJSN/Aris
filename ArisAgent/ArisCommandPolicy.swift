//
//  ArisCommandPolicy.swift
//  aris-agent
//
//  Reading the shell commands an AI wants to run: the plain words of a command (nil when it
//  uses shell syntax that could hide a second command: ; && | $( ) ` > …), and the command
//  inside Codex's `zsh -lc` wrapper. ArisRiskPolicy decides what may run.
//

import Foundation

enum ArisCommandPolicy {
    private static let shells = ["/bin/zsh", "/bin/bash", "/bin/sh", "zsh", "bash", "sh"]

    /// Codex runs commands as `/bin/zsh -lc '<command>'`; this is the command inside.
    static func unwrap(_ command: String) -> String {
        guard let words = words(command), words.count == 3, shells.contains(words[0]), ["-lc", "-c"].contains(words[1]) else {
            return command
        }
        return words[2]
    }

    /// A line break by Unicode scalar, never by Character (Swift reads "\r\n" as one Character, unequal to "\n"): LF, CR,
    /// NEL (U+0085), VT, FF and the line and paragraph separators (U+2028, U+2029). Security review I2.
    static func isLineBreak(_ scalar: Unicode.Scalar) -> Bool {
        ["\n", "\r", "\u{0B}", "\u{0C}", "\u{85}", "\u{2028}", "\u{2029}"].contains(scalar)
    }

    /// Whether the text holds any line break (`isLineBreak`), "\r\n" included.
    static func hasLineBreak(_ text: String) -> Bool { text.unicodeScalars.contains(where: isLineBreak) }

    /// A System Settings link that only opens a pane (audit gate-15): `x-apple.systempreferences:<pane id>` with at most
    /// one plain anchor after `?` (…security?Privacy_Microphone). No parameters (= or &), no other character: such a
    /// link shows the pane and changes nothing. What the gate lets through and what `aris-tools link` opens, one rule.
    static func isSettingsLink(_ text: String) -> Bool {
        text.range(of: #"^x-apple\.systempreferences:[A-Za-z0-9][A-Za-z0-9._-]*(\?[A-Za-z0-9_.-]+)?$"#, options: .regularExpression) != nil
    }

    /// "tell application "System Events" to restart" (or shut down, log out, sleep), exactly: the four scripts that
    /// restart, shut down, log out or sleep the Mac. Which of them; nil for any other script (one more word included).
    static func powerVerb(script: String) -> String? {
        let pattern = #"^tell app(?:lication)? "System Events" to (restart|shut down|log out|sleep)$"#
        guard let found = script.range(of: pattern, options: .regularExpression) else { return nil }
        return ["restart", "shut down", "log out", "sleep"].first { script[found].hasSuffix($0) }
    }

    /// `osascript -e '<one of those four scripts>'` as words (after `aris-tools`, or the whole command): the script.
    static func powerScript(_ words: [String]) -> String? {
        guard words.count == 3, words[0] == "osascript", words[1] == "-e", powerVerb(script: words[2]) != nil else { return nil }
        return words[2]
    }

    /// The commands of a line chained with `&&` or `;` (outside quotes), each still to be read with `words`.
    /// Nil for a lone `&` (background), `|`, `||` or a backslash: those aren't split and the line is asked about.
    static func segments(_ command: String) -> [String]? {
        var pieces: [String] = []
        var piece = ""
        var quote: Character?
        let characters = Array(command)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if let open = quote {
                if character == open { quote = nil }
                piece.append(character)
            } else if character == "'" || character == "\"" {
                quote = character
                piece.append(character)
            } else if character == "\\" || character == "|" {
                return nil
            } else if character == "&" {
                guard index + 1 < characters.count, characters[index + 1] == "&" else { return nil }
                pieces.append(piece)
                piece = ""
                index += 1
            } else if character == ";" {
                pieces.append(piece)
                piece = ""
            } else {
                piece.append(character)
            }
            index += 1
        }
        pieces.append(piece)
        let trimmed = pieces.map { $0.trimmingCharacters(in: .whitespaces) }
        return trimmed.contains(where: \.isEmpty) ? nil : trimmed
    }

    /// The command's words with quotes removed; nil when it uses any other shell syntax.
    static func words(_ command: String) -> [String]? {
        var words: [String] = []
        var word = ""
        var inWord = false
        var quote: Character?
        /// `\'` outside quotes: a quote taken as itself, how POSIX shells (and Codex) write a quote inside '…' ('\''); any
        /// other backslash outside quotes is still refused (QA live on b9c766bc: such a desktop heredoc wasn't unwrapped).
        var quoteEscape = false
        /// A backslash inside "…": the next character is taken as itself when the shell would (\" \\ \$ \`), else both stay.
        /// A backslash before a line break joins the lines in zsh (both vanish), which could hide a path's `..` from the
        /// gate: refused (security review C1).
        var escaped = false
        for character in command {
            if quoteEscape {
                guard character == "'" else { return nil }
                word.append(character)
                inWord = true
                quoteEscape = false
                continue
            }
            if escaped {
                if character.isNewline || character.unicodeScalars.contains(where: { $0 == "\n" || $0 == "\r" }) { return nil }
                if !"\"\\$`".contains(character) { word.append("\\") }
                word.append(character)
                escaped = false
                continue
            }
            switch quote {
            case "'":
                if character == "'" { quote = nil } else { word.append(character) }
            case "\"":
                if character == "\"" { quote = nil } else if character == "\\" { escaped = true } else if "$`".contains(character) { return nil } else { word.append(character) }
            default:
                if character == " " || character == "\t" {
                    if inWord { words.append(word); word = ""; inWord = false }
                } else if character == "'" || character == "\"" {
                    quote = character
                    inWord = true
                } else if character == "\\" {
                    quoteEscape = true
                } else if ";&|<>()$`\\\n*?[]{}#!".contains(character) {
                    return nil
                } else if character.unicodeScalars.contains(where: { $0 == "\n" || $0 == "\r" }) {
                    // Swift reads "\r\n" as one Character, unequal to "\n", but the shell still ends the command at its line
                    // break: outside quotes any line break is shell syntax (security review C1, desktop).
                    return nil
                } else {
                    word.append(character)
                    inWord = true
                }
            }
        }
        guard quote == nil, !escaped, !quoteEscape else { return nil }
        if inWord { words.append(word) }
        return words
    }
}
