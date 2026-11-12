//
//  ArisWakeWord.swift
//  Aris
//
//  "아리스" said at the start of a phrase wakes Aris without the hotkey. Only the
//  start counts, so the name in passing ("오늘 아리스 봤어?") or inside a longer word
//  ("아리스토텔레스") doesn't. The spellings are how the recognizers write it.
//

import Foundation

enum ArisWakeWord {
    private static let name = #"^\s*(?:(?:헤이|hey|야)[\s,]*)?(?:아리스|아리쓰|aris)(?:야|아)?(?=$|[\s,.!?~])"#

    static func heard(_ phrase: String) -> Bool {
        phrase.range(of: name, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// The request without the name (and the comma or pause after it).
    static func stripped(_ text: String) -> String {
        guard let range = text.range(of: name, options: [.regularExpression, .caseInsensitive]) else { return text }
        return String(text[range.upperBound...].drop { " ,.!?~\n\t".contains($0) }).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Just "아리스" so far: wait for the request instead of ending the turn at the first pause.
    static func isOnlyTheName(_ phrase: String) -> Bool {
        heard(phrase) && stripped(phrase).isEmpty
    }
}
