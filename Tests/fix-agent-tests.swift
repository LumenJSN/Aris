// Tests for the audit-1110 fixes in the agent's core and its stores (brains.json and knowledge.json). Every child
// here is a small shell script in a temp folder: no brain CLI, MCP server, schedule or skill of the user's is started,
// and nothing of his (agy's settings, the Keychain, his stores) is read or written.
import Foundation
import Security

/// A temp folder with fake programs in it, removed by `remove()`.
struct FixAgentBin {
    let folder: URL

    init() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-fix-agent-\(UUID().uuidString.prefix(8))")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// An executable shell script named `name`; its path.
    @discardableResult
    func script(_ name: String, _ body: String, shebang: String = "#!/bin/sh") -> String {
        let file = folder.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data((shebang + "\n" + body + "\n").utf8).write(to: file)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file.path
    }

    func remove() { try? FileManager.default.removeItem(at: folder) }
}

private func bytes(_ text: String) -> [UInt8] { Array(text.utf8) }

func runFixAgentTests() {
    // No test starts the user's own login shell: the folders it would give are the tests' own.
    let savedLogin = ArisLoginPath.override
    ArisLoginPath.override = []
    defer { ArisLoginPath.override = savedLogin }
    fixAgentExactArguments()
    fixAgentClosedPipes()
    fixAgentSkillDrain()
    fixAgentProgramFinder()
    fixAgentServiceStart()
    fixAgentJobBrain()
    fixAgentRemembering()
    fixAgentServiceReads()
    fixAgentKeychainRead()
    fixAgentBrainTrouble()
    fixAgentBrainDeath()
    fixAgentResultFiles()
    fixAgentAgyRules()
    fixAgentTeammateNotes()
    fixAgentSkillReferences()
    fixAgentScheduleZone()
}

// MARK: - nfd-argv-1: Korean reaches a child as the user said it

private func fixAgentExactArguments() {
    let bin = FixAgentBin()
    defer { bin.remove() }
    let who = "엄마", text = "지금 출발해요", friend = "José"
    // The fake aris-tools: its words one per line, then one variable, exactly as it got them.
    let tools = bin.script("aris-tools", #"printf '%s\n' "$@"; printf '%s' "$ARIS_JOB""#)
    let expected = bytes("message\n\(who)\n\(text)\n\(friend)\n")

    let process = ArisExactProcess()
    process.executableURL = URL(fileURLWithPath: tools)
    process.arguments = ["message", who, text, friend]
    process.environment = ["ARIS_JOB": "블랙홀 정리", "PATH": "/usr/bin:/bin"]
    let out = Pipe()
    process.standardOutput = out
    process.standardInput = FileHandle.nullDevice
    let started = (try? process.run()) != nil
    let printed = started ? out.fileHandleForReading.readDataToEndOfFile() : Data()
    process.waitUntilExit()
    check(started && Array(printed) == expected + bytes("블랙홀 정리") && process.terminationStatus == 0 && !process.isRunning,
          "nfd: a child gets 엄마, 지금 출발해요 and its job's Korean title byte for byte, never as jamo")
    check(Array(printed) != bytes("message\n\(who)\n\(text)\n\(friend)\n".decomposedStringWithCanonicalMapping),
          "nfd: what arrives is not the decomposed spelling")

    // Every way the agent itself starts aris-tools hands the words over whole.
    let environment = ["PATH": "/usr/bin:/bin"]
    let relayed = ArisAgyRelay.run(["message", who, text, friend], tools: tools, environment: environment)
    check(bytes(relayed) == Array(expected.dropLast()), "nfd: the relay (Claude's send, agy's lines) passes Korean whole")
    let bridged = ArisActivityBridge.run(tools: tools, arguments: ["message", who, text, friend], environment: environment)
    check(bridged.map { bytes($0.out) } == expected, "nfd: the user's changed card passes Korean whole")
    let looked = ArisLook.tool(tools, ["message", who, text, friend], environment)
    check(looked.map(bytes) == Array(expected.dropLast()), "nfd: 메모에 저장 and the looks pass Korean whole")
    let helped = ArisAPIHelper.execute(tools, ["message", who, text, friend], environment: environment, timeout: 10)
    check(helped.0 == 0 && bytes(helped.1) == Array(expected.dropLast()), "nfd: the API brain's calls pass Korean whole")
    let fed = ArisAPIHelper.execute(bin.script("cat-tools", "cat"), [], environment: environment, timeout: 10, stdin: text)
    check(fed.0 == 0 && bytes(fed.1) == bytes(text), "nfd: text handed over on stdin still arrives whole")

    // The pass minted from the user's words is the one aris-tools finds for the words it was started with.
    let saved = ArisMessagePass.folderOverride
    ArisMessagePass.folderOverride = bin.folder.appendingPathComponent("passes")
    defer { ArisMessagePass.folderOverride = saved }
    ArisMessagePass.mint(argv: ["message", who, text])
    let got = ArisAgyRelay.run(["message", who, text], tools: tools, environment: environment).split(separator: "\n").map(String.init)
    let routed = got.count == 3 ? messageRouting(Array(got.dropFirst()), environment: [:]) : .refused("the fake tool printed \(got.count) lines")
    check(routed == .direct, "nfd: after the user's yes the Korean message to 엄마 is sent, not refused at aris-tools' gate")
    check(messageRouting([who, text], environment: [:]) != .direct, "nfd: and that pass was for one send only")
    ArisMessagePass.mint(to: who, text: text)
    check(ArisMessagePass.consume(to: who.decomposedStringWithCanonicalMapping, text: text.decomposedStringWithCanonicalMapping),
          "nfd: a pass is found by the message, however its Hangul is spelled in between")

    // It stays a Process for everything that ends one or waits on one.
    let sleeper = ArisExactProcess()
    sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
    sleeper.arguments = ["30"]
    let ended = DispatchSemaphore(value: 0)
    sleeper.terminationHandler = { _ in ended.signal() }
    let ran = (try? sleeper.run()) != nil
    check(ran && sleeper.isRunning && sleeper.processIdentifier > 0, "exact process: it runs and has a pid")
    ArisProcessEnd.end(sleeper, grace: 1)
    check(ended.wait(timeout: .now() + 5) == .success && !sleeper.isRunning && sleeper.terminationReason == .uncaughtSignal,
          "exact process: ended like any Process, and its handler is told")
    let coded = ArisExactProcess()
    coded.executableURL = URL(fileURLWithPath: bin.script("seven", "exit 7"))
    try? coded.run()
    coded.waitUntilExit()
    check(coded.terminationStatus == 7 && coded.terminationReason == .exit, "exact process: its exit status is the child's")
    let missing = ArisExactProcess()
    missing.executableURL = bin.folder.appendingPathComponent("not-there")
    check((try? missing.run()) == nil && !missing.isRunning, "exact process: a program that isn't there is an error")
}

// MARK: - sigpipe-1: a write to a child that has gone is an error, never the end of the agent

private func fixAgentClosedPipes() {
    let bin = FixAgentBin()
    defer { bin.remove() }
    let big = Data(repeating: UInt8(ascii: "a"), count: 300_000)
    let gone = ArisExactProcess()
    gone.executableURL = URL(fileURLWithPath: "/usr/bin/true")
    let input = Pipe()
    gone.standardInput = input
    gone.standardOutput = FileHandle.nullDevice
    try? gone.run()
    gone.waitUntilExit()
    var threw = false
    do { try input.fileHandleForWriting.write(contentsOf: big) } catch { threw = true }
    check(threw, "sigpipe: writing 300 KB to a brain CLI that already exited is an error the writer catches (and this process lives to say so)")

    // The API brain's helper hands a tool its input; a tool that leaves without reading it is just a tool that ended.
    let quit = bin.script("quits", "exit 0")
    let handed = ArisAPIHelper.execute(quit, [], environment: ["PATH": "/usr/bin:/bin"], timeout: 10, stdin: String(repeating: "가", count: 100_000))
    check(handed.0 == 0, "sigpipe: a tool that exits before reading its input ends normally")

    // A connected service's program that leaves right after starting: the next line to it closes the connection.
    let server = ArisMCPStdio(executable: URL(fileURLWithPath: quit), arguments: [], environment: ["PATH": "/usr/bin:/bin"])
    let closed = DispatchSemaphore(value: 0)
    let lock = NSLock()
    nonisolated(unsafe) var reasons: [String] = []
    server.onClose = { why in
        lock.withLock { reasons.append(why ?? "closed") }
        closed.signal()
    }
    check(server.start() == nil, "sigpipe: the service's program starts")
    for _ in 0..<20 { server.send(["jsonrpc": "2.0", "method": "notifications/initialized", "params": ["pad": String(repeating: "x", count: 100_000)]]) }
    check(closed.wait(timeout: .now() + 5) == .success && lock.withLock({ reasons.count }) == 1,
          "sigpipe: lines written to a service that has gone close its connection once, with a reason")
    server.close()
}

// MARK: - imp-skill-drain: a finished script's output is waited for only a moment

private func fixAgentSkillDrain() {
    let environment = ["PATH": "/usr/bin:/bin"]
    let started = Date()
    let left = ArisSkillProcess.run("/bin/sh", ["-c", "echo started; sleep 6 & exit 0"], environment: environment, timeout: 20)
    check(left.ok && left.stdout == "started\n" && Date().timeIntervalSince(started) < 3,
          "skill drain: a script that leaves a server running behind it returns at once, with what it printed")
    let whole = ArisSkillProcess.run("/bin/sh", ["-c", "head -c 150000 /dev/zero | tr '\\0' 'a'; echo oops >&2; exit 3"], environment: environment, timeout: 20)
    check(whole.status == 3 && whole.stdout.count == 150_000 && whole.stderr == "oops\n" && !whole.timedOut,
          "skill drain: a script's whole output and its status still arrive")
    let late = Date()
    let stuck = ArisSkillProcess.run("/bin/sh", ["-c", "sleep 30 & echo $!; wait"], environment: environment, timeout: 0.4)
    let child = pid_t(stuck.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    Thread.sleep(forTimeInterval: 0.2)
    check(stuck.timedOut && child > 0 && kill(child, 0) != 0 && Date().timeIntervalSince(late) < 5,
          "skill drain: past its time limit a script is ended together with what it started")
}

// MARK: - cli-paths-8, mcp-4: programs are found the way the user's terminal finds them

private func fixAgentProgramFinder() {
    let bin = FixAgentBin()
    defer { bin.remove() }
    let nvm = bin.folder.appendingPathComponent("nvm/versions/node/v22/bin").path
    let mark = ArisLoginPath.marker
    check(ArisLoginPath.folders(inOutput: "Last login: today\nWelcome!\n\n\(mark)\(nvm):/opt/homebrew/bin:/usr/bin:relative:\(nvm)\(mark)\nbye\n") == [nvm, "/opt/homebrew/bin", "/usr/bin"],
          "cli paths: the shell's PATH is read between its marks, whatever its start-up files print; absolute folders, each once")
    check(ArisLoginPath.folders(inOutput: "Welcome!\n/usr/bin:/bin\n") == nil && ArisLoginPath.folders(inOutput: "\(mark)\(mark)") == nil,
          "cli paths: output without a marked PATH is no answer")
    check(ArisLoginPath.arguments(shell: "/bin/zsh")?.prefix(3) == ["-l", "-i", "-c"] && ArisLoginPath.arguments(shell: "/opt/homebrew/bin/fish")?.last?.contains("string join") == true
          && ArisLoginPath.arguments(shell: "/usr/local/bin/nu") == nil,
          "cli paths: zsh and bash are started as a terminal starts them (login, interactive); a shell Aris can't ask isn't started")

    // A fake login shell: a banner, its own PATH, then whatever it was asked to run.
    bin.script("shell/zsh", "echo 'Last login: yesterday'; PATH='\(nvm):/usr/bin:/bin'; eval \"$4\"")
    check(ArisLoginPath.ask(shell: bin.folder.appendingPathComponent("shell/zsh").path, timeout: 10) == [nvm, "/usr/bin", "/bin"],
          "cli paths: the login shell is asked for its PATH")
    bin.script("slow/zsh", "sleep 30")
    let asked = Date()
    check(ArisLoginPath.ask(shell: bin.folder.appendingPathComponent("slow/zsh").path, timeout: 0.5) == nil && Date().timeIntervalSince(asked) < 5,
          "cli paths: a shell that hangs is given up on at the time limit")
    bin.script("agent/zsh", "sleep 6 & PATH='\(nvm):/usr/bin'; eval \"$4\"")
    let quick = Date()
    check(ArisLoginPath.ask(shell: bin.folder.appendingPathComponent("agent/zsh").path, timeout: 10) == [nvm, "/usr/bin"] && Date().timeIntervalSince(quick) < 3,
          "cli paths: a start-up file that leaves something running doesn't hold the answer back")

    // codex installed with npm under nvm: a node script, with node beside it.
    bin.script("nvm/versions/node/v22/bin/aris-fake-node", #"echo "node ran $(basename "$1")""#)
    bin.script("nvm/versions/node/v22/bin/aris-fake-codex", "", shebang: "#!/usr/bin/env aris-fake-node")
    let known = ["~/.local/bin/aris-fake-codex", "/opt/homebrew/bin/aris-fake-codex", "/usr/local/bin/aris-fake-codex"]
    check(ArisPrograms.find("aris-fake-codex", known: known, login: { [] }) == nil, "cli paths: not in the usual folders and no shell PATH: not installed")
    let found = ArisPrograms.find("aris-fake-codex", known: known, login: { ["/nonexistent", nvm] })
    check(found?.path == nvm + "/aris-fake-codex", "cli paths: a CLI under nvm is found through the user's own PATH")
    let usual = bin.script("usual/aris-fake-codex", "exit 0")
    check(ArisPrograms.find("aris-fake-codex", known: [usual], login: { [nvm] })?.path == usual, "cli paths: the usual folders are still looked in first")
    try? FileManager.default.createDirectory(atPath: bin.folder.path + "/dir/aris-fake-codex", withIntermediateDirectories: true)
    check(ArisPrograms.find("aris-fake-codex", known: [], login: { [bin.folder.path + "/dir"] }) == nil, "cli paths: a folder of that name is no program")
    ArisLoginPath.override = [nvm]
    check(ArisClaudeDriver.installed(known)?.path == nvm + "/aris-fake-codex" && ArisCodexDriver.installed(["~/.local/bin/aris-no-such-cli"]) == nil,
          "cli paths: every brain's lookup goes through the same finder")
    ArisLoginPath.override = []

    let path = ArisPrograms.childPath(first: ["/a", "/usr/bin", "/bin"], inherited: "/usr/bin:/launchd", login: [nvm, "/a", "/bun/bin"])
    check(path == "/a:/usr/bin:/bin:/launchd:\(nvm):/bun/bin", "cli paths: a child's PATH keeps its order; the shell's folders are added after, each once")
    func launch(_ path: String) -> (Int32, String) {
        guard let found else { return (-1, "") }
        let process = ArisExactProcess()
        process.executableURL = found
        process.environment = ["PATH": path]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return (-1, "") }
        let printed = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return (process.terminationStatus, printed)
    }
    check(launch("/usr/bin:/bin").0 != 0, "cli paths: (the defect) a node-script CLI dies at once when node isn't on its PATH")
    let ran = launch(ArisPrograms.childPath(first: ["/usr/bin", "/bin"], inherited: nil, login: [nvm]))
    check(ran.0 == 0 && ran.1 == "node ran aris-fake-codex\n", "cli paths: with the shell's folders on its PATH the CLI finds its node and runs")

    // A connected service's `npx` under the same version manager.
    bin.script("nvm/versions/node/v22/bin/aris-fake-npx", "exit 0")
    check(ArisMCPStdio.resolve("aris-fake-npx", path: ArisMCPStdio.searchPath(login: [])) == nil
          && ArisMCPStdio.resolve("aris-fake-npx", path: ArisMCPStdio.searchPath(login: [nvm]))?.path == nvm + "/aris-fake-npx",
          "mcp start: a service's program under a version manager is found")
    let served = ArisMCPStdio.environment(extra: ["TOKEN": "t"], base: ["LANG": "ko_KR.UTF-8", "SECRET": "s"], login: [nvm])
    check(served["PATH"]?.hasSuffix(":" + nvm) == true && served["PATH"]?.contains("/usr/bin") == true && served["SECRET"] == nil && served["TOKEN"] == "t",
          "mcp start: the service gets that PATH (its node is found) and is still given nothing else of the agent's")
}

// MARK: - mcp-4, imp-mcp-test: a service's first start, and what 연결 테스트 says when it fails

private func fixAgentServiceStart() {
    let bin = FixAgentBin()
    defer { bin.remove() }
    check(ArisMCPHub.startTimeout >= 60 && ArisMCPHub.startTimeout > ArisMCPHub.listTimeout,
          "mcp start: a program Aris starts has time to download itself the first time")
    check(ArisMCPHub.reasonLine(ArisMCPError.timeout.message, stdio: true).contains("내려받") && !ArisMCPHub.reasonLine(ArisMCPError.timeout.message, stdio: false).contains("내려받")
          && !ArisMCPHub.reasonLine(ArisMCPError.timeout.message, stdio: true).contains("in time"),
          "mcp test: a slow start is said in Korean, with the hint only for a program")
    check(ArisMCPHub.reasonLine("couldn't find the program npx", stdio: true).hasPrefix("‘npx’ 프로그램을 찾지 못했어요") && ArisMCPHub.reasonLine("the server ended (status 1)", stdio: true).contains("상태 1")
          && ArisMCPHub.reasonLine("HTTP 401", stdio: false) == "HTTP 401",
          "mcp test: a missing program and a program that ended are said in Korean; anything else is passed on")
    let long = ArisMCPHub.reasonLine("the server ended (status 1)", stdio: true, said: "debug\n\n" + String(repeating: "x", count: 900) + "\nError: NOTION_TOKEN is not set\n")
    check(long.hasSuffix("Error: NOTION_TOKEN is not set") && long.count < 400, "mcp test: the server's own last words are added, cut short")

    // A server that dies at start for want of its token says so on stderr: 연결 테스트 shows that line, its secret hidden.
    let dies = bin.script("server", #"echo "Error: bad token $FAKE_TOKEN for workspace" >&2; exit 1"#)
    let secrets = ArisMCPMemorySecrets()
    let hub = ArisMCPHub(store: ArisMCPStore(file: bin.folder.appendingPathComponent("mcp-servers.json"), secrets: secrets), secrets: secrets)
    guard case .success(let server) = hub.save(id: nil, name: "notion", target: "/bin/sh \(dies)", secretName: "FAKE_TOKEN", secret: "tok_SECRET_4242") else {
        return check(false, "mcp test: the failing server is added")
    }
    defer { hub.disconnectAll() }
    let tested = hub.test(server.id)
    check(!tested.ok && tested.message.hasPrefix("연결하지 못했어요: ") && tested.message.contains("Error: bad token ••• for workspace") && !tested.message.contains("tok_SECRET_4242"),
          "mcp test: 연결 테스트 shows the server's own error, never its token (\(tested.message))")
    let row = hub.settingsList().first { $0["id"] as? String == server.id }
    check((row?["error"] as? String)?.contains("bad token") == true, "mcp test: the settings row keeps that reason")
    let turn = FakeMCPTurn()
    let brain = hub.listing(only: "notion", turn: turn)
    check(!brain.output.contains("bad token") && !brain.output.contains("tok_SECRET_4242"), "mcp test: a brain is never shown the server's stderr")

    // A server that hangs on a call: the connection goes with the timeout, so the next call starts a fresh program.
    var made: [FixAgentHungTransport] = []
    hub.makeTransport = { _, _ in
        let transport = FixAgentHungTransport()
        made.append(transport)
        return .success(transport)
    }
    hub.disconnect(server.id)
    _ = hub.listing(only: "notion", turn: FakeMCPTurn())
    check(made.count == 1 && made[0].closed == 0, "mcp test: the hung server is connected once")
    made[0].answersCalls = false
    hub.callTimeout = 0.5
    let hung = fixAgentCall(hub, "notion", "get_page", FakeMCPTurn(), timeout: 5)
    check(hung?.status != 0 && made[0].closed == 1, "mcp test: a call the server never answers ends that connection")
    _ = fixAgentCall(hub, "notion", "get_page", FakeMCPTurn(), timeout: 5)
    check(made.count == 2, "mcp test: the next call starts a fresh connection instead of waiting on the hung one")
}

private func fixAgentCall(_ hub: ArisMCPHub, _ service: String, _ tool: String, _ turn: ArisMCPTurn, timeout: TimeInterval) -> ArisMCPOutcome? {
    let done = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var outcome: ArisMCPOutcome?
    hub.call(service: service, tool: tool, arguments: .json("{}"), turn: turn) { got in
        outcome = got
        done.signal()
    }
    _ = done.wait(timeout: .now() + timeout)
    return outcome
}

/// A service that answers the handshake and its listing, and (when told) never answers a call.
private final class FixAgentHungTransport: ArisMCPTransport {
    var onMessage: ((Any) -> Void)?
    var onClose: ((String?) -> Void)?
    var answersCalls = true
    private(set) var closed = 0
    private let queue = DispatchQueue(label: "fix-agent-hung-transport")

    func start() -> String? { nil }

    func send(_ message: [String: Any]) {
        queue.async { [self] in
            guard let id = message["id"], let method = message["method"] as? String else { return }
            let result: [String: Any]
            switch method {
            case "initialize": result = ["protocolVersion": "2025-06-18", "capabilities": [String: Any](), "serverInfo": ["name": "hung", "version": "1"]]
            case "tools/list": result = ["tools": [["name": "get_page", "inputSchema": ["type": "object"], "annotations": ["readOnlyHint": true]]]]
            default:
                guard answersCalls else { return }
                result = ["content": [["type": "text", "text": "page"]]]
            }
            onMessage?(["jsonrpc": "2.0", "id": id, "result": result])
        }
    }

    func close() { queue.sync { closed += 1 } }
}

// MARK: - sched-1, jobs-codex-only-6: no job is locked to one brain

private func fixAgentJobBrain() {
    let only = { (brains: Set<ArisBrain>) in { (brain: ArisBrain) in brains.contains(brain) } }
    check(ArisJobBrain.pick(.codex, untrusted: true, usable: only([.claude])) == .claude
          && ArisJobBrain.pick(.codex, untrusted: true, usable: only([.antigravity])) == .antigravity
          && ArisJobBrain.pick(.codex, untrusted: false, usable: only([.claude, .antigravity])) == .claude,
          "job brain: a job for Codex on a Mac with only Claude or Antigravity runs there, never \"Couldn't start GPT (Codex)\"")
    check(ArisJobBrain.pick(.claude, untrusted: true, usable: only([.claude, .codex])) == .claude
          && ArisJobBrain.pick(.antigravity, untrusted: false, usable: only([.antigravity, .codex, .claude])) == .antigravity,
          "job brain: the AI the user chose takes the job whenever it can run")
    check(ArisJobBrain.pick(.claude, untrusted: true, usable: only([.codex, .api, .antigravity])) == .codex
          && ArisJobBrain.pick(.codex, untrusted: true, usable: only([.api, .claude, .antigravity])) == .api
          && ArisJobBrain.pick(nil, untrusted: true, usable: only([.claude, .antigravity])) == .claude,
          "job brain: outside-written work falls back first to the brains whose every action passes a gate")
    check(ArisJobBrain.pick(.codex, untrusted: true, usable: only([])) == nil, "job brain: with no AI at all there is nobody, and the caller says so")
    // Each brain keeps its own gate for outside words.
    let codex = ArisJobBrain.untrustedPlan(.codex), claude = ArisJobBrain.untrustedPlan(.claude), agy = ArisJobBrain.untrustedPlan(.antigravity)
    check(codex.brain == .codex && !codex.webSearch && !codex.sealed, "job brain: an untrusted job on Codex has its web search off (the gate asks for the rest)")
    check(claude.brain == .claude && !claude.sealed && ArisJobBrain.marksFromStart(.claude, untrusted: true) && !ArisJobBrain.marksFromStart(.claude, untrusted: false),
          "job brain: on the open Claude its turn gate is marked from the first question")
    check(agy.brain == .antigravity && agy.sealed && !ArisJobBrain.marksFromStart(.codex, untrusted: true), "job brain: on Antigravity it runs sealed (words only)")

    // Schedules: the teammate's own brain, else the one it was made with, else whoever can.
    let mate = ArisTeammate(id: "mate-a", name: "리서처", routing: "조사", instructions: "출처를 달아 줘.", look: .standard, brain: "claude",
                            memoryFile: "teammates/mate-a.md")
    check(ArisJobBrain.scheduled(teammate: mate, madeWith: "codex", usable: only([.claude, .codex])) == .claude,
          "schedule: one filed under a teammate runs on that teammate's brain")
    check(ArisJobBrain.scheduled(teammate: nil, madeWith: "claude", usable: only([.claude, .codex])) == .claude
          && ArisJobBrain.scheduled(teammate: nil, madeWith: nil, usable: only([.antigravity])) == .antigravity
          && ArisJobBrain.scheduled(teammate: nil, madeWith: "bogus", usable: only([.codex, .claude])) == .codex
          && ArisJobBrain.scheduled(teammate: nil, madeWith: "codex", usable: only([])) == nil,
          "schedule: it runs on the AI it was made with, else on whoever is there; with nobody the inbox says what to set up")
    let block = ArisTeamPrompt.job(mate, notes: [])
    check(block.contains("리서처") && block.contains("출처를 달아 줘."), "schedule: a teammate's run carries who it is and how the user wants it to work")

    // The schedule keeps the brain it was made in, and old schedules still read.
    check(ArisSchedule.brainName("claude") == "claude" && ArisSchedule.brainName("Claude; rm") == nil && ArisSchedule.brainName(nil) == nil
          && ArisSchedule.brainName(String(repeating: "a", count: 40)) == nil, "schedule: a brain's name is kept only as a plain short word")
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("aris-fix-agent-sched-\(UUID().uuidString.prefix(8))").path
    defer { try? FileManager.default.removeItem(atPath: home) }
    let now = Date(timeIntervalSince1970: 1_793_000_000)
    let added = try? ArisScheduleTool.add(["--title", "아침 브리핑", "--prompt", "오늘 일정 알려 줘", "--daily", "08:00"], home: home,
                                          environment: [ArisSchedule.brainKey: "claude"], now: now, calendar: .current)
    let plain = try? ArisScheduleTool.add(["--title", "물", "--prompt", "물 마시라고 해 줘", "--daily", "09:00"], home: home, environment: [:], now: now, calendar: .current)
    let stored = ArisScheduleStore.load(file: ArisScheduleStore.file(home: home))
    check(added != nil && plain != nil && stored.first { $0.id == added?.id }?.brain == "claude" && stored.first { $0.id == plain?.id }?.brain == nil,
          "schedule: made while talking to Claude, it asks for Claude when it runs")
    let old = #"{"id":"11111111-2222-3333-4444-555555555555","title":"t","prompt":"p","rule":{"daily":{"hour":8,"minute":0}},"created":0,"parked":[]}"#
    check((try? JSONDecoder().decode(ArisScheduledJob.self, from: Data(old.utf8)))?.brain == nil, "schedule: one saved before brains were kept still loads")
}

// MARK: - mem-1: what the user asks to remember is remembered

private func fixAgentRemembering() {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-fix-agent-mem-\(UUID().uuidString.prefix(8))")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ArisMemoryStore.at(folder)
    func said(_ text: String, _ source: ArisMemorySource = .said) -> ArisMemoryStore.Outcome {
        store.remember(ArisMemoryCandidate(kind: .fact, subject: "", text: text, confidence: 1), source: source, turnAt: Date())
    }
    func kept(_ outcome: ArisMemoryStore.Outcome) -> Bool {
        if case .added = outcome { return true }
        return false
    }
    for text in ["엄마 전화번호는 010-1234-5678이야", "내 학번은 20231234야", "내 키 180이야", "암호학 수업은 화요일", "계좌 이체는 토스로 해",
                 "토큰 이코노미 발표는 금요일", "교수님 내선 번호는 02-880-1234", "my student id is 2023-12345", "비밀번호 바꿔야 해", "토큰 1000개 샀어"] {
        check(kept(said(text)), "memory: the user's own 기억해 keeps \"\(text)\"")
    }
    for text in ["내 비밀번호는 hunter2", "와이파이 pw는 abcd1234", "핀 4821", "cvc 991", "API 키 abcd", "현관 비번 1357*", "인증 번호 553201",
                 "카드 1234.5678.9012.3456", "sk-ant-api03-AbCdEf123456GhIjKl", "my password is hunter2", "주민번호 900101-1234567", "암호는 qwerty"] {
        check(said(text) == .secret, "memory: a credential's value is still never kept (\"\(text)\")")
    }
    check(kept(said("동생 전화번호는 010-9876-5432", .tool)) && said("내 비밀번호는 hunter2", .tool) == .secret,
          "memory: the brain's memory tool, which runs on the user's words or their yes, keeps what he asked and never a credential")
    check(said("거래처 번호는 010-2222-3333", .learned) == .secret && said("암호학 수업은 수요일로 바뀜", .learned) == .secret,
          "memory: what Aris picks up on its own stays under the strict rule")
    let line = ArisMemoryStore.secretLine(korean: true), english = ArisMemoryStore.secretLine(korean: false)
    check(line.contains("넣지 않았어요") && line.contains("파일") && english.contains("didn't") && english.contains("plain file"),
          "memory: a refused credential is told with the reason (memory is a plain file)")
}

// MARK: - mcp-1, mcp-2: a read is a read by where its verb stands

private func fixAgentServiceReads() {
    for slug in ["GMAIL_LIST_LABELS", "GMAIL_LIST_DRAFTS", "GITHUB_LIST_COMMITS", "GITHUB_GET_A_COMMIT", "NOTION_FETCH_COMMENTS", "SLACK_LIST_PINS",
                 "YOUTUBE_LIST_COMMENT_THREADS", "GITHUB_LIST_STARGAZERS", "GITHUB_LIST_OPEN_PULL_REQUESTS", "SLACK_LIST_REMINDERS",
                 "GOOGLEDRIVE_LIST_SHARED_DRIVES", "DROPBOX_LIST_FILES_IN_FOLDER", "POSTHOG_LIST_PROJECTS", "CLOSE_LIST_LEADS", "GMAIL_LABELS_LIST"] {
        check(ArisMCPPolicy.kind(ofSlug: slug) == .read, "mcp reads: \(slug) only reads (its nouns aren't verbs)")
    }
    for slug in ["GMAIL_SEND_EMAIL", "GMAIL_CREATE_EMAIL_DRAFT", "NOTION_FETCH_AND_DELETE_PAGE", "X_GET_OR_CREATE_LIST", "TRELLO_CREATE_LIST", "SLACK_PINS_ADD",
                 "GITHUB_STAR_A_REPOSITORY", "GITHUB_MERGE_A_PULL_REQUEST", "FILES_READ_WRITE_FILE", "DROPBOX_DELETE_FILE", "SLACK_STATUS_UPDATE"] {
        check(ArisMCPPolicy.kind(ofSlug: slug) == .write, "mcp reads: \(slug) still writes")
    }
    check(ArisMCPPolicy.kind(ofSlug: "DO_IT") == .unknown, "mcp reads: a name with no verb still asks")
    let execute = ArisMCPPolicy.composioExecute
    let twoReads: [String: Any] = ["tools": [["tool_slug": "GITHUB_LIST_COMMITS"], ["tool_slug": "GITHUB_LIST_OPEN_PULL_REQUESTS"]]]
    let kind = ArisMCPPolicy.kind(of: ArisMCPTool(name: execute), arguments: twoReads, composio: true)
    check(kind == .read && ArisMCPPolicy.decide(kind: kind, arguments: twoReads, context: ArisMCPPolicy.Context(), composio: true, tool: execute) == .run,
          "mcp reads: 최근 커밋이랑 열린 PR 보여줘 runs as two reads in one call: no card, no \"한 번에 하나씩만\"")
    let twoWrites: [String: Any] = ["tools": [["tool_slug": "GMAIL_SEND_EMAIL"], ["tool_slug": "SLACK_SEND_MESSAGE"]]]
    check(ArisMCPPolicy.decide(kind: .write, arguments: twoWrites, context: ArisMCPPolicy.Context(), composio: true, tool: execute) == .refuse(ArisMCPPolicy.manyWritesRefusal)
          && ArisMCPPolicy.writingSlugs(["GMAIL_LIST_LABELS", "GMAIL_SEND_EMAIL", "DO_IT"]) == ["GMAIL_SEND_EMAIL", "DO_IT"],
          "mcp reads: two real writes in one call are still refused, and an unknown tool still counts as one")

    func own(_ name: String, read: Bool? = nil, destructive: Bool? = nil) -> ArisMCPKind { ArisMCPPolicy.kind(ofName: name, readOnlyHint: read, destructiveHint: destructive) }
    for name in ["list_comments", "get_commit", "search_posts", "list_labels", "get_open_issues", "list_merge_requests"] {
        check(own(name, read: true) == .read, "mcp reads: the user's own server's \(name), marked read-only, reads")
    }
    for name in ["search", "read_file", "list_directory", "get_page", "list_issues", "search_notes", "fetch_page"] {
        check(own(name) == .read, "mcp reads: \(name) with no hint at all is a plain read (it doesn't ask)")
    }
    for name in ["query", "lookup_plain", "mystery", "find_user", "check_status", "download_file", "page_get", "status"] {
        check(own(name) == .unknown, "mcp reads: \(name) with no hint isn't plainly a read, so it asks")
    }
    for name in ["get_or_create_page", "fetch_and_send_report", "read_write_file", "list_and_archive", "search_replace", "send_note", "create_list"] {
        check(own(name) == .write, "mcp reads: \(name) could write, so it asks whatever it leads with")
    }
    check(own("get_page", destructive: true) == .write && own("list_items", read: false) == .write && own("sends_digest", read: true) == .write,
          "mcp reads: a hint that says it changes things, or a write verb's form with no read verb before it, always asks")
    check(ArisMCPPolicy.decide(kind: own("get_page"), arguments: ["id": "x"], context: ArisMCPPolicy.Context(taint: .outsideText)) == .judge,
          "mcp reads: on a careful turn such a read still goes to the read judge")
}

// MARK: - mcp-3: a Keychain that can't be read is not tampering, and deletes nothing

private func fixAgentKeychainRead() {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-fix-agent-keys-\(UUID().uuidString.prefix(8))")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    check(ArisMCPKeychain.lookup(status: errSecSuccess, data: Data("k".utf8)) == .found("k") && ArisMCPKeychain.lookup(status: errSecItemNotFound, data: nil) == .missing
          && ArisMCPKeychain.lookup(status: errSecInteractionNotAllowed, data: nil) == .unreadable && ArisMCPKeychain.lookup(status: errSecAuthFailed, data: nil) == .unreadable,
          "keychain: only \"no such item\" is nothing saved; a locked or denied Keychain couldn't be read")
    let secrets = ArisMCPMemorySecrets()
    let hub = ArisMCPHub(store: ArisMCPStore(file: folder.appendingPathComponent("mcp-servers.json"), secrets: secrets), secrets: secrets)
    guard case .success(let github) = hub.save(id: nil, name: "gh", target: "npx -y github-mcp", secretName: "GITHUB_TOKEN", secret: "ghp_SECRETVALUE123"),
          case .success(let notion) = hub.save(id: nil, name: "notion", target: "npx -y notion-mcp", secretName: "NOTION_TOKEN", secret: "ntn_SECRETVALUE456") else {
        return check(false, "keychain: two services are saved")
    }
    let file = try? Data(contentsOf: hub.store.file)
    secrets.failReads = true
    check(hub.servers().isEmpty && hub.store.unreadable && !hub.store.tampered && hub.listProblem == ArisMCPHub.unreadableLine,
          "keychain: when the signing key can't be read no service starts, and it is said as that, never as a changed file")
    var failedToSave = false
    if case .failure(let error) = hub.save(id: nil, name: "again", target: "npx -y other-mcp", secretName: nil, secret: nil) { failedToSave = error.message == ArisMCPStore.unreadableSave }
    check(failedToSave && (try? Data(contentsOf: hub.store.file)) == file, "keychain: nothing is saved over a list that couldn't be checked")
    secrets.failReads = false
    check(secrets.secret(for: github.id) == "ghp_SECRETVALUE123" && secrets.secret(for: notion.id) == "ntn_SECRETVALUE456" && secrets.accounts().count == 3,
          "keychain: no other service's token is deleted because of a read that failed")
    check(Set(hub.servers().map(\.id)) == [github.id, notion.id] && !hub.store.unreadable && hub.listProblem == nil,
          "keychain: once it can be read again every service is back as it was")
    // A file changed outside Aris is still what it was: tampering.
    try? Data(#"{"servers":[],"mac":"00"}"#.utf8).write(to: hub.store.file)
    check(hub.servers().isEmpty && hub.store.tampered && hub.listProblem == ArisMCPHub.tamperedLine, "keychain: a list changed outside Aris is still called that")

    // The API brains' file has the same two cases.
    let signing = ArisMCPMemorySecrets()
    let api = ArisAPIStore(file: folder.appendingPathComponent("api-brains.json"), signing: signing)
    let profile = ArisAPIProfile(id: "groq", quick: "llama-3.3-70b-versatile", strong: "openai/gpt-oss-120b", baseURL: nil, vision: nil, tools: nil)
    check(api.update { var next = $0.saving(profile); next.active = "groq"; return next } == nil, "keychain: an API brain is saved")
    let apiFile = try? Data(contentsOf: api.file)
    signing.failReads = true
    check(api.load() == .empty && api.unreadable && !api.tampered && api.update { $0 } == ArisMCPStore.unreadableSave && (try? Data(contentsOf: api.file)) == apiFile,
          "keychain: the API brains' settings aren't called changed, or saved over, when their key can't be read")
    signing.failReads = false
    check(api.load().activeProfile == profile && !api.unreadable, "keychain: and they are back once it can")
}

// MARK: - f2-no-brain-5, warm-error-hang-10: a brain that can't start says what is missing

private func fixAgentBrainTrouble() {
    let codex = ArisBrainTrouble(brain: .codex, missing: .program)
    check(codex.line(korean: true).contains("GPT (Codex)") && codex.line(korean: true).contains("설정 › AI 서비스") && !codex.line(korean: true).contains("is it installed")
          && codex.line(korean: false).contains("isn't installed") && codex.line(korean: false).contains("Settings › AI services"),
          "no brain: a missing CLI is said in the user's language: which AI, what is missing, where to fix it")
    check(ArisBrainTrouble(brain: .api, missing: .key).line(korean: true).contains("키") && ArisBrainTrouble(brain: .api, missing: .setup).line(korean: false).contains("provider")
          && ArisBrainTrouble(brain: nil, missing: .any).line(korean: true).contains("쓸 수 있는 AI가 없어요"),
          "no brain: an API brain says whether its key or its set-up is missing; a job with nobody to take it says so")
    for trouble in ArisBrainTrouble.all {
        check(ArisBrainTrouble.named(in: trouble.line(korean: true)) == trouble && ArisBrainTrouble.named(in: trouble.line(korean: false)) == trouble
              && ArisBrainTrouble.parse(trouble.json) == trouble, "no brain: the app can read the line back as the typed reason (\(trouble.missing) \(trouble.brain?.rawValue ?? "-"))")
    }
    let line = String(decoding: ArisAgentReply.failure(codex.line(korean: true)).line, as: UTF8.self)
    let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
    check(ArisBrainTrouble.parse(object?["trouble"]) == codex && ArisAgentReply.parse(line) == .failure(codex.line(korean: true)),
          "no brain: the failure line carries the typed reason, and an app that doesn't know it still reads the sentence")
    let other = String(decoding: ArisAgentReply.failure("연결이 끊겨서 답을 멈췄어요.").line, as: UTF8.self)
    check(!other.contains("trouble") && ArisBrainTrouble.named(in: "연결이 끊겨서 답을 멈췄어요.") == nil && ArisBrainTrouble.parse(["missing": "program"]) == nil,
          "no brain: any other failure is just its sentence")
    check(ArisBrainFailure.startLine(brain: .claude, missing: .program, korean: true) == ArisBrainTrouble(brain: .claude, missing: .program).line(korean: true)
          && ArisBrainFailure.startLine(brain: .claude, missing: nil, korean: true).contains("시작하지 못했어요")
          && !ArisBrainFailure.startLine(brain: .claude, missing: nil, korean: false).contains("installed"),
          "no brain: a start that failed for another reason never guesses \"not installed\"")
    check(ArisBrainFailure.korean(request: "what's the weather", prompt: "<context>서울</context>") == false
          && ArisBrainFailure.korean(request: "", prompt: "매일 아침 브리핑") && ArisBrainFailure.korean(request: "날씨 어때", prompt: "x"),
          "no brain: the line's language is the user's own words'; a schedule's, its prompt's")
    check(ArisBrainFailure.slowLine(brain: .codex, korean: true).contains("오래") && ArisBrainFailure.slowLine(brain: .codex, korean: false).contains("too long")
          && ArisBrainFailure.silentLine(brain: .claude, korean: false) == "Claude didn't answer.", "no brain: the slow and silent lines come in both languages")

    let true_ = URL(fileURLWithPath: "/usr/bin/true")
    let keyed = ArisAPIProfile(id: "groq", quick: "llama-3.3-70b-versatile", strong: "openai/gpt-oss-120b", baseURL: nil, vision: nil, tools: nil)
    check(ArisAPIDriver(profile: keyed, tools: "/t", executable: true_, hasKey: { false }).missing == .key
          && ArisAPIDriver(profile: nil, tools: "/t", executable: true_, hasKey: { true }).missing == .setup
          && ArisAPIDriver(profile: keyed, tools: "/t", executable: true_, hasKey: { true }).missing == nil
          && ArisAPIDriver(profile: keyed, tools: "/t", executable: true_, hasKey: { false }).launch() == nil
          && ArisAPIDriver(profile: keyed, tools: "/t", executable: true_, hasKey: { true }).launch() != nil,
          "no brain: an API brain with no key, or not set up, says which")

    // A warmed Codex whose thread was refused before any question: that process is stopped, not waited on for two minutes.
    let driver = ArisCodexDriver(model: "gpt-6-luna", tools: "/t", instructions: "", home: "/Users/me")
    let opening = driver.opening()
    let thread = opening.last.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }?["id"] as? Int ?? -1
    check(!driver.isReady && thread > 0, "warm error: Codex isn't ready until its thread is open")
    let refused = driver.read(#"{"id":\#(thread),"error":{"message":"The model gpt-6-luna is not available for this account"}}"#)
    var failed = false
    if case .failure? = refused.first { failed = true }
    check(failed && !driver.isReady && ArisBrainFailure.stopsIdleProcess(waiting: false, ready: driver.isReady),
          "warm error: an error before any question, on a process whose conversation never opened, ends that process")
    check(!ArisBrainFailure.stopsIdleProcess(waiting: true, ready: false) && !ArisBrainFailure.stopsIdleProcess(waiting: false, ready: true),
          "warm error: a process that is being asked, or already has its conversation, is left alone")
    let healthy = ArisCodexDriver(model: "gpt-6-luna", tools: "/t", instructions: "", home: "/Users/me")
    let again = healthy.opening().last.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }?["id"] as? Int ?? -1
    _ = healthy.read(#"{"id":\#(again),"result":{"thread":{"id":"thread-1"}}}"#)
    check(healthy.isReady, "warm error: once the thread is open Codex is ready")
}

// MARK: - imp-brain-died-16: a brain that dies mid-turn says why, and is asked once more when nothing was done

private func fixAgentBrainDeath() {
    func death(_ stderr: String, brain: ArisBrain = .codex, korean: Bool = true, acted: Bool = false, isTask: Bool = false, events: Int = 0, retried: Bool = false) -> ArisBrainFailure.Death {
        ArisBrainFailure.death(stderr: stderr, brain: brain, korean: korean, acted: acted, isTask: isTask, events: events, retried: retried)
    }
    check(death("") == .askAgain && death("thread 'main' panicked at src/main.rs") == .askAgain, "brain died: before anything was done the question is asked once more")
    check(death("", retried: true) != .askAgain && death("", acted: true) != .askAgain && death("", isTask: true) != .askAgain && death("", events: 3) != .askAgain,
          "brain died: never twice, never after an action or any part of an answer, never for a background job")
    let flag = death("warning: something\nerror: unexpected argument '--no-session-persistence' found\n", retried: true)
    check(flag == .say("GPT (Codex)가 멈췄어요: error: unexpected argument '--no-session-persistence' found"), "brain died: the tool's own last words say why")
    var named = false
    if case .say(let line) = death("", retried: true) { named = !line.contains("agent.log") && line.contains("멈췄어요") }
    check(named && death("", korean: false, retried: true) == .say("GPT (Codex) stopped unexpectedly. Please ask again."), "brain died: no log file's name, in the user's language")
    check(death("Not logged in · Please run /login", brain: .claude) == .say("Claude 로그인이 필요해요: 터미널에서 claude 를 한 번 실행해 주세요.")
          && death("Not logged in · Please run /login", brain: .claude, korean: false) == .say("Claude needs you to log in: run claude once in Terminal."),
          "brain died: an expired login isn't retried; it says how to log in")
    var limited = false
    if case .unavailable = death("Error: You've hit your usage limit. Try again at 3pm.") { limited = true }
    check(limited, "brain died: a limit goes the way any limit does (another AI may take the question)")
    check(ArisBrainFailure.lastWords("a\n\n  b  \n\n") == "b" && ArisBrainFailure.lastWords(String(repeating: "x", count: 900)).count == ArisBrainFailure.longest,
          "brain died: the last line that says anything, cut short")
}

// MARK: - result-overwrite-12: a second result of the same title doesn't replace the first

private func fixAgentResultFiles() {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-fix-agent-results-\(UUID().uuidString.prefix(8))")
    defer { try? FileManager.default.removeItem(at: folder) }
    let name = "2026-11-10 블랙홀 정리.md"
    let first = ArisTaskResult.save("아침에 정리한 것", as: name, in: [folder])
    let second = ArisTaskResult.save("오후에 다시 정리한 것", as: name, in: [folder])
    let third = ArisTaskResult.save("저녁", as: name, in: [folder])
    check(first?.file.lastPathComponent == name && second?.file.lastPathComponent == "2026-11-10 블랙홀 정리 2.md" && third?.file.lastPathComponent == "2026-11-10 블랙홀 정리 3.md",
          "result file: the same title on the same day gets its own file each time")
    check((try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)) == "아침에 정리한 것"
          && second.flatMap { try? String(contentsOf: $0.file, encoding: .utf8) } == "오후에 다시 정리한 것", "result file: the earlier result is still there, untouched")
    let date = Date(timeIntervalSince1970: 1_793_000_000)
    let body = "정리했어요.\n\n" + String(repeating: "블랙홀은 빛도 빠져나오지 못해요. ", count: 60)
    let morning = ArisTaskResult.deliver(body, request: "블랙홀 정리해서 파일로 저장해 줘", title: "블랙홀", date: date, folders: [folder])
    let afternoon = ArisTaskResult.deliver(body, request: "블랙홀 정리해서 파일로 저장해 줘", title: "블랙홀", date: date, folders: [folder])
    check(morning.file != nil && afternoon.file != nil && morning.file != afternoon.file && afternoon.file.map { afternoon.answer.contains($0.lastPathComponent) } == true
          && afternoon.file?.lastPathComponent.hasSuffix(" 2.md") == true, "result file: the answer names the file that was really written")
    let blocked = folder.appendingPathComponent("not-a-folder")
    try? Data("x".utf8).write(to: blocked)
    check(ArisTaskResult.save("x", as: name, in: [blocked.appendingPathComponent("under"), folder])?.index == 1, "result file: a folder that can't be written still falls to the next")
    check(ArisTaskResult.numbered("a.md", 1) == "a.md" && ArisTaskResult.numbered("a.md", 2) == "a 2.md" && ArisTaskResult.numbered("메모", 3) == "메모 3", "result file: numbered before the extension")
}

// MARK: - agy-rules-7: Antigravity's rules are written by the agent itself

private func fixAgentAgyRules() {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("aris-fix-agent-agy-\(UUID().uuidString.prefix(8))").path
    defer { try? FileManager.default.removeItem(atPath: home) }
    let tools = home + "/.config/aris/aris-tools", folder = home + "/.config/aris/aris"
    let file = ArisAgyRules.settingsFile(home: home)
    func settings() -> [String: Any] { ((try? Data(contentsOf: file)).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:] }
    func rules(_ key: String) -> [String] { (settings()["permissions"] as? [String: Any])?[key] as? [String] ?? [] }
    // agy installed after Aris, never started: no settings file at all.
    check(ArisAgyRules.ensure(home: home, tools: tools, folder: folder) == .written && rules("allow") == ["command(\(tools))", "read_url(*)"],
          "agy rules: with no settings file yet, the agent makes it with the rule that lets agy run aris-tools")
    check(rules("deny").contains("command(\(tools) message)") && rules("deny").contains("command(rm)") && rules("deny").contains("read_file(\(home)/Library/Messages/*)")
          && rules("deny").contains("read_file(\(folder)/memory.sqlite*)") && rules("deny").contains("command(.*claude-hook-token.*)"),
          "agy rules: and with the deny rules that stand in for a risk gate")
    check((try? String(contentsOf: file.appendingPathExtension("before-aris"), encoding: .utf8)) == "{}\n", "agy rules: what was there before Aris (nothing) is kept for the uninstall")
    check(ArisAgyRules.ensure(home: home, tools: tools, folder: folder) == .ready, "agy rules: checked again, nothing is written when every rule is there")

    // The user's own settings: everything of theirs is kept, Aris's rules are added after.
    try? FileManager.default.removeItem(atPath: home + "/.gemini")
    try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    let own = #"{"theme":"dark","permissions":{"allow":["command(open)","command(git status)"],"deny":["command(rm)","command(my-secret-tool)"],"ask":["x"]}}"#
    try? Data(own.utf8).write(to: file)
    check(ArisAgyRules.ensure(home: home, tools: tools, folder: folder) == .written && settings()["theme"] as? String == "dark"
          && (settings()["permissions"] as? [String: Any])?["ask"] as? [String] == ["x"],
          "agy rules: the user's other settings stay as they were")
    check(rules("allow") == ["command(git status)", "command(\(tools))", "read_url(*)"] && Array(rules("deny").prefix(2)) == ["command(rm)", "command(my-secret-tool)"]
          && rules("deny").filter { $0 == "command(rm)" }.count == 1,
          "agy rules: their own rules are kept in place (only the broad rules an old Aris added go), none twice")
    check((try? String(contentsOf: file.appendingPathExtension("before-aris"), encoding: .utf8)) == own, "agy rules: their settings as they were are kept once beside the file")
    check(ArisAgyRules.ensure(home: home, tools: tools, folder: folder) == .ready
          && (try? String(contentsOf: file.appendingPathExtension("before-aris"), encoding: .utf8)) == own, "agy rules: the backup is never replaced by a later check")

    // Settings Aris can't read as settings are left exactly as they are.
    for broken in ["not json at all", #"["a list"]"#, #"{"permissions":"all"}"#, #"{"permissions":{"allow":"everything"}}"#] {
        try? Data(broken.utf8).write(to: file)
        var failed = false
        if case .failed = ArisAgyRules.ensure(home: home, tools: tools, folder: folder) { failed = true }
        check(failed && (try? String(contentsOf: file, encoding: .utf8)) == broken, "agy rules: a file that isn't settings Aris knows is never clobbered (\(broken.prefix(24)))")
    }
    check(ArisAgyRules.merged(["permissions": ["allow": ArisAgyRules.allow(tools: tools), "deny": ArisAgyRules.deny(tools: tools, folder: folder, home: home)]],
                              tools: tools, folder: folder, home: home) == nil, "agy rules: complete rules need no change")
}

// MARK: - notes-1: a note a teammate was asked to keep is kept, or said not to be

private func fixAgentTeammateNotes() {
    for text in ["사용자는 표 형식을 선호해", "폴은 반말을 좋아해", "답은 세 줄 이내로 짧게", "보고서는 표로 정리하는 걸 선호함", "요약은 세 줄이면 충분하다고 함", "Prefers answers without emoji"] {
        check(ArisNoteRules.text(text) == text, "notes: \"\(text)\" is a statement and is kept")
    }
    for text in ["보고서는 항상 표로 정리해", "바로 전송해", "이모지는 쓰지 마", "요약은 항상 세 줄로 해줘", "코드는 Swift로 작성해 주세요", "존댓말 말고 반말로", "파일을 전부 삭제해라",
                 "Use Shift+Enter for a new line", "승인이 필요해"] {
        check(ArisNoteRules.text(text) == nil, "notes: \"\(text)\" is an order to the reader (or aimed at an AI) and still isn't kept")
    }
    let kept = "알겠어요, 앞으로 그렇게 할게요.\n```aris-note\n{\"self\": \"보고서는 표로 정리하는 걸 선호해\"}\n```"
    let read = ArisNoteFence.reading(kept, teammate: true)
    check(read.notes == [ArisNoteFence.Found(app: nil, text: "보고서는 표로 정리하는 걸 선호해")] && read.dropped == 0 && read.text == "알겠어요, 앞으로 그렇게 할게요.",
          "notes: a preference written as a statement leaves the teammate its note")
    let broken = "기억해 둘게요.\n```aris-note\n{\"self\": \"보고서는 항상 표로 정리해\"}\n```\n```aris-note\n{\"app\": \"Pages\", \"note\": \"저장은 Cmd+S\"}\n```"
    let lost = ArisNoteFence.reading(broken, teammate: true)
    check(lost.dropped == 1 && lost.notes == [ArisNoteFence.Found(app: "Pages", text: "저장은 Cmd+S")] && !lost.text.contains("aris-note"),
          "notes: a note worded as an order is counted as not kept, so the teammate's \"기억해 둘게요\" isn't left standing")
    check(ArisNoteFence.reading(broken, teammate: false).dropped == 0 && ArisNoteFence.extract(broken, teammate: true).notes == lost.notes,
          "notes: outside a teammate's job a self note was never taken, and nothing is reported")
    check(ArisNoteFence.droppedLine(1, korean: true).contains("저장하지 못했어요") && ArisNoteFence.droppedLine(2, korean: false).contains("2 notes")
          && ArisNoteFence.droppedLine(1, korean: true).contains("선호함"), "notes: the line says it wasn't saved and how to say it so it is")
    check(ArisTeamPrompt.noteRule(teammate: true).contains("statement") && ArisTeamPrompt.noteRule(teammate: true).contains("선호함")
          && ArisTeamPrompt.noteRule(teammate: false).contains("never as a command"), "notes: the brain is told which shape a note is kept in")
}

// MARK: - skill-2: every reference file a safe skill points at can be read

private final class FixAgentReviewer: ArisSkillReviewing {
    var inputs: [String] = []
    /// The answer for each pass in order (the last one repeats); nil: the reviewer couldn't run.
    var answers: [ArisSkillReview?]
    init(_ answers: [ArisSkillReview?]) { self.answers = answers }

    func review(input: String, manifest: ArisSkillManifest) -> ArisSkillReview? {
        inputs.append(input)
        return answers.count > 1 ? answers.removeFirst() : answers.first ?? nil
    }
}

private final class FixAgentScanner: ArisSkillStaticScanning {
    func scan(_ folder: URL) -> ArisSkillStaticReport? { ArisSkillStaticReport(recommendation: "SAFE", complete: true, issues: []) }
}

private func fixAgentSkillReferences() {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("aris-fix-agent-skill-\(UUID().uuidString.prefix(8))")
    defer { try? FileManager.default.removeItem(at: root) }
    func write(_ text: String, _ path: String, in skill: URL) {
        let file = skill.appendingPathComponent(path)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: file, atomically: true, encoding: .utf8)
    }
    func make(_ name: String, references: [(String, Int)]) -> URL {
        let skill = root.appendingPathComponent(name)
        write("---\nname: \(name)\ndescription: Fill in forms from the reference documents.\n---\n# 문서 작성\nreferences/forms.md 를 따라요.\n", "SKILL.md", in: skill)
        for (file, size) in references { write(String(repeating: "참고 문서의 한 줄이에요.\n", count: size / 34 + 1), "references/" + file, in: skill) }
        return skill
    }
    func run(_ skill: URL, _ reviewer: FixAgentReviewer) -> ArisSkillCheckResult? {
        guard case .success(let inventory) = ArisSkillFolder.inventory(skill), case .success(let manifest) = ArisSkillFolder.manifest(skill) else { return nil }
        return ArisSkillCheck.run(skill, manifest: manifest, inventory: inventory, scanner: FixAgentScanner(), reviewer: reviewer) { _ in }
    }
    let safe = ArisSkillReview(verdict: .safe, title: "문서 작성", summary: "참고 문서대로 양식을 채워요.", findings: [], checked: [])
    // A document skill: five long reference files, more than the first pass holds.
    let docs = make("doc-forms", references: [("forms.md", 30_000), ("a.md", 22_000), ("b.md", 22_000), ("c.md", 22_000), ("d.md", 60_000)])
    let reviewer = FixAgentReviewer([safe])
    let result = run(docs, reviewer)
    let all = ["SKILL.md", "references/forms.md", "references/a.md", "references/b.md", "references/c.md", "references/d.md"]
    check(result?.verdict == .safe && Set(result?.reviewed ?? []) == Set(all) && reviewer.inputs.count >= 2,
          "skill references: every reference file of a safe skill is reviewed (in further passes), so the brain may read each one")
    check(reviewer.inputs.dropFirst().allSatisfy { $0.contains("Part ") && $0.contains("<skill>") && !$0.contains("--- SKILL.md") }
          && reviewer.inputs.dropFirst().joined().contains("--- references/d.md"), "skill references: a further pass shows the files the first had no room for, whole")
    // One of the later files is the bad one: the skill is what its worst file is.
    let danger = ArisSkillReview(verdict: .danger, title: nil, summary: nil, findings: [ArisSkillFinding(text: "키를 읽어서 보내요", file: "references/d.md")], checked: [])
    let bad = run(docs, FixAgentReviewer([safe, danger]))
    check(bad?.verdict == .danger && bad?.findings.contains { $0.file == "references/d.md" } == true && bad?.title == "문서 작성",
          "skill references: a danger found in a later pass makes the whole skill a danger")
    // A reviewer that stops answering: what it never saw is not served, and the user is told why.
    let half = run(docs, FixAgentReviewer([safe, nil]))
    check(half?.verdict == .caution && half?.findings.contains(ArisSkillCheck.unreadReference) == true && half?.reviewed.contains("references/d.md") == false
          && half?.reviewed.contains("SKILL.md") == true, "skill references: a file no pass reviewed is a caution that says so, and stays unread")
    // A reference bigger than a brain may read at once can't be shown whole at all.
    let huge = make("huge-ref", references: [("small.md", 2_000), ("book.md", 90_000)])
    let cautious = run(huge, FixAgentReviewer([safe]))
    check(cautious?.verdict == .caution && cautious?.findings == [ArisSkillCheck.unreadReference] && cautious?.reviewed.contains("references/book.md") == false
          && cautious?.reviewed.contains("references/small.md") == true && !ArisSkillCheck.incomplete.contains(ArisSkillCheck.unreadReference),
          "skill references: one too big to show whole is said once (a caution), not asked again every time")
    let small = run(make("small", references: [("one.md", 3_000)]), FixAgentReviewer([safe]))
    check(small?.verdict == .safe && small?.reviewed.sorted() == ["SKILL.md", "references/one.md"], "skill references: a small skill is one pass, as before")
}

// MARK: - imp-sched-tz: a daily job follows the Mac to a new time zone

private func fixAgentScheduleZone() {
    var seoul = Calendar(identifier: .gregorian), losAngeles = Calendar(identifier: .gregorian)
    seoul.timeZone = TimeZone(identifier: "Asia/Seoul")!
    losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    func at(_ calendar: Calendar, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }
    let lastRun = at(seoul, 9, 8)
    func job(_ rule: ArisRepeat, next: Date?, running: Date? = nil) -> ArisScheduledJob {
        ArisScheduledJob(id: UUID(), title: "아침 브리핑", prompt: "p", teammate: nil, rule: rule, created: lastRun, nextRun: next, lastRun: lastRun, runningSince: running, parked: [])
    }
    let daily = job(.daily(hour: 8, minute: 0), next: at(seoul, 10, 8))
    // Landed in Los Angeles at 13:00 on the 9th (06:00 on the 10th in Seoul).
    let landed = at(losAngeles, 9, 13)
    check(ArisSchedule.retimed(daily, now: landed, calendar: seoul) == daily, "schedule zone: in the same place nothing moves")
    check(ArisSchedule.retimed(daily, now: landed, calendar: losAngeles).nextRun == at(losAngeles, 10, 8),
          "schedule zone: 매일 아침 8시 runs at eight where the Mac is now, not at 15:00 (eight in Seoul)")
    let weekly = job(.weekly(weekday: 6, hour: 18, minute: 0), next: at(seoul, 13, 18))
    check(ArisSchedule.retimed(weekly, now: landed, calendar: losAngeles).nextRun == at(losAngeles, 13, 18), "schedule zone: a weekly job moves the same way")
    let once = job(.once(at(seoul, 10, 8)), next: at(seoul, 10, 8)), every = job(.every(seconds: 3_600), next: landed.addingTimeInterval(1_800))
    check(ArisSchedule.retimed(once, now: landed, calendar: losAngeles) == once && ArisSchedule.retimed(every, now: landed, calendar: losAngeles) == every,
          "schedule zone: a one-time job is a moment and an every-hour job an interval: both stay")
    let due = job(.daily(hour: 8, minute: 0), next: landed.addingTimeInterval(-60)), going = job(.daily(hour: 8, minute: 0), next: at(seoul, 10, 8), running: landed)
    check(ArisSchedule.retimed(due, now: landed, calendar: losAngeles) == due && ArisSchedule.retimed(going, now: landed, calendar: losAngeles) == going,
          "schedule zone: a run that is already due or going isn't touched")
}
