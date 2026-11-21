//
//  ArisTeachLineStart.swift
//  Shared/Core/Teach (aris-agent, tests, swift test)
//
//  The line break a lesson's text began with (eleventh VM run, T1; notes11/D2-taught.json). He pressed Return and typed
//  "Added line" after "첫 줄": the recorder kept "\nAdded line" as the value and no `startsLine` (by design since the
//  fourth run: "his own Return is part of what he typed"), so a run with another value ("줄 추가, 우유") typed "첫
//  줄우유". The break is where the text begins, not what it says: the recorder now keeps it as the step's `startsLine`
//  and the value without it, and a lesson saved the old way is read the same (`lift`, when the store is read). Only
//  for text added at the end of a text area, which is where a replay can put a line break (ArisTeachStep.newLine);
//  a value that is nothing but line breaks stays as it is. Pure.
//

import Foundation

enum ArisTeachLineStart {
    /// `value` without the one line break it begins with; nil when it begins with none, or is nothing else.
    static func lifted(_ value: String) -> String? {
        guard let first = value.first, first.isNewline else { return nil }
        let rest = String(value.dropFirst())
        return rest.contains(where: { !$0.isNewline && !$0.isWhitespace }) ? rest : nil
    }

    /// A saved lesson's steps and values, the old way made the new: for each typing step at the end of a text area whose
    /// value (its own text, or a parameter only it types) begins with a line break.
    static func lift(steps: inout [ArisTeachStep], parameters: inout [ArisTeachParameter]) {
        for index in steps.indices {
            let step = steps[index]
            guard step.action == .type, step.role == "textArea", step.place == nil || step.place == .end else { continue }
            if let key = step.parameter {
                guard steps.filter({ $0.parameter == key }).count == 1, let at = parameters.firstIndex(where: { $0.key == key }),
                      let rest = lifted(parameters[at].example) else { continue }
                parameters[at].example = rest
                steps[index].startsLine = true
            } else if let text = step.text, let rest = lifted(text) {
                steps[index].text = rest
                steps[index].startsLine = true
            }
        }
    }
}
