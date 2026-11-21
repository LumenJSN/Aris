//
//  ArisTeachDesk.swift
//  aris-agent
//
//  The one demonstration under way (F3): it starts the observer only between the owner's "start" and his "done" (or
//  "배우기 취소", or the recorder's own limit), feeds it into the pure recorder, and hands the lesson on. The observer
//  is a port (the live one reads Accessibility notifications; the tests feed fake events), so nothing here reads a
//  real app in a test. Also the replay's binding to Core 2: the run's calls through ArisMindJudge on the trust gate,
//  the run's own calls on the tracker's replay-scoped channel, the steps' taught words as their app's content, and the
//  session forgotten when the run ends.
//

import Foundation

/// Watches what the owner does and calls `sink` with each event (from any thread).
protocol ArisTeachObserving: AnyObject {
    /// False when it can't watch (no Accessibility); it never asks for a permission.
    func start(sink: @escaping (ArisTeachEvent) -> Void) -> Bool
    func stop()
    /// As the lesson ends, before `stop`: the text elements his keys went into, read again (`readAtEnd` values), so what
    /// he typed is kept even when no change of it was reported while he typed (third VM run, D1).
    func closing() -> [ArisTeachEvent]
    /// Its key tap hears his keys one by one (Input Monitoring): the recorder then tells his typing from the app's own
    /// changes (ArisTeachRecorder.keysHeard).
    var hearsKeys: Bool { get }
}

extension ArisTeachObserving {
    func closing() -> [ArisTeachEvent] { [] }
    var hearsKeys: Bool { false }
}

final class ArisTeachDesk: @unchecked Sendable {
    enum Started: Equatable {
        case started
        case already(String)
        /// The observer couldn't start (no Accessibility).
        case cannot
    }

    private let lock = NSLock()
    private var recorder = ArisTeachRecorder()
    private var expiredName: String?
    let observer: ArisTeachObserving
    let now: () -> Date

    init(observer: ArisTeachObserving, now: @escaping () -> Date = Date.init) {
        self.observer = observer
        self.now = now
    }

    nonisolated(unsafe) static var shared = ArisTeachDesk(observer: ArisTeachLiveObserver())

    /// The name of the demonstration under way.
    var recording: String? { lock.withLock { recorder.name } }

    func start(name: String) -> Started {
        if let current = recording { return .already(current) }
        let hears = observer.hearsKeys
        let began = lock.withLock { () -> Bool in
            guard recorder.start(name: name, at: now()) else { return false }
            recorder.keysHeard = hears
            return true
        }
        guard began else { return .already(recording ?? name) }
        lock.withLock { expiredName = nil }
        guard observer.start(sink: { [weak self] event in self?.feed(event) }) else {
            lock.withLock { recorder.cancel() }
            return .cannot
        }
        return .started
    }

    /// One observed event; a demonstration past its limits ends by itself (nothing of it is kept).
    func feed(_ event: ArisTeachEvent) {
        let expired: Bool = lock.withLock {
            guard recorder.isRecording else { return false }
            if recorder.expired(at: now()) {
                expiredName = recorder.name
                recorder.cancel()
                return true
            }
            recorder.feed(event)
            return false
        }
        if expired { observer.stop() }
    }

    /// "다 했어": the observer stops and the lesson is handed on.
    func stop() -> ArisTeachRecorder.Lesson? {
        let read = observer.closing()
        observer.stop()
        return lock.withLock {
            recorder.close(read)
            return recorder.stop(at: now())
        }
    }

    /// "배우기 취소": the observer stops and nothing is kept. The name it had.
    @discardableResult
    func cancel() -> String? {
        observer.stop()
        return lock.withLock {
            let name = recorder.name
            recorder.cancel()
            return name
        }
    }

    /// The name of a demonstration that ended by itself since it was last asked, once.
    func takeExpired() -> String? {
        lock.withLock {
            defer { expiredName = nil }
            return expiredName
        }
    }
}

/// A replay of a taught procedure through Core 2's one decision.
struct ArisTeachRunner {
    let judge: ArisMindJudge
    let gate: ArisTrustGate
    /// Runs a call the decision let through (the Mind's executor by default).
    var execute: (ArisMindDecided, ArisMindJudge.Read, ArisUndoCaller) -> ArisMindResult

    init(judge: ArisMindJudge = .shared, gate: ArisTrustGate = .shared,
         execute: ((ArisMindDecided, ArisMindJudge.Read, ArisUndoCaller) -> ArisMindResult)? = nil) {
        self.judge = judge
        self.gate = gate
        self.execute = execute ?? { item, read, caller in
            // Typing is marked with the selection its decision saw, so app.type types nothing over any other (ArisTeachRunOnce).
            let arguments = Self.typing(read, erases: judge.outcome(session: caller.session ?? "", call: item.call.id)?.facts.erases)
            return ArisMindExecutor(tools: ArisAppBundle.toldTools, environment: [:]).run(read.entry, arguments: arguments, argv: read.argv, stdin: read.stdin, caller: caller,
                                                                                 judged: ArisMindExecutor.judged(item.verdict),
                                                                                 resolved: judge.resolved(session: caller.session ?? "", call: item.call.id))
        }
    }

    /// Runs `procedure` for the owner's words `words` (`rest`: the words after its name; `answered`: values he wrote on
    /// the card that asked for what their words didn't give). Blocks until it ends (a card waits for his answer): call it
    /// off the server's queue.
    func run(_ procedure: ArisTeachProcedure, words: String, rest: String, answered: [String: String] = [:],
             run: String = String(UUID().uuidString.prefix(8)).lowercased(),
             card: @escaping ArisMindJudge.Card, isCurrent: @escaping () -> Bool, progress: (Int, Int) -> Void = { _, _ in },
             goOn: (Int, String) -> Bool = { _, _ in false }, english: Bool = false, pass: ArisTeachRunPass? = nil,
             speaker: ArisTurnSpeaker = .notChecked, approvesAhead: Bool = true, carrying: String? = nil, carryingAll: Bool = false)
        -> (outcome: ArisTeachReplay.Outcome, plan: ArisTeachReplay.Plan) {
        let given = ArisTeachMatch.values(procedure, words: rest).merging(answered) { $1 }
        let plan = ArisTeachReplay.plan(procedure, given: given, words: words, run: run)
        let session = "teach-" + run
        let intent = session + "#1"
        // `speaker`: who spoke the turn that started it (F1). `carrying`: a model started it in that conversation, whose
        // outside text is this run's too; `approvesAhead` false: then no step is approved ahead (ArisMindTaught).
        judge.turn(session: session, intent: intent, words: words, speaker: speaker)
        judge.task(session: session, instruction: plan.instruction)
        if let carrying { gate.carryContent(from: carrying, to: session) }
        // A run by its name (no model, no conversation of its own): what Aris read in the owner's conversations is this
        // run's content too, so no step is decided blind to it (ArisTeachTurn says why such a run asks no card first).
        if carryingAll { gate.carryConversations(to: session) }
        for seen in plan.seen { gate.toolResult(session: session, call: nil, text: seen.text, source: seen.source) }
        if approvesAhead { gate.approve(session: session, steps: plan.approved) }
        // Each step's card says the step as the lesson does, in the UI's language (fifth VM run, D2).
        gate.describe(session: session, calls: ArisTeachReplay.described(procedure, plan: plan, english: english))
        let ports = judge.ports(session: session, task: nil, intent: intent, card: card, execute: execute, isCurrent: isCurrent)
        // Past a step that failed, on their yes: the rest under an intent of their own, so no earlier yes covers them (D7).
        var resumed = 1
        let afresh = { () -> ArisMindPorts in
            resumed += 1
            let next = session + "#\(resumed)"
            judge.nextIntent(session: session, intent: next)
            return judge.ports(session: session, task: nil, intent: next, card: card, execute: execute, isCurrent: isCurrent)
        }
        // His yes on the run's one card, for exactly the plan that card showed (ArisTeachRunOnce).
        let outcome = ArisTeachReplay.run(plan, ports: ports, progress: progress, goOn: goOn, afresh: afresh,
                                          approval: pass.map { approval($0, session: session) })
        gate.endApproval(session: session, run: run)
        judge.end(session: session)
        return (outcome, plan)
    }
}

/// The lesson each replay of this helper ran, by its record session ("teach-<run>"), so the undo of a run names the
/// lesson (seventh VM run, item 5). Memory only and the latest few: after a restart the reply names what was undone
/// without the lesson.
final class ArisTeachRunNames: @unchecked Sendable {
    static let shared = ArisTeachRunNames()
    static let kept = 20

    private let lock = NSLock()
    private var names: [(session: String, name: String)] = []

    init() {}

    func note(session: String, name: String) {
        lock.withLock {
            names.removeAll { $0.session == session }
            names = Array((names + [(session, name)]).suffix(Self.kept))
        }
    }

    func name(of session: String) -> String? {
        lock.withLock { names.last { $0.session == session }?.name }
    }
}
