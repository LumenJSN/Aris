//
//  ArisTurnHearing.swift
//  Aris
//
//  What one turn's hearing keeps between the end of speech and the request (ArisController+Endpoint): its stage clock,
//  its speculative turn, the router's answer fetched during the pause, the words the turn went on with when the second
//  listen was late, and the request's context. One per controller, reset when a turn begins.
//

import Foundation

/// What a request was sent as: the turn takes a request sent early only when it would send exactly this.
struct ArisEarlyKey: Equatable, Sendable {
    let text: String
    let brain: String
    let tier: String
    let screenConversation: Bool
    let outsideConversation: Bool
    let handsFree: Bool
    /// Whether the turn's speaker counted as the owner (F1, ArisVoiceDecisions.sameTag): an early request sent for the
    /// owner's voice is not taken by a turn whose final check says otherwise.
    var voiceOwner = true
}

/// A request already sent, taken by the brain's turn (askAndSpeak).
struct ArisEarlyRequest {
    let replies: AsyncStream<ArisAgentReply>
    /// The conversation was new when it was sent.
    let fresh: Bool
}

@MainActor
final class ArisTurnHearing {
    typealias Turn = ArisSpeculativeTurn<ArisAgentReply, ArisEarlyKey>

    /// When this turn began listening (the clock's origin, and how a new turn is told from this one).
    private(set) var since: ContinuousClock.Instant?
    var clock = ArisStageClock()
    /// The kernel's turn this hearing belongs to: its speculation runs in it (ArisTurnScope), so whatever it does after
    /// the turn is over is dropped by the kernel's guard.
    var turnId: ArisTurnID?
    /// Each stage the clock takes, for the kernel's event ring.
    var stageSink: ((ArisTurnID, ArisStageClock.Stage, Int) -> Void)?

    /// The stage happened (the clock keeps it, and the kernel's ring hears of it once).
    func mark(_ stage: ArisStageClock.Stage, at instant: ContinuousClock.Instant = .now, again: Bool = false) {
        let before = clock.marks[stage]
        clock.mark(stage, at: instant, again: again)
        guard clock.marks[stage] != before, let turnId, let ms = clock.milliseconds(stage) else { return }
        stageSink?(turnId, stage, ms)
    }
    /// The hands-free turn's end (nil for a turn held on the key: its release is the end).
    var turn: Turn?
    /// Apple's own words so far (session.heard shows Scribe's when Scribe hears).
    var appleText = ""
    /// Scribe was streaming when the speculation finished it: it starts again (replaying the turn) if the user goes on.
    var scribeWasOn = false
    /// Smart Turn's score at the plausible end, kept while it is pending (a click moves the voice and drops the score).
    var pendingScore: Float?
    var endCase: ArisEndpointCase?
    /// The router's answer for these words, asked during the pause (answer()'s route() takes it).
    var router: (text: String, task: Task<(intent: ArisIntent?, tier: ArisTier, browserWork: Bool), Never>)?
    /// The context the early request was sent with, and whether it began a new conversation.
    var earlyContext: String?
    var earlyFresh: Bool?
    /// The second listen ran out of budget this turn; a later, better transcript may still replace the words.
    var secondPassLate = false
    var late = ArisLateWords()
    /// What the second listen heard when it came after the budget (cleaned up as the turn's words are, in `stopListening`).
    var lateClean: ((String) -> String)?
    /// What each recogniser wrote (turns.jsonl).
    var recognized: (apple: String, whisper: String?)?

    /// A new turn began listening at `since`: everything of the last one goes (its request too).
    func begin(since: ContinuousClock.Instant) {
        turn?.drop()
        router?.task.cancel()
        self.since = since
        clock.begin(at: since)
        turnId = nil
        turn = nil
        appleText = ""
        scribeWasOn = false
        pendingScore = nil
        endCase = nil
        router = nil
        earlyContext = nil
        earlyFresh = nil
        secondPassLate = false
        late = ArisLateWords()
        lateClean = nil
        recognized = nil
    }

    /// The router's answer for `text`, when it was asked during the pause.
    func routed(_ text: String) -> Task<(intent: ArisIntent?, tier: ArisTier, browserWork: Bool), Never>? {
        router?.text == text ? router?.task : nil
    }
}
