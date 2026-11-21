//
//  ArisOutboundReads.swift
//  aris-agent
//
//  The reads whose arguments leave the Mac (Core 2 review, 2026-11-19): what each one sends, for the trust gate's
//  outbound rule (ArisWebCarry: once something private was read, such a read is a look only when all it sends is
//  accounted for). The helper's own web.fetch and web.search, and every aris-tools row rated a look whose arguments go
//  to a service: `web fetch`, `weather <place>`, `maps directions --json`, `maps search --json`, `stock`, `currency`.
//  Every other row rated a look is listed in `staysOnMac` (it reads the Mac, or a service with no argument of the
//  call), so a new row rated a look is in one list or the other: the tests fail otherwise.
//

import Foundation

enum ArisOutboundReads {
    /// The rows rated a look whose arguments go to a service, by their command words. What each sends is every word
    /// of the call after its command words, joined by single spaces (the tools' own parsers, ArisWeather.request and
    /// ArisMapsCard.request, live in aris-tools): an extra flag, a repeated setting or an odd value is sent as written.
    static let rows: Set<[String]> = [
        ["web", "fetch"], ["weather"], ["maps", "directions", "--json"], ["maps", "search", "--json"], ["stock"], ["currency"],
    ]

    /// The other rows rated a look: they read the Mac, Aris's own stores, or a service with nothing of the call's
    /// arguments (Canvas, Devin, a connected service's listing, a skill).
    static let staysOnMac: Set<[String]> = [
        ["canvas"], ["brief"], ["todo"], ["find"], ["memory"], ["recall"], ["recall", "--tainted"], ["shortcuts"], ["event", "find"],
        ["calendars"], ["selection"], ["clipboard"], ["tab"], ["finder"], ["shelf"], ["screen"], ["windows"], ["activity"],
        ["schedule", "list"], ["mcp", "list"], ["mcp", "wait"], ["skill", "list"], ["skill", "read"], ["session", "list"],
        ["devin", "sessions"], ["messages", "recent"], ["mail", "recent"], ["mail", "search"], ["notes", "recent"], ["notes", "search"],
        ["files", "find"], ["files", "read"], ["obsidian", "search"], ["turn-gate"], ["sealed-gate"], ["--version"],
    ]

    /// What the call sends off the Mac; nil when it is no outbound read. `tools`: aris-tools' path, for a shell line's
    /// aris-tools parts.
    static func sends(capability: String, arguments: [String: Any], argv: [String]?, tools: String = ArisAppBundle.toldTools) -> ArisOutbound? {
        switch capability {
        case "web.fetch": return ArisOutbound(urls: [(arguments["url"] as? String) ?? ""], publicWeb: true)
        case "web.search": return ArisOutbound(queries: [(arguments["query"] as? String) ?? ""], publicWeb: true)
        case "shell.run":
            let command = arguments["command"] as? String ?? ""
            let parts = (ArisCommandPolicy.segments(command) ?? []).compactMap { piece -> ArisOutbound? in
                guard let words = ArisCommandPolicy.words(piece), words.first == tools else { return nil }
                return sends(argv: Array(words.dropFirst()))
            }
            guard !parts.isEmpty else { return nil }
            // A shell line's output is the shell's (never the public web's), whatever it fetched.
            return ArisOutbound(urls: parts.flatMap(\.urls), queries: parts.flatMap(\.queries))
        default:
            return argv.flatMap(sends(argv:))
        }
    }

    /// The weather's place words: the call without the tool's own settings, each at most once and well formed (one
    /// `--ko` or `--en`, one `--days` with a whole number from 1 to 16: the answer's language and length, a closed set that
    /// carries no text; tenth VM run, item 9: "Orlando --ko" was carded as a send). Anything else (a repeated setting,
    /// `--days` with other words, an unknown flag) is left in and so is sent, and asked about, as written.
    static func weatherPlace(_ words: [String]) -> [String] {
        var rest = words
        let languages = rest.filter { $0 == "--ko" || $0 == "--en" }
        if languages.count == 1 { rest.removeAll { $0 == languages[0] } }
        if rest.filter({ $0 == "--days" }).count == 1, let flag = rest.firstIndex(of: "--days"), flag + 1 < rest.count,
           let days = Int(rest[flag + 1]), (1...16).contains(days), String(days) == rest[flag + 1] {
            rest.removeSubrange(flag...(flag + 1))
        }
        return rest
    }

    /// An aris-tools call's sends, by its row: the whole call after its command words (the row's own `--json` once).
    static func sends(argv: [String]) -> ArisOutbound? {
        guard let row = ArisCapabilities.capability(argv), rows.contains(row.command) else { return nil }
        var rest = Array(argv.dropFirst(row.command.filter { !$0.hasPrefix("--") }.count))
        for flag in row.command where flag.hasPrefix("--") {
            if let index = rest.firstIndex(of: flag) { rest.remove(at: index) }
        }
        if row.command == ["weather"] { rest = weatherPlace(rest) }
        let sent = rest.joined(separator: " ")
        return row.command == ["web", "fetch"] ? ArisOutbound(urls: [sent], publicWeb: true) : ArisOutbound(queries: [sent])
    }
}
