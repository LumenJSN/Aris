//
//  ArisTeachReplay.swift
//  Shared/Core/Teach (aris-agent, tests, swift test)
//
//  Doing a taught procedure again (ARCHITECTURE Part 3, F3): its steps become the app layer's calls with the run's
//  values filled in, executed directly as those capability calls (no model re-reads them), each through ArisMindStep,
//  the one way anything happens in Core 2: the one trust decision, the owner's card when it is due, the record.
//  Nothing is approved ahead by the lesson itself; since 2026-11-19 the owner may say yes once, up front, to the run's
//  one card, which is a pass for exactly the plan shown and never for a step that erases, sends, deletes or pays
//  (ArisTeachRunPass). The owner's instruction for the run is only what he said or wrote: the procedure's name,
//  their words for this run, the values he gave. The steps' own words (labels, titles, values read from an app) go to
//  the provenance tracker as that app's content, marked as a taught step's, so they stay data and ground nothing else;
//  and each call is registered on the tracker's replay-scoped channel (ArisApprovedStep: valid once, for that exact
//  call only, never part of the earlier words), which only keeps a step's own taught words from counting against it.
//  So a reversible step runs with its undo, and a permanent or sending step asks, exactly as the trust table has it
//  for Aris's own step. Steps run one at a time and each is checked: the first that is refused or declined stops the
//  run, and the account says which. A step that ran and failed (the app changed, a control isn't there) is said, and
//  the owner is asked whether to go on with the steps left (fifth VM run, D7: the run used to stop there in silence
//  when a later step stood on it); only their yes goes on, and every step after it is decided afresh, under an intent of
//  its own, so no earlier yes covers it. The account names every step left out. Each step's card words that step as
//  the lesson does ("choose ‘File › New’ in TextEdit"), never the call's syntax (D2). Pure.
//

import Foundation

enum ArisTeachReplay {
    /// How a step ended the run.
    enum End: Equatable, Sendable {
        /// The owner said no on its card.
        case declined
        /// Its card got no answer in time: nothing ran, and it is no no of his (ninth VM run, item 3).
        case unanswered
        /// The trust decision refused it; why, for the owner.
        case refused(String)
        /// It ran and failed (the app changed, a control isn't there): what the capability said.
        case failed(String)
        /// A newer turn took over.
        case stale
        /// It couldn't be made into a call (a value missing).
        case unmade
    }

    enum Outcome: Equatable, Sendable {
        case done(steps: Int)
        /// It ran to the end with the owner's yes to go on past the steps at `skipped` (from 0), which failed.
        case partly(done: Int, skipped: [Int])
        /// It stopped at step `at` (from 0), after `done` steps ran.
        case stopped(at: Int, end: End, done: Int)
    }

    /// Content to hand to the provenance tracker before the run: what the steps carry that was read from an app.
    struct Seen: Equatable, Sendable {
        let source: ArisContentSource
        let text: String
    }

    struct Plan: Equatable, Sendable {
        /// One call per step, in order; nil for a step that can't be made.
        let calls: [ArisMindToolCall?]
        /// The procedure's steps, in the calls' order (what a failed step's later steps may stand on).
        var steps: [ArisTeachStep] = []
        /// The owner's instruction for this run, made only of what he said or wrote: the procedure's name, their words for
        /// this run and the values he gave. Never a label, a title or a value read from an app.
        let instruction: String
        /// What the steps carry that was read from an app, as that app's content (the tracker keeps it as data).
        let seen: [Seen]
        /// The replay's own calls for the tracker's replay-scoped channel (ArisApprovedStep).
        let approved: [ArisApprovedStep]
        /// The values used, by parameter key, and which of them the owner gave in this run's words.
        let values: [String: String]
        let ownerGave: Set<String>
        let run: String
    }

    /// Where a step's own taught words are said to come from: the app, marked as a taught step's words (so they are
    /// never mistaken for what the app shows now).
    static func source(_ seen: ArisContentSource) -> ArisContentSource {
        ArisContentSource(kind: seen.kind, source: seen.source + " · 배운 단계")
    }

    /// The plan for one run. `given`: values from the owner's words, by parameter key (the rest are the examples);
    /// `words`: what he said to run it.
    static func plan(_ procedure: ArisTeachProcedure, given: [String: String], words: String = "", run: String) -> Plan {
        let values = procedure.examples.merging(given) { $1 }
        let ownerGave = Set(given.keys)
        var calls: [ArisMindToolCall?] = []
        var approved: [ArisApprovedStep] = []
        for (index, step) in procedure.steps.enumerated() {
            guard let arguments = step.arguments(values: values) else {
                calls.append(nil)
                continue
            }
            let call = ArisMindToolCall(id: "teach-\(run)-\(index + 1)", name: step.toolName, arguments: ArisApps.JSON.object(arguments).text)
            calls.append(call)
            // A recorded value (not their words for this run) is the app's content, judged as such: no approval. A step that
            // replaces what a field holds is never approved ahead either: it is destructive and asks (third VM run, D2).
            guard !step.carriesRecordedValue(ownerGave: ownerGave), !step.replaces else { continue }
            approved.append(ArisApprovedStep(run: run, index: index + 1, call: call.id, capability: step.capability,
                                             arguments: ArisKeyArguments.extract(call.object ?? [:], capability: step.capability)))
        }
        var grouped: [ArisContentSource: [String]] = [:]
        var order: [ArisContentSource] = []
        for step in procedure.steps {
            guard let seen = step.seen else { continue }
            let words = step.seenText(values: values, ownerGave: ownerGave)
            guard !words.isEmpty else { continue }
            let marked = source(seen)
            if grouped[marked] == nil { order.append(marked) }
            grouped[marked, default: []] += words
        }
        let seen = order.map { Seen(source: $0, text: grouped[$0, default: []].joined(separator: "\n")) }
        return Plan(calls: calls, steps: procedure.steps, instruction: instruction(procedure, words: words, given: given), seen: seen, approved: approved,
                    values: values, ownerGave: ownerGave, run: run)
    }

    /// The parameters a run types that the owner's words for it gave no value for (second VM run: "메모 쓰기 해 줘"
    /// typed the old example without asking). They are asked on a card before anything runs, each with its recorded
    /// example as the value to keep or change.
    static func missing(_ procedure: ArisTeachProcedure, given: [String: String]) -> [ArisTeachParameter] {
        let used = Set(procedure.steps.compactMap(\.parameter))
        return procedure.parameters.filter { used.contains($0.key) && given[$0.key] == nil }
    }

    /// The values that are his after their yes on that card, by parameter key (a field is keyed by its parameter's label):
    /// what he wrote or said there. The fields come up empty (ArisTeachCopy.emptyFields), so anything in one is his, last
    /// time's value too when he wrote it in (eleventh VM run, item 5); a field left empty gives nothing, and last time's
    /// value is never taken as his without that (T2).
    static func answered(_ missing: [ArisTeachParameter], edits: [String: String]) -> [String: String] {
        var values: [String: String] = [:]
        for parameter in missing {
            // Keyed by the label the card showed: Aris's own word in the UI's language ("본문", "text").
            let shown = edits[parameter.label] ?? edits[ArisTeachCopy.label(parameter.label, english: true)]
            // The field shows a line break as ↵ (ArisTeachCopy.fieldValue): read back as the line break it stands for.
            guard let typed = shown?.trimmingCharacters(in: .whitespacesAndNewlines), !typed.isEmpty else { continue }
            values[parameter.key] = ArisTeachCopy.fromField(typed)
        }
        return values
    }

    /// The owner's instruction for a run: the procedure's name (his), their words for it, the values he gave (his).
    static func instruction(_ procedure: ArisTeachProcedure, words: String, given: [String: String]) -> String {
        var lines = ["내가 가르친 ‘\(procedure.name)’ 해 줘 (do what I taught you as \(procedure.name))"]
        let said = words.trimmingCharacters(in: .whitespacesAndNewlines)
        if !said.isEmpty { lines.append(said) }
        // The values only: a parameter's label is the field's own words, read from the app.
        for parameter in procedure.parameters {
            if let value = given[parameter.key] { lines.append(value) }
        }
        return lines.joined(separator: "\n")
    }

    /// Each call's card words, by call id: the step it was made from, with this run's values, in the UI's language.
    static func described(_ procedure: ArisTeachProcedure, plan: Plan, english: Bool) -> [String: ArisAskDescription] {
        var out: [String: ArisAskDescription] = [:]
        for (index, call) in plan.calls.enumerated() {
            guard let call, index < procedure.steps.count else { continue }
            let step = procedure.steps[index]
            out[call.id] = ArisTeachCopy.stepCard(procedure, at: index, values: plan.values, ownerGave: plan.ownerGave,
                                                  arguments: ArisKeyArguments.extract(call.object ?? [:], capability: step.capability), english: english)
        }
        return out
    }

    /// Whether the steps after `index` can go on without it: a step that only sets a value (text into a field, an
    /// option of a pop-up) is stood on by nothing; any other (opening the app, a menu command, a press, keys may open
    /// the window or the sheet the next steps work in) only when no later step is in the same app.
    static func canGoOnWithout(_ index: Int, steps: [ArisTeachStep]) -> Bool {
        guard steps.indices.contains(index), index + 1 < steps.count else { return false }
        let failed = steps[index]
        if failed.action == .type || failed.action == .select { return true }
        return !steps[(index + 1)...].contains { $0.bundle == failed.bundle }
    }

    /// Runs the plan's calls one at a time through the step's ports; stops at the first that doesn't run and succeed,
    /// except a step that ran and failed with steps left after it: `goOn(index, why)` asks the owner whether to go on
    /// with them (blocks until he answers; no answer is a no). On their yes the rest run on `afresh()`'s ports (a new
    /// intent: nothing an earlier card's yes allowed is allowed again without its own card), each through the same
    /// decision as any step.
    /// `progress`: before each step, its index and the count.
    /// `approval`: their yes on the run's one card (ArisTeachRunPass): the steps it covers run with no card of their own
    /// while the pass stands; it is void once a step fails, the run stops, or a call isn't the plan's.
    static func run(_ plan: Plan, ports: ArisMindPorts, progress: (Int, Int) -> Void = { _, _ in },
                    goOn: (Int, String) -> Bool = { _, _ in false }, afresh: (() -> ArisMindPorts)? = nil, approval: Approval? = nil) -> Outcome {
        let outcome = steps(plan, ports: passing(ports, plan: plan, approval: approval), progress: progress, goOn: goOn, afresh: afresh, pass: approval?.box)
        // However it ended, nothing is left of the pass (a newer turn took the run over, or it is simply over).
        if case .stopped(_, .stale, _) = outcome { approval?.box.void(.newTurn) }
        approval?.box.void(.stopped)
        return outcome
    }

    private static func steps(_ plan: Plan, ports: ArisMindPorts, progress: (Int, Int) -> Void, goOn: (Int, String) -> Bool,
                              afresh: (() -> ArisMindPorts)?, pass: ArisTeachPassBox?) -> Outcome {
        let ends = ArisTeachDispositions()
        func watching(_ ports: ArisMindPorts) -> ArisMindPorts {
            var watched = ports
            watched.finish = { item, result, disposition in
                ends.set(item.call.id, disposition, asked: item.verdict == .waits)
                ports.finish(item, result, disposition)
            }
            return watched
        }
        var watched = watching(ports)
        var skipped: [Int] = []
        for (index, call) in plan.calls.enumerated() {
            let done = index - skipped.count
            guard let call else { return .stopped(at: index, end: .unmade, done: done) }
            progress(index, plan.calls.count)
            let step = ArisMindStep.run([call], ports: watched, parallel: false)
            guard let result = step.results.first?.result else { return .stopped(at: index, end: .failed(""), done: done) }
            switch ends.get(call.id) {
            case .refused?: return .stopped(at: index, end: .refused(result.text), done: done)
            case .declined?: return .stopped(at: index, end: watched.unanswered(call.id) ? .unanswered : .declined, done: done)
            case .stale?: return .stopped(at: index, end: .stale, done: done)
            case nil where step.stale: return .stopped(at: index, end: .stale, done: done)
            case .ran?, nil:
                if result.isError {
                    let why = failure(result.text)
                    // A step failed: the run's pass is void, and every step left asks on its own card.
                    pass?.void(.failed(at: index))
                    // Steps are left, the run is still his, and he says go on.
                    guard !step.stale, watched.isCurrent(), index + 1 < plan.calls.count, goOn(index, why) else {
                        return .stopped(at: index, end: .failed(why), done: done)
                    }
                    skipped.append(index)
                    if let afresh { watched = watching(afresh()) }
                    continue
                }
                if step.stale { return .stopped(at: index + 1, end: .stale, done: done + 1) }
            }
        }
        return skipped.isEmpty ? .done(steps: plan.calls.count) : .partly(done: plan.calls.count - skipped.count, skipped: skipped)
    }

    /// A failed call's words for the owner: the app layer's "did" line when the result is its JSON, else the text.
    static func failure(_ text: String) -> String {
        if let data = text.data(using: .utf8), let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            if let question = object["question"] as? String, !question.isEmpty { return question }
            if let did = object["did"] as? String, !did.isEmpty { return did }
        }
        return text
    }
}

/// How each call of a run ended, as the step's ports report it.
final class ArisTeachDispositions: @unchecked Sendable {
    private let lock = NSLock()
    private var ends: [String: ArisMindPorts.Disposition] = [:]
    /// The calls that waited for the owner's card (a permanent or sending step, or one content suggested).
    private var waited: Set<String> = []

    func set(_ id: String, _ end: ArisMindPorts.Disposition, asked: Bool = false) {
        lock.withLock {
            ends[id] = end
            if asked { waited.insert(id) }
        }
    }
    func get(_ id: String) -> ArisMindPorts.Disposition? { lock.withLock { ends[id] } }
    func asked(_ id: String) -> Bool { lock.withLock { waited.contains(id) } }
}
