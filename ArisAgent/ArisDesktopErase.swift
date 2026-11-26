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

    /// His words give the text that goes in the erased text's place ("'교체된 내용'이라고 써 줘", "…로 바꿔 줘", "write
    /// 'replaced content'", "replace it with …"), not only erasing. A miss leaves `cmd+a delete` its own erase card.
    static func writesNewText(_ request: String) -> Bool {
        let korean = #"(써\s*줘|써\s*주|쓰고|적어|입력해|입력하|넣어|넣고|(이)?라고|(으)?로\s*바꿔|(으)?로\s*바꾸|(으)?로\s*교체)"#
        let english = #"(?i)(\b(write|type|put|enter|insert)\b|\breplace\b.*\bwith\b)"#
        return request.range(of: korean, options: .regularExpression) != nil || request.range(of: english, options: .regularExpression) != nil
    }

    /// What the brain reads for a type on a bare caret when their words replace only a part of the text ("이거 '체리'로
    /// 바꿔 줘"): nothing typed, never a replace of everything (fifteenth VM run, follow-up).
    static let partialAtCaretLine = "NOT TYPED: the user asked to replace part of the text, but nothing is selected in that field (only the " +
        "caret), so typing would add the text instead of replacing anything. Nothing was typed or erased. " + selectFirstAdvice

    /// What the brain is told to do instead of replacing a part it hasn't selected.
    static let selectFirstAdvice = "Select exactly the text to replace " +
        "first (for one word: `desktop click <ref of the word> --double`), then type; if it isn't clear which text is meant, ask the user."

    /// What the brain reads for a set-value that would drop most of what a document holds when their words didn't ask for
    /// all of it to go (sixteenth VM run, R2k: "이거 '체리'로 바꿔 줘" set the whole TextEdit document to "체리").
    static let partialSetValueLine = "NOT DONE: set-value replaces everything the field holds, and this value would drop most of its text, " +
        "but the user didn't ask for all of it to go. Nothing was changed. To add text, `desktop type` at the caret instead. To change a part: " +
        selectFirstAdvice

    /// A set-value (the field's whole value) keeps less than half of what the field held: by its words (each kept as
    /// often as it was there, wherever it moved), or by the text it keeps unchanged at its start and end (for text with
    /// no spaces). Empty text drops nothing.
    static func dropsMost(was old: String, now new: String) -> Bool {
        guard !old.isEmpty else { return false }
        let words = { (text: String) in text.split(whereSeparator: { $0.isWhitespace }).map(String.init) }
        let oldWords = words(old)
        var left = Dictionary(words(new).map { ($0, 1) }, uniquingKeysWith: +)
        var kept = 0
        for word in oldWords where (left[word] ?? 0) > 0 {
            left[word]! -= 1
            kept += 1
        }
        let byWords = oldWords.isEmpty ? 0 : Double(kept) / Double(oldWords.count)
        let was = Array(old), now = Array(new)
        var start = 0
        while start < min(was.count, now.count), was[start] == now[start] { start += 1 }
        var end = 0
        while end < min(was.count, now.count) - start, was[was.count - 1 - end] == now[now.count - 1 - end] { end += 1 }
        let byEnds = Double(start + end) / Double(was.count)
        return max(byWords, byEnds) < 0.5
    }

    /// The fields a set-value that drops most of the text is refused in: a document's text area, or any field that holds
    /// more than one line. A one-line field (a name, an amount) is set whole by its nature, on the replace card.
    static func guardsPart(_ field: ArisDesktopElement, holding text: String) -> Bool {
        ArisDesktopVerify.isTextArea(field) || text.contains(where: \.isNewline)
    }

    /// What the brain reads when the field changed since the card: nothing was done.
    /// Nothing more acts in the turn after it (fourteenth VM run, R1c: "Make the same call again now" put the change on a
    /// new card at once, and the reply said the document was emptied when nothing was erased).
    static let changedLine = "NOT DONE: what the field holds (or has selected) changed after the user's card showed the text that would be erased, " +
        "so nothing was typed or deleted: nothing in it changed. This request stops here: make no other change in this turn. " +
        "Tell the user exactly that nothing was changed, and ask whether to try again with the text as it is now."

    /// What the brain reads for any acting call after that in the same turn: not run.
    static let afterChangedLine = "Not run: earlier in this turn the field changed after the user's card, so nothing was replaced, and nothing more is " +
        "done for this request now. Tell the user nothing was changed and ask whether to try again with the text as it is now; never put the " +
        "change on a new card in this turn."

    /// A gate's reason for a card-asking call after that in the same turn (any brain's shell gate): not asked, not run.
    static let gateStopLine = "the field changed after the owner's card this turn and nothing was replaced, so nothing more that asks runs now; " +
        "tell him nothing was changed and ask whether to try again with the text as it is now"

    // MARK: - A replace of everything, checked (seventeenth VM run, R1k)

    /// The field's selection covers everything it holds (the select-all took), as Accessibility reads it; nil when the
    /// field tells neither its selection nor its whole value (the typing is then checked after: replacedWhole).
    static func coversAll(_ field: ArisDesktopElement) -> Bool? {
        guard let range = field.selectedRange, let raw = field.rawValue, !field.rawCapped else { return nil }
        return range.location == 0 && range.length == raw.utf16.count
    }

    /// The field holds exactly the new text now (both composed, the outer spaces and line breaks left out).
    static func replacedWhole(_ value: String, with text: String) -> Bool {
        let tidy = { (text: String) in text.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping }
        return tidy(value) == tidy(text)
    }

    /// What the brain reads when the select-all didn't take with the window in front either: nothing typed.
    static let selectMissedLine = "Selecting all of the text to replace didn't take, even with the window in front (the field still had " +
        "only part of it selected), so nothing was typed and nothing in it changed. Don't type it again: tell the user plainly that the " +
        "text wasn't replaced, and ask whether to try again."

    /// How a replace of everything that didn't replace begins: the brain can't call it done.
    static let notReplacedLead = "NOT REPLACED:"

    /// What the brain reads when the new text went in beside the old instead of over it (R1k): taken back, or not.
    static func notReplacedLine(restored: Bool, why: String?) -> String {
        let lead = notReplacedLead + " the new text went in next to the text that was there instead of replacing it (selecting all of it didn't take). "
        if restored {
            return lead + "Aris took it out again, so the field reads as it did before and nothing in it changed. Don't type it again in this turn: " +
                "tell the user plainly that the text wasn't replaced and nothing changed, and ask whether to try again."
        }
        return lead + "Aris couldn't take it out again (\(why ?? "the field didn't read as it did")), so the field now holds the old text and the new " +
            "text together. Don't type it again: tell the user plainly that the text wasn't replaced and the new text was added to what was " +
            "there, and that they can ask Aris to undo it."
    }

    // MARK: - An erase of everything, checked the same way (fix132d)

    /// A press that erases everything, split at its select-all: the keys after it (the delete), which go only once all of
    /// the field reads as selected. Nil when the press doesn't start with a select-all and then delete (pressed as it is).
    static func afterSelectAll(_ keys: [String]) -> [String]? {
        let rest = Array(keys.drop(while: ArisDesktopBatch.isSelectAll))
        guard rest.count < keys.count, !rest.isEmpty, !rest.contains(where: ArisDesktopBatch.isSelectAll) else { return nil }
        return rest
    }

    /// What the brain reads when the select-all didn't take with the window in front either: nothing deleted.
    static let eraseSelectMissedLine = "Selecting all of the text to erase didn't take, even with the window in front (the field still had " +
        "only part of it selected), so nothing was deleted and nothing in it changed. Don't press it again: tell the user plainly that the " +
        "text wasn't erased, and ask whether to try again."

    /// How an erase of everything that didn't empty the field begins: the brain can't call it done.
    static let notErasedLead = "NOT ERASED:"

    /// What the brain reads when the delete left text in the field: put back as it was, or not.
    static func notErasedLine(restored: Bool, why: String?) -> String {
        let lead = notErasedLead + " the delete didn't erase all of the text (selecting all of it didn't take). "
        if restored {
            return lead + "The field reads as it did before (Aris put back anything the delete took), so nothing in it changed. Don't press it " +
                "again in this turn: tell the user plainly that the text wasn't erased and nothing changed, and ask whether to try again."
        }
        return lead + "Aris couldn't put back what the delete took (\(why ?? "the field didn't read as it did")), so part of the text is gone " +
            "and the rest is still there. Don't press it again: tell the user plainly that the text wasn't erased, that some of it was " +
            "deleted, and that they can ask Aris to undo it."
    }

    /// The start of the line for a select-all held back (ArisDesktopEngine.deferredSelectAll): the route counts it as nothing pressed.
    static let heldLead = "Nothing was pressed yet (this is not done)"

    /// What the brain reads for a lone select-all in a turn whose words ask to erase or replace: nothing was pressed.
    static func deferredLine(app: String) -> String {
        heldLead + ": a select-all is done together with what replaces it, on one card that shows the user " +
            "the text that is erased. Now make the replacing call in \(app)'s same window: `desktop type <ref of the text field> --stdin` with the new " +
            "text, or `desktop press delete --app \"\(app)\"` if the user only asked to erase. That call selects everything first. Don't say anything " +
            "was selected or erased before its result says so."
    }
}
