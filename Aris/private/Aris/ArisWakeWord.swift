//
//  ArisWakeWord.swift
//  Aris
//
//  "아리스" said at the start of a phrase wakes Aris without the hotkey. Only the
//  start counts, so the name in passing ("오늘 아리스 봤어?") or inside a longer word
//  ("아리스토텔레스") doesn't. The spellings are how the recognizers write it: the name chosen in Settings (ArisWakeName,
//  "아리스" until then) and the spellings learned from the user's own training recordings.
//

import Foundation

enum ArisWakeWord {
    private static var name: String { #"^\s*(?:(?:헤이|hey|야)[\s,]*)?(?:"# + ArisWakeName.current.pattern + #")(?:야|아)?(?=$|[\s,.!?~])"# }

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

    // MARK: - The wake check

    // Only the wake word's check of a candidate phrase (and its own turn's words) reads these: Whisper on a second and a
    // half of Korean writes the name other ways, or after a filler ("어, 아리스", "Iris", "アリス"; 2026-11-14). Still only
    // at the start and as a whole word, so "아리스토텔레스" and "오늘 아리스 봤어" stay out. The strict `name` above is
    // what every other turn strips.
    private static let filler = #"(?:(?:어|아|음|응|엄|으|에|오|저기|저|그|uh|um|uhm|hmm|hm|ah|oh|eh|er)[\s,.~…]+){0,2}"#
    private static let callEnd = #"(?:야|아)?(?=$|[\s,.!?~。、…])"#
    private static var call: String { #"^\s*"# + filler + #"(?:(?:헤이|hey|야)[\s,]*)?(?:"# + ArisWakeName.current.pattern + ")" + callEnd }
    /// Near spellings of "아리스", which count only with a fairly close voice print (ArisWakeDoubt.nearAllowed). A name
    /// the user chose has none: its learned spellings are in `call`.
    private static let near = #"^\s*"# + filler + #"(?:(?:헤이|hey|야)[\s,]*)?(?:아리사|arisa|알리스|어리스|애리스|에리스|아리수|아리즈|아이리스|앨리스|엘리스|iris|alice|ares|arris|aries|ariss|アリス)"# + callEnd

    private static func callRange(_ text: String, nearAllowed: Bool) -> Range<String.Index>? {
        let options: String.CompareOptions = [.regularExpression, .caseInsensitive]
        let nearCounts = nearAllowed && ArisWakeName.current.isDefault
        return text.range(of: call, options: options) ?? (nearCounts ? text.range(of: near, options: options) : nil)
    }

    /// The wake check heard the name: at the start, perhaps after a filler; near spellings too when `nearAllowed`.
    static func verified(_ text: String, nearAllowed: Bool) -> Bool { callRange(text, nearAllowed: nearAllowed) != nil }

    /// A wake turn's words without the call at their start, whichever spelling woke it.
    static func strippedCall(_ text: String) -> String {
        guard let range = callRange(text, nearAllowed: true) else { return text }
        return String(text[range.upperBound...].drop { " ,.!?~。、…\n\t".contains($0) }).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A wake turn has heard only the call so far.
    static func isOnlyTheCall(_ text: String) -> Bool { verified(text, nearAllowed: true) && strippedCall(text).isEmpty }
}
