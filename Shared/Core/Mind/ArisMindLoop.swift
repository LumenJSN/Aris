//
//  ArisMindLoop.swift
//  Shared/Core (aris-agent, tests)
//
//  The session loop (ARCHITECTURE Part 2, Mind): one turn is the owner's words, then rounds of "the provider thinks,
//  Aris runs what it asked for" until the model stops. Text streams to the app as it arrives; every round's calls go
//  through ArisMindStep (the one decision, one card per intent, parallel runs, the record). The same loop serves a
//  spoken turn, a typed turn and a background task: they differ in budget (rounds, ArisTurnLimits) and in how they
//  report, not in machinery. Budgets are by silence and a ceiling (ArisSilenceClock, from jv-tasks): a card the owner
//  is looking at holds the clock. A turn that is no longer current (ArisMindPorts.isCurrent) stops where it is: no more
//  text to the app, no call run, and the conversation it returns is the one it was given. Pure.
//

import Foundation

final class ArisMindLoop: @unchecked Sendable {
    struct Budget: Equatable, Sendable {
        var rounds: Int
        var limits: ArisTurnLimits

        /// A conversation's turn (ArisAPIDriver.roundBudget's numbers) and a background task's.
        static let chat = Budget(rounds: 24, limits: .chat)
        static let task = Budget(rounds: 40, limits: .job)
    }

    static let roundsLine = "작업 단계가 너무 많아 여기서 멈췄어요. (Stopped: too many steps for one turn.)"
    static let silenceLine = "응답이 너무 오래 없어서 멈췄어요. (Stopped: nothing came for too long.)"

    let provider: ArisMindProvider
    let tools: [ArisMindToolSpec]
    let ports: ArisMindPorts
    let budget: Budget
    /// The UI reads English: the loop's own lines (the notice after content's changes, the line after a no) follow it.
    var english = false
    private let now: () -> Date
    private let lock = NSLock()
    private var cancelled = false

    init(provider: ArisMindProvider, tools: [ArisMindToolSpec], ports: ArisMindPorts, budget: Budget = .chat, now: @escaping () -> Date = Date.init) {
        self.provider = provider
        self.tools = tools
        self.ports = ports
        self.budget = budget
        self.now = now
    }

    /// Stops the turn under way (the owner cut in, or a newer turn began).
    func cancel() {
        lock.withLock { cancelled = true }
        provider.cancel()
    }

    private var isLive: Bool { !lock.withLock { cancelled } && ports.isCurrent() }

    /// One turn. `history`: the conversation so far (the owner's earlier turns, the model's answers and calls).
    /// Returns how it ended and the conversation to keep: with this turn added, or, for a stale turn, `history` as given.
    func turn(system: String, history: [ArisMindMessage], owner: String, output: @escaping (ArisMindOutput) -> Void) -> (end: ArisMindEnd, history: [ArisMindMessage]) {
        var messages = history + [.owner(owner)]
        // What content suggested and was done, across the turn's rounds: said once, when the turn ends.
        var suggested: [String] = []
        let notice = { [self] in
            if !suggested.isEmpty, isLive { output(.said(ArisMindStep.saidLine(suggested, english: english))) }
        }
        let clock = ArisMindClock(ArisSilenceClock(limits: budget.limits, at: now()))
        for _ in 0..<max(1, budget.rounds) {
            guard isLive else { return (.stale, history) }
            let said = ArisMindSaid()
            let end = provider.send(system: system, messages: messages, tools: tools) { [self] event in
                clock.heard(now())
                switch event {
                case .text(let piece):
                    said.add(piece)
                    if isLive { output(.delta(piece)) }
                case .toolCall(let call): said.add(call)
                }
            }
            guard isLive else { return (.stale, history) }
            switch end {
            case .failed(let why): return (.failed(why), history)
            case .cancelled: return (.stale, history)
            case .done: break
            }
            let (text, calls) = said.taken
            messages.append(.assistant(text: text, calls: calls))
            guard !calls.isEmpty else {
                notice()
                return (.answered(text), messages)
            }
            if let why = clock.expired(now()) {
                notice()
                return (.stopped(why == .silence ? Self.silenceLine : Self.roundsLine), messages)
            }
            let step = ArisMindStep.run(calls, ports: ports)
            // The card wait and the calls themselves were activity, not silence.
            clock.heard(now())
            guard !step.stale, isLive else { return (.stale, history) }
            for result in step.results {
                messages.append(.tool(id: result.id, name: result.name, text: result.result.text, isError: result.result.isError))
            }
            suggested += step.said
            // He said no to a card (or didn't answer): the turn ends here with one honest line, and the model gets no
            // further round to try it another way (tenth VM run, item 6).
            if step.declined {
                let line = ArisMindStep.declinedLine(english: english, unanswered: step.unanswered)
                messages.append(.assistant(text: line, calls: []))
                output(.delta((text.isEmpty ? "" : "\n") + line))
                notice()
                return (.answered(text.isEmpty ? line : text + "\n" + line), messages)
            }
        }
        notice()
        return (.stopped(Self.roundsLine), messages)
    }
}

/// The silence clock, shared with the provider's callback.
private final class ArisMindClock: @unchecked Sendable {
    private let lock = NSLock()
    private var clock: ArisSilenceClock

    init(_ clock: ArisSilenceClock) { self.clock = clock }

    func heard(_ at: Date) { lock.withLock { clock.heard(at: at) } }
    func expired(_ at: Date) -> ArisSilenceClock.Why? { lock.withLock { clock.expired(at: at) } }
}

/// One round's text and calls, as they stream in.
private final class ArisMindSaid: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""
    private var calls: [ArisMindToolCall] = []

    func add(_ piece: String) { lock.withLock { text += piece } }
    func add(_ call: ArisMindToolCall) { lock.withLock { calls.append(call) } }
    var taken: (String, [ArisMindToolCall]) { lock.withLock { (text, calls) } }
}
