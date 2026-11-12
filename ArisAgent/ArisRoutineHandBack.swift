//
//  ArisRoutineHandBack.swift
//  aris-agent
//
//  A routine's step that needs no AI. "set a 1 minute timer", "tell me the time", "volume 30" or "add buy milk to my
//  to-do list" typed into the notch are done by the Aris app itself and never reach the agent; saved in a routine they
//  were asked of the agent's AI, so on a Mac with no AI a routine of nothing but such steps could not run (VM run
//  2026-11-11, bug 2). Now each step of a routine made of the user's own words is first offered back to the app on the
//  turn's stream (ArisRoutineLocalStep). The app reads it with the very rules it reads a typed sentence with and
//  answers on POST /routine-step: it did it, it tried and could not, or the words are not its own to do, and only
//  then is the AI asked, exactly as before.
//  Why this way round: the agent keeps the routine (its store, the order, the count in the notch, the one account at
//  the end), and the app keeps the acts (the timer lives in the app, the to-do goes through its Reminders access) and
//  the rules that decide what is local. Neither is copied into the other, so a stored step can do nothing a typed
//  sentence could not: it goes through the same parser, the same guard and the same act.
//  A step an AI worded is never offered (it is model-written text and stays behind the gates), nor is any step when
//  the app that asked doesn't take steps back (an older app). The rules are pure (tested); ArisRoutineTurn holds the
//  wait.
//

import Foundation

enum ArisRoutineHandBack {
    /// How long the agent waits for the app's word on a step it offered. The app's own acts take a moment (a to-do
    /// saved, an app opened, the player answering); past this the step counts as not done and the routine stops there.
    /// It is never asked of the AI instead: the app may have done it.
    static let wait: TimeInterval = 30

    /// Whether a step is offered to the app first. `own`: the routine's steps are the user's own words. `appTakesSteps`:
    /// the app said on this turn's request that it answers such offers.
    static func offers(own: Bool, appTakesSteps: Bool) -> Bool { own && appTakesSteps }

    /// What the app's answer is to the run: the step's own answer, its failure, or nil when the AI is to be asked.
    static func reply(_ outcome: ArisRoutineLocalOutcome) -> ArisAgentReply? {
        switch outcome {
        case .notLocal: return nil
        case .done(let said): return .answer(said)
        case .failed(let why): return .failure(why)
        }
    }

    /// The step's failure when the app never said how it ended.
    static func noWord(korean: Bool) -> String {
        korean ? "Aris 앱이 이 단계를 했는지 알려 주지 않았어요." : "The Aris app didn't say whether it did this step."
    }
}
