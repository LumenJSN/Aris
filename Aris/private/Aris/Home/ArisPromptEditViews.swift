//
//  ArisPromptEditViews.swift
//  Aris
//
//  What editing a sent request looks like (the rules are ArisPromptEdit's): the pencil on the card under the pointer,
//  the card's own editor (the same 15-point words on the same 22-point lines, so nothing moves when the edit begins),
//  and the one line under it that says what the first request did stays done. While a card is being edited the
//  composer steps aside (ArisPromptEditing).
//

import AppKit
import SwiftUI

/// The pencil: a 22-point dark circle with a 12-point glyph, at the card's top right while the pointer is on the card.
struct ArisPromptPencil: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "pencil")
                .font(.system(size: ArisPromptEdit.pencilGlyph - 1, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: ArisPromptEdit.pencilSize, height: ArisPromptEdit.pencilSize)
                .background(Circle().fill(Color(.sRGB, red: ArisPromptEdit.pencilFill.red, green: ArisPromptEdit.pencilFill.green,
                                                blue: ArisPromptEdit.pencilFill.blue, opacity: ArisPromptEdit.pencilFill.alpha)))
                .contentShape(Circle())
        }
        .buttonStyle(ArisPencilStyle())
        .help(ArisPromptEdit.pencilHelp(english: ArisUIWords.english))
        .accessibilityLabel(ArisPromptEdit.pencilHelp(english: ArisUIWords.english))
    }
}

/// Press feedback: the pencil dips a little while held.
private struct ArisPencilStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// The card as its own editor: the words in place, the caret at their end. Return sends, Esc gives up
/// (option-return is a new line). It grows with the words on the card's 22-point pitch, two lines and a peek at most.
/// The press that opened it (the pencil, or the card itself) gives it the keyboard in the same act: once its field is
/// laid out in the notch's panel it is made the panel's first responder, and asked again until it is and when the
/// panel becomes key (ArisPromptEdit.focusTries).
struct ArisPromptEditor: View {
    @Binding var text: String
    let send: () -> Void
    let cancel: () -> Void
    /// Draws without asking for the keyboard (the off-screen render only).
    var preview = false

    @FocusState private var focused: Bool
    @State private var lines = 1
    /// Where the field is, for finding it in the panel (ArisFieldAnchor).
    @State private var seat = ArisFieldAnchor.Seat()
    /// The caret has been put at the end of the words (once: never again under his typing).
    @State private var caretPlaced = false

    var body: some View {
        TextField("", text: $text, axis: .vertical)
            .lineLimit(1...(ArisPromptCollapse.collapsedLines + 1))
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .lineSpacing(ArisPromptCollapse.lineSpacing)
            .foregroundStyle(.white.opacity(0.9))
            .focused($focused)
            .onSubmit(send)
            .onExitCommand(perform: cancel)
            .accessibilityLabel(ArisPromptEdit.editorLabel(english: ArisUIWords.english))
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                let next = ArisPromptCollapse.lines(measured: height)
                // The card's height on the size clock: 340 ms (0.45, 0, 0.55, 1).
                if next != lines { withAnimation(ArisGlass.resize) { lines = next } }
            }
            // Laid out with the field: once it is in the panel, the field takes the keyboard.
            .background(ArisFieldAnchor(seat: seat) { window in if !preview { takeKeyboard(in: window) } })
            .padding(.top, ArisPromptCard.halfLeading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: ArisPromptEdit.editorContent(lines: lines), alignment: .top)
            .clipped()
            // The panel has just become key (Aris came forward a moment after the press): the field is asked again.
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
                guard !preview, let window = note.object as? NSWindow, window === seat.view?.window else { return }
                giveField(in: window, tries: ArisPromptEdit.focusTries)
            }
    }

    /// The editor takes the keyboard the way the composer does: only on the user's own press, through ArisPanelKeys so
    /// the notch's panel really is key (and gives the keyboard back when it lets go). A press something else posted
    /// begins no edit.
    private func takeKeyboard(in window: NSWindow) {
        guard window is ArisNotchPanel, ArisPanelKeys.tapTakesKeyboard(in: window) else { return cancel() }
        ArisPanelKeys.take(window)
        giveField(in: window, tries: ArisPromptEdit.focusTries)
    }

    /// Makes the editor's own field the panel's first responder, trying again a frame later while it is not yet there
    /// to be found; the first time it has the keyboard the caret goes to the end of the words (a field that
    /// takes the keyboard would select all of it).
    private func giveField(in window: NSWindow, tries: Int) {
        guard tries > 0, let anchor = seat.view, anchor.window === window else { return }
        if let field = ArisFieldLocator.field(over: anchor) {
            if !ArisFieldLocator.holds(window.firstResponder, field) { _ = window.makeFirstResponder(field) }
            if ArisFieldLocator.holds(window.firstResponder, field) {
                focused = true
                if !caretPlaced, let editor = window.firstResponder as? NSTextView {
                    caretPlaced = true
                    editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
                }
                return
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + ArisPromptEdit.focusRetry) { giveField(in: window, tries: tries - 1) }
    }
}

/// The card's text sits on 22-point lines: SF's 18-point line at 15 points with 2 above and
/// 2 below, so one line is 22 tall (the card 54) and the first line starts 18 from the card's top.
enum ArisPromptCard {
    static let halfLeading: CGFloat = ArisPromptCollapse.lineSpacing / 2
}

/// Under a card being edited, when the first request already did something.
struct ArisPromptDoneNote: View {
    static let gap: CGFloat = 6

    var body: some View {
        Text(ArisPromptEdit.doneNote(english: ArisUIWords.english))
            .font(.system(size: 11.5))
            .foregroundStyle(ArisGlass.secondaryText)
            .lineLimit(2)
            .padding(.horizontal, ArisPromptCollapse.padding)
            .transition(.opacity)
    }
}

/// A sent request is being edited in the open notch: the composer steps aside for it (the bottom composer
/// shows only while the card is not the editor).
@MainActor
final class ArisPromptEditing: ObservableObject {
    static let shared = ArisPromptEditing()

    @Published private(set) var active = false

    func set(_ on: Bool) { if on != active { active = on } }

    /// The edited request just handed to Aris (ArisPromptEdit.Sent): its turn leaves the waiting files where they are.
    private var sent = ArisPromptEdit.Sent()

    func sending(_ words: String) { sent = .sending(words) }

    /// Asked once by the turn that starts with `said`: whether it is the edited request.
    func takeEdit(_ said: String) -> Bool {
        let taken = sent.taken(by: said)
        sent = taken.left
        return taken.isEdit
    }
}
