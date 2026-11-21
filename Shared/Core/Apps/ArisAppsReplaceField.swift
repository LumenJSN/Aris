//
//  ArisAppsReplaceField.swift
//  Shared/Core/Apps
//
//  The one text field a replace means, however the call named it (eleventh VM run, C3: "TextEdit 글 전부 …로 바꿔 줘"
//  with a real model said "지워질 글을 미리 읽지 못했어요" three times out of three). The tenth run's fix found the field
//  only when the call named none. A real model names it: by the id of a read it took a moment before ("e46", which is
//  only a place in that one look's walk, in the process that took it), or by words no element carries ("문서",
//  "document": TextEdit's text area has no label). Both were given up as unreadable where the card is made, and where
//  the text is set the id's kept element (its text as it was at the read) was used unchecked, or the text was typed at
//  the caret. Now one rule serves the card's read and the typing's, each on a look taken at that moment:
//  - an id: the element of that role and name as the read printed it (`seen`), found again by what it is; with nothing
//    known of the read, nothing;
//  - a description: the text element it names; when it names none, the window's one document or field;
//  - nothing named: that one document or field (ArisApps.Read.defaultTextField).
//  Never a password field, never one of several alike, never a guess. Pure.
//

import Foundation

extension ArisApps.Read {
    /// The longest name a read prints for an element (ReadElement.line).
    static let printedName = 160

    static func replaceField(_ said: String?, seen: ArisApps.Grounding.Seen?, in elements: [ArisApps.ReadElement],
                             focusedFrame: (Double, Double)? = nil) -> ArisApps.ReadElement? {
        let fields = elements.filter { $0.isText && $0.role != "secureTextField" && $0.enabled }
        guard let said = said?.trimmingCharacters(in: .whitespacesAndNewlines), !said.isEmpty else {
            return defaultTextField(in: elements, focusedFrame: focusedFrame)
        }
        if let id = ArisApps.Grounding.named(said).id {
            guard let seen, ArisApps.ReadElement.textRoles.contains(seen.role), seen.role != "secureTextField" else { return nil }
            let alike = fields.filter { $0.role == seen.role && String($0.label.prefix(printedName)) == seen.label }
            // Several alike: only the one that has that place in this look too (what it holds is still checked against the card).
            return alike.count == 1 ? alike[0] : alike.first { $0.shortId == id }
        }
        switch locate(said, in: elements, prefer: ArisApps.ReadElement.textRoles) {
        case .one(let element): return fields.contains { $0.id == element.id } ? element : nil
        case .several: return nil
        case .none: return defaultTextField(in: elements, focusedFrame: focusedFrame)
        }
    }
}

extension ArisApps.Grounding {
    /// An element as a card says it: its kind in plain words and its name, never a look's id (eleventh VM run, C5: the
    /// click card read "대상: e188" for the link “고양이의 지능”).
    struct Shown: Equatable, Sendable {
        var words: String
        /// The element has a name of its own that was read.
        var named: Bool
    }

    /// A role as the owner reads it (the helper's own desktop card uses the same words: ArisDesktopCard.roleWord).
    static let roleWords: [String: String] = [
        "textField": "입력칸", "textArea": "입력칸", "searchField": "검색칸", "secureTextField": "암호 입력칸", "comboBox": "입력칸",
        "button": "버튼", "popUpButton": "팝업 버튼", "menuButton": "메뉴 버튼", "checkBox": "체크박스", "radioButton": "선택 버튼",
        "link": "링크", "menuItem": "메뉴 항목", "menu": "메뉴", "tab": "탭", "tabGroup": "탭", "slider": "슬라이더",
        "staticText": "글자", "image": "그림", "row": "줄", "cell": "칸", "table": "표", "list": "목록", "heading": "제목",
        "disclosureTriangle": "펼치기 버튼",
    ]
    static let anyRole = "요소"
    static let unnamedLead = "이름 없는 "
    static let unread = "이름을 읽지 못한 요소"
    /// The most of a name a card's line shows.
    static let shownName = 80

    /// What a card says for a call's `target` when it is an id: the element this turn's reads printed under it. Nil for
    /// a target that is a name already. An id nothing was read for is said as that, never shown.
    static func shown(target: String, seen: [Seen]?) -> Shown? {
        guard let id = named(target, roles: Set((seen ?? []).map(\.role))).id else { return nil }
        let read: [Seen] = seen ?? []
        guard let found = read.last(where: { ($0.id.hasPrefix("elem_") ? "e" + $0.id.dropFirst(5) : $0.id) == id }) else { return Shown(words: unread, named: false) }
        let role = roleWords[found.role] ?? anyRole
        let name = found.label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return Shown(words: unnamedLead + role, named: false) }
        return Shown(words: role + " “" + (name.count > shownName ? String(name.prefix(shownName)) + "…" : name) + "”", named: true)
    }
}
