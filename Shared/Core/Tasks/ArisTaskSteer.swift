//
//  ArisTaskSteer.swift
//  Shared/Core (aris-agent, tests)
//
//  An instruction the user adds to a background task while it runs ("아까 그거에 가격도 추가해줘"), as each brain can
//  take one. Codex's app-server takes a note into the turn under way (turn/steer, the same call the read judge's notes
//  use), and so does Claude Code's stream-json (a user message written during the turn joins it at its next step:
//  checked live on 2.1.327), so both hear it at their next step. Antigravity and an API brain can't be told mid-turn:
//  their notes wait (ArisSteerDesk), and when the task's turn gives its answer the same process is asked once more
//  with them (its next turn), and that turn's answer is the task's. The brain is told which happened, and says so.
//  Foundation only.
//

import Foundation

enum ArisTaskSteer {
    /// How a brain takes an added instruction.
    enum Support: String, Equatable {
        /// Into the turn under way (Codex turn/steer).
        case midTurn
        /// Held for the task's next turn in the same process (Antigravity, an API brain).
        case nextTurn
    }

    static func support(brain: String) -> Support { brain == "codex" || brain == "claude" ? .midTurn : .nextTurn }

    /// What became of an added instruction, as the tool says it back to the brain.
    enum Outcome: Equatable {
        /// The running turn has it now.
        case steered
        /// It waits for the task's current step to end; then the task takes it in a turn of its own.
        case queued
        /// Too many already wait, or it is empty or too long.
        case refused(String)
        /// No running task has that id (ended, or not this helper's).
        case notRunning
    }

    /// The most notes one task holds at once, and the longest note.
    static let maxNotes = 5
    static let maxLength = 2_000

    /// Why a note can't be held, or nil when it can.
    static func problem(_ note: String, waiting: Int) -> String? {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "the instruction is empty" }
        if text.count > maxLength { return "the instruction is longer than \(maxLength) characters" }
        if waiting >= maxNotes { return "\(maxNotes) instructions already wait for this task" }
        return nil
    }

    /// The words the brain gets back for each outcome.
    static func said(_ outcome: Outcome, brain: String) -> String {
        switch outcome {
        case .steered:
            return "added: the task (on \(ArisWorkInProgress.brainName(brain))) has the instruction now and works it into what it is doing."
        case .queued:
            return "queued: \(ArisWorkInProgress.brainName(brain)) can't take an instruction in the middle of a step, so the task takes it as soon " +
                "as its current step ends, before it reports. Tell the user it will be added after the current step."
        case .refused(let why): return "not added: \(why)."
        case .notRunning: return "not added: no running task has that id (it may have finished)."
        }
    }

    /// The note as the running Codex turn reads it (turn/steer).
    static func midTurnNote(_ note: String) -> String {
        "[Aris] The user added this to the task while you work on it (their words, relayed by the conversation): \(note)\n" +
            "Work it in, then finish as the task asks. If you have already given your answer, give your whole answer again as the task's " +
            "final result, in the same form, with this in it."
    }

    /// The next turn's question for a task whose brain couldn't take notes mid-turn: the notes, and that its answer is
    /// the task's whole result (its last answer was never delivered).
    static func followUp(_ notes: [String]) -> String {
        let listed = notes.map { "- " + $0 }.joined(separator: "\n")
        return "[Aris] While you worked, the user added this to the task (their words, relayed by the conversation):\n\(listed)\n" +
            "Your last answer has not been delivered. Do what was added, then give your whole answer again as the task's final " +
            "result, in the same form the task asks for (the line to say first, then the rest), with the addition in it."
    }
}

/// The notes waiting for each task's next turn, by job id. A value: every change gives a new queue.
struct ArisSteerQueue: Equatable {
    private(set) var notes: [String: [String]] = [:]

    func waiting(job: String) -> Int { notes[job.lowercased()]?.count ?? 0 }

    /// The queue with `note` added for `job`, or why it can't be.
    func adding(_ note: String, job: String) -> Result<ArisSteerQueue, ArisSteerRefusal> {
        let key = job.lowercased()
        if let why = ArisTaskSteer.problem(note, waiting: waiting(job: key)) { return .failure(ArisSteerRefusal(why: why)) }
        var next = notes
        next[key] = (notes[key] ?? []) + [note.trimmingCharacters(in: .whitespacesAndNewlines)]
        return .success(ArisSteerQueue(notes: next))
    }

    /// The notes for `job`, and the queue without them.
    func taking(job: String) -> (queue: ArisSteerQueue, notes: [String]) {
        let key = job.lowercased()
        guard let found = notes[key], !found.isEmpty else { return (self, []) }
        var next = notes
        next[key] = nil
        return (ArisSteerQueue(notes: next), found)
    }
}

struct ArisSteerRefusal: Error, Equatable {
    let why: String
}
