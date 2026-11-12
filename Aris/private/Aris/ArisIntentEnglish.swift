//
//  ArisIntentEnglish.swift
//  Aris
//
//  The English ways of saying what Aris does on the Mac by itself (ArisIntent), where English needs more than a word
//  list: a to-do added ("add buy milk to my to-do list", "remind me to call mom"), one ticked off ("mark buy milk as
//  done"), windows laid out ("open 4 Excel windows in a grid"), the sound and the screen without the words "volume" or
//  "brightness" ("turn the sound down", "dim the screen"), and the small things around a request that change nothing
//  about it ("please", "can you …", "five minutes"). What Aris can do without an AI must not depend on the language
//  (VM run 2026-11-11, bug 1: the English to-do add needed an AI).
//  Every form is a whole sentence: one that goes on with something else ("add milk to my to-do list and mail it to
//  mom") matches nothing here and stays the AI's, and each keeps the guards its Korean form has. Foundation only, so
//  it is tested.
//

import Foundation

enum ArisEnglishAsk {
    // MARK: - The words around a request

    private static let lead = #"^(?:hey\s+)?(?:aris[,!]?\s+)?(?:please\s+)?(?:(?:can|could|would|will)\s+you\s+(?:please\s+)?|i(?:'d| would)\s+like\s+you\s+to\s+|i\s+(?:want|need)\s+you\s+to\s+)?(?:just\s+)?(?:go\s+ahead\s+and\s+)?"#
    private static let tail = #"(?:[\s,]+(?:please|for\s+me|thanks|thank\s+you|now))+$"#

    /// The request without what only makes it polite: "can you open Safari please" is "open safari". `phrase`: as
    /// ArisIntent reads the words (lowercased, end marks off).
    static func core(_ phrase: String) -> String {
        phrase.replacingOccurrences(of: tail, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: lead, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
    }

    /// A sentence that opens like a question ("did you set a timer", "is the timer on", "can i mute it"): speech often
    /// leaves the "?" off, and a question is never taken as a request to act (the "?" itself is ArisIntent.holdsBack's).
    static func opensAsQuestion(_ phrase: String) -> Bool {
        phrase.range(of: #"^(?:hey\s+)?(?:aris[,!]?\s+)?(?:did|does|do\s+(?:i|you|we|they|it)|is|are|was|were|am|has|have\s+(?:i|you|we|they)|had|should|shall|may|might|must|can\s+i|could\s+i|why|when|who|whose|whom|whether|if)\b"#,
                     options: .regularExpression) != nil
    }

    private static let ones = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9]
    private static let teens = ["ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17,
                                "eighteen": 18, "nineteen": 19]
    private static let tens = ["twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90]
    private static let unit = #"(?:more\s+)?(?:hours?|hrs?|minutes?|mins?|seconds?|secs?|percent)\b"#

    /// A length or a level said in words, as digits: "five minutes", "an hour", "half an hour", "twenty five percent".
    /// Only a number right before a unit is changed ("one more song" and "a minute ago" keep their words unless a unit
    /// follows the number itself).
    static func digits(_ phrase: String) -> String {
        guard phrase.range(of: #"\b(?:hours?|hrs?|minutes?|mins?|seconds?|secs?|percent)\b"#, options: .regularExpression) != nil else { return phrase }
        var text = phrase.replacingOccurrences(of: #"\ban?\s+hour\s+and\s+a\s+half\b"#, with: "90 minutes", options: .regularExpression)
            .replacingOccurrences(of: #"\bhalf\s+an\s+hour\b"#, with: "30 minutes", options: .regularExpression)
            .replacingOccurrences(of: #"\ba\s+couple\s+of\s+(?=(?:more\s+)?(?:hours|minutes|mins|seconds))"#, with: "2 ", options: .regularExpression)
        let small = (Array(ones.keys) + Array(teens.keys)).joined(separator: "|")
        let pattern = "\\b(?:(?:(" + tens.keys.joined(separator: "|") + ")(?:[ -](" + ones.keys.joined(separator: "|") + "))?|(" + small + "))(?=\\s+" + unit + ")"
            + #"|(an?)(?=\s+(?:hour|minute|min)\b))"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let whole = Range(match.range, in: text) else { continue }
            func group(_ index: Int) -> String? { Range(match.range(at: index), in: text).map { String(text[$0]) } }
            let value: Int
            if let ten = group(1).flatMap({ tens[$0] }) { value = ten + (group(2).flatMap { ones[$0] } ?? 0) } else if let word = group(3) { value = ones[word] ?? teens[word] ?? 0 } else { value = 1 }
            text.replaceSubrange(whole, with: String(value))
        }
        return text
    }

    // MARK: - To-dos

    private static let list = #"(?:to-?dos?|todos?|to[ -]?do\s+list|todo\s+list|reminders?(?:\s+list)?)"#
    private static let onList = #"\s+(?:to|on|onto|in|into)\s+(?:my\s+|the\s+|our\s+)?"# + list
    private static let adds = [
        // "add buy milk to my to-do list", "put call mom on my reminders".
        #"^(?:add|put|stick|pop)\s+(.+?)"# + onList + "$",
        // "add a to-do: buy milk", "add to-do call mom", "make a new to-do called buy milk".
        #"^(?:add|make|create|set)\s+(?:a\s+|an\s+|one\s+|another\s+)?(?:new\s+)?(?:to-?do|todo)\b(?:\s+item)?(?:\s+(?:to|for|called|that\s+says|saying)\b|\s*[:,–—-])?\s*(.*)$"#,
        // "new to-do: call mom", "to-do: buy milk".
        #"^new\s+(?:to-?do|todo)\b(?:\s+item)?\s*[:,–—-]?\s*(.*)$"#, #"^(?:to-?do|todo)\s*[:–—-]\s*(.*)$"#,
    ]
    /// "remind me to call mom", "add a reminder to call mom", "set a reminder for the dentist", "reminder: call mom".
    private static let reminds = [
        #"^remind\s+me\s+(?:to|about|that)\s+(.+)$"#,
        #"^(?:add|make|create|set)\s+(?:a\s+|an\s+|one\s+|another\s+)?(?:new\s+)?reminder\b(?:\s+(?:to|for|about|called|that\s+says|saying)\b|\s*[:,–—-])?\s*(.*)$"#,
        #"^(?:new\s+)?reminder\s*[:–—-]\s*(.*)$"#,
    ]
    /// A time Aris's own to-do can't keep ("in 10 minutes", "every Monday", "when I get home"): such a reminder is the
    /// AI's to set up, never a to-do saved without the time it was asked for.
    private static let unkeptTime = #"\b(?:in\s+(?:\d+|an?|half|a\s+few|a\s+couple)\b|every|each|later|tonight|next\s+(?:week|month|year)|this\s+(?:morning|afternoon|evening|weekend)|in\s+the\s+(?:morning|afternoon|evening)|at\s+(?:noon|midnight|night|\d)|when|after|before|until|\d{1,2}\s*(?:am|pm)\b|\d{1,2}:\d{2})"#

    /// The item of a plain English add; nil when the sentence isn't one, "" when it names nothing. The sentence is
    /// nothing but the add, and holds none of the words that undo, take away, refuse or ask (ArisIntent.notAnAdd, the
    /// Korean form's own guard).
    static func todoToAdd(_ spoken: String, now: Date = Date()) -> String? {
        let kept = said(spoken), phrase = kept.lowercased()
        guard !ArisIntent.notAnAdd.contains(where: phrase.contains), !opensAsQuestion(phrase) else { return nil }
        for pattern in reminds {
            guard let item = group(pattern, in: kept) else { continue }
            // "remind me to call mom tomorrow at 5" is a to-do with its day and time; a time a to-do can't keep is the AI's.
            let rest = ArisTodoDate.parse(item, now: now).text
            // "remind me to do that", "remind me about it tomorrow": what "that" is, only the AI can tell (ArisPointsBack).
            if ArisPointsBack.onlyAsTask(rest) { return "" }
            return rest.range(of: unkeptTime, options: [.regularExpression, .caseInsensitive]) == nil && !namesAThing(item) ? clean(item) : nil
        }
        for pattern in adds {
            guard let item = group(pattern, in: kept) else { continue }
            return namesAThing(item) ? nil : clean(item)
        }
        return nil
    }

    /// "make a to-do list for my trip", "create a todo app in Swift", "add a reminder widget": the words after "to-do"
    /// name a thing to make, not an item to add.
    private static func namesAThing(_ item: String) -> Bool {
        let first = clean(item).lowercased().split(separator: " ").first.map(String.init) ?? ""
        return ["list", "lists", "app", "apps", "application", "widget", "website", "site", "page", "template", "program", "feature", "api", "cli"].contains(first)
    }

    /// The words as he wrote them (the item keeps its capitals), without the end marks and what only makes them polite.
    private static func said(_ spoken: String) -> String {
        core(spoken.replacingOccurrences(of: "’", with: "'").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".!"))))
    }

    private static let offList = #"\s+(?:on|from|in|off)\s+(?:my\s+|the\s+|our\s+)?"# + list + "$"
    private static let dones = [
        // "mark buy milk as done", "check off buy milk", "tick buy milk off", "cross off buy milk".
        #"^(?:mark|check|tick|cross)\s+(?:off\s+)?(.+?)(?:\s+(?:as\s+)?(?:done|complete|completed|finished)|\s+off)$"#,
        #"^(?:check|tick|cross)\s+off\s+(.+)$"#,
        // "i finished buy milk", "i'm done with buy milk", "done with buy milk".
        #"^(?:(?:i|we)(?:'ve| have)?\s+)?(?:just\s+)?(?:finished|completed)\s+(.+)$"#,
        #"^(?:(?:i'm|i am|im|we're|we are)\s+)?(?:all\s+)?done\s+with\s+(.+)$"#,
        // "buy milk is done".
        #"^(.+?)\s+(?:is|are)\s+(?:all\s+)?(?:done|finished|complete|completed)$"#,
    ]

    /// "<item> is done", "i finished <item>", "mark <item> as done": the item; nil when the sentence isn't one of these.
    /// Whether it is ticked is decided as for the Korean form: only an open item those words name exactly.
    static func todoDone(_ spoken: String) -> String? {
        let kept = said(spoken)
        guard !opensAsQuestion(kept.lowercased()) else { return nil }
        for pattern in dones {
            guard let found = group(pattern, in: kept) else { continue }
            let item = clean(found.replacingOccurrences(of: offList, with: "", options: [.regularExpression, .caseInsensitive]))
            // "i'm done with it", "that is done": a word that names no item.
            return item.isEmpty || ["it", "that", "this", "everything", "them", "all"].contains(item.lowercased()) ? nil : item
        }
        return nil
    }

    private static func clean(_ item: String) -> String {
        item.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'“”‘’:,.-–—")))
    }

    /// The first group of `pattern` in `text`, any case; nil when it doesn't match.
    private static func group(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    // MARK: - Opening an app, windows in a grid

    private static let openVerbs = ["open up", "open", "launch", "start up", "start", "switch to", "bring up", "pull up", "fire up"]
    /// Words that make the rest more than an app's name ("open the file on my desktop", "open a tab with my mail").
    private static let notAName = #"\b(?:on|in|from|with|about|at|for|of|and|then|that|which)\b|[,;:?]"#

    /// The app an English request asks to open, as said (the caller gives it its own spelling); nil when the words are
    /// not just "open <an app>". Whether this Mac has such an app is checked where it is opened.
    static func appToOpen(_ phrase: String) -> String? {
        let said = core(phrase)
        guard let verb = openVerbs.first(where: { said.hasPrefix($0 + " ") }) else { return nil }
        let name = String(said.dropFirst(verb.count + 1))
            .replacingOccurrences(of: #"^(?:the|my|a|an)\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+(?:app|application|again)$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name.split(separator: " ").count <= 4, name.range(of: notAName, options: .regularExpression) == nil else { return nil }
        return name
    }

    /// "open 4 excel windows in a grid", "put 2 safari windows side by side", "tile 3 finder windows": the app as said
    /// and how many windows; nil when the sentence isn't that.
    static func arrangement(_ phrase: String) -> (app: String, count: Int)? {
        let said = core(phrase)
        let laidOut = #"\s+(?:side\s+by\s+side|in\s+a\s+grid|tiled|next\s+to\s+each\s+other)"#
        let patterns = [#"^(?:open|put|show|make|give\s+me)\s+(\d)\s+(?:new\s+)?(.+?)\s+windows?"# + laidOut + "$",
                        #"^(?:tile|arrange)\s+(\d)\s+(?:new\s+)?(.+?)\s+windows?(?:"# + laidOut + ")?$"]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: said, range: NSRange(said.startIndex..., in: said)),
                  let count = Range(match.range(at: 1), in: said).flatMap({ Int(said[$0]) }), let name = Range(match.range(at: 2), in: said) else { continue }
            return (String(said[name]), count)
        }
        return nil
    }

    // MARK: - The sound and the screen

    /// "turn the sound down", "turn up the audio", "sound to 30": the Mac's volume asked for without the word (the
    /// Korean 소리). Only the whole sentence, so "send this sound file to 3 people" is never a volume.
    static func soundLevel(_ phrase: String) -> ArisIntent.Level? {
        let said = core(phrase)
        let bit = #"(?:\s+a\s+(?:bit|little|touch))?$"#
        let subject = #"(?:the\s+|my\s+)?(?:sound|audio)"#
        if let word = group("^(?:turn|make|put)\\s+" + subject + #"\s+(up|down|louder|quieter|lower|higher)"# + bit, in: said)
            ?? group(#"^turn\s+(up|down)\s+"# + subject + bit, in: said) {
            return ["up", "louder", "higher"].contains(word) ? .up : .down
        }
        if let number = group("^(?:set\\s+|turn\\s+|put\\s+)?" + subject + #"\s+(?:to\s+|at\s+)?(\d{1,3})(?:\s*percent|\s*%)?$"#, in: said).flatMap({ Int($0) }) {
            return .set(min(100, max(0, number)))
        }
        return nil
    }

    /// "dim the screen", "brighten the display": the screen's brightness asked for without the word.
    static func screenLevel(_ phrase: String) -> ArisIntent.Level? {
        guard let verb = group(#"^(dim|darken|brighten|lighten)\s+(?:the\s+|my\s+)?(?:screen|display)(?:\s+a\s+(?:bit|little|touch))?$"#, in: core(phrase)) else { return nil }
        return verb == "brighten" || verb == "lighten" ? .up : .down
    }
}
