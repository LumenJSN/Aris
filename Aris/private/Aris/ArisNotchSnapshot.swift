//
//  ArisNotchSnapshot.swift
//  Aris
//
//  What the root notch view (ContentView) needs from Aris's state: whether a turn is on, its phase, whether an answer
//  is parked, whether a job runs. A streaming answer changes the session thirty times a second; none of those changes
//  reach the root view unless one of these few facts changed (ArisNotchState publishes only a new snapshot).
//

import Foundation

struct ArisNotchSnapshot: Equatable {
    let phase: ArisSession.Phase
    /// The session has a reply (parked after the turn, or being written).
    let hasReply: Bool
    let isTraining: Bool
    let isDictating: Bool
    /// The dictation had nowhere to type: its words were copied and its card shows (ArisDictationCopy).
    let dictationCopied: Bool
    let hasUnfinishedTask: Bool
    let taskJustFinished: Bool
    /// A confirmation or question is waiting for the user's answer.
    let hasQuestion: Bool
    /// Listening between turns of a conversation: the closed band shows the calm listening state.
    let conversing: Bool
    /// That listening is paused while another app plays or records: the band shows it paused (still, dimmer).
    let listeningPaused: Bool

    /// As ArisController.isActive: a turn is on, or the wake word is being trained.
    var isActive: Bool { phase != .idle || isTraining }

    /// The turn holds the open notch (BUGS-notch N1): any phase but idle, or a question waiting.
    var holdsNotch: Bool { ArisNotchSnapshot.holds(phase: phase, questionPending: hasQuestion) }

    static func holds(phase: ArisSession.Phase, questionPending: Bool) -> Bool {
        phase != .idle || questionPending
    }

    init(session: ArisSession, isTraining: Bool, isDictating: Bool, hasUnfinishedTask: Bool, taskJustFinished: Bool, inConversation: Bool = false,
         pausedForOtherAudio: Bool = false, dictationCopied: Bool = false, cardWaiting: Bool = false) {
        phase = session.phase
        hasReply = !session.reply.isEmpty
        self.isTraining = isTraining
        self.isDictating = isDictating
        self.dictationCopied = dictationCopied
        self.hasUnfinishedTask = hasUnfinishedTask
        self.taskJustFinished = taskJustFinished
        // A card of the app's own waiting for the user (the new-teammate card) holds the notch like a confirm card (QA retest:
        // the notch closed when the turn ended and the card showed only on hover).
        hasQuestion = session.question != nil || cardWaiting
        conversing = inConversation && session.phase == .idle
        listeningPaused = conversing && pausedForOtherAudio
    }
}
