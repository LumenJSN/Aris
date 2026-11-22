//
//  ArisUndoKind.swift
//  Shared/Core (aris-agent, tests)
//
//  What kind of change an undo is about (thirteenth VM run, item 1: "방금 이름 바꾼 거 되돌려 줘" undid an older typed line
//  instead of the rename, with no card). The owner's words of the turn name a kind ("이름 바꾼 거", "휴지통에 버린 거",
//  "입력한 글", "일정", "창"), or none ("방금 거 되돌려"); each record entry is of one kind, by its capability and its undo,
//  from an allowlist (anything else is of no named kind, so it is never taken for one he named). Pure.
//

import Foundation

enum ArisUndoKind: String, Equatable, Sendable, CaseIterable {
    case rename, trash, typing, event, window, move

    /// The Korean words a card or a reply names the kind with.
    var korean: String {
        switch self {
        case .rename: "이름 바꾼 것"
        case .trash: "휴지통에 넣은 것"
        case .typing: "입력한 글"
        case .event: "일정"
        case .window: "창 옮긴 것"
        case .move: "파일 옮긴 것"
        }
    }

    /// The patterns that name each kind, checked in this order (a window moved is a window, never a file move).
    private static let patterns: [(ArisUndoKind, String)] = [
        (.window, #"(?:^|[\s,])(?:창|윈도우)(?:을|를|이|가|\s|$)|\bwindows?\b"#),
        (.rename, #"이름\s*(?:을|를)?\s*(?:바꾼|바꿨|바꾼\s*거|변경|고친)|\brenam(?:e|ed|ing)\b"#),
        (.trash, #"휴지통|버린|버렸|\btrash(?:ed)?\b|\bbinned\b"#),
        (.event, #"일정|이벤트|캘린더|\bevents?\b|\bcalendar\b|\bappointments?\b"#),
        (.typing, #"입력|타이핑|쓴\s*(?:글|거|것|줄)|적은|넣은\s*(?:글|줄|말)|글자|\btyped\b|\btyping\b|\btext\b"#),
        (.move, #"옮긴|옮겼|이동|\bmoved?\b"#),
    ]

    /// The kind the owner's words name; nil when they name none (then the newest change is meant).
    static func named(in words: String) -> ArisUndoKind? {
        let text = words.precomposedStringWithCanonicalMapping.lowercased()
        return patterns.first { text.range(of: $0.1, options: .regularExpression) != nil }?.0
    }

    /// The kind of change an entry is, by its capability and its undo (an allowlist); nil when it is of none.
    static func of(_ entry: ArisRecordEntry) -> ArisUndoKind? {
        let capability = entry.capability ?? ""
        switch capability {
        case "aris.file_rename": return .rename
        case "aris.file_trash": return .trash
        case "aris.file_move": return .move
        case "aris.add_event": return .event
        case "app.type": return .typing
        default: break
        }
        if capability.hasPrefix("window.") { return .window }
        switch entry.undo {
        case .fileTrashed?: return .trash
        case .textInserted?: return .typing
        case .windowMoved?: return .window
        case .itemCreated(let kind, _)? where kind == "calendar": return .event
        default: return nil
        }
    }
}
