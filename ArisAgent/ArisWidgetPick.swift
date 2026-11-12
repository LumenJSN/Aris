//
//  ArisWidgetPick.swift
//  aris-agent
//
//  The answer card a conversation turn earned by what it ran (ArisWidget in the app): the last `aris-tools weather`,
//  `timer`, `todo`, `music`, `stock` or `maps … --json` command the brain used picks the card, and the answer gets one
//  ```aris-card block naming it (with the place or the symbol the command looked up). The block carries no value: the app reads the card's
//  numbers itself and takes the block out of what is shown and said. The calendar and what's playing come from the
//  context with no command, so for those the brain writes the block (ArisAgentPrompt.cardRule). One card comes before
//  the others: a read the turn ran that needs a permission aris-agent doesn't have now (`messages`, `mail` or `notes`
//  without Full Disk Access, `screen` without Screen Recording) picks the permission card, whose button opens that
//  list in System Settings (QA after a macOS update: those reads failed and nothing said why).
//

import Foundation

enum ArisWidgetPick {
    /// The fence's language tag (ArisWidget.tag in the app).
    static let tag = "aris-card"

    /// What aris-agent may read: Full Disk Access (Messages, Mail, Notes) and Screen Recording (the screen).
    struct Access: Equatable {
        var disk = true
        var screen = true
        // `now`, as macOS has it at this moment, is in ArisScreenAccess+Live (a new process answers: VM bug 1).
    }

    /// The reads that need Full Disk Access.
    static let diskReads: Set<String> = ["messages", "mail", "notes"]

    /// The permission a read of the turn needed and aris-agent doesn't have: "disk" or "screen" (ArisPermissionPane in the
    /// app); nil when every read it ran had what it needed.
    static func missingPermission(commands: [String], tools: String, access: Access) -> String? {
        let ran = Set(commands.flatMap(invocations).compactMap { words in words.count >= 2 && isTools(words[0], tools: tools) ? words[1] : nil })
        if !access.disk, !ran.isDisjoint(with: diskReads) { return "disk" }
        return !access.screen && ran.contains("screen") ? "screen" : nil
    }

    /// The card the turn's commands pick, as the block's JSON fields: a permission that was missing first, then the last
    /// command that names a card. Nil when none does (or a timer was only stopped).
    static func card(commands: [String], tools: String, access: Access = Access()) -> [String: String]? {
        if let pane = missingPermission(commands: commands, tools: tools, access: access) { return ["type": "permission", "pane": pane] }
        return commands.flatMap(invocations).compactMap { words -> [String: String]? in
            guard words.count >= 2, isTools(words[0], tools: tools) else { return nil }
            let rest = Array(words.dropFirst(2))
            switch words[1] {
            case "weather":
                let place = placeWords(rest).joined(separator: " ")
                return place.isEmpty ? ["type": "weather"] : ["type": "weather", "place": place]
            case "timer": return rest.first == "stop" ? nil : ["type": "timer"]
            case "todo": return ["type": "todo"]
            case "music": return ["type": "music"]
            case "stock":
                let symbol = placeWords(rest).joined(separator: " ")
                return symbol.isEmpty ? nil : ["type": "stock", "symbol": symbol]
            case "currency": return ArisCurrencyRoute.card(rest)
            case "maps": return mapCard(rest)
            default: return nil
            }
        }.last
    }

    /// `answer` with the card's block at its end, when the commands pick one; unchanged otherwise.
    static func attach(to answer: String, commands: [String], tools: String, access: Access = Access()) -> String {
        guard let card = card(commands: commands, tools: tools, access: access),
              let data = try? JSONSerialization.data(withJSONObject: card, options: [.sortedKeys]) else { return answer }
        return answer + "\n\n```\(tag)\n" + String(decoding: data, as: UTF8.self) + "\n```"
    }

    /// Words that mean "where I am now" as a start (ArisMapsLink.here in aris-tools; the tests hold them equal).
    static let here: Set<String> = ["here", "current location", "my location", "여기", "현재 위치", "지금 위치", "내 위치", "현위치"]

    /// The map card of `maps search <words> --json` or `maps directions <from> <to> --json` (a lookup; Maps opened
    /// is no card).
    private static func mapCard(_ rest: [String]) -> [String: String]? {
        guard rest.contains("--json") else { return nil }
        let words = rest.filter { !$0.hasPrefix("--") }
        switch words.first {
        case "search":
            let place = words.dropFirst().joined(separator: " ")
            return place.isEmpty ? nil : ["type": "map", "place": place]
        case "directions" where words.count == 3:
            return here.contains(words[1].lowercased()) ? ["type": "map", "place": words[2]]
                : ["type": "map", "place": words[2], "from": words[1]]
        default:
            return nil
        }
    }

    /// POST /stock's arguments: `stock <symbol> --json`, the symbol read as ArisWidget.symbol reads it; nil (no card)
    /// for anything else.
    static func stockArguments(request object: [String: Any]) -> [String]? {
        name(object["symbol"], longest: 40, extra: "^=&").map { ["stock", $0, "--json"] }
    }

    /// POST /maps's arguments: `maps search <place> --json`, or `maps directions <from> <place> --json` with a start;
    /// nil (no card) when the place or the start isn't one.
    static func mapsArguments(request object: [String: Any]) -> [String]? {
        guard let place = name(object["place"], longest: 80, extra: "&") else { return nil }
        guard let raw = object["from"], !(raw is NSNull) else { return ["maps", "search", place, "--json"] }
        return name(raw, longest: 80, extra: "&").map { ["maps", "directions", $0, place, "--json"] }
    }

    /// POST /weather's place, read as ArisWidget.place reads it in the app: a place name (letters, digits, spaces and
    /// . , ' - ·, at most 60, never starting with "-", since it goes to aris-tools as one argument); nil for home or
    /// anything else.
    static func place(_ raw: Any?) -> String? { name(raw, longest: 60, extra: "") }

    private static func name(_ raw: Any?, longest: Int, extra: String) -> String? {
        guard let text = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty, text.count <= longest,
              !text.hasPrefix("-") else { return nil }
        let allowed = CharacterSet.letters.union(.decimalDigits).union(CharacterSet(charactersIn: " .,'-·" + extra))
        return text.unicodeScalars.allSatisfy(allowed.contains) ? text : nil
    }

    /// aris-tools' arguments for the card's weather.
    static func weatherArguments(place: String?) -> [String] {
        ["weather"] + (place.map { [$0] } ?? []) + ["--json"]
    }

    /// POST /weather's arguments: home with no place, the place when it reads as one, and nil (no card) when one was
    /// given that doesn't, never the home weather in its stead.
    static func weatherArguments(request object: [String: Any]) -> [String]? {
        guard let raw = object["place"], !(raw is NSNull) else { return weatherArguments(place: nil) }
        return place(raw).map { weatherArguments(place: $0) }
    }

    /// Each command's plain words: Codex's `zsh -lc` unwrapped, `&&` and `;` chains split, anything with other shell
    /// syntax skipped.
    private static func invocations(_ command: String) -> [[String]] {
        let inner = ArisCommandPolicy.unwrap(command)
        return (ArisCommandPolicy.segments(inner) ?? [inner]).compactMap(ArisCommandPolicy.words)
    }

    private static func isTools(_ word: String, tools: String) -> Bool {
        word == tools || word == "aris-tools" || word.hasSuffix("/aris-tools")
    }

    /// The place words of `weather`: its flags (--ko, --en, --json, --days N) left out.
    private static func placeWords(_ words: [String]) -> [String] {
        var out: [String] = [], skip = false
        for word in words {
            if skip { skip = false; continue }
            if word == "--days" { skip = true; continue }
            if word.hasPrefix("--") { continue }
            out.append(word)
        }
        return out
    }
}
