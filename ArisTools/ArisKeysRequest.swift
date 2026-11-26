//
//  ArisKeysRequest.swift
//  aris-tools
//
//  `keys <chord…> [--app X] [--title <window>] [--times N]`, read once for aris-tools and for the gates (fourteenth VM
//  run, R1b: "이 문서 글 전부 지우고 '교체된 내용'이라고 써 줘" put up a raw "Press keys · cmd+a delete --app TextEdit
//  --title Untitled" card, and on its yes only cmd+a was sent: aris-tools read the first chord alone). Every chord given
//  is sent now (at most eight, as the agent's keys route takes them). Keys that only select everything or erase (a
//  select-all, a bare delete or backspace, nothing else) are the desktop engine's `desktop press` in that app inside a brain's
//  turn: its gate reads the text they would erase and shows it on its one erase card, holds a select-all back until
//  what replaces it comes, and asks every time, so the shell gate asks nothing of its own for them (as for `type`).
//  Pure (tested).
//

import Foundation

enum ArisKeysRequest {
    struct Call: Equatable {
        let chords: [String]
        let app: String?
        let title: String?
        let times: Int
    }

    static let usage = "usage: keys cmd+shift+t [more keys…] [--app X] [--title <window>] [--times N]"
    static let noAppLine = "no app has the keyboard to send keys to (name it with --app)"
    /// The most chords one call sends (the agent's /desktop-keys route takes as many).
    static let mostChords = 8
    /// The most chords one `desktop press` takes (ArisDesktopWords.maxChords), the repeats included.
    static let engineMostChords = 12

    /// The flags `keys` takes, each with one value, each at most once.
    private static let flags: Set<String> = ["--app", "--title", "--times"]

    /// The call, or why not: chords are the words that aren't a flag or a flag's value, each shaped like a key.
    static func parse(_ args: [String]) -> Result<Call, ArisKeysRequestError> {
        var values: [String: String] = [:]
        var chords: [String] = []
        var index = 0
        while index < args.count {
            let word = args[index]
            index += 1
            guard word.hasPrefix("-") else {
                guard looksLikeChord(word) else { return .failure(ArisKeysRequestError(line: usage)) }
                chords.append(word)
                continue
            }
            guard flags.contains(word), values[word] == nil, index < args.count, !args[index].hasPrefix("-"), !args[index].isEmpty else {
                return .failure(ArisKeysRequestError(line: flags.contains(word) ? usage : "keys doesn't take \(word). " + usage))
            }
            values[word] = args[index]
            index += 1
        }
        guard (1...mostChords).contains(chords.count) else { return .failure(ArisKeysRequestError(line: usage)) }
        let times = min(20, max(1, values["--times"].flatMap { Int($0) } ?? 1))
        return .success(Call(chords: chords, app: values["--app"], title: values["--title"], times: times))
    }

    /// A word shaped like a key (`return`, `cmd+a`, `shift+tab`): letters, digits, `+` and key punctuation, never a flag.
    static func looksLikeChord(_ word: String) -> Bool {
        word.lowercased().range(of: #"^[a-z0-9+,./;'\[\]\\=`]{1,40}$"#, options: .regularExpression) != nil
    }

    /// A chord as a set of key names, aliases mapped (as ArisDesktopBatch.normalized reads them).
    static func normalized(_ chord: String) -> Set<String> {
        let aliases = ["command": "cmd", "meta": "cmd", "super": "cmd", "⌘": "cmd", "control": "ctrl", "option": "alt", "opt": "alt",
                       "backspace": "delete", "forwarddelete": "delete", "del": "delete"]
        return Set(chord.lowercased().split(separator: "+").map { aliases[String($0)] ?? String($0) })
    }

    /// The keys only select everything or erase text: each chord exactly a select-all or a bare delete (backspace or
    /// forward delete), nothing held with it. An allowlist: cmd+delete (Finder's move to the Trash), option+delete and
    /// any other chord stay the shell gate's, as before.
    static func erases(_ chords: [String]) -> Bool {
        !chords.isEmpty && chords.allSatisfy { chord in
            let keys = normalized(chord)
            return keys == ["cmd", "a"] || keys == ["delete"]
        }
    }

    /// The desktop engine's words for an erasing call: `press <chords × times> --app <app> [--title <window>]`.
    static func desktopWords(_ call: Call, keyboardApp: String?) -> Result<[String], ArisKeysRequestError> {
        guard let app = call.app ?? keyboardApp, !app.trimmingCharacters(in: .whitespaces).isEmpty else { return .failure(ArisKeysRequestError(line: noAppLine)) }
        let pressed = Array(repeating: call.chords, count: call.times).flatMap { $0 }
        guard pressed.count <= engineMostChords else { return .failure(ArisKeysRequestError(line: usage)) }
        return .success(["press"] + pressed + ["--app", app] + (call.title.map { ["--title", $0] } ?? []))
    }

    /// Whether one engine press takes all of the call's presses (more stay the shell gate's, on its card, as before).
    static func fitsEngine(_ call: Call) -> Bool { call.chords.count * call.times <= engineMostChords }

    /// Whether aris-tools' words (`keys …`, after the program) are an erasing call it hands to the desktop engine.
    static func handsToEngine(_ rest: [String]) -> Bool {
        guard rest.first == "keys", case .success(let call) = parse(Array(rest.dropFirst())) else { return false }
        return erases(call.chords) && fitsEngine(call)
    }
}

struct ArisKeysRequestError: Error, Equatable {
    let line: String
}
