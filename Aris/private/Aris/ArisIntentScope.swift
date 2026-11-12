//
//  ArisIntentScope.swift
//  Aris
//
//  How much of a sentence an everyday request is. Aris does a request on the Mac itself only when the sentence is
//  nothing but that request: "사파리 열어 줘" opens Safari, but "메일 열어서 안 읽은 거 요약해 줘" goes on after its first
//  act, and "오늘 날짜로 폴더 하나 만들어 줘" only has the date's words inside a longer request. Both are the AI's,
//  whole (audit intent-1, intent-2: each used to be cut down to the part a matcher recognised).
//  Foundation only, so it is tested.
//

import Foundation

enum ArisIntentScope {
    /// A verb ending that joins a second act on ("열어서 …", "켜고 …", "…으로 하고 …", "끝나면 …"), "그리고", "and", "then".
    /// "…고 싶어" is a wish for the one act, not a second one.
    private static let joins = #"(?:하고|해서|하면서|하면|한 ?다음|한 ?뒤|한 ?후|하고 ?나서|열고|열어서|켜고|켜서|끄고|꺼서|틀고|틀어서|띄우고|띄워서"#
        + #"|올리고|올려서|내리고|내려서|줄이고|줄여서|낮추고|낮춰서|높이고|높여서|키우고|키워서|맞추고|맞춰서|멈추고|멈춰서|넘기고|넘겨서|바꾸고|바꿔서"#
        + #"|놓고|두고|끝나면|되면|울리면|지나면|그리고|그 ?다음에?|그런 ?다음에?|그러고)\s+(?!싶)\S"#
        + #"|\b(?:and|then|after that|and then)\b\s+(?!\d)\S"#
        // English joins without an "and": a comma and a new verb ("pause the music, set a timer"), "also", "when it ends".
        + #"|[,;]\s*(?:and\s+|then\s+|also\s+|please\s+)*(?:open|launch|start|set|play|pause|resume|stop|skip|turn|add|put|mute|unmute|tell|show|read|send|make|create|write|check|remind|close|quit|search|find|email|text|call|save|copy|move|delete|remove|go|give|run)\b"#
        + #"|\b(?:also|followed\s+by|as\s+well\s+as)\b\s+\S|\b(?:when|once|after|before|as\s+soon\s+as)\s+(?:it|that|this|you|i|the\s+timer|the\s+song|the\s+music)\b"#

    /// The words go on to a second act after the first: more than one everyday request can be.
    static func goesOn(_ phrase: String) -> Bool {
        // "Aris, set a timer" and "ok, open Safari" call or open the one request: that comma joins nothing on.
        let said = phrase.replacingOccurrences(of: #"^(?:(?:hey|ok|okay|alright|so|now|please|아리스(?:야|아)?|aris)\s*[,!]?\s*)+"#, with: "", options: [.regularExpression, .caseInsensitive])
        return said.range(of: joins, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// What may follow the verb of a request to open an app: only its ending ("열어" + "줘", "켜" + " 놔 줘", "실행" + "해
    /// 주세요"). Anything else is more of the sentence, so the request is not just "open it".
    private static let ending = #"^(?:해|시켜|하기)?\s*(?:놔|둬|봐)?\s*(?:줘|줘요|줘봐|줘 봐|줘라|주세요|줄래|줄래요|주실래요|주시겠어요|주실 수 있어요|줄 수 있어|줄수있어|라|요)?$"#

    static func isRequestEnding(_ rest: String) -> Bool {
        rest.trimmingCharacters(in: .whitespaces).range(of: ending, options: .regularExpression) != nil
    }

    /// The phrase is one of `core` and, around it, only `small` words (a name, "지금", "알려 줘", a sentence ending):
    /// nothing else is asked. Korean small words may run together ("알려줘"); English ones are whole words.
    static func isOnly(_ phrase: String, about core: [String], with small: [String]) -> Bool {
        var rest = phrase
        var found = false
        for words in core.sorted(by: { $0.count > $1.count }) {
            let pattern = ascii(words) ? "\\b" + NSRegularExpression.escapedPattern(for: words) + "\\b" : NSRegularExpression.escapedPattern(for: words)
            guard rest.range(of: pattern, options: .regularExpression) != nil else { continue }
            found = true
            rest = rest.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        guard found else { return false }
        let english = Set(small.filter(ascii))
        let korean = small.filter { !ascii($0) }.sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern(for:))
        let run = "^(?:" + korean.joined(separator: "|") + ")+$"
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",.!?~·…"))
        return rest.components(separatedBy: separators).filter { !$0.isEmpty }.allSatisfy { word in
            english.contains(word) || (!korean.isEmpty && word.range(of: run, options: .regularExpression) != nil)
        }
    }

    private static func ascii(_ text: String) -> Bool { text.unicodeScalars.allSatisfy(\.isASCII) }
}
