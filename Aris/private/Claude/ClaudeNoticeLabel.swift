//
//  ClaudeNoticeLabel.swift
//  Aris
//
//  The words of a Claude Code session's done/error/limit notice on the notice pill (ArisNoticeRoute.claude): its title
//  is one line that never wraps, so a long session name is cut in the middle to keep it inside the pill: its start and
//  its end both say which folder it is. Its body is the session's last message, or a plain line when it left none.
//

import Foundation

enum ClaudeNoticeLabel {
    /// A session name at most this wide (a Korean letter counts 2, ArisTeammateName.width). With " · 끝났어요" the
    /// title stays inside the pill's line.
    static let nameLimit = 32

    static func text(for peek: ClaudePeek, english: Bool = ArisUIWords.english) -> String {
        switch peek.kind {
        case .done: return ArisUIWords.text("\(shortened(peek.detail)) · 끝났어요", "\(shortened(peek.detail)) · done", english: english)
        case .error: return ArisUIWords.text("\(shortened(peek.detail)) · 오류가 났어요", "\(shortened(peek.detail)) · hit an error", english: english)
        case .limit: return "Claude · \(peek.detail) \(peek.title)"
        }
    }

    /// The session's last message, or what happened in a plain line.
    static func body(for peek: ClaudePeek, english: Bool = ArisUIWords.english) -> String {
        if let message = peek.message?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty { return message }
        switch peek.kind {
        case .done: return ArisUIWords.text("작업을 마쳤어요.", "The job is done.", english: english)
        case .error: return ArisUIWords.text("작업 중에 오류가 났어요.", "The job hit an error.", english: english)
        case .limit: return ArisUIWords.text("한도가 얼마 안 남았어요.", "The limit is nearly used up.", english: english)
        }
    }

    /// `name` when it fits; else its start, "…" and its end, at most `limit` wide.
    static func shortened(_ name: String, limit: Int = nameLimit) -> String {
        guard ArisTeammateName.width(name) > limit else { return name }
        let room = limit - 1
        let head = take(Array(name), room - room / 2)
        let tail = take(Array(name.reversed()), room / 2).reversed()
        return String(head) + "…" + String(tail)
    }

    /// Letters from the front until `width` is used up.
    private static func take(_ letters: [Character], _ width: Int) -> [Character] {
        var used = 0
        return Array(letters.prefix { letter in
            used += ArisTeammateName.width(String(letter))
            return used <= width
        })
    }
}
