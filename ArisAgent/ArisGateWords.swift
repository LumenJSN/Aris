//
//  ArisGateWords.swift
//  aris-agent
//
//  The gate's words in English (audit gate-24). Confirm cards, refusal reasons, the read-block line and the countdown's
//  spoken line were Korean only, so someone who asked "trash this file" got "휴지통으로 옮기기" and "외부 내용을 읽은
//  뒤라 한 번 더 확인할게요". One switch decides: the request has words and none of them Korean
//  (ArisScheduleCard.isEnglish, as the schedule card already did). The Korean stays exactly as it was, word for word:
//  it is what the gates make first, and these tables only say the same fixed titles, labels and lines in English.
//  Only words this code wrote are ever changed: a title's parts, and the fixed lines a card opens with (why it asks,
//  what kind of file this is). From the first line that isn't one of those on, everything is a value (a path, a
//  message, a mail's text, a tool's argument) and is never touched, so a line of the user's own that happens to read like
//  a label stays as he wrote it. The cards say their labels in English where they are made (ArisCardWords,
//  ArisCodexDriver.paramLine). Pure, so the tests run it.
//

import Foundation

enum ArisGateWords {
    /// The one switch: the user's request has words and none of them Korean.
    static func isEnglish(_ request: String) -> Bool { ArisScheduleCard.isEnglish(request) }

    /// Card titles and the words joined into them (a tool's name, a subcommand).
    static let titles: [String: String] = [
        "메시지 보내기": "Send message", "메일 보내기": "Send mail", "휴지통으로 옮기기": "Move to Trash", "키 누르기": "Press keys", "입력하기": "Type",
        "새 창 열기": "Open new window", "창 배치": "Arrange windows", "창 옮기기": "Move window", "앱 열기": "Open app", "링크 열기": "Open link",
        "폴더 열기": "Open folder", "음악": "Music", "볼륨": "Volume", "미리 알림": "Reminder", "일정 추가": "Add event", "메모": "Note",
        "클립보드": "Clipboard", "단축어 실행": "Run shortcut", "기억하기": "Remember", "잊기": "Forget", "타이머": "Timer", "지도 열기": "Open Maps",
        "파일 변환하기": "Convert files", "파일 합치기": "Merge files", "PDF 나누기": "Split PDF", "용량 줄이기": "Compress files", "Mac 작업": "Mac action",
        "길 찾기": "Directions", "되돌리기": "Undo", "명령 실행": "Run command", "파일 수정": "Edit files", "설정 파일 수정": "Edit settings file",
        "컴퓨터 사용 코드 실행": "Run computer-use code", "앞으로 이건 그냥 할까?": "Do this without asking from now on?",
        "Mac 재시동": "Restart Mac", "Mac 끄기": "Shut down Mac", "로그아웃": "Log out", "Mac 잠자기": "Sleep Mac",
        "폴더 만들기": "New folder", "이름 바꾸기": "Rename", "옮기기": "Move", "할 일에 넣기": "Add to-do", "할 일에서 빼기": "Remove to-do",
        "할 일 끝내기": "Complete to-do", "할 일 고치기": "Edit to-do", "메모 만들기": "New note",
        "추가": "Add", "빼기": "Remove", "지우기": "Delete", "끝내기": "Done", "고치기": "Edit", "보기": "Show", "설정": "Set", "새로 만들기": "New",
        "찾기": "Find", "최근 보기": "Recent", "취소": "Cancel", "멈추기": "Stop",
    ]

    /// The labels in front of a value on a card ("제목: …").
    static let labels: [String: String] = [
        "제목": "Title", "이름": "Name", "시작": "Start", "끝": "End", "받는 사람": "To", "참조": "Cc", "내용": "Text", "검색어": "Query", "장소": "Place",
        "설명": "Description", "참석자": "Attendees", "날짜": "Date", "마감": "Due", "대상": "Target", "때": "When", "길이 (분)": "Minutes", "캘린더": "Calendar",
        "종류": "Kind", "앱": "App", "키": "Keys",
    ]

    /// Whole lines the gates write, and what Aris says or shows when it refuses.
    static let lines: [String: String] = [
        ArisEscalation.taintedReason: "Asking once more because outside content was read",
        ArisEscalation.moneyReason: "I can't do anything that costs money",
        ArisEscalation.mailReason: "I don't send a mail I can't show in full on the card",
        ArisEscalation.literalEscapeNote: "The text to type holds the characters \\n as they are (not a line break)",
        ArisEscalation.judgedNote: "Aris judged it and went ahead",
        ArisAutoCard.notCheckedLine: "I couldn't check automatically that this is what you asked, so I'm asking",
        ArisAutoCard.tooFewLine: "Your request alone doesn't tell me this is what you asked, so I'm asking",
        ArisRiskPolicy.browserRefusal: "Browser work goes to Aside",
        "(어떤 파일인지 알 수 없어요)": "(the files aren't known)",
        "(알 수 없는 명령이라 실행하지 않아요)": "(an unknown command, so it won't run)",
        "가장 최근에 한 일을 되돌려요 (만든 일정이면 캘린더에서 지워지고, 취소한 예약이면 다시 살아나요)":
            "Undoes the latest action (an event it made is removed from the calendar; a cancelled schedule comes back)",
        "셸이나 도구가 시작할 때 읽는 설정 파일이에요. 바뀌는 내용 전체를 확인해 주세요.":
            "A settings file your shell or tools read when they start. Please check the whole change.",
        "Finder에서 고른 파일": "The files selected in Finder", "선반에 둔 파일": "The files on the shelf", "빈 메모": "Empty note", "새 폴더": "New folder",
        "Mac을 재시동해요. 저장하지 않은 작업은 잃을 수 있어요.": "Restarts the Mac. Unsaved work may be lost.",
        "Mac을 꺼요. 저장하지 않은 작업은 잃을 수 있어요.": "Shuts the Mac down. Unsaved work may be lost.",
        "지금 사용자에서 로그아웃해요. 저장하지 않은 작업은 잃을 수 있어요.": "Logs this user out. Unsaved work may be lost.",
        "Mac을 잠자기 상태로 둬요.": "Puts the Mac to sleep.",
        "받는 사람이 바뀌어서 한 번 더 확인할게요.": "The recipient changed, so I'm asking once more.",
        "링크가 들어가서 한 번 더 확인할게요.": "A link was added, so I'm asking once more.",
        "고친 내용은 더 조심할 일이라 한 번 더 확인할게요.": "The change needs more care, so I'm asking once more.",
        "고친 내용은 꼭 확인받는 일이라 한 번 더 확인할게요.": "The change is something I always ask about, so I'm asking once more.",
        "고친 내용은 할 수 없는 일이라 하지 않았어요.": "The changed version is something I can't do, so I didn't.",
        "고친 내용을 그대로 쓸 수 없어서 하지 않았어요.": "The changed version couldn't be used as it is, so I didn't do it.",
        // A connected service's lines (ArisMCPPolicy).
        "고친 값이 이 도구에 맞지 않아서 하지 않았어요.": "The changed value doesn't fit this tool, so I didn't do it.",
        "받는 곳이 바뀌어서 한 번 더 확인할게요.": "Where it goes changed, so I'm asking once more.",
        "보이지 않는 글자나 방향 바꾸는 글자가 들어 있어서 하지 않았어요.": "It holds invisible or direction-changing characters, so I didn't do it.",
        "한 번에 하나씩만 보내거나 바꿀 수 있어요. 나눠서 다시 해 주세요.": "Only one thing can be sent or changed at a time. Please ask again, one at a time.",
    ]

    /// Lines that begin with fixed words and go on with a value.
    static let leads: [(korean: String, english: String)] = [
        ("캘린더 일정이 지워져요: ", "A calendar event will be removed: "), ("예약을 다시 살려요 (혼자 실행돼요): ", "A schedule comes back (it runs on its own): "),
        ("기록에서 찾지 못한 일 ", "Not found in the record "), ("입력하는 글:", "Text to type:"), ("단계:", "Steps:"),
    ]

    /// A title in English: each part between " · " by the table; "명령 실행 (rm)" and "Finder 제어" by their shape.
    /// A part the table doesn't know (a service's name, a tool's name, a recipient) stays as it is.
    static func title(_ korean: String) -> String {
        korean.components(separatedBy: " · ").map { part -> String in
            if let known = titles[part] { return known }
            if part.hasPrefix("명령 실행 (") { return "Run command (" + part.dropFirst("명령 실행 (".count) }
            if part.hasSuffix(" 제어") { return "Control " + part.dropLast(" 제어".count) }
            return part
        }.joined(separator: " · ")
    }

    /// A card's details in English: the fixed lines it opens with (a whole line of `lines`, or a `leads` lead before
    /// its value). The first line that is neither, and every line after it, is a value and stays exactly as it is.
    static func detail(_ korean: String) -> String {
        var open = true
        return korean.components(separatedBy: "\n").map { line -> String in
            guard open else { return line }
            if let known = lines[line] { return known }
            open = false
            if let lead = leads.first(where: { line.hasPrefix($0.korean) }) { return lead.english + line.dropFirst(lead.korean.count) }
            return line
        }.joined(separator: "\n")
    }

    /// One fixed line, or a label, as a card made for an English request says it.
    static func word(_ korean: String, english: Bool) -> String { english ? lines[korean] ?? labels[korean] ?? titles[korean] ?? korean : korean }

    /// A line shown or said on its own (a refusal's reason, the read-block line) in English; any other line as it is.
    static func line(_ korean: String) -> String {
        if let known = lines[korean] ?? ArisAPIDriver.stopsInEnglish[korean] { return known }
        if let why = ArisReadWhy.allCases.first(where: { ArisReadGate.status($0) == korean }) { return ArisReadGate.status(why, english: true) }
        return korean
    }

    /// A confirm card in English. An editable card keeps its details (they are its fields' own text, which the app
    /// shows as rows and sends back); a "앞으로 이건 그냥 할까?" card keeps them too (they are checked against the scope).
    /// A countdown says its line in English; its title and details are the recipient and the message, never changed.
    static func card(_ ask: ArisConfirmation) -> ArisConfirmation {
        if ask.countdown {
            return ArisConfirmation(id: ask.id, title: ask.title, detail: ask.detail, countdown: true,
                                    spoken: ArisRiskPolicy.announcement(to: ask.title, text: ask.detail, english: true), full: ask.full, fields: ask.fields,
                                    memoryWrite: ask.memoryWrite, desktop: ask.desktop)
        }
        let plain = ask.fields.isEmpty && !ask.proposal
        return ArisConfirmation(id: ask.id, title: title(ask.title), detail: plain ? detail(ask.detail) : ask.detail, proposal: ask.proposal,
                                full: plain ? ask.full.map(detail) : ask.full, fields: ask.fields, allow: ask.allow, memoryWrite: ask.memoryWrite,
                                desktop: ask.desktop)
    }
}
