//
//  ArisAgentStatus.swift
//  aris-agent
//
//  A few words for the notch about what the AI is doing right now ("웹 검색 중"), so a
//  slow answer doesn't look like Aris froze.
//

import Foundation

enum ArisAgentStatus {
    private static let toolWords: [String: String] = [
        "weather": "날씨 보는 중", "remember": "기억하는 중", "forget": "잊는 중", "memory": "기억 찾는 중", "recall": "기억 찾는 중",
        "window": "창 정리 중", "tile": "창 정리 중", "windows": "창 보는 중",
        "music": "음악 다루는 중", "volume": "소리 맞추는 중",
        "app": "앱 여는 중", "new": "앱 여는 중", "link": "링크 여는 중", "folder": "폴더 여는 중", "move": "옮기는 중", "rename": "이름 바꾸는 중",
        "shortcut": "단축어 실행 중", "shortcuts": "단축어 보는 중", "remind": "미리 알림 추가 중",
        "event": "일정 추가 중", "calendars": "캘린더 보는 중", "use-calendar": "캘린더 바꾸는 중", "calendar": "캘린더 여는 중",
        "note": "메모 쓰는 중", "screen": "화면 보는 중", "selection": "선택한 내용 보는 중", "clipboard": "클립보드 보는 중",
        "tab": "브라우저 보는 중", "finder": "Finder 보는 중", "message": "메시지 준비 중", "trash": "휴지통으로 옮기는 중",
        "keys": "키 누르는 중", "type": "입력하는 중", "show": "결과 정리 중", "timer": "타이머 맞추는 중",
        "messages": "메시지 읽는 중", "mail": "메일 보는 중", "notes": "메모 찾는 중", "files": "파일 찾는 중",
        "obsidian": "Obsidian 찾는 중", "maps": "지도 여는 중", "stock": "주가 가져오는 중", "currency": ArisCurrencyRoute.status, "desktop": "앱 다루는 중",
        "aside": ArisAside.workingStatus, "convert": "파일 변환하는 중", "merge": "파일 합치는 중", "split": "PDF 나누는 중", "compress": "용량 줄이는 중",
    ]

    private static let actionWords: [String: String] = [
        "folder new": "폴더 만드는 중", "event find": "일정 찾는 중", "event delete": "일정 지우는 중", "event change": "일정 바꾸는 중",
        "todo add": "할 일 추가 중", "todo done": "할 일 끝내는 중", "todo remove": "할 일 지우는 중", "schedule add": "예약 만드는 중",
        "schedule remove": "예약 취소하는 중", "schedule list": "예약 보는 중", "clipboard set": "클립보드에 넣는 중",
        "routine list": "루틴 보는 중", "routine show": "루틴 보는 중", "routine add": "루틴 만드는 중", "routine remove": "루틴 지우는 중",
        "routine wait": "루틴 보는 중",
        "mail reply": "답장 준비 중",
    ]

    /// A video or sound job that is still going (said every half minute or so), with the minutes so far.
    static func longJob(minutes: Int) -> String {
        minutes < 1 ? "영상·소리 변환하는 중" : "영상·소리 변환하는 중 (\(minutes)분째)"
    }

    /// Whether the long job's "still going" line is sent now. Never while one of the turn's cards waits for its
    /// answer: the job has not started, and a line sent then arrives in the app after a no has dropped the step and
    /// puts it back, so "OK, I won't convert it." came with "Converting video or sound (1 min) ✓" (fourth VM run,
    /// bug 2: a card that waited longer than the first half minute).
    static func beatsLongJob(cardWaiting: Bool) -> Bool { !cardWaiting }

    /// For a shell command the AI runs.
    static func forCommand(_ command: String, tools: String) -> String {
        // A desktop type with its text on stdin (the engine then says which app: "카카오톡에서 입력 중…").
        if ArisDesktopShell.parse(command, tools: tools) != nil { return "앱 다루는 중" }
        guard let words = ArisCommandPolicy.words(command), words.first == tools else { return "명령 실행 중" }
        // `maps … --json` only looks the way up; Maps doesn't open.
        if words.dropFirst().first == "maps", words.contains("--json") { return "길 찾는 중" }
        if let call = ArisConvertWords.parse(Array(words.dropFirst())), ArisConvertWords.isMedia(call) { return longJob(minutes: 0) }
        // The subcommand says what it does (QA: "폴더 여는 중" while a folder was being made).
        let pair = words.dropFirst().prefix(2).joined(separator: " ")
        if let said = actionWords[pair] { return said }
        return words.dropFirst().first.flatMap { toolWords[$0] } ?? "Mac 다루는 중"
    }

    /// The status for a tool that has no words of its own.
    static let anyTool = "도구 쓰는 중"

    /// For one of Claude's tools: its own words, else the plain one. Every tool Claude starts shows a step, so "a
    /// step was shown" is true whenever something ran (security review 6, L3: Write, Edit and others showed none,
    /// and a question lost to the helper right after such a call would have been asked again, the act run twice).
    static func forClaudeTool(_ name: String) -> String { forTool(type: name, server: nil) ?? anyTool }

    /// Before a learned shortcut's commands are run again: the first command's own status (none learned: the plain
    /// one). The same reason: the replay is an act, and the turn must show it before it runs.
    static func forReplay(_ commands: [String], tools: String) -> String {
        commands.first.map { forCommand($0, tools: tools) } ?? anyTool
    }

    /// For any other tool (Codex item types; MCP calls by server). Nil for thinking and talking.
    static func forTool(type: String, server: String?) -> String? {
        switch type {
        case "webSearch", "WebSearch": return "웹 검색 중"
        case "WebFetch": return "웹 페이지 읽는 중"
        case "Read": return "파일 읽는 중"
        case "fileChange": return "파일 고치는 중"
        case "mcpToolCall":
            switch server {
            case "aris_notion": return "Notion 보는 중"
            case "cua_repl": return "화면 다루는 중"
            default: return "도구 쓰는 중"
            }
        default: return nil
        }
    }
}
