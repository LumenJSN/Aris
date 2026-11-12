//
//  ArisDictationState.swift
//  Aris
//
//  One dictation's own state beside ArisController's `dictation` stage: hands-free or held, the 19-minute warning,
//  the app it types into (and so its writing style), the warmed polish session, the words around the caret (polish
//  only, kept in memory until the dictation ends), the last text typed, for ⌃⌘V, and whether it was copied instead.
//  Also why a press couldn't start one just now, and the settings it reads.
//

import AppKit
import Defaults
import KeyboardShortcuts

extension Defaults.Keys {
    /// Polish falls back to a brain (no tools) when Apple's on-device model can't: off unless the user turns it on.
    static let arisDictationBrainPolish = Key<Bool>("arisDictationBrainPolish", default: false)
    /// The user's writing style per app kind (ArisAppKind raw value → ArisWritingStyle raw value); missing: the default.
    static let arisDictationStyles = Key<[String: String]>("arisDictationStyles", default: [:])
}

extension KeyboardShortcuts.Name {
    /// Types the last dictation again where the cursor is.
    static let pasteLastDictation = Self("pasteLastDictation", default: .init(.v, modifiers: [.control, .command]))
}

@MainActor
final class ArisDictationState: ObservableObject {
    static let shared = ArisDictationState()

    /// Locked hands-free: letting go keeps listening.
    @Published var locked = false
    /// A minute left before the 20-minute cap.
    @Published var warning = false
    /// Nowhere took the words, so they were put on the clipboard (ArisDictationCopy).
    @Published var copied = false
    /// The pointer is on the copied card: it stays up meanwhile.
    var cardHovered = false
    /// Why the right ⌥ couldn't start a dictation just now, for a moment in the notch (audit voice-9).
    @Published private(set) var refusal: String?
    private var refusalClear: Task<Void, Never>?

    private(set) var style = ArisWritingStyle.standard
    private var polishSession: AnyObject?
    private var context: (before: String, after: String)?
    private var contextRead: Task<Void, Never>?
    /// Its words are being written down and typed: the key and the cap can't end it again.
    var finishing = false
    /// Counts dictations, so a watch left from the last one knows it's stale.
    private(set) var generation = 0
    /// What dictation typed last, in memory only.
    var lastText: String?

    /// The hint under the words while listening.
    var hint: String {
        if warning { return ArisUIWords.text("곧 20분이에요 · 1분 뒤에 여기까지 넣어요", "Nearly 20 minutes · in 1 minute what you've said so far goes in") }
        // Written for the right ⌥; said with the key that dictates now (Settings › 받아쓰기).
        let key = ArisDictationKey.Choice.current
        if locked { return key.naming(ArisUIWords.text("손 떼고 받아쓰는 중 · 오른쪽 ⌥ 한 번 더 누르면 넣어요 · Esc 취소", "Hands-free dictation · press right ⌥ once more to put it in · Esc cancels")) }
        return key.naming(ArisUIWords.text("오른쪽 ⌥에서 손을 떼면 넣어요 · 두 번 누르면 손 떼고 말해요", "Let go of right ⌥ to put it in · press twice to talk hands-free"))
    }

    /// The status once it's typed, or copied for want of a field.
    var typedStatus: String { copied ? ArisDictationCopy.tag : ArisUIWords.text("넣었어요 · ⌘Z로 되돌리기", "Put in · ⌘Z undoes it") }

    /// Puts `text` on the clipboard in place of what was there (it's recorded in the clipboard history like any
    /// copy). True when it's there.
    func copy(_ text: String) -> Bool {
        let board = NSPasteboard.general
        board.clearContents()
        return board.setString(text, forType: .string)
    }

    /// The right ⌥ was pressed while Aris can't be interrupted: the notch says why, then the line goes.
    func refuse(_ why: ArisDictationPress.Why) {
        refusalClear?.cancel()
        refusal = why.line
        refusalClear = Task { [weak self] in
            try? await Task.sleep(for: ArisDictationPress.refusalLinger)
            guard !Task.isCancelled else { return }
            self?.refusal = nil
        }
    }

    func clearRefusal() {
        refusalClear?.cancel()
        refusalClear = nil
        if refusal != nil { refusal = nil }
    }

    /// A dictation starts, typing into `front`: its style, a warmed session, and the caret's words (read by aris-agent).
    func begin(front: NSRunningApplication?) {
        end()
        generation += 1
        finishing = false
        let kind = ArisAppKind.of(bundleId: front?.bundleIdentifier, name: front?.localizedName)
        style = ArisWritingStyles.style(for: kind, choices: Defaults[.arisDictationStyles])
        copied = false
        cardHovered = false
        polishSession = ArisDictationPolish.prepare(style: style, words: ArisVocabulary.load())
        guard style.polishes else { return }
        contextRead = Task { [weak self] in
            let read = await ArisAgentClient.caretContext()
            guard !Task.isCancelled else { return }
            self?.context = read
        }
    }

    /// What polish needs, handed over once (the caret's words leave this object here).
    func takeForPolish() -> (session: AnyObject?, context: (before: String, after: String)?) {
        contextRead?.cancel()
        contextRead = nil
        defer { polishSession = nil; context = nil }
        return (polishSession, context)
    }

    /// The dictation is over (typed, cancelled or failed): nothing of it is kept but `lastText`.
    func end() {
        contextRead?.cancel()
        contextRead = nil
        polishSession = nil
        context = nil
        locked = false
        warning = false
    }
}
