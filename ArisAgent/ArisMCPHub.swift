//
//  ArisMCPHub.swift
//  aris-agent
//
//  The tool bus: the agent's MCP client for every service the user added, and the one gate in front of it. Brains reach it
//  only through `aris-tools mcp list` and `aris-tools mcp call` (POST /mcp-tool), from inside one of their own turns,
//  whichever brain it is; the settings page reaches it through POST /mcp (the app itself only). A call is checked
//  against the tool's schema, judged by ArisMCPPolicy, run at once, put to the read judge (a read on a careful or screen
//  turn) or put to the user as a card (a write), and its result comes back marked as outside text, every secret replaced.
//  Connections open on first use and close when idle.
//

import Foundation

/// The turn an aris-tools call belongs to, as the hub sees it (ArisAgentRunner in the agent, a fake in the tests).
protocol ArisMCPTurn: AnyObject {
    /// The brain's id ("claude", "codex", "antigravity", "api"): only for the audit line. The gate never reads it.
    var brainName: String { get }
    /// The conversation's taint right now.
    var taint: ArisTaint { get }
    var handsFree: Bool { get }
    var isTask: Bool { get }
    /// The turn carries the screen (an image of it, or "이거" text from it) or its conversation saw it: careful (its
    /// reads judged, its writes asked).
    var screen: Bool { get }
    /// Antigravity's relay ran it for a brain with no gate of its own: careful, like a job.
    var relayed: Bool { get }
    /// Outside text is about to come in (a listing or a result): the conversation is outside text from now on, and a
    /// hands-free turn's answer is shown, not spoken. Called before the server is reached.
    func takeOutsideText()
    /// Puts the user's card up; `answer` is called once (a no, a timeout or the turn ending is `.no`).
    func ask(_ card: ArisMCPCard, answer: @escaping (ArisMCPAnswer) -> Void)
    /// The read judge on this turn's brain, with the user's own words for the turn (ArisReadMemo: once per identical call);
    /// `done` is called once.
    func judgeRead(_ call: ArisReadCall, done: @escaping (ArisReadVerdict) -> Void)
    /// One quiet status line in the notch (a read the judge blocked), never a card.
    func quiet(_ status: String)
    func audit(_ fields: [String: String])
}

struct ArisMCPCard: Equatable {
    let title: String
    let detail: String
    let full: String?
    let fields: [ArisMCPCardField]
    /// The yes button's word when it isn't 허용 (Aside's 설치).
    var allow: String? = nil
    /// The user's dictated message (ArisMessageGate): sent after the countdown unless stopped, and what Aris says first.
    var countdown = false
    var spoken: String? = nil
    /// A desktop card whose yes brings this process's window forward (ArisConfirmation.desktop).
    var desktop: ArisCardTarget? = nil
    /// The automatic check's stopped card (ArisConfirmation.stopped).
    var stopped = false

    /// The card about a desktop action in `pid`'s window, named by its bundle id and start (none: no handoff).
    func aimed(pid: Int32, bundle: String?) -> ArisMCPCard {
        guard let bundle, let started = ArisProcessStart.of(pid: pid) else { return self }
        var card = self
        card.desktop = ArisCardTarget(pid: pid, bundle: bundle, started: started)
        return card
    }
}

enum ArisMCPAnswer: Equatable {
    case no
    /// The user didn't answer the card in time (its limit, or the app's): not their no.
    case unanswered
    case yes([String: String])
}

/// Why a server can't be reached, already safe to show (no secret in it).
struct ArisMCPWhy: Error, Equatable {
    let text: String
    init(_ text: String) { self.text = text }
}

/// What aris-tools prints, and its exit status.
struct ArisMCPOutcome: Equatable {
    let status: Int32
    let output: String

    static func failed(_ text: String) -> ArisMCPOutcome { ArisMCPOutcome(status: 1, output: text) }
}

final class ArisMCPHub {
    static let shared: ArisMCPHub = {
        let keychain = ArisMCPKeychain()
        return ArisMCPHub(store: ArisMCPStore(secrets: keychain), secrets: keychain)
    }()

    /// How long one tool may run, and how long a listing waits for each server.
    static let callTimeout: TimeInterval = 45
    static let listTimeout: TimeInterval = 15
    /// How long a program Aris starts may take to say hello: `npx`, `bunx` and `uvx` download the server the first
    /// time, which takes longer than a listing (audit mcp-4).
    static let startTimeout: TimeInterval = 90
    /// An unused connection closes after this.
    static let idleTimeout: TimeInterval = 600

    let store: ArisMCPStore
    let secrets: ArisMCPSecretStore
    /// This hub's idle time (the tests shorten it).
    var idleTimeout = ArisMCPHub.idleTimeout
    /// How long this hub lets one tool run (the tests shorten it).
    var callTimeout = ArisMCPHub.callTimeout
    /// Makes the transport for a server and its secret (the tests swap in their own).
    var makeTransport: (ArisMCPServer, String?) -> Result<ArisMCPTransport, ArisMCPWhy> = ArisMCPHub.liveTransport

    private struct Connection {
        let client: ArisMCPClient
        var tools: [ArisMCPTool]
        var idle: DispatchWorkItem?
    }
    private let lock = NSLock()
    private var connections: [String: Connection] = [:]
    /// One connect at a time per server.
    private var connecting: [String: NSLock] = [:]
    /// What the last listing or test found, for the settings rows (no connection needed to show them).
    private var lastTools: [String: [ArisMCPTool]] = [:]
    private var lastError: [String: String] = [:]
    private let idleQueue = DispatchQueue(label: "com.lumenjsn.aris.mcp.idle")

    init(store: ArisMCPStore, secrets: ArisMCPSecretStore) {
        self.store = store
        self.secrets = secrets
    }

    // MARK: - Transports

    static func liveTransport(_ server: ArisMCPServer, _ secret: String?) -> Result<ArisMCPTransport, ArisMCPWhy> {
        switch server.transport {
        case .http:
            guard let text = server.url, case .success = ArisMCPTarget.checkURL(text), let url = URL(string: text) else { return .failure(ArisMCPWhy("the URL isn't usable")) }
            return .success(ArisMCPHTTP(url: url, headers: headers(server, secret)))
        case .stdio:
            guard let command = server.command, let program = ArisMCPStdio.resolve(command, path: ArisMCPStdio.searchPath) else {
                return .failure(ArisMCPWhy("couldn't find the program \(server.command ?? "")"))
            }
            return .success(ArisMCPStdio(executable: program, arguments: server.arguments, environment: ArisMCPStdio.environment(extra: environment(server, secret))))
        }
    }

    /// The secret's header: the one named, or "Authorization: Bearer …".
    static func headers(_ server: ArisMCPServer, _ secret: String?) -> [String: String] {
        guard let secret else { return [:] }
        guard let name = server.secretName else { return ["Authorization": "Bearer " + secret] }
        return [name: secret]
    }

    /// The secret's variable for a command, when one is named.
    static func environment(_ server: ArisMCPServer, _ secret: String?) -> [String: String] {
        guard let secret, let name = server.secretName else { return [:] }
        return [name: secret]
    }

    // MARK: - Settings (the app only)

    func servers() -> [ArisMCPServer] { store.load() }

    /// Adds or changes a server. `secret`: a new key or token (nil keeps the saved one; "" removes it).
    func save(id: String?, name: String, target: String, secretName: String?, secret: String?, enabled: Bool = true) -> Result<ArisMCPServer, ArisMCPConfigError> {
        let checkedSecret: String??
        switch secret {
        case nil: checkedSecret = .none
        case ""?: checkedSecret = .some(nil)
        case let raw?:
            switch ArisMCPConfig.checkSecret(raw) {
            case .failure(let error): return .failure(error)
            case .success(let value): checkedSecret = .some(value)
            }
        }
        let result = store.update { servers -> Result<ArisMCPServer, ArisMCPConfigError> in
            let serverId = id ?? ArisMCPConfig.newId()
            guard ArisMCPConfig.isId(serverId), serverId != ArisMCPServer.composioId else { return .failure(.missing) }
            let old = servers.first { $0.id == serverId }
            guard id == nil || old != nil else { return .failure(.missing) }
            guard old != nil || servers.count < ArisMCPConfig.maxServers else { return .failure(.full) }
            let hasSecret: Bool
            switch checkedSecret {
            case .none: hasSecret = old?.hasSecret ?? false
            case .some(let value): hasSecret = value != nil
            }
            let made = ArisMCPConfig.server(id: serverId, name: name, target: target, secretName: secretName, hasSecret: hasSecret,
                                            enabled: enabled, existing: servers)
            guard case .success(let server) = made else { return made }
            if case .some(let value) = checkedSecret {
                if let value {
                    if let problem = secrets.save(value, for: serverId) { return .failure(.secret(problem)) }
                } else {
                    secrets.delete(serverId)
                }
            }
            servers.removeAll { $0.id == serverId }
            servers.append(server)
            return .success(server)
        }
        if case .success(let server) = result { disconnect(server.id) }
        return result
    }

    /// The user's Composio key: saved (and the Composio server added or turned back on), or removed with it (nil).
    func setComposio(key: String?) -> Result<Void, ArisMCPConfigError> {
        if let key {
            let checked: String
            switch ArisMCPConfig.checkSecret(key) {
            case .failure(let error): return .failure(error)
            case .success(let value): checked = value
            }
            let result = store.update { servers -> Result<Void, ArisMCPConfigError> in
                guard servers.contains(where: { $0.id == ArisMCPServer.composioId }) || servers.count < ArisMCPConfig.maxServers else { return .failure(.full) }
                if let problem = secrets.save(checked, for: ArisMCPServer.composioId) { return .failure(.secret(problem)) }
                servers.removeAll { $0.id == ArisMCPServer.composioId }
                servers.insert(.composio(), at: 0)
                return .success(())
            }
            disconnect(ArisMCPServer.composioId)
            return result
        }
        return remove(ArisMCPServer.composioId)
    }

    /// Removes a server and its secret.
    func remove(_ id: String) -> Result<Void, ArisMCPConfigError> {
        let result = store.update { servers -> Result<Void, ArisMCPConfigError> in
            guard servers.contains(where: { $0.id == id }) else { return .failure(.missing) }
            servers.removeAll { $0.id == id }
            return .success(())
        }
        // The secret goes even when the list had no entry for it (nothing is left behind).
        if ArisMCPConfig.isId(id) { secrets.delete(id) }
        disconnect(id)
        lock.withLock {
            lastTools[id] = nil
            lastError[id] = nil
        }
        return result
    }

    func setEnabled(_ id: String, _ on: Bool) -> Result<Void, ArisMCPConfigError> {
        let result = store.update { servers -> Result<Void, ArisMCPConfigError> in
            guard let index = servers.firstIndex(where: { $0.id == id }) else { return .failure(.missing) }
            servers[index].enabled = on
            return .success(())
        }
        if !on { disconnect(id) }
        return result
    }

    /// Connects afresh and lists the tools: (true, a line) or (false, why). Blocks.
    func test(_ id: String) -> (ok: Bool, message: String) {
        guard let server = servers().first(where: { $0.id == id }) else { return (false, ArisMCPConfigError.missing.message) }
        disconnect(id)
        switch connection(server) {
        case .failure(let why):
            // The settings row's text: the reason in the user's words, with what the server itself said (never a brain's).
            return (false, "연결하지 못했어요: \(lock.withLock { lastError[id] } ?? Self.reasonLine(why.text, stdio: server.transport == .stdio))")
        case .success(let tools):
            let reads = tools.filter { ArisMCPPolicy.listedKind($0, composio: server.id == ArisMCPServer.composioId) == .read }.count
            return (true, "연결됐어요. 도구 \(tools.count)개 (읽기 \(reads)개, 나머지는 할 때마다 물어봐요).")
        }
    }

    /// The settings rows: each server with what the last connection found (no secret, ever).
    func settingsList() -> [[String: Any]] {
        let (known, errors) = lock.withLock { (lastTools, lastError) }
        return servers().map { server in
            var row: [String: Any] = ["id": server.id, "name": server.name, "transport": server.transport.rawValue,
                                      "target": server.target, "edit": ArisMCPStore.targetText(server), "enabled": server.enabled,
                                      "hasSecret": server.hasSecret, "composio": server.id == ArisMCPServer.composioId]
            if let name = server.secretName { row["secretName"] = name }
            if let tools = known[server.id] {
                let composio = server.id == ArisMCPServer.composioId
                row["tools"] = tools.map { ["name": $0.name, "kind": ArisMCPPolicy.listedKind($0, composio: composio).rawValue] }
            }
            if let error = errors[server.id] { row["error"] = error }
            return row
        }
    }

    // MARK: - Connections

    /// Every secret saved, to replace in anything a brain or a log could see.
    private func allSecrets() -> [String] {
        servers().filter(\.hasSecret).compactMap { secrets.secret(for: $0.id) }
    }

    private func gate(for id: String) -> NSLock {
        lock.withLock {
            if let existing = connecting[id] { return existing }
            let made = NSLock()
            connecting[id] = made
            return made
        }
    }

    /// The server's tools, connecting first when needed. Why not, redacted.
    private func connection(_ server: ArisMCPServer) -> Result<[ArisMCPTool], ArisMCPWhy> {
        let serverLock = gate(for: server.id)
        serverLock.lock()
        defer { serverLock.unlock() }
        if let live = lock.withLock({ connections[server.id] }), !live.client.isClosed {
            touch(server.id)
            return .success(live.tools)
        }
        let looked = server.hasSecret ? secrets.lookup(server.id) : .missing
        if server.hasSecret, looked == .unreadable { return remember(server.id, error: "키체인을 읽지 못했어요. Mac의 잠금을 풀거나 키체인 접근을 허용한 뒤 다시 해 주세요.") }
        let secret: String? = { if case .found(let saved) = looked { return saved } else { return nil } }()
        if server.hasSecret, secret == nil { return remember(server.id, error: "키체인에서 키를 찾지 못했어요. 설정에서 다시 넣어 주세요.") }
        let transport: ArisMCPTransport
        switch makeTransport(server, secret) {
        case .failure(let why): return remember(server.id, error: why.text, shown: Self.reasonLine(why.text, stdio: server.transport == .stdio))
        case .success(let made): transport = made
        }
        let client = ArisMCPClient(transport: transport)
        let stdio = server.transport == .stdio
        let failed = { [self] (error: ArisMCPError) -> Result<[ArisMCPTool], ArisMCPWhy> in
            client.close()
            let own = [secret].compactMap { $0 }
            return remember(server.id, error: ArisMCPPolicy.redacted(error.message, secrets: own),
                            shown: ArisMCPPolicy.redacted(Self.reasonLine(error.message, stdio: stdio, said: client.diagnostics), secrets: own))
        }
        if let error = client.connect(timeout: stdio ? Self.startTimeout : Self.listTimeout) { return failed(error) }
        switch client.listTools(timeout: Self.listTimeout) {
        case .failure(let error): return failed(error)
        case .success(let tools):
            // Heard on the transport's own queue, which closing it waits for: closed from elsewhere, and listed afresh next time.
            // Only this connection's own notice closes it (M6): a stale one's can't close a newer connection.
            client.onToolsChanged = { [weak self, weak client] in
                DispatchQueue.global().async {
                    guard let self, let client else { return }
                    self.disconnect(server.id, only: client)
                }
            }
            // A dead connection this one replaces: its idle clock stops (it would close this one) and its client is
            // closed (an HTTP session would leak otherwise).
            let replaced = lock.withLock { () -> Connection? in
                let old = connections[server.id]
                connections[server.id] = Connection(client: client, tools: tools, idle: nil)
                lastTools[server.id] = tools
                lastError[server.id] = nil
                return old
            }
            replaced?.idle?.cancel()
            replaced?.client.close()
            touch(server.id)
            return .success(tools)
        }
    }

    /// `error` is what a brain is told; `shown` (else `error`) is the settings row's and 연결 테스트's line.
    private func remember(_ id: String, error: String, shown: String? = nil) -> Result<[ArisMCPTool], ArisMCPWhy> {
        lock.withLock { lastError[id] = shown ?? error }
        return .failure(ArisMCPWhy(error))
    }

    /// The most of a server's own words shown with a failure.
    static let maxSaid = 300

    /// Why a connection failed, for the user: the usual reasons in Korean with what they can do, then the server's own last
    /// words (`said`, its stderr: a missing token variable, a wrong argument), so he can tell what to fix
    /// (audit imp-mcp-test). Anything else is passed on as it is.
    static func reasonLine(_ why: String, stdio: Bool, said: String = "") -> String {
        var line = why
        if why == ArisMCPError.timeout.message {
            line = stdio ? "서버가 제때 답하지 않았어요. 처음이면 프로그램을 내려받느라 오래 걸릴 수 있어요. 한 번 더 해 보세요." : "서버가 제때 답하지 않았어요."
        } else if why.hasPrefix("couldn't find the program ") {
            line = "‘\(why.dropFirst("couldn't find the program ".count))’ 프로그램을 찾지 못했어요. 터미널에서 그 이름으로 실행되는지 확인해 주세요."
        } else if why.range(of: #"^the server ended \(status -?\d+\)$"#, options: .regularExpression) != nil {
            line = "서버 프로그램이 바로 끝났어요 (상태 \(why.filter { $0.isNumber || $0 == "-" }))."
        } else if why == "the server closed its output" || why == "the server closed the connection" {
            line = "서버가 연결을 끊었어요."
        }
        let words = ArisMCPPolicy.clean(said, limit: nil, keepNewlines: true).split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.suffix(4).joined(separator: " / ")
        return words.isEmpty ? line : line + " 서버가 남긴 말: " + String(words.suffix(maxSaid))
    }

    /// Restarts the idle clock for a connection. The clock closes only the connection it was started for.
    private func touch(_ id: String) {
        let item = lock.withLock { () -> DispatchWorkItem? in
            guard let client = connections[id]?.client else { return nil }
            let item = DispatchWorkItem { [weak self, weak client] in
                guard let self, let client else { return }
                self.disconnect(id, only: client)
            }
            connections[id]?.idle?.cancel()
            connections[id]?.idle = item
            return item
        }
        if let item { idleQueue.asyncAfter(deadline: .now() + idleTimeout, execute: item) }
    }

    func disconnect(_ id: String, only client: ArisMCPClient? = nil) {
        let old = lock.withLock { () -> Connection? in
            if let client, connections[id]?.client !== client { return nil }
            return connections.removeValue(forKey: id)
        }
        old?.idle?.cancel()
        old?.client.close()
    }

    func disconnectAll() {
        let ids = lock.withLock { Array(connections.keys) }
        ids.forEach { disconnect($0) }
    }

    // MARK: - Brains (aris-tools mcp …)

    static let tamperedLine = "서비스 목록 파일이 Aris 밖에서 바뀌어서 아무 서버도 켜지 않았어요. 서비스를 다시 추가하면 새로 저장돼요."
    /// The Keychain couldn't be read: nothing was changed, and nothing needs adding again (audit mcp-3).
    static let unreadableLine = "키체인을 읽지 못해서 서비스를 켜지 못했어요. 서비스 목록과 키는 그대로예요. Mac의 잠금을 풀거나 키체인 접근을 허용하면 다시 돼요."

    /// What the settings page is told about the list, if anything is wrong with it.
    var listProblem: String? { store.tampered ? Self.tamperedLine : store.unreadable ? Self.unreadableLine : nil }

    static let usage = "usage: aris-tools mcp list [service] | aris-tools mcp call <service> <tool> '<json arguments>' (or key=value …)"

    /// `aris-tools mcp list [service]`: each service's tools, what each needs, and whether it asks the user. Outside text.
    func listing(only: String? = nil, turn: ArisMCPTurn) -> ArisMCPOutcome {
        let enabled = servers().filter(\.enabled)
        guard !enabled.isEmpty else {
            ArisFixTurns.shared.note(.settings(.services))
            return ArisMCPOutcome(status: 0, output: "No external services are connected. the user adds them in 설정 › AI 서비스 › 연결된 서비스.")
        }
        let chosen = only.map { name in enabled.filter { $0.name == name.lowercased() } } ?? enabled
        guard !chosen.isEmpty else { return .failed("no connected service named \(only ?? ""). Services: " + enabled.map(\.name).joined(separator: ", ")) }
        turn.takeOutsideText()
        turn.audit(["answer": "mcp list", "brain": turn.brainName])
        var found = [String: Result<[ArisMCPTool], ArisMCPWhy>]()
        let group = DispatchGroup(), results = NSLock()
        for server in chosen {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let tools = self.connection(server)
                results.withLock { found[server.id] = tools }
                group.leave()
            }
        }
        // One slow server can't hold the whole listing (M7).
        _ = group.wait(timeout: .now() + Self.listTimeout * 2 + 5)
        let text = chosen.map { server in
            switch results.withLock({ found[server.id] }) ?? .failure(ArisMCPWhy("no answer in time")) {
            case .failure(let why): return "\(server.name): couldn't connect (\(why.text))"
            case .success(let tools): return Self.describe(server: server, tools: tools, detailed: only != nil)
            }
        }.joined(separator: "\n")
        let body = ArisMCPPolicy.wrapped(text, server: "the services' own tool lists", tool: "names and descriptions", secrets: allSecrets(), isError: false)
        return ArisMCPOutcome(status: 0, output: body + "\nCall one with: aris-tools mcp call <service> <tool> '<json arguments>'. "
                              + "Reads run at once (on a careful turn after Aris's quick check); anything else shows the user a card and waits for their yes.")
    }

    static func describe(server: ArisMCPServer, tools: [ArisMCPTool], detailed: Bool) -> String {
        let lines = tools.map { tool -> String in
            let kind: String
            switch ArisMCPPolicy.listedKind(tool, composio: server.id == ArisMCPServer.composioId) {
            case .read: kind = "read"
            case .write: kind = "asks the user"
            case .unknown: kind = server.id == ArisMCPServer.composioId && tool.name == ArisMCPPolicy.composioExecute
                ? "read if every tool it runs only reads, else asks the user (at most one write per call)" : "asks the user"
            }
            let description = ArisMCPPolicy.clean(tool.description, limit: detailed ? 600 : 160)
            return "  \(tool.name) [\(kind)]" + (description.isEmpty ? "" : " — \(description)") + "\n    args: " + arguments(tool.inputSchema)
        }
        return "\(server.name):\n" + (lines.isEmpty ? "  (no tools)" : lines.joined(separator: "\n"))
    }

    /// "subject (string, required), to (string)…", or "none".
    static func arguments(_ schema: [String: Any]) -> String {
        let properties = schema["properties"] as? [String: Any] ?? [:]
        let required = Set(schema["required"] as? [String] ?? [])
        guard !properties.isEmpty else { return "none" }
        return properties.keys.sorted().prefix(20).map { key in
            let type = ((properties[key] as? [String: Any])?["type"] as? String) ?? "any"
            return ArisMCPPolicy.clean(key, limit: 40) + " (\(ArisMCPPolicy.clean(type, limit: 12))\(required.contains(key) ? ", required" : ""))"
        }.joined(separator: ", ") + (properties.count > 20 ? ", …" : "")
    }

    /// The arguments as aris-tools sent them: one JSON object, or key=value words read by the schema.
    enum Arguments {
        case json(String)
        case pairs([String])
    }

    /// `aris-tools mcp call <service> <tool> …`: checked, judged, run or asked; `done` gets what aris-tools prints.
    /// Blocks its caller (never the agent's server queue) until the answer.
    func call(service: String, tool name: String, arguments raw: Arguments, turn: ArisMCPTurn, done: @escaping (ArisMCPOutcome) -> Void) {
        guard let server = servers().first(where: { $0.name == service.lowercased() && $0.enabled }) else {
            return done(.failed("no connected service named \(service). See: aris-tools mcp list"))
        }
        // The brain wrote this call before anything the server says now: the gate judges it by the taint as it was
        // (M8: no driver marks an mcp command itself; only the hub does, below).
        let taintBefore = turn.taint
        // Whatever the server says from here on (a tool list, an error, a result) is outside text.
        turn.takeOutsideText()
        let tools: [ArisMCPTool]
        switch connection(server) {
        case .failure(let why): return done(.failed("\(server.name): couldn't connect (\(why.text))"))
        case .success(let found): tools = found
        }
        guard let tool = tools.first(where: { $0.name == name }) else {
            return done(.failed("\(server.name) has no tool named \(ArisMCPPolicy.clean(name, limit: 80)). See: aris-tools mcp list \(server.name)"))
        }
        let arguments: [String: Any]
        switch raw {
        case .json(let text):
            guard text.utf8.count <= ArisMCPSchema.maxArgumentBytes,
                  let object = (try? JSONSerialization.jsonObject(with: Data((text.isEmpty ? "{}" : text).utf8))) as? [String: Any] else {
                return done(.failed("the arguments must be one JSON object, like '{\"query\": \"…\"}'"))
            }
            arguments = object
        case .pairs(let words):
            guard let object = ArisMCPSchema.pairs(words, schema: tool.inputSchema) else {
                return done(.failed("each argument must be key=value, with a value of the field's type"))
            }
            arguments = object
        }
        if let problem = ArisMCPSchema.problem(arguments, schema: tool.inputSchema) {
            return done(.failed("the arguments don't fit \(tool.name): \(ArisMCPPolicy.clean(problem, limit: 200)). See: aris-tools mcp list \(server.name)"))
        }
        let composio = server.id == ArisMCPServer.composioId
        let kind = ArisMCPPolicy.kind(of: tool, arguments: arguments, composio: composio)
        let context = ArisMCPPolicy.Context(taint: taintBefore, screen: turn.screen, handsFree: turn.handsFree, job: turn.isTask, relayed: turn.relayed)
        let decision = ArisMCPPolicy.decide(kind: kind, arguments: arguments, context: context, composio: composio, tool: tool.name)
        let what = "\(server.name) \(tool.name)"
        switch decision {
        case .refuse(let why):
            turn.audit(["answer": "refused (\(why))", "action": what, "brain": turn.brainName])
            done(.failed(why))
        case .run:
            turn.audit(["answer": "ran (\(kind.rawValue))", "action": what, "brain": turn.brainName])
            done(run(server: server, tool: tool, arguments: arguments))
        case .judge:
            turn.judgeRead(ArisReadGate.call(service: server.name, tool: tool.name, arguments: arguments)) { [weak self] verdict in
                // Off whatever queue the judge answered on: running the call blocks.
                DispatchQueue.global(qos: .userInitiated).async {
                    guard let self else { return done(.failed(ArisReadGate.refusal(.undecided))) }
                    // The judge's own words go to the audit log only (I5); the brain and the notch get fixed lines.
                    guard verdict.allowed else {
                        let why = verdict.why ?? .other
                        turn.audit(["answer": "refused by the read judge (\(why.rawValue))", "note": verdict.note, "action": what, "brain": turn.brainName])
                        turn.quiet(ArisReadGate.status(why))
                        return done(.failed(ArisReadGate.refusal(why)))
                    }
                    turn.audit(["answer": "ran (read, the judge allowed)", "note": verdict.note, "action": what, "brain": turn.brainName])
                    done(self.run(server: server, tool: tool, arguments: arguments))
                }
            }
        case .ask(let reason):
            ask(server: server, tool: tool, arguments: arguments, reason: reason, careful: context.careful, turn: turn, done: done)
        }
    }

    /// The user's card; a yes runs the call (with their changes, checked again), a no tells the brain they said no.
    /// `careful`: the card shows every argument whole (C2), not cut.
    private func ask(server: ArisMCPServer, tool: ArisMCPTool, arguments: [String: Any], reason: String?, careful: Bool, turn: ArisMCPTurn,
                     done: @escaping (ArisMCPOutcome) -> Void) {
        let fields = ArisMCPPolicy.fields(tool: tool, arguments: arguments, composio: server.id == ArisMCPServer.composioId)
        let short = ArisMCPPolicy.detail(reason: reason, arguments: arguments, fields: fields, limit: careful ? nil : 400)
        let full = ArisMCPPolicy.detail(reason: reason, arguments: arguments, fields: fields, limit: nil)
        let card = ArisMCPCard(title: ArisMCPPolicy.title(server: server.name, tool: tool, arguments: arguments),
                               detail: ArisMCPPolicy.redacted(short, secrets: allSecrets()),
                               full: full == short ? nil : ArisMCPPolicy.redacted(full, secrets: allSecrets()), fields: fields)
        turn.ask(card) { [weak self] answer in
            // Off whatever queue the answer came on (the agent's server queue, a runner's): the rest may block.
            DispatchQueue.global(qos: .userInitiated).async { self?.answered(answer, server: server, tool: tool, arguments: arguments, fields: fields, turn: turn, done: done) }
        }
    }

    private func answered(_ answer: ArisMCPAnswer, server: ArisMCPServer, tool: ArisMCPTool, arguments: [String: Any], fields: [ArisMCPCardField],
                          turn: ArisMCPTurn, done: @escaping (ArisMCPOutcome) -> Void) {
        let what = "\(server.name) \(tool.name)"
        guard case .yes(let edits) = answer else {
            turn.audit(["answer": "no", "action": what, "brain": turn.brainName])
            return done(.failed("the user said no (or didn't answer), so \(tool.name) didn't run. Don't try it another way now. A later request in a new turn gets a new card."))
        }
        switch ArisMCPPolicy.verdict(edits: edits, fields: fields, tool: tool, arguments: arguments) {
        case .refuse(let why):
            turn.audit(["answer": "refused (\(why))", "action": what, "brain": turn.brainName])
            done(.failed(why))
        case .reask(let why):
            turn.audit(["answer": "asked again (\(why))", "action": what, "brain": turn.brainName])
            var changed = arguments
            for (key, value) in edits { changed[key] = value }
            ask(server: server, tool: tool, arguments: changed, reason: why, careful: true, turn: turn, done: done)
        case .run(let applied):
            var changed = arguments
            for (key, value) in applied { changed[key] = value }
            turn.audit(["answer": applied.isEmpty ? "yes" : "yes, changed on the card", "action": what, "brain": turn.brainName])
            var outcome = run(server: server, tool: tool, arguments: changed)
            if !applied.isEmpty, outcome.status == 0 {
                outcome = ArisMCPOutcome(status: 0, output: "the user changed " + applied.keys.sorted().joined(separator: ", ")
                                         + " on the card before saying yes; this ran with their values.\n" + outcome.output)
            }
            done(outcome)
        }
    }

    private func run(server: ArisMCPServer, tool: ArisMCPTool, arguments: [String: Any]) -> ArisMCPOutcome {
        guard let client = lock.withLock({ connections[server.id]?.client }), !client.isClosed else {
            guard case .success = connection(server), let again = lock.withLock({ connections[server.id]?.client }) else {
                return .failed("\(server.name): the connection closed")
            }
            return finish(again.call(tool.name, arguments: arguments, timeout: callTimeout), server: server, tool: tool, client: again)
        }
        touch(server.id)
        return finish(client.call(tool.name, arguments: arguments, timeout: callTimeout), server: server, tool: tool, client: client)
    }

    private func finish(_ result: Result<ArisMCPCallResult, ArisMCPError>, server: ArisMCPServer, tool: ArisMCPTool,
                        client: ArisMCPClient) -> ArisMCPOutcome {
        switch result {
        case .failure(let error):
            // A server that didn't answer is hung: its connection goes, so the next call starts afresh instead of
            // waiting the whole limit on it again (audit imp-mcp-test).
            if error == .timeout { disconnect(server.id, only: client) }
            return .failed("\(server.name) \(tool.name) failed: " + ArisMCPPolicy.redacted(error.message, secrets: allSecrets()))
        case .success(let answer):
            return ArisMCPOutcome(status: answer.isError ? 1 : 0,
                                  output: ArisMCPPolicy.wrapped(answer.text, server: server.name, tool: tool.name, secrets: allSecrets(), isError: answer.isError))
        }
    }
}
