//
//  ArisUIWords.swift
//  Aris
//
//  One UI language for every visible status line (QA, English macOS: the placeholder was English while 닫기, 생각 중,
//  날씨 보는 중 and 폴더 여는 중 were Korean). The language is ArisUILanguage's (the app's language setting, else the
//  Mac's first of Korean and English), the same one the guide and the team pages read. The agent's statuses come in
//  Korean and are shown in English when the UI is; a line of the app's own is written both ways where it is said
//  (text). Pure, so it's tested.
//

import Foundation

enum ArisUIWords {
    /// The UI is English (anything but Korean is shown in English).
    static var english: Bool { ArisUILanguage.english }

    static func english(preferred: String?) -> Bool { !(preferred ?? "ko").hasPrefix("ko") }

    /// A word or a sentence of Aris's own, in the UI's language (fresh install F5: cards, labels and failure lines
    /// stayed Korean on an English Mac).
    static func text(_ korean: String, _ english: String, english inEnglish: Bool = ArisUIWords.english) -> String {
        inEnglish ? english : korean
    }

    static var thinking: String { english ? "Thinking" : "생각 중" }
    static var close: String { english ? "Close" : "닫기" }

    /// An agent status ("날씨 보는 중") in the UI's language; an unknown one as it came.
    static func status(_ korean: String, english: Bool = ArisUIWords.english) -> String {
        guard english else { return korean }
        // A counted step ("메일 보는 중 · 2/3", a routine's): the count stays, the words are said in English like any status.
        if let step = ArisRoutineProgress.parse(korean) { return ArisRoutineProgress.line(step: step.step, total: step.total, text: status(step.text, english: true)) }
        if let known = statuses[korean] { return known }
        // "영상·소리 변환하는 중 (3분째)"
        if korean.hasPrefix("영상·소리 변환하는 중"), let minutes = korean.range(of: #"\d+"#, options: .regularExpression) {
            return "Converting video or sound (\(korean[minutes]) min)"
        }
        // A read the gate stopped: "읽기 막음 · 요청하지 않은 일이라 막았어요".
        if korean.hasPrefix(readBlocked), let why = readBlocks[String(korean.dropFirst(readBlocked.count))] { return "Read blocked · " + why }
        // One AI's limit was reached and another took the turn: "Claude 한도 → Codex".
        // The API model keeps its English name there ("API 브레인 한도 → Claude").
        let named = korean.replacingOccurrences(of: ArisBrain.api.title, with: ArisBrain.api.title(english: true))
        if korean.contains(" 한도 → ") { return named.replacingOccurrences(of: " 한도 → ", with: " limit → ") }
        // The chosen AI isn't on this Mac and another took the turn: "Claude 없음 → Codex".
        if korean.contains(" 없음 → ") { return named.replacingOccurrences(of: " 없음 → ", with: " not set up → ") }
        // Computer use names the app it is in: "카카오톡에서 입력 중…".
        for (pattern, english) in appPatterns {
            if let match = try? NSRegularExpression(pattern: pattern).firstMatch(in: korean, range: NSRange(korean.startIndex..., in: korean)),
               let name = Range(match.range(at: 1), in: korean) {
                return english.replacingOccurrences(of: "%@", with: String(korean[name]))
            }
        }
        return korean
    }

    private static let readBlocked = "읽기 막음 · "
    /// ArisReadWhy's words for the notch.
    private static let readBlocks: [String: String] = [
        "개인 내용이 밖으로 나갈 수 있어서 막았어요": "it could have carried private content out",
        "요청하지 않은 일이라 막았어요": "it wasn't asked for", "내부 주소라 막았어요": "it is an address inside this network",
        "허락을 꾸민 글이 있어서 막았어요": "the text faked a permission", "판단 못 했어요": "it couldn't be judged",
        "이번 턴에 읽기를 너무 많이 해서 막았어요": "too many reads in one turn", "요청과 맞지 않아 막았어요": "it didn't fit the request",
    ]
    /// A status with a name in it (%@): the app computer use works in.
    private static let appPatterns: [(String, String)] = [
        ("^(.+)에서 입력 중…$", "Typing in %@…"), ("^(.+)에서 누르는 중…$", "Working in %@…"), ("^(.+) 보는 중…$", "Looking at %@…"),
    ]

    private static let statuses: [String: String] = [
        "생각 중": "Thinking", "시킨 일이 맞는지 확인 중": "Checking it's what you asked", "날씨 보는 중": "Checking the weather", "기억하는 중": "Remembering", "잊는 중": "Forgetting",
        "기억 찾는 중": "Looking through memories", "창 정리 중": "Arranging windows", "창 보는 중": "Looking at windows",
        "음악 다루는 중": "Controlling music", "소리 맞추는 중": "Setting the volume", "앱 여는 중": "Opening the app",
        "링크 여는 중": "Opening the link", "폴더 여는 중": "Opening the folder", "폴더 만드는 중": "Making the folder",
        "옮기는 중": "Moving", "이름 바꾸는 중": "Renaming", "단축어 실행 중": "Running the shortcut", "단축어 보는 중": "Looking at shortcuts",
        "미리 알림 추가 중": "Adding a reminder", "일정 추가 중": "Adding the event", "일정 찾는 중": "Finding the event",
        "일정 지우는 중": "Deleting the event", "일정 바꾸는 중": "Changing the event", "캘린더 보는 중": "Looking at calendars",
        "캘린더 바꾸는 중": "Switching calendars", "캘린더 여는 중": "Opening Calendar", "메모 쓰는 중": "Writing a note",
        "화면 보는 중": "Looking at the screen", "답장 준비 중": "Preparing the reply", "선택한 내용 보는 중": "Reading the selection", "클립보드 보는 중": "Reading the clipboard",
        "클립보드에 넣는 중": "Copying to the clipboard", "브라우저 보는 중": "Looking at the browser", "Finder 보는 중": "Looking at Finder",
        "메시지 준비 중": "Preparing the message", "휴지통으로 옮기는 중": "Moving to the Trash", "키 누르는 중": "Pressing keys",
        "입력하는 중": "Typing", "결과 정리 중": "Putting the result together", "타이머 맞추는 중": "Setting the timer",
        "메시지 읽는 중": "Reading messages", "메일 보는 중": "Reading mail", "메모 찾는 중": "Searching notes", "파일 찾는 중": "Finding files",
        "Obsidian 찾는 중": "Searching Obsidian", "지도 여는 중": "Opening Maps", "길 찾는 중": "Finding the way", "주가 가져오는 중": "Getting the stock price", "환율 확인 중": "Checking the rate",
        "앱 다루는 중": "Working in the app", "파일 변환하는 중": "Converting the file", "파일 합치는 중": "Merging files",
        "PDF 나누는 중": "Splitting the PDF", "용량 줄이는 중": "Making it smaller", "영상·소리 변환하는 중": "Converting video or sound",
        "루틴 보는 중": "Looking at routines", "루틴 만드는 중": "Making the routine", "루틴 지우는 중": "Deleting the routine",
        "명령 실행 중": "Running a command", "Mac 다루는 중": "Working on the Mac", "웹 검색 중": "Searching the web",
        "웹 페이지 읽는 중": "Reading the web page", "파일 읽는 중": "Reading a file", "파일 고치는 중": "Editing a file",
        "Notion 보는 중": "Looking at Notion", "화면 다루는 중": "Working on the screen", "도구 쓰는 중": "Using a tool",
        "할 일 추가 중": "Adding a to-do", "할 일 끝내는 중": "Ticking off a to-do", "할 일 지우는 중": "Removing a to-do",
        "예약 만드는 중": "Scheduling", "예약 취소하는 중": "Cancelling a schedule", "예약 보는 중": "Looking at schedules",
        // Aside, computer use, a teammate's launch, the relay and the judge (aris-agent's other status lines).
        "Aside가 브라우저에서 하는 중": "Aside is working in the browser", "Aside 로그인 코드를 받는 중": "Getting the Aside sign-in code",
        "컴퓨터 사용 도구 설치 중…": "Installing the computer-use tool…",
        "Aris에 손쉬운 사용 권한을 켜 주세요": "Turn on Accessibility for Aris",
        "Aris에 기기 제어 및 데이터 접근 권한을 켜 주세요": "Turn on Device Control and Data Access for Aris",
        "Aris에 화면 기록 권한을 켜 주세요": "Turn on Screen Recording for Aris",
        "Claude Code 여는 중": "Opening Claude Code", "Claude Code 두 개가 일하는 중이라 기다려요": "Two Claude Code jobs are running, so this one waits",
        "Claude Code 작업 중": "Claude Code is working", "확인 기다리는 중": "Waiting for your OK",
        "Claude Code가 스스로 묻는 것 외에는 확인 없이 진행해요": "Going ahead without asking, except for Claude Code's own questions",
        "Aris가 대신 읽는 중": "Aris is reading it instead", "Aris가 대신 찾는 중": "Aris is searching instead", "Aris가 대신 하는 중": "Aris is doing it instead",
        "Aris가 판단해서 진행": "Aris judged it safe to go on",
        // The app's own.
        "대기 중": "Waiting", "확인 중": "Checking", "취소됨": "Cancelled",
        // A job whose stop aris-agent never confirmed (ArisJobCancel.unconfirmed).
        "중단됨 · 아직 돌고 있을 수 있어요": "Stopped · it may still be running",
    ]
}

/// The shelf's words in the notch.
enum ArisShelfWords {
    static func name(english: Bool = ArisUIWords.english) -> String { ArisUIWords.text("선반", "Shelf", english: english) }

    /// The shelf strip's button: its name, or how many there are when not all of them show.
    static func label(count: Int, shown: Int, english: Bool = ArisUIWords.english) -> String {
        count > shown ? ArisUIWords.text("모두 \(count)", "All \(count)", english: english) : name(english: english)
    }

    static func keep(english: Bool = ArisUIWords.english) -> String { ArisUIWords.text("선반에 두기", "Keep on the shelf", english: english) }
    static func give(english: Bool = ArisUIWords.english) -> String { ArisUIWords.text("Aris한테 주기", "Give to Aris", english: english) }
}
