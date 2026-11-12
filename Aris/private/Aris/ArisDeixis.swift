//
//  ArisDeixis.swift
//  Aris
//
//  "이거 요약해줘", "이 메일 답장 써줘", "translate this": words that point at the screen. Only then does Aris
//  look (selected text, the browser tab, the front window), so the screen is never sent along otherwise.
//  "이 노래" is the music, "this week" a time, and "이거 말고 타이머" sets this aside: not the screen.
//  "화면 봐 줘", "여기 뭐야", "what am I looking at" ask Aris to look without a pointing word (`asksToLook`): with
//  either kind the turn carries the screenshot (ArisScreenNeed), and with neither nothing is captured.
//

import Foundation

enum ArisDeixis {
    /// A pointing word starts its own word: "내일이거든", "아이 사진" and "삼십이분" point at nothing.
    /// Written without the space ("이글", "이문서") it points only as a word of its own: the noun ends there or takes
    /// a particle ("이글은"), so "한화 이글스 경기 결과" and "이창호 9단" point at nothing.
    private static let things = "글|문장|단락|문단|페이지|화면|메일|이메일|창|내용|사이트|문서|코드|표|부분|기사|메시지|댓글|사람|사진|이미지|링크|버튼|파일|그림"
    private static let wordEnds = #"(?=(들)?(은|는|이|가|을|를|도|에|의|로|으로|만|와|과|랑|이랑|하고|처럼|부터|까지|에서|에게|한테|보다|이야|야|인데|이나|나|요)?(?![가-힣]))"#
    private static let korean = #"(?<![가-힣])((이거|이걸|이것|이게|이건|요거|저거|저걸|이분|이 분|저 사람)|이 ("# + things + ")"
        + "|이(" + things + ")" + wordEnds + ")"
    private static let english = #"(?i)\b(this|selected|highlighted)\b(?!\s+("# + notTheScreen + #")\b)|\bon (my )?screen\b"# + asDevice
    /// After "this": a time, the music, or Aris's own timer or conversation (whole words, so "this timeline" still points).
    private static let notTheScreen = "week|weekend|morning|afternoon|evening|night|year|month|time|summer|winter|spring|fall|autumn|semester|quarter|"
        + "monday|tuesday|wednesday|thursday|friday|saturday|sunday|song|track|album|playlist|artist|band|music|podcast|timer|alarm|conversation|chat"
    /// After "screen": the Mac's own features ("screen sharing", "screen time"), not what is on it.
    private static let asDevice = #"(?!\s+(sharing|share|saver|time|recording|brightness|mirroring|lock|resolution|settings)\b)"#
    /// "이거 말고 타이머", "not this, the timer": this is set aside, so it points at nothing.
    private static let setAside = #"(?i)(?<![가-힣])(이거|이것|이건|이게|요거|저거)\s*(말고|아니고|아니라|빼고|대신)|\b(not|instead of|other than|rather than)\s+this\b"#
        + "|" + saidNotShown
    /// An English "this" that is not on the screen: the song in the ears ("who sings this", "skip this"), or what the user
    /// is about to say ("remember this: the door code is 4812", "note this down, …").
    private static let saidNotShown = #"\b(sings?|singing|sang|sung)\s+this\b|\b(skip|pause|replay)\s+this\s*$"#
        + #"|\b(remember|memorize|note|know|hear|write|jot|take|save)\s+(down\s+)?this(\s+down)?\s*[:,;—–-]\s*\S|\bthis\s*:\s*\S"#
    private static let rewriteWords = #"(?i)바꿔|고쳐|다듬어|번역해|교정해|줄여|늘려|정리해서 바꿔|\b(rewrite|rephrase|translate|fix|shorten|polish)\b"#

    static func refersToScreen(_ text: String) -> Bool {
        // Files given to Aris ride along (ArisPendingFiles): "이 파일" / "이거" is them, not the screen.
        guard !meansFileWork(text), !ArisPendingFiles.carriesFiles(text) else { return false }
        let text = text.replacingOccurrences(of: setAside, with: " ", options: .regularExpression)
        return text.range(of: korean, options: .regularExpression) != nil || text.range(of: english, options: .regularExpression) != nil
    }

    /// Asking Aris to look, in words that name no "이거": the screen itself ("화면 봐 줘", "화면에 뭐 있어", "look at my
    /// screen"), what is showing ("지금 보이는 거", "방금 뜬 알림", "what am I looking at", "the current page"), a spot on
    /// it ("여기 뭐라고 써 있어", "마우스 가리키는 거", "what does it say here"), or a thing on it the pointing words above
    /// don't list ("이 에러", "저게", "선택한 부분", "these emails"). Never the screen as a device ("화면 밝기", "화면 꺼줘",
    /// "오른쪽 화면에 보여줘", "lock the screen") or "여기" as the place the user is in ("여기 날씨").
    private static let koreanLook = #"화면\s*(을|를|은|이|도)?\s*((좀|한번|한 번|같이|다시)\s*)*(봐|보고|보면|보니|보이|보여(?!\s*(줘|주|드))|읽어|확인|설명|요약|번역|분석)"#
        + #"|화면\s*(에|에서|이|은)?\s*(지금\s*)?(뭐|뭔|무슨|무엇|뭘|있는|보이는|나온|나와 ?있는|뜬|떠 ?있는|띄워진|적힌|쓰인|쓰여|써 ?있는)"#
        + #"|(보이는|보고 ?있는|띄워진|띄워 ?놓은|떠 ?있는|열려 ?있는|열어 ?놓은|방금 뜬|지금 뜬)\s*(거|것|게|걸|건|화면|창|페이지|글|내용|문서|메일|코드|사이트|탭|영상|사진|이미지|에러|오류|알림|메시지)"#
        + #"|(커서|마우스|포인터)(가|로|를)?\s*(있는|가리키는|올려 ?놓은|올린|댄|둔)"#
        + #"|(?<![가-힣])이 (에러|오류|버그|문제|영상|동영상|단어|그래프|차트|수식|숫자|글자|글씨|경고|팝업|메뉴|아이콘|상품|제품|가격|게시물|트윗|포스트|채팅|오타|함수)"#
        + #"|(?<![가-힣])(저것|저게|저건|요걸|요게|요건)|선택(한|된|해 ?놓은)|드래그(한|해 ?놓은)"#
    private static let koreanHere = #"여기(서|에|에서|는|가)?\s*(좀\s*)?(뭐|뭔|뭘|무슨|무엇|어떻게|왜|틀린|틀렸|잘못|적힌|쓰여|써 ?있)"#
    private static let koreanPlace = #"날씨|기온|미세먼지|근처|주변|맛집|카페|식당|먹|맛있|위치|주소|동네"#
    private static let englishLook = #"(?i)\bthese\b(?!\s+days\b)|\bon (the|this) (screen|display)\b"# + asDevice
        + #"|\b(look|looking|see|read|check|describe|explain)\s+(at\s+|on\s+)?(my|the|this)\s+(screen|display)\b"# + asDevice
        + #"|\bwhat\s+(am i|i'?m|i am|are we|we'?re)\s+(looking at|seeing|reading|watching|viewing)\b|\bwhat (do|can) you see\b"#
        + #"|\b(can|do) you see (this|that|it|what i|what's on|my screen|the screen)\b|\b(under|at|near|by) (my|the) (cursor|pointer|mouse)\b"#
        + #"|\b(say|says|written|click|press|tap|wrong|going on|happening|mean|means|do i do|should i do)\b[^.?!]{0,40}\bhere\b"#
        + #"|\b(the|my) (current|open|front|frontmost|active) (page|tab|window|document|doc|email|site|website|article)\b"#

    static func asksToLook(_ text: String) -> Bool {
        guard !meansFileWork(text), !ArisPendingFiles.carriesFiles(text) else { return false }
        if text.range(of: koreanLook, options: .regularExpression) != nil || text.range(of: englishLook, options: .regularExpression) != nil { return true }
        return text.range(of: koreanHere, options: .regularExpression) != nil && text.range(of: koreanPlace, options: .regularExpression) == nil
    }

    /// Converting, merging, splitting or shrinking files ("이거 PNG로 바꿔줘", "이 두 PDF 합쳐줘", "소리만 뽑아줘", "용량 줄여줘",
    /// "convert this to png"): "this" is the files (aris-tools --finder or --shelf), so the screen isn't read.
    private static let fileFormats = "png|jpe?g|heic|heif|tiff?|gif|bmp|webp|pdf|mp4|mov|m4a|mp3|wav|aiff?"
    private static let koreanFileWork = #"(?i)("# + fileFormats + #")\s*(으로|로|파일로)|(소리|오디오|음성)만|(용량|파일 ?크기)\s*(좀\s*)?(줄|작게)|"#
        + #"(파일|사진|이미지|영상|동영상|비디오|녹음|"# + fileFormats + #").*(합쳐|합치|병합|나눠|쪼개|분할|압축|변환)"#
    private static let englishFileWork = #"(?i)\b(to|into|as)\s+(an?\s+)?("# + fileFormats + #")\b|\bextract\s+the\s+(audio|sound)\b|"#
        + #"\b(compress|merge|combine|split|shrink)\b.*\b(files?|photos?|pictures?|images?|videos?|clips?|"# + fileFormats + #")\b"#

    /// Words that point at the screen itself: then the screen is read, whatever else is asked.
    private static let screenWords = #"(?i)화면|이 ?창|보이는|띄워진|\bscreen\b|\bthis window\b|\bon (my )?screen\b"#

    static func meansFileWork(_ text: String) -> Bool {
        guard text.range(of: screenWords, options: .regularExpression) == nil else { return false }
        return text.range(of: koreanFileWork, options: .regularExpression) != nil || text.range(of: englishFileWork, options: .regularExpression) != nil
    }

    /// "아까 복사한 링크", "클립보드에 있는 거": the clipboard history goes along (as outside text, like the screen).
    static func refersToClipboard(_ text: String) -> Bool {
        text.range(of: #"(?i)복사한|복사했던|복사해 둔|복사해둔|클립보드|\b(copied|clipboard)\b|\bdid i copy\b"#, options: .regularExpression) != nil
    }

    /// The last few copies, each cut short, for the AI.
    static func clipboardContext(_ items: [ArisClipboard.Item], count: Int = 10, each: Int = 300) -> String {
        var lines: [String] = []
        for (index, item) in items.prefix(count).enumerated() {
            let source = item.app.map { "[\($0)] " } ?? ""
            let text = item.isImage ? "(an image)" : String(item.title.replacingOccurrences(of: "\n", with: " ").prefix(each))
            lines.append("\(index + 1). \(source)\(text)")
        }
        return "Recently copied (newest first):\n" + lines.joined(separator: "\n")
    }

    /// "이거 정중하게 바꿔줘": the answer replaces the selected text instead of being read out.
    static func wantsRewrite(_ text: String) -> Bool {
        refersToScreen(text) && text.range(of: rewriteWords, options: .regularExpression) != nil
    }
}
