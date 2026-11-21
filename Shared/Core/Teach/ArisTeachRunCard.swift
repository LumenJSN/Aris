//
//  ArisTeachRunCard.swift
//  Shared/Core/Teach (aris-agent, tests, swift test)
//
//  The one card of a taught procedure's run (ArisTeachRunPass), and the short questions Aris says aloud for a run's
//  cards (jv-quick). The card names the procedure and lists every step in order in the step cards' own words, with this
//  run's values, where the steps come from, and each step that still asks on its own card marked plainly. A value his
//  words didn't give is asked on the same card (the values card's fields and notes), and the step that types it shows
//  the field in place of a value he may still change. Said aloud: the action in a few words and "할까요?"; the whole is
//  on the card. A step that erases, or presses something that sends, deletes or pays, still says so. Pure.
//

import Foundation

extension ArisTeachCopy {
    /// The most characters of a question said aloud for a run's card (the app holds its own questions to the same:
    /// ArisConfirmReply.questionLimit).
    static let spokenLimit = 60
    /// How much of a name, an app or a label is said.
    static let spokenName = 14
    static let spokenApp = 12
    static let spokenWord = 16

    /// The run's one card. `plan`: the run as it will be done; `marks`: each step's mark (a step with none asks again);
    /// `missing`: the values asked on this card, each as a field holding last time's value.
    static func runCard(_ procedure: ArisTeachProcedure, plan: ArisTeachReplay.Plan, marks: [ArisTeachRunPass.Mark], missing: [ArisTeachParameter] = [],
                        last: [String: String] = [:], english: Bool) -> (card: Card, fields: [(key: String, value: String)], spoken: String) {
        let asked = Set(missing.map(\.key))
        // A value asked below is shown as its field.
        var values = plan.values
        for parameter in missing { values[parameter.key] = "[\(label(parameter.label, english: english))]" }
        let given = plan.ownerGave.union(asked)
        let lines = numbered(procedure.steps.enumerated().map { index, taught in
            var line = step(taught, in: procedure, values: values, english: english)
            if let key = taught.parameter, asked.contains(key) { line += english ? " (the value in the field below)" : " (아래 칸의 값)" }
            // A replace's own line says that it asks each time.
            let again = !(index < marks.count && marks[index] != .asksAgain)
            if again, !taught.replaces { line += english ? " — asks again before this step" : " — 이 단계 전에 다시 물어봐요" }
            return line
        })
        var head = english ? "From your saved steps “\(procedure.name)”." : "저장한 단계 ‘\(procedure.name)’ 그대로예요."
        for taught in procedure.steps {
            let said = origin(procedure, step: taught, values: values, ownerGave: given, english: english).origin
            guard said.hasPrefix(head), said.count > head.count, !head.contains(said.dropFirst(head.count)) else { continue }
            head += said.dropFirst(head.count)
        }
        var tail = [english ? "Allow runs these steps as shown, once. If anything differs, it stops and asks again."
                            : "허용하면 위 단계를 이대로 한 번 해요. 달라지는 게 있으면 멈추고 다시 물어봐요."]
        let count = procedure.steps.count
        let title = english ? "Run “\(procedure.name)”, \(count) step\(count == 1 ? "" : "s")?" : "‘\(procedure.name)’ \(count)단계 할까요?"
        let name = ArisTextClip.clip(procedure.name, spokenName)
        let spoken = english ? "Run “\(name)”, \(count) step\(count == 1 ? "" : "s")?" : "‘\(name)’ \(count)단계, 할까요?"
        guard !missing.isEmpty else {
            let shown = lines.count > shownSteps ? Array(lines.prefix(shownSteps)) + [english ? "… and \(lines.count - shownSteps) more" : "… 외 \(lines.count - shownSteps)단계"] : lines
            let full = lines.count > shownSteps ? ([head] + lines + [""] + tail).joined(separator: "\n") : nil
            return (Card(title: title, detail: ([head] + shown + [""] + tail).joined(separator: "\n"), full: full), [], spoken)
        }
        // The values card's own notes and fields (an editable card draws the lines above its fields as its note).
        var note = suggestion(missing, last: last, english: english)
        if procedure.steps.indices.contains(where: { procedure.steps[$0].parameter.map(asked.contains) == true && procedure.putsLineBreak(at: $0) }) {
            note += english ? " It goes on a new line (\(lineBreak))." : " 새 줄(\(lineBreak))에 넣어요."
        }
        tail.append(note)
        let fields = emptyFields(missing, english: english)
        let detail = ([head] + lines + [""] + tail).joined(separator: "\n") + "\n" + fields.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
        return (Card(title: title, detail: detail, full: nil), fields, spoken)
    }

    /// What Aris says for the card of a step that erases text: a replace, or typing that goes over a selection.
    static func erasesSpoken(_ procedure: ArisTeachProcedure, at index: Int, english: Bool) -> String {
        let name = ArisTextClip.clip(procedure.name, spokenName), number = index + 1
        let app = ArisTextClip.clip(procedure.steps.indices.contains(index) ? procedure.steps[index].app : "", spokenApp)
        return english ? "“\(name)” step \(number) erases \(app)’s text. OK?" : "‘\(name)’ \(number)단계, \(app) 글이 지워져요. 할까요?"
    }

    /// What Aris says for a step's own card: which step, and what it erases or presses when that is the point.
    static func stepSpoken(_ procedure: ArisTeachProcedure, at index: Int, english: Bool) -> String {
        let name = ArisTextClip.clip(procedure.name, spokenName), number = index + 1
        guard procedure.steps.indices.contains(index) else { return english ? "“\(name)”, step \(number)?" : "‘\(name)’ \(number)단계, 할까요?" }
        let taught = procedure.steps[index]
        if taught.replaces { return erasesSpoken(procedure, at: index, english: english) }
        if ArisTeachCover.namesRisk(taught), let pressed = taught.label ?? taught.menu?.last ?? taught.target, !pressed.isEmpty {
            let what = ArisTextClip.clip(pressed, spokenWord)
            return english ? "“\(name)” step \(number) presses ‘\(what)’. OK?" : "‘\(name)’ \(number)단계, ‘\(what)’ 눌러요. 할까요?"
        }
        return english ? "“\(name)”, step \(number)?" : "‘\(name)’ \(number)단계, 할까요?"
    }
}
