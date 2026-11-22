//
//  ArisToolWords.swift
//  Shared/Core (aris-agent, tests)
//
//  aris-tools words read before a card (thirteenth VM run, item 4): a calendar event's delete or change is titled as
//  what it is on its card ("일정 지우기", never the bare "지우기" that read as a message to send), and words aris-tools would
//  refuse as a usage error are refused before any card, with the usage, so the one card that goes up is for words that
//  run (the delete needed two cards: the first one's yes ended in "usage: …"). Only stricter, and presentation. Pure.
//

import Foundation

enum ArisToolWords {
    /// `event delete|change`'s form, as aris-tools' ArisEventWords reads it.
    static let eventUsage = "usage: event delete --id <id> --title <title> --start \"YYYY-MM-DD HH:MM\" | "
        + "event change --id <id> --title <title> --start \"YYYY-MM-DD HH:MM\" [--to \"YYYY-MM-DD HH:MM\"] [--rename <new title>]"

    /// The card's own title for these words, when they are an act it names: nil for anything else.
    static func title(_ argv: [String]?) -> String? {
        guard let argv, argv.first == "event", argv.count > 1 else { return nil }
        switch argv[1] {
        case "delete": return "일정 지우기"
        case "change": return "일정 바꾸기"
        default: return nil
        }
    }

    /// Why these words can't run as they are (aris-tools would answer with its usage), said before any card; nil when
    /// they are not an event delete or change, or are one aris-tools reads.
    static func usageRefusal(_ argv: [String]?) -> String? {
        guard let argv, argv.first == "event", argv.count > 1, ["delete", "change"].contains(argv[1]) else { return nil }
        var words = Array(argv.dropFirst(2))
        let required = ["--id", "--title", "--start"]
        let optional = argv[1] == "change" ? ["--to", "--rename"] : []
        var missing: [String] = []
        for flag in required where take(flag, from: &words) == nil { missing.append(flag) }
        for flag in optional { _ = take(flag, from: &words) }
        guard !missing.isEmpty || !words.isEmpty else { return nil }
        let what = missing.isEmpty ? "words it doesn't take (" + words.prefix(3).joined(separator: " ") + ")" : "no " + missing.joined(separator: ", ")
        return "Not run, and nothing was asked: aris-tools would refuse these words (" + what + "). Find the event first (event find), then use "
            + "exactly this form: " + eventUsage
    }

    /// The value after `flag`, taken out of `words`; nil when the flag or a value for it isn't there.
    private static func take(_ flag: String, from words: inout [String]) -> String? {
        guard let index = words.firstIndex(of: flag), index + 1 < words.count, !words[index + 1].hasPrefix("--") else { return nil }
        let value = words[index + 1]
        words.removeSubrange(index...(index + 1))
        return value
    }
}
