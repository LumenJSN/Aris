//
//  ArisRoutineRoutes.swift
//  aris-agent
//
//  POST /routine-tool {"turn", "words": […]}  ->  {"status", "output"}: `aris-tools routine …` from inside a brain's
//  turn (ArisRoutineTool). The caller must be that turn's own brain process, as for /skill-tool. Listing and showing
//  answer at once. Adding or removing a routine never happens here without the user: the agent puts its own card on the
//  turn's stream (the routine read back step by step) and saves or deletes only on their yes, the same on every brain,
//  whatever the risk gate made of the command. Steps that aren't his own words of this clean turn are kept as
//  AI-worded (ArisRoutine.own), so their runs are treated as model-written text, and reading one back into a turn marks
//  that turn as outside text. A card can outlast one shell command:
//  the call then hands back an id and `routine wait <id>` collects the result (ArisSlowCalls).
//

import Foundation
import Network

enum ArisRoutineRoutes {
    static func tool(_ object: [String: Any], on connection: NWConnection, agentPort: UInt16, reply: @escaping (String, Data) -> Void) {
        let refuse = { (why: String) in
            ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["answer": "refused (\(why))", "question": "routine-tool"]), key: "local")
            reply("403 Forbidden", ArisMCPRoutes.json(["status": 1, "output": "aris-tools routine works only inside an Aris turn."]))
        }
        guard let credential = object["turn"] as? String, let runner = ArisAgentRunner.runner(forMCPTurn: credential) else { return refuse("no turn credential") }
        let remotePort = ArisTeammateDesk.remotePort(of: connection)
        DispatchQueue.global(qos: .userInitiated).async {
            let now = runner.messageSnapshot()
            guard now.active else { return refuse("no turn under way") }
            guard let pid = now.pid, let remotePort, ArisMCPCaller.isInside(root: pid, remotePort: remotePort, agentPort: agentPort) else {
                return refuse("not from the brain's own process")
            }
            let send = { (outcome: ArisMCPOutcome) in reply("200 OK", ArisMCPRoutes.json(["status": Int(outcome.status), "output": outcome.output])) }
            let words = (object["words"] as? [Any] ?? []).compactMap { $0 as? String }
            if words.first == "wait" {
                guard words.count == 2, ArisSlowCalls.isID(words[1]) else { return send(.failed("usage: routine wait <id>")) }
                return ArisSlowCalls.shared.wait(id: words[1], owner: credential, kind: "routine", reply: send)
            }
            guard let call = ArisRoutineTool.parse(words) else { return send(.failed(ArisRoutineTool.usage)) }
            // Anyone near the Mac may be speaking: his routines aren't read out or changed.
            guard !now.handsFree else { return send(.failed(ArisRoutineTool.handsFree)) }
            ArisSlowCalls.shared.run(owner: credential, kind: "routine", work: { done in
                answer(call, turn: Turn(runner: runner, credential: credential, request: now.request, clean: now.taint == .none && !runner.isBackgroundTask), done: done)
            }, reply: send)
        }
    }

    /// The turn a call came from: its runner (whose stream the card goes up on), the user's words, and whether it is clean.
    private struct Turn {
        let runner: ArisAgentRunner
        let credential: String
        let request: String
        let clean: Bool
    }

    private static func answer(_ call: ArisRoutineToolCall, turn: Turn, done: @escaping (ArisMCPOutcome) -> Void) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let stored = ArisRoutineStore.load(file: ArisRoutineStore.file(home: home))
        let korean = !ArisScheduleCard.isEnglish(turn.request)
        switch call {
        case .list:
            // A name or a step an AI worded is model-written text coming into the turn, like a schedule's prompt: the
            // turn is outside text from here on (his own words bring nothing in).
            if stored.contains(where: { !$0.own }) { turn.runner.mcpTakeOutsideText() }
            done(ArisMCPOutcome(status: 0, output: ArisRoutineTool.listing(stored)))
        case .show(let name):
            guard let routine = ArisRoutineNames.find(name, in: stored) else { return done(.failed(ArisRoutineTool.noSuch(name, routines: stored))) }
            if !routine.own { turn.runner.mcpTakeOutsideText() }
            done(ArisMCPOutcome(status: 0, output: ArisRoutineTool.showing(routine)))
        case .add(let raw, let given):
            let name = ArisRoutineNames.clean(raw), existing = ArisRoutineNames.find(raw, in: stored)
            if let problem = ArisRoutineRules.problem(name: name, steps: given, others: existing == nil ? stored.count : 0) {
                return done(.failed(ArisRoutineTool.refusal(problem)))
            }
            let steps = given.compactMap(ArisRoutineRules.step)
            let own = ArisRoutineTool.isOwn(steps: steps, request: turn.request, clean: turn.clean)
            let card = ArisRoutineCopy.saveCard(name: existing?.name ?? name, steps: steps, replacing: existing, written: !own, korean: korean)
            ask(card, turn: turn, done: done) {
                let saved = try ArisRoutineDesk.save(name: existing?.name ?? name, steps: steps, own: own, replacing: existing, home: home)
                return "saved: the \(saved.name) routine (\(saved.steps.count) steps). The user runs it by saying \"\(saved.name) 루틴 해 줘\"."
            }
        case .remove(let name):
            guard let routine = ArisRoutineNames.find(name, in: stored) else { return done(.failed(ArisRoutineTool.noSuch(name, routines: stored))) }
            let card = ArisRoutineCopy.deleteCard(routine, schedules: ArisRoutineDesk.schedules(running: routine, home: home, korean: korean), korean: korean)
            ask(card, turn: turn, done: done) { "removed: the \(try ArisRoutineDesk.delete(routine, home: home).name) routine" }
        }
    }

    /// The user's card on the calling turn's stream; `yes` runs only after their yes there.
    private static func ask(_ card: ArisRoutineCard, turn: Turn, done: @escaping (ArisMCPOutcome) -> Void, yes: @escaping () throws -> String) {
        turn.runner.mcpAsk(ArisMCPCard(title: card.title, detail: card.detail, full: nil, fields: []), credential: turn.credential) { answer in
            switch answer {
            case .yes:
                do { done(ArisMCPOutcome(status: 0, output: try yes())) } catch {
                    done(.failed("couldn't save: \(error.localizedDescription). Nothing changed."))
                }
            case .no: done(.failed(ArisRoutineTool.declined))
            case .unanswered: done(.failed(ArisRoutineTool.unanswered))
            }
        }
    }
}
