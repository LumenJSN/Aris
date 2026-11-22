//
//  ArisMindRoute+Live.swift
//  aris-agent
//
//  POST /mind-call's door (ArisMindRoute): the checks of the caller, as /action-tool's (the turn's credential, the open
//  Claude's own turn under way, the caller inside that brain's process tree), then the decision or the record line. A
//  card goes up on the turn's own stream (the runner's mcpAsk), so its answer comes back on the card's own path.
//

import Foundation
import Network

extension ArisMindRoute {
    static func call(_ object: [String: Any], on connection: NWConnection, agentPort: UInt16, reply: @escaping (String, Data) -> Void) {
        let refuse = { (why: String) in
            ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["answer": "refused (\(why))", "question": "mind-call"]), key: "mind")
            reply("403 Forbidden", ArisMCPRoutes.json(["verdict": "refuse", "text": "That works only inside an Aris turn."]))
        }
        guard ArisCore2.isOn() else { return refuse("arisCore2 is off") }
        guard let credential = object["turn"] as? String, let runner = ArisAgentRunner.runner(forMCPTurn: credential) else {
            return refuse("no turn credential")
        }
        // One call's id (decide, done); a round's calls carry their own (decide_batch, ask).
        let op = object["op"] as? String
        let id = object["id"] as? String ?? ""
        guard op == "decide_batch" || op == "ask" || (!id.isEmpty && id.count <= 100) else {
            return reply("400 Bad Request", ArisMCPRoutes.json(["verdict": "refuse"]))
        }
        let remotePort = ArisTeammateDesk.remotePort(of: connection)
        DispatchQueue.global(qos: .userInitiated).async {
            // The open Claude's face (its MCP server, inside Claude's tree), or the Mind's own loop for an API brain
            // (`aris-agent mind-brain`, the runner's own child, which asks here itself).
            let mind = runner.isMindBrain
            guard runner.brain == .claude || mind else { return refuse("\(runner.brain.title) isn't the face's brain") }
            let now = runner.messageSnapshot()
            guard now.active, now.openClaude || mind else { return refuse("no open Claude turn under way") }
            guard let pid = now.pid, let remotePort,
                  ArisMCPCaller.isInside(root: pid, remotePort: remotePort, agentPort: agentPort)
                    || (mind && ArisPeer.owns(pid: pid, localPort: remotePort, remotePort: agentPort)) else {
                return refuse("not from the brain's own process")
            }
            let session = Self.session(runner)
            let task = runner.isBackgroundTask ? session : nil
            let judge = ArisMindJudge.shared
            let card: ArisMindJudge.Card = { card, answer in
                var shown = ArisMCPCard(title: card.title, detail: card.detail, full: card.full, fields: [], countdown: card.countdown, spoken: card.spoken)
                // The gate's action countdown stays an action's card on its way to the app (thirteenth VM run, item 4).
                shown.action = card.action
                runner.mcpAsk(shown, credential: credential) { reply in
                    switch reply {
                    case .yes: answer(true)
                    case .no: answer(false)
                    case .unanswered: answer(nil)
                    }
                }
            }
            // The API brain's child sends and writes as Aris: aris-tools needs the one-shot pass for exactly what the
            // gate let run (the API brain's own gate mints the same on its allow). The face's calls go to the routes.
            let allow: ([String]) -> Void = { argv in
                guard mind else { return }
                ArisMessagePass.mint(argv: argv)
                ArisActionGrants.shared.mint(argv: argv)
            }
            // The desktop engine's own refusal before any card (its replace guard), on this turn's ledger and words:
            // the gate refuses such a call with it instead of carding it first (VM run 2, D4).
            let refusesFirst: (ArisMindJudge.Read) -> String? = { read in
                // A click names an element this turn's reads showed, or it is refused before any card (ArisMindClickReads).
                if let unread = ArisMindClickReads.shared.refusal(session: session, intent: credential, capability: read.entry.id, arguments: read.arguments) {
                    return unread
                }
                guard let argv = read.argv, argv.first == "desktop" else { return nil }
                let snapshot = runner.mcpSnapshot()
                let turn = ArisRunnerMCPTurn(runner: runner, handsFree: snapshot.handsFree, screen: snapshot.screen, credential: credential)
                return ArisDesktopEngine.shared.refusesBeforeCard(Array(argv.dropFirst()), text: read.stdin, turn: turn)
            }
            switch op {
            case "decide_batch":
                guard let calls = object["calls"] as? [[String: Any]] else { return reply("400 Bad Request", ArisMCPRoutes.json(["verdicts": []])) }
                if task == nil { judge.turn(session: session, intent: credential, words: now.request, speaker: now.speaker) } else {
                    // A job's turn: its own intent (his no ends its acting) and its request for the payment boundary only.
                    judge.jobTurn(session: session, intent: credential, request: now.request)
                }
                reply("200 OK", ArisMCPRoutes.json(decideBatch(judge: judge, session: session, task: task, calls: calls, intent: credential,
                                                               refusesFirst: refusesFirst, allow: allow)))
            case "ask":
                guard let ids = object["ids"] as? [String] else { return reply("400 Bad Request", ArisMCPRoutes.json(["run": []])) }
                reply("200 OK", ArisMCPRoutes.json(ask(judge: judge, session: session, task: task, intent: credential, ids: ids, allow: allow, card: card)))
            case "decide":
                guard let name = object["name"] as? String, let arguments = object["arguments"] as? [String: Any] else {
                    return reply("400 Bad Request", ArisMCPRoutes.json(["verdict": "refuse"]))
                }
                if task == nil { judge.turn(session: session, intent: credential, words: now.request, speaker: now.speaker) } else {
                    // A job's turn: its own intent (his no ends its acting) and its request for the payment boundary only.
                    judge.jobTurn(session: session, intent: credential, request: now.request)
                }
                let answer = decide(judge: judge, session: session, task: task, intent: credential, id: id, name: name, arguments: arguments,
                                    refusesFirst: refusesFirst, card: card)
                // Before the reply, so before the call runs and its result reaches the driver's web-result check.
                if !mind { noteRun(answer, use: object["use"], turn: credential, name: name, arguments: arguments, into: runner.faceDecisions) }
                reply("200 OK", ArisMCPRoutes.json(answer))
            case "taught":
                // A saved-steps call the gate let run (ArisMindTaught): its cards on this turn's stream, its account back.
                // Only the mind-brain's call, and only one the gate decided for this very turn, once: anything else is refused.
                guard mind, let decided = judge.takeDecided(session: session, call: id, intent: credential, capability: ArisTaughtOffer.capability) else {
                    return refuse("no decided saved-steps call")
                }
                reply("200 OK", ArisMCPRoutes.json(ArisMindTaught.call(decided, runner: runner, credential: credential, session: session)))
            case "done":
                if object["content"] != nil { runner.mcpTakeOutsideText() }
                // What an app.read showed is what this turn's clicks may name (before `done` forgets the call).
                if let capability = judge.capability(session: session, call: id) {
                    ArisMindClickReads.shared.note(session: session, intent: credential, capability: capability, result: object["text"] as? String ?? "",
                                                   isError: object["isError"] as? Bool ?? true)
                }
                done(judge: judge, session: session, object: object, id: id)
                reply("200 OK", Data("{}".utf8))
            default:
                reply("400 Bad Request", ArisMCPRoutes.json(["verdict": "refuse"]))
            }
        }
    }

}
