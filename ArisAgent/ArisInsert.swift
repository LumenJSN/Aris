//
//  ArisInsert.swift
//  aris-agent
//
//  Types dictated words where the cursor is, for the notch app (which is sandboxed): through the clipboard and ⌘V,
//  which works in every app and with the Korean input method on. The clipboard holds a lazy item (and an HTML copy
//  with links when there are URLs, a trailing space in terminals), so the moment the app asks for the text is the
//  paste-confirmed signal (2 s). Read: the user's clipboard comes back 500 ms later; not read: the words stay a minute so
//  he can ⌘V them himself. Never presses Enter, and never types while a password field has the keyboard (secure input)
//  or into a password app. A read paste of dictation starts the edit watch (ArisEditWatch), never in a terminal.
//  Runs on the main queue without holding it (ArisPasteSession): the pasteboard asks for promised data only through
//  the main run loop, which main.swift runs.
//

import AppKit
import Carbon

enum ArisInsert {
    static let maxLength = 4_000
    /// The key that types "v" with ⌘ held on the keyboard layout in use (audit desk-10: by its US place, key 9, the
    /// paste was ⌘K on Dvorak and nothing was typed); the US place when the layout can't be read.
    private static var vKey: CGKeyCode { ArisKeyLayout.current(command: true)["v"] ?? 9 }
    /// A paste is under way (until the user's clipboard is back, or the unread words are left on it). Main thread only.
    nonisolated(unsafe) private static var busy = false
    /// Which paste `busy` belongs to: an earlier session ending late (a later one took its restore over) leaves it.
    nonisolated(unsafe) private static var pasteNumber = 0

    /// The text to type, trimmed; nil when blank or too long.
    static func text(from raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || text.count > maxLength ? nil : text
    }

    /// Why ⌘V mustn't be pressed now, or nil when it may.
    private static func refusal() -> String? {
        // The app that has the keyboard now, as Accessibility says (ArisFrontLive), never NSWorkspace's stale front app
        // (second upgrade run, bug 1) nor the window order (review 9, L4): no answer is a refusal.
        let trusted = AXIsProcessTrusted()
        return ArisInsertRefusal.refusal(trusted: trusted, secureInput: IsSecureEventInputEnabled(), front: trusted ? ArisFrontLive.keyboardFront() : nil)
    }

    /// Presses ⌘V for what's already on the clipboard (the notch's clipboard history put it there).
    static func pressPaste() -> String? {
        if let refusal = refusal() { return refusal }
        pressCommandV()
        return nil
    }

    private static func pressCommandV() {
        let source = CGEventSource(stateID: .privateState)
        let key = vKey
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
            if down { usleep(10_000) }
        }
    }

    struct Pasted: Equatable {
        let failure: String?
        /// The app read the paste within the window.
        let confirmed: Bool
    }

    /// Types `text`; `done` gets the outcome once the paste was read or the window passed. `learn`: watch the field a
    /// minute for the user's fix of one word.
    static func paste(_ text: String, learn: Bool = false, waited: TimeInterval = 0, done: @escaping (Pasted) -> Void) {
        if let refusal = refusal() { return done(Pasted(failure: refusal, confirmed: false)) }
        if busy {
            // The last paste is still under way: this one goes in once it's done.
            guard let delay = ArisInsertText.busyRetry(waited: waited) else {
                return done(Pasted(failure: "still typing the last words", confirmed: false))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { paste(text, learn: learn, waited: waited + delay, done: done) }
            return
        }
        busy = true
        pasteNumber += 1
        let number = pasteNumber
        let terminal = ArisWritingStyles.isTerminal(ArisFrontLive.front()?.bundleId)
        let typed = ArisInsertText.prepared(text, terminal: terminal)
        ArisPasteSession.start(text: typed, html: ArisInsertText.html(for: typed), press: pressCommandV, confirmed: { confirmed in
            if !confirmed, number == pasteNumber { busy = false }
            if confirmed, learn, !terminal { ArisEditWatch.start(inserted: text) }
            done(Pasted(failure: nil, confirmed: confirmed))
        }, finished: { if number == pasteNumber { busy = false } })
    }
}
