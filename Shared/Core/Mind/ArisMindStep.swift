//
//  ArisMindStep.swift
//  Shared/Core (aris-agent, tests)
//
//  One round of tool calls, the one way anything happens in Core 2 (ARCHITECTURE Part 2): every call is decided by the
//  one trust decision, the ones that wait for the owner go on one card per intent and wait for his answer, the ones
//  allowed run (in parallel), and every call ends as one line of the record with what the provenance tracker learns
//  from its result. The parts are ports (ArisMindPorts): the helper binds them to ArisTrustGate, the capability book
//  and the record; the tests to fakes. A turn that is no longer the current one runs nothing more: the check comes
//  before the decision, after the card wait and before each call, so a stale turn cannot write state. Pure.
//

import Foundation

struct ArisMindPorts: @unchecked Sendable {
    /// How a call ended, for `finish`.
    enum Disposition: Equatable, Sendable {
        /// It ran (its result may still be an error).
        case ran
        /// The policy refused it (the decision already recorded it).
        case refused
        /// It waited for the owner and he said no, or didn't answer (his answer is already recorded).
        case declined
        /// Its turn was no longer the current one: nothing ran.
        case stale
    }

    /// Decides every call of one round, in order.
    var decide: ([ArisMindToolCall]) -> [ArisMindDecided]
    /// The calls that wait for the owner: shown on one card per intent; blocks until he answers. The ids that may run.
    var ask: ([ArisMindDecided]) -> Set<String>
    /// Runs one allowed call.
    var execute: (ArisMindDecided) -> ArisMindResult
    /// After each call: its record line and what the provenance tracker learns from its result.
    var finish: (ArisMindDecided, ArisMindResult, Disposition) -> Void
    /// The turn is still the current one.
    var isCurrent: () -> Bool
    /// Whether a call that waited and didn't run got no answer at all (its card timed out), by its id; false when he
    /// said no. A call nobody answered is never said to be his no (ninth VM run, item 3).
    var unanswered: (String) -> Bool = { _ in false }
}

enum ArisMindStep {
    struct Outcome: Equatable, Sendable {
        /// Each call's result, in the calls' order (the model reads them under their ids).
        var results: [(id: String, name: String, result: ArisMindResult)]
        /// The tools' names of changes content suggested, done with their undo kept: said once when the turn ends
        /// (`saidLine`), in plain words.
        var said: [String]
        /// The turn went stale during the round.
        var stale: Bool
        /// A call waited for the owner and he said no (or didn't answer): the turn ends here (tenth VM run, item 6).
        var declined = false
        /// Every card that kept a call from running went unanswered: none was his no (ninth VM run, item 3).
        var unanswered = false

        static func == (a: Outcome, b: Outcome) -> Bool {
            a.said == b.said && a.stale == b.stale && a.declined == b.declined && a.unanswered == b.unanswered && a.results.map(\.id) == b.results.map(\.id) && a.results.map(\.result) == b.results.map(\.result)
        }
    }

    static let staleText = "Not run: a newer turn took over."
    static let declinedText = "Not run: the owner said no (or didn't answer). Don't try another way; say so in a few words."
    /// For a call whose card nobody answered: the model must not tell him he said no (ninth VM run, item 3).
    static let unansweredText = "Not run: the owner didn't answer its card in time. That is not a no. Don't try another way; say in a few words that there was no answer."
    static let duplicateText = "Not run: another call of this round has the same id."

    /// The calls of one round, decided, asked about, run and finished. `parallel`: allowed calls run at once.
    static func run(_ calls: [ArisMindToolCall], ports: ArisMindPorts, parallel: Bool = true) -> Outcome {
        guard ports.isCurrent() else {
            return Outcome(results: calls.map { ($0.id, $0.name, ArisMindResult(text: staleText, isError: true)) }, said: [], stale: true)
        }
        // A repeated id would make two results the model can't tell apart: only the first is decided.
        var seen = Set<String>()
        let unique = calls.filter { seen.insert($0.id).inserted }
        let decided = ports.decide(unique)
        let waiting = decided.filter { $0.verdict == .waits }
        let allowed = waiting.isEmpty ? [] : ports.ask(waiting)
        let current = ports.isCurrent()
        var results = [String: ArisMindResult]()
        var runnable: [ArisMindDecided] = []
        var declined = false, saidNo = false
        for item in decided {
            switch item.verdict {
            case .refuse(let reason):
                let result = ArisMindResult(text: reason, isError: true)
                results[item.call.id] = result
                ports.finish(item, result, .refused)
            case .waits where !allowed.contains(item.call.id):
                let silent = ports.unanswered(item.call.id)
                let result = ArisMindResult(text: silent ? unansweredText : declinedText, isError: true)
                results[item.call.id] = result
                declined = true
                if !silent { saidNo = true }
                ports.finish(item, result, .declined)
            case .run, .waits:
                if current { runnable.append(item) } else {
                    let result = ArisMindResult(text: staleText, isError: true)
                    results[item.call.id] = result
                    ports.finish(item, result, .stale)
                }
            }
        }
        let ran = execute(runnable, ports: ports, parallel: parallel)
        var said: [String] = []
        for (item, result, disposition) in ran {
            results[item.call.id] = result
            ports.finish(item, result, disposition)
            if disposition == .ran, !result.isError, case .run(_, true) = item.verdict { said.append(item.call.name) }
        }
        let ordered = calls.map { call -> (id: String, name: String, result: ArisMindResult) in
            guard unique.contains(where: { $0.id == call.id && $0.name == call.name && $0.arguments == call.arguments }) else {
                return (call.id, call.name, ArisMindResult(text: duplicateText, isError: true))
            }
            return (call.id, call.name, results[call.id] ?? ArisMindResult(text: staleText, isError: true))
        }
        return Outcome(results: ordered, said: said, stale: !current || !ports.isCurrent(), declined: declined, unanswered: declined && !saidNo)
    }

    /// Runs the allowed calls, each only while the turn is still current.
    private static func execute(_ items: [ArisMindDecided], ports: ArisMindPorts, parallel: Bool)
        -> [(ArisMindDecided, ArisMindResult, ArisMindPorts.Disposition)] {
        let box = ArisMindResults(count: items.count)
        let one = { (index: Int) in
            let item = items[index]
            guard ports.isCurrent() else { return box.set(index, (item, ArisMindResult(text: staleText, isError: true), .stale)) }
            box.set(index, (item, ports.execute(item), .ran))
        }
        if parallel && items.count > 1 {
            DispatchQueue.concurrentPerform(iterations: items.count, execute: one)
        } else {
            for index in items.indices { one(index) }
        }
        return box.all
    }

    /// The model's tool names that aren't a capability's id with "_" for its first ".".
    static let toolIDs = ["read_file": "file.read", "write_file": "file.write", "edit_file": "file.edit", "search_files": "file.search"]

    /// A tool as the owner reads it ("앱에 입력"), never its internal name (tenth VM run, item 8: the reply read
    /// "app_open … app_press … app_type" aloud); nil when no name is known for it.
    static func plainName(_ tool: String, english: Bool) -> String? {
        var ids = [toolIDs[tool], "aris." + tool].compactMap { $0 }
        if let underscore = tool.firstIndex(of: "_") { ids.insert(tool.replacingCharacters(in: underscore...underscore, with: "."), at: 0) }
        return ids.lazy.compactMap { ArisCapabilityNames.name($0) }.first.map { english ? $0.english : $0.korean }
    }

    /// What Aris says, once, after changes content suggested (each kept with its undo): what they were in plain words,
    /// each kind once, in the UI's language.
    static func saidLine(_ tools: [String], english: Bool = false) -> String {
        var names: [String] = []
        for tool in tools {
            let name = plainName(tool, english: english) ?? (english ? "a change" : "바꾼 것")
            if !names.contains(name) { names.append(name) }
        }
        let list = names.prefix(4).joined(separator: ", ") + (names.count > 4 ? (english ? " and more" : " 등") : "")
        return english ? "I did some things because of what I read: \(list). Say “undo” to take them back."
            : "읽은 내용에 따라 한 일이 있어요: \(list). 되돌리려면 ‘되돌려’라고 하세요."
    }

    /// The turn's last line when the owner didn't allow a card.
    /// `unanswered`: no card was answered no; they only went unanswered, and the line never says he refused.
    static func declinedLine(english: Bool, unanswered: Bool = false) -> String {
        if unanswered { return english ? "The card got no answer, so I left that undone." : "카드에 답이 없어서 그 일은 하지 않았어요." }
        return english ? "I left out what you didn't allow." : "허락하지 않으신 일은 하지 않았어요."
    }
}

/// The parallel calls' results, each in its place.
private final class ArisMindResults: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [(ArisMindDecided, ArisMindResult, ArisMindPorts.Disposition)?]

    init(count: Int) { values = Array(repeating: nil, count: count) }

    func set(_ index: Int, _ value: (ArisMindDecided, ArisMindResult, ArisMindPorts.Disposition)) { lock.withLock { values[index] = value } }

    var all: [(ArisMindDecided, ArisMindResult, ArisMindPorts.Disposition)] { lock.withLock { values.compactMap { $0 } } }
}
