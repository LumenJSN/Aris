//
//  ArisTodoListName.swift
//  Aris
//
//  Which Reminders list `aris-tools todo add --list <name>` means (twelfth VM run, K1: "이 문서에 적힌 할 일 미리 알림에
//  추가해 줘" made three `todo add … --list '미리 알림'` cards whose adds failed after the yes, then three more cards without
//  the list). The name is compared as people write it (any case, any Unicode form, spaces left out); the app's own name
//  ("미리 알림", "Reminders") with no list called that means the default list, never a failure. Pure.
//

import Foundation

enum ArisTodoListName {
    enum Match: Equatable {
        /// That list.
        case list(String)
        /// The default list (the name was the Reminders app's own).
        case defaultList
        /// No list of that name: the message says which there are.
        case none(String)
    }

    /// The Reminders app's own names, folded: "미리 알림에 추가해 줘" means the app, not a list.
    static let appNames: Set<String> = ["미리알림", "리마인더", "reminders", "reminder", "remindersapp", "미리알림앱", "할일", "todo", "to-do", "todos"]

    static func fold(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.lowercased().filter { !$0.isWhitespace }
    }

    static func match(_ name: String, lists: [(id: String, name: String)]) -> Match {
        let wanted = fold(name)
        if let found = lists.first(where: { fold($0.name) == wanted }) { return .list(found.id) }
        if appNames.contains(wanted) { return .defaultList }
        let known = lists.map(\.name).prefix(12).joined(separator: ", ")
        return .none("no Reminders list named \"\(name)\"" + (known.isEmpty ? "" : " (lists: \(known))") + "; leave out --list for the default list")
    }
}
