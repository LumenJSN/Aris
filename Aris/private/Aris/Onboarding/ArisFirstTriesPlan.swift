//
//  ArisFirstTriesPlan.swift
//  Aris
//
//  What the setup leaves behind (the owner's pick 5-A, 2026-11-11; the mockup's "바로 시켜 볼 일 세 가지"): when the last
//  page closes, the real notch opens with one line and three things to try, each of which can be pressed (it is then
//  sent as a request typed into the notch is, by the normal path) or simply said; and the left side notch comes out
//  once with two words beside it. Nothing else is explained. The three: the timer, a folder on the desktop (which
//  shows the card that asks first), and what is on the screen. Those last two need an AI, so on a Mac with none the
//  three are ones the app does itself: the timer, opening Notes, the time; nothing offered there ends in "no AI is
//  ready". The offer stays, each time the notch is open, until the first request of any kind after the setup. Pure,
//  so the tests check every sentence is read the way it is meant; ArisFirstTries runs it.
//

import Foundation

/// One thing to try.
enum ArisFirstTry: String, Equatable, CaseIterable, Identifiable {
    /// The app sets it itself: a running timer appears in the notch.
    case timer
    /// An AI makes it, and Aris asks on a card first.
    case folder
    /// An AI looks at the screen (Screen Recording).
    case screen
    /// The app opens Notes itself.
    case notes
    /// The app says the time itself.
    case time

    var id: String { rawValue }

    /// The request as it is shown and, pressed, sent.
    func text(english: Bool) -> String {
        switch self {
        case .timer: ArisSetupTry.line(english: english)
        case .folder: english ? "Make a folder on my desktop" : "바탕화면에 폴더 만들어 줘"
        case .screen: english ? "What's on my screen?" : "지금 화면에 뭐가 있어?"
        case .notes: english ? "Open Notes" : "메모 앱 열어 줘"
        case .time: english ? "What time is it?" : "지금 몇 시야?"
        }
    }

    /// The app does this one itself, with no AI.
    var needsNoAI: Bool { self == .timer || self == .notes || self == .time }
}

enum ArisFirstTriesPlan {
    /// The three offered. `noAI`: the helper said no AI is set up on this Mac.
    static func tries(noAI: Bool) -> [ArisFirstTry] { noAI ? [.timer, .notes, .time] : [.timer, .folder, .screen] }

    /// The notch, opened by Aris with nobody's pointer on it, closes by itself after this long if the pointer never
    /// came (the three stay for the next time it is opened).
    static let staysOpen: TimeInterval = 60
    /// How long the left side notch stays out with its words.
    static let sliverSeconds: TimeInterval = 5

    /// The offer is over at the first request of any kind after the setup: a turn that starts, however it was asked.
    static func ends(turnStarted: Bool) -> Bool { turnStarted }

    /// Whether the notch Aris opened is closed again now: only when the three are still on offer, it is still open,
    /// no turn has it and the pointer is not on it.
    static func closesItself(offered: Bool, open: Bool, inTurn: Bool, pointerOnNotch: Bool) -> Bool {
        offered && open && !inTurn && !pointerOnNotch
    }

    // MARK: - The words

    /// The one line over the three. `name`: what the user asked to be called.
    static func line(name: String?, english: Bool) -> String {
        guard let name, !name.isEmpty else { return english ? "I'll be right here. Try one of these." : "여기 있을게요. 이런 걸 시켜 보세요." }
        return english ? "I'll be right here, \(name). Try one of these." : "\(name)님, 여기 있을게요. 이런 걸 시켜 보세요."
    }

    /// Under it. `keys`: the talk shortcut as it is set ("⌥ Space").
    static func hint(keys: String, english: Bool) -> String {
        english ? "Or hold \(keys) and say it." : "\(keys)를 누른 채 말해도 돼요"
    }

    /// Beside the left side notch.
    static func sliverWord(english: Bool) -> String { english ? "Your history is here" : "기록은 여기" }
}
