//
//  ArisDesktopErase.swift
//  aris-agent
//
//  What a desktop action erases (thirteenth VM run, 1.3.0's promise "erasing, replacing or typing over a selection always
//  shows a card with the text, and the change can be undone"): on the default path a type over "banana" showed only
//  "Text to type: 바뀐 글", and "select all" then "type" went up as two harmless-looking cards that never named the text
//  they wiped. A type into a field with a selection, a delete over one, and a select-all followed by a type or a delete
//  in the same window are one replace: the text that goes is read when the action is decided, shown on its card, and
//  the action is held to it (the field holds anything else by then: nothing is done). A selection that can't be read is
//  treated as one that holds something (a miss is never less strict than a hit). Pure.
//

import Foundation

struct ArisDesktopErase: Equatable {
    /// What goes: the field's selection, or everything it holds (a select-all comes first).
    enum Scope: Equatable { case selection, whole }

    /// What was read of it when the action was decided.
    enum Seen: Equatable {
        case nothing
        case text(String)
        case unread
    }

    let scope: Scope
    let seen: Seen

    /// The action takes text away (or may: unreadable): it is a replace, asked on its own card every time.
    var replaces: Bool { seen != .nothing }

    /// It surely takes text away: everything, or a selection that was read. (A selection that couldn't be read may be
    /// nothing: setting the field to what it held plus the text keeps it, so that fallback stays open.)
    var erasesText: Bool {
        guard replaces else { return false }
        if scope == .whole { return true }
        if case .text = seen { return true }
        return false
    }

    /// The field's selected text as read (UTF-16 range over its raw value); unread when the field tells neither in full.
    static func selection(of field: ArisDesktopElement?) -> Seen {
        guard let field, let range = field.selectedRange else { return .unread }
        // A bare caret erases nothing, whatever the field holds.
        guard range.length > 0 else { return .nothing }
        guard let raw = field.rawValue, !field.rawCapped else { return .unread }
        let text = raw as NSString
        guard range.location >= 0, range.location + range.length <= text.length else { return .unread }
        return .text(text.substring(with: NSRange(location: range.location, length: range.length)))
    }

    /// Everything the field holds, as read; unread when it doesn't give it in full.
    static func whole(of field: ArisDesktopElement?) -> Seen {
        guard let field, let raw = field.rawValue, !field.rawCapped else { return .unread }
        return raw.isEmpty ? .nothing : .text(raw)
    }

    /// What this erase reads in `field` now.
    func now(_ field: ArisDesktopElement?) -> Seen { scope == .whole ? Self.whole(of: field) : Self.selection(of: field) }

    /// Whether the action may go on with `now` read right before it: exactly what was shown (nothing, or the same
    /// text); after a card that couldn't read it, only while it still reads as nothing or unreadable (text there now was
    /// never shown: the call is made again so its card shows it).
    static func holds(card: Seen, now: Seen) -> Bool {
        switch card {
        case .nothing: return now == .nothing
        case .text: return now == card
        case .unread: if case .text = now { return false } else { return true }
        }
    }

    // MARK: - Words

    /// The card's title verb ("TextEdit에서 글 바꾸기" / "Replace text in TextEdit"): a type replaces, a delete erases.
    static func verb(typing: Bool, english: Bool) -> String {
        typing ? (english ? "Replace text" : "글 바꾸기") : (english ? "Erase text" : "글 지우기")
    }

    /// The lines first on the card: what goes, whole (the card wraps; its full text is kept when long).
    func cardLines(typing: Bool, english: Bool) -> [String] {
        let say = { (korean: String, inEnglish: String) in english ? inEnglish : korean }
        let lead: String
        switch (scope, typing) {
        case (.whole, true): lead = say("⚠️ 이 창의 글을 모두 지우고 그 자리에 입력해요", "⚠️ This erases all the text in this window and types in its place")
        case (.whole, false): lead = say("⚠️ 이 창의 글을 모두 지워요", "⚠️ This erases all the text in this window")
        case (.selection, true): lead = say("⚠️ 선택한 글을 지우고 그 자리에 입력해요", "⚠️ This erases the selected text and types in its place")
        case (.selection, false): lead = say("⚠️ 선택한 글을 지워요", "⚠️ This erases the selected text")
        }
        switch seen {
        case .nothing: return []
        case .text(let text): return [lead, say("지워지는 글:\n", "Text that is erased:\n") + ArisDesktopCard.shown(text)]
        case .unread:
            return [lead, say("지워질 글을 미리 읽지 못했어요. 그 사이 글이 보이면 하지 않고 다시 물어봐요",
                              "The text that would be erased couldn't be read first. If text shows there by then, nothing is done and Aris asks again")]
        }
    }

    /// What the brain reads when the field changed since the card: nothing was done.
    static let changedLine = "NOT DONE: what the field holds (or has selected) changed since the user's card showed the text that would be erased, " +
        "so nothing was typed or deleted. Make the same call again now: its card will show the text as it is."

    /// What the brain reads for a lone select-all in a turn whose words ask to erase or replace: nothing was pressed.
    static func deferredLine(app: String) -> String {
        "Nothing was pressed yet (this is not done): a select-all is done together with what replaces it, on one card that shows the user " +
            "the text that is erased. Now make the replacing call in \(app)'s same window: `desktop type <ref of the text field> --stdin` with the new " +
            "text, or `desktop press delete --app \"\(app)\"` if the user only asked to erase. That call selects everything first. Don't say anything " +
            "was selected or erased before its result says so."
    }
}
