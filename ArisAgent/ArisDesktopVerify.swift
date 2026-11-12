//
//  ArisDesktopVerify.swift
//  aris-agent
//
//  Whether an action did what it was for, read back from the window, never from an exit code (the benchmark: set-value
//  "ok" that SwiftUI never committed, clicks "dispatched but not verified"). Typed text must be in the field, a value set
//  must be the field's value, a checkbox must have flipped; anything else must have changed something in the window.
//  The change is said in a line or two, so the brain sees what happened. Pure.
//

import Foundation

enum ArisDesktopCheck: Equatable {
    /// It did what it was for.
    case done(String)
    /// The window shows no sign of it.
    case notSeen(String)
}

/// What a press can be told by besides the window's tree (audit desk-2): the clipboard, and the document's unsaved mark.
struct ArisPressEvidence: Equatable {
    /// The clipboard's change count moved while the keys were pressed.
    var clipboardChanged = false
    /// Whether the window's document had unsaved changes before the keys, and has them after; nil when it can't be told.
    var editedBefore: Bool? = nil
    var editedAfter: Bool? = nil
}

enum ArisDesktopVerify {
    /// What changed between two looks at the same window: values, controls that came or went, its title.
    static func changes(before: ArisDesktopObservation, after: ArisDesktopObservation, limit: Int = 6) -> [String] {
        var lines: [String] = []
        if before.window != after.window { lines.append("now on window \(after.window) “\(after.title)”") } else if before.title != after.title {
            lines.append("the window's title is now “\(after.title)”")
        }
        // Peekaboo's ids aren't stable across looks: a control is its role and label (the nth of that kind).
        let oldKeys = keyed(before.shown), newKeys = keyed(after.shown)
        let old = Dictionary(oldKeys.map { ($0.key, $0.element) }, uniquingKeysWith: { first, _ in first })
        let new = Dictionary(newKeys.map { ($0.key, $0.element) }, uniquingKeysWith: { first, _ in first })
        for (key, element) in newKeys {
            guard let was = old[key] else { continue }
            if (was.value ?? "") != (element.value ?? "") {
                lines.append("“\(short(element.label))” \(element.role): “\(short(was.value ?? ""))” → “\(short(element.value ?? ""))”")
            }
        }
        let came = newKeys.filter { old[$0.key] == nil && !$0.element.label.isEmpty }.map(\.element)
        let went = oldKeys.filter { new[$0.key] == nil && !$0.element.label.isEmpty }.map(\.element)
        if !came.isEmpty { lines.append("appeared: " + came.prefix(5).map { "“\(short($0.label))”" }.joined(separator: ", ") + (came.count > 5 ? " (+\(came.count - 5))" : "")) }
        if !went.isEmpty { lines.append("gone: " + went.prefix(5).map { "“\(short($0.label))”" }.joined(separator: ", ") + (went.count > 5 ? " (+\(went.count - 5))" : "")) }
        if before.focused != after.focused, let field = after.shown.first(where: after.isFocused), !(lines.contains { $0.contains(field.label) }) {
            lines.append("focus is on “\(short(field.label))”")
        }
        return Array(lines.prefix(limit))
    }

    /// Typed text landed: the field (found again by role and label) now holds it. Compared with the raw value (the
    /// app's own, unredacted), and said with the shown one (C2). `before`: the field's raw value before typing, when
    /// known: then it must hold the text once more than it did (QA BUG-10: text it held already proves nothing).
    static func typed(_ text: String, field: ArisDesktopElement, after: ArisDesktopObservation, before: String? = nil) -> ArisDesktopCheck {
        let now = find(field, in: after)
        // Both sides composed (NFC): the same text, however either was encoded.
        let raw = (now?.rawValue ?? "").precomposedStringWithCanonicalMapping, shown = now?.value ?? ""
        let wanted = text.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        let more = before.map { raw.components(separatedBy: wanted).count > $0.precomposedStringWithCanonicalMapping.components(separatedBy: wanted).count } ?? true
        if !wanted.isEmpty, raw.contains(wanted), more { return .done("“\(short(field.label))” now reads “\(short(shown))”") }
        return .notSeen("“\(short(field.label))” reads “\(short(shown))”")
    }

    /// The typed text shows somewhere in the window (a field that can't be read back: the chat read back instead).
    static func appears(_ text: String, in look: ArisDesktopObservation) -> Bool {
        let wanted = text.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        guard !wanted.isEmpty else { return false }
        return (look.elements + look.marks).contains {
            ($0.rawValue ?? "").precomposedStringWithCanonicalMapping.contains(wanted) || $0.label.precomposedStringWithCanonicalMapping.contains(wanted)
        }
    }

    /// A value set landed exactly (the raw value, C2).
    static func set(_ text: String, field: ArisDesktopElement, after: ArisDesktopObservation) -> ArisDesktopCheck {
        let now = find(field, in: after)
        let shown = now?.value ?? ""
        return now?.rawValue?.precomposedStringWithCanonicalMapping == text.precomposedStringWithCanonicalMapping ? .done("“\(short(field.label))” is now “\(short(shown))”") : .notSeen("“\(short(field.label))” reads “\(short(shown))”")
    }

    /// Anything else: a checkbox flipped, or the window changed at all.
    static func acted(on element: ArisDesktopElement?, before: ArisDesktopObservation, after: ArisDesktopObservation) -> ArisDesktopCheck {
        let lines = changes(before: before, after: after)
        if let element, ["checkbox", "radioButton", "switch"].contains(element.role), let was = find(element, in: before), let now = find(element, in: after) {
            return was.value != now.value ? .done("“\(short(element.label))” is now \(now.value == "1" ? "on" : now.value == "0" ? "off" : "“\(now.value ?? "")”")")
                : .notSeen("“\(short(element.label))” didn't change")
        }
        return lines.isEmpty ? .notSeen("nothing in the window changed") : .done(lines.joined(separator: "; "))
    }

    /// Keys that only move the caret (End, Home, the arrows, Page Up/Down, with ⌘ ⌥ ⌃): nothing in the window's tree
    /// changes for them, so "nothing changed" isn't a failure (QA retest on 8e236bff: an approved append stopped at its
    /// "end" step with TextEdit in front).
    static let caretKeys: Set<String> = ["end", "home", "up", "down", "left", "right", "pageup", "pagedown", "page_up", "page_down"]
    static let caretModifiers: Set<String> = ["cmd", "command", "alt", "option", "opt", "ctrl", "control"]
    static func movesCaretOnly(_ keys: [String]) -> Bool {
        !keys.isEmpty && keys.allSatisfy { chord in
            let parts = chord.lowercased().split(separator: "+").map(String.init)
            guard let key = parts.last, caretKeys.contains(key) else { return false }
            return parts.dropLast().allSatisfy(caretModifiers.contains)
        }
    }

    /// A copy or a cut (⌘C, ⌘X), a save (⌘S), and a caret key held with Shift (it selects).
    static func copies(_ chord: String) -> Bool { [["cmd", "c"], ["cmd", "x"]].contains(ArisDesktopBatch.normalized(chord)) }
    static func saves(_ chord: String) -> Bool { ArisDesktopBatch.normalized(chord) == ["cmd", "s"] }
    static func extendsSelection(_ chord: String) -> Bool {
        let parts = chord.lowercased().split(separator: "+").map(String.init)
        guard let key = parts.last, caretKeys.contains(key), parts.dropLast().contains("shift") else { return false }
        return parts.dropLast().allSatisfy { $0 == "shift" || caretModifiers.contains($0) }
    }

    /// Keys whose work shows nowhere in the window's tree: a copy, a select-all, a selection, a caret move, a save.
    static func isQuiet(_ chord: String) -> Bool {
        copies(chord) || saves(chord) || ArisDesktopBatch.isSelectAll(chord) || extendsSelection(chord) || movesCaretOnly([chord])
    }

    /// A press read back: what changed in the window; else, only for keys that change nothing there (audit desk-2: a
    /// copy, a select-all and a save of a saved file were told as not done, and stopped a batch), what each of them can
    /// be told by, every one of them: the clipboard moved for a copy or cut; the document has no unsaved changes after
    /// a save; and in the text control that has the focus, the selection covers everything after a select-all, the
    /// selection changed after a Shift caret key, the caret as AX reads it for a caret key ("moved" only when it did,
    /// else only that the keys were sent: security review of 0c370061). Return, a letter, or any of these with no such
    /// sign stays not confirmed.
    static func pressed(_ keys: [String], dispatched: Bool, before: ArisDesktopObservation, after: ArisDesktopObservation,
                        evidence: ArisPressEvidence = ArisPressEvidence()) -> ArisDesktopCheck {
        let check = acted(on: nil, before: before, after: after)
        guard case .notSeen = check, dispatched, !keys.isEmpty, keys.allSatisfy(isQuiet), !after.focusIsSecure else { return check }
        let pressed = keys.joined(separator: " ")
        var seen: [String] = []
        if keys.contains(where: copies) {
            guard evidence.clipboardChanged else { return check }
            seen.append("the clipboard changed (\(pressed)): what was selected is on it")
        }
        if keys.contains(where: saves) {
            guard evidence.editedAfter == false else { return check }
            seen.append(evidence.editedBefore == true ? "the document's unsaved changes are saved (\(pressed))"
                : "the document has no unsaved changes (\(pressed)): there was nothing left to save")
        }
        // The last key that touches the selection has the last word on it.
        if let last = keys.last(where: { ArisDesktopBatch.isSelectAll($0) || extendsSelection($0) || movesCaretOnly([$0]) }) {
            guard let field = after.focusedElement, field.isTextEntry else { return check }
            let named = "“\(short(field.label))”"
            let was = find(field, in: before)?.selectedRange, now = field.selectedRange
            if ArisDesktopBatch.isSelectAll(last) {
                guard let now, now.location == 0 else { return check }
                if let text = field.rawValue ?? field.value {
                    guard now.length >= text.utf16.count else { return check }
                    seen.append(text.isEmpty ? "\(named) is empty, so there was nothing to select (\(pressed))" : "everything in \(named) is selected (\(pressed): \(now.shown))")
                } else {
                    guard now.length > 0, was != now else { return check }
                    seen.append("the selection in \(named) is now \(now.shown) (\(pressed))")
                }
            } else if extendsSelection(last) {
                guard let was, let now, was != now else { return check }
                seen.append("the selection in \(named) changed (\(pressed): \(was.shown) → \(now.shown))")
            } else {
                switch (was, now) {
                case let (was?, now?) where was != now:
                    seen.append("the caret moved in \(named) (\(pressed): \(was.shown) → \(now.shown))")
                case let (was?, now?) where was == now:
                    seen.append("keys sent to \(named) (\(pressed)); the caret stayed \(now.shown): it was already there")
                default:
                    seen.append("keys sent to \(named) (\(pressed)); the caret's place can't be read, and a caret key changes nothing else in the window")
                }
            }
        }
        return seen.isEmpty ? check : .done(seen.joined(separator: "; "))
    }

    /// A click read back: what changed; else, for a document's text area, only when the click moved the focus onto
    /// it or moved its caret or selection (AX's kAXSelectedTextRange). A click that missed a text area that already
    /// had the focus stays "not confirmed" (security review of 0c370061). Only a text area: a click on a field (a
    /// search field) is often meant to open something, and "nothing changed" there is worth saying.
    /// A document's text area (AXTextArea).
    static func isTextArea(_ element: ArisDesktopElement) -> Bool { element.role == "textArea" || element.axRole == "AXTextArea" }

    static func clicked(_ element: ArisDesktopElement, before: ArisDesktopObservation, after: ArisDesktopObservation) -> ArisDesktopCheck {
        let check = acted(on: element, before: before, after: after)
        guard case .notSeen = check, element.role == "textArea" || element.axRole == "AXTextArea",
              let now = find(element, in: after), after.isFocused(now) else { return check }
        let was = find(element, in: before)
        if !(was.map(before.isFocused) ?? false) { return .done("“\(short(element.label))” has the keyboard focus now") }
        if let from = was?.selectedRange, let to = now.selectedRange, from != to {
            return .done("the caret in “\(short(element.label))” moved (\(from.shown) → \(to.shown))")
        }
        return check
    }

    /// A drawn view: the text read from the screen came or went.
    static func textChanged(before: ArisDesktopObservation, after: ArisDesktopObservation) -> ArisDesktopCheck {
        let old = before.marks.map(\.label), new = after.marks.map(\.label)
        let came = new.filter { !old.contains($0) }, went = old.filter { !new.contains($0) }
        guard !came.isEmpty || !went.isEmpty else { return .notSeen("the text on the window didn't change") }
        var parts: [String] = []
        if !came.isEmpty { parts.append("the window now shows " + came.prefix(4).map { "“\(short($0))”" }.joined(separator: ", ")) }
        if !went.isEmpty { parts.append("no longer " + went.prefix(4).map { "“\(short($0))”" }.joined(separator: ", ")) }
        return .done(parts.joined(separator: "; "))
    }

    /// The same control in another look: the same Peekaboo id with the same role and label, else the one control with that
    /// role and label, else the one control of that role where it was. A text field's label can be its own text (a
    /// SwiftUI field with no label of its own reads "text field" empty, "Jane Doe" once typed in): matched by its id and
    /// role in the same place, or by place, never by its label alone (bench form_save).
    static func find(_ element: ArisDesktopElement, in observation: ArisDesktopObservation) -> ArisDesktopElement? {
        if let same = observation.element(id: element.id), same.sameControl(element) { return same }
        let byText = element.isTextEntry || element.label.isEmpty
        // A text field: its id and role where it was come before its label, which another (empty) field can share
        // ("text field").
        if byText, let same = observation.element(id: element.id), same.role == element.role, samePlace(same, element) { return same }
        let matches = observation.elements.filter { $0.sameControl(element) && (!byText || samePlace($0, element)) }
        if matches.count == 1 { return matches[0] }
        guard byText else { return nil }
        let placed = observation.elements.filter { $0.role == element.role && samePlace($0, element) }
        return placed.count == 1 ? placed[0] : nil
    }

    /// The same place: its top-left and height within a few points (the same window, not moved). Its width may change:
    /// a field can grow with its text (bench form_save).
    static func samePlace(_ one: ArisDesktopElement, _ other: ArisDesktopElement) -> Bool {
        one.bounds.width > 0 && abs(one.bounds.minX - other.bounds.minX) <= 3 && abs(one.bounds.minY - other.bounds.minY) <= 3
            && abs(one.bounds.height - other.bounds.height) <= 3
    }

    private static func keyed(_ elements: [ArisDesktopElement]) -> [(key: String, element: ArisDesktopElement)] {
        var seen: [String: Int] = [:]
        return elements.map { element in
            let kind = "\(element.role)|\(element.label)"
            seen[kind, default: 0] += 1
            return ("\(kind)|\(seen[kind]!)", element)
        }
    }

    static func short(_ text: String) -> String {
        let one = String(String.UnicodeScalarView(text.unicodeScalars.map { ArisCommandPolicy.isLineBreak($0) ? " " : $0 }))
        return one.count > 80 ? String(one.prefix(80)) + "…" : one
    }
}
