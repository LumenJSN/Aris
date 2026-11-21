//
//  ArisRecapAsk.swift
//  Shared/Core (app, tests)
//
//  How the day in review (ArisRecap) is asked for and offered. Asked: the day-end request ("오늘 정리해 줘", "오늘 뭐
//  했어", ArisDayEndAsk) is the day; with the recap on, "뭐 남았어", "남은 일 뭐야", "what's left" ask for what is left,
//  and nothing else in the sentence ("타이머 얼마 남았어" and "마감 뭐 남았어" are someone else's). Offered: the evening
//  chip (ArisDayEndOffer) comes up only when the one interruption policy lets low news come up (not over the user's voice
//  or Aris's, not in a call, not on a locked screen), and never when there is nothing to tell. The switch is
//  `arisRecap` (Settings › 조용히 · 알림), off until the user has heard it. Foundation only.
//

import Foundation

enum ArisRecapSwitch {
    static let key = "arisRecap"
    nonisolated(unsafe) static var isOn: () -> Bool = { UserDefaults.standard.bool(forKey: key) }
}

enum ArisRecapAsk {
    private static let cores = [
        #"(뭐|뭐가|무엇이|뭣이)\s*(더\s*)?남았"#,
        #"남은\s*(일|거|것|게|작업)(들)?(이|은|는|을|를)?"#,
        #"(아직\s*)?(안|못)\s*(끝낸|끝난|한)\s*(일|거|것|게)(들)?(이|은|는)?"#,
        #"\bwhat(?:'s| is| do i have| have i got| have i)? (?:still )?left\b"#,
        #"\bwhat(?:'s| is) still (?:open|to do|undone)\b"#,
        #"\b(?:anything|what) (?:else )?(?:remains|remaining)\b"#,
        #"\banything (?:still )?left\b"#,
    ]
    private static let koreanSmall = ["아리스", "야", "오늘", "하루", "지금", "아직", "이제", "그럼", "좀", "더", "다", "들", "은", "는", "이", "가", "을", "를",
                                      "뭐야", "뭐", "뭐지", "뭐예요", "있어", "있나", "있니", "있어요", "있지", "있는지", "없어", "알려", "줘", "주세요", "말해", "해줘",
                                      "궁금해", "내가", "제가", "나", "우리", "어", "어요", "지", "니", "냐", "나요", "요", "거", "건", "게"]
    private static let englishSmall: Set<String> = ["hey", "aris", "so", "ok", "okay", "now", "today", "for", "me", "to", "do", "is", "there", "on", "my",
                                                   "plate", "list", "please", "tell", "what", "else", "still", "the", "day"]

    /// The words ask what is left of the day and nothing more. `phrase`: lowercased, end marks off (ArisIntent.phrase).
    static func asksLeft(_ phrase: String) -> Bool {
        var rest = phrase
        var found = false
        for core in cores where rest.range(of: core, options: .regularExpression) != nil {
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

    /// With the recap on, "what is left" is answered by the day-end card too.
    static func asksLeftWhenOn(_ phrase: String) -> Bool { ArisRecapSwitch.isOn() && asksLeft(phrase) }

    /// What a day-end request is about: what is left, or the whole day.
    static func focus(_ phrase: String) -> ArisRecapFocus { asksLeft(phrase) ? .left : .day }
}

enum ArisRecapOffer {
    /// The evening chip as the interruption policy sees it: Aris's own low news, shown without a sound.
    static func want(hasNews: Bool) -> ArisInterruption.Want {
        ArisInterruption.Want(kind: .news, urgency: .low, spoken: false, empty: !hasNews)
    }

    /// Whether the chip may come up at this moment.
    static func mayOffer(hasNews: Bool, _ moment: ArisInterruption.Moment) -> Bool {
        ArisInterruption.decide(want(hasNews: hasNews), moment).comesUp
    }
}
