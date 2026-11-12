//
//  ArisSession.swift
//  Aris
//
//  One turn with Aris: listen while the key is held, think, then speak.
//  Each step returns a new value, so the notch view always draws a whole state.
//

import Foundation

/// Something the AI did during a turn ("웹 검색 중"): running while it works, done once it moved on or answered. One
/// per tool: the tool's next status relabels it in place (보는 중 → 쓰는 중), so `id` (its place in the turn) stays.
struct ArisStep: Equatable, Identifiable {
    let label: String
    var done = false
    /// The agent said this step ended with an error (its command exited non-zero, its tool result was an error): the
    /// tag shows that instead of a tick (VM run 2026-11-10: "Adding a to-do ✓" under "I couldn't add it").
    var failed = false
    var id = 0

    /// The tool a status is about: its first word ("웹 검색 중" and "웹 페이지 읽는 중" are both "웹").
    static func tool(of label: String) -> String {
        label.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
    }
}

/// How a dictated message's countdown ended (the owner's pick C): the card settles into one line saying so.
struct ArisCountdownEnd: Equatable {
    /// Who it went to, and the message (ArisConfirmation's title and detail for a countdown).
    let to: String
    let message: String
    /// The countdown let it go (it is on its way to Messages, which is all the app knows: the card says "보내는 중",
    /// and the answer says whether it went out); false when the user stopped it.
    let sent: Bool
    /// Not a message at all: the automatic check's stopped card was answered 하지 않기 (ArisStoppedCard), and this is the
    /// action that was not done ("할 일 추가"), for the one settled line.
    var stopped: String? = nil
    /// That line is said in English (the card was drawn in English).
    var stoppedEnglish = false
}

struct ArisSession: Equatable {
    enum Phase: Equatable { case idle, listening, thinking, speaking, failed }

    private(set) var phase: Phase = .idle
    /// What Aris heard so far (live while listening).
    private(set) var heard = ""
    /// Aris's answer (growing while it's written), or what went wrong.
    private(set) var reply = ""
    /// What the AI did this turn, in order; one step per tool. Kept, done, under the answer (the activity tags).
    private(set) var steps: [ArisStep] = []
    /// What the AI is doing right now: the running step, else the last one.
    var status: String { (steps.first { !$0.done } ?? steps.last)?.label ?? "" }

    /// The tag that runs while the AI works without saying what at.
    static var thinkingLabel: String { ArisUIWords.thinking }

    /// The activity tags under the turn: its steps, with 생각 중 running after them while the AI works and no step
    /// runs; none while listening or while the confirm card has the result slot.
    var tags: [ArisStep] {
        switch phase {
        case .listening: return []
        // 생각 중 holds the next tag's place, so the first status relabels it rather than replacing it.
        case .thinking: return steps.contains { !$0.done } ? steps : steps + [ArisStep(label: Self.thinkingLabel, id: steps.count)]
        case .speaking, .idle, .failed: return question == nil ? steps : []
        }
    }
    /// Something the AI wants to do that waits for the user's yes.
    private(set) var question: ArisConfirmation?
    /// The reply is a card's title and words, left up after the card was answered (a job's card: its Aside brief, for
    /// one). The notch folds it to two lines (ArisSettledCardText) so it doesn't take the answer's room.
    private(set) var settledCard = false
    /// A dictated message's countdown ended: set while its card is still up, kept through the answer to it and the AI's
    /// work after, gone with whatever comes next (its answer, a failure, a new turn).
    private(set) var countdownEnd: ArisCountdownEnd?

    func listening() -> ArisSession {
        ArisSession(phase: .listening, heard: "", reply: "")
    }

    /// The recognizer's latest guess replaces the previous one.
    func hearing(_ text: String) -> ArisSession {
        guard phase == .listening else { return self }
        return ArisSession(phase: .listening, heard: text, reply: reply)
    }

    /// The key was released; nothing heard means there is nothing to do.
    func thinking() -> ArisSession {
        let said = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        let saidSomething = said.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
        return ArisSession(phase: saidSomething ? .thinking : .idle, heard: said, reply: "")
    }

    /// A status runs in its tool's step, relabelled in place (one tag per task); a tool not seen this turn is a new
    /// step. The others are done.
    func working(_ status: String) -> ArisSession {
        guard phase == .thinking, !status.isEmpty, status != self.status || steps.allSatisfy(\.done) else { return self }
        let tool = ArisStep.tool(of: status)
        let own = steps.firstIndex { ArisStep.tool(of: $0.label) == tool }
        let next = steps.enumerated().map { index, step in
            index == own ? ArisStep(label: status, id: step.id) : ArisStep(label: step.label, done: true, failed: step.failed, id: step.id)
        }
        return ArisSession(phase: .thinking, heard: heard, reply: reply,
                           steps: own == nil ? next + [ArisStep(label: status, id: steps.count)] : next, countdownEnd: countdownEnd)
    }

    /// The tools of the steps still running: what a no on the card drops (`answered(allowed: false)`).
    var runningTools: Set<String> { Set(steps.filter { !$0.done }.map { ArisStep.tool(of: $0.label) }) }

    /// Whether a status is left out because it is about a step that was declined in this turn: the helper's "still
    /// going" line for a job the no called off can arrive after the no, and would put the step back for the answer
    /// to tick (fourth VM run, bug 2). `declined`: the tools of the steps a no dropped, until a later yes.
    static func ignoresStatus(_ status: String, declined: Set<String>) -> Bool {
        declined.contains(ArisStep.tool(of: status))
    }

    /// Every step finished: the AI is answering, asking, done or failed. A step that failed stays marked.
    private var finishedSteps: [ArisStep] { steps.map { ArisStep(label: $0.label, done: true, failed: $0.failed, id: $0.id) } }

    /// The agent says a step ended with an error. `label`: the step's status when the agent knows which (matched by its
    /// tool, as a status is); else, or when no step has that tool, the step running now, else the last one. Only while
    /// the AI works: after the answer nothing changes.
    func stepFailed(_ label: String?) -> ArisSession {
        guard phase == .thinking, !steps.isEmpty else { return self }
        let named = label.flatMap { label in steps.firstIndex { ArisStep.tool(of: $0.label) == ArisStep.tool(of: label) } }
        let index = named ?? steps.firstIndex { !$0.done } ?? steps.count - 1
        var next = self
        next.steps = steps.enumerated().map { offset, step in
            offset == index ? ArisStep(label: step.label, done: true, failed: true, id: step.id) : step
        }
        return next
    }

    /// Aris speaks up on its own: a background task (`title`) is done.
    static func announcing(_ title: String, _ text: String) -> ArisSession {
        ArisSession(phase: .speaking, heard: title, reply: text)
    }

    /// Aris asks before the AI acts: the exact details are on screen.
    func asking(_ ask: ArisConfirmation) -> ArisSession {
        ArisSession(phase: .speaking, heard: heard, reply: ask.title + "\n" + ask.detail, steps: steps, question: ask)
    }

    /// A dictated message's countdown ran out or was stopped: its card says whether the message went.
    func counted(sent: Bool) -> ArisSession {
        guard let question, question.countdown else { return self }
        var next = self
        next.countdownEnd = ArisCountdownEnd(to: question.title, message: question.detail, sent: sent)
        return next
    }

    /// The stopped card was answered 하지 않기: it settles into one line that says so, until the answer takes the slot.
    func stoppedSettled(english: Bool = false) -> ArisSession {
        guard let question, question.stopped else { return self }
        var next = self
        next.countdownEnd = ArisCountdownEnd(to: "", message: "", sent: false, stopped: ArisStoppedCopy.action(of: question), stoppedEnglish: english)
        return next
    }

    /// The user answered; the AI carries on. A countdown's end stays up only when the agent got the answer (`delivered`).
    /// `allowed`: he said yes. The step that waited on the card is not finished by his answer: after a yes it is the
    /// step that runs now, under its own name and with its clock from the yes, and it gets its tick when the AI moves
    /// on or answers (third VM run, bug C: it was ticked at the yes, "Converting video or sound ✓" beside a running
    /// "Thinking" while the conversion was only starting, and a stop then kept that false tick). After a no (or no
    /// answer) it did not run: it goes, never ticked, as a step cut off by a stop does. What had finished before the
    /// card keeps its check either way.
    func answered(delivered: Bool = true, allowed: Bool = true) -> ArisSession {
        guard question != nil else { return self }
        return ArisSession(phase: .thinking, heard: heard, steps: allowed ? steps : steps.filter(\.done),
                           countdownEnd: delivered ? countdownEnd : nil)
    }

    /// A settings page the answer points to is named as the settings window names it on this Mac (ArisSettingsPath).
    func answering(_ text: String) -> ArisSession {
        ArisSession(phase: .speaking, heard: heard, reply: ArisSettingsPath.shown(text), steps: finishedSteps)
    }

    /// The turn failed. A step that was still running did not finish: it goes, never ticked (as after a stop), unless
    /// the agent marked it failed; what had finished keeps its check.
    func failing(_ message: String) -> ArisSession {
        ArisSession(phase: .failed, heard: heard, reply: message, steps: steps.filter { $0.done || $0.failed })
    }

    /// The failure's line changed while it shows (the helper is running again): the same turn, with what is true now.
    func corrected(_ line: String) -> ArisSession {
        guard phase == .failed || phase == .idle, question == nil else { return self }
        var next = self
        next.reply = line
        return next
    }

    func done() -> ArisSession {
        ArisSession(phase: .idle, heard: heard, reply: reply, steps: finishedSteps, settledCard: settledCard || question != nil)
    }

    /// The user stopped the work from its tag: `line` says where it stopped (ArisStopLine). What had finished keeps its
    /// check; the step that was cut off goes, never ticked.
    func stopped(_ line: String) -> ArisSession {
        ArisSession(phase: .idle, heard: heard, reply: line, steps: steps.filter(\.done))
    }

    /// Idle, with an earlier answer kept for when the notch opens again (the parked answer).
    static func parked(heard: String, reply: String) -> ArisSession {
        ArisSession(phase: .idle, heard: heard, reply: reply)
    }
}
