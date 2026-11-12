//
//  ArisEventWords.swift
//  aris-tools
//
//  The words of `aris-tools event find|delete|change …` as the request the Aris app answers (POST /aris/events,
//  ArisEventRoute). `event find <title> --start …` finds one exact event; `event find --from <day> [--to <day>]` lists
//  the events of those days (audit tools-imp-1: nothing could read past the coming week). Both are reads; delete and
//  change name the event by its id, title and start and are always the user's card. Pure, so the tests run it.
//

import Foundation

enum ArisEventWords {
    /// The usage line (the app's ArisEventEdit has the same).
    static let usage = "usage: event find <title> --start \"YYYY-MM-DD HH:MM\" | event find --from \"YYYY-MM-DD\" [--to \"YYYY-MM-DD\"] | " +
        "event delete --id <id> --title <title> --start \"YYYY-MM-DD HH:MM\" | " +
        "event change --id <id> --title <title> --start \"YYYY-MM-DD HH:MM\" [--to \"YYYY-MM-DD HH:MM\"] [--rename <new title>]"

    /// The app's request body for these words, or nil when they aren't one of the forms.
    static func body(_ args: [String]) -> [String: Any]? {
        var words = Array(args.dropFirst())
        guard let verb = args.first, ["find", "delete", "change"].contains(verb) else { return nil }
        // The list: days only, no title.
        if verb == "find", let from = option("--from", in: &words) {
            var body: [String: Any] = ["op": "list", "from": from]
            if let to = option("--to", in: &words) { body["to"] = to }
            return words.isEmpty ? body : nil
        }
        guard let start = option("--start", in: &words) else { return nil }
        var body: [String: Any] = ["op": verb, "start": start]
        if verb == "find" {
            let title = words.joined(separator: " ")
            guard !title.isEmpty else { return nil }
            body["title"] = title
            return body
        }
        guard let id = option("--id", in: &words), let title = option("--title", in: &words) else { return nil }
        body["id"] = id
        body["title"] = title
        if verb == "change" {
            if let to = option("--to", in: &words) { body["to"] = to }
            if let rename = option("--rename", in: &words) { body["rename"] = rename }
        }
        return words.isEmpty ? body : nil
    }

    /// The value after `flag` (removed from `words`), if any.
    private static func option(_ flag: String, in words: inout [String]) -> String? {
        guard let index = words.firstIndex(of: flag), index + 1 < words.count else { return nil }
        let value = words[index + 1]
        words.removeSubrange(index...(index + 1))
        return value
    }
}
