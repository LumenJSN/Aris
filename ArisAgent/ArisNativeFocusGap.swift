//
//  ArisNativeFocusGap.swift
//  aris-agent
//
//  The one rule for Aris taking the front (an app that takes keys only in front, a real pointer click the user's card
//  allowed, a drag, a file panel's folder): never while the user has typed, clicked, scrolled or moved the pointer in the
//  last moment (the owner-input measure, ArisOwnerActivity: Aris's own synthetic input never counts), and never while a
//  dictation is going in (ArisDesktopLock.urgent). Until then the step waits, for at most a bounded time (longer for a
//  background job, which nobody waits on), and gives up with a reason the controller can retry on, nothing sent. Once
//  in front, the same measure is read again right before the keys: input during the raise means the front is given back
//  and the step waits again (twice at most). The decisions are pure and tested over synthetic activity timelines.
//

import CoreGraphics
import Foundation

enum ArisNativeFocusGap {
    /// How long the user's last input must be past before the front is taken.
    static let gap: TimeInterval = 1.0
    /// How long a step waits for that gap: in a conversation, and in a background job.
    static let limit: TimeInterval = 8
    static let jobLimit: TimeInterval = 45
    /// The longest single pause while waiting.
    static let step: TimeInterval = 0.25

    enum Decision: Equatable {
        case go
        case wait(TimeInterval)
        case giveUp
    }

    /// `sinceInput`: seconds since the user's last input; `urgent`: a dictation is going in; `waited`: how long this step
    /// has waited already. Pure.
    static func decide(sinceInput: Double, urgent: Bool, waited: TimeInterval, limit: TimeInterval, gap: TimeInterval = gap) -> Decision {
        if !urgent, sinceInput >= gap { return .go }
        if waited >= limit { return .giveUp }
        let needed = urgent ? step : max(0.05, gap - sinceInput)
        return .wait(min(step, needed, max(0.01, limit - waited)))
    }

    /// Waits for the gap (`sleep` is the clock: the tests advance a fake one). True once the front may be taken; false
    /// when the limit passed first.
    static func await(limit: TimeInterval, sinceInput: () -> Double, urgent: () -> Bool, sleep: (TimeInterval) -> Void) -> Bool {
        var waited: TimeInterval = 0
        while true {
            switch decide(sinceInput: sinceInput(), urgent: urgent(), waited: waited, limit: limit) {
            case .go: return true
            case .giveUp: return false
            case .wait(let pause):
                sleep(pause)
                waited += pause
            }
        }
    }

    /// Input came during the raise (`sinceInput` is shorter than the raise took): the keys must not go.
    static func inputDuringRaise(sinceInput: Double, raisedFor: TimeInterval) -> Bool { sinceInput < raisedFor }

    /// The refusal the controller reads when no gap came (nothing was sent; safe to try again).
    static let busyCode = "USER_ACTIVE"
    static func busyLine(waited: TimeInterval) -> String {
        "the user kept typing or clicking for \(Int(waited.rounded())) s, so Aris didn't take the front (nothing was sent); try the step again in a moment"
    }
}

/// The live measure for one engine call: the user's input as the window server has it, the call's own input left out.
struct ArisNativeOwnerClock {
    /// The call's desktop-lock owner (its turn), whose own input never counts; nil: none of it is left out.
    var owner: String?
    /// When the call began: everything it sent since then is its own.
    var began = Date()

    /// The input that tells the owner is at the Mac: keys, clicks, scrolls, the pointer moving (mouse or trackpad).
    static let ownerEvents: [CGEventType] = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel,
                                             .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]

    func sinceInput() -> Double {
        if let owner { ArisOwnInput.shared.note(from: began, to: Date(), owner: owner) }
        let last = Self.ownerEvents.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
        return ArisOwnerActivity.secondsSinceOwner(lastEvents: last, ownSpans: owner.map { ArisOwnInput.shared.recent(for: $0) } ?? [])
    }

    func urgent() -> Bool { ArisDesktopLock.shared.urgent }

    /// Waits for the gap; true when the front may be taken.
    func awaitGap(job: Bool) -> Bool {
        ArisNativeFocusGap.await(limit: job ? ArisNativeFocusGap.jobLimit : ArisNativeFocusGap.limit, sinceInput: sinceInput, urgent: urgent,
                                 sleep: { Thread.sleep(forTimeInterval: $0) })
    }
}
