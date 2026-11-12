//
//  ArisRoutineStep.swift
//  Aris
//
//  A routine's step that the app does by itself. aris-agent offers each step of a routine made of the user's own words back
//  to the app before it asks any AI (ArisRoutineLocalStep, on the turn's stream). Here: which steps the app takes, and
//  how what happened is told. The step is read by the very rules a typed sentence is read by (ArisIntent.parse, then
//  the one guard every local act passes), so a step saved in a routine can do nothing the same words typed could not:
//  a question, a "don't", a sentence that goes on with another request, or anything naming an AI is not the app's, and
//  goes to the AI as it did before this existed.
//  A few local answers stay the AI's turn inside a routine, as before: the ones that put a card or a reading of their
//  own in the notch (the brief, the day's wrap-up, undo, "read it", saving the last answer, windows in a grid), and the
//  to-do list read out (its titles can be other people's words, which a typed turn keeps out of what is remembered;
//  a routine's account would carry them).
//  Foundation only, so it is tested.
//

import Foundation

enum ArisRoutineStepRule {
    /// The local act these words are, when the app would have done them by itself had he typed them; nil for the AI's.
    static func act(for words: String) -> ArisIntent? {
        let said = words.trimmingCharacters(in: .whitespacesAndNewlines)
        // "GPT한테 물어봐, …" names an AI; "됐어" or "stop" alone ends a conversation when typed, and does nothing here.
        guard !said.isEmpty, said.count <= ArisRoutineLocalStep.longest, ArisBrain.pick(from: said) == nil, !ArisFollowUp.isDone(said) else { return nil }
        let intent = ArisIntent.guarded(ArisIntent.parse(said), said: said)
        switch intent {
        case .ask, .listTodos, .brief, .dayEnd, .undo, .readAgain, .saveAnswer, .arrange: return nil
        default: return intent
        }
    }

    /// How a step that the app answered with `reply` ended: done, unless the reply is the line that says the act did
    /// not happen (the sound output has no volume the Mac can set, the display no brightness, macOS didn't open the
    /// app). The lines are told apart by making them again from the functions that make them, never by their words.
    /// A true line about nothing to change ("No timer is running.", "The volume is already at its highest.") is the
    /// step's answer, as it is when typed.
    static func ended(_ intent: ArisIntent, reply: String, korean: Bool) -> ArisRoutineLocalOutcome {
        if let control = ArisControl(intent), reply == control.reply(changed: false, korean: korean) { return .failed(reply) }
        if case .openApp(let name) = intent, reply == ArisLocalReply.appNotOpened(ArisIntent.displayName(name, korean: korean), korean: korean) {
            return .failed(reply)
        }
        return .done(reply)
    }

    /// A to-do the step added, or why it wasn't (Reminders is off for Aris, it named nothing, Reminders refused it).
    static func added(_ outcome: ArisTodoAdded, korean: Bool) -> ArisRoutineLocalOutcome {
        let reply = ArisLocalReply.todoAdded(outcome, korean: korean)
        if case .saved = outcome { return .done(reply) }
        return .failed(reply)
    }

    /// The player's answer to a play, pause, next or previous.
    static func played(_ media: ArisIntent.Media, done: Bool, korean: Bool) -> ArisRoutineLocalOutcome {
        let reply = media.reply(done: done, korean: korean)
        return done ? .done(reply) : .failed(reply)
    }
}
