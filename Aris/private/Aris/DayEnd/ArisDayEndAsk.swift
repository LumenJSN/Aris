//
//  ArisDayEndAsk.swift
//  Aris
//
//  When the day-end summary (ArisDayEnd) comes. Asked for: "오늘 정리해 줘", "하루 마감", "오늘 뭐 했어?", "wrap up my
//  day", "what did you do today", and nothing else in the sentence ("오늘 받은 메일 정리해 줘" and "오늘 한 일 메일로
//  보내 줘" ask the AI for something else). Offered: once in the evening, the way the morning brief picks its moment
//  (a set hour, the user at the Mac after it, never twice a day), and only as a chip. Foundation only, so it is tested.
//

import Foundation

enum ArisDayEndAsk {
    /// What the request is about: the day, and wrapping it up or what was done in it.
    private static let cores = [
        #"(오늘\s*(하루\s*)?|하루\s*)(을|를)?\s*(정리|마무리|요약)"#,
        // "오늘 마감 뭐 있어" asks about deadlines: only the day itself is closed.
        #"(오늘\s*)?하루\s*(를\s*)?마감"#,
        #"오늘\s*(하루\s*)?(뭐|뭘|뭐를|무엇을|무슨\s*일을?|어떤\s*일을?)\s*했(는지|던\s*거|던\s*것)?(\s*(정리|요약))?"#,
        #"오늘\s*(하루\s*)?(한|했던|끝낸|처리한)\s*(일|거|것|작업)(들)?(을|를)?(\s*(정리|요약))?"#,
        #"\bwrap(?:ping)?[ -]?up (?:my |the |our |this )?(?:day|today)\b"#,
        #"\b(?:day[ -]?end|end[ -]of[ -](?:the[ -])?day|daily) (?:summary|wrap[ -]?up|recap|report)\b"#,
        #"\b(?:day|today)(?:'s|s)? ?(?:wrap[ -]?up|summary|recap)\b"#,
        #"\bwhat (?:did|have) (?:you|we|aris|everyone|the team|you all|you guys) (?:do|done|get done|got done|finish|finished) today\b"#,
        #"\b(?:summari[sz]e|recap|sum up) (?:my |the |our )?(?:day|today)\b"#,
        // "close out my day", "end my day": the day itself is closed ("end the day's meeting early" names something else).
        #"\b(?:close out|close|end|finish up) (?:my |the |our )day\b(?!')"#,
    ]
    /// The words that may stand around it: who is asked, a please, a sentence ending.
    private static let koreanSmall = ["아리스", "야", "오늘", "하루", "지금", "이제", "그럼", "좀", "한번", "한 번", "다", "전부", "같이", "우리", "너", "넌", "네가", "니가",
                                      "팀원들이랑", "팀원들", "팀원", "이랑", "랑", "하고", "도", "까지", "것", "거", "들", "을", "를", "은", "는", "이", "가",
                                      "해", "하자", "할게", "할까", "해줘", "줘", "주세요", "줄래", "줄래요", "봐", "보여", "알려", "말해", "들려", "부탁", "부탁해",
                                      "는지", "었는지", "어", "어요", "었어", "었어요", "니", "냐", "나요", "지", "게", "요", "뭐야", "뭐", "뭐였지", "있어", "궁금해"]
    private static let englishSmall: Set<String> = ["hey", "aris", "please", "can", "could", "would", "you", "me", "us", "give", "show", "tell", "a", "an",
                                                   "the", "my", "our", "so", "far", "now", "quick", "quickly", "for", "and", "team", "teammates", "with",
                                                   "let's", "lets", "i", "want", "to", "see", "ok", "okay"]

    /// The words ask for the day-end summary and nothing more. `phrase`: lowercased, end marks off (ArisIntent.phrase).
    static func asks(_ phrase: String) -> Bool {
        var rest = phrase
        var found = false
        for core in cores {
            guard rest.range(of: core, options: .regularExpression) != nil else { continue }
            found = true
            rest = rest.replacingOccurrences(of: core, with: " ", options: .regularExpression)
        }
        guard found else { return false }
        let run = "^(?:" + koreanSmall.sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|") + ")+$"
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",.!?~·…"))
        return rest.components(separatedBy: separators).filter { !$0.isEmpty }.allSatisfy { word in
            englishSmall.contains(word) || word.range(of: run, options: .regularExpression) != nil
        }
    }
}

enum ArisDayEndOffer {
    /// The evening begins at six: the chip comes at the user's first activity after it.
    static let hour = 18
    /// Touching the Mac within this long counts as being at it.
    static let activeWithin: TimeInterval = 90
    /// How long the chip hangs under the closed notch before it steps back into the open notch's row.
    static let chipShows: Duration = .seconds(12)

    /// The evening of the day being wrapped up: from six until that day ends at five in the morning (ArisDaySpan).
    static func isEvening(_ now: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: now)
        return hour >= Self.hour || hour < ArisDaySpan.startHour
    }

    /// A summary already showed in the evening of the day `now` belongs to (an afternoon's doesn't count, nor one from
    /// the evening before, past midnight included).
    static func hadEvening(_ lastShown: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        guard let lastShown else { return false }
        return ArisDaySpan(now: lastShown, calendar: calendar).today == ArisDaySpan(now: now, calendar: calendar).today && isEvening(lastShown, calendar: calendar)
    }

    /// Whether the chip may be offered now. `lastShown`: when a summary last showed, asked for or offered (a day that
    /// already had one gets no chip). `idle`: seconds since the user last touched the Mac.
    static func isDue(enabled: Bool, lastShown: Date?, now: Date, idle: TimeInterval, calendar: Calendar = .current) -> Bool {
        guard enabled, isEvening(now, calendar: calendar), idle <= activeWithin else { return false }
        return !hadEvening(lastShown, now: now, calendar: calendar)
    }

    /// After a look that found nothing to tell, the evening is looked at again this much later.
    static let quietRecheck: TimeInterval = 30 * 60

    /// How long to sleep before looking again: until six when it is earlier in the day or this evening already had its
    /// summary; half an hour after an evening with nothing to tell (`quiet`); else a minute, for the user to come back.
    static func nextCheck(after now: Date, lastShown: Date?, quiet: Bool = false, calendar: Calendar = .current) -> TimeInterval {
        if isEvening(now, calendar: calendar), !hadEvening(lastShown, now: now, calendar: calendar) { return quiet ? quietRecheck : 60 }
        let six = calendar.nextDate(after: now, matching: DateComponents(hour: hour, minute: 0, second: 0), matchingPolicy: .nextTime)
        return max(60, six?.timeIntervalSince(now) ?? 3_600)
    }

    /// Whether the chip may hang under the closed notch right now: never over a turn, a card, a drag or the guide, and
    /// never while something else is drawn there (the same quiet the speech-model offer keeps).
    static func mayShow(turn: Bool, card: Bool, dragging: Bool, onboarding: Bool) -> Bool {
        !(turn || card || dragging || onboarding)
    }
}
