//
//  ArisHandsShim.swift
//  aris-agent
//
//  `aris-agent hands-mcp --tools <aris-tools>`: the MCP face's stdio server (ArisHandsFace), started by the open Claude's
//  Claude Code as its own child, so it runs in Claude's process tree with Claude's environment, as that Claude's Bash
//  calls do. For each tools/call: the start check looked at again, then the one gate entry with the trust policy
//  (ArisCapabilityGate.decide(.trust): ArisTodayTrust until jv-trust's lands, which gives an aris-tools call what the
//  PreToolUse hook gave its shell line: Claude Code's rules, a teammate's scopes, the turn gate with the hook's own
//  input, folder and judge); then aris-tools with those words as a child (its own hand-offs to the agent's routes
//  included), a read of Aris's own stores in this process (ArisCapabilityLocal), or the helper capability itself. A call that comes
//  back "still under way" with an id (a desktop, service or skill call waiting on a card) is collected here, as the API
//  brain's helper does: the model has no `wait` tool. Nothing of the agent's server runs in this process.
//

import Foundation

final class ArisHandsServer: @unchecked Sendable {
    /// Runs aris-tools with these words (and text on stdin) in `environment`: its status, stdout and stderr. `started`
    /// hands over the process so a cancel can end it.
    typealias Run = (_ tools: String, _ argv: [String], _ stdin: String?, _ environment: [String: String], _ timeout: TimeInterval,
                     _ started: (Process) -> Void) -> ArisCapabilityLocal.Output
    typealias Local = (_ argv: [String], _ environment: [String: String]) -> ArisCapabilityLocal.Output?

    let tools: String
    private let environment: [String: String]
    private let write: (Data) -> Void
    private let judge: (ArisReadCall) -> ArisReadVerdict
    private let run: Run
    private let local: Local
    private let mayRun: () -> Bool
    private let trust: ArisTrustDeciding
    private let lock = NSLock()
    private var running: [String: Process] = [:]
    private var cancelled: Set<String> = []

    /// What a call's text is cut to (Claude Code's own Bash output limit).
    static let longestText = 30_000

    init(tools: String, environment: [String: String], write: @escaping (Data) -> Void, judge: @escaping (ArisReadCall) -> ArisReadVerdict,
         run: @escaping Run = { ArisHandsServer.runTools($0, $1, $2, $3, $4, folder: nil, $5) }, local: @escaping Local = ArisHandsServer.runLocal,
         mayRun: @escaping () -> Bool = { ArisOrigin.stillMayRun() }, trust: ArisTrustDeciding? = nil) {
        self.tools = tools
        self.environment = environment
        self.write = write
        self.judge = judge
        self.run = run
        self.local = local
        self.mayRun = mayRun
        self.trust = trust ?? ArisMindTrust.decider(environment: environment, judge: judge)
    }

    /// One line from Claude Code (any queue). A call is answered on its own queue, so a card that waits doesn't hold
    /// up another call; every line out is written whole.
    func receive(_ line: Data) {
        switch ArisMCPServerWire.step(line, tools: ArisHandsFace.tools) {
        case .reply(let data): write(data)
        case .nothing: break
        case .cancel(let id):
            let key = Self.key(id)
            let process = lock.withLock { () -> Process? in
                cancelled.insert(key)
                return running[key]
            }
            if let process, process.isRunning { ArisProcessEnd.end(process) }
        case .call(let id, let name, let arguments):
            // Claude Code's own id for the call (its stream's tool-use id), for the helper's record of what it decided.
            let use = ArisMCPServerWire.toolUseId(line)
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                let answer = self.answer(name: name, input: arguments, key: Self.key(id), use: use)
                let gone = lock.withLock { () -> Bool in
                    running[Self.key(id)] = nil
                    return cancelled.remove(Self.key(id)) != nil
                }
                // A cancelled call gets no answer (the client has moved on).
                if !gone { write(ArisMCPServerWire.callResult(id: id, text: answer.text, isError: answer.isError, meta: answer.meta)) }
            }
        }
    }

    /// Ends every call still running (the client went away).
    func endAll() {
        let all = lock.withLock { () -> [Process] in
            let all = Array(running.values)
            running = [:]
            return all
        }
        for process in all where process.isRunning { ArisProcessEnd.end(process) }
    }

    private static func key(_ id: Any) -> String { (id as? String).map { "s:" + $0 } ?? "n:\((id as? NSNumber)?.stringValue ?? "?")" }

    /// One call's answer: what the model reads, whether it failed, and the content's source. `use`: the provider's own
    /// id for the call (ArisTrustCall.useId).
    func answer(name: String, input: [String: Any], key: String = "", use: String? = nil) -> ArisToolResult {
        guard let call = ArisHandsFace.call(function: name, input: input, tools: tools) else {
            return ArisToolResult(text: "Not run: the arguments aren't what this tool takes.", isError: true)
        }
        // The start check looked at again (the hook's first step), then the one gate entry with the trust policy.
        guard mayRun() else { return ArisToolResult(text: ArisOrigin.refusedLine, isError: true) }
        let trustCall = ArisTrustCall(entry: call.entry, arguments: input, effect: call.entry.effect(input), argv: call.argv, stdin: call.stdin,
                                      environment: environment, tools: tools, useId: use)
        switch ArisCapabilityGate.decide(call.argv ?? [], stdin: call.stdin, tools: tools, turn: .trust(trust, trustCall)) {
        case .trust(.run), .trust(.runWithUndo): break
        case .trust(.ask(let question)): return ArisToolResult(text: "Not run: it needs the owner's yes (\(question)).", isError: true)
        case .trust(.refuse(let reason)): return ArisToolResult(text: reason, isError: true)
        default: return ArisToolResult(text: ArisTurnGate.unreadable, isError: true)
        }
        // Core 2: the helper decided (and asked); the call runs the Core 2 way here, in Claude's process tree, and the
        // helper records it.
        if let remote = trust as? ArisMindRemote { return core2(remote, call: trustCall, key: key) }
        guard let argv = call.argv else {
            guard case .helper(let body) = call.entry.run else { return ArisToolResult(text: ArisTurnGate.unreadable, isError: true) }
            return body(input, ArisCapabilityContext(environment: environment, folder: ArisCapabilityLocal.ownFolder,
                                                     home: FileManager.default.homeDirectoryForCurrentUser.path, tools: tools, timeout: ArisHandsFace.callLimit))
        }
        let content = Self.content(argv)
        if call.stdin == nil, let output = local(argv, environment) { return Self.result(output, content: content) }
        let started = Date()
        let register = { [weak self] (process: Process) in
            guard let self else { return }
            let stop = self.lock.withLock { () -> Bool in
                self.running[key] = process
                return self.cancelled.contains(key)
            }
            if stop { ArisProcessEnd.end(process) }
        }
        var output = run(tools, argv, call.stdin, environment, ArisHandsFace.callLimit, register)
        // A call that handed back an id: collected here until it is done or the call's time is up.
        if let kind = argv.first, ["desktop", "mcp", "skill"].contains(kind) {
            let deadline = started.addingTimeInterval(ArisHandsFace.callLimit)
            while output.status == ArisSlowCalls.waitingStatus, Date() < deadline,
                  let match = (output.stdout + output.stderr).range(of: #"wait [0-9a-f]{16}"#, options: .regularExpression) {
                let id = String((output.stdout + output.stderr)[match].dropFirst(5))
                output = run(tools, [kind, "wait", id], nil, environment, ArisSlowCalls.slice + 15, register)
            }
        }
        return Self.result(output, content: content)
    }

    /// A call the helper let through with `arisCore2` on: run by ArisMindExecutor (the shell sandbox, files with their
    /// undo), aris-tools as this server runs it, then reported to the helper for the record.
    private func core2(_ remote: ArisMindRemote, call: ArisTrustCall, key: String) -> ArisToolResult {
        let register = { [weak self] (process: Process) in
            guard let self else { return }
            let stop = self.lock.withLock { () -> Bool in
                self.running[key] = process
                return self.cancelled.contains(key)
            }
            if stop { ArisProcessEnd.end(process) }
        }
        // The owner's yes on the trust gate's card for this call: its route takes it in place of its own card.
        var own = environment
        own[ArisMindPasses.environmentKey] = remote.pass(call.id)
        // The one child environment Core 2 gives what it starts (ArisMindExecutor.childEnvironment).
        let callEnvironment = ArisMindExecutor.childEnvironment(own)
        var executor = ArisMindExecutor(tools: tools, environment: environment, home: FileManager.default.homeDirectoryForCurrentUser.path,
                                        runTools: { [self] argv, stdin in run(tools, argv, stdin, callEnvironment, ArisHandsFace.callLimit, register) })
        // The call's mark rides into aris-tools' activity log, so the record knows which of its entries are this call.
        executor.markedTools = { [self] argv, stdin, mark in
            run(tools, argv, stdin, ArisMindExecutor.marked(callEnvironment, mark), ArisHandsFace.callLimit, register)
        }
        executor.local = { [self] argv in local(argv, environment) }
        // The effect the helper decided it as (decision 4): an overwrite decided reversible is written only with its
        // verified copy; with no word from the helper, the strictest reading (reversible: the copy is needed).
        // The helper's mark is the only one that counts: whatever the model wrote under that name goes.
        var arguments = call.arguments
        if call.entry.id == "app.type" { arguments[ArisApps.TypeOver.argument] = remote.erasedMark(call.id) }
        let result = executor.run(call.entry, arguments: arguments, argv: call.argv, stdin: call.stdin, caller: remote.caller(call.id),
                                  judged: remote.judged(call.id) ?? .changeReversible, resolved: remote.resolved(call.id))
        remote.report(call, result: result)
        return ArisToolResult(text: result.text, isError: result.isError, content: result.content.map { ArisToolResult.Content(kind: $0.kind, source: $0.source) })
    }

    /// The source an aris-tools call's output is content from, when others' words may be in it (its row's `prints`).
    static func content(_ argv: [String]) -> ArisToolResult.Content? {
        guard let row = ArisCapabilities.capability(argv), row.prints == .outsideText || row.prints == .markedByRoute else { return nil }
        let kind: String
        switch argv.first ?? "" {
        case "mail", "messages", "notes", "obsidian": kind = argv[0] == "obsidian" ? "notes" : argv[0]
        case "web": kind = "web"
        case "files", "find", "shelf", "finder": kind = "file"
        case "screen", "selection", "clipboard", "tab", "windows": kind = "screen"
        case "desktop", "type": kind = "app"
        case "mcp", "skill", "aside", "session", "routine": kind = "service"
        default: kind = "aris"
        }
        return .init(kind: kind, source: "aris-tools " + argv.prefix(3).joined(separator: " "))
    }

    static func result(_ output: ArisCapabilityLocal.Output, content: ArisToolResult.Content?) -> ArisToolResult {
        let shown = shown(output)
        // A failure may name what others wrote too: still marked.
        return ArisToolResult(text: shown.text, isError: shown.isError, content: content)
    }

    /// What the model reads of a command: what it printed and what it complained (as a shell call shows both), cut to
    /// Claude Code's limit; a failure says its exit status first.
    static func shown(_ output: ArisCapabilityLocal.Output) -> (text: String, isError: Bool) {
        let said = [output.stdout, output.stderr].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n")
        let text = String((output.status == 0 ? said : "Exit code \(output.status)\n" + said).prefix(longestText))
        return (text.isEmpty ? "(no output)" : text, output.status != 0)
    }

    // MARK: - Live

    static func runLocal(_ argv: [String], _ environment: [String: String]) -> ArisCapabilityLocal.Output? {
        ArisCapabilityLocal.run(argv, environment: environment, folder: ArisCapabilityLocal.ownFolder,
                                home: FileManager.default.homeDirectoryForCurrentUser.path)
    }

    /// aris-tools as a child of this process (so of Claude's), in Claude's environment, as the Bash call ran it.
    static func runTools(_ tools: String, _ argv: [String], _ stdin: String?, _ environment: [String: String], _ timeout: TimeInterval,
                         folder: String? = nil, _ started: (Process) -> Void) -> ArisCapabilityLocal.Output {
        let process = ArisExactProcess()
        process.executableURL = URL(fileURLWithPath: ArisAppBundle.executed(tools))
        process.arguments = argv
        process.environment = environment
        if let folder { process.currentDirectoryURL = URL(fileURLWithPath: folder) }
        let output = Pipe(), errors = Pipe(), input = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = stdin == nil ? FileHandle.nullDevice : input
        do { try ArisChildren.run(process) } catch { return .failed("(couldn't run it)") }
        started(process)
        if let stdin {
            DispatchQueue.global().async {
                try? input.fileHandleForWriting.write(contentsOf: Data(stdin.utf8))
                try? input.fileHandleForWriting.close()
            }
        }
        var printed = Data(), complaint = Data()
        let reading = DispatchGroup(), lock = NSLock()
        for (pipe, isOutput) in [(output, true), (errors, false)] {
            reading.enter()
            DispatchQueue.global().async {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                lock.withLock { if isOutput { printed = data } else { complaint = data } }
                reading.leave()
            }
        }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.005) }
        if process.isRunning {
            ArisProcessEnd.end(process)
            _ = reading.wait(timeout: .now() + 2)
            return .failed("(it took too long)")
        }
        _ = reading.wait(timeout: .now() + 5)
        return lock.withLock {
            ArisCapabilityLocal.Output(status: process.terminationStatus, stdout: String(decoding: printed, as: UTF8.self), stderr: String(decoding: complaint, as: UTF8.self))
        }
    }

    /// The read judge as the hook asks it (aris-tools' askReadJudge): POST /mcp-tool `judge` with this turn's credential.
    static func liveJudge(environment: [String: String]) -> (ArisReadCall) -> ArisReadVerdict {
        { call in
            guard let path = environment[ArisMCPTurnCredential.environmentKey], path.hasPrefix("/"), let turn = credential(path), !turn.isEmpty,
                  let token = ClaudeHookToken.load(), let url = URL(string: "http://127.0.0.1:23351/mcp-tool") else { return .blocked(.undecided) }
            let wait = ArisReadGate.timeout + 8
            var request = URLRequest(url: url, timeoutInterval: wait)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
            request.httpBody = try? JSONSerialization.data(withJSONObject: ArisReadGate.body(call, turn: turn))
            let configuration = ArisNoStore.configuration()
            configuration.timeoutIntervalForRequest = wait
            configuration.timeoutIntervalForResource = wait
            let done = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var reply: [String: Any]?
            URLSession(configuration: configuration).dataTask(with: request) { data, _, _ in
                if let data { reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] }
                done.signal()
            }.resume()
            _ = done.wait(timeout: .now() + wait + 2)
            return ArisReadGate.verdict(reply: reply)
        }
    }

    /// The turn's credential as aris-tools reads it (its first 128 bytes, trimmed).
    static func credential(_ path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 128) else { return nil }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ArisHandsShim {
    /// The server loop: lines on stdin, lines on stdout, until stdin closes (Claude Code ended).
    static func serve(arguments: [String] = CommandLine.arguments) -> Never {
        guard let index = arguments.firstIndex(of: "--tools"), index + 1 < arguments.count,
              arguments[index + 1].hasPrefix("/"), (arguments[index + 1] as NSString).lastPathComponent == "aris-tools" else {
            FileHandle.standardError.write(Data("aris-agent hands-mcp: --tools <aris-tools> is needed\n".utf8))
            exit(2)
        }
        let environment = ProcessInfo.processInfo.environment
        if ArisCore2.isOn() {
            ArisMindUndoHooks.live.register()
            ArisAppsTextUndoLive.install()
        }
        let out = FileHandle.standardOutput, lock = NSLock()
        let server = ArisHandsServer(tools: arguments[index + 1], environment: environment,
                                     write: { data in lock.withLock { try? out.write(contentsOf: data) } },
                                     judge: ArisHandsServer.liveJudge(environment: environment))
        signal(SIGTERM, SIG_IGN)
        let terminate = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
        terminate.setEventHandler {
            server.endAll()
            exit(0)
        }
        terminate.resume()
        var buffer = Data()
        FileHandle.standardInput.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                server.endAll()
                exit(0)
            }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = Data(buffer[buffer.startIndex..<newline])
                buffer.removeSubrange(buffer.startIndex...newline)
                if !line.isEmpty { server.receive(line) }
            }
            if buffer.count > ArisMCPServerWire.longestLine { exit(1) }
        }
        dispatchMain()
    }
}
