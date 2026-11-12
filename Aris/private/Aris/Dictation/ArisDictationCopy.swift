//
//  ArisDictationCopy.swift
//  Aris
//
//  Dictation with nowhere to type (the owner's pick B with the 3-line fold, mockups/dictation-copy): when aris-agent's ⌘V
//  was read by no app (no field had the keyboard) or the insert failed, the words go on the clipboard and the notch
//  says so ("입력할 곳이 없어서 복사해 뒀어요 · ⌘V로 붙여 넣으세요"), with the words card folded to three lines and a
//  "다시 복사" button that shows "복사했어요 ✓" for 1.5 s. Words that went in are never copied. The decision is the
//  insert's own outcome (the paste-confirmed signal), not a guess at focus. Pure, so it's tested.
//

import Foundation

/// What aris-agent's /insert said.
enum ArisInsertOutcome: Equatable {
    /// Typed; `confirmed`: the app read the paste (else no app took it: nowhere to type).
    case typed(confirmed: Bool)
    case failed(String)
    /// aris-agent wouldn't press ⌘V because it has no Accessibility switch of its own (ArisHelperRow): the one
    /// failure the user can fix, so it is said as such and not as "nowhere to type".
    case helperOff

    /// The agent's word for its own Accessibility in `needs` (ArisInsertRefusal; the tests hold the two equal).
    static let needsAccessibility = "accessibility"

    /// What /insert's answer means. The agent names what it lacks in `needs`; its sentence is for the log.
    static func read(status: Int, reply: [String: Any]) -> ArisInsertOutcome {
        guard status != 200 else { return .typed(confirmed: reply["confirmed"] as? Bool ?? true) }
        if reply["needs"] as? String == needsAccessibility { return .helperOff }
        return .failed(reply["error"] as? String ?? "couldn't type it")
    }
}

enum ArisDictationCopy {
    enum Landing: Equatable {
        /// In the field: nothing more to do.
        case inserted
        /// No app took the paste, or it couldn't be typed: the words go on the clipboard.
        case nowhere
    }

    static func landing(_ outcome: ArisInsertOutcome) -> Landing {
        outcome == .typed(confirmed: true) ? .inserted : .nowhere
    }

    /// Only words that didn't go in are copied.
    static func copies(_ outcome: ArisInsertOutcome) -> Bool { landing(outcome) == .nowhere }

    /// "복사했어요 ✓" after 다시 복사, as variant A's button.
    static let feedback: Duration = .milliseconds(1500)
    /// How long the copied card stays before the notch closes (longer while the pointer is on it).
    static let linger: Duration = .seconds(4)
    /// Long words fold to this many lines.
    static let lineLimit = 3

    enum Toggle: Equatable { case more, less }

    /// The words card's fold: whole when the words fit in three lines; else folded with 더 보기, or open with 접기.
    struct Fold: Equatable {
        /// The words run past three lines at the card's width.
        var overflows: Bool
        var open = false

        var lineLimit: Int? { overflows && !open ? ArisDictationCopy.lineLimit : nil }
        var toggle: Toggle? { overflows ? (open ? .less : .more) : nil }

        func toggled() -> Fold { overflows ? Fold(overflows: true, open: !open) : self }
    }

    /// The card's type: 15 points, 4 between lines.
    static let fontSize: CGFloat = 15
    static let lineSpacing: CGFloat = 4

    // MARK: - Words (Localizable.xcstrings, dictation.copy.*)

    static let languages: Set<String> = ["ko", "en"]

    /// The language, chosen once: the app's one UI language (ArisUILanguage).
    nonisolated(unsafe) static var language: String = ArisUILanguage.code
    nonisolated(unsafe) static var bundle: Bundle = lproj(language, in: .main)

    static func lproj(_ language: String, in bundle: Bundle) -> Bundle {
        bundle.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? bundle
    }

    static var locale: Locale { Locale(identifier: language) }

    /// Picks the language again (the tests and offscreen renders).
    static func use(_ code: String, in main: Bundle = .main) {
        language = code
        bundle = lproj(code, in: main)
    }

    static var tag: String { String(localized: "dictation.copy.tag", defaultValue: "Nowhere to type, so it's copied · Paste with ⌘V", bundle: bundle, locale: locale, comment: "Dictation with no text field: the notch's tag, the words are on the clipboard") }
    static var again: String { String(localized: "dictation.copy.again", defaultValue: "Copy again", bundle: bundle, locale: locale, comment: "Dictation with no text field: puts the words on the clipboard again") }
    static var done: String { String(localized: "dictation.copy.done", defaultValue: "Copied", bundle: bundle, locale: locale, comment: "Dictation with no text field: the button for 1.5 s after copying again") }
    static var more: String { String(localized: "dictation.copy.more", defaultValue: "Show more", bundle: bundle, locale: locale, comment: "Dictation with no text field: unfolds long words") }
    static var less: String { String(localized: "dictation.copy.less", defaultValue: "Show less", bundle: bundle, locale: locale, comment: "Dictation with no text field: folds long words to three lines") }

    static func label(_ toggle: Toggle) -> String { toggle == .more ? more : less }
}
