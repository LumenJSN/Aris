//
//  ArisMemoryImportRowDetail.swift
//  Aris
//
//  설정 › 기억 › 다른 AI에서 가져오기: what a preview row must say besides its line, so the user sees what they is agreeing to
//  before he ticks it (security review 8, H2 and M3): exactly what will be stored when that differs from the line (an
//  item longer than a memory may be keeps a short title), and, for a line that replaces one of his memories, the
//  wording it replaces. The agent sends both with each line (ArisImportRow.stored, .replaces), and the sheet shows
//  them as they came. Also how much of a paste the box keeps. Foundation only (tested).
//

import Foundation

enum ArisMemoryImportRowDetail {
    /// What a row adds under its line; nil fields are not shown.
    struct Extra: Equatable {
        var stored: String?
        var replaces: String?
    }

    /// The row's extra lines: exactly what the agent sent with the line (what is stored when it differs, the wording
    /// it replaces); nothing is worked out here.
    static func extra(_ row: ArisImportRow) -> Extra {
        let stored = row.stored.flatMap { $0.isEmpty || $0 == row.text ? nil : $0 }
        return Extra(stored: stored, replaces: row.replaces.flatMap { $0.isEmpty ? nil : $0 })
    }

    /// The paste box keeps at most what a preview reads (ArisMemoryImportBoard.mostPaste): cut as it is typed or
    /// pasted, once per change, never on every redraw.
    static func kept(_ text: String, most: Int = ArisMemoryImportBoard.mostPaste) -> String {
        // Walks at most `most` characters, however long the paste is.
        guard let end = text.index(text.startIndex, offsetBy: most, limitedBy: text.endIndex), end < text.endIndex else { return text }
        return String(text[..<end])
    }

    /// Whether the paste has anything in it but spaces: stops at the first letter, so a long paste costs nothing.
    static func hasWords(_ text: String) -> Bool { text.contains { !$0.isWhitespace } }
}
