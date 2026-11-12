//
//  ArisWhyIntent.swift
//  aris-agent
//
//  The user asking why Aris did what it just did, in Korean or English:
//    "왜 그렇게 했어?", "왜 그랬어?", "방금 왜 그런 거야?", "why did you do that?"   -> did
//    "왜 물어봐?", "왜 또 물어보는 거야?", "why are you asking?"                    -> asked
//    "왜 안 돼?", "왜 못 해?", "왜 안 했어?", "why not?", "why can't you?"          -> refused
//    "왜?", "왜요?", "why?"                                                         -> bare
//  Only a short sentence that is nothing but that question counts: "왜 하늘은 파래?" and "왜 그렇게 했는지 메일로 보내 줘"
//  are the AI's. Foundation only (tested).
//

import Foundation

enum ArisWhyFocus: Equatable {
    /// Why it did what it did: the whole record.
    case did
    /// Why a card asked.
    case asked
    /// Why something wasn't done.
    case refused
    /// Just "왜?": about a card or a refusal when the turn before had one.
    case bare
}

enum ArisWhyIntent {
    /// A why-question is short; anything longer is a request with a "왜" in it.
    static let longest = 40

    /// Words in front that don't change the question ("근데 방금 그건 왜 그랬어").
    private static let leads = ["근데", "그런데", "아니", "잠깐", "잠깐만", "방금", "아까", "지금", "그건", "그거", "그걸", "이건", "이거", "너", "넌", "아리스",
                                "hey", "wait", "but", "so", "aris", "ok", "okay", "and", "then", "just now"]

    private static let koreanDid = #"^왜 ?(그렇게|그리|이렇게|그런 ?식으로)? ?(했어|했니|했지|했냐|했는데|했어요|했나요|했죠|한 ?거야|한 ?거예요|한 ?건데|한 ?거죠|답했어|대답했어|말했어|"#
        + #"그랬어|그랬니|그랬지|그랬냐|그랬는데|그랬어요|그랬나요|그랬죠|그런 ?거야|그런 ?거예요|그런 ?건데|그런 ?거죠|그런 ?건가요)$"#
    private static let koreanDidOther = #"^(무슨|어떤|어느) ?(기억|규칙|이유)(을|를|으로|로|이|가)? ?(썼어|쓴 ?거야|보고 ?(그랬어|했어)|때문이야|때문에 ?(그랬어|했어)|그랬어|그런 ?거야)(요)?$"#
        + #"|^(그렇게 ?(한|했던)|그런) ?(이유|까닭)(가|는)? ?(뭐야|뭐예요|뭔데|뭐지|뭐죠)$"#
    private static let koreanAsked = #"^왜 ?(또|자꾸|굳이|그걸|이걸|나한테)? ?(물어봐|물어보는 ?거야|물어본 ?거야|물어봤어|물어|묻는 ?거야|물은 ?거야|확인해|확인하는 ?거야|확인받아|"#
        + #"카드(가|를)? ?(떠|떴어|띄워|띄웠어|뜨는 ?거야))(요)?$"#
    private static let koreanRefused = #"^왜 ?(안 ?돼|안 ?되는 ?거야|안 ?되는데|안 ?된 ?거야|안 ?됐어|안 ?해|안 ?해 ?줘|안 ?했어|안 ?한 ?거야|안 ?하는 ?거야|못 ?해|못 ?하는 ?거야|못 ?했어|못 ?한 ?거야|"#
        + #"막았어|막는 ?거야|막은 ?거야|막혔어|거절했어|거절해|거절한 ?거야|안 ?보냈어|안 ?보내|실패했어|멈췄어|멈춘 ?거야)(요)?$"#
    private static let koreanBare: Set<String> = ["왜", "왜요", "왜죠", "왜지", "어째서", "어째서요", "이유는", "이유가 뭐야", "이유가 뭐예요", "왜 그런데", "왜 그래", "왜 그래요"]

    private static let englishDid = #"^(why did you|why'd you|why would you|what made you) (do|say|answer|pick|choose|write) (that|this|it|so)( like that| that way)?$"#
        + #"|^why did you (do|answer|say) (it|that) (like that|that way)$|^why that$"#
        + #"|^(which|what) (memory|memories|rule|rules) (did you use|made you do that|was that|were those)$"#
    private static let englishAsked = #"^why (are|were) you asking( me)?( that| again)?$|^why (did|do|would) you (ask|have to ask)( me)?( that| again| about that)?$"#
        + #"|^why (do|did) (you|i) (need|have) to (confirm|ask|approve)( that| it)?$|^why (the|a) card$|^why ask( me)?$"#
    private static let englishRefused = #"^why not$|^why (can't|cant|couldn't|couldnt|won't|wont|didn't|didnt|wouldn't) you( do (it|that))?$|^why can't i$"#
        + #"|^why (did you|would you) (refuse|stop|block)( it| that)?$|^why (is|was) (it|that) (blocked|refused|not allowed|stopped)$|^why did (it|that) fail$"#
    private static let englishBare: Set<String> = ["why", "how come", "why's that", "why is that", "why so", "and why"]

    static func parse(_ said: String) -> ArisWhyFocus? {
        let text = plain(said)
        guard !text.isEmpty, text.count <= longest else { return nil }
        if koreanBare.contains(text) || englishBare.contains(text) { return .bare }
        if matches(text, koreanAsked) || matches(text, englishAsked) { return .asked }
        if matches(text, koreanRefused) || matches(text, englishRefused) { return .refused }
        if matches(text, koreanDid) || matches(text, koreanDidOther) || matches(text, englishDid) { return .did }
        return nil
    }

    /// The user's own words in lower case with no punctuation, single spaces, and without the words in front that don't
    /// change the question.
    static func plain(_ said: String) -> String {
        let own = ArisMemoryText.ownWords(said).precomposedStringWithCanonicalMapping.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        let kept = own.unicodeScalars.map { CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) || $0 == "'" ? Character($0) : " " }
        var words = String(kept).split(separator: " ").map(String.init)
        while let first = words.first, words.count > 1, leads.contains(first) || (words.count > 2 && leads.contains(first + " " + words[1])) {
            words.removeFirst(leads.contains(first) ? 1 : 2)
        }
        return words.joined(separator: " ")
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}
