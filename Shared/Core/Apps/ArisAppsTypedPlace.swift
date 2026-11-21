//
//  ArisAppsTypedPlace.swift
//  Shared/Core/Apps
//
//  Where app.type's text landed, said in its result (tenth VM run, item 11: "줄 하나 더 넣어 줘 ‘우유’로" typed "우유"
//  right after "첫 줄" on the same line, the result said only "typed 2 characters", and the model told the owner it had
//  added a line). From the field's value read before the typing and read back after it: the added run is on a line of
//  its own, or on a line with text that was there. The result says which, and when the field wasn't read back it says
//  that; the Mind's instructions (`rule`) hold the model to what the result says. Pure.
//

import Foundation

extension ArisApps {
    enum TypedPlace {
        enum Place: Equatable, Sendable {
            /// Nothing else is on its line (or lines).
            case ownLine
            /// It shares a line with text that was there; `after`: that line's text before it ("" when it went in before
            /// the text).
            case sameLine(after: String)
        }

        /// The longest a line that was there is quoted.
        static let quoted = 40

        /// Nil when it can't be told: nothing was added, or something that was there is gone.
        static func place(before: String, after: String) -> Place? {
            guard let added = TextUndo.insertion(before: before, after: after) else { return nil }
            let units = Array(before.utf16)
            let head = String(decoding: units[..<min(added.location, units.count)], as: UTF16.self)
            let tail = String(decoding: units[min(added.location, units.count)...], as: UTF16.self)
            let startsLine = head.isEmpty || head.last?.isNewline == true || added.text.first?.isNewline == true
            let endsLine = tail.isEmpty || tail.first?.isNewline == true || added.text.last?.isNewline == true
            if startsLine && endsLine { return .ownLine }
            guard !startsLine else { return .sameLine(after: "") }
            let line = head.split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
            return .sameLine(after: line.trimmingCharacters(in: .whitespaces))
        }

        /// The place as the result's words.
        static func note(before: String, after: String) -> String? {
            switch place(before: before, after: after) {
            case nil: return nil
            case .ownLine?: return "it is on a line of its own"
            case .sameLine(let line)?:
                guard !line.isEmpty else { return "it went on the same line as text that was there (no new line was started)" }
                let shown = line.count > quoted ? "…" + String(line.suffix(quoted - 1)) : line
                return "it went on the same line, right after “\(shown)” (no new line was started)"
            }
        }

        /// What a typing that wasn't read back says.
        static let unread = "where it landed wasn't read back"

        /// The Mind's rule for speaking about a typing.
        static let rule = """
        A typing's result says where the text landed. Tell the owner only that: when it says the text went on the same \
        line, never say a new line was added (say it went on the same line, and offer to put it on a new one); when it \
        says it wasn't read back, say the text was typed and that you couldn't check where.
        """
    }
}
