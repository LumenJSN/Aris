//
//  ArisTeachGeneralise.swift
//  Shared/Core/Teach (aris-agent, tests, swift test)
//
//  A finished demonstration made into a procedure (ARCHITECTURE Part 3, F3): the events become calls of the app layer's
//  existing capabilities, and what the owner typed becomes a parameter labelled by its field, its value kept as the
//  example a run uses when he gives no other. Mechanically, with no model: every app is opened once (app.open, in the
//  background), a menu command is app.do with its path, a press is app.click (a row or a tab is app.select), a field's
//  last value is app.type, keys are app.press. What only moves the focus (a click into a field, Tab, ⌘Tab) or only
//  follows from a step (a window opening) is no step. Labels, menu titles and typed text are outside text read from
//  that app: they are data in a step (which control, which value), never a step of their own, and every step keeps
//  where they were seen. Pure.
//

import Foundation

enum ArisTeachGeneralise {
    enum Problem: Error, Equatable, Sendable {
        /// Nothing in it can be done again (no app, or only looks).
        case nothing
        /// More steps than a procedure holds.
        case tooLong(Int)
    }

    static let mostSteps = 40
    static let mostParameters = 8
    /// A shortcut this close before a menu command of the same app is that command (said once).
    static let shortcutMenuGap: TimeInterval = 1.5

    /// The word the app layer finds an element of this role by (ArisApps.Read.locate's role words).
    static func roleWord(_ role: String?) -> String? {
        switch role ?? "" {
        case "button", "menuButton": "버튼"
        case "textField", "textArea", "comboBox": "칸"
        case "searchField": "검색창"
        case "checkBox": "체크박스"
        case "link": "링크"
        case "tab", "radioButton": "탭"
        case "row", "cell", "outlineRow": "항목"
        case "popUpButton": "메뉴"
        default: nil
        }
    }

    /// What a document's main text is called when the owner names it ("메모 쓰기 해 줘, 본문은 …").
    static let bodyLabel = "본문"

    /// The name a field goes by on the card and in the owner's words: its own label when it says what the field is for;
    /// a document's main text area, whose only name is a developer's ("First Text View", "Text View", "Text Area") or
    /// none, is "본문".
    static func fieldName(_ element: ArisTeachElement) -> String {
        let name = element.name
        guard element.role == "textArea" else { return name }
        let generic = #"^(?:(?:first|second|main|primary)\s+)?(?:text(?:\s*(?:view|area|editor|field))?|editor|document|content|scroll\s*view|body)(?:\s*\d+)?$"#
        if name.isEmpty || name.range(of: generic, options: [.regularExpression, .caseInsensitive]) != nil { return bodyLabel }
        return name
    }

    /// The description a step finds the element by again ("보내기 버튼"); nil when it has no name at all.
    static func target(_ element: ArisTeachElement) -> String? {
        let name = element.name
        guard !name.isEmpty else { return nil }
        guard let word = roleWord(element.role), !name.hasSuffix(word) else { return name }
        return name + " " + word
    }

    static func procedure(_ lesson: ArisTeachRecorder.Lesson, id: UUID = UUID()) -> Result<ArisTeachProcedure, Problem> {
        procedure(name: lesson.name, events: lesson.events, skipped: lesson.skipped, at: lesson.ended, id: id)
    }

    static func procedure(name: String, events: [ArisTeachEvent], skipped: Int = 0, at now: Date, id: UUID = UUID()) -> Result<ArisTeachProcedure, Problem> {
        var steps: [ArisTeachStep] = []
        var parameters: [ArisTeachParameter] = []
        var opened = Set<String>()
        for (index, event) in events.enumerated() {
            guard let made = step(event, index: index, events: events, parameters: &parameters) else {
                if event.kind == .appActivated { open(event.app, steps: &steps, opened: &opened) }
                continue
            }
            open(event.app, steps: &steps, opened: &opened)
            // The same press twice in a row (a press and its value change) is one step.
            if let last = steps.last, last == made, made.action == .click || made.action == .select { continue }
            steps.append(made)
        }
        // An app that was only brought to the front, with nothing done in it, is no step of its own.
        steps = steps.enumerated().filter { index, step in
            guard step.action == .open else { return true }
            return steps[(index + 1)...].contains { $0.bundle == step.bundle && $0.action != .open }
        }.map(\.element)
        guard !steps.isEmpty else { return .failure(.nothing) }
        guard steps.count <= mostSteps else { return .failure(.tooLong(steps.count)) }
        return .success(ArisTeachProcedure(id: id, name: name, steps: steps, parameters: parameters, skipped: skipped, created: now))
    }

    /// The lesson took text out of a field and put none in (Delete pressed, a selection cut): for the reply when
    /// nothing in it can be done again (eighth VM run, item 7). Deleting is not replayed; this only names it.
    static func deletedText(_ events: [ArisTeachEvent]) -> Bool {
        events.contains { event in
            guard event.kind == .valueChanged, event.pasted != true, let element = event.element, element.takesText,
                  let before = event.before, let after = event.value, after.count < before.count else { return false }
            return textChange(before: before, after: after).text.isEmpty
        }
    }

    private static func open(_ app: ArisTeachApp, steps: inout [ArisTeachStep], opened: inout Set<String>) {
        guard !opened.contains(app.bundle) else { return }
        opened.insert(app.bundle)
        steps.append(ArisTeachStep(action: .open, app: app.name, bundle: app.bundle))
    }

    private static func seen(_ app: ArisTeachApp) -> ArisContentSource { ArisContentSource(kind: "app", source: app.name) }

    /// The step one event makes, or nil when it makes none.
    private static func step(_ event: ArisTeachEvent, index: Int, events: [ArisTeachEvent], parameters: inout [ArisTeachParameter]) -> ArisTeachStep? {
        let app = event.app
        switch event.kind {
        case .appActivated, .windowOpened, .focused, .input:
            return nil
        case .menuChosen:
            guard let menu = event.menu, !menu.isEmpty else { return nil }
            // The key equivalent it was chosen by, when it was: the replay checks the item still has it.
            return ArisTeachStep(action: .menu, app: app.name, bundle: app.bundle, label: menu.last, menu: menu, keys: event.keys.map(normalisedKeys), seen: seen(app))
        case .pressed:
            // A click on a pop-up only opens its menu: the choice in it is the step.
            guard let element = event.element, !element.takesText, !ArisTeachRecorder.choiceRoles.contains(element.role),
                  let target = target(element) else { return nil }
            let action: ArisTeachStep.Action = ArisTeachElement.listRoles.contains(element.role) ? .select : .click
            return ArisTeachStep(action: action, app: app.name, bundle: app.bundle, target: target, role: element.role, label: element.name, seen: seen(app))
        case .selected:
            // A menu opened from the menu bar (its title highlighted as it opens) is no step: the item chosen in it is
            // (fourth VM run, D4: "pick ‘Format’" was saved before Format › Wrap to Page and failed every replay).
            guard let element = event.element, !ArisTeachRecorder.menuRoles.contains(element.role), let target = target(element) else { return nil }
            var step = ArisTeachStep(action: .select, app: app.name, bundle: app.bundle, target: target, role: element.role, label: element.name,
                                     option: event.value.flatMap { $0.isEmpty ? nil : String($0.prefix(200)) }, seen: seen(app))
            if step.option != nil { step.fromApp = true }
            return step
        case .valueChanged:
            guard let element = event.element, let target = target(element) else { return nil }
            if element.takesText {
                // What a paste put there: the paste before it is the step, and it pastes what the clipboard holds then.
                guard event.pasted != true else { return nil }
                guard let whole = event.value, !whole.isEmpty else { return nil }
                // What he put there, and where: after what the field held (or into an empty one), or over it.
                var change = textChange(before: event.before, after: whole, selectedAll: selectedAll(before: index, events: events, element: element),
                                        overSelection: event.overSelection == true, began: event.began)
                // The run as its changes built it, one after another, when they could be followed and it fits the two
                // values (ninth VM run, item 1); a replace stays a replace.
                if change.place != .all, let told = event.run?.text(in: whole, before: event.before ?? "") {
                    change = TextChange(text: told.text, place: told.atEnd ? .end : .caret)
                }
                var value = String(change.text.prefix(ArisTeachRecorder.longestValue))
                // His own Return before the text is where the text begins, not part of the value (eleventh VM run, T1:
                // "\nAdded line" was kept as the value, so a run with another value dropped the break: "첫 줄우유").
                let lifted = change.place == .end && element.role == "textArea" ? ArisTeachLineStart.lifted(value) : nil
                if let lifted { value = lifted }
                guard !value.isEmpty else { return nil }
                // The card's hint only: looks typed by them, or put there by the app. Content at replay either way.
                let fromApp = event.typed != true
                let key = parameter(for: value, element: element, app: app, fromApp: fromApp, parameters: &parameters)
                var step = ArisTeachStep(action: .type, app: app.name, bundle: app.bundle, target: target, role: element.role, label: fieldName(element),
                                         text: key == nil ? value : nil, parameter: key, seen: seen(app))
                step.fromApp = fromApp
                step.place = change.place
                // A key that put the caret at the end right before this typing (⌘↓, ⌘→, End) is where the text goes
                // (fourth VM run, D3), not a step of its own.
                if change.place == .caret, endKeyBefore(index, events: events, element: element) { step.place = .end }
                // Whether his typing began a line, in a text area only (a one-line field never takes a line break).
                if change.place != .all, element.role == "textArea", startsLine(before: event.before, after: whole) { step.startsLine = true }
                if lifted != nil { step.startsLine = true }
                return step
            }
            if element.role == "popUpButton" || element.role == "comboBox" {
                guard let value = event.value, !value.isEmpty else { return nil }
                var step = ArisTeachStep(action: .select, app: app.name, bundle: app.bundle, target: target, role: element.role, label: element.name,
                                         option: String(value.prefix(200)), seen: seen(app))
                step.fromApp = true
                return step
            }
            // A checkbox or a switch that changed: pressing it again does the same, unless the press itself is the event before.
            guard ["checkBox", "radioButton", "switch"].contains(element.role) else { return nil }
            if index > 0, events[index - 1].kind == .pressed, events[index - 1].element.map({ $0.same(as: element) }) == true { return nil }
            return ArisTeachStep(action: .click, app: app.name, bundle: app.bundle, target: target, role: element.role, label: element.name, seen: seen(app))
        case .shortcut:
            guard let keys = event.keys.map(normalisedKeys), !keys.isEmpty, !movesFocusOnly(keys), !ArisTeachLaunchers.keys.contains(keys) else { return nil }
            // ⌘A in a text field followed by typing there: the type step replaces the whole text, so no key step.
            if keys == "cmd+a", let element = event.element, element.takesText,
               events[(index + 1)...].prefix(4).contains(where: { $0.kind == .valueChanged && $0.pasted != true && $0.element.map { $0.same(as: element) } == true }) {
                return nil
            }
            // A key that only puts the caret at the end of a text right before he types there: the typing's place.
            if caretEndKeys.contains(keys), endKeyLeadsToTyping(index, events: events) { return nil }
            // A shortcut that chose a menu command: the command is the step.
            if events[(index + 1)...].prefix(3).contains(where: { $0.kind == .menuChosen && $0.app == app && $0.at.timeIntervalSince(event.at) <= shortcutMenuGap }) {
                return nil
            }
            return ArisTeachStep(action: .press, app: app.name, bundle: app.bundle, keys: keys, seen: seen(app))
        }
    }

    /// What a stretch of typing did to a text element: only the text he put in, and where it went relative to what was
    /// there (at its end, or at the caret inside it); or, only when the lesson saw him select text that was there and
    /// type over it, the whole value he left (it replaced what was there).
    struct TextChange: Equatable, Sendable {
        let text: String
        let place: ArisTeachStep.Place
    }

    /// The change from the field's value before his first key (`before`) to the value after his last (`after`), never
    /// the whole field as his (fourth VM run, D2: "quick note" saved the document's old line with the new one, and D1:
    /// typing into an empty new document was saved as "replace everything"). The inserted run is the difference: what
    /// lies between the longest common start and end of the two values. It is a replace only with evidence that he
    /// selected text that was there: ⌘A in the field while it held text (`selectedAll`), or a non-empty selection the
    /// observer read right before his key (`overSelection`), and text that was there is gone. Anything else (an empty
    /// field, a caret in a field with text, text gone with no selection seen: an app's own correction of what he had
    /// just typed, a value read late) is an insertion of what he added, so a replay never removes text he did not.
    /// `began`: the one character his first key of the stretch put in (the recorder's note). The two values alone
    /// leave open where a run went in when it begins like the text right after it (eighth VM run, item 8: "Wrap memo"
    /// typed at the start of "Wrap seed" gave "Wrap memoWrap seed", and the longest common start made it "memoWrap ").
    /// Of the places the values allow, the first whose run begins with that character is his; when none does (the app
    /// changed what he typed, a syllable still being composed) the place is told as before.
    static func textChange(before: String?, after: String, selectedAll: Bool = false, overSelection: Bool = false, began: String? = nil) -> TextChange {
        let old = Array(before ?? ""), new = Array(after)
        // He selected all of what the field held and typed: his text is the whole new value, and it replaces.
        if selectedAll, !old.isEmpty { return TextChange(text: after, place: .all) }
        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < old.count - prefix, suffix < new.count - prefix, old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }
        let removed = old.count - prefix - suffix
        // A selection of what was there, typed over or deleted: the lesson replaced it.
        if removed > 0, overSelection { return TextChange(text: after, place: .all) }
        if removed == 0, let began, began.count == 1, let first = began.first {
            let length = new.count - old.count
            var tail = 0
            while tail < old.count, old[old.count - 1 - tail] == new[new.count - 1 - tail] { tail += 1 }
            let lowest = old.count - tail
            if length > 0, lowest < prefix, let start = (lowest...prefix).first(where: { new[$0] == first }) {
                return TextChange(text: String(new[start..<(start + length)]), place: start + length == new.count ? .end : .caret)
            }
        }
        // What he typed went in: at the end of what was there, or at the caret inside it.
        return TextChange(text: String(new[prefix..<(new.count - suffix)]), place: suffix == 0 ? .end : .caret)
    }

    /// Whether the text he put in began a line: the field was empty, or the character right before where his text went
    /// in was a line break. Read only from the field's text before his first key (`before`) and after his last, as the
    /// insertion's place is (textChange); a text not read before (nil) tells nothing, so it is no.
    static func startsLine(before: String?, after: String) -> Bool {
        guard let before else { return false }
        let old = Array(before), new = Array(after)
        guard !old.isEmpty else { return !new.isEmpty }
        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] { prefix += 1 }
        return prefix > 0 && old[prefix - 1].isNewline
    }

    /// Keys that put the caret at the end of a text (⌘↓, ⌘→ to a line's end, End, ⌘End).
    static let caretEndKeys: Set<String> = ["cmd+down", "cmd+right", "end", "cmd+end", "ctrl+e"]

    /// Events that come between his key and his typing without being a step (a focus, his hand, a window).
    private static let between: Set<ArisTeachEvent.Kind> = [.focused, .input, .windowOpened]

    /// The caret-end key at `index` is followed by his typing into a text element of that app (its own element when
    /// the key told it), with only a focus or his hand between.
    private static func endKeyLeadsToTyping(_ index: Int, events: [ArisTeachEvent]) -> Bool {
        let key = events[index]
        guard key.element.map({ $0.takesText }) ?? true else { return false }
        for later in events[(index + 1)...] {
            if between.contains(later.kind) { continue }
            guard later.kind == .valueChanged, later.pasted != true, later.app == key.app, let element = later.element, element.takesText else { return false }
            return key.element.map { $0.same(as: element) } ?? true
        }
        return false
    }

    /// A caret-end key in this element (or its app, when the key told no element) right before the change at `index`.
    private static func endKeyBefore(_ index: Int, events: [ArisTeachEvent], element: ArisTeachElement) -> Bool {
        var at = index - 1
        while at >= 0 {
            let earlier = events[at]
            if earlier.kind == .shortcut {
                return caretEndKeys.contains(normalisedKeys(earlier.keys ?? "")) && earlier.app == events[index].app
                    && (earlier.element.map { $0.same(as: element) } ?? true)
            }
            guard between.contains(earlier.kind) else { return false }
            at -= 1
        }
        return false
    }

    /// He selected all of that field (⌘A in it) before this change, with no other step between.
    private static func selectedAll(before index: Int, events: [ArisTeachEvent], element: ArisTeachElement) -> Bool {
        var at = index - 1
        while at >= 0 {
            let earlier = events[at]
            if earlier.kind == .shortcut, normalisedKeys(earlier.keys ?? "") == "cmd+a" { return earlier.element.map { $0.same(as: element) } ?? true }
            guard [.focused, .input, .windowOpened].contains(earlier.kind) else { return false }
            at -= 1
        }
        return false
    }

    /// The parameter a typed value fills: the one already made for the same value in the same field, else a new one;
    /// nil past the most a procedure takes (the value is then typed as it was).
    private static func parameter(for value: String, element: ArisTeachElement, app: ArisTeachApp, fromApp: Bool, parameters: inout [ArisTeachParameter]) -> String? {
        let label = fieldName(element)
        if let same = parameters.first(where: { $0.example == value && $0.app == app.name && ($0.fromApp ?? false) == fromApp }) { return same.key }
        guard parameters.count < mostParameters else { return nil }
        var shown = label.isEmpty ? "값 \(parameters.count + 1)" : label
        if parameters.contains(where: { $0.label == shown }) { shown += " \(parameters.filter { $0.label.hasPrefix(shown) }.count + 1)" }
        let key = "p\(parameters.count + 1)"
        var made = ArisTeachParameter(key: key, label: shown, example: value, app: app.name)
        made.fromApp = fromApp
        parameters.append(made)
        return key
    }

    /// Keys as app.press takes them: lowercased, "+" between, the modifiers first.
    static func normalisedKeys(_ raw: String) -> String {
        let parts = raw.lowercased().replacingOccurrences(of: " ", with: "").split(separator: "+").map(String.init).filter { !$0.isEmpty }
        let order = ["cmd", "ctrl", "opt", "shift", "fn"]
        let aliases = ["command": "cmd", "⌘": "cmd", "control": "ctrl", "⌃": "ctrl", "option": "opt", "alt": "opt", "⌥": "opt", "⇧": "shift", "enter": "return"]
        let named = parts.map { aliases[$0] ?? $0 }
        let modifiers = order.filter(named.contains)
        let rest = named.filter { !order.contains($0) }
        return (modifiers + rest).joined(separator: "+")
    }

    /// Keys that only move the focus or switch apps (the next steps name their own field and app).
    static func movesFocusOnly(_ keys: String) -> Bool {
        ["tab", "shift+tab", "cmd+tab", "cmd+shift+tab", "cmd+`", "cmd+shift+`"].contains(keys)
    }
}
