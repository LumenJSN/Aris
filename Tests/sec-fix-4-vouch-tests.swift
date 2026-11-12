// Tests for security review 4, M2: the helper vouches for its own children (ArisOrigin+Vouch, ArisChildren,
// ArisVouchService). A tool that macOS charges to Aris runs only when the real helper says it started that tool or
// one of its parents; who the tool's parents are is never taken from the tool.
// The walk runs over process tables written here from the shapes that were measured (qa/design-1111/one-row-experiment.md,
// U1–U6); one test asks a listener of its own on a free loopback port, with a made-up token and a /bin/bash child.
// Called from runSecFix4Tests(); uses main.swift's check().
import Foundation

func secFix4VouchTests() {
    secFix4WalkTests()
    secFix4WireTests()
    secFix4DecisionTests()
    secFix4SpawnPlaceTests()
    secFix4RoundTripTests()
}

private let vouchRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("..")
private func vouchCode(_ path: String) -> String {
    ((try? String(contentsOf: vouchRoot.appendingPathComponent(path), encoding: .utf8)) ?? "").components(separatedBy: "\n")
        .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
}

// MARK: - The walk, over recorded shapes

private func secFix4WalkTests() {
    typealias O = ArisOrigin
    typealias L = O.Live
    let helper: pid_t = 500
    /// The helper started at 1000; `recorded` is its own list (pid: start time).
    func found(_ pid: pid_t, _ table: [pid_t: L], recorded: [pid_t: UInt64]) -> pid_t? {
        var all = table
        all[helper] = all[helper] ?? L(parent: 1, started: 1_000)
        return O.recordedAncestor(of: pid, helper: helper, live: { all[$0] }, recorded: { recorded[$0] == $1 })
    }
    // Every chain Aris really makes today (each is a start through ArisChildren in the helper, then the program's own
    // children). The first three are the ones the VM run of the inherited commit saw working.
    let chains: [(String, [pid_t: L], [pid_t: UInt64], pid_t)] = [
        ("helper → aris-tools for a look (its own calls: look, cards, the activity log, permission checks; seen working in the VM at 43428e42)",
         [900: L(parent: 500, started: 2_000)], [900: 2_000], 900),
        ("helper → the AI's command-line program → zsh → aris-tools (Claude Code's Bash tool and its hook; seen working in the VM at 43428e42)",
         [800: L(parent: 500, started: 2_000), 810: L(parent: 800, started: 2_100), 900: L(parent: 810, started: 2_200)], [800: 2_000], 800),
        ("a scheduled job with the app closed: the helper's own timer starts the AI program as in any turn (seen working in the VM at 43428e42)",
         [760: L(parent: 500, started: 86_400_000), 761: L(parent: 760, started: 86_400_100), 900: L(parent: 761, started: 86_400_200)], [760: 86_400_000], 760),
        ("helper → codex app-server → its shell → aris-tools",
         [700: L(parent: 500, started: 2_000), 710: L(parent: 700, started: 2_050), 711: L(parent: 710, started: 2_060), 900: L(parent: 711, started: 2_070)], [700: 2_000], 700),
        ("helper → zsh -lc (finding the AI programs, agy) → aris-tools",
         [830: L(parent: 500, started: 2_000), 900: L(parent: 830, started: 2_010)], [830: 2_000], 830),
        ("helper → agy → aris-tools",
         [840: L(parent: 500, started: 2_000), 900: L(parent: 840, started: 2_500)], [840: 2_000], 840),
        ("helper → aris-agent api-brain (the API helper asks for itself)",
         [720: L(parent: 500, started: 2_000)], [720: 2_000], 720),
        ("helper → aris-agent api-brain → aris-tools (the API brain's function calls)",
         [720: L(parent: 500, started: 2_000), 900: L(parent: 720, started: 2_300)], [720: 2_000], 720),
        ("helper → aris-agent --usage-report",
         [730: L(parent: 500, started: 2_000)], [730: 2_000], 730),
        ("helper → a skill's script under sandbox-exec → python → aris-tools",
         [740: L(parent: 500, started: 2_000), 741: L(parent: 740, started: 2_001), 900: L(parent: 741, started: 2_002)], [740: 2_000], 740),
        ("helper → an external service's program (MCP) → aris-tools",
         [750: L(parent: 500, started: 2_000), 900: L(parent: 750, started: 2_900)], [750: 2_000], 750),
        ("a child started in the same microsecond as its parent",
         [800: L(parent: 500, started: 2_000), 900: L(parent: 800, started: 2_000)], [800: 2_000], 800),
    ]
    for (what, table, recorded, expected) in chains {
        check(found(table.keys.max() ?? 0, table, recorded: recorded) == expected, "sec4 M2 chain: \(what) is vouched for")
    }
    // The measured shapes that must not pass.
    check(found(900, [900: L(parent: 500, started: 900)], recorded: [:]) == nil,
          "sec4 M2: a tool a script job started before it became aris-agent (U2: its parent is “the genuine agent”) is not vouched for")
    check(found(900, [850: L(parent: 500, started: 900), 900: L(parent: 850, started: 950)], recorded: [:]) == nil,
          "sec4 M2: nor is a tool under a worker that was forked before the exec (env, sh -c, a #! script)")
    check(found(900, [850: L(parent: 500, started: 900), 900: L(parent: 850, started: 950)], recorded: [800: 2_000]) == nil,
          "sec4 M2: the helper's other children don't vouch for a process that isn't under them")
    check(found(900, [900: L(parent: 1, started: 2_000)], recorded: [800: 1_500]) == nil,
          "sec4 M2: a tool launchd started itself (any job pointed at the file) is not vouched for")
    check(found(900, [860: L(parent: 1, started: 2_100), 900: L(parent: 860, started: 2_200)], recorded: [800: 2_000]) == nil,
          "sec4 M2: a daemonised child (double fork, setsid: its parents no longer lead to the helper) is not vouched for")
    check(found(900, [800: L(parent: 1, started: 9_000), 900: L(parent: 800, started: 9_100)], recorded: [800: 2_000]) == nil,
          "sec4 M2: a later process that was given a recorded child's pid does not pass (another start time)")
    check(found(900, [800: L(parent: 500, started: 9_000), 900: L(parent: 800, started: 5_000)], recorded: [800: 9_000]) == nil,
          "sec4 M2: a “parent” that started after its child is a reused pid, not the parent")
    check(found(900, [:], recorded: [900: 2_000]) == nil, "sec4 M2: a process that is gone is not vouched for")
    check(found(500, [:], recorded: [500: 1_000]) == nil && found(1, [:], recorded: [:]) == nil && found(0, [:], recorded: [:]) == nil,
          "sec4 M2: the helper itself, launchd and pid 0 are never an answer")
    check(found(900, [900: L(parent: 901, started: 2_000), 901: L(parent: 900, started: 2_000)], recorded: [:]) == nil, "sec4 M2: a loop of parents ends")
    var deep: [pid_t: L] = [:]
    for pid in pid_t(600)..<700 { deep[pid] = L(parent: pid == 600 ? 500 : pid - 1, started: UInt64(pid)) }
    check(found(699, deep, recorded: [600: 600]) == nil && found(620, deep, recorded: [600: 600]) == 600,
          "sec4 M2: the walk gives up after \(O.ancestorLimit) parents")
    // The helper's own list.
    ArisChildren.forgetAll()
    ArisChildren.note(4_242, live: { _ in L(parent: getpid(), started: 77) })
    ArisChildren.note(4_243, live: { _ in nil })
    ArisChildren.note(1, live: { _ in L(parent: 0, started: 1) })
    check(ArisChildren.isRecorded(4_242, started: 77) && !ArisChildren.isRecorded(4_242, started: 78) && !ArisChildren.isRecorded(4_243, started: 0)
            && !ArisChildren.isRecorded(1, started: 1),
          "sec4 M2: the helper writes a child down with its start time; one that is already gone, and launchd, are left out")
    ArisChildren.forgetAll()
    check(!ArisChildren.isRecorded(4_242, started: 77) && !ArisChildren.vouches(for: getpid()) && !ArisChildren.vouches(for: getppid()),
          "sec4 M2: with an empty list nothing is vouched for, the asking process's own parents included")
}

// MARK: - The question and the answer

private func secFix4WireTests() {
    typealias O = ArisOrigin
    typealias S = ArisVouchService
    let token = String(repeating: "ab", count: 20), port = O.vouchPort
    func parsed(_ data: Data) -> HTTPRequest? {
        if case .complete(let request) = HTTPRequestParser.parse(data) { return request }
        return nil
    }
    func verdict(_ request: HTTPRequest?, token given: String? = token, holds: Bool = true, vouches: Bool = true) -> S.Verdict {
        guard let request else { return .refused }
        return S.verdict(request, token: given, port: port, holdsConnection: { _ in holds }, vouches: { _ in vouches })
    }
    let question = parsed(O.vouchRequest(pid: 900, token: token))
    check(question?.path == "/vouch" && question.map { O.vouchedPid(body: $0.body) } == 900 && verdict(question) == .answered(true),
          "sec4 M2 wire: the tool's question is a request the helper's parser reads, and a child of the helper's gets a yes")
    check(verdict(question, vouches: false) == .answered(false), "sec4 M2 wire: a process the helper did not start gets a no")
    check(verdict(question, holds: false) == .answered(false), "sec4 M2 wire: a question about a pid that does not hold the asking connection gets a no (the pid is checked, not believed)")
    check(verdict(question, token: nil) == .refused && verdict(question, token: String(repeating: "cd", count: 20)) == .refused
            && verdict(parsed(O.vouchRequest(pid: 900, token: ""))) == .refused,
          "sec4 M2 wire: without Aris's token there is no answer at all")
    func raw(_ head: String, _ body: String) -> HTTPRequest? { parsed(Data((head + "Content-Length: \(body.utf8.count)\r\n\r\n" + body).utf8)) }
    let headers = "Host: 127.0.0.1:\(port)\r\nx-aris-token: \(token)\r\nContent-Type: application/json\r\n"
    check(verdict(raw("POST /vouch HTTP/1.1\r\n" + headers, "{\"pid\":900}")) == .answered(true)
            && verdict(raw("GET /vouch HTTP/1.1\r\n" + headers, "{\"pid\":900}")) == .refused
            && verdict(raw("POST /ask HTTP/1.1\r\n" + headers, "{\"pid\":900}")) == .refused
            && verdict(raw("POST /vouch HTTP/1.1\r\nOrigin: http://evil.example\r\n" + headers, "{\"pid\":900}")) == .refused
            && verdict(raw("POST /vouch HTTP/1.1\r\n" + headers.replacingOccurrences(of: "127.0.0.1:\(port)", with: "evil.example"), "{\"pid\":900}")) == .refused
            && verdict(raw("POST /vouch HTTP/1.1\r\n" + headers.replacingOccurrences(of: "application/json", with: "text/plain"), "{\"pid\":900}")) == .refused,
          "sec4 M2 wire: only a POST of JSON to /vouch on this listener, from no web page, is answered")
    for body in ["{}", "{\"pid\":\"900\"}", "{\"pid\":true}", "{\"pid\":1}", "{\"pid\":0}", "{\"pid\":-5}", "{\"pid\":900.5}", "{\"pid\":99999999999}",
                 "{\"pid\":900,\"parent\":500}", "[900]", "900", ""] {
        check(O.vouchedPid(body: Data(body.utf8)) == nil, "sec4 M2 wire: “\(body)” names no process (and nothing else a tool says about itself is read)")
    }
    let yes = O.vouchResponse(true), no = O.vouchResponse(false)
    check(O.vouchAnswer(yes) == true && O.vouchAnswer(no) == false && O.vouchAnswer(O.vouchRefusal) == false, "sec4 M2 wire: the tool reads the helper's yes, no and refusal")
    check(O.vouchAnswer(yes.prefix(10)) == nil && O.vouchAnswer(yes.dropLast(3)) == nil && O.vouchAnswer(Data()) == nil, "sec4 M2 wire: an answer that has not all arrived is not an answer yet")
    func answer(_ text: String) -> Bool? { O.vouchAnswer(Data(text.utf8)) }
    check(answer("HTTP/1.1 500 Oops\r\nContent-Length: 16\r\n\r\n{\"vouched\":true}") == false
            && answer("HTTP/1.1 200 OK\r\nContent-Length: 13\r\n\r\n{\"vouched\":1}") == false
            && answer("HTTP/1.1 200 OK\r\nContent-Length: 18\r\n\r\n{\"vouched\":\"true\"}") == false
            && answer("HTTP/1.1 200 OK\r\n\r\n{\"vouched\":true}") == false
            && answer("HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\ntrue") == false
            && answer("yes\r\n\r\n") == false && answer(String(repeating: "x", count: O.vouchMaxBytes + 1)) == false,
          "sec4 M2 wire: anything but a whole 200 whose body says vouched: true is a no")
}

// MARK: - What the tool decides from it

private func secFix4DecisionTests() {
    typealias O = ArisOrigin
    let app = "/Applications/Aris.app", agent = app + "/Contents/MacOS/aris-agent", tools = app + "/Contents/MacOS/aris-tools"
    func facts(program: String = tools, job: O.Job? = O.Job(pid: 500, program: agent), answered: Bool = true, signed: Set<pid_t> = [500], vouchedBy: pid_t? = 500) -> O.Facts {
        O.Facts(me: 900, program: program, responsible: 500, responsibleProgram: agent, responsibleIdentity: .aris, job: job, launchdAnswered: answered,
                signedAsAgent: signed, vouchedBy: vouchedBy, looksLikeJob: false)
    }
    check(O.mayRun(facts()) && O.helperBehind(facts(), app: app) == 500, "sec4 M2: a tool the real helper vouched for runs")
    check(!O.mayRun(facts(vouchedBy: nil)), "sec4 M2: with the real helper as its parent but no yes from it, the tool is refused (the pre-forked tool, U2)")
    check(!O.mayRun(facts(vouchedBy: 777)), "sec4 M2: a yes from any process but launchd's job is no yes")
    check(!O.mayRun(facts(signed: [])), "sec4 M2: a yes from a job that is not signed as aris-agent is no yes")
    check(!O.mayRun(facts(job: O.Job(pid: 500, program: "/bin/sh", argument0: "/bin/sh"))) && !O.mayRun(facts(job: O.Job(pid: 500, program: nil, argument0: "/usr/bin/env")))
            && !O.mayRun(facts(job: O.Job(pid: 500, program: "/Users/kim/x.sh", argument0: agent))),
          "sec4 M2: nor from a job launchd started as a shell, env or a script (U2, U3), whatever it says")
    check(!O.mayRun(facts(job: nil, answered: false)) && !O.mayRun(facts(job: nil)), "sec4 M2, L1: with launchd silent, or no job under Aris's label, nothing vouches")
    check(!O.mayRun(facts(job: O.Job(pid: 900, program: agent), signed: [900], vouchedBy: 900)), "sec4 M2: a process never vouches for itself")
    let copy = "/Users/kim/c/Aris.app"
    check(!O.mayRun(facts(program: copy + "/Contents/MacOS/aris-tools")),
          "sec4 M2: the tool of a copy of the app (U1c) is not vouched for by the helper of the installed app: the helper must be this same app's")
    check(!O.mayRun(facts(program: app + "/Contents/Helpers/aris-tools")), "sec4 M1: the tool in Contents/Helpers (U1) never runs, vouched or not")
    let origin = vouchCode("ArisAgent/ArisOrigin.swift")
    check(origin.contains("if genuineHelper(facts, app: app) != nil, !facts.homeRedirected, let token = ClaudeHookToken.load() {")
            && origin.contains("helperReply(pid: me, token: token, listens: { holdsSocket(pid: helper, localPort: vouchPort, remotePort: 0) }) { mine in\n                        holdsSocket(pid: helper, localPort: vouchPort, remotePort: mine)")
            && origin.contains("facts.vouchedBy = said.vouched ? helper : nil"),
          "sec4 M2: wiring: the tool asks only the real helper, and takes the yes only while launchd's job itself holds the other end of the connection")
    check(origin.components(separatedBy: "facts.ancestors").count == 3 && origin.contains("if !ArisRollout.enforcing { facts.ancestors = ancestors(of: me) }"),
          "sec4 M2: wiring: the tool's own parents are read only for the rule of the release before, while that one still decides")
    let main = vouchCode("ArisAgent/main.swift")
    if let service = main.range(of: "ArisVouchService.start()"), let first = main.range(of: "ArisBuildInfo.recordRunningAgent"), let guarded = main.range(of: "ArisOrigin.agentRefusedLine") {
        check(guarded.lowerBound < service.lowerBound && service.lowerBound < first.lowerBound, "sec4 M2: wiring: the helper answers from the moment it is allowed to serve, before it starts anything")
    } else {
        check(false, "sec4 M2: wiring: the helper starts answering its tools")
    }
}

// MARK: - Every start in the helper goes through the one place

private func secFix4SpawnPlaceTests() {
    let folder = vouchRoot.appendingPathComponent("ArisAgent")
    let files = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".swift") && $0 != "ArisChildren.swift" }
    check(files.count > 200, "sec4 M2: the helper's sources are read (\(files.count) files)")
    // Any other way to start a process: Foundation's run()/launch(), the spawn and fork calls, a shell through libc.
    let forbidden = [#"\.run\(\)"#, #"(?<!driver)(?<!\))\.launch\(\)"#, #"\bposix_spawnp?\("#, #"\bfork\(\)"#, #"\bvfork\(\)"#, #"(?<![.\w])(?<!func )system\("#, #"\bpopen\("#,
                     #"(?<!\w)Process\.run\("#, #"launchedProcess"#, #"\bexecv[pe]*\("#, #"\bexecl[pe]*\("#, #"NSTask\b"#, #"NSUserUnixTask"#]
    var offenders: [String] = []
    for file in files {
        let code = vouchCode("ArisAgent/\(file)")
        // ArisExactProcess is itself a Process (aris-tools has it too): its run() is what ArisChildren.run starts.
        for pattern in forbidden where code.range(of: pattern, options: .regularExpression) != nil && !(file == "ArisExactProcess.swift" && pattern.contains("posix_spawn")) {
            offenders.append("\(file): \(pattern)")
        }
    }
    check(offenders.isEmpty, "sec4 M2: no source file of the helper starts a process except through ArisChildren \(offenders)")
    let children = vouchCode("ArisAgent/ArisChildren.swift")
    check(children.contains("try process.run()\n        note(process.processIdentifier)") && children.contains("let failed = posix_spawn(pid, path, actions, attributes, argv, envp)\n        if failed == 0 { note(pid.pointee) }"),
          "sec4 M2: the one place writes down every child it starts, while it holds the list")
    let started = files.reduce(0) { $0 + vouchCode("ArisAgent/\($1)").components(separatedBy: "ArisChildren.run(").count - 1 + vouchCode("ArisAgent/\($1)").components(separatedBy: "ArisChildren.spawn(").count - 1 }
    check(started >= 24, "sec4 M2: the helper's starts all name it (\(started) places)")
}

// MARK: - A real question on a free loopback port (a made-up token; the child is /bin/bash)

private func secFix4RoundTripTests() {
    typealias O = ArisOrigin
    let token = String(repeating: "5e", count: 20)
    let listener = ArisVouchService.listen(on: 0)
    guard listener >= 0, let port = O.localPort(of: listener) else { return check(false, "sec4 M2 round trip: couldn't listen on a loopback port") }
    let server = Thread { ArisVouchService.accept(from: listener, port: port, token: { token }, vouches: ArisChildren.vouches(for:)) }
    server.start()
    defer { close(listener) }
    ArisChildren.forgetAll()
    // This process asks about itself: it holds the connection, but nobody here started it.
    var looked = false
    check(!O.askHelper(pid: getpid(), token: token, port: port) { _ in looked = true; return true } && !looked,
          "sec4 M2 round trip: a process the helper did not start gets a no, and nobody is asked who answered")
    check(!O.askHelper(pid: getpid(), token: String(repeating: "00", count: 20), port: port) { _ in true }, "sec4 M2 round trip: a wrong token gets no yes")
    // A child this process starts through the one place asks about itself over its own connection.
    let request = "POST /vouch HTTP/1.1\\r\\nHost: 127.0.0.1:\(port)\\r\\nx-aris-token: \(token)\\r\\nContent-Type: application/json\\r\\nContent-Length: %d\\r\\n\\r\\n%s"
    let script = "exec 3<>/dev/tcp/127.0.0.1/\(port) || exit 9; body=\"{\\\"pid\\\":${1:-$$}}\"; printf '\(request)' ${#body} \"$body\" >&3; head -c 87 <&3; exec 3>&-"
    func ask(naming pid: String?, through start: (Process) throws -> Void) -> String {
        let child = Process(), output = Pipe()
        child.executableURL = URL(fileURLWithPath: "/bin/bash")
        child.arguments = ["-c", script, "bash"] + (pid.map { [$0] } ?? [])
        child.standardOutput = output
        child.standardError = FileHandle.nullDevice
        guard (try? start(child)) != nil else { return "(couldn't start /bin/bash)" }
        child.waitUntilExit()
        return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
    let own = ask(naming: nil, through: { try ArisChildren.run($0) })
    check(own.contains("\"vouched\":true"), "sec4 M2 round trip: a child started through ArisChildren asks over its own connection and gets a yes")
    let unrecorded = ask(naming: nil, through: { try $0.run() })
    check(unrecorded.contains("\"vouched\":false"), "sec4 M2 round trip: a child started any other way gets a no")
    // A recorded child that names another process (this one) gets a no: the pid must hold the asking connection.
    let other = ask(naming: "\(getpid())", through: { try ArisChildren.run($0) })
    check(other.contains("\"vouched\":false"), "sec4 M2 round trip: a child that names another process's pid gets a no")
    // The answer stays open until the asker has looked at who holds the other end.
    let always = ArisVouchService.listen(on: 0)
    guard always >= 0, let second = O.localPort(of: always) else { return check(false, "sec4 M2 round trip: couldn't listen on a second port") }
    Thread { ArisVouchService.accept(from: always, port: second, token: { token }, vouches: { _ in true }) }.start()
    defer { close(always) }
    var held = false, heldByOther = true
    let answered = O.askHelper(pid: getpid(), token: token, port: second) { mine in
        held = O.holdsSocket(pid: getpid(), localPort: second, remotePort: mine)
        heldByOther = O.holdsSocket(pid: getppid(), localPort: second, remotePort: mine)
        return held
    }
    check(answered && held && !heldByOther, "sec4 M2 round trip: when the tool looks, the answering process still holds the other end, and no other process does")
    check(!O.askHelper(pid: getpid(), token: token, port: second) { _ in false }, "sec4 M2 round trip: a yes from a process that is not the helper is a no")
    ArisChildren.forgetAll()
}
