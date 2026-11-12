//
//  ArisStoppedCopy.swift
//  Aris
//
//  The words of the automatic check's stopped card (ArisStoppedCard), of its one settled line and of the "확인함" mark,
//  Korean and English, in the language the card is drawn in. Foundation only, so the tests read them.
//

import Foundation

/// The card's and the mark's words, in the language the card is drawn in.
enum ArisStoppedCopy {
    static func anyway(english: Bool) -> String { english ? "Do it anyway" : "그래도 하기" }
    static func skip(english: Bool) -> String { english ? "Don't" : "하지 않기" }
    static func skipped(english: Bool) -> String { english ? "Not done" : "하지 않았어요" }
    static func checked(english: Bool) -> String { english ? "Checked" : "확인함" }
    static func checkedHelp(english: Bool) -> String {
        english ? "Aris checked that this was what you asked before doing it" : "시킨 일이 맞는지 Aris가 확인하고 했어요"
    }
    /// Said aloud when the card comes up: the sentence, and that nothing was done.
    static func spoken(_ title: String, english: Bool) -> String {
        english ? "\(title) Nothing was done." : "\(title) 아무것도 하지 않았어요."
    }

    /// The label beside the action's name on the card.
    static func aboutTo(english: Bool) -> String { english ? "Was about to" : "하려던 일" }

    /// What was about to happen, in the gate's own fixed words ("할 일에 넣기"): the first line of the card's details
    /// (aris-agent's ArisAutoCard.detail), for the card's one row and the settled line's note.
    static func action(of question: ArisConfirmation) -> String {
        question.detail.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    }

    /// The action's own text: every line after the first, exactly as it came. It may be words anyone wrote (a page's,
    /// a mail's), so the card shows it as one quoted block and never reads a line of it as a row, a label or a button.
    static func quoted(of question: ArisConfirmation) -> String {
        question.detail.split(whereSeparator: \.isNewline).dropFirst().joined(separator: "\n")
    }
}
