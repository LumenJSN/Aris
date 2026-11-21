//
//  ArisTeachRecorder.swift
//  Shared/Core/Teach (aris-agent, tests, swift test)
//
//  The demonstration's recorder (ARCHITECTURE Part 3, F3): only between the owner's "start" and his "done" does it keep
//  anything. Each event passes the privacy rules first (ArisTeachPrivacy: a secure field, a password app, a card
//  number, Aris's own windows are left out, counted but never kept). Typing into one field is one change (the last
//  value wins), a focus that changes nothing is kept once, and a demonstration ends by itself when it runs too long or
//  holds too much, so it never goes on unseen. A value state machine: the helper feeds it, the tests feed it fake
//  event streams. Pure.
//  Only what the owner's own hand did to that very control is his (second VM run, defect 3): a field's value counts
//  when the field had the keyboard (it took focus, or his key went into it); a pop-up's choice, a checkbox or any other
//  control's change counts only right after his click on that control (a pop-up's menu may stay open a while). What an
//  app sets by itself (a new document's typeface, style, size and spacing controls) is dropped. And while Aris's own
//  window, notch or composer has the keyboard, nothing of any app is kept: what he types there (the stop phrase, ⌘A,
//  ⌘V, Return in the composer) is no step, and neither is what another app does meanwhile.
//

import Foundation

struct ArisTeachRecorder: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case idle
        case recording(name: String, started: Date)
    }

    /// Why an event was not kept.
    enum Dropped: String, Equatable, Sendable {
        case notRecording
        /// A secure field, a password app, a value shaped like a card number.
        case secret
        /// Aris's own window.
        case ownApp
        /// The demonstration holds the most it may; it should be ended.
        case full
        /// The demonstration has gone on past its longest; it should be ended.
        case tooLong
        /// Nothing new (a focus on the element already focused, an empty value).
        case nothing
        /// The app wasn't in front.
        case background
        /// A value or a selection with no owner input just before it in that app (the app or a page changed it).
        case unprompted
        /// The system's launchers and switchers (Spotlight, the Dock, the app switcher…) and the keys that call them up:
        /// how he got to an app, never a step (third VM run, D1).
        case launcher
    }

    /// What a finished demonstration hands on.
    struct Lesson: Equatable, Sendable {
        let name: String
        let events: [ArisTeachEvent]
        /// Secret fields and password-app events left out (the card says how many).
        let skipped: Int
        let started: Date
        let ended: Date
    }

    static let longest: TimeInterval = 15 * 60
    static let mostEvents = 400
    static let longestValue = 2_000
    /// What is kept of a text element's value (and its value before), so where the text went can be told; a step's
    /// text is cut to `longestValue`.
    static let longestKept = 100_000
    /// A value change or a selection is the owner's only this soon after his own key or click in that app.
    static let inputWindow: TimeInterval = 3
    /// A pop-up's choice is his this long after his click on that pop-up, with no other key or click in between: its
    /// menu may stay open while he reads it.
    static let choiceWindow: TimeInterval = 30
    /// A presence-only input (the hardware's idle time, a shortcut) this much after his key no longer leaves the value typed.
    static let handAfterKey: TimeInterval = 0.25
    /// Controls whose value is a choice from a menu.
    static let choiceRoles: Set<String> = ["popUpButton", "menuButton"]
    /// The menu bar and its menus: a menu opened (its title highlighted, a click on it) is no step; the item chosen in
    /// it comes as `menuChosen` (fourth VM run, D4), and a menu opened and closed with nothing chosen is nothing.
    static let menuRoles: Set<String> = ["menuBar", "menuBarItem", "menu", "menuItem"]

    private(set) var state: State = .idle
    private(set) var events: [ArisTeachEvent] = []
    /// Fields and password apps left out (each counted once).
    private(set) var skipped = 0
    /// The fields found secret during this lesson: nothing from them is kept, before or after.
    private(set) var secretFields: Set<String> = []
    /// The owner's last own key or click in each app (by bundle): when, which hand, and on which control.
    private(set) var lastInput: [String: LastInput] = [:]
    /// The owner's last presence in each app that names no control (the hardware's idle time).
    private(set) var lastHand: [String: Date] = [:]
    /// The control that has the keyboard in each app (its field key), as its last focus or key said.
    private(set) var focusedField: [String: String] = [:]
    /// Aris's own window, notch or composer has the keyboard: nothing of another app is kept until his hand is back there.
    private(set) var inAris = false
    /// The text fields his own character keys (or Return in a text area) went into during the lesson (their field keys).
    private(set) var typedFields: Set<String> = []
    /// His keys are heard one by one (the observer's key tap runs). Only then is a text change told from the app's own:
    /// without them, his presence alone (a click, the hardware's idle time) still makes a change his, as before.
    var keysHeard = false
    /// His last key or command in each app that edits text (a character key, Delete, Return in a text area, a paste,
    /// cut, undo or redo), and the field it went into when known. With `keysHeard`, a field's text change is his only
    /// right after one (seventh VM run, item 7: TextEdit's autocorrection of a word, taken at his double-click, became
    /// a typed step "Copyworb").
    private(set) var lastEdit: [String: LastInput] = [:]
    /// A paste in each app (⌘V and its variants, or the menu's Paste) with no key of his since: the text field's next
    /// change is what the paste put there, the paste's own result and never a typed step beside it (eighth VM run,
    /// item 1: "Edit › Paste" and a step typing the old clipboard were both saved, and the replay inserted both).
    private(set) var pasteWaiting: [String: Date] = [:]

    struct LastInput: Equatable, Sendable {
        let at: Date
        let input: ArisTeachEvent.Input
        /// The field that had focus for a key.
        var field: String?
    }

    var isRecording: Bool { if case .recording = state { return true } else { return false } }
    var name: String? { if case .recording(let name, _) = state { return name } else { return nil } }
    var started: Date? { if case .recording(_, let started) = state { return started } else { return nil } }

    init() {}

    /// Starts a demonstration named `name`; false when one is already under way (it keeps going).
    @discardableResult
    mutating func start(name: String, at: Date) -> Bool {
        guard !isRecording else { return false }
        state = .recording(name: name, started: at)
        events = []
        skipped = 0
        return true
    }

    /// The demonstration has run past its longest or is full: it should end now.
    func expired(at: Date) -> Bool {
        guard let started else { return false }
        return at.timeIntervalSince(started) > Self.longest || events.count >= Self.mostEvents
    }

    /// One event. Nil when it was kept; else why not.
    @discardableResult
    mutating func feed(_ event: ArisTeachEvent) -> Dropped? {
        guard let started else { return .notRecording }
        if event.at.timeIntervalSince(started) > Self.longest { return .tooLong }
        if ArisTeachPrivacy.isOwnApp(event.app) {
            // His hand in Aris itself (a key in the composer, a click on the notch): from now on until he is back in an
            // app, nothing is the lesson's.
            inAris = true
            return .ownApp
        }
        if ArisTeachLaunchers.isSystemUI(event.app) {
            // Spotlight, the Dock, the switcher: the key that called it up (⌘Space in the app before) goes too.
            if let last = events.last, last.kind == .shortcut, event.at.timeIntervalSince(last.at) <= ArisTeachLaunchers.summonGap,
               last.at <= event.at.addingTimeInterval(0.05) {
                events.removeLast()
            }
            return .launcher
        }
        guard event.frontmost else { return .background }
        if inAris {
            guard backInAnApp(event) else { return .ownApp }
            inAris = false
        }
        let bundle = event.app.bundle
        let field = event.element.map { ArisTeachPrivacy.fieldKey(event.app, $0) }
        if event.kind == .input {
            switch event.input {
            case .hand?: lastHand[bundle] = event.at
            case let input?:
                lastInput[bundle] = LastInput(at: event.at, input: input, field: field)
                if input == .key {
                    lastEdit[bundle] = LastInput(at: event.at, input: .key, field: field)
                    pasteWaiting[bundle] = nil
                }
                if input == .key, let field {
                    focusedField[bundle] = field
                    if event.element?.takesText == true { typedFields.insert(field) }
                }
            case nil: break
            }
            return nil
        }
        if event.kind == .focused, let field { focusedField[bundle] = field }
        if let element = event.element, secretFields.contains(ArisTeachPrivacy.fieldKey(event.app, element)) { return .secret }
        if let refusal = ArisTeachPrivacy.refusal(event) {
            if refusal == .secret { markSecret(event) }
            return refusal
        }
        guard events.count < Self.mostEvents else { return .full }
        var event = event
        if let value = event.value { event.value = String(value.prefix(Self.longestKept)) }
        if let before = event.before { event.before = String(before.prefix(Self.longestKept)) }
        switch event.kind {
        case .focused:
            guard let element = event.element else { return .nothing }
            // The same element focused again with nothing in between: nothing new.
            if let last = events.last, last.kind == .focused, last.app == event.app, last.element.map({ $0.same(as: element) }) == true { return .nothing }
        case .valueChanged:
            guard let element = event.element else { return .nothing }
            guard ownersOwn(event) else { return .unprompted }
            // The hint: a character key pressed in this very field, and no paste or other hand after it. Never trusted for anything.
            event.typed = typedHere(event, element: element)
            if element.takesText, let paste = pasteWaiting.removeValue(forKey: bundle), Self.soon(paste, event.at, within: Self.inputWindow) {
                event.pasted = true
            }
            // Typing into one field is one change: the last value of a run of changes to the same field wins (a focus
            // on that same field in between changes nothing). A checkbox's changes each count.
            // A paste's result and his typing are never one change.
            if element.takesText, let index = lastChange(of: event), (events[index].pasted ?? false) == (event.pasted ?? false) {
                // One stretch of typing: its first value before, its last value after; and where its run sits now.
                events[index].run = events[index].run.flatMap { $0.after(old: events[index].value ?? "", new: event.value ?? "", caret: event.caret) }
                events[index].value = event.value
                events[index].at = event.at
                // Any change of the run the app may have made makes the whole value the app's.
                events[index].typed = (events[index].typed ?? false) && event.typed == true
                // Whether he typed over a selection is told by the stretch's first change (the selection before his
                // first key), never by a later one.
                return nil
            }
            // A new stretch: the one character its first change put in, when it was just that.
            if element.takesText, event.pasted != true, let before = event.before, let value = event.value, value.count == before.count + 1 {
                let typed = ArisTeachGeneralise.textChange(before: before, after: value).text
                if typed.count == 1 { event.began = typed }
            }
            if element.takesText, event.pasted != true, let before = event.before {
                event.run = ArisTeachRun.none.after(old: before, new: event.value ?? "", caret: event.caret)
            }
        case .menuChosen:
            guard let menu = event.menu, !menu.isEmpty, menu.allSatisfy({ !$0.isEmpty }) else { return .nothing }
            // His hand chose it (the mouse, or its key equivalent): he is there, in that app.
            lastInput[bundle] = LastInput(at: event.at, input: .hand, field: field)
            if Self.editsText(menu: menu, keys: event.keys) { lastEdit[bundle] = LastInput(at: event.at, input: .hand, field: field) }
            pasteWaiting[bundle] = Self.pastes(menu: menu, keys: event.keys) ? event.at : nil
        case .shortcut:
            guard let keys = event.keys, !keys.isEmpty else { return .nothing }
            let normal = ArisTeachGeneralise.normalisedKeys(keys)
            // A key that only calls up a launcher or switches apps: how he gets somewhere, never a step.
            if ArisTeachLaunchers.keys.contains(normal) { return .launcher }
            // Return in a document's text (a multi-line text area) is part of what he types there, not a key step;
            // Return in a one-line field, a search box or a dialog stays a step.
            if Self.typesNewline(normal), let element = event.element, element.role == "textArea", let field {
                lastInput[bundle] = LastInput(at: event.at, input: .key, field: field)
                lastEdit[bundle] = LastInput(at: event.at, input: .key, field: field)
                focusedField[bundle] = field
                typedFields.insert(field)
                pasteWaiting[bundle] = nil
                return nil
            }
            // A shortcut (a paste, Return) shows the owner was there, in the control that has the keyboard; it is
            // never typing, and it ends a pop-up's wait for its choice.
            lastInput[bundle] = LastInput(at: event.at, input: .hand, field: field)
            if Self.editsText(keys: normal) { lastEdit[bundle] = LastInput(at: event.at, input: .hand, field: field) }
            pasteWaiting[bundle] = Self.pasteKeys.contains(normal) ? event.at : nil
        case .appActivated:
            // The same app again, with nothing in between: nothing new.
            if let last = events.last, last.kind == .appActivated, last.app == event.app { return .nothing }
            dropFinderOpen(of: event)
        case .selected:
            if let element = event.element, Self.menuRoles.contains(element.role) { return .nothing }
            guard ownersOwn(event) else { return .unprompted }
        case .pressed:
            lastInput[bundle] = LastInput(at: event.at, input: .click, field: field)
            // A click on a pop-up only opens its menu: the choice in it is the step.
            if let element = event.element, Self.choiceRoles.contains(element.role) { return .nothing }
        case .windowOpened, .input:
            break
        }
        events.append(event)
        return nil
    }

    /// Return as typing ("return", "shift+return", "opt+return": a new line in a text area).
    static func typesNewline(_ keys: String) -> Bool { ["return", "shift+return", "opt+return"].contains(keys) }

    /// ⌘V and its variants (paste and match style, paste without formatting).
    static let pasteKeys: Set<String> = ["cmd+v", "cmd+shift+v", "cmd+opt+v", "cmd+opt+shift+v"]
    /// The menu's paste commands, by their name's start (English, and the Korean name macOS gives them).
    static let pasteNames = ["paste", "붙여넣기"]
    /// ⌘ keys that change a field's text: paste (and its variants), cut, undo, redo, delete to the line's start.
    static let commandEdits: Set<String> = pasteKeys.union(["cmd+x", "cmd+z", "cmd+shift+z", "cmd+delete"])

    /// A menu item chosen that pastes: by its key equivalent when it came by one, else by its name.
    static func pastes(menu: [String], keys: String?) -> Bool {
        if let keys, !keys.isEmpty { return pasteKeys.contains(ArisTeachGeneralise.normalisedKeys(keys)) }
        let item = (menu.last ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        return pasteNames.contains { item.hasPrefix($0) }
    }
    /// Menu items that change a field's text, by their name's start (English, and the Korean names macOS gives them).
    static let menuEdits = ["paste", "cut", "undo", "redo", "delete", "붙여넣기", "오려두기", "잘라내기", "실행 취소", "실행 복귀", "삭제"]

    /// A key that edits text: one with no ⌘ (⌥ and ⌃ keys type or edit: é, ⌃K), or one of `commandEdits`.
    static func editsText(keys: String) -> Bool {
        let normal = ArisTeachGeneralise.normalisedKeys(keys)
        return !normal.split(separator: "+").contains("cmd") || commandEdits.contains(normal)
    }

    /// A menu item chosen that edits text: by its key equivalent when it came by one, else by its name.
    static func editsText(menu: [String], keys: String?) -> Bool {
        if let keys, !keys.isEmpty, commandEdits.contains(ArisTeachGeneralise.normalisedKeys(keys)) { return true }
        let item = (menu.last ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        return menuEdits.contains { item.hasPrefix($0) || (item.unicodeScalars.contains { $0.value >= 0xAC00 } && item.contains($0)) }
    }

    /// An app came up right after he opened its item in Finder (a double-click, ⌘O, ⌘↓): opening it from Finder is how
    /// he got there, not a step; the app's own "open" stands for it.
    private mutating func dropFinderOpen(of event: ArisTeachEvent) {
        let target = ArisTeachLaunchers.appName(event.app.name)
        guard !target.isEmpty else { return }
        var index = events.count - 1
        var found: Int?
        while index >= 0, events[index].app.bundle == "com.apple.finder", event.at.timeIntervalSince(events[index].at) <= ArisTeachLaunchers.finderOpenGap {
            let kept = events[index]
            if [.pressed, .selected].contains(kept.kind), let element = kept.element,
               ArisTeachLaunchers.appName(element.label) == target || ArisTeachLaunchers.appName(element.name) == target {
                found = index
            }
            index -= 1
        }
        if let found { events.removeSubrange(found...) }
    }

    /// The values read from the text elements his keys went into, when the lesson ended (`readAtEnd`): each stands for
    /// typing in a field whose changes weren't reported while he typed (third VM run, D1: TextEdit, launched through
    /// Spotlight, wasn't observed yet when "lesson line one" was typed, and the lesson lost it). Kept only for a field he
    /// typed into, with nothing of it kept already, by the same privacy rules, at the time of his last key there.
    mutating func close(_ read: [ArisTeachEvent]) {
        guard isRecording else { return }
        for event in read {
            guard event.kind == .valueChanged, let element = event.element, element.takesText, let value = event.value, !value.isEmpty else { continue }
            let field = ArisTeachPrivacy.fieldKey(event.app, element)
            guard typedFields.contains(field), !secretFields.contains(field), ArisTeachPrivacy.refusal(event) == nil else { continue }
            let kept = events.contains { earlier in
                guard earlier.kind == .valueChanged, let other = earlier.element else { return false }
                return ArisTeachPrivacy.fieldKey(earlier.app, other) == field
            }
            guard !kept, events.count < Self.mostEvents else { continue }
            var made = event
            made.value = String(value.prefix(Self.longestKept))
            made.before = event.before.map { String($0.prefix(Self.longestKept)) }
            made.readAtEnd = true
            made.typed = true
            // Read once, at the end: where the caret is now is where his typing ended.
            made.run = made.before.flatMap { ArisTeachRun.none.after(old: $0, new: made.value ?? "", caret: event.caret) }
            let at = events.firstIndex { $0.at > event.at } ?? events.count
            events.insert(made, at: at)
        }
    }

    /// Whether `at` is within `window` after `earlier` (a moment's clock skew allowed).
    private static func soon(_ earlier: Date?, _ at: Date, within window: TimeInterval) -> Bool {
        guard let earlier else { return false }
        let gap = at.timeIntervalSince(earlier)
        return gap >= -0.05 && gap <= window
    }

    /// Whether a value change or a selection is the direct result of the owner's own hand on that very control:
    /// - a field's value: his key or click in the app just before, and the field had the keyboard (it took focus, or
    ///   his key went into it);
    /// - a pop-up's choice (or its value): his click on that pop-up, with no other key or click since;
    /// - any other control's value (a checkbox, a slider): his click on it just before;
    /// - a row's or a tab's selection: his key or click in the app just before.
    private func ownersOwn(_ event: ArisTeachEvent) -> Bool {
        let bundle = event.app.bundle
        let last = lastInput[bundle]
        guard let element = event.element else {
            return Self.soon(last?.at, event.at, within: Self.inputWindow) || Self.soon(lastHand[bundle], event.at, within: Self.inputWindow)
        }
        let field = ArisTeachPrivacy.fieldKey(event.app, element)
        let clickedHere = last.map { $0.input == .click && ($0.field == nil || $0.field == field) } ?? false
        if Self.choiceRoles.contains(element.role) {
            return clickedHere && Self.soon(last?.at, event.at, within: Self.choiceWindow)
        }
        if element.takesText {
            let present = Self.soon(last?.at, event.at, within: Self.inputWindow) || Self.soon(lastHand[bundle], event.at, within: Self.inputWindow)
            guard present && (focusedField[bundle] == field || last?.field == field) else { return false }
            // With his keys heard: a change no key or command of his that edits text came just before is the app's own
            // (an autocorrection or a completion taken at a click), never his typing.
            guard keysHeard else { return true }
            guard let edit = lastEdit[bundle], Self.soon(edit.at, event.at, within: Self.inputWindow) else { return false }
            return edit.field == nil || edit.field == field
        }
        if event.kind == .valueChanged {
            return clickedHere && Self.soon(last?.at, event.at, within: Self.inputWindow)
        }
        return Self.soon(last?.at, event.at, within: Self.inputWindow) || Self.soon(lastHand[bundle], event.at, within: Self.inputWindow)
    }

    /// The display hint: his last input in the app was a character key in this very field, with no paste or other
    /// presence-only hand well after it.
    private func typedHere(_ event: ArisTeachEvent, element: ArisTeachElement) -> Bool {
        guard let last = lastInput[event.app.bundle], last.input == .key, last.field == ArisTeachPrivacy.fieldKey(event.app, element) else { return false }
        if let hand = lastHand[event.app.bundle], hand.timeIntervalSince(last.at) > Self.handAfterKey { return false }
        return true
    }

    /// His hand is back in an app after Aris had the keyboard: an app came to the front, or his own key, click or
    /// shortcut went into it. What an app does by itself (a focus, a value) while Aris has the keyboard is not that.
    private func backInAnApp(_ event: ArisTeachEvent) -> Bool {
        switch event.kind {
        case .appActivated, .pressed, .shortcut: return true
        case .input: return event.input == .key || event.input == .click
        // A menu command chosen by its key equivalent is his shortcut, pressed in the app that had the keyboard (the
        // observer tells a shortcut as its command): his hand is back as much as with any other shortcut (sixth VM run,
        // items 7a and 7c: ⌘A, and a ⌘C-only lesson, right after the lesson was started in Aris's composer were left out).
        case .menuChosen: return event.keys?.isEmpty == false
        case .focused, .valueChanged, .selected, .windowOpened: return false
        }
    }

    /// A secret seen: its field (or its password app) is left out from now on, and what was already kept from that
    /// field goes. Only a real secret field (a text field or a secure one) or a password app is counted for the card's
    /// "left out" line (fourth VM run, D6: "1 password or secret field" after a lesson with none, from a control that
    /// wasn't a field at all).
    private mutating func markSecret(_ event: ArisTeachEvent) {
        let wholeApp = ArisTeachPrivacy.isPasswordApp(event.app) || event.element == nil
        let key = wholeApp ? "app\u{1F}" + event.app.bundle : ArisTeachPrivacy.fieldKey(event.app, event.element!)
        guard secretFields.insert(key).inserted else { return }
        if ArisTeachPrivacy.isPasswordApp(event.app) || event.element.map(ArisTeachPrivacy.isField) == true { skipped += 1 }
        guard !wholeApp else { return }
        events.removeAll { kept in
            guard kept.app == event.app, let element = kept.element else { return false }
            return ArisTeachPrivacy.fieldKey(kept.app, element) == key
        }
    }

    /// The change of the same element this one continues: the last event, or the last before a focus on that element.
    private func lastChange(of event: ArisTeachEvent) -> Int? {
        guard let element = event.element else { return nil }
        var index = events.count - 1
        while index >= 0 {
            let earlier = events[index]
            guard earlier.app == event.app, let other = earlier.element, other.same(as: element) else { return nil }
            if earlier.kind == .valueChanged { return index }
            guard earlier.kind == .focused else { return nil }
            index -= 1
        }
        return nil
    }

    /// Ends the demonstration and hands on what was kept; nil when none was under way.
    mutating func stop(at: Date) -> Lesson? {
        guard case .recording(let name, let started) = state else { return nil }
        let lesson = Lesson(name: name, events: events, skipped: skipped, started: started, ended: at)
        self = ArisTeachRecorder()
        return lesson
    }

    /// Drops the demonstration and everything it kept.
    mutating func cancel() {
        self = ArisTeachRecorder()
    }
}
