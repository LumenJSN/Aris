//
//  ArisCardEnglish+Desktop.swift
//  Aris
//
//  The helper's own desktop card (ArisDesktopCard.card: "Finder에서 누르기 / 창: “…” / 대상: 글자 “Downloads” / 백그라운드로
//  안 되면 …") in English, for an English UI under a Korean request (tenth VM run, item 12: only its 대상 label was
//  known here, so the card read "Finder에서 누르기 · 창 · Target · 글자 “Downloads”" with a Korean sentence under it). The
//  helper writes that card in the request's language; a card is drawn in the UI's (ArisCardEnglish). The English is the
//  helper's own (ArisDesktopCopy), word for word: the tests hold the two equal. Also which cards carry the activity
//  log's own line (an undo's "일정 추가: 치과" under "Delete the event"). Foundation only (tested).
//

import Foundation

extension ArisCardEnglish {
    /// ArisDesktopCard.verbLabel → ArisDesktopCopy.verb.
    static let desktopVerbs: [String: String] = [
        "누르기": "Click", "입력하기": "Type", "값 넣기": "Set a value", "키 누르기": "Press keys", "스크롤": "Scroll", "끌어다 놓기": "Drag and drop",
        "메뉴 고르기": "Choose a menu item", "대화상자 버튼 누르기": "Press a dialog button", "대화상자에 입력하기": "Type in a dialog",
        "파일 고르기": "Choose a file", "창 다루기": "Manage a window", "앱 다루기": "Manage an app", "화면 보고 누르기": "Look and click", "보기": "Look",
        "여러 단계 하기": "Do several steps", "붙여넣기": "Paste",
        // A replace or an erase (ArisDesktopErase.verb).
        "글 바꾸기": "Replace text", "글 지우기": "Erase text",
    ]

    /// ArisDesktopCard.roleWord → ArisDesktopCopy.roles (one English word per Korean word; "입력칸" is every text field).
    static let desktopRoles: [String: String] = [
        "입력칸": "text field", "검색칸": "search field", "암호 입력칸": "password field", "버튼": "button", "팝업 버튼": "pop-up button",
        "메뉴 버튼": "menu button", "체크박스": "checkbox", "선택 버튼": "radio button", "링크": "link", "메뉴 항목": "menu item", "메뉴": "menu",
        "탭": "tab", "슬라이더": "slider", "글자": "text", "그림": "image", "줄": "row", "칸": "cell", "표": "table", "목록": "list",
        "스크롤 영역": "scroll area", "창": "window", "묶음": "group", "도구 막대": "toolbar", "웹 페이지": "web page", "제목": "heading",
        "펼치기 버튼": "disclosure button", "요소": "item",
    ]

    /// The card's labelled rows (ArisDesktopCard.card's `say("…: ", "…: ")` pairs) that the general table doesn't have.
    static let desktopLabels: [String: String] = [
        "창": "Window", "사이트": "Site", "칸": "Field", "메뉴": "Menu", "버튼": "Button", "누를 버튼": "Button to press", "파일 이름": "File name",
        "형식": "Format", "놓을 곳": "Drop on", "찾을 것": "Looking for", "창 다루기": "Window", "지워지는 글": "Text that is erased",
    ]

    /// Lines the helper writes whole on that card.
    static let desktopLines: [String: String] = [
        "메시지 앱이라 매번 물어봐요": "This is a messaging app, so Aris asks every time",
        "읽은 내용이 있어서 다시 물어봐요": "Aris has read other text since your yes, so it asks again",
        "파일 창을 앞으로 가져와서 다뤄요": "The file panel is brought to the front for this",
        "이 문서를 저장하거나 열어요 (지금 앞에 있는 문서)": "This saves or opens this document (the one in front now)",
        "앱을 종료해요 (저장하지 않은 문서가 있으면 앱이 먼저 물어봐요)": "This quits the app (if a document isn't saved, the app asks first)",
        "창을 찍어 AI가 위치를 찾은 뒤 그 자리를 눌러요 (안 되면 실제 마우스로)":
            "Aris takes a picture of the window, an AI finds the spot, and that spot is clicked (with the real pointer if it must)",
        "⚠️ 이 창의 글을 모두 선택해서 지워요": "⚠️ This selects all the text in this window and deletes it",
        // A replace or an erase (ArisDesktopErase.cardLines).
        "⚠️ 이 창의 글을 모두 지우고 그 자리에 입력해요": "⚠️ This erases all the text in this window and types in its place",
        "⚠️ 이 창의 글을 모두 지워요": "⚠️ This erases all the text in this window",
        "⚠️ 선택한 글을 지우고 그 자리에 입력해요": "⚠️ This erases the selected text and types in its place",
        "⚠️ 선택한 글을 지워요": "⚠️ This erases the selected text",
        "지워질 글을 미리 읽지 못했어요. 그 사이 글이 보이면 하지 않고 다시 물어봐요":
            "The text that would be erased couldn't be read first. If text shows there by then, nothing is done and Aris asks again",
        "이 앱은 입력 칸의 글을 읽을 수 없어서, 입력한 뒤 창을 다시 읽어 확인해요":
            "This app's text field can't be read, so after typing Aris reads the window again to check",
    ]

    /// "Finder에서 누르기" → "Click in Finder", "메모 종료하기" → "Quit 메모"; nil for any other title.
    static func desktopTitle(_ korean: String) -> String? {
        if let match = desktopMatch(#"^(.+)에서 (.+)$"#, korean), let verb = desktopVerbs[match[1]] { return "\(verb) in \(match[0])" }
        if let match = desktopMatch(#"^(.+) 종료하기$"#, korean) { return "Quit \(match[0])" }
        return nil
    }

    /// One row of that card in English; nil when it is none of its rows (the general rules go on).
    static func desktopRow(_ row: String) -> String? {
        if let known = desktopLines[row] { return known }
        // "대상: 글자 “Downloads”": the role's word, the element's own name as it is.
        if let match = desktopMatch(#"^대상: (.+?)( “.*”)?$"#, row), let role = desktopRoles[match[0]] { return "Target: " + role + match[1] }
        // The trust gate's card for an element with no name of its own, or one nothing was read for (ArisApps.Grounding.shown).
        if let match = desktopMatch(#"^대상: 이름 없는 (.+)$"#, row), let role = desktopRoles[match[0]] { return "Target: an unnamed " + role }
        if row == "대상: 이름을 읽지 못한 요소" { return "Target: an item whose name couldn't be read" }
        if let match = desktopMatch(#"^백그라운드로 안 되면 (?:‘(.*)’ )?창을 앞으로 가져와서 (.+) \(끝나면 원래 앱으로 돌아가요\)$"#, row), desktopVerbs[match[1]] != nil {
            let named = match[0].isEmpty ? "" : " “\(match[0])”"
            return "If it can't be done in the background, the window\(named) is brought to the front for it (then the app you were in comes back)"
        }
        if let match = desktopMatch(#"^허용하면 이 대화에서 (.+)[은는] 다시 묻지 않아요$"#, row) {
            return "If you allow it, Aris won't ask again for \(match[0]) in this conversation"
        }
        let parts = row.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count == 2, let label = desktopLabels[String(parts[0])] { return label + ":" + parts[1] }
        return nil
    }

    /// The cards an undo asks first (ArisActivityTimeline.confirmation): their one row is the activity log's own line
    /// ("일정 추가: 치과", "예약 취소: …"), whose kind is said as the side notch says it (ArisActivityWords' own leads; the
    /// tests hold them equal). What follows the kind is his own title and stays.
    static let undoLeads: [String: [(korean: String, english: String)]] = [
        "일정 지우기": [("일정 추가: ", "Event added: ")],
        "예약 다시 살리기": [("예약 취소: ", "Schedule cancelled: ")],
        // The same cards when their title came in English already (ArisActivityTimeline.confirmation in an English UI:
        // "Delete the event" over "일정 추가: …" in the eleventh VM run).
        "Delete the event": [("일정 추가: ", "Event added: ")],
        "Bring the schedule back": [("예약 취소: ", "Schedule cancelled: ")],
    ]

    /// An undo card's row in English; nil on any other card or for a row that isn't the log's line.
    static func undoRow(_ row: String, title: String) -> String? {
        guard let lead = undoLeads[title]?.first(where: { row.hasPrefix($0.korean) }) else { return nil }
        return lead.english + row.dropFirst(lead.korean.count)
    }

    private static func desktopMatch(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
    }
}
