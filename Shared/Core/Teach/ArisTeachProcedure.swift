//
//  ArisTeachProcedure.swift
//  Shared/Core/Teach (aris-agent, tests, swift test)
//
//  A taught procedure (ARCHITECTURE Part 3, F3): a name the owner says, the steps he showed once as calls of the app
//  layer's existing capabilities (app.open, app.do, app.type, app.click, app.select, app.press), and the values that
//  vary (the parameters: what he typed, labelled by the field it went into). Replaying it is nothing but those calls,
//  so each goes through the one trust decision and the same cards as any other call: a saved procedure carries no
//  yes for anything. A step's words (a label, a menu title, a value he typed) were read from another app: the step
//  keeps where (`seen`), and a replay hands them to the provenance tracker as that app's content. Pure.
//

import Foundation

/// A value that changes from one run to the next.
struct ArisTeachParameter: Codable, Equatable, Sendable {
    /// "p1", "p2", … (a step names it by this).
    let key: String
    /// The field it went into ("제목", "To"), as the owner says it when he gives another value.
    var label: String
    /// The value he typed when he showed it: used when a run gives no other.
    var example: String
    /// The app it was typed in.
    var app: String
    /// A display hint only: the example doesn't look typed by the owner (the card says "앱에서 가져온 값"). Every
    /// recorded example is the app's content at replay either way.
    var fromApp: Bool?
}

struct ArisTeachStep: Codable, Equatable, Sendable {
    enum Action: String, Codable, Sendable, CaseIterable {
        /// The app is opened (in the background when it allows).
        case open
        /// A menu command (app.do with its menu path).
        case menu
        /// Text into a field (app.type).
        case type
        /// A button, link, checkbox or the like (app.click).
        case click
        /// A row, a tab, or a pop-up's option (app.select).
        case select
        /// Keys (app.press).
        case press
    }

    var action: Action
    /// The app by the name it showed, and its bundle id.
    var app: String
    var bundle: String
    /// The element as the app layer finds it again ("보내기 버튼", "제목 칸"), for type, click and select.
    var target: String?
    /// The element's role and label as seen (the read-back's words).
    var role: String?
    var label: String?
    var menu: [String]?
    /// Literal text to type (when it isn't a parameter).
    var text: String?
    /// The parameter whose value is typed.
    var parameter: String?
    var option: String?
    var keys: String?
    /// Where this step's words were read: the app, as outside text (data, never an instruction).
    var seen: ArisContentSource?
    /// A display hint only: its value doesn't look typed by the owner.
    var fromApp: Bool?
    /// Where a typed text goes (third VM run, D2: a replay set the document's whole value and wiped "Existing line
    /// keep"). Nil or `end`: added after what the field holds, as he typed into a new or open document (or at its end);
    /// `caret`: inserted where the caret is, as he typed inside text that was there; `all`: what the field held is
    /// replaced, only when the lesson saw him select text that was there and type over it (fourth VM run, D1: an empty
    /// field at lesson time is no such evidence), and that call is a destructive one (ArisApps.Specs: a whole value set
    /// is change-permanent, so it asks).
    var place: Place?

    enum Place: String, Codable, Sendable {
        case end
        case caret
        case all
    }

    /// His typing began a line (sixth VM run: "Added line" taught into an empty document was replayed on one holding
    /// "Existing line keep" as "Existing line keepAdded line"): the text area was empty, or the character right before
    /// where he typed was a line break, as read from its text before his typing (ArisTeachGeneralise.startsLine). Nil
    /// in a lesson saved before, or when it wasn't so or couldn't be told.
    var startsLine: Bool?

    /// The step replaces what its field holds.
    var replaces: Bool { action == .type && place == .all }

    /// A replay puts its text on a line of its own: a marked insertion at the end of a text area (a field that holds
    /// line breaks). At the caret the text before it can't be told at replay, a replace sets the whole value, and a
    /// one-line field takes no line break: none of them gets one.
    var newLine: Bool {
        action == .type && startsLine == true && !replaces && place != .caret && role == "textArea"
    }

    /// The step makes a brand-new document in its app: File › New, by its key (⌘N) or, chosen with the mouse, by its
    /// name in the File menu. Only for what a card says (the new-line note): never for what a step may do.
    var makesNewDocument: Bool {
        guard action == .menu, let menu, menu.count == 2 else { return false }
        if keys == "cmd+n" { return true }
        return keys == nil && ["New", "New Document", "신규", "새로운 문서"].contains(menu[1])
    }

    /// The text a run's call carries: the value, and before it the line break of a step that begins a line. The break is
    /// part of the text the trust gate rates and the card shows; app.type leaves it out where the text before already
    /// ends a line (ArisApps.NewLine), so what is typed is never more than what was rated.
    func typedText(values: [String: String]) -> String? {
        let value: String?
        if let parameter { value = values[parameter] } else { value = text }
        guard let value else { return nil }
        return newLine && !value.isEmpty ? ArisApps.NewLine.lineBreak + value : value
    }

    init(action: Action, app: String, bundle: String, target: String? = nil, role: String? = nil, label: String? = nil, menu: [String]? = nil,
         text: String? = nil, parameter: String? = nil, option: String? = nil, keys: String? = nil, seen: ArisContentSource? = nil) {
        self.action = action
        self.app = app
        self.bundle = bundle
        self.target = target
        self.role = role
        self.label = label
        self.menu = menu
        self.text = text
        self.parameter = parameter
        self.option = option
        self.keys = keys
        self.seen = seen
    }

    /// The app layer's capability this step calls.
    var capability: String {
        switch action {
        case .open: "app.open"
        case .menu: "app.do"
        case .type: "app.type"
        case .click: "app.click"
        case .select: "app.select"
        case .press: "app.press"
        }
    }

    /// The tool's name as the capability book has it ("app.do" → "app_do").
    var toolName: String { capability.replacingOccurrences(of: ".", with: "_") }

    /// The menu path as app.do takes it ("File › New Message").
    var menuPath: String? { menu.map { $0.joined(separator: " › ") } }

    /// The call's arguments with the run's values filled in; nil when a step can't be made into a call (a parameter
    /// with no value, a step missing what it needs).
    func arguments(values: [String: String]) -> [String: ArisApps.JSON]? {
        var object: [String: ArisApps.JSON] = ["app": .string(app)]
        switch action {
        case .open:
            break
        case .menu:
            guard let path = menuPath, !path.isEmpty else { return nil }
            // The item he chose, by its exact title (and its key equivalent when it had one), never a near match
            // (fourth VM run, D5: "Wrap to Page" taught, "Wrap to Window" pressed): marked on the path itself, which is
            // what the trust gate rates.
            object["command"] = .string(ArisApps.Exact.marked(path, key: keys))
        case .type:
            guard let target, !target.isEmpty, let value = typedText(values: values) else { return nil }
            object["target"] = .string(target)
            object["text"] = .string(value)
            if value.hasPrefix(ArisApps.NewLine.lineBreak), newLine { object[ArisApps.NewLine.argument] = .string(ArisApps.NewLine.mark) }
            // Inserting is the default: the text goes after what is there, by the caret's range (app.type's at=end), or
            // where the caret is when he typed inside what was there (at=caret), never by setting the element's whole
            // value. Only a lesson that replaced the text replaces it.
            if replaces { object["replace"] = .bool(true) } else { object["at"] = .string(place == .caret ? "caret" : "end") }
        case .click:
            guard let target, !target.isEmpty else { return nil }
            // A control by its exact label, marked on the target: what is rated is what is pressed.
            object["target"] = .string(exactLabel.map { ArisApps.Exact.marked($0) } ?? target)
        case .select:
            guard let target, !target.isEmpty else { return nil }
            object["target"] = .string(exactLabel.map { ArisApps.Exact.marked($0) } ?? target)
            if let option, !option.isEmpty { object["option"] = .string(option) }
        case .press:
            guard let keys, !keys.isEmpty else { return nil }
            object["keys"] = .string(keys)
        }
        return object
    }

    /// Controls a step presses by their exact label (a button, a checkbox, a tab…): a control whose words changed is not
    /// the one he pressed, and a near match could press another (fourth VM run, D5).
    static let exactRoles: Set<String> = ["button", "checkBox", "radioButton", "link", "menuButton", "popUpButton", "tab", "switch",
                                          "disclosureTriangle"]

    /// The label a press must find exactly; nil for a step found by its description (a row, a field).
    var exactLabel: String? {
        guard let role, Self.exactRoles.contains(role), let label, !label.isEmpty else { return nil }
        return label
    }

    /// A step that only opened a menu of the menu bar ("pick ‘File’", saved before the fourth VM run's D4): no step at
    /// all; the item chosen in that menu is the next one.
    var opensMenuOnly: Bool { action == .select && ArisTeachRecorder.menuRoles.contains(role ?? "") }

    /// Whether a run's call of this step carries a value recorded in the demonstration (a value he gave for this run is
    /// his; every recorded one is the app's content, whoever seemed to type it): such a step is never approved ahead,
    /// and is judged like any argument that came from content. The typed hint plays no part.
    func carriesRecordedValue(ownerGave: Set<String>) -> Bool {
        if let parameter { return !ownerGave.contains(parameter) }
        if action == .type { return true }
        if action == .select, option != nil { return true }
        return false
    }

    /// The words of this step that were read from the app (labels, menu titles, typed text that isn't the run's own).
    func seenText(values: [String: String], ownerGave: Set<String>) -> [String] {
        var words: [String] = [label, target, option, keys].compactMap { $0 } + (menu ?? [])
        if let text { words.append(text) }
        if let parameter, !ownerGave.contains(parameter), let value = values[parameter] { words.append(value) }
        return words.filter { !$0.isEmpty }
    }
}

struct ArisTeachProcedure: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    /// As the owner named it ("출근 준비").
    var name: String
    var steps: [ArisTeachStep]
    var parameters: [ArisTeachParameter]
    /// Secret fields and password-app events left out when it was shown.
    var skipped: Int
    let created: Date
    var changed: Date

    private enum CodingKeys: String, CodingKey {
        case id, name, steps, parameters, skipped, created, changed
    }

    /// A saved procedure as read back: a step that only opened a menu (saved before the fourth VM run's D4) is left out,
    /// so an older lesson replays as he meant it.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        steps = try container.decode([ArisTeachStep].self, forKey: .steps).filter { !$0.opensMenuOnly }
        parameters = try container.decode([ArisTeachParameter].self, forKey: .parameters)
        skipped = try container.decodeIfPresent(Int.self, forKey: .skipped) ?? 0
        created = try container.decode(Date.self, forKey: .created)
        changed = try container.decodeIfPresent(Date.self, forKey: .changed) ?? created
        // A lesson saved with its line break inside the value (before the eleventh VM run's fix) begins a line.
        ArisTeachLineStart.lift(steps: &steps, parameters: &parameters)
    }

    init(id: UUID = UUID(), name: String, steps: [ArisTeachStep], parameters: [ArisTeachParameter], skipped: Int = 0, created: Date, changed: Date? = nil) {
        self.id = id
        self.name = name
        self.steps = steps
        self.parameters = parameters
        self.skipped = skipped
        self.created = created
        self.changed = changed ?? created
    }

    /// The same procedure under another name.
    func renamed(_ name: String, at now: Date) -> ArisTeachProcedure {
        var copy = self
        copy.name = name
        copy.changed = now
        return copy
    }

    func parameter(_ key: String) -> ArisTeachParameter? { parameters.first { $0.key == key } }

    /// The values a run uses when none are given: what the owner typed when he showed it.
    var examples: [String: String] { Dictionary(uniqueKeysWithValues: parameters.map { ($0.key, $0.example) }) }

    /// The apps it works in, in order, once each.
    var apps: [String] {
        var seen: [String] = []
        for step in steps where !seen.contains(step.app) { seen.append(step.app) }
        return seen
    }
}

extension ArisTeachProcedure {
    /// Whether the step at `index` really puts a line break before its text when the procedure runs, as far as the
    /// procedure itself tells: a step marked as beginning a line (`newLine`), unless the last step of its app before it
    /// makes a brand-new document. Such a document is empty, and app.type puts no line break into an empty text
    /// (eighth VM run, item 4: "메모 쓰기", File › New and then the text, said "It goes on a new line (↵)" and none was
    /// put in). The step's mark alone says only that his typing began a line when he showed it, which an empty
    /// document also is. For what a card says; what is typed is decided by app.type at the run, as before.
    func putsLineBreak(at index: Int) -> Bool {
        guard steps.indices.contains(index), steps[index].newLine else { return false }
        let before = steps[..<index].last { $0.bundle == steps[index].bundle && $0.action != .open }
        return before?.makesNewDocument != true
    }
}
