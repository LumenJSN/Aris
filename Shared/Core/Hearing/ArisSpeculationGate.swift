//
//  ArisSpeculationGate.swift
//  Aris (Shared/Core, Foundation only)
//
//  Which spoken requests may go to aris-agent before the turn is sure it is over (the speculative turn). A speculative
//  request must never do anything twice, so it only goes where nothing irreversible can happen before its first reply
//  that the app sees and can hold:
//
//  - Only the plain brain path: every request the Mac answers itself (timers, music, to-dos, volume, opening apps, the
//    currency card, teammates, skills, hand-offs, background jobs) acts at once, so it waits for the firm end as before.
//    So do the screen ("이거", circled shots, files given to Aris), a borderline wake, a card or question that is up, a
//    hand-off Aris asked about, and a follow-up that may be "됐어".
//  - aris-agent answers some words itself before any brain runs, and some of those write without a step or a card the
//    app would see first: "기억해 / 잊어" (the memory store) and routines ("… 루틴"). Words that may be one of them are
//    never speculated (`helperActsOn`); "기억나?" is caught too, which only means it waits as before.
//  - Everything a brain does shows first as a status line, a card or a desktop step (ArisReplyKind.action): the turn
//    then commits at once instead of cancelling (ArisEndpointDriver.reply), so a step is never started twice. Learned
//    shortcuts and saved desktop steps show their step line before they run, so they commit the same way.
//

import Foundation

enum ArisSpeculationGate {
    /// Why a request waits for the firm end (for the endpoint log); nil when it may go early.
    enum Block: String, Equatable, Sendable {
        case noWords, notPlain, helperWords, screen, gesture, files, card, wakeEvidence, echo, followUpDone, typed, practice, dictation
    }

    /// What the app knows about the turn when its end becomes plausible.
    struct Turn: Equatable, Sendable {
        var words: String
        /// The words take the plain brain path: no local intent, no hand-off, no teammate, no job (the app's own matchers).
        var plainBrainPath: Bool
        var pointsAtScreen = false
        var gesture = false
        var filesWaiting = false
        var cardUp = false
        var wakeEvidence = false
        /// Heard without the key (a follow-up or the wake word) and the echo guard did not say it is the user.
        var echoDoubt = false
        var followUpDone = false
        var typed = false
        var practice = false
        var dictation = false
    }

    static func block(_ turn: Turn) -> Block? {
        let words = turn.words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return .noWords }
        if turn.dictation { return .dictation }
        if turn.practice { return .practice }
        if turn.typed { return .typed }
        if turn.wakeEvidence { return .wakeEvidence }
        if turn.echoDoubt { return .echo }
        if turn.cardUp { return .card }
        if turn.followUpDone { return .followUpDone }
        if turn.gesture { return .gesture }
        if turn.filesWaiting { return .files }
        if turn.pointsAtScreen { return .screen }
        if helperActsOn(words) { return .helperWords }
        if !turn.plainBrainPath { return .notPlain }
        return nil
    }

    /// Words aris-agent may act on by itself, before any brain and without a step line: memory and routines.
    static func helperActsOn(_ words: String) -> Bool {
        let lower = words.lowercased()
        let korean = ["기억", "잊어", "잊지", "잊어버", "까먹", "루틴"]
        let english = [#"\bremember\b"#, #"\bforget\b"#, #"\bforgot\b"#, #"\broutines?\b"#, #"\bmemor(y|ies|ize)\b"#]
        if korean.contains(where: { lower.contains($0) }) { return true }
        return english.contains { lower.range(of: $0, options: .regularExpression) != nil }
    }
}
