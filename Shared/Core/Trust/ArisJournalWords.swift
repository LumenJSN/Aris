//
//  ArisJournalWords.swift
//  Shared/Core/Trust (app, aris-agent, tests)
//
//  A few of the record's result lines in the language the owner reads the app in (eighth VM run, item 6: with the
//  English UI the journal's results stayed Korean, "TextEdit에 입력한 글을 지웠어요", "주인이 거절", and the undo's result
//  dropped the lesson it was part of, which the spoken reply named). One wording for the undo of typed or replaced
//  text, used by the journal's line and by the reply (ArisUndoWords.undidLine). Foundation only.
//

import Foundation

enum ArisJournalWords {
    /// An undo of text Aris put into `app`: typed text removed, or (`restored`) a replace's erased text put back.
    /// `lesson`: the taught procedure whose run it was part of, named when known.
    static func textUndone(app: String, restored: Bool, lesson: String?, english: Bool) -> String {
        if restored {
            if let lesson { return english ? "Put back what was in \(app) before “\(lesson)” replaced it." : "‘\(lesson)’에서 \(app)에 바꿔 넣은 글을 원래 글로 되돌렸어요." }
            return english ? "Put back the text I replaced in \(app)." : "\(app)에 바꿔 넣은 글을 원래 글로 되돌렸어요."
        }
        if let lesson { return english ? "Removed the text I typed in \(app) for “\(lesson)”." : "‘\(lesson)’에서 \(app)에 입력한 글을 지웠어요." }
        return english ? "Removed the text I typed in \(app)." : "\(app)에 입력한 글을 지웠어요."
    }

    /// A call the owner said no to on its card.
    static func declined(english: Bool) -> String { english ? "You said no" : "하지 말라고 하셨어요" }

    /// A call whose card nobody answered in time: never his no (ninth VM run, item 3: the record said "답이 없었어요
    /// (no answer in time)" in the English UI).
    static func unanswered(english: Bool) -> String { english ? "No answer in time" : "답이 없었어요" }

    /// A failed call's result as the record keeps it: the app layer's "did" line (English as it writes it) in the UI's
    /// language where it is one of its known reasons (ArisTeachCopy.knownReasons), the rest of the result as it was
    /// (ninth VM run, item 6: "that menu item isn't there now …" in the Korean record). English, a result that isn't
    /// the app layer's JSON, or a reason with no Korean: unchanged.
    static func failure(_ text: String, english: Bool) -> String {
        guard !english, let data = text.data(using: .utf8), var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let did = object["did"] as? String, ArisTeachCopy.isEnglish(did), let said = ArisTeachCopy.reason(did, english: false) else { return text }
        object["did"] = said
        guard let made = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else { return text }
        return String(decoding: made, as: UTF8.self)
    }

    /// A replace of an app's text, as the 한 일 list and the undo card name it (ArisCapabilityNames.replacedText).
    static func replaced(_ recipe: ArisUndoRecipe?) -> Bool {
        guard case .textInserted(_, let element, _)? = recipe else { return false }
        return ArisApps.TextUndo.mark(element)?.erased != nil
    }
}
