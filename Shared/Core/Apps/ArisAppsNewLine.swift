//
//  ArisAppsNewLine.swift
//  Shared/Core/Apps
//
//  A taught text that began a line (sixth VM run: "줄 추가" was taught by typing "Added line" into an empty document,
//  and its replay on a document holding "Existing line keep" left "Existing line keepAdded line"). The replay's call
//  carries the text with one line break before it, so the trust gate rates the break (a line break is Return where
//  Return sends or submits, ArisApps.Risk.type) and the card shows it (↵), and marks it `line: "new"`. app.type then
//  types that break only where it is needed and can be told: into a text area (a field that holds line breaks), at its
//  end, whose text as the app layer read it before typing is not empty and doesn't already end a line. Anywhere else,
//  or when the field wasn't read, the break is left out: the mark can only ever take that one break away, so what is
//  typed is never more than what was rated. Pure.
//

import Foundation

extension ArisApps {
    enum NewLine {
        /// The argument that marks the text's first character as a line break typed only where it is needed.
        static let argument = "line"
        static let mark = "new"
        static let lineBreak = "\n"

        /// The text app.type types for a call: its `text`, without the leading line break the mark covers unless `field`
        /// (as read before typing) is a text area whose text needs it to put the rest on a line of its own.
        static func typed(_ arguments: JSON, field: ReadElement?) -> String {
            let text = arguments["text"]?.string ?? ""
            guard arguments[argument]?.string == mark, text.hasPrefix(lineBreak) else { return text }
            return keepsBreak(arguments, field: field) ? text : String(text.dropFirst(lineBreak.count))
        }

        /// The break goes in: at the end of a text area that holds text not ending a line.
        static func keepsBreak(_ arguments: JSON, field: ReadElement?) -> Bool {
            guard arguments["at"]?.string == "end", arguments["replace"]?.bool != true, let field, field.role == "textArea",
                  let last = (field.value ?? "").last else { return false }
            return !last.isNewline
        }
    }
}
