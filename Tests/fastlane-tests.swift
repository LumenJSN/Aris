// jv-fastlane: the helper's first reply token leaves as early as the brain allows. A quick turn thinks at low (one
// table, ArisThinking.efforts), Claude switches effort per turn in the same process, a warm spare stands beside each
// conversation runner (ArisFastLane), and a Claude Code update that adds a tool costs one relaunch instead of every turn
// (ArisClaudeInit). Fakes only: no process is started here.
import Foundation

func runFastLaneTests() {
    fastLaneEffortTableTests()
    fastLaneClaudeEffortTests()
    fastLaneInitTests()
    fastLanePolicyTests()
    fastLaneSwapTests()
    fastLaneClockTests()
}

// MARK: - The effort table

private func fastLaneEffortTableTests() {
    typealias T = ArisThinking
    check(T.effort(.quick) == T.Effort(claude: "low", codex: "low", why: T.efforts[.quick]!.why) && T.effort(.work).claude == "medium"
          && T.effort(.work).codex == "medium" && T.effort(.deep).claude == "high" && T.effort(.critical).codex == "high",
          "effort table: quick at low, work at medium, a look-up or careful turn at high")
    check([ArisTier.quick, .work, .deep, .critical].allSatisfy { T.efforts[$0] != nil && !(T.efforts[$0]?.why.isEmpty ?? true) },
          "effort table: every tier has a row and a reason")
    check(T.claudeEffort(model: "sonnet") == "low" && T.claudeEffort(model: "opus") == "high" && T.claudeEffort(model: "opus", tier: .quick) == "high"
          && T.claudeEffort(model: "haiku", tier: .work) == "low",
          "effort table: a Sonnet process starts at a quick turn's effort; Opus stays high, Haiku low")
    let codex = ArisCodexDriver(model: "m", tools: "/t", instructions: "i")
    let threadRequest = codex.opening().map(jsonLine).last?["id"] as? Int ?? -1
    _ = codex.read(#"{"id":\#(threadRequest),"result":{"thread":{"id":"T1"}}}"#)
    let quick = (jsonLine(codex.ask("x", tier: .quick)[0])["params"] as? [String: Any])?["effort"] as? String
    let work = (jsonLine(codex.ask("x", tier: .work)[0])["params"] as? [String: Any])?["effort"] as? String
    check(quick == "low" && work == "medium", "effort table: Codex's turn/start carries the tier's effort")
}

// MARK: - Claude: effort per turn in one process

private func fastLaneClaudeEffortTests() {
    func control(_ line: Data) -> String? {
        let object = jsonLine(line)
        guard object["type"] as? String == "control_request", let request = object["request"] as? [String: Any],
              request["subtype"] as? String == "apply_flag_settings" else { return nil }
        return (request["settings"] as? [String: Any])?["effortLevel"] as? String
    }
    let claude = ArisClaudeDriver(model: "sonnet", tools: "/t")
    let args = claude.arguments
    let launched = args.firstIndex(of: "--effort").map { args[$0 + 1] }
    check(launched == "low", "claude effort: a Sonnet process starts at low")
    let first = claude.ask("q", tier: .quick)
    check(first.count == 1 && control(first[0]) == nil && jsonLine(first[0])["type"] as? String == "user",
          "claude effort: a quick turn on a low process sends only the question")
    let work = claude.ask("q", tier: .work)
    check(work.count == 2 && control(work[0]) == "medium" && jsonLine(work[1])["type"] as? String == "user",
          "claude effort: a work turn first sets medium, then asks")
    check(claude.ask("q", tier: .work).count == 1, "claude effort: a second work turn sends nothing more")
    let back = claude.ask("q", tier: .quick)
    check(back.count == 2 && control(back[0]) == "low", "claude effort: back to low for the next quick turn")
    let ids = [work[0], back[0]].compactMap { (jsonLine($0)["request_id"] as? String) }
    check(Set(ids).count == 2, "claude effort: each request has its own id")
    claude.reset()
    check(claude.ask("q", tier: .quick).count == 1, "claude effort: a new process starts at its launch effort again")
    let opus = ArisClaudeDriver(model: "opus", tools: "/t", task: true)
    check(opus.ask("q", tier: .deep).count == 1 && opus.ask("q", tier: .critical).count == 1, "claude effort: Opus stays at high")
    let images = ArisClaudeDriver(model: "sonnet", tools: "/t", sealed: true).ask("q", images: [], tier: .work)
    check(images.count == 2 && control(images[0]) == "medium", "claude effort: the sealed Claude's turns switch too")
    check(ArisClaudeDriver.quietKinds.contains("control_response")
          && claude.read(#"{"type":"control_response","response":{"subtype":"success","request_id":"aris-effort-1"}}"#).isEmpty,
          "claude effort: the control answer is a known quiet line")
}

// MARK: - The init check (ArisClaudeInit)

private func fastLaneInitTests() {
    typealias I = ArisClaudeInit
    let open: Set<String> = ["Bash", "Read", "WebFetch", "WebSearch"]
    check(I.verdict(listed: ["Bash", "Read", "WebFetch", "WebSearch"], servers: [], expected: open) == .ok, "init: exactly the tools, no server")
    check(I.verdict(listed: ["Bash", "Read", "WebFetch", "WebSearch", "Monitor"], servers: [], expected: open) == .relaunch(extra: ["Monitor"]),
          "init: an extra built-in tool asks for a relaunch with it denied")
    check(I.verdict(listed: ["Bash", "Read", "WebFetch"], servers: [], expected: open) == .refused, "init: a missing tool still stops it")
    check(I.verdict(listed: ["Bash", "Read", "WebFetch", "WebSearch"], servers: [["name": "x"]], expected: open) == .refused
          && I.verdict(listed: ["Bash", "Read", "WebFetch", "WebSearch", "Monitor"], servers: [["name": "x"]], expected: open) == .refused,
          "init: any MCP server still stops it")
    check(I.verdict(listed: ["Bash", "Read", "WebFetch", "WebSearch", "mcp__x__y"], servers: [], expected: open) == .refused
          && I.verdict(listed: ["Bash", "Read", "WebFetch", "WebSearch", "Bash(rm:*)"], servers: [], expected: open) == .refused
          && I.verdict(listed: ["Bash", "Read", "WebFetch", "WebSearch", "lower"], servers: [], expected: open) == .refused,
          "init: an MCP tool, a rule or an odd name is never learned: it stops")
    check(I.verdict(listed: nil, servers: [], expected: open) == .refused && I.verdict(listed: ["Bash"], servers: nil, expected: ["Bash"]) == .refused
          && I.verdict(listed: ["Bash", "Bash", "Read", "WebFetch", "WebSearch"], servers: [], expected: open) == .refused,
          "init: no list, no server list or a doubled name stops it")
    let many = (1...9).map { "Tool\($0)" }
    check(I.verdict(listed: Array(open) + many, servers: [], expected: open) == .refused, "init: many new tools at once is no update: it stops")

    // The driver: still stopped on the extra tool (it never answers), and hands the names to the runner once.
    func isAbort(_ events: [ArisBrainEvent]) -> Bool { events.contains { if case .abort = $0 { return true } else { return false } } }
    let driver = ArisClaudeDriver(model: "sonnet", tools: "/t")
    check(isAbort(driver.read(#"{"type":"system","subtype":"init","tools":["Bash","Read","WebFetch","WebSearch","Monitor"],"mcp_servers":[]}"#))
          && driver.takeRelaunch() == ["Monitor"] && driver.takeRelaunch() == nil,
          "init: the process with the extra tool is stopped, and the runner is told to relaunch once")
    check(isAbort(driver.read(#"{"type":"result","subtype":"success","result":"x"}"#)), "init: that process still answers nothing")
    let server = ArisClaudeDriver(model: "sonnet", tools: "/t")
    check(isAbort(server.read(#"{"type":"system","subtype":"init","tools":["Bash","Read","WebFetch","WebSearch","Monitor"],"mcp_servers":[{"name":"x"}]}"#))
          && server.takeRelaunch() == nil, "init: with an MCP server there is no relaunch")

    // What is learned is denied by name in the next process (a bare deny takes the tool out: checked live), never a
    // tool that Claude is given.
    let drift = ArisClaudeToolDrift.shared
    drift.forget()
    check(drift.learn(["Monitor"]) && !drift.learn(["mcp__a"]) && !drift.learn(many) && !drift.learn([]), "drift: only plain names, a few at a time")
    _ = drift.learn(["Read"])
    func denied(_ claude: ArisClaudeDriver) -> [String] {
        let args = claude.arguments
        guard let start = args.firstIndex(of: "--disallowedTools"), let end = args.firstIndex(of: "--system-prompt") else { return [] }
        return Array(args[(start + 1)..<end])
    }
    let openNext = ArisClaudeDriver(model: "sonnet", tools: "/t"), sealedNext = ArisClaudeDriver(model: "sonnet", tools: "/t", sealed: true)
    check(denied(openNext).contains("Monitor") && !denied(openNext).contains("Read") && denied(sealedNext).contains("Monitor") && denied(sealedNext).contains("Read"),
          "drift: the next process denies the new tool by name; the open Claude keeps its own Read")
    check(openNext.read(#"{"type":"system","subtype":"init","tools":["Bash","Read","WebFetch","WebSearch"],"mcp_servers":[]}"#).isEmpty,
          "drift: that process's init (the tool gone) passes as exact")
    drift.forget()
    check(!denied(ArisClaudeDriver(model: "sonnet", tools: "/t")).contains("Monitor"), "drift: nothing learned, nothing denied")
}

// MARK: - The spare policy

private func fastLanePolicyTests() {
    typealias F = ArisFastLane
    let ready = ArisSpareState(alive: true, busy: false, asked: false)
    let used = ArisSpareState(alive: true, busy: false, asked: true)
    let gone = ArisSpareState(alive: false, busy: false, asked: false)
    let busy = ArisSpareState(alive: true, busy: true, asked: true)
    check(F.swapsOnFresh(current: used, spare: ready, inProcess: false) && !F.swapsOnFresh(current: used, spare: ready, inProcess: true),
          "spare: a used conversation starting over takes the spare, unless its brain opens a new thread in process (Codex)")
    check(F.swapsOnFresh(current: gone, spare: ready, inProcess: true) && F.swapsOnFresh(current: nil, spare: ready, inProcess: false),
          "spare: a conversation with no process takes it on any brain")
    check(!F.swapsOnFresh(current: busy, spare: ready, inProcess: false) && !F.swapsOnFresh(current: ready, spare: ready, inProcess: false),
          "spare: never while a turn is under way, and a started process never asked has nothing to forget")
    check(!F.swapsOnFresh(current: used, spare: gone, inProcess: false) && !F.swapsOnFresh(current: used, spare: used, inProcess: false)
          && !F.swapsOnFresh(current: used, spare: nil, inProcess: false),
          "spare: a dead, used or missing spare is never swapped in")
    check(F.swapsOnAsk(current: gone, spare: ready) && !F.swapsOnAsk(current: used, spare: ready) && !F.swapsOnAsk(current: gone, spare: gone)
          && !F.swapsOnAsk(current: ArisSpareState(alive: false, busy: true, asked: false), spare: ready),
          "spare: a question finds the spare only when its runner lost its process and is idle")
    check(F.needsSpare(nil) && F.needsSpare(gone) && F.needsSpare(used) && !F.needsSpare(ready), "spare: a missing, dead or used spare is replaced")
    check(F.keepsSpare(.claude) && F.keepsSpare(.codex) && F.keepsSpare(.antigravity) && !F.keepsSpare(.api),
          "spare: every brain that takes seconds to start keeps one; the API brain doesn't")
    check(F.startsOverInProcess(.codex) && !F.startsOverInProcess(.claude) && !F.startsOverInProcess(.antigravity)
          && (ArisClaudeDriver(model: "m", tools: "/t").newConversation() == nil)
          && ArisCodexDriver(model: "m", tools: "/t", instructions: "i").newConversation() != nil,
          "spare: the in-process list matches the drivers (Codex opens a thread, Claude can't)")
}

// MARK: - The swap, with fake runners

private final class FakeRunner {
    var state = ArisSpareState()
    var coldStarts = 0
    var stopped = false
    let number: Int
    init(_ number: Int) { self.number = number }
    func warm() { if !state.alive { state.alive = true } }
    /// A question: a runner with no process starts one first (the cold start this all avoids).
    func ask() {
        if !state.alive { coldStarts += 1; state.alive = true }
        state.asked = true
    }
}

private func fastLaneSwapTests() {
    var pool = ArisSparePool<FakeRunner>()
    let slot = "n/claude/sonnet"
    var made: [FakeRunner] = []
    func keep() -> (made: FakeRunner?, dropped: FakeRunner?) {
        let kept = pool.keep(slot, brain: .claude, model: "sonnet", state: { $0.state }) { number in
            let runner = FakeRunner(number)
            made.append(runner)
            return runner
        }
        kept.dropped?.stopped = true
        kept.made?.warm()
        return kept
    }
    // /warm: the runner and its spare.
    var current = FakeRunner(0)
    current.warm()
    check(keep().made != nil && keep().made == nil && pool.made == 1, "swap: /warm starts one spare per brain and model, once")
    current.ask()
    // "fresh": the spare takes over; no cold start; the next spare starts.
    func fresh() -> Bool {
        guard let spare = pool.swap(slot, current: current, fresh: true, state: { $0.state }) else { return false }
        current.stopped = true
        current = spare
        _ = keep()
        return true
    }
    let before = current
    check(fresh() && before.stopped && current !== before && pool.spare(slot) != nil && pool.spare(slot) !== current,
          "swap: a new conversation takes the warm spare, stops the old process and starts the next spare")
    current.ask()
    check(current.coldStarts == 0, "swap: the question after a fresh start takes no cold start")
    check(fresh() && pool.made == 3, "swap: and again on the next fresh start, the spare replaced each time")
    // The idle stop: the spare's own idle timer stops it like any runner; a dead spare is never swapped in, and the next
    // keep replaces it (the old one handed back to be stopped).
    pool.spare(slot)!.state.alive = false
    current.ask()
    check(!fresh() && current.state.asked, "swap: an idle-stopped spare is never swapped in (today's path: the runner starts over)")
    let idle = pool.spare(slot)!
    let replaced = keep()
    check(replaced.made != nil && replaced.dropped === idle && idle.stopped && pool.spare(slot)!.state.alive, "swap: /warm replaces an idle-stopped spare")
    // A spare's process crashes: never used, replaced on the next keep, never in a loop by itself.
    let crashed = pool.spare(slot)!
    crashed.state.alive = false
    let count = pool.made
    check(pool.swap(slot, current: current, fresh: false, state: { $0.state }) == nil && pool.made == count, "swap: a crashed spare is left until the next keep")
    check(keep().dropped === crashed && pool.made == count + 1, "swap: the next keep replaces the crashed spare")
    // The current runner lost its process (a crash, a time limit, the idle stop): the next question takes the spare.
    current.state.alive = false
    current.state.asked = false
    if let spare = pool.swap(slot, current: current, fresh: false, state: { $0.state }) { current = spare; _ = keep() }
    current.ask()
    check(current.coldStarts == 0 && current.state.alive, "swap: after a lost process the question goes to the warm spare, not a cold start")
    // Busy: a turn under way keeps its runner.
    current.state.busy = true
    check(pool.swap(slot, current: current, fresh: true, state: { $0.state }) == nil, "swap: never while a turn is under way")
    // A retired brain: its spares go and are handed back to be stopped; nothing is kept for its slots.
    let retired = pool.remove(brain: .claude)
    check(retired.count == 1 && pool.spare(slot) == nil && pool.lane(slot) == nil, "swap: retiring a brain takes its spare away")
    check(made.count == pool.made, "swap: every spare made was counted")
}

// MARK: - The turn's timing line

private func fastLaneClockTests() {
    let t0 = Date(timeIntervalSince1970: 1_000)
    var clock = ArisTurnClock(received: t0, started: t0.addingTimeInterval(0.002), warm: true, effort: "low")
    clock.line(at: t0.addingTimeInterval(0.001))
    clock.wrote(at: t0.addingTimeInterval(0.004))
    clock.wrote(at: t0.addingTimeInterval(0.009))
    clock.line(at: t0.addingTimeInterval(0.020))
    clock.delta(at: t0.addingTimeInterval(0.510))
    clock.delta(at: t0.addingTimeInterval(0.600))
    let line = clock.answered(at: t0.addingTimeInterval(0.900), brain: "claude", model: "sonnet")
    check(line == "turn timing claude/sonnet effort low warm: written 4 ms, first line 20 ms, first text 510 ms, answer 900 ms (from the request)",
          "timing: one line with each stage from the request, the first of each only (a cold start's own lines don't count)")
    check(clock.answered(brain: "claude", model: "sonnet") == nil, "timing: logged once per turn")
    var cold = ArisTurnClock(received: nil, warm: false, effort: "medium")
    check(cold.answered(brain: "codex", model: "m")?.contains("cold: written -, first line -, first text -") == true,
          "timing: a stage that never came is a dash; no request time is the turn's start")
    let owner = NSObject()
    ArisTurnArrivals.shared.received(owner, at: t0)
    check(ArisTurnArrivals.shared.take(owner) == t0 && ArisTurnArrivals.shared.take(owner) == nil && ArisTurnArrivals.shared.take(nil) == nil,
          "timing: the request's arrival is taken once by its turn")
}
