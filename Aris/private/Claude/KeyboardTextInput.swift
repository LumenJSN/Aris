//
//  KeyboardTextInput.swift
//  Aris
//
//  Which first responder owns typed keys, for KeyboardFocus's Y/N monitor: only an editable text view (a text
//  field's editor, a text box). A read-only one, like Aris's selectable answer, doesn't, so
//  Y and N still answer a card next to it. And a Claude card takes keys only while its page is shown.
//

import AppKit

@MainActor
enum KeyboardTextInput {
    static func takesKeys(_ responder: NSResponder?) -> Bool {
        (responder as? NSText)?.isEditable == true
    }

    /// Whether a Claude card may take a key typed in the armed notch (Y/N on a tool approval; 1–9, arrows, ↩, Esc on a
    /// question): only while the notch shows the Claude page, where that card is, and no field is being typed in. On
    /// Aris's page (the composer) a Claude card waiting out of sight never takes what is typed (QA BUG-22).
    static func claudeCardTakesKeys(claudePageShown: Bool, responder: NSResponder?) -> Bool {
        claudePageShown && !takesKeys(responder)
    }

    /// How arming the keyboard for a card goes. A non-activating panel made key behind another app looks ready while
    /// Y and N go to that app, so hovering a card makes its panel key only while Aris is already active; the answer
    /// hotkey (the user's own press) brings Aris forward first, and arm(false) gives the keyboard back.
    struct Arm: Equatable {
        let makeKey: Bool
        let activate: Bool
    }

    static func arm(byHotkey: Bool, arisActive: Bool) -> Arm {
        byHotkey ? Arm(makeKey: true, activate: true) : Arm(makeKey: arisActive, activate: false)
    }

    /// A card's key (Y/N, 1–9, ↩, Esc) counts only while Aris is the active app.
    static func answersCardKey(arisActive: Bool) -> Bool { arisActive }
}
