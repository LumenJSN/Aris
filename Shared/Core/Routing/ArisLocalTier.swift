//
//  ArisLocalTier.swift
//  Aris (Shared/Core)
//
//  How much work a request is when the router can't say (no router key, or it didn't answer in time): read from the
//  request itself. A request that has to look things up (ArisThinking's look-up words), points at the screen or at
//  files, or is long, is work; a plain question or one command is quick. Before, every turn without the key was quick,
//  so a report or a long writing request ran at the lowest effort. Fits ArisThinking's effort table: quick is low,
//  work is medium, and the helper still makes a look-up turn deep. Foundation only (swift test).
//

import Foundation

enum ArisLocalTier {
    /// Words that name files or documents to work on.
    private static let files = #"(?i)파일|문서|폴더|첨부|\.(?:pdf|docx?|xlsx?|pptx?|txt|md|csv|key|pages|numbers)\b|\b(?:file|files|document|documents|folder|attachment|pdf|spreadsheet)\b"#
    /// From this long on (letters and digits, spaces left out) a request is work: several asks, or a piece to write.
    static let longRequest = 45
    /// Or this many words.
    static let manyWords = 12

    /// Whether the request is work (`true`) or quick. `looksUp`: ArisThinking's look-up words; `pointsAtScreen`: the
    /// words point at the screen or the clipboard (ArisDeixis).
    static func isWork(_ words: String, looksUp: Bool, pointsAtScreen: Bool) -> Bool {
        if looksUp || pointsAtScreen { return true }
        if words.range(of: files, options: .regularExpression) != nil { return true }
        let letters = words.filter { $0.isLetter || $0.isNumber }.count
        let count = words.split(whereSeparator: \.isWhitespace).count
        return letters >= longRequest || count >= manyWords
    }
}
