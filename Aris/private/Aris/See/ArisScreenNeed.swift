//
//  ArisScreenNeed.swift
//  Aris
//
//  Whether a turn's ask carries the screenshot (the owner, 2026-11-10): only when their words point at the screen ("이거
//  뭐야", "이 메일 답장 써줘", "화면 봐 줘", "여기 뭐야", "what's on my screen", "look at this"). A plain question
//  ("프랑스 수도가 어디야") captures nothing: no ScreenCaptureKit call, so no macOS notice and no recording dot, and
//  its request goes out without an image, so the brain that answers it isn't sealed for that. "이 노래", "이번 주",
//  "this week" and "이거 말고 타이머" are not the screen (ArisDeixis). Shots the user circled go as they always did and
//  stand in for the screenshot; files given to Aris are what "이거" means. With "질문할 때 화면 같이 보기" off, never.
//  A brain that needs the screen on any other turn looks for itself (aris-tools screen, desktop see).
//  Look first (the owner, 2026-11-14: "이 대화에는 어사이드의 답이 없어요" with Aside open in front of them): the words of an
//  app that is showing ("어사이드가 뭐라고 했어", "Claude Code 세션 읽어줘", "what did Aside say"), a bare "뭐야?" and
//  another screen ("다른 화면에 있다", "the other monitor") point at the screen too; `want` says which displays
//  (ArisDisplayPick). Opening, closing or asking an app ("어사이드한테 물어봐", "크롬 꺼줘") never does.
//  Pure, so the tests run its table.
//

import Foundation

enum ArisScreenNeed {
    /// What a screen turn wants to see: the displays holding these apps' windows (none: the one under the pointer), and
    /// with `others` the remaining displays as well.
    struct Want: Equatable {
        let apps: [String]
        let others: Bool
        /// The plain screenshot of the display under the pointer.
        var plain: Bool { apps.isEmpty && !others }
    }

    /// Whether the words point at what is on screen: a pointing word ("이거", "this"), asking Aris to look, the words of
    /// an app in `apps` (the apps with a window showing), a bare "뭐야?", or another screen.
    static func pointsAtScreen(_ words: String, apps: [String] = []) -> Bool {
        want(words, apps: apps) != nil
    }

    /// Whether this turn takes the screenshot. `setting`: "질문할 때 화면 같이 보기". `drew`: the turn holds circled
    /// shots or a drawing, which go instead of it.
    static func captures(words: String, setting: Bool, drew: Bool, apps: [String] = []) -> Bool {
        setting && !drew && pointsAtScreen(words, apps: apps)
    }

    /// What the turn wants to see, or nil when its words don't point at the screen.
    static func want(_ words: String, apps: [String]) -> Want? {
        // Never a question about the Claude Code sessions ("클로드 코드 저거, 세션 … 읽어줘"): the context has them (ask-claude).
        guard !ClaudeSessionsContext.asks(words), !ArisDeixis.meansFileWork(words), !ArisPendingFiles.carriesFiles(words) else { return nil }
        let named = readsApps(words, apps: apps)
        let others = wantsOtherScreens(words)
        guard !named.isEmpty || others || ArisDeixis.refersToScreen(words) || ArisDeixis.asksToLook(words) || bareWhat(words) else { return nil }
        return Want(apps: named, others: others)
    }

    // MARK: - Another screen

    private static let otherKorean = #"(다른|옆|두\s*번째|세\s*번째|모든|전체|양쪽|외부|보조)\s*(화면|모니터|디스플레이)|(화면|모니터)\s*(전부|다\s|모두|두\s*개)"#
    private static let otherEnglish = #"(?i)\b(other|another|second|third|external|both|all(\s+of)?(\s+my|\s+the)?|every)\s+(screens?|monitors?|displays?)\b"#
    /// Another screen as the place to put something, or the display as a device: not a look.
    private static let placeKorean = #"띄워|옮겨|보내|보여\s*(줘|주|드)|표로|밝기|해상도|미러링|녹화|꺼\s*줘|켜\s*줘|잠가"#
    private static let placeEnglish = #"(?i)\b(put|move|send|throw|drag|mirror|show (it|this|that|them)|open (it|this|that) on|brightness|resolution)\b"#

    /// "다른 화면에 있다", "옆 화면 봐 줘", "look at my other monitor": the displays besides the pointer's are wanted too.
    static func wantsOtherScreens(_ words: String) -> Bool {
        let korean = words.range(of: otherKorean, options: .regularExpression) != nil
            && words.range(of: placeKorean, options: .regularExpression) == nil
        let english = words.range(of: otherEnglish, options: .regularExpression) != nil
            && words.range(of: placeEnglish, options: .regularExpression) == nil
        return korean || english
    }

    // MARK: - A bare "뭐야?"

    private static let bareKorean = #"^(아리스|에리스)?(근데|어|아|응|엥|헐|와|잠깐)?((이게|저게|이거|저거|이건|저건)?(뭐야|뭐지|뭔데|뭐임|머야|뭐냐|뭐예요|뭐에요|뭐죠|뭐니))+$"#
    private static let bareEnglish = #"^(hey\s+)?(aris\s+)?(huh\s+)?(what|whats|what is|what's)(\s+(that|this|it))?$"#

    /// "뭐야?", "뭐야? 뭐야?", "what's that?": nothing else in the words to say what is meant, so it is what is showing.
    static func bareWhat(_ words: String) -> Bool {
        let korean = words.filter { !$0.isWhitespace && !$0.isPunctuation }
        if korean.range(of: bareKorean, options: .regularExpression) != nil { return true }
        let english = words.lowercased().replacingOccurrences(of: #"[^a-z' ]"#, with: " ", options: .regularExpression)
            .split(separator: " ").joined(separator: " ")
        return english.range(of: bareEnglish, options: .regularExpression) != nil
    }

    // MARK: - An app's words

    /// Terminals and the editors with one inside.
    private static let consoles = ["Terminal", "iTerm2", "Ghostty", "Warp", "WezTerm", "Alacritty", "kitty", "Visual Studio Code", "Cursor"]
    /// Names said for apps, each with the apps it may be (the first one showing wins). Everyday words that are also apps
    /// (메일, 메모, 메시지, 사진, 지도, 음악, 설정, 캘린더) are left out: their own tools read them, not the screen.
    static let spokenNames: [String: [String]] = [
        "어사이드": ["Aside"], "아사이드": ["Aside"], "aside": ["Aside"],
        // The coding agents' sessions are answered from what Aris's hooks know, never read off the screen: named, so "claude"
        // inside "claude code" isn't the Claude app, but no app.
        "클로드 코드": [], "클로드코드": [], "클코": [], "claude code": [], "코덱스": [], "codex": [], "제미나이 cli": [], "gemini cli": [],
        "터미널": consoles, "terminal": consoles, "아이텀": ["iTerm2", "iTerm"], "iterm": ["iTerm2", "iTerm"], "고스티": ["Ghostty"], "ghostty": ["Ghostty"],
        "워프": ["Warp"], "클로드": ["Claude"], "claude": ["Claude"], "챗지피티": ["ChatGPT"], "챗gpt": ["ChatGPT"], "chatgpt": ["ChatGPT"],
        "크롬": ["Google Chrome"], "chrome": ["Google Chrome"], "사파리": ["Safari"], "safari": ["Safari"], "아크": ["Arc"], "arc": ["Arc"],
        "파이어폭스": ["Firefox"], "firefox": ["Firefox"], "브레이브": ["Brave Browser"], "엣지": ["Microsoft Edge"],
        "슬랙": ["Slack"], "slack": ["Slack"], "디스코드": ["Discord"], "discord": ["Discord"], "카톡": ["KakaoTalk"], "카카오톡": ["KakaoTalk"],
        "kakaotalk": ["KakaoTalk"], "노션": ["Notion"], "notion": ["Notion"], "옵시디언": ["Obsidian"], "obsidian": ["Obsidian"],
        "브이에스코드": ["Visual Studio Code"], "vs code": ["Visual Studio Code"], "vscode": ["Visual Studio Code"],
        "엑스코드": ["Xcode"], "xcode": ["Xcode"], "피그마": ["Figma"], "figma": ["Figma"], "줌": ["zoom.us"], "zoom": ["zoom.us"],
        "텔레그램": ["Telegram"], "telegram": ["Telegram"], "왓츠앱": ["WhatsApp"], "whatsapp": ["WhatsApp"], "퍼플렉시티": ["Perplexity"],
        "perplexity": ["Perplexity"], "워드": ["Microsoft Word"], "엑셀": ["Microsoft Excel"], "파워포인트": ["Microsoft PowerPoint"],
        "파인더": ["Finder"],
    ]

    /// App names that are everyday words ("my cursor", "read my notes", "messages"), or apps whose own tools read them:
    /// never taken for the app here.
    private static let commonWords: Set<String> = ["cursor", "notes", "mail", "messages", "music", "photos", "maps", "calendar", "reminders",
                                                   "contacts", "settings", "systemsettings", "news", "stocks", "weather", "clock", "books",
                                                   "home", "shortcuts", "preview", "freeform", "podcasts", "tv"]

    /// Asking what an app says or shows: its words, its answer, what is on it.
    private static let readKorean = #"뭐라고|뭐래|뭐라\s*(해|했|하|그래|그랬)|뭐\s*(했|하고|해\s*놨|나와|떠|있|써|적|보여|와\s*있|왔)|무슨\s*말|뭔\s*말|읽어|말한|말했|한\s*말|대답|답변|답이|답을|답은|답\s*(좀\s*)?(읽|알려|요약|봐)|적힌|적혀|써\s*있|쓰여|나와\s*있|나온|떠\s*있|뜬|보이는|내용|세션|진행|요약|에러|오류|어디까지"#
    private static let readEnglish = #"(?i)\b(say|says|said|saying|wrote|written|writing|answer(ed|s)?|repl(y|ied|ies)|response|showing|shows|read|telling|told|session|output|error)\b|\bwhat('?s|\s+is|\s+does|\s+did|\s+was)\b"#
    /// Doing something with the app instead: opening, closing, asking it to do the work.
    private static let actKorean = #"(한테|에게|더러)\s*(물어|시켜|맡겨|부탁)|시켜|맡겨|열어|켜\s*줘|꺼\s*줘|닫아|실행|종료|띄워|깔아|설치"#
    private static let actEnglish = #"(?i)\b(open|launch|quit|close|kill|install)\b|\b(ask|have|tell|get)\s+\S+(\s+\S+)?\s+to\b|\bhave\s+\S+\s+do\b"#

    /// The apps in `apps` (those with a window showing) whose words or contents the request asks about, in the order of
    /// `apps`; none when it asks to open, close or hand something to them.
    static func readsApps(_ words: String, apps: [String]) -> [String] {
        guard !apps.isEmpty else { return [] }
        var text = words.precomposedStringWithCanonicalMapping
        let reads = text.range(of: readKorean, options: .regularExpression) != nil || text.range(of: readEnglish, options: .regularExpression) != nil
        let acts = text.range(of: actKorean, options: .regularExpression) != nil || text.range(of: actEnglish, options: .regularExpression) != nil
        guard reads, !acts else { return [] }
        let showing = Dictionary(apps.map { (key($0), $0) }, uniquingKeysWith: { first, _ in first })
        var found: [String] = []
        // The longest names first, so "Claude Code" isn't read as "Claude".
        var said = spokenNames.map { (name: $0.key, apps: $0.value) }
        said += apps.filter { $0.count >= 3 && !commonWords.contains(key($0)) }.map { (name: $0, apps: [$0]) }
        for (name, candidates) in said.sorted(by: { $0.name.count > $1.name.count }) {
            guard let range = mention(name, in: text) else { continue }
            // A shorter name inside a longer one already found ("claude" in "claude code") is the same mention.
            text.replaceSubrange(range, with: String(repeating: " ", count: text[range].count))
            if let app = candidates.lazy.compactMap({ showing[key($0)] }).first, !found.contains(app) { found.append(app) }
        }
        return apps.filter(found.contains)
    }

    private static func key(_ name: String) -> String { name.lowercased().filter { !$0.isWhitespace } }

    /// Where `name` is said (Latin names as whole words, case-insensitive, spaces optional between its words).
    private static func mention(_ name: String, in text: String) -> Range<String.Index>? {
        let latin = name.unicodeScalars.allSatisfy(\.isASCII)
        let escaped = name.split(whereSeparator: \.isWhitespace).map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: #"\s*"#)
        let pattern = (latin ? #"(?<![A-Za-z0-9])"# : "") + escaped + (latin ? #"(?![A-Za-z0-9])"# : "")
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive])
    }
}
