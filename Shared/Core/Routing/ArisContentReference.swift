//
//  ArisContentReference.swift
//  Aris (Shared/Core)
//
//  Words that stand for content which is somewhere else: a document, a page, the screen, a selection, what was just
//  said ("이 문서에 적힌 할 일", "여기 있는 거", "선택한 파일", "the tasks in this email", "that", "them"). What they
//  mean only the AI can tell: it has the screen, the files and the conversation. So a local rule that takes words (a
//  to-do's item, the app to open) never takes a request that holds one: the whole request goes to the model (tenth VM
//  run: "이 문서에 적힌 할 일 미리 알림에 추가해 줘" was saved as a to-do called "이 문서에 적힌 미리 알림에").
//  A miss costs a second (the model calls the same capability); a hijack does the wrong thing, so the lists are wide
//  on purpose and a title that only looks like a reference ("이 닦기") goes to the model too.
//  Foundation only (swift test).
//

import Foundation

enum ArisContentReference {
    /// Things that hold content.
    private static let holders = "문서|파일|폴더|페이지|화면|메일|이메일|메시지|문자|카톡|글|기사|사진|이미지|스크린샷|창|탭|사이트|웹페이지|웹사이트|링크|노트|메모|표|목록|리스트|대화|채팅|슬라이드|영상|동영상|클립보드|pdf|pptx?|docx?"
    /// A clause that says where the thing is or how it got there ("…에 적힌", "…에 나온", "선택한 …").
    private static let clause = #"적힌|적혀\s?있는|쓰인|쓰여\s?있는|써\s?있는|써\s?진|나온|나와\s?있는|나오는|담긴|들어\s?있는|보이는|뜬|떠\s?있는|열린|열려\s?있는|언급된|언급한"#
    private static let picked = #"선택한|선택된|선택해\s?(?:둔|놓은)|고른|골라\s?(?:둔|놓은)|복사한|복사해\s?(?:둔|놓은)|첨부한|첨부된|드래그한|표시한|동그라미\s?친"#
    private static let spoken = #"말한|말해\s?준|알려\s?준|찾은|찾아\s?준|보여\s?준|보낸|받은|정리한|정리해\s?준|만든|만들어\s?준"#

    /// Korean: a holder pointed at ("이 문서", "열린 페이지"), a holder and what is in it ("메일에 적힌", "화면에 있는"), a
    /// place and a clause ("여기 있는", "방금 말한"), or a clause that can only be about other content ("적힌", "선택한").
    private static let korean: [String] = [
        #"(?<![가-힣])(?:이|그|저|요|해당|현재|지금|위|아래)\s?(?:"# + holders + #")(?![가-힣]{2})"#,
        "(?:" + holders + #")(?:들)?\s?(?:에|에서|안에|속에|의)\s*(?:"# + clause + "|있는|" + spoken + ")",
        #"(?<![가-힣])(?:여기|거기|저기|위에|아래에|밑에|앞에|방금|아까|좀\s?전에?)\s*(?:"# + clause + "|있는|" + spoken + ")",
        "(?<![가-힣])(?:" + picked + ")(?![가-힣])",
        "(?<![가-힣])(?:" + clause + ")(?![가-힣])",
    ]

    /// English: "in this document", "on the screen", "the selected file", "what you said", "the tasks from that email".
    private static let english: [String] = [
        #"\b(?:in|on|from|inside|within|off)\s+(?:this|that|these|those|the|my|our)\s+(?:open\s+|current\s+|selected\s+|attached\s+)?(?:document|doc|file|folder|page|screen|email|e-mail|mail|message|text|chat|thread|article|photo|picture|image|screenshot|window|tab|site|website|link|note|notes|table|list|slide|slides|video|clipboard|pdf|selection|conversation)s?\b"#,
        #"\b(?:the|my|this|that|these|those)\s+(?:selected|highlighted|circled|copied|attached|open|current)\b"#,
        #"\b(?:the\s+|my\s+)?selection\b"#,
        #"\b(?:written|mentioned|listed|shown|described|displayed|highlighted|selected)\s+(?:in|on|here|there|above|below)\b"#,
        #"\bwhat(?:ever)?\s+(?:you|i|we|he|she|they|it)\s+(?:just\s+)?(?:said|told|mentioned|found|wrote|showed|sent|listed|see)\b"#,
        #"\bwhat(?:'s|\s+is)\s+(?:on|in)\s+(?:the|my|this)\b"#,
    ]

    /// Words that point at something and name nothing, anywhere in what a rule would take as its words.
    private static let pointersKorean = #"(?<![가-힣])(?:이거(?!저거)|이걸|이것|이게|이건|그거|그걸|그것|그게|그건|저거|저걸|저것|요거|여기|거기|저기|얘|걔|쟤|이분|이\s?사람|방금|아까|위에|위의|아래에|밑에)"#
        + #"|(?<![가-힣])(?:이|그|저|요)\s(?=[가-힣A-Za-z0-9])"#
    /// "this week" and "that morning" are times, not pointers.
    private static let times = #"(?:morning|afternoon|evening|night|week|weekend|month|year|time|monday|tuesday|wednesday|thursday|friday|saturday|sunday|spring|summer|fall|autumn|winter|quarter|semester|term)"#
    private static let pointersEnglish = #"\b(?:this|that|these|those)\b(?!\s+"# + times + #"\b)|\b(?:them|here|there|above|below|everything|all\s+of\s+(?:it|them|this|that))\b"#
    /// "it" as written small: "IT support ticket" names a thing.
    private static let pointerIt = #"\b[Ii]t\b"#

    private static func found(_ patterns: [String], in text: String) -> Bool {
        patterns.contains { text.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }
    }

    private static func plain(_ words: String) -> String {
        words.precomposedStringWithCanonicalMapping.replacingOccurrences(of: "’", with: "'")
    }

    /// Whether the sentence speaks of content held somewhere else: a document, a page, the screen, a selection, what
    /// was said. True for "이 문서에 적힌 할 일 미리 알림에 추가해 줘", "여기 있는 거 할 일에 넣어 줘", "선택한 파일 열어 줘",
    /// "add the tasks in this email to my reminders"; false for "내일 우유 사기 할 일에 추가해 줘", "open Safari".
    static func inSentence(_ words: String) -> Bool {
        let said = plain(words)
        return found(korean, in: said) || found(english, in: said)
    }

    /// Whether the words a rule would take (a to-do's item, an app's name) point at something instead of naming it:
    /// everything `inSentence` finds, and any pointing word ("이거", "그 보고서", "that report", "it", "them").
    static func inArgument(_ words: String) -> Bool {
        let said = plain(words)
        return inSentence(said) || found([pointersKorean, pointersEnglish], in: said) || said.range(of: pointerIt, options: .regularExpression) != nil
    }
}
