// Tests for jv-mind2 (ARCHITECTURE Part 2, the second pass on Core 2's mind): one card per call (the trust gate's yes
// handed to the call's route as a single-use pass bound to the call and its turn), the Mind's own loop for API brains
// in the `aris-agent mind-brain` child, the app's World in the helper's trust facts, the undo of items and of simple
// shell commands in the record, and an unanswered card recorded as such. Called from main.swift.
import Foundation

func runMind2Tests() {
    mind2PassStoreTests()
    mind2PassKeyTests()
    mind2OneCardTests()
    mind2BrainTests()
    mind2DriverTests()
    mind2WorldTests()
    mind2ItemUndoTests()
    mind2ShellUndoTests()
    mind2UnansweredTests()
    mind2UndoSecurityTests()
    mind2VoiceTests()
    mind2RecordQueryTests()
    mind2FocusWorldTests()
}

private let mind2Tools = "/Applications/Aris.app/Contents/Helpers/aris-tools"

private func mind2Home() -> String {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-mind2-\(UUID().uuidString.prefix(8))")
    try? FileManager.default.createDirectory(at: folder.appendingPathComponent("Documents"), withIntermediateDirectories: true)
    return URL(fileURLWithPath: folder.path).resolvingSymlinksInPath().path
}

private func mind2Call(_ id: String, _ name: String, _ arguments: [String: Any]) -> ArisMindToolCall {
    let data = try! JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys])
    return ArisMindToolCall(id: id, name: name, arguments: String(decoding: data, as: UTF8.self))
}

/// A clock the tests move.
private final class Mind2Clock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}

// MARK: - The pass store

private func mind2PassStoreTests() {
    let clock = Mind2Clock()
    let passes = ArisMindPasses(now: { clock.now })
    let send = ["message", "엄마", "곧 도착"]
    let key = ArisMindPassKey.key(argv: send, stdin: nil)
    guard let token = passes.mint(intent: "turn-A", capability: "aris.send_message", argv: send, stdin: nil) else {
        return check(false, "mind2 pass: a message call gets a pass")
    }
    check(ArisMindPasses.wellFormed(token) && token != passes.mint(intent: "turn-A", capability: "aris.send_message", argv: send, stdin: nil),
          "mind2 pass: 256 random bits, a new one each time")
    check(passes.redeem(token, turn: "turn-A", key: key), "mind2 pass: the pass opens exactly its own call in its own turn")
    check(!passes.redeem(token, turn: "turn-A", key: key), "mind2 pass: a replayed pass is refused")
    // A pass for call A does not open call B (and is gone after the try).
    let other = passes.mint(intent: "turn-A", capability: "aris.send_message", argv: send, stdin: nil)
    check(!passes.redeem(other, turn: "turn-A", key: ArisMindPassKey.key(argv: ["message", "엄마", "늦어"], stdin: nil)),
          "mind2 pass: a pass for one message does not send another")
    check(!passes.redeem(other, turn: "turn-A", key: key), "mind2 pass: a pass tried on the wrong call is burnt")
    let third = passes.mint(intent: "turn-A", capability: "aris.send_message", argv: send, stdin: nil)
    check(!passes.redeem(third, turn: "turn-B", key: key), "mind2 pass: a pass of another turn opens nothing")
    // A stale turn's pass: the turn ended.
    let stale = passes.mint(intent: "turn-C", capability: "aris.send_message", argv: send, stdin: nil)
    passes.end(intent: "turn-C")
    check(!passes.redeem(stale, turn: "turn-C", key: key), "mind2 pass: a pass of a turn that ended is refused")
    let late = passes.mint(intent: "turn-D", capability: "aris.send_message", argv: send, stdin: nil)
    clock.now = clock.now.addingTimeInterval(ArisMindPasses.lifetime + 1)
    check(!passes.redeem(late, turn: "turn-D", key: key), "mind2 pass: a pass older than its two minutes is refused")
    check(!passes.redeem("not-a-token", turn: "turn-A", key: key) && !passes.redeem(nil, turn: "turn-A", key: key)
          && !passes.redeem(ArisMindPasses.token(), turn: "turn-A", key: key), "mind2 pass: a forged or missing pass opens nothing")
    check(passes.mint(intent: "t", capability: "aris.timer", argv: ["timer", "5"], stdin: nil) == nil
          && passes.mint(intent: "t", capability: "shell.run", argv: nil, stdin: nil) == nil,
          "mind2 pass: a call whose route has no card of its own gets no pass")
    // The route's side: only with the switch on, only a redeemed pass.
    let fresh = ArisMindPasses()
    let good = fresh.mint(intent: "T", capability: "aris.send_message", argv: send, stdin: nil)!
    check(ArisMindPasses.standIn(["pass": good], turn: "T", key: key, passes: fresh, isOn: { false }) == nil,
          "mind2 pass: with arisCore2 off a route never takes a pass")
    check(ArisMindPasses.standIn(["pass": good], turn: "T", key: key, passes: fresh, isOn: { true }) != nil
          && ArisMindPasses.standIn(["pass": good], turn: "T", key: key, passes: fresh, isOn: { true }) == nil,
          "mind2 pass: a route takes its pass once")
    check(ArisMindPasses.standIn([:], turn: "T", key: key, passes: fresh, isOn: { true }) == nil, "mind2 pass: no pass, no stand-in")
}

// MARK: - The keys read the same from both sides

private func mind2PassKeyTests() {
    let folder = mind2Home() + "/cred"
    try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    try? Data("cred-1".utf8).write(to: URL(fileURLWithPath: folder + "/turn"))
    let pass = ArisMindPasses.token()
    let environment = ["ARIS_MCP_TURN_FILE": folder + "/turn", ArisTurnGate.stateKey: folder, ArisMindPasses.environmentKey: pass]
    func argv(_ name: String, _ input: [String: Any]) -> (argv: [String], stdin: String?)? {
        ArisHandsFace.call(function: name, input: input, tools: mind2Tools).flatMap { found in found.argv.map { ($0, found.stdin) } }
    }
    // The message route: what aris-tools sends it, and the key the gate's call made.
    if let send = argv("send_message", ["to": "엄마", "text": "곧 도착해"]), case .agent(let to, let text, _) = messageRouting(Array(send.argv.dropFirst()), environment: environment) {
        check(ArisMindPassKey.key(argv: send.argv, stdin: send.stdin) == ArisMindPassKey.messageKey(to: to, text: text), "mind2 key: a message reads the same on both sides")
    } else { check(false, "mind2 key: send_message reaches the message route") }
    // NFC and NFD Hangul are the same message.
    check(ArisMindPassKey.messageKey(to: "엄마", text: "곧") == ArisMindPassKey.messageKey(to: "엄마".decomposedStringWithCanonicalMapping, text: "곧"),
          "mind2 key: a launcher's spelling of the Hangul doesn't matter")
    // A handed-off write (an event): the route gets the words as given.
    if let event = argv("add_event", ["title": "치과", "start": "2026-11-20 15:00"]), case .agent(let words, _) = handOffRouting(event.argv, environment: environment) {
        check(ArisMindPassKey.key(argv: event.argv, stdin: nil) == ArisMindPassKey.actionKey(words: words), "mind2 key: a handed-off write reads the same")
    } else { check(false, "mind2 key: add_event is handed off to the action route") }
    // A connected service's call, both of its argument forms.
    for rest in [[String](), ["{\"q\":\"x\"}"], ["q=x", "n=2"]] {
        let words = ["mcp", "call", "notion", "search"] + rest
        guard case .success(let body) = mcpRequest(Array(words.dropFirst()), environment: environment) else {
            check(false, "mind2 key: mcp body for \(rest)"); continue
        }
        let pairs = body["pairs"] as? [String]
        check(body["pass"] as? String == pass, "mind2 key: aris-tools hands the pass to the service route")
        check(ArisMindPassKey.key(argv: words, stdin: nil) == ArisMindPassKey.mcpKey(service: "notion", tool: "search", pairs: pairs,
                                                                                      arguments: pairs == nil ? body["arguments"] as? String : nil),
              "mind2 key: a service call reads the same (\(rest))")
    }
    // Aside.
    if let brief = argv("aside_task", ["brief": "항공권 찾아 줘"]), case .success(let body) = asideRequest(Array(brief.argv.dropFirst()), environment: environment) {
        check(ArisMindPassKey.key(argv: brief.argv, stdin: nil) == ArisMindPassKey.asideKey(brief: body["brief"] as? String ?? "") && body["pass"] as? String == pass,
              "mind2 key: an Aside brief reads the same, with its pass")
    } else { check(false, "mind2 key: aside_task reaches Aside's route") }
    // The desktop: the words after `desktop`, the text as aris-tools reads it from stdin (one final line break off).
    if let typed = argv("desktop_type", ["ref": "@s1:e3", "text": "안녕"]) {
        check(ArisMindPassKey.key(argv: typed.argv, stdin: (typed.stdin ?? "") + "\n") == ArisMindPassKey.desktopKey(words: Array(typed.argv.dropFirst()), text: typed.stdin),
              "mind2 key: a desktop call and its text read the same")
        check(ArisMindPassKey.key(argv: typed.argv, stdin: typed.stdin) != ArisMindPassKey.desktopKey(words: Array(typed.argv.dropFirst()), text: "다른 글"),
              "mind2 key: other text is another call")
    } else { check(false, "mind2 key: desktop_type has its words") }
    // Without a pass in the environment, nothing is added: the routes behave exactly as before.
    var plain = environment
    plain[ArisMindPasses.environmentKey] = nil
    if case .success(let body) = mcpRequest(["call", "notion", "search"], environment: plain) { check(body["pass"] == nil, "mind2 key: no pass, no field") }
    check(mindPassed(["a": 1], environment: [ArisMindPasses.environmentKey: "short"])["pass"] == nil, "mind2 key: a malformed pass isn't passed on")
}

// MARK: - One card per call

private final class Mind2RouteTurn: ArisMessageTurn {
    var request: String
    var isTask = false
    var taint = ArisTaint.none
    var handsFree = false
    var critical = false
    var scopes: Set<ArisTeammateScope>? = nil
    var standIn: ArisMindStandIn?
    private(set) var shown: [ArisMCPCard] = []
    init(request: String) { self.request = request }
    func stillSendable() -> Bool { true }
    func ask(_ card: ArisMCPCard, answer: @escaping (ArisMCPAnswer) -> Void) {
        ArisMindStandIn.ask(card, standIn: standIn, audit: { _ in }, show: { card, done in self.shown.append(card); done(.yes([:])) }, answer: answer)
    }
    func audit(_ fields: [String: String]) {}
}

private func mind2OneCardTests() {
    let home = mind2Home()
    let saved = ArisMessagePass.folderOverride
    ArisMessagePass.folderOverride = URL(fileURLWithPath: home + "/passes")
    defer { ArisMessagePass.folderOverride = saved }
    let gate = ArisTrustGate(home: home, world: { _ in ArisWorldFacts(contacts: [.init(name: "엄마", addresses: ["mom@example.com"])], home: home) })
    let passes = ArisMindPasses()
    let judge = ArisMindJudge(gate: gate, tools: mind2Tools, passes: passes)
    judge.cardWait = 2
    var gateCards = 0
    let card: ArisMindJudge.Card = { _, answer in gateCards += 1; answer(true) }
    let words = "엄마한테 곧 도착 이라고 보내 줘"
    judge.turn(session: "s1", intent: "cred-1", words: words)
    let call = mind2Call("m1", "send_message", ["to": "엄마", "text": "곧 도착"])
    let decided = judge.decide(session: "s1", task: nil, calls: [call])
    check(decided.first?.verdict == .waits, "mind2 one card: the dictated message waits on the gate's countdown card")
    let allowed = judge.ask(session: "s1", task: nil, intent: "cred-1", waiting: decided, card: card)
    let token = judge.pass(session: "s1", call: "m1")
    check(allowed == ["m1"] && gateCards == 1 && token != nil, "mind2 one card: the owner's yes on the gate's card mints the call's pass")
    // The message route with the pass: its own card is not shown again, and the message goes.
    let turn = Mind2RouteTurn(request: words)
    turn.standIn = ArisMindPasses.standIn(["pass": token ?? ""], turn: "cred-1", key: ArisMindPassKey.messageKey(to: "엄마", text: "곧 도착"),
                                          passes: passes, isOn: { true })
    var sent: [[String]] = []
    let outcome = ArisMessageGate.answer(to: "엄마", text: "곧 도착", turn: turn, tools: mind2Tools, home: home, limit: 2) { argv in
        sent.append(argv)
        return ArisMCPOutcome(status: 0, output: "sent to 엄마")
    }
    check(gateCards + turn.shown.count == 1 && sent.count == 1 && outcome.status == 0, "mind2 one card: one card for the message, then it is sent (\(turn.shown.count) more)")
    // Without the pass (or with it spent) the route asks exactly as before.
    let again = Mind2RouteTurn(request: words)
    again.standIn = ArisMindPasses.standIn(["pass": token ?? ""], turn: "cred-1", key: ArisMindPassKey.messageKey(to: "엄마", text: "곧 도착"),
                                           passes: passes, isOn: { true })
    _ = ArisMessageGate.answer(to: "엄마", text: "곧 도착", turn: again, tools: mind2Tools, home: home, limit: 2) { _ in ArisMCPOutcome(status: 0, output: "sent to 엄마") }
    check(again.standIn == nil && again.shown.count == 1, "mind2 one card: a replayed pass is refused and the route's own card shows")
    // A handed-off write with a pass: the action route's card is the one it stands in for.
    let write = ["trash", home + "/Documents/a.txt"]
    let writeToken = passes.mint(intent: "cred-1", capability: "aris.trash", argv: write, stdin: nil)
    let writer = Mind2RouteTurn(request: "문서 정리해 줘")
    writer.standIn = ArisMindPasses.standIn(["pass": writeToken ?? ""], turn: "cred-1", key: ArisMindPassKey.actionKey(words: write), passes: passes, isOn: { true })
    var ran = 0
    _ = ArisActionGate.answer(write, turn: writer, tools: mind2Tools, home: home, limit: 2, notes: ArisHandOffNotes()) { _ in ran += 1; return ArisMCPOutcome(status: 0, output: "ok") }
    check(writeToken != nil && writer.standIn != nil && writer.shown.isEmpty && ran == 1, "mind2 one card: a handed-off write the gate's card covered asks no second card")
    // Call A's pass doesn't open call B on the same route.
    let otherWrite = ["trash", home + "/Documents/b.txt"]
    let aToken = passes.mint(intent: "cred-1", capability: "aris.trash", argv: write, stdin: nil)
    let b = Mind2RouteTurn(request: "문서 정리해 줘")
    b.standIn = ArisMindPasses.standIn(["pass": aToken ?? ""], turn: "cred-1", key: ArisMindPassKey.actionKey(words: otherWrite), passes: passes, isOn: { true })
    _ = ArisActionGate.answer(otherWrite, turn: b, tools: mind2Tools, home: home, limit: 2, notes: ArisHandOffNotes()) { _ in ArisMCPOutcome(status: 0, output: "ok") }
    check(b.standIn == nil && b.shown.count == 1, "mind2 one card: call A's pass doesn't open call B: B's own card shows")
    // The desktop, a service and Aside ask through the same turn ask: one stand-in answers the call's first card only,
    // never a card that isn't the call's own (Aside's install or sign-in, the automatic check's stopped card).
    for kind in ["desktop", "mcp", "aside"] {
        let standIn = ArisMindStandIn()
        var shown = 0, yes = 0
        let ask = { (card: ArisMCPCard) in
            ArisMindStandIn.ask(card, standIn: standIn, audit: { _ in }, show: { _, done in shown += 1; done(.no) }) { answer in if case .yes = answer { yes += 1 } }
        }
        ask(ArisMCPCard(title: "Install Aside", detail: "", full: nil, fields: [], allow: "Install"))
        var stopped = ArisMCPCard(title: "확인", detail: "", full: nil, fields: [])
        stopped.stopped = true
        ask(stopped)
        ask(ArisMCPCard(title: kind, detail: "the call", full: nil, fields: []))
        ask(ArisMCPCard(title: kind, detail: "a second card", full: nil, fields: []))
        check(yes == 1 && shown == 3, "mind2 one card: on the \(kind) route the pass answers the call's own card once, nothing else (\(yes) yes, \(shown) shown)")
    }
    // A stale turn: the next turn of the conversation ends the last one's passes.
    let staleToken = passes.mint(intent: "cred-1", capability: "aris.send_message", argv: ["message", "엄마", "곧 도착"], stdin: nil)
    judge.turn(session: "s1", intent: "cred-2", words: "고마워")
    check(!passes.redeem(staleToken, turn: "cred-1", key: ArisMindPassKey.messageKey(to: "엄마", text: "곧 도착")), "mind2 one card: a stale turn's pass is refused")
    // A no on the gate's card mints nothing.
    judge.turn(session: "s2", intent: "cred-3", words: words)
    let declined = judge.decide(session: "s2", task: nil, calls: [mind2Call("m2", "send_message", ["to": "엄마", "text": "곧 도착"])])
    _ = judge.ask(session: "s2", task: nil, intent: "cred-3", waiting: declined, card: { _, answer in answer(false) })
    check(judge.pass(session: "s2", call: "m2") == nil, "mind2 one card: a no mints no pass")
}

// MARK: - The Mind's own loop for API brains (`aris-agent mind-brain`)

private final class Mind2Scripted: ArisMindProvider, @unchecked Sendable {
    let lock = NSLock()
    var rounds: [([String], [ArisMindToolCall])]
    init(_ rounds: [([String], [ArisMindToolCall])]) { self.rounds = rounds }
    func send(system: String, messages: [ArisMindMessage], tools: [ArisMindToolSpec], event: @escaping (ArisMindProviderEvent) -> Void) -> ArisMindProviderEnd {
        guard let round = lock.withLock({ rounds.isEmpty ? nil : rounds.removeFirst() }) else { return .done(.endTurn) }
        round.0.forEach { event(.text($0)) }
        round.1.forEach { event(.toolCall($0)) }
        return .done(round.1.isEmpty ? .endTurn : .toolUse)
    }
    func cancel() {}
}

/// The child and the helper's side of /mind-call joined by a function call: the real gate, judge and record in a temp
/// home; aris-tools and the shell are fakes that log what they were asked and with which pass.
private final class Mind2BrainRig: @unchecked Sendable {
    let home = mind2Home()
    let gate: ArisTrustGate
    let judge: ArisMindJudge
    let passes = ArisMindPasses()
    let lock = NSLock()
    var cards: [ArisConfirmation] = []
    var answer: Bool? = true
    var posted: [String] = []
    var allowed: [[String]] = []
    var ran: [(argv: [String], pass: String?)] = []
    var lines: [[String: Any]] = []
    var words = ""
    let session = "claude-mind"
    var credential = "cred-mind-1"

    init() {
        let home = self.home
        gate = ArisTrustGate(home: home, world: { _ in ArisWorldFacts(contacts: [.init(name: "엄마", addresses: ["mom@example.com"]), .init(name: "아빠")], home: home) })
        judge = ArisMindJudge(gate: gate, tools: mind2Tools, passes: passes)
        judge.cardWait = 2
    }

    /// What POST /mind-call answers, as ArisMindRoute+Live does after its checks of the caller.
    func post(_ body: [String: Any], _ wait: TimeInterval) -> [String: Any]? {
        guard body["turn"] as? String == credential else { return nil }
        let op = body["op"] as? String ?? ""
        lock.withLock { posted.append(op) }
        let allow = { [self] (argv: [String]) in lock.withLock { allowed.append(argv) } }
        switch op {
        case "decide_batch":
            judge.turn(session: session, intent: credential, words: words)
            return ArisMindRoute.decideBatch(judge: judge, session: session, task: nil, calls: body["calls"] as? [[String: Any]] ?? [], allow: allow)
        case "ask":
            return ArisMindRoute.ask(judge: judge, session: session, task: nil, intent: credential, ids: body["ids"] as? [String] ?? [], allow: allow) { [self] card, answer in
                lock.withLock { cards.append(card) }
                let said = lock.withLock { self.answer }
                DispatchQueue.global().async { answer(said) }
            }
        case "done":
            ArisMindRoute.done(judge: judge, session: session, object: body, id: body["id"] as? String ?? "")
            return [:]
        default: return nil
        }
    }

    func brain(_ provider: Mind2Scripted) -> ArisMindBrain {
        ArisMindBrain(tools: mind2Tools, provider: { _ in provider }, post: { [self] body, wait in post(body, wait) }, credential: { [self] in credential },
                      executor: { [self] pass in
                          ArisMindExecutor(tools: mind2Tools, environment: [:], home: home, folder: URL(fileURLWithPath: home + "/own"),
                                           runTools: { [self] argv, _ in lock.withLock { ran.append((argv, pass)) }; return .printed("done") },
                                           shell: { _, _, _ in .printed("ok") }, store: ArisUndoStore(folder: URL(fileURLWithPath: home + "/undo-store")))
                      },
                      send: { [self] data in
                          if let object = (try? JSONSerialization.jsonObject(with: data.prefix(while: { $0 != 0x0A }))) as? [String: Any] { lock.withLock { lines.append(object) } }
                      })
    }

    var record: [ArisRecordEntry] { ArisRecordJournal.entries(home: home) }
}

private func mind2BrainTests() {
    let rig = Mind2BrainRig()
    rig.words = "엄마한테 곧 도착 이라고 보내고 아빠한테도 곧 도착 이라고 보내 줘"
    let file = rig.home + "/Documents/plan.txt"
    try? Data("plan".utf8).write(to: URL(fileURLWithPath: file))
    let provider = Mind2Scripted([
        ([], [mind2Call("r1", "read_file", ["path": file]), mind2Call("m1", "send_message", ["to": "엄마", "text": "곧 도착"]),
              mind2Call("m2", "send_message", ["to": "아빠", "text": "곧 도착"])]),
        (["보냈어요"], []),
    ])
    let brain = rig.brain(provider)
    let end = brain.turn(rig.words, tier: .quick, task: false, context: "Now: 2026-11-18")
    check(end == .answered("보냈어요"), "mind2 brain: the turn answers: \(end)")
    check(rig.posted.first == "decide_batch" && rig.posted.filter { $0 == "decide_batch" }.count == 1 && rig.posted.filter { $0 == "ask" }.count == 1,
          "mind2 brain: one round, decided together, asked together: \(rig.posted)")
    check(rig.cards.count == 1, "mind2 brain: the round's two sends wait on one card (\(rig.cards.count))")
    let sends = rig.ran.filter { $0.argv.first == "message" }
    check(sends.count == 2 && sends.allSatisfy { $0.pass.map(ArisMindPasses.wellFormed) == true } && Set(sends.compactMap(\.pass)).count == 2,
          "mind2 brain: both sends run after the yes, each with its own pass for its route")
    check(rig.allowed.filter { $0.first == "message" }.count == 2, "mind2 brain: aris-tools' one-shot message passes are minted for exactly what was allowed")
    check(Set(rig.record.compactMap(\.capability)) == ["file.read", "aris.send_message"] && rig.record.filter { $0.capability == "aris.send_message" }.allSatisfy { $0.answer == "yes" },
          "mind2 brain: every call is one line of the record, the sends with the owner's yes")
    check(rig.lines.last?["type"] as? String == "result" && rig.lines.last?["text"] as? String == "보냈어요", "mind2 brain: the result line ends the turn")
    check(brain.conversation.count == 6, "mind2 brain: the conversation is kept for the next turn (\(brain.conversation.count))")
    // A no on the card runs nothing and is recorded.
    rig.answer = false
    rig.credential = "cred-mind-2"
    let before = rig.ran.count
    let declined = rig.brain(Mind2Scripted([([], [mind2Call("m3", "send_message", ["to": "엄마", "text": "늦어"])]), (["안 보냈어요"], [])]))
    rig.words = "엄마한테 늦어 라고 보내 줘"
    _ = declined.turn(rig.words, tier: .quick, task: false, context: "")
    check(rig.ran.count == before && rig.record.last?.answer == "no" && rig.allowed.filter { $0 == ["message", "엄마", "늦어"] }.isEmpty,
          "mind2 brain: a no runs nothing, mints nothing, and is recorded")
    // The helper not answering refuses every call (nothing runs on its own).
    let cut = ArisMindBrain(tools: mind2Tools, provider: { _ in Mind2Scripted([([], [mind2Call("t1", "timer", ["minutes": 5])]), (["음"], [])]) },
                            post: { _, _ in nil }, credential: { "x" }, executor: { _ in rig.brain(Mind2Scripted([])).executorForTests() }, send: { _ in })
    let runs = rig.ran.count
    _ = cut.turn("5분 타이머", tier: .quick, task: false, context: "")
    check(rig.ran.count == runs, "mind2 brain: with no answer from the helper nothing runs")
    // Stale: a newer turn takes over while the provider thinks; nothing of the old one is said or kept.
    let slow = Mind2Slow()
    let staleBrain = rig.brain(Mind2Scripted([]))
    let stale = ArisMindBrain(tools: mind2Tools, provider: { _ in slow }, post: { body, wait in rig.post(body, wait) }, credential: { rig.credential },
                              executor: { _ in staleBrain.executorForTests() }, send: { data in rig.lock.withLock { rig.lines.append(["raw": String(decoding: data, as: UTF8.self)]) } })
    let count = rig.lines.count
    let done = DispatchSemaphore(value: 0)
    var first: ArisMindEnd?
    DispatchQueue.global().async { first = stale.turn("하나", tier: .quick, task: false, context: ""); done.signal() }
    slow.started.wait()
    stale.cancel()
    slow.release.signal()
    done.wait()
    check(first == .stale && rig.lines.count == count && stale.conversation.isEmpty, "mind2 brain: a stale turn says and keeps nothing")
}

private final class Mind2Slow: ArisMindProvider, @unchecked Sendable {
    let started = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    func send(system: String, messages: [ArisMindMessage], tools: [ArisMindToolSpec], event: @escaping (ArisMindProviderEvent) -> Void) -> ArisMindProviderEnd {
        started.signal()
        release.wait()
        event(.text("늦은 답"))
        return .done(.endTurn)
    }
    func cancel() {}
}

private extension ArisMindBrain {
    /// An executor that runs nothing real (the tests' cut-off helper never lets anything through anyway).
    func executorForTests() -> ArisMindExecutor {
        ArisMindExecutor(tools: mind2Tools, environment: [:], home: NSTemporaryDirectory(), runTools: { _, _ in .printed("ran") }, shell: { _, _, _ in .printed("ran") },
                         store: ArisUndoStore(folder: URL(fileURLWithPath: NSTemporaryDirectory() + "/aris-mind2-undo")))
    }
}

private func mind2DriverTests() {
    let profile = ArisAPIProfile(id: "openai", quick: "gpt-x", strong: "", baseURL: nil, vision: nil, tools: nil)
    let driver = ArisMindBrainDriver(profile: profile, task: false, executable: URL(fileURLWithPath: "/Applications/Aris.app/Contents/Helpers/aris-agent"),
                                     hasKey: { true }, context: { "Now: 2026-11-18" })
    check(driver.launch()?.1 == ["mind-brain", "--profile", "openai"], "mind2 driver: the brain's process is aris-agent mind-brain with its profile")
    check(ArisMindBrainDriver(profile: profile, executable: URL(fileURLWithPath: "/x"), hasKey: { false }).missing == .key, "mind2 driver: no key, said as that")
    let asked = driver.ask("안녕", tier: .quick).first.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
    check(asked?["type"] as? String == "ask" && asked?["context"] as? String == "Now: 2026-11-18" && asked?["task"] as? Bool == false,
          "mind2 driver: the question goes with the World's context")
    check(driver.read(#"{"type":"delta","text":"네"}"#) == [.delta("네")] && driver.read(#"{"type":"result","text":" 네 "}"#) == [.result("네")],
          "mind2 driver: the answer streams and ends")
    check(driver.taint == .none, "mind2 driver: a clean conversation stays clean")
    _ = driver.ask("다시", tier: .quick)
    _ = driver.read("not json")
    check(driver.taint == .outsideText, "mind2 driver: a line it can't read fails closed")
    _ = driver.newConversation()
    check(driver.taint == .none, "mind2 driver: a new conversation starts clean")
    check(ArisMindBrainDriver.serves(core2: true, sealed: false, handsFree: false, scopes: nil)
          && !ArisMindBrainDriver.serves(core2: false, sealed: false, handsFree: false, scopes: nil)
          && !ArisMindBrainDriver.serves(core2: true, sealed: true, handsFree: false, scopes: nil)
          && !ArisMindBrainDriver.serves(core2: true, sealed: false, handsFree: true, scopes: nil)
          && !ArisMindBrainDriver.serves(core2: true, sealed: false, handsFree: false, scopes: [.files]),
          "mind2 driver: only Core 2's plain API turns go to the Mind; with the switch off, sealed, hands-free or a teammate's, the API brain's own path")
}

// MARK: - The app's World in the helper's trust facts

private func mind2WorldTests() {
    let home = mind2Home()
    let sent = ArisWorldWire.Payload(frontApp: "Messages", frontBundle: "com.apple.MobileSMS",
                                     contacts: [.init(name: "엄마", aliases: ["어머니"], addresses: ["mom@example.com"])], apps: ["Safari": ["사파리"]])
    let payload = ArisWorldWire.decode((try? JSONSerialization.data(withJSONObject: ArisWorldWire.encode(sent))).flatMap { try? JSONSerialization.jsonObject(with: $0) })
    check(payload == sent, "mind2 world: the app's World arrives as it was sent")
    func decision(_ app: ArisWorldWire.Payload?) -> ArisDecision {
        let gate = ArisTrustGate(home: home, world: { _ in ArisMindWorld.facts(live: nil, app: app, appAt: Date(), now: Date(), home: home) })
        gate.ownerTurn(session: "w", text: "엄마한테 곧 간다고 보내 줘")
        let arguments: [String: Any] = ["to": "mom@example.com", "text": "곧 간다"]
        guard let found = ArisHandsFace.call(function: "send_message", input: arguments, tools: mind2Tools) else { return .refuse(reason: "no call") }
        return gate.decide(session: "w", call: "c", capability: found.entry.id, effect: found.entry.effect(arguments), arguments: arguments,
                           argv: found.argv, stdin: nil).decision
    }
    let grounded = decision(payload)
    let bare = decision(nil)
    check(grounded != bare, "mind2 world: the contact grounds 엄마 as the address the call names (\(grounded) with it, \(bare) without)")
    if case .sayThenRun = grounded {} else { check(false, "mind2 world: the owner named her, so it is said first with a moment to stop: \(grounded)") }
    // Only from the app itself, only with Core 2 on.
    let saved = ArisCore2.isOn
    defer { ArisCore2.isOn = saved }
    ArisCore2.isOn = { false }
    ArisMindLive.heard(ArisWorldWire.encode(sent), fromApp: true)
    check(ArisMindLive.facts(home: home).contacts.isEmpty, "mind2 world: with arisCore2 off the helper takes nothing")
    ArisCore2.isOn = { true }
    ArisMindLive.heard(ArisWorldWire.encode(sent), fromApp: false)
    check(ArisMindLive.facts(home: home).contacts.isEmpty, "mind2 world: a caller that isn't the app gives the helper no World")
    ArisMindLive.heard(ArisWorldWire.encode(sent), fromApp: true)
    let facts = ArisMindLive.facts(home: home)
    check(facts.contacts.map(\.name) == ["엄마"] && facts.apps["Safari"] == ["사파리"], "mind2 world: the app's contacts and nicknames reach the trust facts")
}

// MARK: - Undo coverage

private func mind2ItemUndoTests() {
    let now = Date()
    let stamp = ISO8601DateFormatter().string(from: now)
    let old = ISO8601DateFormatter().string(from: now.addingTimeInterval(-600))
    func entry(_ summary: String, _ undo: [String: Any]?, date: String, undone: Bool = false, id: String = UUID().uuidString) -> [String: Any] {
        var object: [String: Any] = ["id": id, "date": date, "summary": summary, "undone": undone, "job": "대화", "worker": "API"]
        if let undo { object["undo"] = undo }
        return object
    }
    let event = ["event", "치과", "--start", "2026-11-20 15:00", "--minutes", "30"]
    let made = entry("일정 추가: 치과", ["deleteEvent": ["id": "UID-1"]], date: stamp)
    check(ArisMindItemUndo.recipe(argv: event, since: now, entries: [made]) == .itemCreated(kind: "calendar", id: "UID-1"),
          "mind2 undo: an event made through aris-tools gets its undo in the record")
    check(ArisMindItemUndo.recipe(argv: event, since: now, entries: [made, entry("일정 추가: 치과", ["deleteEvent": ["id": "UID-2"]], date: stamp)]) == nil,
          "mind2 undo: two entries that could be it: none (never a wrong one)")
    check(ArisMindItemUndo.recipe(argv: event, since: now, entries: [entry("일정 추가: 치과", ["deleteEvent": ["id": "UID-0"]], date: old)]) == nil
          && ArisMindItemUndo.recipe(argv: event, since: now, entries: [entry("일정 추가: 치과", ["deleteEvent": ["id": "UID-3"]], date: stamp, undone: true)]) == nil
          && ArisMindItemUndo.recipe(argv: event, since: now, entries: [entry("일정 추가: 회의", ["deleteEvent": ["id": "UID-4"]], date: stamp)]) == nil,
          "mind2 undo: an older, undone or other entry is never taken for this call's")
    let todo = ["todo", "add", "우유", "사기", "--due", "내일"]
    check(ArisMindItemUndo.recipe(argv: todo, since: now, entries: [entry("할 일 추가: 우유 사기", ["removeTodo": ["id": "R-9"]], date: stamp)]) == .itemCreated(kind: "reminder", id: "R-9"),
          "mind2 undo: a to-do made through aris-tools gets its undo in the record")
    check(ArisMindItemUndo.expected(["note", "장보기"]) == nil && ArisMindItemUndo.expected(["remind", "약"]) == nil && ArisMindItemUndo.expected(["event", "find", "--from", "x"]) == nil,
          "mind2 undo: notes, remind reminders and reads get none")
    // Taking it back: the entry that holds the id, undone by aris-tools.
    let holder = UUID()
    var asked: [[String]] = []
    let entries = [entry("일정 추가: 치과", ["deleteEvent": ["id": "UID-1"]], date: stamp, id: holder.uuidString)]
    let removed = (try? ArisMindItemUndo.remove(kind: "calendar", id: "UID-1", entries: entries) { asked.append($0); return (0, "undone") }) != nil
    check(removed && asked == [["undo", "--id", holder.uuidString, "--confirmed"]], "mind2 undo: the record's undo of an event goes through its activity entry")
    check((try? ArisMindItemUndo.remove(kind: "calendar", id: "UID-404", entries: entries) { _ in (0, "") }) == nil
          && (try? ArisMindItemUndo.remove(kind: "calendar", id: "UID-1", entries: entries) { _ in (1, "Calendar didn't answer") }) == nil,
          "mind2 undo: an item no longer in the log, or an undo that failed, says so")
    // Through the executor: the call's undo is in its result (and so in the record).
    let home = mind2Home()
    var executor = ArisMindExecutor(tools: mind2Tools, environment: [:], home: home, runTools: { _, _ in .printed("일정을 추가했어요") }, shell: { _, _, _ in .printed("") },
                                    store: ArisUndoStore(folder: URL(fileURLWithPath: home + "/undo-store")))
    executor.hooks = ArisMindUndoHooks(volume: { nil }, setVolume: { _ in })
    executor.activity = { [entry("일정 추가: 치과", ["deleteEvent": ["id": "UID-7"]], date: ISO8601DateFormatter().string(from: Date()))] }
    if let found = ArisHandsFace.call(function: "add_event", input: ["title": "치과", "start": "2026-11-20 15:00"], tools: mind2Tools) {
        let result = executor.run(found.entry, arguments: ["title": "치과", "start": "2026-11-20 15:00"], argv: found.argv, stdin: nil,
                                  caller: ArisUndoCaller(session: "u", provenance: .ownerSaid))
        check(result.undo == .itemCreated(kind: "calendar", id: "UID-7"), "mind2 undo: the executor reads the event's id after the call: \(String(describing: result.undo))")
    } else { check(false, "mind2 undo: add_event reads") }
}

private func mind2ShellUndoTests() {
    let home = mind2Home()
    let docs = home + "/Documents"
    try? Data("a".utf8).write(to: URL(fileURLWithPath: docs + "/a.txt"))
    try? FileManager.default.createDirectory(atPath: docs + "/box", withIntermediateDirectories: true)
    try? Data("b".utf8).write(to: URL(fileURLWithPath: docs + "/b.txt"))
    check(ArisMindShellUndo.plan("mkdir " + docs + "/new", cwd: home, home: home)?.recipe == .fileCreated(path: docs + "/new"), "mind2 shell undo: mkdir of a new folder: \(String(describing: ArisMindShellUndo.plan("mkdir " + docs + "/new", cwd: home, home: home)))")
    check(ArisMindShellUndo.plan("mkdir new", cwd: docs, home: home)?.recipe == .fileCreated(path: docs + "/new"), "mind2 shell undo: a relative path, resolved in the call's folder")
    check(ArisMindShellUndo.plan("mv " + docs + "/a.txt " + docs + "/c.txt", cwd: home, home: home)?.recipe == .fileMoved(original: docs + "/a.txt", current: docs + "/c.txt"),
          "mind2 shell undo: a rename")
    check(ArisMindShellUndo.plan("mv " + docs + "/a.txt " + docs + "/box", cwd: home, home: home)?.recipe == .fileMoved(original: docs + "/a.txt", current: docs + "/box/a.txt"),
          "mind2 shell undo: a move into a folder")
    check(ArisMindShellUndo.plan("cp " + docs + "/a.txt " + docs + "/copy.txt", cwd: home, home: home)?.recipe == .fileCreated(path: docs + "/copy.txt"),
          "mind2 shell undo: a copy to a new name")
    let none = ["mv " + docs + "/a.txt " + docs + "/b.txt",            // over an existing file
                "cp " + docs + "/box " + docs + "/box2",               // a folder without -R
                "mkdir " + docs + "/x " + docs + "/y",                 // two at once
                "mkdir -p " + docs + "/deep/er",                       // parents made too
                "mv " + docs + "/*.txt " + docs + "/box",              // a glob
                "mv $HOME/a " + docs + "/z",                           // a variable
                "mkdir " + docs + "/n; rm -rf " + docs,                // two commands
                "mv -f " + docs + "/a.txt " + docs + "/d.txt",         // a flag it doesn't know
                "mv " + docs + "/missing " + docs + "/m",              // nothing to move
                "mkdir /tmp/outside-home",                             // outside the home folder
                "mv '" + docs + "/a.txt' " + docs + "/q.txt"]          // quoting
    for command in none where ArisMindShellUndo.plan(command, cwd: home, home: home) != nil {
        check(false, "mind2 shell undo: no recipe for \(command)")
    }
    // Through the executor: recorded once the disk shows it happened; not when it didn't.
    var executor = ArisMindExecutor(tools: mind2Tools, environment: [:], home: home, runTools: { _, _ in .printed("") },
                                    shell: { line, _, _ in
                                        if line.hasPrefix("mv ") {
                                            let words = line.split(separator: " ").map(String.init)
                                            try? FileManager.default.moveItem(atPath: words[1], toPath: words[2])
                                        }
                                        return .printed("")
                                    }, store: ArisUndoStore(folder: URL(fileURLWithPath: home + "/undo-store")))
    executor.hooks = ArisMindUndoHooks(volume: { nil }, setVolume: { _ in })
    let shell = ArisCapabilityBook.entry(named: "shell_run")!
    let moved = executor.run(shell, arguments: ["command": "mv " + docs + "/a.txt " + docs + "/e.txt"], argv: nil, stdin: nil, caller: ArisUndoCaller(session: "s", provenance: .ownerSaid))
    check(moved.undo == .fileMoved(original: docs + "/a.txt", current: docs + "/e.txt"), "mind2 shell undo: the move's undo is in its result")
    let mkdir = executor.run(shell, arguments: ["command": "mkdir " + docs + "/never-made"], argv: nil, stdin: nil, caller: ArisUndoCaller(session: "s", provenance: .ownerSaid))
    check(mkdir.undo == nil, "mind2 shell undo: a command that didn't do it records no undo")
}

// MARK: - Unanswered is not "no"

private func mind2UnansweredTests() {
    func run(_ answer: Bool?) -> (allowed: Set<String>, entry: ArisRecordEntry?, pass: String?) {
        let home = mind2Home()
        let gate = ArisTrustGate(home: home, world: { _ in ArisWorldFacts(home: home) })
        let judge = ArisMindJudge(gate: gate, tools: mind2Tools, passes: ArisMindPasses())
        judge.cardWait = 1
        judge.turn(session: "u", intent: "t", words: "문서 폴더 정리해 줘")
        let decided = judge.decide(session: "u", task: nil, calls: [mind2Call("d1", "shell_run", ["command": "truncate -s 0 " + home + "/Documents/a.log"])])
        let allowed = judge.ask(session: "u", task: nil, intent: "t", waiting: decided) { _, done in if let answer { done(answer) } }
        let entry = ArisRecordJournal.entries(home: home).last { $0.capability == "shell.run" }
        return (allowed, entry, judge.pass(session: "u", call: "d1"))
    }
    let timedOut = run(nil)
    let no = run(false)
    check(timedOut.allowed.isEmpty && no.allowed.isEmpty && timedOut.pass == nil, "mind2 unanswered: a card that timed out runs nothing, exactly like a no")
    check(timedOut.entry?.answer == "unanswered" && no.entry?.answer == "no", "mind2 unanswered: recorded as unanswered, not as his no (\(timedOut.entry?.answer ?? "-"), \(no.entry?.answer ?? "-"))")
    check(timedOut.entry?.ok == false && timedOut.entry?.decision == no.entry?.decision, "mind2 unanswered: the same decision and outcome as a no")
    // The app's own card answer: `unanswered` with no yes.
    let home = mind2Home()
    let gate = ArisTrustGate(home: home, world: { _ in ArisWorldFacts(home: home) })
    gate.ownerTurn(session: "g", text: "정리해 줘")
    let entry = ArisCapabilityBook.entry(named: "shell_run")!
    let command = "truncate -s 0 " + home + "/Documents/b.log"
    let outcome = gate.decide(session: "g", call: "x1", capability: entry.id, effect: entry.effect(["command": command]), arguments: ["command": command])
    let cards = gate.cards(session: "g", intent: "i", outcomes: [("x1", outcome)]).cards
    let answered = gate.answer(cards.first?.id ?? "", allow: true, unanswered: true)
    check(answered.run == ["x1"], "mind2 unanswered: a yes is a yes, whatever else the card says")
    let second = gate.decide(session: "g", call: "x2", capability: entry.id, effect: entry.effect(["command": command + "2"]), arguments: ["command": command + "2"])
    let card2 = gate.cards(session: "g", intent: "i2", outcomes: [("x2", second)]).cards
    let quiet = gate.answer(card2.first?.id ?? "", allow: false, unanswered: true)
    check(quiet.run.isEmpty && quiet.refused == ["x2"] && ArisRecordJournal.entries(home: home).last?.answer == "unanswered",
          "mind2 unanswered: the app's timed-out card refuses its call and is recorded as unanswered")
}

// MARK: - The undo acts only where its paths still lead, and a to-do's grant only for its own write

private func mind2UndoSecurityTests() {
    let fm = FileManager.default
    let home = mind2Home()
    let docs = home + "/Documents"
    let sub = docs + "/sub"
    try? fm.createDirectory(atPath: sub, withIntermediateDirectories: true)
    try? Data("mine".utf8).write(to: URL(fileURLWithPath: sub + "/a.txt"))
    let other = mind2Home() + "/Documents"
    try? Data("theirs".utf8).write(to: URL(fileURLWithPath: other + "/b.txt"))
    let store = ArisUndoStore(folder: URL(fileURLWithPath: home + "/undo-store"))
    guard let plan = ArisMindShellUndo.plan("mv " + sub + "/a.txt " + sub + "/b.txt", cwd: home, home: home) else {
        return check(false, "mind2 undo security: the rename has a plan")
    }
    try? fm.moveItem(atPath: sub + "/a.txt", toPath: sub + "/b.txt")
    guard let recipe = ArisMindShellUndo.confirmed(plan) else { return check(false, "mind2 undo security: the rename is confirmed") }
    // A parent swapped for a link to another folder after the command: the undo is refused and touches nothing there.
    try? fm.moveItem(atPath: sub, toPath: docs + "/sub-old")
    try? fm.createSymbolicLink(atPath: sub, withDestinationPath: other)
    let refused = (try? ArisUndoRecipes.perform(recipe, home: home, store: store, hands: ArisUndoHands(trash: { _ in })))
    check(refused == nil && (try? String(contentsOfFile: other + "/b.txt", encoding: .utf8)) == "theirs" && !fm.fileExists(atPath: other + "/a.txt"),
          "mind2 undo security: a folder swapped for a link refuses the undo, and the other folder is untouched")
    var trashed: [String] = []
    let made = (try? ArisUndoRecipes.perform(.fileCreated(path: sub + "/b.txt"), home: home, store: store, hands: ArisUndoHands(trash: { trashed.append($0) })))
    check(made == nil && trashed.isEmpty, "mind2 undo security: nothing is trashed through a swapped folder")
    // Put back as it was, the same undo works.
    try? fm.removeItem(atPath: sub)
    try? fm.moveItem(atPath: docs + "/sub-old", toPath: sub)
    let done = (try? ArisUndoRecipes.perform(recipe, home: home, store: store, hands: ArisUndoHands(trash: { _ in })))
    check(done != nil && fm.fileExists(atPath: sub + "/a.txt"), "mind2 undo security: with every folder as it was, the move is taken back")
    // A link already on the way: no recipe at all.
    try? fm.createSymbolicLink(atPath: docs + "/link", withDestinationPath: other)
    check(ArisMindShellUndo.plan("mkdir " + docs + "/link/new", cwd: home, home: home) == nil
          && ArisMindShellUndo.plan("mv " + sub + "/a.txt " + docs + "/link", cwd: home, home: home) == nil,
          "mind2 undo security: a path through a link gets no recipe")
    // The to-do's undo grant: only for exactly its own write, once.
    let grants = ArisActionGrants()
    let mine = ArisMindItemUndo.todoUndoKey("R-A")
    check(mine == ArisActionGrant.key(todo: ["op": "remove", "id": "R-A"]), "mind2 undo security: the grant's key is the app's key for that very removal")
    let grant = grants.mintUndo(exactly: mine)
    check(grant != nil && !grants.consume(ArisMindItemUndo.todoUndoKey("R-B")) && !grants.consume("todo|remove|id=") && !grants.consume("todo|reopen|id=R-A"),
          "mind2 undo security: with A's grant out, a request for B (or with no id) gets nothing")
    check(grants.consume(mine) && !grants.consume(mine), "mind2 undo security: A's grant is single-use")
    check(grants.mintUndo(exactly: "todo|add|text=x") == nil, "mind2 undo security: only an undo write can have such a grant")
    let dropped = grants.mintUndo(exactly: mine)
    grants.dropUndo(dropped)
    check(!grants.consume(mine), "mind2 undo security: a grant dropped when its run returned opens nothing")
}

// MARK: - Who spoke the turn (F1) reaches Core 2's gate and the undo's caller

private func mind2VoiceTests() {
    // The app's field, as the helper takes it: only from the app, anything missing or unknown is "not checked".
    let voices = ArisTurnVoices()
    let a = NSObject(), b = NSObject(), c = NSObject(), d = NSObject()
    voices.received(a, raw: "unverified", fromApp: true)
    voices.received(b, raw: nil, fromApp: true)
    voices.received(c, raw: "nonsense", fromApp: true)
    voices.received(d, raw: "unverified", fromApp: false)
    check(voices.take(a) == .unverified && voices.take(a) == .notChecked && voices.take(b) == .notChecked && voices.take(c) == .notChecked
          && voices.take(d) == .notChecked && voices.take(nil) == .notChecked,
          "mind2 voice: the app's verdict reaches the turn once; missing, unknown or from another caller is not checked")
    // An unverified turn's outward call asks; the same words not checked go as before.
    func send(_ speaker: ArisTurnSpeaker?) -> ArisDecision {
        let home = mind2Home()
        let gate = ArisTrustGate(home: home, world: { _ in ArisWorldFacts(contacts: [.init(name: "엄마", addresses: ["mom@example.com"])], home: home) })
        let judge = ArisMindJudge(gate: gate, tools: mind2Tools, passes: ArisMindPasses())
        if let speaker { judge.turn(session: "v", intent: "t", words: "엄마한테 곧 도착 이라고 보내 줘", speaker: speaker) }
        else { judge.turn(session: "v", intent: "t", words: "엄마한테 곧 도착 이라고 보내 줘") }
        let arguments: [String: Any] = ["to": "엄마", "text": "곧 도착"]
        let found = ArisHandsFace.call(function: "send_message", input: arguments, tools: mind2Tools)!
        return gate.decide(session: "v", call: "m", capability: found.entry.id, effect: found.entry.effect(arguments), arguments: arguments, argv: found.argv).decision
    }
    let absent = send(nil), notChecked = send(.notChecked), unverified = send(.unverified)
    check(absent == notChecked, "mind2 voice: with no voice field the decision is exactly as before (\(absent))")
    if case .sayThenRun = notChecked {} else { check(false, "mind2 voice: the owner's dictated send is said first, then sent: \(notChecked)") }
    check(unverified.waitsForOwner && unverified != notChecked, "mind2 voice: an unverified voice's send asks (\(unverified))")
    // The undo's caller carries the speaker: an unverified voice's 되돌려 reaches only its own session's entries.
    let home = mind2Home()
    let gate = ArisTrustGate(home: home, world: { _ in ArisWorldFacts(home: home) })
    let judge = ArisMindJudge(gate: gate, tools: mind2Tools, passes: ArisMindPasses())
    let file = home + "/Documents/made.txt"
    judge.turn(session: "A", intent: "A1", words: "문서 폴더에 made.txt 만들어")
    let write = judge.decide(session: "A", task: nil, calls: [mind2Call("w1", "write_file", ["path": file, "text": "x"])])
    let executor = ArisMindExecutor(tools: mind2Tools, environment: [:], home: home, runTools: { _, _ in .printed("") }, shell: { _, _, _ in .printed("") },
                                    store: ArisUndoStore(folder: URL(fileURLWithPath: home + "/undo-store")))
    if case .success(let read) = judge.read(write[0].call) {
        let result = executor.run(read.entry, arguments: read.arguments, argv: read.argv, stdin: read.stdin, caller: judge.caller(session: "A", task: nil, call: "w1"))
        judge.finish(session: "A", item: write[0], result: result, disposition: .ran)
    }
    check(ArisRecordJournal.entries(home: home).last?.undo == .fileCreated(path: file), "mind2 voice: the file made in conversation A has its undo")
    func undo(_ speaker: ArisTurnSpeaker, session: String) -> (verdict: ArisMindVerdict, caller: ArisUndoCaller) {
        judge.turn(session: session, intent: session + "1", words: "방금 만든 거 되돌려", speaker: speaker)
        let decided = judge.decide(session: session, task: nil, calls: [mind2Call("u-" + session, "undo_last", [:])])
        return (decided[0].verdict, judge.caller(session: session, task: nil, call: "u-" + session))
    }
    let other = undo(.unverified, session: "B")
    check(other.caller.speaker == .unverified && !other.caller.ownerSaid, "mind2 voice: the undo's caller is the unverified voice's")
    if case .refuse = other.verdict {} else { check(false, "mind2 voice: an unverified voice's undo can't reach conversation A's entry: \(other.verdict)") }
    let owner = undo(.notChecked, session: "C")
    if case .refuse = owner.verdict { check(false, "mind2 voice: the owner's own 되돌려 (not checked) still reaches it, as before") }
}

// MARK: - record.query through the Mind

private func mind2RecordQueryTests() {
    let saved = ArisCore2.isOn
    ArisCore2.isOn = { true }
    defer { ArisCore2.isOn = saved }
    let rig = Mind2BrainRig()
    rig.words = "오늘 뭐 했어?"
    check(ArisCapabilityBook.entry(id: "record.query").map { $0.effect([:]) } == .observe, "mind2 record.query: it is an observe call in the book")
    let brain = rig.brain(Mind2Scripted([([], [mind2Call("q1", "record_query", ["from": "today"])]), (["오늘은 아무것도 안 했어요"], [])]))
    let end = brain.turn(rig.words, tier: .quick, task: false, context: "")
    let line = rig.record.last { $0.capability == "record.query" }
    check(end == .answered("오늘은 아무것도 안 했어요") && rig.cards.isEmpty && line?.decision == "run" && line?.ok == true,
          "mind2 record.query: runs through the Mind with the switch on, no card, one line of the record (\(String(describing: line?.decision)))")
    let read = brain.conversation.compactMap { message -> String? in if case .tool(_, "record_query", let text, false) = message { return text } else { return nil } }
    check(read.count == 1, "mind2 record.query: its answer goes back to the model")
}

// MARK: - One World for the trust gate: the focus over the app's wire

private func mind2FocusWorldTests() {
    let wire = ArisWorldFacts(contacts: [.init(name: "엄마", addresses: ["mom@example.com"])], apps: ["Safari": ["사파리"]], frontApp: "Notes", home: "/Users/p")
    let mail = ArisFocusObject(source: ArisContentSource(kind: "mail", source: "boss@corp.example"), sender: "boss@corp.example")
    let merged = ArisMindWorld.facts(wire, focus: ArisWorldFacts(frontApp: "Mail", focus: mail))
    check(merged.focus == mail && merged.frontApp == "Mail" && merged.contacts == wire.contacts && merged.apps["Safari"] == ["사파리"],
          "mind2 world: the focus and its app lie over the app's contacts and nicknames, nothing of either lost")
    check(ArisMindWorld.facts(wire, focus: ArisWorldFacts()) == wire, "mind2 world: no fresh focus, the wire's facts as they are")
    // The live facts read the focus desk: with nothing kept there, no focus.
    check(ArisMindLive.facts(home: "/Users/p", focus: ArisFocusDesk()).focus == nil, "mind2 world: an empty focus desk adds no focus")
}
