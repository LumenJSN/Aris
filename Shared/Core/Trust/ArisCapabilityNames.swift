//
//  ArisCapabilityNames.swift
//  Shared/Core (app, aris-agent, tests)
//
//  What each capability is called where the owner reads it (the 한 일 list, the day-end card, an undo's line): one
//  table, Korean and English, for every capability in the book (tests/vmfix2-tests.swift fails when one has none). A
//  capability's id ("aris.desktop_batch") is the record's and the model's, never the owner's (VM run 2026-11-19, D5:
//  the day review showed "aris.desktop_batch · 바꾸기 · TextEdit"). The Korean words follow the activity log's own
//  ("이름 바꿈", "일정 추가"), so a line reads the same whichever path wrote it. Foundation only.
//

import Foundation

enum ArisCapabilityNames {
    struct Name: Hashable, Sendable {
        let korean: String
        let english: String
    }

    private static func n(_ korean: String, _ english: String) -> Name { Name(korean: korean, english: english) }

    /// By capability id.
    static let table: [String: Name] = [
        // aris-tools' typed functions (ArisCapabilityFunctions), and the generic one.
        "aris.aris": n("Aris 도구", "Aris tool"),
        "aris.timer": n("타이머", "Timer"),
        "aris.music": n("음악", "Music"),
        "aris.volume": n("볼륨", "Volume"),
        "aris.open_app": n("앱 열기", "App opened"),
        "aris.weather": n("날씨 보기", "Weather"),
        "aris.todo_add": n("할 일 추가", "To-do added"),
        "aris.remind": n("미리 알림 추가", "Reminder added"),
        "aris.add_event": n("일정 추가", "Event added"),
        "aris.list_events": n("일정 보기", "Calendar read"),
        "aris.send_message": n("메시지 보냄", "Message sent"),
        "aris.save_note": n("메모 저장", "Note saved"),
        "aris.remember": n("기억함", "Remembered"),
        "aris.stock": n("주가 보기", "Stock price"),
        "aris.currency": n("환율 보기", "Exchange rate"),
        "aris.recall": n("기억 찾기", "Memory searched"),
        "aris.file_read": n("파일 읽기", "File read"),
        "aris.file_rename": n("이름 바꿈", "Renamed"),
        "aris.file_move": n("옮김", "Moved"),
        "aris.file_trash": n("휴지통으로 옮김", "Moved to the Trash"),
        "aris.folder_new": n("새 폴더", "New folder"),
        "aris.file_convert": n("변환", "Converted"),
        "aris.files_merge": n("합침", "Merged"),
        "aris.pdf_split": n("나눔", "Split"),
        "aris.files_compress": n("압축", "Made smaller"),
        "aris.desktop_save_as": n("다른 이름으로 저장", "Saved as"),
        "aris.aside_task": n("Aside에 맡김", "Handed to Aside"),
        "aris.claude_session_send": n("코딩 세션에 보냄", "Sent to a coding session"),
        "aris.claude_sessions": n("코딩 세션 보기", "Coding sessions read"),
        "aris.devin_sessions": n("Devin 세션 보기", "Devin sessions read"),
        "aris.desktop_see": n("앱 화면 보기", "App looked at"),
        "aris.desktop_click": n("앱에서 누름", "Clicked in an app"),
        "aris.desktop_type": n("앱에 입력", "Typed into an app"),
        "aris.desktop_batch": n("앱에서 여러 단계", "Steps in an app"),
        "aris.desktop_set_value": n("앱의 값 바꿈", "Value changed in an app"),
        "aris.desktop_press": n("앱에서 키 누름", "Keys pressed in an app"),
        "aris.desktop_window": n("창 다루기", "Window"),
        "aris.desktop_app": n("앱 다루기", "App"),
        "aris.desktop_drag": n("앱에서 끌어 놓음", "Dragged in an app"),
        "aris.desktop_click_at": n("앱 화면을 보고 누름", "Clicked on an app's screen"),
        "aris.desktop_dialog_click": n("대화상자에서 누름", "Clicked in a dialog"),
        "aris.desktop_dialog_input": n("대화상자에 입력", "Typed into a dialog"),
        "aris.desktop_menu": n("메뉴 선택", "Menu item chosen"),
        "aris.desktop_scroll": n("스크롤", "Scrolled"),
        // Core 2's own (ArisCapabilityCore2).
        "shell.run": n("명령 실행", "Command run"),
        "file.read": n("파일 읽기", "File read"),
        "file.write": n("파일 저장", "File written"),
        "file.edit": n("파일 고침", "File edited"),
        "file.search": n("파일 찾기", "Files searched"),
        "web.fetch": n("웹 페이지 읽기", "Web page read"),
        "web.search": n("웹 검색", "Web searched"),
        // The coding sessions (ArisFleetCapabilities).
        "fleet.list": n("코딩 세션 보기", "Coding sessions read"),
        "fleet.status": n("코딩 세션 상태 보기", "Coding session status"),
        "fleet.say": n("코딩 세션에 지시", "Told a coding session"),
        "fleet.interrupt": n("코딩 세션 멈춤", "Coding session interrupted"),
        "fleet.answer": n("코딩 세션에 답함", "Answered a coding session"),
        "fleet.start": n("코딩 세션 시작", "Coding session started"),
        "fleet.stop": n("코딩 세션 끝냄", "Coding session stopped"),
        // The record itself.
        "record.query": n("기록 보기", "Record read"),
        "taught.run": n("배운 대로 하기", "Saved steps run"),
        "record.undo": n("되돌림", "Undone"),
        "record.undo_last": n("되돌림", "Undone"),
        // The app layer (ArisApps.Specs).
        "app.alias": n("앱 별명", "App nickname"),
        "app.click": n("앱에서 누름", "Clicked in an app"),
        "app.commands": n("앱 메뉴 보기", "App commands read"),
        "app.do": n("앱 명령 실행", "App command"),
        "app.find": n("앱 찾기", "App found"),
        "app.focus": n("앱 앞으로", "App brought forward"),
        "app.frontmost": n("앞의 앱 보기", "Front app read"),
        "app.hide": n("앱 숨김", "App hidden"),
        "app.open": n("앱 열기", "App opened"),
        "app.press": n("앱에서 키 누름", "Keys pressed in an app"),
        "app.quit": n("앱 종료", "App quit"),
        "app.read": n("앱 내용 읽기", "App read"),
        "app.recipe": n("앱 작업 순서", "App steps"),
        "app.running": n("실행 중인 앱 보기", "Running apps read"),
        "app.scroll": n("스크롤", "Scrolled"),
        "app.select": n("앱에서 고름", "Chosen in an app"),
        "app.type": n("앱에 입력", "Typed into an app"),
        "window.close": n("창 닫음", "Window closed"),
        "window.list": n("창 보기", "Windows read"),
        "window.minimize": n("창 내림", "Window minimized"),
        "window.move": n("창 옮김", "Window moved"),
        "window.resize": n("창 크기 바꿈", "Window resized"),
        "window.space": n("창 공간 옮김", "Window moved to a space"),
        "window.tile": n("창 배치", "Windows arranged"),
        // The app layer's intents.
        "browser.open": n("웹 페이지 열기", "Web page opened"),
        "browser.search": n("웹 검색", "Web searched"),
        "event.create": n("일정 추가", "Event added"),
        "file.open": n("파일 열기", "File opened"),
        "mail.compose": n("메일 초안", "Mail drafted"),
        "mail.send": n("메일 보냄", "Mail sent"),
        "message.send": n("메시지 보냄", "Message sent"),
        "music.play": n("음악 재생", "Music played"),
        "note.create": n("메모 저장", "Note saved"),
        "reminder.create": n("미리 알림 추가", "Reminder added"),
        "settings.change": n("설정 바꿈", "Setting changed"),
    ]

    /// app.type when it replaced what the field held (its undo puts the erased text back): said as a replace, never as
    /// typing (eighth VM run, item 6: the undo card of a replace said "Typed into an app: TextEdit").
    static let replacedText = n("앱의 글 바꿈", "Replaced text in an app")

    /// app.open by what it opened (eleventh VM run, item 10: "다운로드 폴더 열어 줘" was listed as "앱 열기").
    static let openedFolder = n("폴더 열기", "Folder opened")
    static let openedFile = n("파일 열기", "File opened")
    static let openedPage = n("웹 페이지 열기", "Web page opened")

    static func name(_ capability: String) -> Name? { table[capability.lowercased()] }

    /// The owner's name of a capability; one no row names yet says what kind of thing it did, never its id.
    static func shown(_ capability: String, effect: ArisEffectClass) -> Name {
        if let known = name(capability) { return known }
        switch effect {
        case .outward: return n("보냄", "Sent")
        case .changePermanent: return n("지움", "Removed")
        case .changeReversible: return n("바꿈", "Changed")
        case .observe: return n("봄", "Looked")
        case .never: return n("하지 않음", "Not done")
        }
    }

    /// Every name once, the longest Korean first (a longer name is never read as a shorter one's start).
    private static let byLength: [Name] = Set(table.values).union([replacedText, openedFolder, openedFile, openedPage]).sorted { ($1.korean.count, $0.korean, $0.english) < ($0.korean.count, $1.korean, $1.english) }

    /// A line made of a Korean name ("앱에서 여러 단계: TextEdit", "앱 열기") in English; nil when it is no name's.
    static func english(_ line: String) -> String? {
        for name in byLength {
            if line == name.korean { return name.english }
            if line.hasPrefix(name.korean + ": ") { return name.english + ": " + line.dropFirst(name.korean.count + 2) }
        }
        return nil
    }
}

