//
//  ArisTeachLeftOut.swift
//  Shared/Core/Teach (aris-agent, tests, swift test)
//
//  What a lesson showed that its saved steps don't hold, said on the card before he allows it (ninth VM run). Item 5:
//  "abc " typed, ⌘V, Delete was saved as the typing and the paste, and nothing said that the deleting was gone, so a
//  replay pasting the whole clipboard came as a surprise. Item 1: typing into a field whose only name is one the
//  system made up ("_NS:8") was saved as "put [_NS:8] in ‘_NS:8’"; such a field can't be found again by any name of
//  its own, so the step is not saved and the card says so. Also the lesson's shape for the audit: which events were
//  kept and how each text change was told, with none of the text. Pure.
//

import Foundation

extension ArisTeachGeneralise {
    /// Something he did in the lesson that no saved step does again.
    enum LeftOut: String, Equatable, Sendable {
        /// Text taken out of a field (Delete, a selection cut): deleting is not replayed.
        case deleting
        /// Text typed into a field with no name of its own: the step can't find its field again, so it isn't saved.
        case unnamedField
    }

    /// What the lesson's events hold that `procedure(_:)` makes no step of, in this order, each once.
    static func leftOut(_ events: [ArisTeachEvent]) -> [LeftOut] {
        var found: [LeftOut] = []
        if deletedText(events) { found.append(.deleting) }
        let unnamed = events.contains { event in
            guard event.kind == .valueChanged, event.pasted != true, let element = event.element, element.takesText,
                  let value = event.value, !value.isEmpty else { return false }
            return target(element) == nil
        }
        if unnamed { found.append(.unnamedField) }
        return found
    }

    /// The lesson's events as one line for the audit: each kept event's kind, and for a text change whether it was
    /// reported while he typed or read at the end, and where its run was told to sit (low-high+length). No label, no
    /// value, no key: nothing he typed or an app showed.
    static func shape(_ events: [ArisTeachEvent]) -> String {
        events.map { event -> String in
            guard event.kind == .valueChanged, event.element?.takesText == true else { return event.kind.rawValue }
            let how = event.pasted == true ? "pasted" : event.readAtEnd == true ? "end" : "live"
            let run = event.run.map { "run \($0.low)-\($0.high)+\($0.length)" } ?? "no run"
            return "valueChanged(\(how) \(run))"
        }.joined(separator: " ")
    }
}

extension ArisTeachCopy {
    /// The save card's lines for what was left out. `pastes`: the saved steps hold a paste (it puts in whatever the
    /// clipboard holds, all of it: the part he deleted after pasting comes back).
    static func leftOutLines(_ leftOut: [ArisTeachGeneralise.LeftOut], pastes: Bool, english: Bool) -> [String] {
        leftOut.map { kind in
            switch kind {
            case .deleting:
                if pastes {
                    return english ? "Left out: what you deleted. I can't learn deleting yet, so doing this again deletes nothing, and the paste puts in the whole clipboard."
                                   : "지우신 건 빼고 배웠어요. 지우기는 아직 배울 수 없어서, 다시 할 때는 아무것도 지우지 않고 붙여넣기는 클립보드에 있는 걸 전부 넣어요."
                }
                return english ? "Left out: what you deleted. I can't learn deleting yet, so doing this again deletes nothing."
                               : "지우신 건 빼고 배웠어요. 지우기는 아직 배울 수 없어서, 다시 할 때는 아무것도 지우지 않아요."
            case .unnamedField:
                return english ? "Left out: what you typed into a text field that has no name. I couldn't find that field again, so that step isn't saved."
                               : "이름 없는 입력 칸에 쓰신 건 빼고 배웠어요. 그 칸은 다시 찾을 수 없어서 그 단계는 저장하지 않아요."
            }
        }
    }

    /// Nothing to learn, and what he showed was typing into a field with no name of its own.
    static func onlyUnnamedField(_ name: String, english: Bool) -> String {
        english ? "I saw you type into a text field for “\(name)”, but that field has no name I could find it by again, so nothing was saved."
                : "‘\(name)’에서 입력 칸에 쓰신 건 봤어요. 그런데 이름 없는 입력 칸이라 다시 찾을 수 없어서 저장하지 않았어요."
    }

    /// The reply when a lesson holds nothing that can be done again, by what it did hold.
    static func nothingSaved(_ name: String, leftOut: [ArisTeachGeneralise.LeftOut], english: Bool) -> String {
        if leftOut.contains(.unnamedField) { return onlyUnnamedField(name, english: english) }
        return nothingSaved(name, deletedText: leftOut.contains(.deleting), english: english)
    }
}
