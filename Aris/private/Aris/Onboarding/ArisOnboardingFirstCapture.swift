//
//  ArisOnboardingFirstCapture.swift
//  Aris
//
//  macOS's second question about the screen, asked in the setup (VM run 2026-11-11, bug 3). With Screen Recording on,
//  macOS 26 still asks once more the first time an app captures the screen itself instead of through macOS's window
//  picker ("“Aris” is requesting to bypass the system private window picker and directly access your screen and
//  audio"). That prompt used to come over the notch at the first "what's on my screen?", after the setup had said
//  "Screen Recording is on." Now the setup takes the app's first real capture itself as soon as the card is on (the
//  smallest frame the capture code makes, dropped at once: ArisScreenCapture.firstCapture), so the prompt comes where
//  prompts are expected, and the card says so before, and says truthfully what follows a "not now". Pure, so the tests
//  run it: when the capture is due, what came of it, and which line the card shows.
//

import Foundation

enum ArisFirstCapture {
    /// What came of the capture.
    enum Outcome: Equatable {
        /// A frame came back: macOS has its yes.
        case allowed
        /// macOS said the user turned it down.
        case declined
        /// Nothing came back and macOS didn't say why (the prompt was left, a password field had the keyboard, an error).
        case unknown
    }

    static func outcome(gotImage: Bool, declined: Bool) -> Outcome { gotImage ? .allowed : declined ? .declined : .unknown }

    /// Where the Screen Recording card is with it.
    enum Step: Equatable {
        case idle
        /// The capture was started: macOS's prompt is up, or about to be.
        case asking
        case done(Outcome)
    }

    /// Set once macOS has said yes: the setup never takes the capture again (a replay of the guide captures nothing).
    static let allowedKey = "arisFirstCaptureAllowed"

    /// Whether the setup takes the capture now: only while the permissions page shows, with the Screen Recording card
    /// on and no other card waiting on macOS, once per setup, and never again after a yes.
    static func due(page: ArisSetupPage, screenGranted: Bool, waiting: Bool, step: Step, allowedBefore: Bool) -> Bool {
        page == .permissions && screenGranted && !waiting && step == .idle && !allowedBefore
    }

    /// A line on the Screen Recording card.
    enum Note: Equatable {
        /// macOS asks once more here, and why.
        case asksOnceMore
        /// It was turned down: what happens at the first screen question.
        case declined
        /// It couldn't be finished: the question may come at the first screen question.
        case unfinished
    }

    /// The card's line: before and while macOS asks, that it asks once more and why; after a yes, nothing (the card
    /// says Screen Recording is on, and it is); after anything else, what happens at the first screen question.
    static func note(card: ArisCardState, step: Step, allowedBefore: Bool) -> Note? {
        guard !allowedBefore else { return nil }
        switch card {
        case .idle, .later: return nil
        case .active, .waiting: return .asksOnceMore
        case .granted:
            switch step {
            case .idle, .asking: return .asksOnceMore
            case .done(.allowed): return nil
            case .done(.declined): return .declined
            case .done(.unknown): return .unfinished
            }
        }
    }

    // MARK: The app captures before the helper does

    /// When macOS last said yes to the app's own capture (a date in the defaults).
    static let allowedAtKey = "arisFirstCaptureAllowedAt"
    /// macOS asks again about a month after its last yes. One approval covers the app and the helper inside it, and
    /// the question names whichever of them captures first (follow-up experiment, 1-capture-*.txt): so the app takes
    /// its own smallest capture before it asks the helper to read the screen, whenever its last yes is older than
    /// this, and the question says "Aris", never the helper's file name.
    static let renewAfter: TimeInterval = 25 * 24 * 3_600
    /// After a capture that brought no yes, the next try waits this long (the question is not put up at every request).
    static let retryAfter: TimeInterval = 600

    /// Whether the app takes its own capture now, before a request goes to the helper: with Screen Recording on, no
    /// yes on record within `renewAfter`, and no try within `retryAfter`.
    static func appCaptureDue(screenGranted: Bool, lastAllowed: Date?, lastTry: Date?, now: Date) -> Bool {
        guard screenGranted else { return false }
        if let lastAllowed, now >= lastAllowed, now.timeIntervalSince(lastAllowed) < renewAfter { return false }
        if let lastTry, now >= lastTry, now.timeIntervalSince(lastTry) < retryAfter { return false }
        return true
    }

    /// Whether the setup window comes forward again once the capture is over: after a yes. After anything else
    /// macOS may have opened System Settings at the user's own choice, and nothing of Aris's covers that.
    static func comesForward(after outcome: Outcome) -> Bool { outcome == .allowed }
}

// MARK: - The card's words

extension ArisSetupWords {
    static func captureNote(_ note: ArisFirstCapture.Note, english: Bool = english) -> String {
        switch note {
        case .asksOnceMore:
            say("여기서 macOS가 한 번 더 물어요. 창 선택 화면 없이 화면을 바로 보기 위해서예요.",
                "macOS asks once more here, so I can look at the screen directly, without its window picker.", english)
        case .declined:
            say("macOS의 두 번째 질문은 허용하지 않았어요. 화면에 대해 처음 물어볼 때 다시 시도하고, 그때 macOS가 다시 물을 수 있어요.",
                "macOS's second question wasn't allowed. I'll try again the first time you ask about the screen, and macOS may ask again then.", english)
        case .unfinished:
            say("macOS의 두 번째 질문을 지금은 마치지 못했어요. 화면에 대해 처음 물어볼 때 그 질문이 나올 수 있어요.",
                "I couldn't finish macOS's second question just now. It may come up the first time you ask me about the screen.", english)
        }
    }
}
