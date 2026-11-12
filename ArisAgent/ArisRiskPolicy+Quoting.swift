//
//  ArisRiskPolicy+Quoting.swift
//  aris-agent
//
//  How the never-list reads a command line (audit gate-7). A word after ( ; & | inside double quotes is text, not a
//  command: "보안 점검 (security 팀 회의)" as a to-do, "오늘 늦어; reboot 하고 갈게" as a message. The shell runs nothing
//  there except a backtick or $( … ), so only those cut inside double quotes, as ArisProtectedPlaces already reads it.
//  And when the whole line reads as plain aris-tools calls (no shell syntax at all), the text a note, message, to-do,
//  reminder, event or board carries is data that never reaches a shell: the never-list, the hook-token check and the
//  Calendar-app check look at the program, the subcommand and the flags, never at the user's words.
//

import Foundation

extension ArisRiskPolicy {
    /// The line cut wherever a command could start: outside quotes at ; & | ( a line break or a backtick; inside double
    /// quotes only at a backtick or $( (all the shell runs there); never inside single quotes (a note's table rows,
    /// `| 가격 | … |`). An escaped separator still cuts, as before. Where the shell could read quotes differently from
    /// this scan (a # comment, a << heredoc, $'…', an unclosed quote), the whole line is cut everywhere.
    static func commandStarts(_ command: String) -> [String] {
        let everywhere = command.components(separatedBy: CharacterSet(charactersIn: ";&|\n\r`("))
        let separators: Set<Character> = [";", "&", "|", "`", "("]
        var pieces: [String] = []
        var piece = ""
        var single = false, double = false, escaped = false
        var previous: Character?
        for character in command {
            defer { previous = character }
            // Any line break ("\r\n" is one Character, unequal to "\n") ends a command outside quotes.
            let isSeparator = separators.contains(character) || character.isNewline
            if escaped {
                escaped = false
                if isSeparator { pieces.append(piece); piece = "" } else { piece.append(character) }
                continue
            }
            if !single, !double {
                if character == "#" || (character == "<" && previous == "<") || (character == "'" && previous == "$") { return everywhere }
            }
            if character == "\\", !single { escaped = true; piece.append(character); continue }
            if character == "'", !double { single.toggle() } else if character == "\"", !single { double.toggle() }
            let cuts = single ? false : double ? character == "`" || (character == "(" && previous == "$") : isSeparator
            if cuts {
                pieces.append(piece)
                piece = ""
            } else {
                piece.append(character)
            }
        }
        pieces.append(piece)
        return single || double ? everywhere : pieces
    }

    /// aris-tools subcommands whose plain arguments are only text Aris stores, shows or sends (never a path, a program
    /// or an address): what the user dictates may hold any word.
    private static let textTools: Set<String> = ["note", "message", "todo", "board", "remind", "event", "remember", "forget"]

    /// The line as the never-list, the hook-token check and the Calendar-app check read it. When every chained command
    /// reads word by word (ArisCommandPolicy: no $, backtick, pipe, redirect or bracket anywhere, so the shell runs
    /// nothing inside the words), a text tool's words are dropped and only its program, subcommand and flags are left;
    /// `clipboard set <text>` and `web fetch <https address>` likewise. Every other chained command stays exactly as it
    /// was written, and any other line comes back unchanged, to be scanned whole.
    static func withoutPlainText(_ command: String, tools: String) -> String {
        guard !tools.isEmpty, let pieces = ArisCommandPolicy.segments(command) else { return command }
        var kept: [String] = []
        for piece in pieces {
            guard let words = ArisCommandPolicy.words(piece) else { return command }
            kept.append(textFree(words, tools: tools)?.map(ArisEditableAction.quoted).joined(separator: " ") ?? piece)
        }
        return kept.joined(separator: " ; ")
    }

    /// A text tool's call without its text (its program, subcommand and flags); nil for any other command.
    private static func textFree(_ words: [String], tools: String) -> [String]? {
        guard words.count > 1, words[0] == tools else { return nil }
        let tool = words[1], rest = Array(words.dropFirst(2))
        if textTools.contains(tool) { return [tools, tool] + rest.filter { $0.hasPrefix("-") } }
        if tool == "clipboard", rest.first == "set" { return [tools, tool, "set"] }
        // One public page by its address: the address names a site, never a file of Aris's.
        if tool == "web", rest.count == 2, rest[0] == "fetch", rest[1].lowercased().hasPrefix("https://") || rest[1].lowercased().hasPrefix("http://") {
            return [tools, tool, "fetch"]
        }
        return nil
    }
}
