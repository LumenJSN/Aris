//
//  ArisPromptEdit.swift
//  Aris
//
//  Editing a request already sent: a 22-point pencil comes up on the sent-prompt card under the pointer; a press on
//  it (or on a card short enough not to collapse) turns the card into its own editor, the words in place with the
//  caret at their end. Return sends what is there, Esc or closing the notch throws the edit away, and an emptied card
//  sends nothing. What Return sends is a new typed turn in the same conversation, by Aris's own typed path
//  (ArisController.submitTyped: the same gate and the same cards as any request); the turn on screen is replaced by
//  it (its answer and cards are cleared), and nothing the first request did is taken back. Because nothing is taken
//  back, the card says so while it is edited whenever the first request already did something. No pencil while Aris
//  listens, while a card waits for an answer (an edit must never stand in for a yes or a no), or on words that went
//  with files or circled shots (the resend would leave them behind). Foundation only, so the states and what is
//  resent are tested.
//

import CoreGraphics
import Foundation

enum ArisPromptEdit {
    /// The pencil: a 22 × 22 circle 16 from the card's top and 10 from its right, rgba(28, 28, 32, .92), a
    /// 12-point glyph at white 90 %.
    static let pencilSize: CGFloat = 22
    static let pencilTop: CGFloat = 16
    static let pencilTrailing: CGFloat = 10
    static let pencilGlyph: CGFloat = 12
    static let pencilFill: (red: Double, green: Double, blue: Double, alpha: Double) = (28 / 255, 28 / 255, 32 / 255, 0.92)

    /// The turn as the card sees it.
    struct Turn: Equatable {
        var phase: ArisSession.Phase
        /// The user's words as the card shows them.
        var words: String
        /// The card shows a hint in their place ("듣고 있어요…").
        var placeholder = false
        /// A confirm card (or any card that waits for an answer) is up.
        var cardWaiting = false
        /// The words went with files given to Aris, or with circled shots.
        var carriesFiles = false
        var carriesShots = false
        /// The first request already did something: a step of its finished, or it left a receipt.
        var didSomething = false
    }

    enum Why: Equatable { case listening, placeholder, cardWaiting, carriesFiles, carriesShots, noWords }

    enum Offer: Equatable {
        /// `saysDone`: while edited, the card says that what the first request did stays done.
        case editable(saysDone: Bool)
        case no(Why)

        var isEditable: Bool { if case .editable = self { true } else { false } }
    }

    static func offer(_ turn: Turn) -> Offer {
        if turn.cardWaiting { return .no(.cardWaiting) }
        if turn.phase == .listening { return .no(.listening) }
        if turn.placeholder { return .no(.placeholder) }
        if turn.words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .no(.noWords) }
        if turn.carriesFiles { return .no(.carriesFiles) }
        if turn.carriesShots { return .no(.carriesShots) }
        return .editable(saysDone: turn.didSomething)
    }

    /// A press on the card itself: a card long enough to collapse opens and folds, as before; a shorter one becomes
    /// its editor when it can.
    enum Tap: Equatable { case toggles, edits, nothing }

    static func tap(lines: Int, offer: Offer) -> Tap {
        if lines > ArisPromptCollapse.collapsedLines { return .toggles }
        return offer.isEditable ? .edits : .nothing
    }

    /// What Return does with the draft.
    enum Send: Equatable {
        /// Nothing left in the card: the edit is thrown away and nothing is sent.
        case discard
        /// The trimmed words go as a new typed request. `stopsFirst`: Aris is still working on the first one, which
        /// is stopped first, the way its Stop button stops it.
        case send(String, stopsFirst: Bool)
    }

    /// `offer`: what the turn is now, asked as Return is pressed (not as the card was last drawn). If the words can no
    /// longer be edited, a card has come up or Aris has begun to listen, the edit is thrown away: Return in the frame a
    /// card appears must never be its answer (typed words that read as a yes answer a waiting card; security review 7, L3).
    static func send(draft: String, phase: ArisSession.Phase, offer: Offer = .editable(saysDone: false)) -> Send {
        guard offer.isEditable else { return .discard }
        let words = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return .discard }
        return .send(words, stopsFirst: phase == .thinking)
    }

    /// Files given to Aris wait for "the next request" as chips on the composer, and go with a request only when it is
    /// asked with the chips in sight (ArisPendingFiles.taking). While a request is edited the composer steps aside, so
    /// the chips are out of sight: the edited request goes out as its words alone and the files keep waiting, their
    /// chips back when the editor closes (security review 7, L2).
    static func chipsInSight(notchOpen: Bool, editedRequest: Bool) -> Bool { notchOpen && !editedRequest }

    /// An edited request on its way to Aris, so its own turn knows itself: asked once by the turn that starts, and
    /// any turn with other words is an ordinary one.
    struct Sent: Equatable {
        private(set) var words: String?

        static func sending(_ words: String) -> Sent { Sent(words: words) }

        func taken(by said: String) -> (isEdit: Bool, left: Sent) { (words != nil && words == said, Sent()) }
    }

    /// What the editor's field writes into the draft. A field that is going away still writes its text back once (as
    /// it ends editing, after Return or Esc, by then the empty string of a draft that is gone): that write must not
    /// open the editor again. It did: Esc left the editor open and emptied, and after Return the card stayed an empty
    /// editor over the new turn (the second upgrade VM run, B12).
    static func draft(_ current: String?, typed: String) -> String? {
        current == nil ? nil : typed
    }

    /// Esc while a request is edited is the editor's: it throws the edit away and nothing else (no conversation ends,
    /// no card under the answer is put away). Only an Esc with no editor up does what Esc does elsewhere.
    static func escIsEditors(editing: Bool) -> Bool { editing }

    /// The editor's field is given the keyboard once it is laid out in the panel, and asked again until it has it:
    /// a field just put into a panel that is only now becoming key can miss the first asking. Up to 30 tries, a
    /// frame apart.
    static let focusTries = 30
    static let focusRetry: Double = 0.016

    /// The editor's text height: its lines on the card's 22-point pitch up to two, then two and an 18-point peek of
    /// the third, scrolling inside; the editor is the card's own box.
    static func editorContent(lines: Int) -> CGFloat {
        ArisPromptCollapse.content(lines: lines, collapsed: lines > ArisPromptCollapse.collapsedLines)
    }

    /// While the card is edited: what the first request did is not undone by sending another.
    static func doneNote(english: Bool) -> String {
        english ? "What the first request did stays done · this goes as a new request"
            : "앞 요청이 한 일은 그대로예요 · 고친 말은 새 요청으로 보내요"
    }

    static func pencilHelp(english: Bool) -> String { english ? "Edit request" : "요청 고치기" }
    static func editorLabel(english: Bool) -> String { english ? "Edit your request" : "보낸 요청 고치기" }
}
