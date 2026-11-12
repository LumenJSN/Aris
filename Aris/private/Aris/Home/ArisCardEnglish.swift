//
//  ArisCardEnglish.swift
//  Aris
//
//  A confirm card in English (VM run, bug 4: "폴더 만들기 / 바탕화면 / 취소 / 허용" under an English request). A card is
//  one language through and through, the language of the request it answers: aris-agent already writes its computer
//  use, schedule and Aside cards that way, and every other card it writes in Korean (ArisCardWords, ArisCodexDriver's
//  titles, the fields of an editable card). Those are put into English here, where the card is drawn, so nothing the
//  agent checks or echoes changes: the session keeps the card as it came. A title, a row's label, a line the agent
//  writes whole and Finder's folder names have their English; the user's own words (a message, a file's name, a to-do)
//  stay as they are, and so does a line this table doesn't know. The words are aris-agent's own where it has them
//  (ArisGateWords, which now writes most cards in English itself for an English request): this is what is left to
//  draw (an editable card's field labels, a "앞으로 이건 그냥 할까?" card's rows, the event, connector and file cards). A request with no words (an undo from the panel)
//  follows the Mac's language. Foundation only (tested).
//

import Foundation

enum ArisCardEnglish {
    /// The card is drawn in English: the request has words and none of them Korean; with no request, the UI's language.
    static func isEnglish(request: String, uiEnglish: Bool = ArisUIWords.english) -> Bool {
        guard !request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return uiEnglish }
        return !hasHangul(request)
    }

    static func hasHangul(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) || (0x3131...0x318E).contains($0.value) }
    }

    /// A card's title: "폴더 만들기" → "New folder", "미리 알림 · 추가" → "Reminder · Add", "Safari 제어" → "Control Safari".
    static func title(_ korean: String) -> String {
        guard hasHangul(korean) else { return korean }
        if let known = titles[korean] { return known }
        // Several commands on one card, or a noun and what is done to it.
        let pieces = korean.components(separatedBy: " · ")
        if pieces.count > 1 { return pieces.map { titles[$0] ?? verbs[$0] ?? title($0) }.joined(separator: " · ") }
        for (pattern, english) in titlePatterns {
            if let value = capture(pattern, in: korean) { return english.replacingOccurrences(of: "%@", with: titles[value] ?? verbs[value] ?? value) }
        }
        return korean
    }

    /// A row's label: "받는 사람" → "To".
    static func label(_ korean: String) -> String { labels[korean] ?? korean }

    /// The details, line by line. A "label: value" row gets its label's English; its value stays (it is the user's own
    /// words: a message, a title) unless the agent wrote it (where a file goes). A line the agent writes whole has
    /// its English; a file card's paths are named as Finder names them in English; a desktop card's first line says
    /// what is done in which window. Everything else stays as it is: a note's lines, a to-do, the text to type.
    static func detail(_ korean: String, title: String) -> String {
        guard hasHangul(korean) else { return korean }
        let files = fileTitles.contains(title), desktop = desktopTitles.contains(title) || title.hasPrefix("창 ") || title.hasPrefix("앱 ")
        // A to-do's or a note's lines are the user's own words: none of them is taken for one of the agent's lines.
        let own = ownWordsTitles.contains(title)
        // Codex's own computer-use cards: an app it will work in ("Safari 사용"), a chat it will send in ("엄마에서 보내기").
        let usesApp = title.hasSuffix(" 사용") || title.contains(" 사용 · "), sendsInChat = title.hasSuffix("에서 보내기")
        return korean.components(separatedBy: "\n").enumerated().map { index, row -> String in
            if !own || row == "빈 메모", let known = lines[row] { return known }
            for (prefix, english) in leads where row.hasPrefix(prefix) { return english + row.dropFirst(prefix.count) }
            let parts = row.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2, let known = labels[parts[0].trimmingCharacters(in: .whitespaces)] {
                let value = parts[1].trimmingCharacters(in: .whitespaces)
                let written = writtenByAgent.contains(String(parts[0])) ? place(lines[value] ?? value) : value
                return known + ":" + (value.isEmpty ? "" : " " + written)
            }
            if files { return place(row) }
            if desktop, index == 0 { return windowLine(row) ?? row }
            if let more = capture(#"^…\((\d+)줄 더\)$"#, in: row) ?? capture(#"^\(\+(\d+)줄 더\)$"#, in: row) { return "…(\(more) more lines)" }
            // The Claude Code card's note when only the tool's new version keeps the launch from going ahead on its own.
            if let version = capture(#"^Claude Code가 업데이트돼서 \(버전 (.+)\) 확인할게요$"#, in: row) {
                return "Claude Code was updated (version \(version == "확인 불가" ? "unknown" : version)), so I'm asking"
            }
            // Codex's own computer-use cards (ArisCodexDriver+ComputerUse): what it will do in the app and what was asked
            // of it there; the chat a send goes to. The text it will type is the user's and stays as it is.
            if usesApp {
                if let app = capture(#"^화면을 보고 (.+)[을를] 직접 클릭하고 입력해요$"#, in: row) { return "Looks at the screen, and clicks and types in \(app) itself" }
                if index == 0, let app = capture(#"^(.+?)에서: "#, in: row) { return "In \(app): " + row.dropFirst(app.count + "에서: ".count) }
            }
            if title == "녹음", row.hasPrefix("요청: ") { return "Request: " + row.dropFirst("요청: ".count) }
            if sendsInChat {
                if index == 1, row == "(없음)" { return "(none)" }
                if row == "대화는 코드가 직접 골라요 (이름이 코드에 없어요)" { return "The code picks the chat itself (its name isn't in the code)" }
                if row.hasPrefix("코드가 고른 대화: ") { return "Chat the code picked: " + row.dropFirst("코드가 고른 대화: ".count) }
            }
            return row
        }.joined(separator: "\n")
    }

    /// A path as Finder names it, in English: "바탕화면 › qa-test" → "Desktop › qa-test"; "a → b" side by side.
    static func place(_ korean: String) -> String {
        let sides = korean.components(separatedBy: " → ")
        if sides.count == 2 { return sides.map(place).joined(separator: " → ") }
        var parts = korean.components(separatedBy: " › ")
        guard let first = parts.first, let named = folders[first] else { return korean }
        parts[0] = named
        return parts.joined(separator: " › ")
    }

    /// The cards whose details are paths (ArisCardWords, ArisFileRelay).
    private static let fileTitles: Set<String> = ["폴더 만들기", "폴더 열기", "이름 바꾸기", "옮기기", "파일 옮기기", "새 폴더 만들기"]
    /// The cards whose first line is what is done in which window (ArisCardWords.desktop).
    private static let desktopTitles: Set<String> = ["입력하기", "값 바꾸기", "클릭하기", "키 누르기", "스크롤하기", "끌어 놓기", "메뉴 누르기", "메뉴 보기", "대화상자",
                                                     "여러 단계 하기", "화면 읽기", "결과 기다리기", "Mac 작업"]
    /// The cards whose lines are the user's own words.
    private static let ownWordsTitles: Set<String> = ["할 일에 넣기", "할 일에서 빼기", "할 일 끝내기", "할 일 고치기", "할 일 완료", "메모 만들기"]
    /// The rows whose value the agent writes (a place), never the user's words.
    private static let writtenByAgent: Set<String> = ["위치", "저장할 것", "폴더"]

    // MARK: - the tables

    /// ArisCardWords, ArisCodexDriver.toolTitles and describe, ArisEventCard, ArisFileRelay, ArisEditableAction, the
    /// gates' own cards and the app's.
    static let titles: [String: String] = [
        "폴더 만들기": "New folder", "폴더 열기": "Open folder", "이름 바꾸기": "Rename", "옮기기": "Move", "파일 옮기기": "Move a file",
        "새 폴더 만들기": "New folder", "할 일에 넣기": "Add to-do", "할 일에서 빼기": "Remove to-do", "할 일 끝내기": "Complete to-do",
        "할 일 고치기": "Edit to-do", "할 일 완료": "Finish to-do", "메모 만들기": "New note", "입력하기": "Type", "값 바꾸기": "Change a value",
        "클릭하기": "Click", "키 누르기": "Press keys", "스크롤하기": "Scroll", "끌어 놓기": "Drag and drop", "메뉴 누르기": "Choose a menu item",
        "메뉴 보기": "Look at the menus", "대화상자": "Dialog", "여러 단계 하기": "Do several steps", "화면 읽기": "Read the screen",
        "결과 기다리기": "Wait for the result", "Mac 작업": "Mac action", "메시지 보내기": "Send message", "메일 보내기": "Send mail",
        "휴지통으로 옮기기": "Move to Trash", "새 창 열기": "Open new window", "창 배치": "Arrange windows", "창 옮기기": "Move window",
        "앱 열기": "Open app", "링크 열기": "Open link", "음악": "Music", "볼륨": "Volume", "미리 알림": "Reminder", "일정 추가": "Add event",
        "일정 지우기": "Delete the event", "일정 바꾸기": "Change the event", "메모": "Note", "클립보드": "Clipboard", "단축어 실행": "Run shortcut",
        "기억하기": "Remember", "잊기": "Forget", "타이머": "Timer", "지도 열기": "Open Maps", "길 찾기": "Directions",
        "파일 변환하기": "Convert files", "파일 합치기": "Merge files", "PDF 나누기": "Split PDF", "용량 줄이기": "Compress files",
        "되돌리기": "Undo", "명령 실행": "Run command", "파일 수정": "Edit files", "읽기 확인": "Allow a read", "컴퓨터 사용 코드 실행": "Run computer-use code",
        "컴퓨터 사용": "Computer use", "앞으로 이건 그냥 할까?": "Do this without asking from now on?", "Claude Code 열기": "Open Claude Code", "예약 추가": "Add a schedule",
        "예약 다시 살리기": "Bring the schedule back", "파일로 저장": "Save as a file",
        "설정 파일 수정": "Edit settings file", "Mac 재시동": "Restart Mac", "Mac 끄기": "Shut down Mac", "로그아웃": "Log out", "Mac 잠자기": "Sleep Mac",
        "녹음": "Recording",
        "창 앞으로 가져오기": "Bring a window forward", "창 닫기": "Close a window", "창 내리기": "Minimise a window", "창 되살리기": "Restore a window",
        "창 최대화": "Maximise a window", "창 크기 바꾸기": "Resize a window", "창 목록": "List windows", "창 다루기": "Manage a window",
        "앱 앞으로 가져오기": "Bring an app forward", "앱 숨기기": "Hide an app", "앱 종료": "Quit an app", "앱 다루기": "Manage an app",
    ]

    /// What is done to a noun title ("미리 알림 · 추가"): ArisCodexDriver.subcommandWords.
    static let verbs: [String: String] = [
        "추가": "Add", "빼기": "Remove", "지우기": "Delete", "끝내기": "Done", "고치기": "Edit", "보기": "Show", "설정": "Set",
        "새로 만들기": "New", "찾기": "Find", "최근 보기": "Recent", "취소": "Cancel", "멈추기": "Stop",
    ]

    private static let titlePatterns: [(String, String)] = [
        (#"^(.+) 제어$"#, "Control %@"), (#"^명령 실행 \((.+)\)$"#, "Run command (%@)"), (#"^컴퓨터 사용 · (.+)$"#, "Computer use · %@"),
        // Codex's own computer-use cards (ArisCodexDriver+ComputerUse): an app it will work in, a chat it will send in.
        (#"^(.+) 사용$"#, "Use %@"), (#"^표시: (.+)$"#, "shown as %@"), (#"^(.+)에서 보내기$"#, "Send in %@"),
    ]

    /// The rows' labels: an editable card's fields, the connectors' argument names, the cards' own.
    static let labels: [String: String] = [
        "받는 사람": "To", "내용": "Text", "제목": "Title", "때": "When", "시작": "Start", "끝": "End", "길이 (분)": "Minutes",
        "캘린더": "Calendar", "이름": "Name", "참조": "Cc", "검색어": "Query", "장소": "Place", "설명": "Description", "참석자": "Attendees",
        "날짜": "Date", "마감": "Due", "대상": "Target", "위치": "Where", "저장할 것": "Saving", "시간": "Time", "키": "Keys", "단계": "Steps",
        "입력하는 글": "Text to type", "폴더": "Folder", "종류": "Kind", "앱": "App", "언제": "When", "할 일": "Does", "팀원": "Teammate",
        "보내는 곳": "Through", "되돌릴 일": "To undo", "바깥으로 나가는 일": "Goes outside",
    ]

    /// Lines the agent writes whole.
    private static let lines: [String: String] = [
        "새 폴더": "New folder", "빈 메모": "Empty note", "홈": "Home", "이 일정 하나만 지워요": "Only this one event is deleted",
        "(어떤 파일인지 알 수 없어요)": "(the files aren't known)", "(알 수 없는 명령이라 실행하지 않아요)": "(an unknown command, so it won't run)",
        "가장 최근에 한 일을 되돌려요 (만든 일정이면 캘린더에서 지워지고, 취소한 예약이면 다시 살아나요)":
            "Undoes the latest action (an event it made is removed from the calendar; a cancelled schedule comes back)",
        "진행 중인 작업의 결과 기다리기": "Wait for the result of the job in progress", "Finder에서 고른 파일": "The files selected in Finder",
        "선반에 둔 파일": "The files on the shelf", "방금 답": "the last answer", "메모 앱 (새 메모)": "Notes (a new note)",
        "팀원 없이 Aris로 실행돼요": "Runs as Aris, with no teammate", "⚠️ 홈 폴더 밖의 폴더예요": "⚠️ This folder is outside the home folder",
        "메뉴 누르기": "Choose a menu item", "메뉴 보기": "Look at the menus", "대화상자 다루기": "Work in a dialog",
        "외부 내용을 읽은 뒤라 한 번 더 확인할게요": "Asking once more because outside content was read", "(값 없음)": "(no values)",
        "다른 곳에서 읽은 내용 뒤라서 먼저 물어봐요.": "Asking first, since text from elsewhere was read.",
        "대화 모드로 들은 말이라 먼저 물어봐요.": "Asking first, since this was heard in conversation mode.",
        "맡긴 일 중에 하는 거라 먼저 물어봐요.": "Asking first, since this is part of a job handed over.",
        "화면을 본 대화라 먼저 물어봐요.": "Asking first, since the screen was looked at in this conversation.",
        "받는 사람이 바뀌어서 한 번 더 확인할게요.": "The recipient changed, so I'm asking once more.",
        "링크가 들어가서 한 번 더 확인할게요.": "A link was added, so I'm asking once more.",
        "고친 내용은 더 조심할 일이라 한 번 더 확인할게요.": "The change needs more care, so I'm asking once more.",
        "새 파일로 만들어요 (같은 이름의 파일이 있으면 저장하지 않아요)": "A new file is made (nothing is saved if a file with that name is there)",
        "셸이나 도구가 시작할 때 읽는 설정 파일이에요. 바뀌는 내용 전체를 확인해 주세요.": "A settings file your shell or tools read when they start. Please check the whole change.",
        "Mac을 재시동해요. 저장하지 않은 작업은 잃을 수 있어요.": "Restarts the Mac. Unsaved work may be lost.",
        "Mac을 꺼요. 저장하지 않은 작업은 잃을 수 있어요.": "Shuts the Mac down. Unsaved work may be lost.",
        "지금 사용자에서 로그아웃해요. 저장하지 않은 작업은 잃을 수 있어요.": "Logs this user out. Unsaved work may be lost.",
        "Mac을 잠자기 상태로 둬요.": "Puts the Mac to sleep.",
        "고친 내용은 꼭 확인받는 일이라 한 번 더 확인할게요.": "The change is something I always ask about, so I'm asking once more.",
        "받는 곳이 바뀌어서 한 번 더 확인할게요.": "Where it goes changed, so I'm asking once more.",
        "컴퓨터 소리를 녹음해요": "Records the computer's sound",
    ]

    /// What a line starts with, before words that stay as they are.
    private static let leads: [(String, String)] = [
        ("캘린더 일정이 지워져요: ", "A calendar event will be removed: "), ("예약을 다시 살려요 (혼자 실행돼요): ", "A schedule comes back (it runs on its own): "),
        ("기록에서 찾지 못한 일 ", "Not found in the record "), ("⚠️ 이 답에는 바깥 글(화면, 웹, 파일, 메일)에서 온 내용이 있어요", "⚠️ This answer holds text from outside (the screen, the web, a file, mail)"),
    ]

    /// Home's folders as Finder names them (ArisCardWords.folders).
    private static let folders = ["바탕화면": "Desktop", "문서": "Documents", "다운로드": "Downloads", "사진": "Pictures", "동영상": "Movies", "음악": "Music",
                                  "응용 프로그램": "Applications", "라이브러리": "Library", "공개": "Public", "홈": "Home"]

    /// What ArisCardWords.desktop says is done in a window, and how the English names the place.
    private static let windowActs: [String: String] = [
        "입력하기": "Type in", "칸 내용 바꾸기": "Change a field in", "클릭하기": "Click in", "키 누르기": "Press keys in", "스크롤하기": "Scroll in",
        "끌어 놓기": "Drag and drop in", "여러 단계 하기": "Do several steps in", "읽기": "Read", "작업하기": "Work in", "앞으로 가져오기": "Bring forward",
        "닫기": "Close", "내리기": "Minimise", "되살리기": "Restore", "최대화": "Maximise", "옮기기": "Move", "크기 바꾸기": "Resize", "목록": "List the windows of",
        "다루기": "Manage",
    ]
    private static let appActs: [String: String] = ["열기": "Open", "앞으로 가져오기": "Bring forward", "숨기기": "Hide", "종료": "Quit", "다루기": "Manage"]

    /// "TextEdit ‘무제’ 창에 입력하기" → "Type in the TextEdit window “무제”"; "TextEdit의 메뉴 누르기"; "Safari 종료".
    private static func windowLine(_ korean: String) -> String? {
        let pattern = #"^(.+?)(?: ‘(.*)’)? 창(?:에서|에|의)? (.+)$"#
        if let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: korean, range: NSRange(korean.startIndex..., in: korean)),
           let app = Range(match.range(at: 1), in: korean), let act = Range(match.range(at: 3), in: korean), let verb = windowActs[String(korean[act])] {
            let named = Range(match.range(at: 2), in: korean).map { " “\(korean[$0])”" } ?? ""
            return "\(verb) the \(korean[app]) window\(named)"
        }
        if let app = capture(#"^(.+)의 메뉴 누르기$"#, in: korean) { return "Choose a menu item in \(app)" }
        if let app = capture(#"^(.+)의 메뉴 보기$"#, in: korean) { return "Look at \(app)'s menus" }
        if let app = capture(#"^(.+)의 대화상자 다루기$"#, in: korean) { return "Work in \(app)'s dialog" }
        for (act, verb) in appActs {
            if korean.hasSuffix(" " + act) {
                let app = String(korean.dropLast(act.count + 1))
                return app == "앱" ? "\(verb) an app" : "\(verb) \(app)"
            }
        }
        return nil
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}
