//
//  ArisAnswerDocument.swift
//  Aris
//
//  The owner's pick A, "깔끔한 문서" (mockups/answer-format.html): the open notch's answer as the pieces it
//  draws. The first line is the lead (the conclusion, 16/24 at 600); everything after it is ArisBoardContent's blocks
//  (labels, tables, bullets, checklists). While an answer streams only the last piece grows, so pieces already on screen
//  never change. Each piece rises in on ArisRevealClock's stagger. Pure, so the tests check it.
//

import CoreGraphics
import Foundation

enum ArisAnswerDocument {
    enum Piece: Equatable {
        case lead(String)
        case block(ArisBoardContent.Block)
    }

    /// A first line longer than this is a paragraph: a brain that ignored the shape doesn't get a bold wall.
    static let leadLimit = 120

    static func pieces(from answer: String) -> [Piece] {
        let lines = answer.components(separatedBy: .newlines)
        guard let first = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return [] }
        let line = lines[first].trimmingCharacters(in: .whitespaces)
        let rest = lines[(first + 1)...].joined(separator: "\n")
        guard line.count <= leadLimit, ArisBoardContent.blocks(from: line) == [.paragraph(line)] else {
            return ArisBoardContent.blocks(from: answer).map(Piece.block)
        }
        return [.lead(line)] + ArisBoardContent.blocks(from: rest).map(Piece.block)
    }

    /// An answer that is one plain line or paragraph: no heading, list or table, and no inline marks. Beside a card it
    /// keeps the card's own line (pick B: the line, then the card); an answer with more to it is drawn as every other
    /// answer is, so its headings, tables and lists are never shown as their raw marks.
    static func isPlainLine(_ answer: String) -> Bool {
        let pieces = pieces(from: answer)
        guard pieces.count == 1, !["**", "`", "](", "~~"].contains(where: answer.contains) else { return false }
        switch pieces[0] {
        case .lead, .block(.paragraph): return true
        case .block: return false
        }
    }

    /// The button that fixes a failure shows under every reply that is up, with a card or without: only a card's
    /// words left up after its answer, and the permission card (whose own button is that same fix), go without.
    static func showsFix(settledCard: Bool, permissionCard: Bool) -> Bool { !settledCard && !permissionCard }

    /// A section's body rises together with its label (the mockup reveals label and table as one).
    static func joinsPrevious(_ piece: Piece, after previous: Piece?) -> Bool {
        guard case .block(.label) = previous else { return false }
        if case .block(.label) = piece { return false }
        return true
    }
}

/// When each piece starts rising: 120 ms after the first, then 90 ms apart, so an answer that arrives whole rises in
/// order; a piece that streams in later rises at once, but never sooner than 90 ms after the one before it.
struct ArisRevealClock {
    static let duration: TimeInterval = 0.42
    static let step: TimeInterval = 0.09
    static let leadIn: TimeInterval = 0.12
    /// Points the piece rises from.
    static let rise: CGFloat = 6
    static let blur: CGFloat = 3
    /// The mockup's (.22, .61, .36, 1).
    static let curve: [Double] = [0.22, 0.61, 0.36, 1]

    private(set) var last: TimeInterval?

    mutating func start(now: TimeInterval, joinsPrevious: Bool) -> TimeInterval {
        let next = last.map { joinsPrevious ? max(now, $0) : max(now, $0 + Self.step) } ?? now + Self.leadIn
        last = next
        return next
    }
}
