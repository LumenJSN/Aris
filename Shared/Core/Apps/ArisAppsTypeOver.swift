//
//  ArisAppsTypeOver.swift
//  Shared/Core/Apps
//
//  Typing goes over whatever is selected where it lands. A taught replay's typing (never a replace, which has its own
//  card) is decided by the trust gate from the field's selection as read at the decision (ArisTrustGate.peekSelection):
//  nothing selected and it runs as any text put in; anything else and it asks on a card that shows what is erased.
//  Between that read and the typing the selection can change (a card waits for the owner, the app itself, his own
//  hand), and a decision stands only for the content it saw. So the replay marks its call with what the decision saw
//  (`selection`: nothing, exactly this text, or "couldn't be read" when he said yes to a card that said so), and
//  app.type, which reads the field again right before it types, types nothing when what it reads is not that.
//  A replace is marked the same way with the text its card showed as erased, and sets nothing when the field holds
//  anything else by then. A call with no mark is as it was; the mark can only ever stop the typing. Pure.
//

import Foundation

extension ArisApps {
    enum TypeOver {
        static let argument = "selection"
        /// The decision saw nothing selected.
        static let empty = "empty"
        /// The owner said yes to a card that said the selection couldn't be read.
        static let any = "any"
        /// The owner said yes to a card that showed exactly this selected text (its print follows).
        static let seen = "is:"

        /// The mark for a call whose decision saw `erases` (nil: nothing selected).
        static func mark(erases: ArisErasedText?) -> String {
            guard let erases else { return empty }
            return erases.text.map { seen + print($0) } ?? any
        }

        /// Whether app.type types nothing: the call is marked, and `selected` (the field's selected text as read right
        /// before typing; nil when it can't be read) is not what its decision saw.
        static func refuses(_ arguments: JSON, selected: String?) -> Bool {
            guard let mark = arguments[argument]?.string else { return false }
            if mark == any { return false }
            if mark == empty { return selected != "" }
            guard mark.hasPrefix(seen), let selected, !selected.isEmpty else { return true }
            return mark != seen + print(selected)
        }

        /// Whether a marked replace sets nothing: `holds` (the field's whole text as read right before it is replaced;
        /// nil when it can't be read) is not the text its card showed as erased. `empty`: only an empty field.
        static func refusesReplace(_ arguments: JSON, holds: String?) -> Bool {
            guard let mark = arguments[argument]?.string else { return false }
            if mark == any { return false }
            if mark == empty { return holds != "" }
            guard mark.hasPrefix(seen), let holds else { return true }
            return mark != seen + print(holds)
        }

        /// Whether a marked call stops because its card couldn't show what it erases and there is something now (eleventh
        /// VM run, C3: Allow on "지워질 글을 미리 읽지 못했어요" overwrote text the owner never saw): the mark is `any`
        /// and `now` (the field's whole text for a replace, its selected text for typing; nil when it still can't be
        /// read) is read and not empty. Nothing is typed; the call is to be made again, so its card shows that text.
        static func unseen(_ arguments: JSON, now: String?) -> Bool {
            guard arguments[argument]?.string == any, let now else { return false }
            return !now.isEmpty
        }

        /// What is said when a call was stopped for text its card never showed. Read by the AI, or said as a step's failure.
        static let unseenRefusal = "the field holds text the card couldn't show when it asked: nothing was typed or replaced. "
            + "Make the same call again now: its card will show the owner the text that would be erased"

        /// What is said when a replace has no text field it can read and set: it never falls back to typing at the caret.
        static let noFieldRefusal = "no text field to replace could be found and read in the window: nothing was typed. "
            + "Read the app (app.read, part \"controls\") and name the field by its id or exact name"

        /// What the owner is told when a replace was stopped.
        static let replaceRefusal = "what the field holds changed since this step was checked: nothing was replaced"

        /// What the owner is told when the typing was stopped.
        static let refusal = "the selection changed since this step was checked: nothing was typed"

        /// FNV-1a over the text, with its length.
        static func print(_ text: String) -> String {
            var value: UInt64 = 0xcbf2_9ce4_8422_2325
            for byte in text.utf8 { value = (value ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
            return "\(text.utf16.count)-" + String(value, radix: 16)
        }
    }
}
