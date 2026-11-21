//
//  ArisFocusWords.swift
//  Shared/Core/Focus (aris-agent, app, tests)
//
//  What the owner's pointing words aim at, so resolution picks the right one of the things on screen:
//    region   "동그라미 친 거", "what I circled": the circle first.
//    pointer  "마우스 가리키는 거", "under my cursor": the element under the pointer first.
//    person   "이 사람한테 답장해 줘", "이분", "보낸 사람", "reply to her", "this person": someone in the focus (a mail's
//             sender, a chat's other person); when nobody is there, resolution says so instead of guessing.
//    place    "여기 고쳐 줘", "여기에 써 줘", "put it here": where to act (the selection, the focused field).
//    thing    "이거 요약해 줘", "이걸", "this", "these", "선택한 거": what is selected or showing.
//  and what kind of thing the words name with their pointing ("이 메일", "these files", "이 일정"). "여기" that is the
//  owner's place ("여기 날씨", "near here") and "이 분 뒤" (two minutes later) aim at nothing. Whether a turn looks at
//  the screen at all stays the app's ArisDeixis; this only reads which of the things it finds is meant. Pure.
//

import Foundation

enum ArisFocusWords {
    enum Aim: String, Equatable, Sendable, Codable {
        case thing, place, person, pointer, region
    }

    enum Want: String, Equatable, Sendable, Codable, CaseIterable {
        case mail, file, page, event, chat, text, image, field
    }

    struct Pointing: Equatable, Sendable {
        /// What decides the order (the strongest aim the words have).
        var aim: Aim = .thing
        /// The kind of thing named with the pointing.
        var wants: Want?
        var plural = false
        /// The words point at all.
        var points = false
        /// They name a person too ("이 사람한테 여기 답장 써 줘": the aim is the person, the place still counts).
        var person = false
        /// They name a place to act too.
        var place = false
    }

    // MARK: - Patterns

    private static let hangulBefore = #"(?<![가-힣])"#
    private static let region = #"동그라미|원\s?(을\s?)?(그린|친)|(?<![가-힣])(표시|체크)\s?(한|해 ?둔|해 ?놓은)\s?(거|것|걸|부분|데|곳)"#
        + #"|(?i)\bcircled\b|\bthe circle\b|\bwhat i (drew|marked|circled)\b"#
    private static let pointer = #"마우스|커서|포인터|(?i)\b(cursor|pointer|mouse)\b|\bhover(ing|ed)?\b"#
    /// Time after "이 분" / "이분": two minutes, not a person.
    private static let notMinutes = #"(?!\s*(뒤|후|전|동안|만에|간|짜리|정도|쯤|이내|남|지나|있다가))"#
    private static let person = hangulBefore + #"(이|저|그|요)\s?(사람|친구|양반)|"# + hangulBefore + #"(이|저|그)\s?분"# + notMinutes + #"(한테|에게|께서|께|이|은|는|을|를|의|도|이랑|하고)?(?![가-힣])"#
        + #"|보낸\s?(사람|분|이)|(?i)\b(this|that)\s+(person|guy|sender|woman|man|lady|contact|one who)\b|\bthe sender\b"#
        + #"|\b(reply|respond|write|text|message|answer|tell|send)\b[^.?!]{0,24}\b(him|her)\b"#
    /// "여기" as the owner's own place, in the same sentence: then it points at nothing.
    private static let ownPlace = #"날씨|기온|미세먼지|근처|주변|맛집|카페|식당|먹을|맛있|위치|주소|동네|어디|가까운|멀어"#
        + #"|(?i)\b(weather|near|nearby|around here|restaurants?|cafes?|coffee|food|location|address|close to|far from)\b"#
    private static let place = hangulBefore + #"(여기|요기)|"# + hangulBefore + #"이\s?(칸|입력창|입력 칸|자리)(에|에다|에다가|에서|는|를|을)?(?![가-힣])"#
        + #"|(?i)\b(in|into|right)\s+here\b|\bhere\b|\bthis (field|box)\b"#
    private static let thing = hangulBefore + #"(이거|이걸|이것|이게|이건|요거|요걸|요것|저거|저걸|저것|저게|그거|그걸|그것)"#
        + #"|선택(한|된|해 ?둔|해 ?놓은|되어 ?있는|돼 ?있는)|(?<![가-힣])고른|골라 ?(둔|놓은)|드래그(한|해 ?둔)|(?i)\b(this|that|these|those|selected|highlighted)\b"#

    private static let nouns: [(Want, korean: String, english: String)] = [
        (.mail, "메일|이메일|편지", "mails?|emails?|e-mails?"),
        (.file, "파일|폴더|문서|pdf|PDF", "files?|folders?|documents?|docs?|pdfs?"),
        (.page, "페이지|웹페이지|사이트|기사|탭|링크", "pages?|sites?|websites?|articles?|tabs?|links?"),
        (.event, "일정|약속|이벤트|미팅|회의|초대", "events?|meetings?|invites?|invitations?|appointments?"),
        (.chat, "대화|채팅|메시지|톡|카톡|문자|디엠", "chats?|conversations?|messages?|threads?|dms?"),
        (.image, "사진|이미지|그림|스크린샷", "photos?|images?|pictures?|screenshots?"),
        (.field, "칸|입력창|입력칸|필드|검색창", "fields?|box|boxes|inputs?"),
        (.text, "글|문장|단락|문단|내용|부분|코드|표|구절", "text|paragraphs?|sentences?|lines?|code|parts?|sections?|tables?|passages?"),
    ]

    private static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    /// The kind named with a pointing word: "이 메일", "저 파일들", "선택한 사진", "this email", "these files",
    /// "the selected rows" ("이메일" written as one word is the noun email, so "이메일 보내 줘" names none).
    static func wanted(_ text: String) -> Want? {
        for (want, korean, english) in nouns {
            let koreanPattern = hangulBefore + #"((이|저|그|요)\s+(이)?("# + korean + #")|(저|그|요)("# + korean + #")|(선택(한|된|해 ?둔|해 ?놓은|되어 ?있는|돼 ?있는)|고른|골라 ?(둔|놓은))\s*("# + korean + #"))"#
            let englishPattern = #"(?i)\b(this|that|these|those|the selected|selected|highlighted)\s+(\w+\s+)?("# + english + #")\b"#
            // "the file I selected", "the photos I picked".
            let englishAfter = #"(?i)\b("# + english + #")\s+(that\s+)?(i|i've|i have)\s+(just\s+)?(selected|picked|chose|chosen|highlighted)\b"#
            if matches(koreanPattern, text) || matches(englishPattern, text) || matches(englishAfter, text) { return want }
        }
        return nil
    }

    static func plural(_ text: String) -> Bool {
        let koreanNouns = nouns.map(\.korean).joined(separator: "|")
        return matches(#"(이것|이거|저것|저거|그것)들|얘네|이거\s?다|전부|모두|("# + koreanNouns + #")들"#, text)
            || matches(#"(?i)\b(these|those|all of (them|these|those))\b"#, text)
    }

    /// Whether "여기" / "here" in these words is a place on screen, not where the owner is.
    static func pointsHere(_ text: String) -> Bool {
        matches(place, text) && !matches(ownPlace, text)
    }

    static func parse(_ text: String) -> Pointing {
        var pointing = Pointing()
        let regionSaid = matches(region, text), pointerSaid = matches(pointer, text)
        pointing.person = matches(person, text)
        pointing.place = pointsHere(text)
        pointing.wants = wanted(text)
        pointing.plural = plural(text)
        let thingSaid = matches(thing, text)
        pointing.points = regionSaid || pointerSaid || pointing.person || pointing.place || thingSaid || pointing.wants != nil
        pointing.aim = regionSaid ? .region : pointerSaid ? .pointer : pointing.person ? .person : pointing.place && !thingSaid ? .place : .thing
        // "여기 이거 고쳐 줘": the thing is here; the place still decides where the result goes.
        if pointing.aim == .thing, pointing.place, pointing.wants == nil { pointing.aim = .place }
        return pointing
    }
}
