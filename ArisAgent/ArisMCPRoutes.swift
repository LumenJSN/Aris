//
//  ArisMCPRoutes.swift
//  aris-agent
//
//  The two doors to the tool bus:
//
//    POST /mcp {"op": …, "pid", "started"}  (the Aris app itself only, ArisPeer; 403 else)
//        "list"                                         ->  {"servers": [ArisMCPHub.settingsList rows]}
//        "save" {"id"?, "name", "target", "secretName"?, "secret"?}  ->  {"server": row} or {"error"} (400)
//                (secret: a new token, "" removes it, absent keeps it; it goes to the Keychain, never back)
//        "composio" {"key"?: "ck_…"}                   ->  {} or {"error"} (a key saves it; none removes Composio)
//        "remove" {"id"} | "enable" {"id", "on"}       ->  {} or {"error"}
//        "test" {"id"}                                 ->  {"ok": bool, "message"}
//    POST /mcp-tool {"op": "list"|"call", "turn", "service"?, "tool"?, "arguments"? | "pairs"?}  (aris-tools, from
//        inside a brain's turn: ArisMCPCaller)  ->  {"status": n, "output": "…"} for aris-tools to print
//    POST /mcp-tool {"op": "judge", "turn", "tool", "arguments"}  (a Claude's hook asking the read judge, from the same
//        process tree)  ->  {"status": 0, "output": reason} to allow, {"status": 1, "output": reason} to block
//

import Foundation
import Network

/// The hub's view of one runner's turn.
final class ArisRunnerMCPTurn: ArisMCPTurn {
    let runner: ArisAgentRunner
    let handsFree: Bool
    let isTask: Bool
    let screen: Bool
    let relayed = false
    /// The turn this call belongs to (its credential): a card it raises, or a yes it gets, counts only while that turn is
    /// still the runner's (security review of BUG-33: a slow call's late card showed in the next turn).
    let credential: String

    init(runner: ArisAgentRunner, handsFree: Bool, screen: Bool, credential: String) {
        self.runner = runner
        self.handsFree = handsFree
        self.isTask = runner.isBackgroundTask
        self.screen = screen
        self.credential = credential
    }

    /// The brain's id ("claude", "api"): the ledger keeps a value in no language, shown by lookup (ArisBrain.title).
    /// It kept "API 브레인" on an English Mac (second upgrade run).
    var brainName: String { runner.brain.rawValue }
    var taint: ArisTaint { runner.mcpSnapshot().taint }
    func takeOutsideText() { runner.mcpTakeOutsideText() }
    func ask(_ card: ArisMCPCard, answer: @escaping (ArisMCPAnswer) -> Void) { runner.mcpAsk(card, credential: credential, answer: answer) }
    func judgeRead(_ call: ArisReadCall, done: @escaping (ArisReadVerdict) -> Void) { runner.judgeRead(call, showsBlock: false, done: done) }
    func quiet(_ status: String) { runner.quietStatus(status) }
    func audit(_ fields: [String: String]) {
        if !isTask { ArisWhyDesk.shared.gated(ArisAgentRunner.auditJSON(fields)) }
        ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(fields.merging(["question": "mcp"]) { $1 }), key: "mcp")
    }
}

/// The hub's view of Antigravity's relay (ArisAgyRelay): agy asked Aris to call a service for it, so Aris does, on the
/// /ask stream that turn is answering on; its cards go up there.
final class ArisRelayMCPTurn: ArisMCPTurn {
    let handsFree: Bool
    let isTask = false
    let screen: Bool
    let relayed = true
    private let lock = NSLock()
    private var current: ArisTaint
    private var cards: Set<String> = []
    /// When the relayed call under way stops being waited for (its time limit): a later answer does nothing (M5).
    private var deadline: Date?
    private let show: (ArisAgentReply) -> Void
    /// Whether the /ask stream is still open (M7: a card whose stream ended is a no).
    private let isOpen: () -> Bool

    /// This relay's read judgements (agy's own judge, the user's words for the turn).
    let memo: ArisReadMemo
    /// The user's own words for the turn. Not private: the desktop engine reads them through ArisDesktopTurn, whose
    /// conformance is in another file (audit desk-5: private, they never reached it, so on Antigravity no window was
    /// ever "named", every file panel was refused and every replace too).
    let request: String

    /// I1: `taint` is the turn's (outside text for a sealed or untrusted turn, screenSeen for a screen one).
    init(taint: ArisTaint, screen: Bool, handsFree: Bool, request: String, memo: ArisReadMemo, isOpen: @escaping () -> Bool,
         show: @escaping (ArisAgentReply) -> Void) {
        current = taint
        self.screen = screen
        self.handsFree = handsFree
        self.request = request
        self.memo = memo
        self.isOpen = isOpen
        self.show = show
    }

    func judgeRead(_ call: ArisReadCall, done: @escaping (ArisReadVerdict) -> Void) { memo.judge(call, request: request, done: done) }
    func quiet(_ status: String) { show(.status(status)) }
    /// The desktop overlay for the window a relayed `desktop …` line works in (ArisDesktopRoutes).
    func operating(_ target: ArisOperatingTarget) { show(.operating(target)) }

    var brainName: String { ArisBrain.antigravity.rawValue }
    var taint: ArisTaint { lock.withLock { current } }
    func takeOutsideText() { lock.withLock { current = .outsideText } }
    func ask(_ card: ArisMCPCard, answer: @escaping (ArisMCPAnswer) -> Void) {
        guard isOpen() else { return answer(.no) }
        // The one card clock (QA BUG-33 reopened): as long as any card of a conversation waits, the app closing it first.
        let shown = ArisMCPCards.shared.put(card, timeout: ArisCardEdit.questionTimeout, answer: answer)
        lock.withLock { _ = cards.insert(shown.id) }
        show(.confirm(shown))
        watch(shown.id)
    }

    /// Every card this relay put up is a no (its time ran out, or its stream ended).
    /// The relayed call is still waited for: its stream is open and its time hasn't run out (M5).
    var live: Bool { isOpen() && (lock.withLock { deadline }.map { Date() < $0 } ?? true) }

    /// A relayed call starts: answers count until `seconds` from now.
    func startCall(limit seconds: TimeInterval) { lock.withLock { deadline = Date().addingTimeInterval(seconds) } }

    func cancelAll() {
        let ids = lock.withLock { () -> Set<String> in
            let all = cards
            cards = []
            return all
        }
        ArisMCPCards.shared.cancel(ids)
    }

    private func watch(_ id: String) {
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, ArisMCPCards.shared.isWaiting(id) else { return }
            if self.isOpen() { self.watch(id) } else { ArisMCPCards.shared.cancel([id]) }
        }
    }
    func audit(_ fields: [String: String]) {
        ArisWhyDesk.shared.gated(ArisAgentRunner.auditJSON(fields))
        ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(fields.merging(["question": "mcp"]) { $1 }), key: "mcp")
    }
}

/// One outcome handed across threads.
final class ArisMCPOutcomeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: ArisMCPOutcome?
    func set(_ outcome: ArisMCPOutcome) { lock.withLock { if stored == nil { stored = outcome } } }
    var value: ArisMCPOutcome? { lock.withLock { stored } }
}

enum ArisMCPRoutes {
    /// How long one relayed call may take, its card included: past the card's own limit, so the card always ends first
    /// (security review LOW 10, as the desktop relay).
    static let relayLimit: TimeInterval = ArisCardEdit.questionTimeout + 10

    /// One `mcp …` line of agy's aris-run block, run through the hub (blocks: a card may wait for the user).
    static func relayed(_ words: [String], turn: ArisMCPTurn) -> String {
        let rest = Array(words.dropFirst())
        let outcome: ArisMCPOutcome
        switch rest.first {
        case "list" where rest.count <= 2:
            outcome = ArisMCPHub.shared.listing(only: rest.count == 2 ? rest[1] : nil, turn: turn)
        case "call" where rest.count >= 3:
            let values = Array(rest.dropFirst(3))
            let arguments: ArisMCPHub.Arguments = values.count == 1 && values[0].hasPrefix("{") ? .json(values[0])
                : values.isEmpty ? .json("{}") : .pairs(values)
            let done = DispatchSemaphore(value: 0)
            let box = ArisMCPOutcomeBox()
            ArisMCPHub.shared.call(service: rest[1], tool: rest[2], arguments: arguments, turn: turn) { result in
                box.set(result)
                done.signal()
            }
            // A relayed call has a time limit of its own (M7): past it, its card comes down as a no.
            if done.wait(timeout: .now() + relayLimit) == .timedOut {
                (turn as? ArisRelayMCPTurn)?.cancelAll()
                outcome = .failed("it took too long, so Aris stopped it")
            } else {
                outcome = box.value ?? .failed("no answer")
            }
        default:
            outcome = .failed(ArisMCPHub.usage)
        }
        return String(outcome.output.prefix(ArisAgyRelay.maxResult))
    }

    static func json(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
    }

    /// POST /mcp-tool: whose turn it is (the credential and the process tree), then the hub, off the server queue.
    static func tool(_ object: [String: Any], on connection: NWConnection, agentPort: UInt16, reply: @escaping (String, Data) -> Void) {
        let refuse = { (why: String) in
            ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["answer": "refused (\(why))", "question": "mcp-tool"]), key: "mcp")
            reply("403 Forbidden", json(["status": 1, "output": "aris-tools mcp works only inside an Aris turn."]))
        }
        guard let credential = object["turn"] as? String, let runner = ArisAgentRunner.runner(forMCPTurn: credential) else {
            return refuse("no turn credential")
        }
        let remotePort = ArisTeammateDesk.remotePort(of: connection)
        DispatchQueue.global(qos: .userInitiated).async {
            let now = runner.mcpSnapshot()
            guard now.active else { return refuse("no turn under way") }
            // agy reaches the services only through Aris's relay (I6): its own process has a web search no gate covers.
            guard runner.brain != .antigravity else { return refuse("Antigravity uses the relay") }
            guard let pid = now.pid, let remotePort, ArisMCPCaller.isInside(root: pid, remotePort: remotePort, agentPort: agentPort) else {
                return refuse("not from the brain's own process")
            }
            let turn = ArisRunnerMCPTurn(runner: runner, handsFree: now.handsFree, screen: now.screen, credential: credential)
            let send = { (outcome: ArisMCPOutcome) in reply("200 OK", json(["status": Int(outcome.status), "output": outcome.output])) }
            switch object["op"] as? String {
            case "judge":
                // A hook asks the read judge: the user's own words come from the runner, never from the caller.
                guard let tool = object["tool"] as? String, let arguments = object["arguments"] as? String, tool.count <= 200 else {
                    return send(.failed(ArisReadWhy.undecided.rawValue))
                }
                runner.judgeRead(ArisReadCall(tool: tool, arguments: arguments), showsBlock: true) { verdict in
                    // Only the fixed kind goes back (I5): never the judge's words.
                    let answer = ArisReadGate.reply(verdict)
                    send(ArisMCPOutcome(status: answer.status, output: answer.output))
                }
            case "list":
                send(ArisMCPHub.shared.listing(only: object["service"] as? String, turn: turn))
            case "wait":
                // `mcp wait <id>`: a call that outlasted one shell command (ArisSlowCalls).
                guard let id = object["id"] as? String, ArisSlowCalls.isID(id) else { return send(.failed(ArisMCPHub.usage)) }
                ArisSlowCalls.shared.wait(id: id, owner: credential, kind: "mcp", reply: send)
            case "call":
                guard let service = object["service"] as? String, let tool = object["tool"] as? String, service.count <= 64, tool.count <= 128 else {
                    return send(.failed(ArisMCPHub.usage))
                }
                let arguments: ArisMCPHub.Arguments
                if let pairs = object["pairs"] as? [String], pairs.count <= 40 {
                    arguments = .pairs(pairs)
                } else {
                    arguments = .json(object["arguments"] as? String ?? "{}")
                }
                ArisSlowCalls.shared.run(owner: credential, kind: "mcp", work: { done in
                    ArisMCPHub.shared.call(service: service, tool: tool, arguments: arguments, turn: turn, done: done)
                }, reply: send)
            default:
                send(.failed(ArisMCPHub.usage))
            }
        }
    }

    /// POST /mcp, after the app was checked to be itself. Off the server queue: the Keychain and a test can take seconds.
    static func settings(_ object: [String: Any], reply: @escaping (String, Data) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let hub = ArisMCPHub.shared
            let audit = { (what: String) in
                ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["answer": what, "question": "mcp settings"]), key: "settings")
            }
            let done = { (result: Result<Void, ArisMCPConfigError>, what: String) in
                switch result {
                case .success: audit(what); reply("200 OK", json([:]))
                case .failure(let error): reply("400 Bad Request", json(["error": error.message]))
                }
            }
            switch object["op"] as? String {
            case "list":
                let rows = hub.settingsList()
                // Changed behind Aris's back (I5): nothing in it starts until the user saves the list again.
                reply("200 OK", json(hub.listProblem.map { ["servers": rows, "problem": $0] } ?? ["servers": rows]))
            case "save":
                guard let name = object["name"] as? String, let target = object["target"] as? String, name.count <= 64, target.count <= 4_096 else {
                    return reply("400 Bad Request", json(["error": "이름과 명령 또는 URL을 넣어 주세요."]))
                }
                let id = object["id"] as? String
                switch hub.save(id: id, name: name, target: target, secretName: object["secretName"] as? String, secret: object["secret"] as? String,
                                enabled: object["enabled"] as? Bool ?? true) {
                case .success(let server):
                    audit(id == nil ? "added \(server.name)" : "changed \(server.name)")
                    reply("200 OK", json(["server": hub.settingsList().first { $0["id"] as? String == server.id } ?? [:]]))
                case .failure(let error):
                    reply("400 Bad Request", json(["error": error.message]))
                }
            case "composio":
                let key = object["key"] as? String
                done(hub.setComposio(key: key?.isEmpty == true ? nil : key), key == nil ? "removed Composio" : "saved the Composio key")
            case "remove":
                guard let id = object["id"] as? String else { return reply("400 Bad Request", json([:])) }
                done(hub.remove(id), "removed a service")
            case "enable":
                guard let id = object["id"] as? String, let on = object["on"] as? Bool else { return reply("400 Bad Request", json([:])) }
                done(hub.setEnabled(id, on), on ? "turned a service on" : "turned a service off")
            case "test":
                guard let id = object["id"] as? String else { return reply("400 Bad Request", json([:])) }
                let (ok, message) = hub.test(id)
                reply("200 OK", json(["ok": ok, "message": message]))
            default:
                reply("400 Bad Request", json([:]))
            }
        }
    }
}
