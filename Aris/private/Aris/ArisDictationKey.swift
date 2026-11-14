//
//  ArisDictationKey.swift
//  Aris
//
//  The right ⌥ held alone dictates; let go and the words are typed where the cursor is. Two quick presses lock it
//  hands-free (let go and keep talking), one more press types it; a third press inside the first half second, or Esc,
//  throws it away. A press under 200 ms with no second one is an accident and dropped quietly. ⌥ with another key (a
//  special character, a shortcut) cancels. Pure: the key
//  tap feeds it events and the time, and delivers `.tick` at `deadline`.
//

import Foundation

enum ArisDictationKey {
    /// kVK_RightOption (the key a fresh install dictates with: ArisDictationKey.Choice), kVK_Escape.
    static let keyCode: UInt16 = 61
    static let escapeKeyCode: UInt16 = 53
    /// A press shorter than this, with no second one, is an accident.
    static let accidentalTap: Duration = .milliseconds(200)
    /// From the first press: a second press inside it locks hands-free, a third cancels.
    static let multiTapWindow: Duration = .milliseconds(500)

    enum Event: Equatable {
        /// The right ⌥ went down; `alone`: no other modifier was held.
        case down(alone: Bool)
        case up
        /// Any other key or modifier.
        case otherKey
        case escape
        /// `deadline` came.
        case tick
    }

    enum Action: Equatable {
        case start
        /// Hands-free now: letting go keeps listening.
        case lock
        case finish, cancel, none
    }

    struct State {
        private enum Phase: Equatable {
            case idle
            /// Down with another modifier, or already settled: nothing until it's let go.
            case ignoring
            case holding(firstDown: ContinuousClock.Instant)
            /// Let go after a short press: a second press may still come.
            case waiting(firstDown: ContinuousClock.Instant, held: Duration)
            case locked(firstDown: ContinuousClock.Instant)
        }

        private var phase = Phase.idle

        var isIdle: Bool { phase == .idle }

        /// Hands-free: Esc is Aris's now (the key tap keeps it from the front app).
        var isLocked: Bool {
            if case .locked = phase { return true }
            return false
        }

        /// When `.tick` must be delivered (the double-tap window's end), or nil.
        var deadline: ContinuousClock.Instant? {
            if case .waiting(let firstDown, _) = phase { return firstDown + ArisDictationKey.multiTapWindow }
            return nil
        }

        /// Forget everything (the app dropped the dictation on its own).
        mutating func reset() { phase = .idle }

        /// A dictation started with a click on the pill is hands-free: the key's next press puts it in (never read as
        /// the triple tap that cancels), Esc cancels.
        mutating func lockFromPill(at now: ContinuousClock.Instant) { phase = .locked(firstDown: now - ArisDictationKey.multiTapWindow) }

        mutating func handle(_ event: Event, at now: ContinuousClock.Instant) -> Action {
            switch phase {
            case .idle:
                guard case .down(let alone) = event else { return .none }
                phase = alone ? .holding(firstDown: now) : .ignoring
                return alone ? .start : .none
            case .ignoring:
                if event == .up { phase = .idle }
                return .none
            case .holding(let firstDown):
                switch event {
                case .up:
                    let held = now - firstDown
                    guard held < ArisDictationKey.multiTapWindow else {
                        phase = .idle
                        return .finish
                    }
                    phase = .waiting(firstDown: firstDown, held: held)
                    return .none
                case .otherKey, .escape:
                    phase = .ignoring
                    return .cancel
                case .down, .tick:
                    return .none
                }
            case .waiting(let firstDown, let held):
                let settled: Action = held < ArisDictationKey.accidentalTap ? .cancel : .finish
                switch event {
                case .down(let alone):
                    if alone, now < firstDown + ArisDictationKey.multiTapWindow {
                        phase = .locked(firstDown: firstDown)
                        return .lock
                    }
                    phase = .ignoring
                    return settled
                case .tick:
                    guard now >= firstDown + ArisDictationKey.multiTapWindow else { return .none }
                    phase = .idle
                    return settled
                case .otherKey:
                    phase = .idle
                    return settled
                case .escape:
                    phase = .idle
                    return .cancel
                case .up:
                    return .none
                }
            case .locked(let firstDown):
                switch event {
                case .down(let alone):
                    guard alone else { return .none }
                    phase = .ignoring
                    return now < firstDown + ArisDictationKey.multiTapWindow ? .cancel : .finish
                case .escape:
                    phase = .idle
                    return .cancel
                case .up, .otherKey, .tick:
                    return .none
                }
            }
        }
    }
}

/// Dictation stops itself at 20 minutes, with a gentle word at 19.
enum ArisDictationLimit {
    static let warning: Duration = .seconds(19 * 60)
    static let longest: Duration = .seconds(20 * 60)

    enum Stage: Equatable { case fine, warning, over }

    static func stage(after elapsed: Duration) -> Stage {
        elapsed >= longest ? .over : elapsed >= warning ? .warning : .fine
    }
}

/// A right-⌥ press while Aris is doing something else (bug hunt 11-06 #3, audit voice-9): it's never dropped without a
/// sign. Pure.
enum ArisDictationPress: Equatable {
    case start
    /// "넣었어요" still lingers: it closes and the new dictation starts at once.
    case replaceTyped
    /// The last words are still being written down, polished or typed: the press waits for them (ArisDictationQueue).
    case queue
    /// Aris is reading an answer out, or a failure line is still up: it stops (as it does for ⌥Space) and the
    /// dictation starts at once.
    case interrupt
    /// Aris can't be interrupted now; the notch says why for a moment (`Why.line`).
    case refuse(Why)

    /// What Aris is doing when the key goes down.
    enum Turn: Equatable {
        case idle
        /// Hearing a request.
        case listening
        /// The AI is working on one.
        case thinking
        /// Reading an answer out.
        case speaking
        /// A confirm card is up, waiting for yes or no.
        case asking
        /// A failure line is up for a moment.
        case failed
    }

    enum Why: Equatable {
        case training, listening, thinking, asking

        /// The notch's line, short enough for one tag.
        var line: String {
            switch self {
            case .training: ArisUIWords.text("호출어를 배우는 중이라 받아쓰기는 끝난 뒤에 돼요", "Aris is learning its name: dictation works once that's done")
            case .listening: ArisUIWords.text("Aris가 듣는 중이라 받아쓰기는 끝난 뒤에 돼요", "Aris is listening: dictation works once that's done")
            case .thinking: ArisUIWords.text("Aris가 일하는 중이라 받아쓰기는 끝난 뒤에 돼요", "Aris is working: dictation works once that's done")
            case .asking: ArisUIWords.text("카드에 먼저 답해 주세요 · 받아쓰기는 그 뒤에 돼요", "Answer the card first · dictation works after that")
            }
        }
    }

    /// How long the reason stays in the notch.
    static let refusalLinger: Duration = .milliseconds(2800)

    /// `lastTyped`: the last dictation's "넣었어요" is up. `lastTyping`: its words are still on their way in.
    static func decide(turn: Turn, training: Bool, lastTyped: Bool, lastTyping: Bool) -> ArisDictationPress {
        if training { return .refuse(.training) }
        // A failure line (the last dictation's "입력하지 못했어요" too) never holds the key back: a press queued behind
        // it was dropped without a word when the line left.
        if turn == .failed { return .interrupt }
        if lastTyped { return .replaceTyped }
        if lastTyping { return .queue }
        switch turn {
        case .idle: return .start
        case .speaking, .failed: return .interrupt
        case .listening: return .refuse(.listening)
        case .thinking: return .refuse(.thinking)
        case .asking: return .refuse(.asking)
        }
    }
}

/// Whether a dictation that stops has anything to type (audit voice-10): voice the level meter counted, or words a
/// recogniser wrote. A quiet microphone (an external display's, a soft voice) can stay under the voice level the
/// whole time while the recogniser writes every word; loudness alone threw those words away.
enum ArisDictationEnd {
    static func saidSomething(heardVoice: Bool, wroteWords: Bool) -> Bool { heardVoice || wroteWords }
}

/// A press that came while the last words were still being typed: it starts the moment they're in, unless the key
/// was let go (or the press cancelled) first.
struct ArisDictationQueue: Equatable {
    private(set) var waiting = false
    private(set) var locked = false

    mutating func press() {
        waiting = true
        locked = false
    }

    /// The key's next action while a press waits; true when the queue took it (the controller does nothing else).
    mutating func take(_ action: ArisDictationKey.Action) -> Bool {
        guard waiting else { return false }
        switch action {
        case .lock: locked = true
        case .finish, .cancel: self = ArisDictationQueue()
        case .start, .none: break
        }
        return true
    }

    /// The last words are in: whether the waiting press starts now, and hands-free. The queue empties.
    mutating func typed() -> (start: Bool, locked: Bool) {
        defer { self = ArisDictationQueue() }
        return (waiting, locked)
    }
}

// MARK: - Which key

extension ArisDictationKey {
    /// The key that dictates while it is held: one modifier key, by itself. The right ⌥ unless another was picked in
    /// Settings (받아쓰기, 단축키), so no key of Aris's is fixed. A key that is pressed all the time for other things
    /// can't be it: ⇧ (typing), and the left ⌥ ⌘ ⌃ (the talk key, ⌥⇧ to point at the screen, every app's shortcuts):
    /// each such press would start a dictation.
    struct Choice: Equatable, Sendable {
        enum Kind: String, Sendable { case option, command, control, shift, function }

        let keyCode: UInt16
        let kind: Kind
        /// The right-hand key of its pair; nil for fn, which has no pair.
        let right: Bool?
        /// This one key's own bit in a keyboard event's flags (NX_DEVICE…KEYMASK; fn: NX_SECONDARYFNMASK).
        let flag: UInt64

        static let rightOption = Choice(keyCode: 61, kind: .option, right: true, flag: 0x40)
        /// Every modifier key, the ones that can dictate first.
        static let keys: [Choice] = [
            rightOption,
            Choice(keyCode: 54, kind: .command, right: true, flag: 0x10), Choice(keyCode: 62, kind: .control, right: true, flag: 0x2000),
            Choice(keyCode: 63, kind: .function, right: nil, flag: 0x80_0000),
            Choice(keyCode: 58, kind: .option, right: false, flag: 0x20), Choice(keyCode: 55, kind: .command, right: false, flag: 0x8),
            Choice(keyCode: 59, kind: .control, right: false, flag: 0x1),
            Choice(keyCode: 56, kind: .shift, right: false, flag: 0x2), Choice(keyCode: 60, kind: .shift, right: true, flag: 0x4),
        ]

        static func key(_ code: UInt16) -> Choice? { keys.first { $0.keyCode == code } }

        var symbol: String {
            switch kind {
            case .option: "⌥"
            case .command: "⌘"
            case .control: "⌃"
            case .shift: "⇧"
            case .function: "fn"
            }
        }

        /// "오른쪽 ⌥", "오른쪽 ⌘", "fn"; in English "right ⌥".
        func name(english: Bool) -> String {
            guard let right else { return symbol }
            let side = right ? ArisUIWords.text("오른쪽", "right", english: english) : ArisUIWords.text("왼쪽", "left", english: english)
            return "\(side) \(symbol)"
        }

        /// What the settings' shortcut recorder calls this key (it isn't a KeyboardShortcuts name: one key, held).
        static let recorderName = "dictationKey"

        // MARK: Kept

        static let storeKey = "arisDictationKeyCode"

        /// The key a stored value means: one that may dictate, else the right ⌥ (nothing stored, or something unusable).
        static func stored(_ value: Any?) -> Choice {
            guard let code = value as? Int, let key = key(UInt16(clamping: code)), problem(keyCode: key.keyCode, talkModifiers: [], talkCaps: []) == nil else { return rightOption }
            return key
        }

        /// The key in use now.
        static var current: Choice { stored(UserDefaults.standard.object(forKey: storeKey)) }

        // MARK: What can be picked

        /// Why the pressed key can't be the dictation key, as the recorder says it; nil when it can. `keyCode` nil: a
        /// key that isn't a modifier. `talkModifiers`, `talkCaps`: the talk shortcut's modifiers and how it is shown.
        static func problem(keyCode: UInt16?, talkModifiers: Set<Kind>, talkCaps: [String], english: Bool = false) -> String? {
            guard let keyCode, let key = key(keyCode) else {
                return ArisUIWords.text("받아쓰기 키는 혼자 누르고 있는 키예요. 오른쪽 ⌥ ⌘ ⌃ 나 fn 중에서 골라 주세요", "The dictation key is one key held by itself. Pick the right ⌥, ⌘ or ⌃, or fn", english: english)
            }
            if key.kind == .shift { return ArisUIWords.text("⇧는 글자를 칠 때 쓰는 키라 받아쓰기에 쓸 수 없어요", "⇧ is used for typing, so it can't be the dictation key", english: english) }
            guard key.right == false else { return nil }
            let talk = talkCaps.joined(separator: " "), name = key.name(english: english)
            if talkModifiers.contains(key.kind) {
                return ArisUIWords.text("말하기 단축키(\(talk))를 누를 때마다 받아쓰기가 시작돼요. 오른쪽 키나 fn을 골라 주세요",
                                        "Every press of the talk shortcut (\(talk)) would start a dictation. Pick a right-hand key or fn", english: english)
            }
            if key.kind == .option {
                return ArisUIWords.text("⌥⇧로 화면을 가리킬 때마다 받아쓰기가 시작돼요. 오른쪽 키나 fn을 골라 주세요",
                                        "Every time you hold ⌥⇧ to point at the screen a dictation would start. Pick a right-hand key or fn", english: english)
            }
            return ArisUIWords.text("\(name) 키는 다른 단축키를 누를 때마다 받아쓰기를 시작해요. 오른쪽 키나 fn을 골라 주세요",
                                    "The \(name) key would start a dictation with every other shortcut. Pick a right-hand key or fn", english: english)
        }

        /// What the recorder says once the key is changed.
        static func changed(english: Bool) -> String { ArisUIWords.text("받아쓰기 키를 바꿨어요", "Dictation key changed", english: english) }

        // MARK: Lines that name the key

        /// A line written for the right ⌥ ("오른쪽 ⌥에서 손을 떼면…", "hold the right ⌥…"), naming this key instead.
        func naming(_ text: String) -> String {
            guard self != .rightOption else { return text }
            let korean = name(english: false)
            // 컨트롤 and 에프엔 end in a consonant: 을, where 옵션 was written with 를.
            let object = kind == .control || kind == .function ? "을" : "를"
            return text.replacingOccurrences(of: "오른쪽 ⌥를", with: korean + object)
                .replacingOccurrences(of: "오른쪽 ⌥", with: korean)
                .replacingOccurrences(of: "Right ⌥", with: name(english: true).prefix(1).uppercased() + name(english: true).dropFirst())
                .replacingOccurrences(of: "right ⌥", with: name(english: true))
        }
    }
}
