//
//  ArisMindBrain.swift
//  aris-agent
//
//  `aris-agent mind-brain --profile <id>`: the Mind's own loop for an API-key brain with `arisCore2` on (ARCHITECTURE
//  Part 2, Mind), started by its runner as the brain's process (ArisMindBrainDriver), so every aris-tools call it makes
//  is inside that brain's own process tree and the agent's routes take it as the turn's. The provider only thinks
//  (ArisMindAPIProvider, the key read here by profile id and never sent anywhere but its provider); the loop is
//  ArisMindLoop. Each round's calls are decided by the helper, which holds the owner's words, the trust gate, the cards
//  and the record (POST /mind-call: decide_batch, then ask for the ones that wait: one card per intent), and run here
//  in parallel the Core 2 way (ArisMindExecutor: the shell sandbox, files with their undo), each with the pass the
//  owner's yes on the gate's card minted for it (ArisMindPasses), and reported back (done). Nothing the helper didn't
//  let run is run; anything that keeps the helper from answering refuses.
//
//  Driver → child (JSON lines): ask {text, tier, task, context}, new_conversation, cancel.
//  Child → driver: delta {text}, status {text}, result {text}, error {message}.
//

import Foundation

final class ArisMindBrain: @unchecked Sendable {
    typealias Post = (_ body: [String: Any], _ wait: TimeInterval) -> [String: Any]?

    let tools: String
    private let provider: (ArisTier) -> ArisMindProvider
    private let post: Post
    private let credential: () -> String?
    /// The executor for one call: `pass` goes into that aris-tools run's environment only.
    private let executor: (_ pass: String?) -> ArisMindExecutor
    private let send: (Data) -> Void
    private let lock = NSLock()
    private var history: [ArisMindMessage] = []
    private var current = ArisTurnID.zero
    private var running: ArisMindLoop?

    static let unreachable = ArisMindRemote.unreachable

    init(tools: String, provider: @escaping (ArisTier) -> ArisMindProvider, post: @escaping Post, credential: @escaping () -> String?,
         executor: @escaping (_ pass: String?) -> ArisMindExecutor, send: @escaping (Data) -> Void) {
        self.tools = tools
        self.provider = provider
        self.post = post
        self.credential = credential
        self.executor = executor
        self.send = send
    }

    var conversation: [ArisMindMessage] { lock.withLock { history } }

    // MARK: - Lines in

    /// One line from the driver (any queue). A turn runs off the reading queue; a newer one ends it.
    func receive(_ line: String) {
        guard let data = line.data(using: .utf8), let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        switch object["type"] as? String {
        case "ask":
            guard let text = object["text"] as? String, !text.isEmpty else { return emit(["type": "error", "message": "empty question"]) }
            let tier = ArisTier.named(object["tier"] as? String)
            let task = object["task"] as? Bool == true
            let context = (object["context"] as? String).map { String($0.prefix(4_000)) } ?? ""
            let english = object["english"] as? Bool == true
            DispatchQueue.global(qos: .userInitiated).async { [self] in _ = turn(text, tier: tier, task: task, context: context, english: english) }
        case "new_conversation":
            cancel()
            lock.withLock { history = [] }
        case "cancel":
            cancel()
        default:
            break
        }
    }

    func cancel() {
        let loop = lock.withLock { () -> ArisMindLoop? in
            current = current.next()
            defer { running = nil }
            return running
        }
        loop?.cancel()
    }

    // MARK: - One turn

    /// One turn: streamed as deltas, ended with one result or error line (none for a turn a newer one took over).
    @discardableResult
    func turn(_ words: String, tier: ArisTier, task: Bool, context: String, english: Bool = false) -> ArisMindEnd {
        let (mine, before, previous) = lock.withLock { () -> (ArisTurnID, [ArisMindMessage], ArisMindLoop?) in
            current = current.next()
            return (current, history, running)
        }
        previous?.cancel()
        let isCurrent = { [self] in lock.withLock { current == mine } }
        let ports = remotePorts(task: task, isCurrent: isCurrent)
        let loop = ArisMindLoop(provider: provider(tier), tools: ArisMindSession.tools, ports: ports, budget: task ? .task : .chat)
        loop.english = ArisSkillLanguage.english(for: words, ui: english)
        lock.withLock { if current == mine { running = loop } }
        let system = context.isEmpty ? ArisMindSession.rules : ArisMindSession.rules + "\n\n" + context
        let said = ArisLocked("")
        let ended = loop.turn(system: system, history: before, owner: words) { [self] piece in
            guard isCurrent() else { return }
            switch piece {
            case .delta(let text):
                said.withLock { $0 += text }
                emit(["type": "delta", "text": text])
            case .said(let line):
                let text = "\n" + line
                said.withLock { $0 += text }
                emit(["type": "delta", "text": text])
            case .status(let text):
                emit(["type": "status", "text": text])
            }
        }
        let kept: Bool = lock.withLock {
            guard current == mine else { return false }
            running = nil
            switch ended.end {
            case .answered, .stopped: history = ArisMindSession.trimmed(ended.history)
            case .failed, .stale: break
            }
            return true
        }
        guard kept else { return .stale }
        let text = said.withLock { $0 }.trimmingCharacters(in: .whitespacesAndNewlines)
        switch ended.end {
        case .answered: emit(["type": "result", "text": text])
        case .stopped(let why): emit(["type": "result", "text": text.isEmpty ? why : text + "\n" + why])
        case .failed(let why):
            // The provider's own words stay in this process: the driver gets the kind, and Aris's own lines.
            var line: [String: Any] = ["type": "error", "message": ArisMindAPIProvider.ownLines.contains(why) ? why : ""]
            if let kind = ArisMindAPIProvider.kind(of: why) { line["kind"] = kind.rawValue }
            emit(line)
        case .stale: return .stale
        }
        return ended.end
    }

    private func emit(_ object: [String: Any]) {
        send(((try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)) + Data("\n".utf8))
    }

    // MARK: - The helper decides, this process runs

    /// How long `ask` may wait for the owner: a card's own time and a little (a job's card waits ten minutes).
    static func askWait(task: Bool) -> TimeInterval { task ? taskCardWait + 60 : ArisCardEdit.questionTimeout + 30 }
    /// A background job's card waits ten minutes (ArisAgentRunner.mcpTaskWait).
    static let taskCardWait: TimeInterval = 600

    func remotePorts(task: Bool, isCurrent: @escaping () -> Bool) -> ArisMindPorts {
        let callers = ArisLocked<[String: ArisUndoCaller]>([:])
        let passes = ArisLocked<[String: String]>([:])
        // A file call's path as the helper decided it, links followed: the run must land there.
        let paths = ArisLocked<[String: String]>([:])
        // A replace's mark of what its decision read in the field (ArisApps.TypeOver.argument).
        let erased = ArisLocked<[String: String]>([:])
        // The calls whose card nobody answered in time, as the helper said (never his no).
        let silent = ArisLocked<Set<String>>([])
        let turn = credential()
        let keep = { (line: [String: Any]) in
            guard let id = line["id"] as? String else { return }
            if let session = line["session"] as? String {
                let caller = ArisUndoCaller(session: session, provenance: line["owner"] as? Bool == true ? .ownerSaid : .ownStep,
                                            approved: line["approved"] as? Bool == true, speaker: ArisTurnSpeaker.named(line["speaker"] as? String),
                                            named: (line["undoKind"] as? String).flatMap(ArisUndoKind.init(rawValue:)),
                                            planned: (line["undoIDs"] as? [String]).map { Array($0.prefix(ArisUndoScope.mostAtOnce)) })
                callers.withLock { $0[id] = caller }
            }
            if let pass = line["pass"] as? String, ArisMindPasses.wellFormed(pass) { passes.withLock { $0[id] = pass } }
            if let path = line["resolved"] as? String, path.hasPrefix("/"), path.count <= 4_096 { paths.withLock { $0[id] = path } }
            if let mark = line["erased"] as? String, mark.count <= 200 { erased.withLock { $0[id] = mark } }
        }
        return ArisMindPorts(
            decide: { [self] calls in
                guard let turn, !calls.isEmpty else { return calls.map { ArisMindDecided(call: $0, verdict: .refuse(Self.unreachable)) } }
                let body: [String: Any] = ["op": "decide_batch", "turn": turn,
                                           "calls": calls.map { ["id": $0.id, "name": $0.name, "arguments": $0.arguments] }]
                let lines = (post(body, 30)?["verdicts"] as? [[String: Any]]) ?? []
                var byID: [String: [String: Any]] = [:]
                for line in lines { if let id = line["id"] as? String, byID[id] == nil { byID[id] = line } }
                return calls.map { call in
                    guard let line = byID[call.id] else { return ArisMindDecided(call: call, verdict: .refuse(Self.unreachable)) }
                    switch line["verdict"] as? String {
                    case "run":
                        keep(line)
                        return ArisMindDecided(call: call, verdict: .run(undo: line["undo"] as? Bool == true, announce: line["announce"] as? Bool == true))
                    case "waits": return ArisMindDecided(call: call, verdict: .waits)
                    default: return ArisMindDecided(call: call, verdict: .refuse(line["text"] as? String ?? Self.unreachable))
                    }
                }
            },
            ask: { [self] waiting in
                guard let turn else { return [] }
                let reply = post(["op": "ask", "turn": turn, "ids": waiting.map(\.call.id)], Self.askWait(task: task))
                let run = (reply?["run"] as? [[String: Any]]) ?? []
                run.forEach(keep)
                let asked = Set(waiting.map(\.call.id))
                silent.withLock { $0.formUnion(((reply?["unanswered"] as? [String]) ?? []).filter(asked.contains)) }
                return Set(run.compactMap { $0["id"] as? String }.filter(asked.contains))
            },
            execute: { [self] item in
                guard let read = read(item.call) else { return ArisMindResult(text: ArisMindJudge.badArguments, isError: true) }
                // A saved-steps call is run by the helper, by this decided call's id (ArisMindTaught).
                if read.entry.id == ArisTaughtOffer.capability, let taught = ArisMindTaught.remote {
                    return ArisMindExecutor.result(taught(item.call.id, read.arguments))
                }
                let caller = callers.withLock { $0[item.call.id] } ?? ArisUndoCaller(session: nil, provenance: .ownStep)
                let pass = passes.withLock { $0.removeValue(forKey: item.call.id) }
                // The helper's mark is the only one that counts: whatever the model wrote under that name goes.
                var arguments = read.arguments
                if read.entry.id == "app.type" {
                    arguments[ArisApps.TypeOver.argument] = erased.withLock { $0.removeValue(forKey: item.call.id) }
                }
                return executor(pass).run(read.entry, arguments: arguments, argv: read.argv, stdin: read.stdin, caller: caller,
                                          judged: ArisMindExecutor.judged(item.verdict), resolved: paths.withLock { $0.removeValue(forKey: item.call.id) })
            },
            finish: { [self] item, result, disposition in
                guard let turn, disposition == .ran || disposition == .stale else { return }
                var body: [String: Any] = ["op": "done", "turn": turn, "id": item.call.id, "text": String(result.text.prefix(20_000)), "isError": result.isError]
                if disposition == .stale { body["disposition"] = "stale" }
                if let content = result.content { body["content"] = ["kind": content.kind, "source": content.source] }
                if let undo = result.undo, let data = try? JSONEncoder().encode(undo), let object = try? JSONSerialization.jsonObject(with: data) { body["undo"] = object }
                if !result.logged.isEmpty { body["logged"] = result.logged }
                if result.framed { body["framed"] = true }
                _ = post(body, 10)
            },
            isCurrent: isCurrent,
            unanswered: { id in silent.withLock { $0.contains(id) } })
    }

    /// A call as the book reads it (as the helper's judge reads it: the same words decided are the words run).
    func read(_ call: ArisMindToolCall) -> ArisMindJudge.Read? {
        guard ArisCapabilityBook.entry(named: call.name) != nil, let arguments = call.object,
              let found = ArisHandsFace.call(function: call.name, input: arguments, tools: tools) else { return nil }
        return ArisMindJudge.Read(entry: found.entry, arguments: arguments, argv: found.argv, stdin: found.stdin)
    }

    // MARK: - The process

    static func runProcess(arguments: [String] = CommandLine.arguments) -> Never {
        // Only aris-agent's own child, for a known provider (as `api-brain`: security review C1), and only with Core 2 on.
        guard ArisCore2.isOn(), ArisAPIParent.isAgent(), let index = arguments.firstIndex(of: "--profile"), index + 1 < arguments.count,
              let profile = ArisAPIHelper.resolve(arguments[index + 1], store: ArisAPISecrets.store) else {
            FileHandle.standardError.write(Data("aris-agent mind-brain: refused (not started by Aris)\n".utf8))
            exit(2)
        }
        let out = FileHandle.standardOutput
        let lock = NSLock()
        let environment = ProcessInfo.processInfo.environment
        let tools = ArisAPIHelper.toolsPath
        ArisMindUndoHooks.live.register()
        ArisAppsTextUndoLive.install()
        // A saved-steps call is run by the helper, which holds the lessons, the owner's words and the cards (ArisMindTaught).
        ArisMindTaught.remote = ArisMindTaught.remote(
            credential: { environment[ArisMCPTurnCredential.environmentKey].flatMap { $0.hasPrefix("/") ? ArisHandsServer.credential($0) : nil }.flatMap { $0.isEmpty ? nil : $0 } },
            post: { body, wait in ArisMindRemote.livePost(body, wait: wait) })
        let brain = ArisMindBrain(
            tools: tools,
            provider: { tier in ArisMindAPIProvider(profile: profile, tier: tier, key: { ArisAPISecrets.live.secret(for: profile.id) }) },
            post: { body, wait in ArisMindRemote.livePost(body, wait: wait) },
            credential: {
                environment[ArisMCPTurnCredential.environmentKey].flatMap { $0.hasPrefix("/") ? ArisHandsServer.credential($0) : nil }.flatMap { $0.isEmpty ? nil : $0 }
            },
            executor: { pass in
                var own = ArisAPIHelper.scrubbed(environment)
                own[ArisMindPasses.environmentKey] = pass
                // The one child environment Core 2 gives what it starts (ArisMindExecutor.childEnvironment).
                let callEnvironment = ArisMindExecutor.childEnvironment(own)
                var executor = ArisMindExecutor(tools: tools, environment: ArisAPIHelper.scrubbed(environment),
                                                runTools: { argv, stdin in ArisMindBrain.runTools(tools, argv, stdin, callEnvironment) })
                executor.local = ArisCapabilityLocal.live
                executor.markedTools = { argv, stdin, mark in ArisMindBrain.runTools(tools, argv, stdin, ArisMindExecutor.marked(callEnvironment, mark)) }
                return executor
            },
            send: { data in lock.withLock { try? out.write(contentsOf: data) } })
        signal(SIGTERM, SIG_IGN)
        let terminate = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
        terminate.setEventHandler {
            brain.cancel()
            exit(0)
        }
        terminate.resume()
        var buffer = Data()
        FileHandle.standardInput.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                brain.cancel()
                exit(0)
            }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
                buffer.removeSubrange(buffer.startIndex...newline)
                brain.receive(line)
            }
            if buffer.count > 16 * 1_024 * 1_024 { exit(1) }
        }
        dispatchMain()
    }

    /// aris-tools as a child of this process (so inside the brain's tree), with each call's own time limit (as the API
    /// brain's helper gives it: ArisAPIHelper.runTools).
    static func runTools(_ tools: String, _ argv: [String], _ stdin: String?, _ environment: [String: String]) -> ArisCapabilityLocal.Output {
        let limit: TimeInterval = argv.first == "aside" ? ArisAPIHelper.asideWait : argv.first == "message" ? ArisMessageGate.sendLimit
            : argv.first == "session" ? ArisSessionSend.cardWait + 60 : ArisConvertWords.isLong(argv) ? ArisConvertWords.mediaLimit + 15
            : ArisHandsFace.callLimit
        var own = environment
        own[ArisConvertWords.deadlineKey] = String(Date().timeIntervalSince1970 + limit - 5)
        return ArisHandsServer.runTools(tools, argv, stdin, own, limit) { _ in }
    }
}
