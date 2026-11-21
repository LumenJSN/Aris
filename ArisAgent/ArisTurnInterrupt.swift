//
//  ArisTurnInterrupt.swift
//  aris-agent
//
//  A conversation turn that timed out ends without losing its conversation when the brain can stop a turn: Claude
//  Code takes stream-json's interrupt control request, Codex's app-server `turn/interrupt`. The turn is over for the user
//  at once ("took too long"); the process is kept and drained: what the stopped turn still writes is dropped (a
//  protocol reply it needs is still sent) until the brain says that turn ended, and a question that comes meanwhile
//  waits for that. A brain that says nothing within the grace is stopped as before. The API helper and Antigravity
//  can't be interrupted: their process is stopped as before.
//

import Foundation

/// A brain whose turn under way can be stopped without ending its process.
protocol ArisInterruptibleDriver: AnyObject {
    /// The lines that stop the turn under way; nil when no turn is open.
    func interruptLines() -> [Data]?
    /// Once the stopped turn ended: the lines that take it out of the conversation (a question the app dropped because
    /// The user went on talking, sent again whole). Nil when the brain can't, or the turn must stay (it called a tool).
    func dropLines() -> [Data]?
    /// Whether `line` answers the drop (either way), and whether the turn was taken out.
    func dropAnswer(_ line: String) -> (answered: Bool, dropped: Bool)
}

extension ArisInterruptibleDriver {
    func dropLines() -> [Data]? { nil }
    func dropAnswer(_ line: String) -> (answered: Bool, dropped: Bool) { (false, false) }
}

extension ArisClaudeDriver: ArisInterruptibleDriver {
    /// stream-json's control request (the one the Agent SDK sends; claude 2.1.327 carries `subtype:"interrupt"`). The
    /// CLI ends the turn with a result line, error_during_execution, within milliseconds (checked live on 2.1.327); the
    /// process answers the next question, and the cut-off question and its partial answer stay in the conversation.
    func interruptLines() -> [Data]? {
        noteInterrupt()
        return [Self.line(["type": "control_request", "request_id": "aris-interrupt-\(UUID().uuidString.prefix(8))", "request": ["subtype": "interrupt"]])]
    }

    /// `rewind_conversation` to the turn's question (checked live on 2.1.327: answered `rewound: true`, and the next
    /// turn's conversation no longer holds it).
    func dropLines() -> [Data]? { rewindLines() }

    func dropAnswer(_ line: String) -> (answered: Bool, dropped: Bool) {
        let answer = rewindAnswer(line)
        return (answer.answered, answer.rewound)
    }
}

/// The stopped turn's leftovers, on the runner's queue.
struct ArisTurnDrain {
    /// How long the brain has to say the turn ended before its process is stopped.
    static let grace: TimeInterval = 10

    private(set) var active = false
    /// Which drain this is: a grace timer of an earlier drain never stops a later one on the same process.
    private(set) var generation = 0
    private var waiting: [Waiting] = []

    /// A question that came while draining, and the connection it came on.
    private struct Waiting {
        let owner: AnyObject?
        let run: () -> Void
        let drop: () -> Void
    }

    /// The stopped turn is to be taken out of the conversation once it ends (a question the app dropped), and the drain
    /// then waits for the brain's answer to that.
    private(set) var dropsTurn = false
    private(set) var awaitingDrop = false

    /// Begins a drain; its generation, for its grace timer (which also bounds the wait for a drop's answer).
    @discardableResult
    mutating func begin(dropTurn: Bool = false) -> Int {
        active = true
        dropsTurn = dropTurn
        awaitingDrop = false
        generation += 1
        return generation
    }

    /// The stopped turn ended and its drop was asked for: the drain goes on until the brain answers it.
    mutating func awaitDrop() {
        dropsTurn = false
        awaitingDrop = true
    }

    /// Whether drain `generation` is still the one under way.
    func isCurrent(_ generation: Int) -> Bool { active && generation == self.generation }

    /// A question that came while draining: run when the drain ends (either way), unless its connection is dropped
    /// first (`drop(owner:)`: then `dropped` runs instead and the question never starts).
    mutating func afterDrain(owner: AnyObject? = nil, dropped: @escaping () -> Void = {}, _ work: @escaping () -> Void) {
        waiting.append(Waiting(owner: owner, run: work, drop: dropped))
    }

    /// The app dropped `owner`'s stream while its question waited: that question goes, never to run. What it leaves to
    /// do (its `dropped`), to run now; empty when it had none waiting.
    mutating func drop(owner: AnyObject) -> [() -> Void] {
        let gone = waiting.filter { $0.owner === owner }
        waiting.removeAll { $0.owner === owner }
        return gone.map(\.drop)
    }

    /// The drain is over: what waited, to run now.
    mutating func end() -> [() -> Void] {
        active = false
        dropsTurn = false
        awaitingDrop = false
        defer { waiting = [] }
        return waiting.map(\.run)
    }

    /// Whether these events end the stopped turn.
    static func ends(_ events: [ArisBrainEvent]) -> Bool {
        events.contains { event in
            switch event {
            case .result, .failure, .unavailable, .abort: return true
            default: return false
            }
        }
    }

    /// Whether these events stop the process (a sealed Claude's rule backstop, an unchecked web result): it is stopped
    /// even while draining, as outside a drain.
    static func aborts(_ events: [ArisBrainEvent]) -> Bool {
        events.contains { if case .abort = $0 { return true } else { return false } }
    }

    /// The lines of these events that must still go back to the brain (its protocol's own replies), every approval
    /// among them turned into a decline: nothing the stopped turn asks for is allowed.
    static func replies(_ events: [ArisBrainEvent]) -> [Data] {
        events.compactMap { if case .send(let data) = $0 { return declined(data) } else { return nil } }
    }

    /// `line` with any yes in it made a no: Codex's approval answer ({"result": {"decision"}} or {"result": {"action"}}),
    /// the API helper's {"type": "allow"}. Any other line as it is.
    static func declined(_ line: Data) -> Data {
        guard var object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return line }
        if object["type"] as? String == "allow" {
            return ArisClaudeDriver.line(["type": "deny", "id": object["id"] ?? "", "reason": "The turn was stopped: nothing more runs in it."])
        }
        guard var result = object["result"] as? [String: Any] else { return line }
        if let decision = result["decision"] as? String, decision != "decline", decision != "cancel" { result["decision"] = "decline" }
        if let action = result["action"] as? String, action != "decline", action != "cancel" {
            result = ["action": "decline"]
        }
        object["result"] = result
        return ArisClaudeDriver.line(object)
    }
}
