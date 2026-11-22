//
//  ArisMindRoute.swift
//  aris-agent
//
//  The MCP face's calls through the one decision (ARCHITECTURE Part 2: Claude Code in model-only mode is a provider,
//  and Aris is its only tool surface). Claude Code runs its own loop, so its calls come to the face's server
//  (ArisHandsServer, in Claude's process tree); with `arisCore2` on it asks the helper, which holds the owner's words,
//  the cards and the record, before each call, and tells it after:
//
//    POST /mind-call {"op": "decide", "turn", "id", "name", "arguments", "use"?}   ("use": Claude Code's tool-use id: noteRun)
//        -> {"verdict": "run" | "runWithUndo" | "refuse", "text"?, "pass"?}   (after the owner's card when one was due;
//           "pass": their yes on that card, which the call's own route takes in place of its card: ArisMindPasses)
//    POST /mind-call {"op": "done", "turn", "id", "text", "isError", "content"?: {"kind", "source"}, "undo"?: recipe,
//                     "logged"?: [activity log entry id]}
//        -> {}   (the call's line in the record; what it read to the provenance tracker)
//
//    POST /mind-call {"op": "decide_batch", "turn", "calls": [{"id", "name", "arguments"}]}  -> {"verdicts": [{"id", "verdict"…}]}
//    POST /mind-call {"op": "ask", "turn", "ids"}  -> {"run": [{"id", "session", "owner", "pass"?}]}   (after the cards)
//        the Mind's own loop for API brains (`aris-agent mind-brain`, ArisMindBrain): a round's calls decided together,
//        one card per intent for those that wait, the calls themselves run in parallel in the child.
//
//  Checked as /action-tool is: the turn's credential, the open Claude's own turn under way, the caller inside that
//  brain's process tree. The conversation is the runner's (its tracker spans turns); the intent is the turn. A
//  background job's prompt may have come from a model or outside content, so it is never taken as the owner's words.
//  ArisMindRemote is the server's side: an ArisTrustDeciding that asks here. The route's checks of the caller are in
//  ArisMindRoute+Live (they need the runners and the connection).
//

import Foundation

enum ArisMindRoute {
    static let path = "/mind-call"

    /// The runner's conversation, as the trust gate keys its tracker: a name of its own for each runner, never used
    /// again (thirteenth VM run, item 3: the name was the runner's address, so a later job's runner at a freed address
    /// took an earlier job's tracker, and its brief was judged as the earlier job's content). A runner keeps its name
    /// while it lives (the conversation's tracker spans turns); a background job's runner is a new one each time.
    static func session(_ runner: AnyObject) -> String {
        sessionLock.withLock {
            if let name = sessionNames.object(forKey: runner) { return name as String }
            let name = "claude-" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(16))
            sessionNames.setObject(name as NSString, forKey: runner)
            return name
        }
    }

    private static let sessionLock = NSLock()
    /// Weak keys: a runner that is gone takes its name with it, and a new runner at its address gets a new one.
    nonisolated(unsafe) private static let sessionNames = NSMapTable<AnyObject, NSString>.weakToStrongObjects()

    /// One call decided, asked about when it must be, and the answer for the face's server.
    /// `refusesFirst`: the call's route's own refusal before any card (ArisMindJudge.decide).
    static func decide(judge: ArisMindJudge, session: String, task: String?, intent: String, id: String, name: String, arguments: [String: Any],
                       refusesFirst: ((ArisMindJudge.Read) -> String?)? = nil, card: @escaping ArisMindJudge.Card) -> [String: Any] {
        let text = (try? JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        let call = ArisMindToolCall(id: id, name: name, arguments: text)
        guard let decided = judge.decide(session: session, task: task, calls: [call], intent: intent, refusesFirst: refusesFirst).first else { return ["verdict": "refuse"] }
        switch decided.verdict {
        case .refuse(let reason):
            judge.finish(session: session, item: decided, result: ArisMindResult(text: reason, isError: true), disposition: .refused)
            return ["verdict": "refuse", "text": reason]
        case .run(let undo, _):
            // A desktop call the gate let run without a card: the pass that is the app's yes for it at the route (judgedRun).
            let pass = judge.pass(session: session, call: id).map { ["pass": $0] } ?? [:]
            return ["verdict": undo ? "runWithUndo" : "run"].merging(caller(judge, session: session, id: id)) { $1 }.merging(pass) { $1 }
        case .waits:
            guard judge.ask(session: session, task: task, intent: intent, waiting: [decided], card: card).contains(id) else {
                // A card nobody answered is told as that, never as his no (ninth VM run, item 3).
                let text = judge.unanswered(session: session, call: id) ? ArisMindStep.unansweredText : ArisMindStep.declinedText
                judge.finish(session: session, item: decided, result: ArisMindResult(text: text, isError: true), disposition: .declined)
                return ["verdict": "refuse", "text": text]
            }
            // The owner's yes on the gate's card: the pass the call's own route takes in place of its card.
            let pass = judge.pass(session: session, call: id).map { ["pass": $0] } ?? [:]
            return ["verdict": "run"].merging(caller(judge, session: session, id: id)) { $1 }.merging(pass) { $1 }
        }
    }

    /// A face call the gate let run (on its own, or on the owner's yes on its card: both answer "run" or "runWithUndo"),
    /// noted for its turn by the provider's own id (`use`), so the Claude driver's web-result check (I3) finds the
    /// trust gate's decision for exactly that call in place of the read judge's yes. A refusal, or no id, notes nothing.
    static func noteRun(_ answer: [String: Any], use: Any?, turn: String, name: String, arguments: [String: Any], into decisions: ArisFaceDecisions) {
        guard let use = use as? String, ["run", "runWithUndo"].contains(answer["verdict"] as? String) else { return }
        decisions.ran(turn: turn, id: use, function: name, arguments: arguments)
    }

    /// Who the call is for an undo: the conversation, and whether the owner's own words asked for it; and the effect
    /// it was decided as, which its run keeps to (decision 4).
    static func caller(_ judge: ArisMindJudge, session: String, id: String) -> [String: Any] {
        var fields: [String: Any] = ["session": session, "owner": judge.provenance(session: session, call: id) == .ownerSaid,
                                     "speaker": judge.speaker(session: session, call: id).rawValue]
        if let effect = judge.effect(session: session, call: id) { fields["effect"] = effect.rawValue }
        // A file call's path as it was decided, links followed: the run resolves it again and must land there.
        if let resolved = judge.resolved(session: session, call: id) { fields["resolved"] = resolved }
        // A call whose card showed what it erases (the model's own replace: tenth VM run, item 4): the mark of what the
        // card showed, which the process that runs it puts in the call, so app.type sets nothing when the field holds
        // something else by then (ArisApps.TypeOver).
        if let erased = judge.erasedMark(session: session, call: id) { fields["erased"] = erased }
        // An undo's plan as decided: the kind their words named, the entries its card named and their yes on it (item 1).
        let undo = judge.caller(session: session, task: nil, call: id)
        if let named = undo.named { fields["undoKind"] = named.rawValue }
        if let planned = undo.planned { fields["undoIDs"] = planned }
        if undo.approved { fields["approved"] = true }
        return fields
    }

    // MARK: - The Mind's own loop (`aris-agent mind-brain`, ArisMindBrain): one round's calls at a time

    /// The most calls one round may hand over.
    static let mostCalls = 16

    /// `{"op": "decide_batch", "calls": [{"id", "name", "arguments"}]}`: every call of the round decided at once. A call
    /// that runs now comes back with its caller; one the policy refused is recorded here; one that waits says so, and
    /// its card goes up with the round's other waiting calls on `ask`. `allow`: the aris-tools words of a call let run,
    /// for the one-shot passes aris-tools needs to send or write as Aris (the API brain's gate does the same on its
    /// allow: ArisAPIDriver.allowLine).
    /// `intent`: the turn (a desktop call let run without a card carries its judgedRun pass); `refusesFirst`: the
    /// call's route's own refusal before any card (ArisMindJudge.decide).
    static func decideBatch(judge: ArisMindJudge, session: String, task: String?, calls raw: [[String: Any]], intent: String? = nil,
                            refusesFirst: ((ArisMindJudge.Read) -> String?)? = nil, allow: ([String]) -> Void) -> [String: Any] {
        let calls = raw.prefix(mostCalls).compactMap { object -> ArisMindToolCall? in
            guard let id = object["id"] as? String, !id.isEmpty, id.count <= 100, let name = object["name"] as? String, name.count <= 100 else { return nil }
            let arguments = object["arguments"] as? String ?? "{}"
            return arguments.utf8.count <= 200_000 ? ArisMindToolCall(id: id, name: name, arguments: arguments) : nil
        }
        let decided = judge.decide(session: session, task: task, calls: calls, intent: intent, refusesFirst: refusesFirst)
        let verdicts: [[String: Any]] = decided.map { item in
            switch item.verdict {
            case .refuse(let reason):
                judge.finish(session: session, item: item, result: ArisMindResult(text: reason, isError: true), disposition: .refused)
                return ["id": item.call.id, "verdict": "refuse", "text": reason]
            case .run(let undo, let announce):
                if case .success(let read) = judge.read(item.call), let argv = read.argv { allow(argv) }
                var line: [String: Any] = ["id": item.call.id, "verdict": "run", "undo": undo, "announce": announce].merging(caller(judge, session: session, id: item.call.id)) { $1 }
                if let pass = judge.pass(session: session, call: item.call.id) { line["pass"] = pass }
                return line
            case .waits:
                return ["id": item.call.id, "verdict": "waits"]
            }
        }
        return ["verdicts": verdicts]
    }

    /// `{"op": "ask", "ids"}`: the round's calls that wait, on one card per intent; blocks until the owner answered.
    /// The ids that run, with their callers and, for a yes on the gate's card, the pass their route takes in place of
    /// its own card. A call he said no to (or didn't answer) is recorded here and runs nothing.
    static func ask(judge: ArisMindJudge, session: String, task: String?, intent: String, ids: [String], allow: ([String]) -> Void,
                    card: @escaping ArisMindJudge.Card) -> [String: Any] {
        let waiting = ids.prefix(mostCalls).map { ArisMindDecided(call: ArisMindToolCall(id: $0, name: "", arguments: ""), verdict: .waits) }
        let allowed = judge.ask(session: session, task: task, intent: intent, waiting: Array(waiting), card: card)
        var run: [[String: Any]] = []
        // The calls whose card nobody answered: the brain tells the model so, never that he said no (ninth VM run, item 3).
        var silent: [String] = []
        for item in waiting {
            guard allowed.contains(item.call.id) else {
                if judge.unanswered(session: session, call: item.call.id) { silent.append(item.call.id) }
                judge.finish(session: session, item: item, result: ArisMindResult(text: ArisMindStep.declinedText, isError: true), disposition: .declined)
                continue
            }
            if let argv = judge.argv(session: session, call: item.call.id) { allow(argv) }
            var line: [String: Any] = ["id": item.call.id].merging(caller(judge, session: session, id: item.call.id)) { $1 }
            if let pass = judge.pass(session: session, call: item.call.id) { line["pass"] = pass }
            run.append(line)
        }
        return silent.isEmpty ? ["run": run] : ["run": run, "unanswered": silent]
    }

    /// The call ran: its record line and what it read.
    static func done(judge: ArisMindJudge, session: String, object: [String: Any], id: String) {
        if object["disposition"] as? String == "stale" {
            judge.finish(session: session, item: ArisMindDecided(call: ArisMindToolCall(id: id, name: "", arguments: ""), verdict: .waits),
                         result: ArisMindResult(text: ArisMindStep.staleText, isError: true), disposition: .stale)
            return
        }
        let content = (object["content"] as? [String: Any]).flatMap { content -> ArisContentSource? in
            guard let kind = content["kind"] as? String, let source = content["source"] as? String else { return nil }
            return ArisContentSource(kind: String(kind.prefix(20)), source: String(source.prefix(400)))
        }
        let undo = (object["undo"] as? [String: Any]).flatMap { value -> ArisUndoRecipe? in
            guard let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
            return try? JSONDecoder().decode(ArisUndoRecipe.self, from: data)
        }
        var result = ArisMindResult(text: String((object["text"] as? String ?? "").prefix(ArisProvenanceTracker.keptText)), isError: object["isError"] as? Bool ?? true,
                                    content: content, undo: undo)
        // The activity log's entries the call's aris-tools run wrote (ArisMindExecutor): ids only, at most twenty.
        result.logged = ((object["logged"] as? [Any]) ?? []).prefix(20).compactMap { ($0 as? String).flatMap(UUID.init(uuidString:))?.uuidString.lowercased() }
        // Said by Aris's own process that ran the call (the Mind's child, the face's server), never by a model.
        result.framed = object["framed"] as? Bool == true
        judge.finish(session: session, item: ArisMindDecided(call: ArisMindToolCall(id: id, name: "", arguments: ""), verdict: .run(undo: undo != nil, announce: false)),
                     result: result, disposition: .ran)
    }
}

/// The face's server's trust policy with `arisCore2` on: the helper's gate for this call's turn, over POST /mind-call
/// with the turn's credential (the same as aris-tools' calls to the agent's routes). The helper puts a card in front of
/// the owner when one is due and answers once he has: run or refuse. Anything that keeps it from answering refuses.
final class ArisMindRemote: ArisTrustDeciding, @unchecked Sendable {
    let environment: [String: String]
    /// The POST: the body, how long to wait; the reply's object (nil: no answer).
    var post: (_ body: [String: Any], _ wait: TimeInterval) -> [String: Any]?

    static let unreachable = "Not run: Aris's helper didn't answer for this call."
    /// The decide call may wait for the owner's card.
    static let decideWait: TimeInterval = ArisCardEdit.questionTimeout + 20

    init(environment: [String: String], post: ((_ body: [String: Any], _ wait: TimeInterval) -> [String: Any]?)? = nil) {
        self.environment = environment
        self.post = post ?? { body, wait in ArisMindRemote.livePost(body, wait: wait) }
    }

    private let callers = ArisLocked<[String: ArisUndoCaller]>([:])
    private let passes = ArisLocked<[String: String]>([:])
    private let effects = ArisLocked<[String: ArisEffectClass]>([:])
    private let paths = ArisLocked<[String: String]>([:])
    private let erased = ArisLocked<[String: String]>([:])

    /// A typing call's mark of what its decision read in the field (ArisApps.TypeOver), as the helper said it (taken
    /// once). The face's server puts it in the call, as the Mind's own loop does: before the eleventh VM run's fix this
    /// path dropped it, so a replace through the face was bound to nothing.
    func erasedMark(_ id: String) -> String? { erased.withLock { $0.removeValue(forKey: id) } }

    /// A file call's path as the helper decided it, links followed (taken once). Nil: it didn't say, and the run then
    /// takes the strictest reading (no link on the way at all).
    func resolved(_ id: String) -> String? { paths.withLock { $0.removeValue(forKey: id) } }

    /// The effect the helper decided a call it let run as (taken once). Nil: it didn't say, and the run takes the
    /// strictest reading (an overwrite then needs its verified copy).
    func judged(_ id: String) -> ArisEffectClass? { effects.withLock { $0.removeValue(forKey: id) } }

    /// The pass the helper handed back for a call the owner said yes to on its card (taken once).
    func pass(_ id: String) -> String? { passes.withLock { $0.removeValue(forKey: id) } }

    /// The caller the helper named for a call it let run (an undo reaches what its provenance lets it).
    func caller(_ id: String) -> ArisUndoCaller {
        callers.withLock { $0.removeValue(forKey: id) } ?? ArisUndoCaller(session: nil, provenance: .ownStep)
    }

    private var credential: String? {
        environment[ArisMCPTurnCredential.environmentKey].flatMap { $0.hasPrefix("/") ? ArisHandsServer.credential($0) : nil }.flatMap { $0.isEmpty ? nil : $0 }
    }

    func decide(_ call: ArisTrustCall) -> ArisTrustVerdict {
        // The never-list holds before anything is asked (ArisCapabilityGate checks it too).
        if call.effect == .never { return .refuse(ArisCapabilityGate.neverLine) }
        guard let turn = credential else { return .refuse(Self.unreachable) }
        var body: [String: Any] = ["op": "decide", "turn": turn, "id": call.id, "name": call.entry.name, "arguments": call.arguments]
        // The provider's own id for the call: the helper notes that it decided this very call (ArisFaceDecisions).
        if let use = call.useId { body["use"] = use }
        guard let reply = post(body, Self.decideWait),
              let verdict = reply["verdict"] as? String else { return .refuse(Self.unreachable) }
        if let session = reply["session"] as? String, verdict != "refuse" {
            let caller = ArisUndoCaller(session: session, provenance: reply["owner"] as? Bool == true ? .ownerSaid : .ownStep,
                                        approved: reply["approved"] as? Bool == true, speaker: ArisTurnSpeaker.named(reply["speaker"] as? String),
                                        named: (reply["undoKind"] as? String).flatMap(ArisUndoKind.init(rawValue:)),
                                        planned: (reply["undoIDs"] as? [String]).map { Array($0.prefix(ArisUndoScope.mostAtOnce)) })
            callers.withLock { $0[call.id] = caller }
        }
        if verdict != "refuse", let pass = reply["pass"] as? String, ArisMindPasses.wellFormed(pass) { passes.withLock { $0[call.id] = pass } }
        if verdict != "refuse", let effect = (reply["effect"] as? String).flatMap(ArisEffectClass.init(rawValue:)) { effects.withLock { $0[call.id] = effect } }
        if verdict != "refuse", let path = reply["resolved"] as? String, path.hasPrefix("/"), path.count <= 4_096 { paths.withLock { $0[call.id] = path } }
        if verdict != "refuse", let mark = reply["erased"] as? String, mark.count <= 200 { erased.withLock { $0[call.id] = mark } }
        switch verdict {
        case "run": return .run
        case "runWithUndo": return .runWithUndo
        default: return .refuse(reply["text"] as? String ?? Self.unreachable)
        }
    }

    /// After the call ran: its result for the record and the provenance tracker.
    func report(_ call: ArisTrustCall, result: ArisMindResult) {
        guard let turn = credential else { return }
        var body: [String: Any] = ["op": "done", "turn": turn, "id": call.id, "text": String(result.text.prefix(20_000)), "isError": result.isError]
        if let content = result.content { body["content"] = ["kind": content.kind, "source": content.source] }
        if let undo = result.undo, let data = try? JSONEncoder().encode(undo), let object = try? JSONSerialization.jsonObject(with: data) { body["undo"] = object }
        if !result.logged.isEmpty { body["logged"] = result.logged }
        if result.framed { body["framed"] = true }
        _ = post(body, 10)
    }

    static func livePost(_ body: [String: Any], wait: TimeInterval) -> [String: Any]? {
        guard let token = ClaudeHookToken.load(), let url = URL(string: "http://127.0.0.1:23351" + ArisMindRoute.path),
              let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: wait)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
        request.httpBody = data
        let configuration = ArisNoStore.configuration()
        configuration.timeoutIntervalForRequest = wait
        configuration.timeoutIntervalForResource = wait
        let done = DispatchSemaphore(value: 0)
        let reply = ArisLocked<[String: Any]?>(nil)
        URLSession(configuration: configuration).dataTask(with: request) { data, _, _ in
            if let data, let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] { reply.withLock { $0 = object } }
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + wait + 2)
        return reply.withLock { $0 }
    }
}
