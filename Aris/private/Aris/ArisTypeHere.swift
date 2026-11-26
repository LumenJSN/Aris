//
//  ArisTypeHere.swift
//  Aris
//
//  When the app's own quick path may type into the focused field by itself (no card), and when it must hand the turn
//  to the brain's normal path, where every change asks on a card that shows what is erased and keeps an undo (the
//  twelfth VM run, S3/S3u: "이 문서에 있는 글을 전부 지우고 '교체된 내용'이라고 써 줘" went to the quick path, which only
//  appended and said "입력 칸에 써 뒀어요"; "선택한 부분에 '바뀐 글'이라고 입력해 줘" typed over the selected text with no
//  card, and "방금 거 되돌려 줘" found nothing to undo).
//
//  An allowlist: the quick path types only at a caret with nothing selected (read just now; a selection it couldn't
//  read counts as one), for words that plainly ask to write there and say nothing of erasing, replacing or rewriting.
//  Anything else goes to the normal path. Pure.
//

import Foundation

enum ArisTypeHere {
    enum Route: Equatable {
        /// The quick path types it at the caret, records it and says it was added there.
        case insertAtCaret
        /// The brain's normal turn (a card for any change, the erased text shown, an undo).
        case normalPath
    }

    /// What the look read of the field's selection.
    enum Selection: Equatable {
        /// A caret: nothing selected.
        case empty
        /// Something is selected.
        case text
        /// It couldn't be read (the strict case: as if something were selected).
        case unreadable
    }

    /// Korean words that erase, replace, overwrite, rewrite or point at a selection (stems, matched anywhere).
    static let koreanChangeWords = [
        "지우", "지워", "삭제", "없애", "비우", "비워", "교체", "바꿔", "바꾸", "바뀐", "바꾼", "대신", "덮어", "갈아", "고쳐", "고치", "수정", "다듬",
        "번역", "줄여", "늘려", "전부", "전체", "모두", "싹 ", "선택", "이걸로", "그걸로",
    ]
    /// English words for the same, as whole words in their forms.
    static let englishChangeWords = #"\b(?:eras\w*|delet\w*|clear\w*|remov\w*|replac\w*|instead|overwrit\w*|over\s+(?:it|the|that|this)|rewrit\w*|"#
        + #"chang\w*|fix\w*|translat\w*|edit\w*|select\w*|everything|whole|all\s+(?:of\s+)?the\s+text|swap\w*)\b"#

    /// Whether the words say anything of erasing, replacing or changing what is there (or of a selection).
    static func changesText(_ words: String) -> Bool {
        let folded = words.precomposedStringWithCompatibilityMapping.lowercased()
        return koreanChangeWords.contains { folded.contains($0) } || folded.range(of: englishChangeWords, options: .regularExpression) != nil
    }

    /// The route for a request the look found a focused, writable field for. `writesHere`: the helper read the words
    /// as asking to write in that field (ArisFocusContext.writesInPlace). `rewrite`: the words ask to rewrite a selection.
    static func route(words: String, writesHere: Bool, rewrite: Bool, selection: Selection) -> Route {
        guard writesHere, !rewrite, selection == .empty, !changesText(words) else { return .normalPath }
        return .insertAtCaret
    }

    /// The selection as the look reported it: `selected` (there was a selection), `readable` (the field was read).
    static func selection(selected: Bool, readable: Bool) -> Selection {
        !readable ? .unreadable : selected ? .text : .empty
    }

    /// What the quick path says after it typed: what actually happened (added at the caret, nothing erased). "Check it
    /// before you send it" only where it could be sent: a chat or mail field (`sends`; fourteenth VM run, R1d: it was said
    /// after typing into TextEdit).
    static func insertedLine(korean: Bool, undoable: Bool, sends: Bool = true) -> String {
        let check = sends ? (korean ? " 보내기 전에 확인해 주세요." : " Check it before you send it.") : ""
        return korean ? "커서 자리에 덧붙여 썼어요(지운 글은 없어요)." + check + (undoable ? " \"되돌려\"라고 하면 빼 드려요." : "")
            : "Added it at the cursor (nothing was erased)." + check + (undoable ? " Say \"undo\" to take it out." : "")
    }

    /// Whether the field the quick path typed into is one a send goes from (the look's focus kind: a chat or a mail).
    static func sends(focusKind: String?) -> Bool { ["chat", "mail"].contains(focusKind ?? "") }
}
