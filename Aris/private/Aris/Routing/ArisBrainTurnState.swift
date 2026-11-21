//
//  ArisBrainTurnState.swift
//  Aris
//
//  What one brain turn has seen so far (askAndSpeak), in one value the turn's task owns (ARCHITECTURE.md 3.1, step 4):
//  made fresh for each turn and gone with it, so nothing of one turn's cards, taint or jobs can carry into the next.
//  These were ten-odd loose locals of askAndSpeak. Foundation only.
//

import Foundation

struct ArisBrainTurnState {
    /// "확인해 볼게요" or "알아볼게요" was said while nothing else had been.
    var saidHold = false
    /// The agent's id for this turn when its answer dispatches a Claude Code job (it vouches for that job).
    var turnId: String?
    /// The agent counts this turn as outside content (the screen, or others' words): its answer dispatches only when the
    /// agent says it may (a screen turn: every job untrusted, a Claude Code launch always asks the user).
    var untrustedTurn = false
    var dispatchAllowed = false
    /// Something readable was said this turn (code and JSON never are: ArisSpeakable).
    var saidAnything = false
    /// The agent took this turn's jobs block out (its refusedJobs line).
    var refusedJobs = false
    /// aris-agent said it answers this turn itself (ArisAgentReply.helperAnswers).
    var helperAnswers = false
    /// A hands-free turn read the user's messages, mail or notes: shown, never spoken (its shownOnly line).
    var shownOnly = false
    /// A card of this turn nobody answered, one the user said no to, one they said yes to: the reply is told in their terms
    /// (QA BUG-39, BUG-43).
    var cardUnanswered = false, cardDeclined = false, cardApproved = false
    /// The steps a no dropped in this turn, by their tool: a status for one of them is ignored until a later yes.
    var declinedTools: Set<String> = []

    /// The answer waits whole: after a card nobody answered or the user said no to, it may be rewritten in their terms.
    var holdsAnswer: Bool { cardUnanswered || cardDeclined }

    /// A card's answer, as the turn keeps it: `stopped` is the automatic check's card (its 그래도 하기 approves nothing).
    mutating func answered(allow: Bool, unanswered: Bool, stopped: Bool, waiting: Set<String>) {
        declinedTools = allow ? [] : declinedTools.union(waiting)
        if !allow { if unanswered { cardUnanswered = true } else { cardDeclined = true } } else if !stopped { cardApproved = true }
    }
}
