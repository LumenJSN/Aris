//
//  ClaudeNoticeLabel.swift
//  Aris
//
//  The words on Claude's done/error/limit tag (ClaudeNoticeView). The tag is one line that never wraps, so a long
//  session name is cut in the middle to keep it inside the 416-point page: its start and its end both say which
//  folder it is.
//

import Foundation

enum ClaudeNoticeLabel {
    /// A session name at most this wide (a Korean letter counts 2, ArisTeammateName.width). With " · 끝났어요", the orb
    /// and the check, the tag stays under the page's 384-point text line at 11.5 points.
    static let nameLimit = 32

    static func text(for peek: ClaudePeek) -> String {
        switch peek.kind {
        case .done: return ArisUIWords.text("\(shortened(peek.detail)) · 끝났어요", "\(shortened(peek.detail)) · done")
        case .error: return ArisUIWords.text("\(shortened(peek.detail)) · 오류가 났어요", "\(shortened(peek.detail)) · hit an error")
        case .limit: return "Claude · \(peek.detail) \(peek.title)"
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
