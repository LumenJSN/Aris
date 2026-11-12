// Tests for the API brains (cleanroom spec 14, phase 1): presets and the signed profile store, the Keychain-only key and
// its redaction, the three wire formats against local fake servers (SSE streaming, tool calls, errors, 429s, malformed
// and cut streams, cancellation, time limits), the function catalog and its argv ⇄ command round trip, and every gate
// path on the API brain mirrored against the Codex driver. No real API call and no real key: every server is on
// 127.0.0.1 in this process.
import AppKit
import Foundation
import Network

// MARK: - A fake provider

/// One scripted answer: a status, headers, and the body in pieces (each sent after its delay); `hang`: never answer.
struct FakeReply {
    var status = 200
    var type = "text/event-stream"
    var headers: [String: String] = [:]
    var chunks: [(String, Double)] = []
    var hang = false

    static func sse(_ events: [String], delay: Double = 0) -> FakeReply {
        FakeReply(chunks: events.map { ("data: \($0)\n\n", delay) })
    }

    static func named(_ events: [(String, String)], delay: Double = 0) -> FakeReply {
        FakeReply(chunks: events.map { ("event: \($0.0)\ndata: \($0.1)\n\n", delay) })
    }

    static func json(_ status: Int, _ body: String, headers: [String: String] = [:]) -> FakeReply {
        FakeReply(status: status, type: "application/json", headers: headers, chunks: [(body, 0)])
    }
}

/// A provider on 127.0.0.1: answers each request with the next scripted reply and keeps every request.
final class FakeAPIServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "fake-api")
    private let lock = NSLock()
    private var replies: [FakeReply]
    private var seen: [HTTPRequest] = []
    private var open: [NWConnection] = []
    private(set) var port: UInt16 = 0

    init(_ replies: [FakeReply]) {
        self.replies = replies
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: 0)
        listener = try! NWListener(using: parameters)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in if case .ready = state { ready.signal() } }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
        _ = ready.wait(timeout: .now() + 5)
        port = listener.port?.rawValue ?? 0
    }

    var base: String { "http://127.0.0.1:\(port)/v1" }

    var requests: [HTTPRequest] { lock.withLock { seen } }

    func body(_ index: Int) -> [String: Any] {
        let all = requests
        guard index < all.count else { return [:] }
        return (try? JSONSerialization.jsonObject(with: all[index].body)) as? [String: Any] ?? [:]
    }

    func stop() {
        listener.cancel()
        lock.withLock { open }.forEach { $0.cancel() }
    }

    private func accept(_ connection: NWConnection) {
        lock.withLock { open.append(connection) }
        connection.start(queue: queue)
        read(connection, Data())
    }

    private func read(_ connection: NWConnection, _ buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, done, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            switch HTTPRequestParser.parse(buffer, limit: { _, _, _ in HTTPRequestParser.askBytes }) {
            case .complete(let request): self.answer(connection, request)
            case .incomplete where !done && error == nil: self.read(connection, buffer)
            default: connection.cancel()
            }
        }
    }

    private func answer(_ connection: NWConnection, _ request: HTTPRequest) {
        let reply: FakeReply = lock.withLock {
            seen.append(request)
            return replies.isEmpty ? FakeReply.json(500, #"{"error":{"message":"no more scripted replies"}}"#) : replies.removeFirst()
        }
        guard !reply.hang else { return }
        let reason = reply.status == 200 ? "OK" : "Error"
        var head = "HTTP/1.1 \(reply.status) \(reason)\r\nContent-Type: \(reply.type)\r\nConnection: close\r\n"
        for (name, value) in reply.headers { head += "\(name): \(value)\r\n" }
        connection.send(content: Data((head + "\r\n").utf8), completion: .contentProcessed { _ in })
        var at = 0.0
        for (chunk, delay) in reply.chunks {
            at += delay
            queue.asyncAfter(deadline: .now() + at) { connection.send(content: Data(chunk.utf8), completion: .contentProcessed { _ in }) }
        }
        queue.asyncAfter(deadline: .now() + at + 0.02) {
            connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}

// MARK: - The helper and the driver, wired as the runner wires them

/// The helper's lines go to the driver (on a queue of their own, as the runner's), the driver's answers back to the
/// helper; cards are answered by `answer`, and every other event is kept.
final class APIWire: @unchecked Sendable {
    let driver: ArisAPIDriver
    var helper: ArisAPIHelper!
    private let queue = DispatchQueue(label: "api-wire")
    private let lock = NSLock()
    private var kept: [ArisBrainEvent] = []
    private var lines: [String] = []
    private var ranArgv: [[String]] = []
    private let ended = DispatchSemaphore(value: 0)
    /// What the user (or the judge) says to a card: "yes", "no", "judge-yes", "judge-no".
    var answer: (ArisConfirmation, ArisPendingAction?) -> String = { _, _ in "yes" }

    init(driver: ArisAPIDriver, key: String? = "sk-test-SECRETKEY123456", output: String = "OK done") {
        self.driver = driver
        helper = ArisAPIHelper(profile: driver.profile!, tools: apiTools, strictOrigin: false, testServer: driver.profile?.baseURL,
                               send: { [weak self] data in self?.fromHelper(data) }, key: { _ in key },
                               run: { [weak self] _, argv, done in
            self?.lock.withLock { self?.ranArgv.append(argv) }
            DispatchQueue.global().async { done(0, output) }
        })
        for line in driver.opening() { helper.receive(String(decoding: line, as: UTF8.self)) }
    }

    var events: [ArisBrainEvent] { lock.withLock { kept } }
    var rawLines: [String] { lock.withLock { lines } }
    var ran: [[String]] { lock.withLock { ranArgv } }

    func ask(_ prompt: String, tier: ArisTier = .quick, images: [ArisTurnImage] = []) {
        queue.sync {
            let opened = driver.ask(prompt, images: images, tier: tier)
            for line in opened { helper.receive(String(decoding: line, as: UTF8.self)) }
        }
    }

    /// Waits for the turn's last event (an answer, a failure, a stop).
    @discardableResult func wait(_ seconds: Double = 8) -> Bool { ended.wait(timeout: .now() + seconds) == .success }

    private func fromHelper(_ data: Data) {
        let line = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines)
        queue.async { [self] in
            lock.withLock { lines.append(line) }
            for event in driver.read(line) { handle(event) }
        }
    }

    private func send(_ lines: [Data]) { for line in lines { helper.receive(String(decoding: line, as: UTF8.self)) } }

    private func handle(_ event: ArisBrainEvent) {
        lock.withLock { kept.append(event) }
        switch event {
        case .send(let data): send([data])
        case .confirm(let card):
            let pending = driver.escalation(for: card.id)
            switch answer(card, pending) {
            case "judge-yes": send(driver.approveOnce(card.id))
            case "judge-no": send(driver.refuseRead(card.id, note: ArisReadGate.refusal(.privateData)))
            case "edited": send(driver.declineEdited(card.id, arguments: ["message", "엄마", "고친 말"], note: "Aris sent the user's changed version itself."))
            case "yes": send(driver.decide(card.id, allow: true))
            default: send(driver.decide(card.id, allow: false))
            }
        case .result, .failure, .unavailable, .abort: ended.signal()
        default: break
        }
    }

    var answerText: String? {
        events.compactMap { if case .result(let text) = $0 { return text } else { return nil } }.last
    }
    var deltas: [String] { events.compactMap { if case .delta(let text) = $0 { return text } else { return nil } } }
    var cards: [ArisConfirmation] { events.compactMap { if case .confirm(let card) = $0 { return card } else { return nil } } }
}

private let apiTools = "/Users/me/.config/aris/aris-tools"

/// Lines gathered across threads.
final class ArisCancelFlagList: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func add(_ line: String) { lock.withLock { lines.append(line) } }
    var all: [String] { lock.withLock { lines } }
}

private func apiProfile(_ id: String, base: String, vision: Bool? = nil, tools: Bool? = nil) -> ArisAPIProfile {
    let preset = ArisAPIPreset.named(id)!
    return ArisAPIProfile(id: id, quick: preset.quick.isEmpty ? "local-model" : preset.quick, strong: preset.strong.isEmpty ? "local-model" : preset.strong,
                          baseURL: base, vision: vision, tools: tools)
}

private func apiDriver(_ id: String = "openai", base: String = "http://127.0.0.1:1/v1", sealed: Bool = false, handsFree: Bool = false,
                       task: Bool = false, vision: Bool? = nil, tools: Bool? = nil) -> ArisAPIDriver {
    ArisAPIDriver(profile: apiProfile(id, base: base, vision: vision, tools: tools), tools: apiTools, sealed: sealed, task: task, handsFree: handsFree,
                  home: "/Users/me", executable: URL(fileURLWithPath: "/usr/bin/true"))
}

private func object(_ data: Data) -> [String: Any] { (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:] }

private func sends(_ events: [ArisBrainEvent]) -> [[String: Any]] {
    events.compactMap { if case .send(let data) = $0 { return object(data) } else { return nil } }
}

private func toolRequest(_ id: String, _ name: String, _ arguments: [String: Any], round: Int = 1) -> String {
    let line: [String: Any] = ["type": "tool_request", "id": id, "name": name, "arguments": ArisAPIDialects.jsonText(arguments), "round": round]
    return String(decoding: try! JSONSerialization.data(withJSONObject: line), as: UTF8.self)
}

private func chatChunk(_ delta: [String: Any], finish: String? = nil) -> String {
    ArisAPIDialects.jsonText(["choices": [["index": 0, "delta": delta, "finish_reason": finish.map { $0 as Any } ?? NSNull()]]])
}

func runAPIBrainTests() {
    runAPIPureTests()
    runAPIDialectTests()
    runAPIStoreTests()
    runAPICatalogTests()
    runAPIGateParityTests()
    runAPIDriverTests()
    runAPIWireTests()
    runAPIJudgeAndSmokeTests()
    runAPIRoutingTests()
}

// MARK: - SSE, errors, redaction

private func runAPIPureTests() {
    var parser = ArisSSEParser()
    var events = parser.feed(Data("data: {\"a\"".utf8))
    events += parser.feed(Data(":1}\r\n\r\n: comment\n".utf8))
    events += parser.feed(Data("event: message_start\ndata: x\ndata: y\n\nid: 3\ndata: [DONE]".utf8))
    events += parser.finish()
    check(events == [ArisSSEEvent(name: "", data: #"{"a":1}"#), ArisSSEEvent(name: "message_start", data: "x\ny"), ArisSSEEvent(name: "", data: "[DONE]")],
          "api sse: lines split anywhere, \\r\\n, comments, multi-line data, an event at the end without its blank line")

    check(ArisAPIError.http(status: 401, body: Data(#"{"error":{"message":"Invalid API key"}}"#.utf8), headers: [:]).kind == .auth,
          "api errors: 401 is a bad key")
    let now = Date(timeIntervalSince1970: 1_000)
    let limited = ArisAPIError.http(status: 429, body: Data(#"{"error":{"message":"Rate limit reached"}}"#.utf8), headers: ["Retry-After": "20"], now: now)
    check(limited.kind == .rate && limited.retryAt == now.addingTimeInterval(20) && limited.isUnavailable && ArisBrainFailure.isUnavailable(limited.message),
          "api errors: 429 is a rate limit with its Retry-After, which another AI can take")
    check(ArisAPIError.http(status: 429, body: Data(#"{"error":{"message":"You exceeded your current quota","type":"insufficient_quota"}}"#.utf8), headers: [:]).kind == .quota,
          "api errors: a 429 about quota is out of quota")
    check(ArisAPIError.http(status: 529, body: Data(#"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#.utf8), headers: [:]).kind == .overloaded,
          "api errors: Anthropic's 529 is overloaded")
    check(ArisAPIError.http(status: 400, body: Data(#"{"error":{"message":"This model's maximum context length is 8192 tokens"}}"#.utf8), headers: [:]).kind == .context
          && ArisAPIError.http(status: 400, body: Data(#"{"error":{"message":"llama3 does not support tools"}}"#.utf8), headers: [:]).kind == .noTools,
          "api errors: a context error and a model without tools are told apart")
    check(ArisAPIError.http(status: 500, body: Data("<html>".utf8), headers: [:]).kind == .server, "api errors: 5xx is the server's")

    let key = "sk-proj-abcdefghijklmnop1234"
    let said = ArisAPISecrets.redacted("bad key \(key) and AIzaSyA1234567890abcdefghijk and Bearer abc.def.ghijklmnopq x-api-key: sk-ant-api03-zzzzzzzzzzzzzzzz")
    check(!said.contains("abcdefghijklmnop1234") && !said.contains("AIzaSyA1234567890") && !said.contains("abc.def.ghijklmnopq") && !said.contains("zzzzzzzz")
          && said.contains("bad key"), "api secrets: keys of every provider's shape are dotted out of anything shown or logged")
    check(ArisAPISecrets.redacted("my key is hunter2-very-long-secret", secrets: ["hunter2-very-long-secret"]) == "my key is ••••",
          "api secrets: a saved key is dotted out by value too")
    check(ArisAPISecrets.check("  sk-abc123  ") == "sk-abc123" && ArisAPISecrets.check("sk abc") == nil && ArisAPISecrets.check("") == nil
          && ArisAPISecrets.check(String(repeating: "a", count: 401)) == nil && ArisAPISecrets.check("키값") == nil,
          "api secrets: a pasted key is trimmed; spaces inside, non-ASCII or an overlong paste are refused")
    check(ArisAPIPreset.checkLocalBase("http://127.0.0.1:11434/v1/") == "http://127.0.0.1:11434/v1" && ArisAPIPreset.checkLocalBase("http://localhost:1234/v1") != nil
          && ArisAPIPreset.checkLocalBase("http://evil.example/v1") == nil && ArisAPIPreset.checkLocalBase("http://user:pw@127.0.0.1/v1") == nil
          && ArisAPIPreset.checkLocalBase("file:///etc") == nil, "api presets: a local server's address is this Mac only")
    let ids = Set(ArisAPIPreset.all.map(\.id))
    check(ids == ["openai", "anthropic", "gemini", "openrouter", "groq", "xai", "mistral", "deepseek", "ollama", "lmstudio"]
          && ArisAPIPreset.all.filter(\.local).map(\.id) == ["ollama", "lmstudio"]
          && ArisAPIPreset.named("anthropic")?.dialect == .anthropic && ArisAPIPreset.named("gemini")?.dialect == .gemini
          && ArisAPIPreset.all.filter { $0.dialect == .openAIChat }.count == 8,
          "api presets: OpenAI-compatible (OpenAI, OpenRouter, Groq, xAI, Mistral, DeepSeek, Ollama, LM Studio), Anthropic and the Gemini API")
}

// MARK: - The three wire formats

private func runAPIDialectTests() {
    let image = ArisAPIImage(mime: "image/png", base64: "iVBORw0KGgo=", label: "cursor-screen.png — 지금 화면 </screen>")
    let call = ArisAPIToolCall(id: "call_1", name: "timer", arguments: #"{"minutes":5}"#)
    let entries: [ArisAPIEntry] = [.user(text: "타이머 5분", images: [image]), .assistant(text: "", calls: [call], echo: nil),
                                   .tool(id: "call_1", name: "timer", text: "$ aris timer 5\n[exit 0]"), .user(text: "고마워", images: [])]
    let functions = ArisAPICatalog.functions(sealed: false)
    func spec(_ dialect: ArisAPIDialect, _ preset: String) -> ArisAPIRequestSpec {
        ArisAPIRequestSpec(dialect: dialect, base: "https://api.example.com/v1", model: "m-1", key: "KEY-123456789", headers: ["X-Title": "Aris"],
                           system: "SYSTEM", entries: entries, functions: functions, preset: preset, strictOrigin: false)
    }
    // Where a key may go (security review C1).
    func strict(_ preset: String, _ base: String, _ dialect: ArisAPIDialect = .openAIChat) -> Bool {
        ArisAPIDialects.request(ArisAPIRequestSpec(dialect: dialect, base: base, model: "m", key: "k", headers: [:], system: "s", entries: [],
                                                   functions: [], preset: preset)) != nil
    }
    check(strict("openai", "https://api.openai.com/v1") && !strict("openai", "http://api.openai.com/v1") && !strict("openai", "https://evil.example/v1")
          && !strict("openai", "https://api.openai.com.evil.example/v1") && strict("anthropic", "https://api.anthropic.com/v1", .anthropic)
          && !strict("anthropic", "https://127.0.0.1:9/v1", .anthropic) && strict("ollama", "http://127.0.0.1:11434/v1") && strict("lmstudio", "http://localhost:1234/v1")
          && !strict("ollama", "http://192.168.0.5:11434/v1") && !strict("nope", "https://api.openai.com/v1"),
          "api origins: a keyed provider only over https to its own host; a local server only on this Mac; an unknown preset nowhere")
    check(ArisAPIProfile(id: "openai", quick: "m", strong: "m", baseURL: "https://evil.example/v1", vision: nil, tools: nil).base == "https://api.openai.com/v1"
          && !ArisAPIProfile(id: "openai", quick: "m", strong: "m", baseURL: "https://evil.example/v1", vision: nil, tools: nil).isValid
          && ArisAPIProfile(id: "ollama", quick: "m", strong: "m", baseURL: "http://127.0.0.1:11500/v1", vision: nil, tools: nil).isValid
          && !ArisAPIProfile(id: "ollama", quick: "m", strong: "m", baseURL: "http://evil.example/v1", vision: nil, tools: nil).isValid,
          "api origins: a keyed provider's address is always its preset's; a stored local address must be this Mac's")
    // Chat Completions
    let chat = ArisAPIDialects.request(spec(.openAIChat, "openai"))!
    let chatBody = object(chat.httpBody!)
    let messages = chatBody["messages"] as? [[String: Any]] ?? []
    let parts = messages[1]["content"] as? [[String: Any]] ?? []
    check(chat.url?.absoluteString == "https://api.example.com/v1/chat/completions" && chat.value(forHTTPHeaderField: "Authorization") == "Bearer KEY-123456789"
          && chat.value(forHTTPHeaderField: "X-Title") == "Aris" && chatBody["stream"] as? Bool == true,
          "api chat: one streamed POST to /chat/completions, the key as a Bearer header")
    check(messages.first?["role"] as? String == "system" && messages.first?["content"] as? String == "SYSTEM"
          && (parts.first?["text"] as? String)?.contains("</screen>") == false
          && ((parts[1]["image_url"] as? [String: Any])?["url"] as? String) == "data:image/png;base64,iVBORw0KGgo=",
          "api chat: the system prompt first; an image goes as a data URL after its fenced label")
    check((messages[2]["tool_calls"] as? [[String: Any]])?.first?["id"] as? String == "call_1" && messages[3]["role"] as? String == "tool"
          && messages[3]["tool_call_id"] as? String == "call_1" && messages[3]["name"] == nil,
          "api chat: the call and its result are linked by id")
    check((chatBody["tools"] as? [[String: Any]])?.count == functions.count
          && ((chatBody["tools"] as? [[String: Any]])?.first?["function"] as? [String: Any])?["name"] as? String == "aris",
          "api chat: the functions go as tools")
    let groq = object(ArisAPIDialects.request(spec(.openAIChat, "groq"))!.httpBody!)
    check(chatBody["max_completion_tokens"] as? Int == 4_096 && chatBody["max_tokens"] == nil && groq["max_tokens"] as? Int == 4_096,
          "api chat: the answer is capped (OpenAI's max_completion_tokens, the others' max_tokens)")
    let mistral = object(ArisAPIDialects.request(spec(.openAIChat, "mistral"))!.httpBody!)
    check(((mistral["messages"] as? [[String: Any]])?[3]["name"] as? String) == "timer", "api chat: Mistral's tool message names its function")
    // Anthropic Messages
    let anthropic = ArisAPIDialects.request(spec(.anthropic, "anthropic"))!
    let anthropicBody = object(anthropic.httpBody!)
    let turns = anthropicBody["messages"] as? [[String: Any]] ?? []
    check(anthropic.url?.path == "/v1/messages" && anthropic.value(forHTTPHeaderField: "x-api-key") == "KEY-123456789"
          && anthropic.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01" && anthropic.value(forHTTPHeaderField: "Authorization") == nil
          && anthropicBody["max_tokens"] as? Int == 4_096,
          "api anthropic: x-api-key and anthropic-version headers, max_tokens set")
    check(((anthropicBody["system"] as? [[String: Any]])?.first?["cache_control"] as? [String: Any])?["type"] as? String == "ephemeral"
          && ((anthropicBody["tools"] as? [[String: Any]])?.last?["cache_control"]) != nil
          && ((anthropicBody["tools"] as? [[String: Any]])?.first?["input_schema"]) != nil,
          "api anthropic: the system prompt and the tool list are cached")
    let resultTurn = turns.count == 3 ? turns[2]["content"] as? [[String: Any]] ?? [] : []
    check(turns.map { $0["role"] as? String ?? "" } == ["user", "assistant", "user"]
          && resultTurn.first?["type"] as? String == "tool_result" && resultTurn.first?["tool_use_id"] as? String == "call_1"
          && resultTurn.last?["text"] as? String == "고마워"
          && ((turns[0]["content"] as? [[String: Any]])?[1]["source"] as? [String: Any])?["type"] as? String == "base64",
          "api anthropic: a tool result and the next words share one user turn (turns alternate); images as base64 blocks")
    // Gemini
    let gemini = ArisAPIDialects.request(spec(.gemini, "gemini"))!
    let geminiBody = object(gemini.httpBody!)
    let declarations = ((geminiBody["tools"] as? [[String: Any]])?.first?["functionDeclarations"] as? [[String: Any]]) ?? []
    let schema = declarations.first?["parameters"] as? [String: Any] ?? [:]
    let contents = geminiBody["contents"] as? [[String: Any]] ?? []
    check(gemini.url?.absoluteString == "https://api.example.com/v1/models/m-1:streamGenerateContent?alt=sse"
          && gemini.value(forHTTPHeaderField: "x-goog-api-key") == "KEY-123456789" && !(gemini.url?.absoluteString.contains("KEY") ?? true),
          "api gemini: streamGenerateContent over SSE, the key in its header and never in the address")
    check(schema["type"] as? String == "OBJECT" && ((schema["properties"] as? [String: Any])?["args"] as? [String: Any])?["type"] as? String == "ARRAY"
          && !ArisAPIDialects.jsonText(geminiBody).contains("additionalProperties"),
          "api gemini: the schema in Gemini's subset (capital types, no additionalProperties)")
    check(contents.map { $0["role"] as? String ?? "" } == ["user", "model", "user"]
          && ((contents[2]["parts"] as? [[String: Any]])?.first?["functionResponse"] as? [String: Any])?["name"] as? String == "timer"
          && ((contents[0]["parts"] as? [[String: Any]])?[1]["inlineData"]) != nil
          && ((geminiBody["systemInstruction"] as? [String: Any])?["parts"] as? [[String: Any]])?.first?["text"] as? String == "SYSTEM",
          "api gemini: results as functionResponse in a user turn, images inline, the system instruction apart")
    check((geminiBody["generationConfig"] as? [String: Any])?["maxOutputTokens"] as? Int == 4_096, "api gemini: the answer is capped")

    // Streams back
    let chatStream = ArisAPIStreamDecoder(dialect: .openAIChat)
    var said: [String] = []
    for chunk in [chatChunk(["role": "assistant", "content": "안녕"]), chatChunk(["content": "하세요"]),
                  chatChunk(["tool_calls": [["index": 0, "id": "c1", "function": ["name": "tim", "arguments": "{\"min"]]]]),
                  chatChunk(["tool_calls": [["index": 0, "function": ["name": "er", "arguments": "utes\":5}"]]]]),
                  chatChunk(["tool_calls": [["index": 1, "function": ["name": "music", "arguments": ["action": "play"]]]]], finish: "tool_calls"),
                  "{not json", #"{"choices":[],"usage":{"prompt_tokens":12,"completion_tokens":3}}"#, "[DONE]"] {
        said += chatStream.feed(ArisSSEEvent(name: "", data: chunk))
    }
    let chatCalls = chatStream.calls
    check(said == ["안녕", "하세요"] && chatCalls.count == 2 && chatCalls[0] == ArisAPIToolCall(id: "c1", name: "timer", arguments: #"{"minutes":5}"#)
          && chatCalls[1].name == "music" && ArisAPIDialects.jsonObject(chatCalls[1].arguments)?["action"] as? String == "play" && chatCalls[1].id.count == 9
          && chatStream.usage.input == 12 && chatStream.odd == 1 && !chatStream.cutShort,
          "api chat stream: words as they come; a call's name and arguments joined by index, Ollama's whole call too (a 9-character id made for it); a malformed chunk counted")
    let cut = ArisAPIStreamDecoder(dialect: .openAIChat)
    _ = cut.feed(ArisSSEEvent(name: "", data: chatChunk(["content": "반쯤"])))
    check(cut.cutShort, "api chat stream: a stream with no finish is cut short")
    let errored = ArisAPIStreamDecoder(dialect: .openAIChat)
    _ = errored.feed(ArisSSEEvent(name: "", data: #"{"error":{"message":"Rate limit exceeded","code":429}}"#))
    check(errored.error?.kind == .rate, "api chat stream: an error inside the stream is read as one")

    let claude = ArisAPIStreamDecoder(dialect: .anthropic)
    let anthropicEvents: [(String, String)] = [
        ("message_start", #"{"type":"message_start","message":{"usage":{"input_tokens":40,"cache_read_input_tokens":30}}}"#),
        ("content_block_start", #"{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}"#),
        ("content_block_delta", #"{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"생각"}}"#),
        ("content_block_delta", #"{"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"SIG=="}}"#),
        ("content_block_stop", #"{"type":"content_block_stop","index":0}"#),
        ("content_block_start", #"{"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}"#),
        ("content_block_delta", #"{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"맞출게요"}}"#),
        ("content_block_start", #"{"type":"content_block_start","index":2,"content_block":{"type":"tool_use","id":"toolu_1","name":"timer","input":{}}}"#),
        ("content_block_delta", #"{"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"{\"minu"}}"#),
        ("content_block_delta", #"{"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"tes\": 3}"}}"#),
        ("content_block_stop", #"{"type":"content_block_stop","index":2}"#),
        ("ping", #"{"type":"ping"}"#),
        ("message_delta", #"{"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":9}}"#),
        ("message_stop", #"{"type":"message_stop"}"#)]
    let claudeSaid = anthropicEvents.flatMap { claude.feed(ArisSSEEvent(name: $0.0, data: $0.1)) }
    let echoed = claude.echo as? [[String: Any]] ?? []
    check(claudeSaid == ["맞출게요"] && claude.calls == [ArisAPIToolCall(id: "toolu_1", name: "timer", arguments: #"{"minutes":3}"#)]
          && echoed.first?["type"] as? String == "thinking" && echoed.first?["signature"] as? String == "SIG==" && echoed.first?["thinking"] as? String == "생각"
          && claude.usage.cacheRead == 30 && claude.stop == "tool_use" && claude.odd == 0 && !claude.cutShort,
          "api anthropic stream: text, a tool_use built from its JSON pieces, and the thinking block with its signature kept to send back")
    let overloaded = ArisAPIStreamDecoder(dialect: .anthropic)
    _ = overloaded.feed(ArisSSEEvent(name: "error", data: #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#))
    check(overloaded.error?.kind == .overloaded, "api anthropic stream: an overloaded error event")

    let flash = ArisAPIStreamDecoder(dialect: .gemini)
    let flashSaid = [#"{"candidates":[{"content":{"role":"model","parts":[{"text":"생각","thought":true},{"text":"타이머"}]}}]}"#,
                     #"{"candidates":[{"content":{"role":"model","parts":[{"functionCall":{"name":"timer","args":{"minutes":2}},"thoughtSignature":"TS1"}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":7,"candidatesTokenCount":2}}"#]
        .flatMap { flash.feed(ArisSSEEvent(name: "", data: $0)) }
    let flashEcho = flash.echo as? [[String: Any]] ?? []
    check(flashSaid == ["타이머"] && flash.calls.count == 1 && flash.calls[0].name == "timer" && ArisAPIDialects.jsonObject(flash.calls[0].arguments)?["minutes"] as? Int == 2
          && flashEcho.contains { $0["thoughtSignature"] as? String == "TS1" } && flash.usage.input == 7 && !flash.cutShort,
          "api gemini stream: thoughts aren't said; a functionCall whole, its thoughtSignature kept to send back")
    // The provider searched the web itself: outside text (I1).
    let cited = ArisAPIStreamDecoder(dialect: .openAIChat)
    _ = cited.feed(ArisSSEEvent(name: "", data: #"{"choices":[{"delta":{"content":"x","annotations":[{"type":"url_citation","url_citation":{"url":"https://e.com"}}]}}]}"#))
    let grounded = ArisAPIStreamDecoder(dialect: .gemini)
    _ = grounded.feed(ArisSSEEvent(name: "", data: #"{"candidates":[{"content":{"parts":[{"text":"x"}]},"groundingMetadata":{"webSearchQueries":["q"]}}]}"#))
    let plainStream = ArisAPIStreamDecoder(dialect: .openAIChat)
    _ = plainStream.feed(ArisSSEEvent(name: "", data: #"{"choices":[{"delta":{"content":"x","annotations":[]}}],"citations":null}"#))
    let perplexity = ArisAPIStreamDecoder(dialect: .openAIChat)
    _ = perplexity.feed(ArisSSEEvent(name: "", data: #"{"citations":["https://e.com"],"search_results":[{"url":"https://e.com"}],"choices":[]}"#))
    check(cited.searched && grounded.searched && perplexity.searched && !plainStream.searched,
          "api search: annotations, citations, search results or grounding in a stream are the provider's own web search")
    check(ArisAPIDriver.searchesOnItsOwn("openai/gpt-oss-120b:online") && ArisAPIDriver.searchesOnItsOwn("sonar-pro")
          && ArisAPIDriver.searchesOnItsOwn("gpt-4o-search-preview") && !ArisAPIDriver.searchesOnItsOwn("gpt-6-luna"),
          "api search: a model id that searches on its own (:online, sonar, search)")
    let huge = ArisAPIStreamDecoder(dialect: .openAIChat)
    for _ in 0..<70 { _ = huge.feed(ArisSSEEvent(name: "", data: chatChunk(["tool_calls": [["index": 0, "id": "h", "function": ["name": "aris", "arguments": String(repeating: "a", count: 1_000)]]]]))) }
    check(huge.error?.kind == .malformed, "api caps: a call's arguments past 64 KB while they arrive fail the round")
    // A server that doesn't stream: one whole JSON body.
    let whole = ArisAPIStreamDecoder(dialect: .openAIChat)
    let wholeSaid = whole.feed(ArisSSEEvent(name: "json", data: #"{"choices":[{"message":{"role":"assistant","content":"한 번에","tool_calls":[{"id":"w1","type":"function","function":{"name":"timer","arguments":"{\"minutes\":1}"}}]},"finish_reason":"tool_calls"}]}"#))
    check(wholeSaid == ["한 번에"] && whole.calls.first?.name == "timer" && !whole.cutShort, "api chat: a server that doesn't stream still answers, in one piece")
}

// MARK: - The profile store and the settings route

private func runAPIStoreTests() {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-api-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let secrets = ArisMCPMemorySecrets()
    let signing = ArisMCPMemorySecrets()
    let store = ArisAPIStore(file: folder.appendingPathComponent("api-brains.json"), signing: signing)
    check(store.load() == .empty && !store.tampered, "api store: nothing saved is no profile")
    let profile = ArisAPIProfile(id: "groq", quick: "llama-3.3-70b-versatile", strong: "openai/gpt-oss-120b", baseURL: nil, vision: nil, tools: nil)
    check(store.update { var next = $0.saving(profile); next.active = "groq"; return next } == nil && store.load().activeProfile == profile,
          "api store: a profile saved and made the one that answers")
    let text = (try? String(contentsOf: store.file, encoding: .utf8)) ?? ""
    let mode = ((try? FileManager.default.attributesOfItem(atPath: store.file.path))?[.posixPermissions] as? NSNumber)?.intValue
    check(text.contains("\"mac\"") && mode == 0o600 && !text.contains("sk-") && signing.secret(for: ArisAPIStore.signingKey) != nil
          && secrets.secret(for: ArisAPIStore.signingKey) == nil && ArisAPISecrets.signingService != ArisAPISecrets.service,
          "api store: signed, 0600, no key in it; the signing key under its own Keychain service (no profile id can name it)")
    try? text.replacingOccurrences(of: "llama-3.3-70b-versatile", with: "evil-model").write(to: store.file, atomically: true, encoding: .utf8)
    check(store.load() == .empty && store.tampered, "api store: a file changed outside Aris is no profile at all")
    _ = store.update { _ in ArisAPIBrains.empty.saving(profile) }
    check(store.load().profiles == [profile] && !store.tampered && store.load().active == nil, "api store: saving again makes it Aris's own")
    _ = store.update { $0.saving(ArisAPIProfile(id: "openai", quick: "m", strong: "m", baseURL: "https://evil.example/v1", vision: nil, tools: nil)) }
    check(store.load().profile("openai") == nil && store.load().profile("groq") == profile,
          "api store: a stored profile that isn't valid (a keyed provider with an address) is dropped on load")
    check(ArisAPIHelper.resolve("groq", store: store) == profile && ArisAPIHelper.resolve("openai", store: store)?.base == "https://api.openai.com/v1"
          && ArisAPIHelper.resolve("config-hmac", store: store) == nil && ArisAPIHelper.resolve("../x", store: store) == nil,
          "api helper: its profile is the signed one or the preset's defaults; anything else (the signing key's name included) is refused")
    let tested = store.load().recording(ArisAPITested(profile: "groq", model: "m", at: Date(timeIntervalSince1970: 5), passed: ["stream"], failed: []))
        .recording(ArisAPITested(profile: "groq", model: "m", at: Date(timeIntervalSince1970: 9), passed: ["stream", "tool"], failed: []))
    check(tested.tested.count == 1 && tested.tested[0].passed == ["stream", "tool"], "api store: the latest smoke check per model is kept")

    // The settings route: a key goes to the Keychain and never comes back.
    var changed = 0
    func route(_ body: [String: Any], smoke: @escaping (ArisAPIProfile, String, String?) -> ArisAPISmoke.Outcome = { _, _, _ in ArisAPISmoke.Outcome() })
        -> (String, [String: Any]) {
        let done = DispatchSemaphore(value: 0)
        var answer = ("", [String: Any]())
        ArisAPIRoutes.settings(body, store: store, secrets: secrets, changed: { changed += 1 }, smoke: smoke) { status, data in
            answer = (status, object(data))
            done.signal()
        }
        _ = done.wait(timeout: .now() + 10)
        return answer
    }
    let secret = "sk-ant-api03-TESTKEYTESTKEYTESTKEY"
    let saved = route(["op": "save", "id": "anthropic", "key": secret, "quick": "claude-haiku-4-5", "activate": true])
    let listed = route(["op": "list"])
    let listedText = ArisAPIDialects.jsonText(listed.1)
    check(saved.0 == "200 OK" && secrets.secret(for: "anthropic") == secret && changed == 1
          && (listed.1["profiles"] as? [[String: Any]])?.contains { $0["id"] as? String == "anthropic" && $0["hasKey"] as? Bool == true } == true
          && listed.1["active"] as? String == "anthropic" && !listedText.contains("TESTKEY") && !ArisAPIDialects.jsonText(saved.1).contains("TESTKEY"),
          "api route: the key goes to the Keychain, the app hears only that one is saved, and the API brain starts again with it")
    check(route(["op": "save", "id": "anthropic", "key": "bad key with spaces"]).0 == "400 Bad Request" && secrets.secret(for: "anthropic") == secret,
          "api route: a key that can't be one is refused and the saved one kept")
    check(route(["op": "save", "id": "ollama", "baseURL": "http://evil.example:11434/v1"]).0 == "400 Bad Request"
          && route(["op": "save", "id": "ollama", "baseURL": "http://localhost:11434/v1", "key": "x"]).0 == "400 Bad Request"
          && route(["op": "save", "id": "ollama", "baseURL": "http://localhost:11500/v1"]).0 == "200 OK"
          && store.load().profile("ollama")?.base == "http://localhost:11500/v1",
          "api route: a local server only on this Mac, and with no key")
    check(route(["op": "save", "id": "openai", "quick": "gpt; rm -rf ~"]).0 == "400 Bad Request" && route(["op": "save", "id": "nope"]).0 == "400 Bad Request",
          "api route: a model name or provider that isn't one is refused")
    let smoked = route(["op": "test", "id": "anthropic"]) { _, model, key in
        ArisAPISmoke.Outcome(passed: model == "claude-haiku-4-5" && key == secret ? ["stream"] : [], failed: ["tool"], message: "x")
    }
    check(smoked.1["ok"] as? Bool == false && store.load().tested.contains { $0.profile == "anthropic" && $0.passed == ["stream"] }
          && store.load().profile("anthropic")?.tools == false,
          "api route: 테스트 records the smoke check; a model that can't call functions moves to the text relay (never locked out)")
    check(route(["op": "remove", "id": "anthropic"]).0 == "200 OK" && secrets.secret(for: "anthropic") == nil && store.load().profile("anthropic") == nil
          && store.load().active == nil, "api route: 지우기 removes the key from the Keychain and the profile")
}

// MARK: - The function catalog

private func runAPICatalogTests() {
    // argv → command → the same argv, for every kind of word.
    let awkward = ["it's", "a \"quoted\" word", "$(rm -rf ~)", "a;b && c | d", "line\nbreak", "`id`", "~/Downloads", "", "*.txt", "#tag",
                   "back\\slash", "'", "''", "엄마", "늦어요 😀", "--due", "x=y", "a'b\"c$d", "!bang", "(paren)", "{brace}", "tab\there"]
    var roundTrips = true
    for word in awkward {
        let argv = ["note", word, "end"]
        let command = ArisAPICatalog.command(tools: apiTools, argv: argv)
        if ArisCommandPolicy.words(command) != [apiTools] + argv || ArisCommandPolicy.segments(command)?.count != 1 { roundTrips = false; print("  round trip broke for \(word.debugDescription)") }
    }
    for _ in 0..<300 {
        let alphabet = Array("ab '\"$;&|`\\\n()<>*?[]{}#!~가-😀\t")
        let word = String((0..<Int.random(in: 0...12)).map { _ in alphabet.randomElement()! })
        let argv = ["remember", word]
        if ArisCommandPolicy.words(ArisAPICatalog.command(tools: apiTools, argv: argv)) != [apiTools] + argv { roundTrips = false; print("  round trip broke for \(word.debugDescription)") }
    }
    check(roundTrips, "api catalog: every argv becomes one command that the gate reads back to exactly that argv (quotes, $, ;, newlines, emoji)")

    let samples: [(String, [String: Any], [String]?)] = [
        ("aris", ["args": ["weather", "Seoul", "--ko"]], ["weather", "Seoul", "--ko"]),
        ("aris", ["args": []], nil), ("aris", ["args": "weather"], nil), ("aris", ["args": ["", "x"]], nil),
        ("timer", ["minutes": 25], ["timer", "25"]), ("timer", ["minutes": 25, "mode": "focus"], ["timer", "25", "--focus"]),
        ("timer", ["mode": "pomodoro"], ["timer", "pomodoro"]), ("timer", ["mode": "stop"], ["timer", "stop"]), ("timer", ["minutes": 0], nil),
        ("timer", ["minutes": 2.5], nil), ("music", ["action": "next", "app": "spotify"], ["music", "next", "spotify"]), ("music", ["action": "rm"], nil),
        ("volume", ["level": "40"], ["volume", "40"]), ("volume", ["level": 101], nil), ("volume", ["level": "mute"], ["volume", "mute"]),
        ("open_app", ["name": "Figma"], ["app", "Figma"]),
        ("weather", ["place": "Seoul", "days": 7, "language": "ko"], ["weather", "Seoul", "--days", "7", "--ko"]),
        ("todo_add", ["item": "우유", "due": "내일 3시"], ["todo", "add", "우유", "--due", "내일 3시"]),
        ("remind", ["text": "약", "at": "2026-11-07 09:00"], ["remind", "약", "--at", "2026-11-07 09:00"]),
        ("add_event", ["title": "회의", "start": "2026-11-07 15:00", "minutes": 30], ["event", "회의", "--start", "2026-11-07 15:00", "--minutes", "30"]),
        ("send_message", ["to": "엄마", "text": "늦어요"], ["message", "엄마", "늦어요"]), ("send_message", ["to": "엄마"], nil),
        ("save_note", ["markdown": "# 장보기\n- [ ] 우유"], ["note", "--markdown", "# 장보기\n- [ ] 우유"]),
        ("remember", ["fact": "커피는 라떼"], ["remember", "커피는 라떼"]), ("stock", ["symbol": "AAPL"], ["stock", "AAPL"]),
        ("nope", [:], nil)]
    let wrong = samples.filter { ArisAPICatalog.argv(name: $0.0, arguments: ArisAPIDialects.jsonText($0.1)) != $0.2 }
    check(wrong.isEmpty, "api catalog: each function's arguments make exactly its aris-tools words, and anything else is nil\(wrong.map { " \($0.0)" }.joined())")
    check(ArisAPICatalog.argv(name: "timer", arguments: "{not json") == nil && ArisAPICatalog.argv(name: "aris", arguments: #"{"args":["a\u0000b"]}"#) == nil,
          "api catalog: malformed arguments or a NUL are nil (the driver stops the turn)")
    let sealedNames = ArisAPICatalog.names(sealed: true)
    let sealedSamples = [["timer", "25"], ["timer", "25", "--focus"], ["music", "play"], ["volume", "up"], ["app", "Figma"],
                         ["desktop", "see", "--app", "TextEdit"], ["desktop", "type", "@s1abc:e2", "--stdin"], ["desktop", "menu", "click", "--app", "TextEdit", "--path", "File › Save"],
                         ["desktop", "dialog", "file", "--app", "TextEdit", "--path", "/tmp/out", "--name", "copy"], ["aside", "쿠팡에서 이어폰 찾아줘"]]
    // Computer use too (the owner: no feature locked out by the brain): its gate is the desktop engine's, and every action there
    // shows the user a card on a sealed turn.
    let desktopNames: Set<String> = ["desktop_see", "desktop_click", "desktop_type", "desktop_set_value", "desktop_press", "desktop_menu", "desktop_scroll",
                                     "desktop_save_as", "desktop_batch", "desktop_window",
                                     // HANDOVERS C: the desktop calls the API brain had no function for.
                                     "desktop_app", "desktop_drag", "desktop_click_at", "desktop_dialog_click", "desktop_dialog_input"]
    // file_read (audit gate-1 / F1): a document's text is a read like the user's app reads, judged first on a sealed turn.
    check(sealedNames == Set(["aris", "timer", "music", "volume", "open_app", "aside_task", "file_read"]).union(desktopNames) && sealedSamples.allSatisfy { ArisSealedTools.allows($0) }
          && !sealedNames.contains("send_message") && !sealedNames.contains("save_note") && !sealedNames.contains("remember")
          && !sealedNames.contains("file_rename") && !sealedNames.contains("file_move") && !sealedNames.contains("folder_new"),
          "api catalog: the sealed subset's typed functions make only sealed-list argv; nothing that sends or writes is offered (desktop asks on its card)")
    let names = ArisAPICatalog.functions(sealed: false).map(\.name)
    check(Set(names).count == names.count && names.allSatisfy { $0.range(of: #"^[a-z_]{1,64}$"#, options: .regularExpression) != nil }
          && ArisAPICatalog.functions(sealed: false).allSatisfy { ($0.parameters["type"] as? String) == "object" && !ArisAPIDialects.jsonText($0.parameters).contains("additionalProperties") },
          "api catalog: names every provider takes, flat object schemas (Gemini's subset)")
    let prompt = ArisAgentPrompt.system(tools: "aris", gated: true, functions: true)
    let sealedPrompt = ArisAgentPrompt.sealed(tools: "aris", functions: true)
    check(prompt.contains("aris(args: [\"timer\", \"25\"])") && !prompt.contains("aris_aside exec") && !prompt.contains("you can run any shell command")
          // Audit imp-api-web-13: it is no longer told to hand a web question out as a job "where the web is" (the job
          // ran on the same brain, which has none): it is told it has no search, and what it and the user can do.
          && prompt.contains("you have no web search here") && !prompt.contains("it runs where the web is") && prompt.contains("`aris message") && !prompt.contains("Gmail tools")
          && prompt.contains("aside_task(brief)") && !ArisAgentPrompt.system(tools: "/t", gated: true).contains("aris_aside"),
          "api prompt: aris-tools as function calls, no shell or computer use; Aside through aside_task like every brain")
    check(!sealedPrompt.contains("WebSearch") && sealedPrompt.contains("`aris` function call") && ArisAgentPrompt.sealed(tools: "/t").contains("WebSearch and WebFetch"),
          "api prompt: the sealed API brain has no web tools; the sealed Claude's prompt unchanged")
}

// MARK: - Gate parity: the same command, the same answer as Codex

private enum GateAnswer: String { case allow, deny, ask, read, countdown }

private func codexAnswer(_ codex: ArisCodexDriver, _ command: String, id: Int) -> GateAnswer {
    let request: [String: Any] = ["id": id, "method": "item/commandExecution/requestApproval", "params": ["threadId": "T1", "command": command]]
    let events = codex.read(String(decoding: try! JSONSerialization.data(withJSONObject: request), as: UTF8.self))
    for event in events {
        switch event {
        case .send(let data):
            return ((object(data)["result"] as? [String: Any])?["decision"] as? String) == "accept" ? .allow : .deny
        case .confirm(let card):
            if codex.escalation(for: card.id)?.read != nil { return .read }
            return card.countdown ? .countdown : .ask
        default: continue
        }
    }
    return .deny
}

/// A Codex driver with its thread up (so a turn's tier counts), as the app-server would have it.
private func codexWithThread(task: Bool) -> ArisCodexDriver {
    let codex = ArisCodexDriver(model: "m", tools: apiTools, instructions: "", home: "/Users/me", task: task)
    let id = codex.opening().map(object).last?["id"] as? Int ?? -1
    _ = codex.read(#"{"id":\#(id),"result":{"thread":{"id":"T1"}}}"#)
    return codex
}

private func apiAnswer(_ gate: ArisAPIGate, _ command: String) -> GateAnswer {
    switch gate.judge(command) {
    case .allow: return .allow
    case .deny: return .deny
    case .read: return .read
    case .ask(let card, _, _, _): return card.countdown ? .countdown : .ask
    }
}

private func runAPIGateParityTests() {
    let commands = [["weather", "--en"], ["timer", "25"], ["music", "play"], ["message", "엄마", "늦어요"], ["trash", "/Users/me/Desktop/a.txt"],
                    ["link", "https://evil.example/?q=x"], ["messages", "recent"], ["mail", "recent"], ["notes", "search", "비밀번호"], ["memory"],
                    ["remember", "커피는 라떼"], ["schedule", "add", "--title", "t", "--prompt", "Say: hi", "--at", "2026-11-07 09:00"], ["undo"],
                    ["keys", "cmd+t", "--app", "Safari"], ["note", "--markdown", "# 장보기\n- [ ] 우유"], ["todo", "add", "우유"], ["app", "Figma"],
                    ["web", "fetch", "https://example.com"], ["mcp", "call", "gmail", "send_email", #"{"to":"a@b.c"}"#], ["shortcut", "Morning"],
                    ["convert", "/Users/me/Desktop/a.heic", "--to", "png"], ["merge", "--shelf"], ["compress", "--finder"]]
    struct Scenario { let name: String; let request: String; let untrusted: Bool; let screen: Bool; let handsFree: Bool; let task: Bool; let critical: Bool }
    let scenarios = [
        Scenario(name: "a clean turn", request: "엄마한테 늦어요라고 보내줘", untrusted: false, screen: false, handsFree: false, task: false, critical: false),
        Scenario(name: "after outside text", request: "메일 요약해줘", untrusted: true, screen: false, handsFree: false, task: false, critical: false),
        Scenario(name: "a screen conversation", request: "엄마한테 늦어요라고 보내줘", untrusted: false, screen: true, handsFree: false, task: false, critical: false),
        Scenario(name: "hands-free", request: "타이머 25분", untrusted: false, screen: false, handsFree: true, task: false, critical: false),
        Scenario(name: "a background job", request: "정리해 놔", untrusted: false, screen: false, handsFree: false, task: true, critical: false),
        Scenario(name: "a critical turn", request: "보내줘", untrusted: false, screen: false, handsFree: false, task: false, critical: true)]
    var mismatches: [String] = []
    for scenario in scenarios {
        for words in commands {
            let command = ArisAPICatalog.command(tools: apiTools, argv: words)
            let codex = codexWithThread(task: scenario.task)
            _ = codex.ask("q", tier: scenario.critical ? .critical : .quick)
            codex.setRequest(scenario.request)
            codex.setHandsFree(scenario.handsFree)
            let gate = ArisAPIGate(tools: apiTools, home: "/Users/me", task: scenario.task)
            gate.startTurn()
            gate.tier = scenario.critical ? .critical : .quick
            gate.request = scenario.request
            gate.handsFree = scenario.handsFree
            if scenario.screen { codex.markScreenSeen(); gate.markScreenSeen() }
            if scenario.untrusted { codex.markUntrusted(); gate.markUntrusted() }
            let mine = apiAnswer(gate, command), theirs = codexAnswer(codex, command, id: 500)
            if mine != theirs { mismatches.append("\(scenario.name): \(words.joined(separator: " ")) api=\(mine.rawValue) codex=\(theirs.rawValue)") }
            if gate.taint != codex.taint { mismatches.append("\(scenario.name): \(words.joined(separator: " ")) taint api=\(gate.taint) codex=\(codex.taint)") }
        }
    }
    mismatches.forEach { print("  parity: \($0)") }
    // A conversion only makes new files beside the originals: Codex runs it at once on a clean turn, and refuses it
    // (no card) once outside text or the screen came in.
    for words in [["convert", "/Users/me/Desktop/a.heic", "--to", "png"], ["merge", "--shelf"], ["split", "--finder"]] {
        let clean = codexWithThread(task: false), tainted = codexWithThread(task: false), screen = codexWithThread(task: false)
        for codex in [clean, tainted, screen] { _ = codex.ask("q", tier: .quick); codex.setRequest("이거 PNG로 바꿔줘") }
        tainted.markUntrusted()
        screen.markScreenSeen()
        // Audit gate-4: after outside text it asks on a card (it was refused); after the screen, what the owner picked
        // himself (--finder, --shelf) runs and a file their words don't name asks.
        let picked = words.contains("--shelf") || words.contains("--finder")
        check(codexAnswer(clean, ArisAPICatalog.command(tools: apiTools, argv: words), id: 700) == .allow
              && codexAnswer(tainted, ArisAPICatalog.command(tools: apiTools, argv: words), id: 701) == .ask
              && codexAnswer(screen, ArisAPICatalog.command(tools: apiTools, argv: words), id: 702) == (picked ? .allow : .ask),
              "convert gate (Codex): \(words[0]) runs at once on a clean turn, asks on a card after outside text, and after the screen runs only for what the user picked or named")
    }
    let wrapped = codexWithThread(task: false)
    _ = wrapped.ask("q", tier: .quick)
    wrapped.markUntrusted()
    let shells = ["sh -c '\(apiTools) convert /Users/me/a.png --to jpg'", "bash -c \"\(apiTools) merge --shelf\"", "env \(apiTools) compress --finder",
                  "echo /Users/me/a.png | xargs \(apiTools) convert --to png"]
    // (Codex's own `sh -c '<command>'` wrapper is taken off like its zsh -lc, so the first two are the plain call: a card.)
    check(shells.enumerated().map { codexAnswer(wrapped, $0.element, id: 710 + $0.offset) } == [.ask, .ask, .deny, .deny],
          "convert gate (Codex, follow-up 5): after outside text env and xargs around a conversion are refused, not carded; the plain call in Codex's own shell wrapper asks")
    check(mismatches.isEmpty, "api gate parity: every command in every kind of turn (clean, outside text, screen, hands-free, job, critical) gets Codex's answer and taint")

    // Within a turn: a no closes the rest; a yes is remembered only while clean; the user's changed card is never run twice.
    let gate = ArisAPIGate(tools: apiTools, home: "/Users/me")
    gate.startTurn()
    let trash = ArisAPICatalog.command(tools: apiTools, argv: ["trash", "/Users/me/Desktop/a.txt"])
    guard case .ask(let first, _, _, _) = gate.judge(trash) else { return check(false, "api gate: trash asks") }
    gate.answered(first.id, allow: false)
    check(apiAnswer(gate, ArisAPICatalog.command(tools: apiTools, argv: ["trash", "/Users/me/Desktop/b.txt"])) == .deny,
          "api gate: after a no, anything else that would ask is declined this turn")
    gate.startTurn()
    check(apiAnswer(gate, trash) == .ask, "api gate: the next turn asks again")
    let edited = ArisAPIGate(tools: apiTools, home: "/Users/me")
    edited.startTurn()
    let message = ArisAPICatalog.command(tools: apiTools, argv: ["message", "엄마", "늦어요"])
    edited.sentEdited(.shell(message), arguments: ["message", "엄마", "고친 말"])
    check(apiAnswer(edited, message) == .deny && apiAnswer(edited, ArisAPICatalog.command(tools: apiTools, argv: ["message", "엄마", "고친 말"])) == .deny,
          "api gate: the user's changed card ran; the AI's call and the changed one aren't run again this turn")
}

// MARK: - The driver's line protocol

private func runAPIDriverTests() {
    let driver = apiDriver()
    let asked = object(driver.ask("타이머 5분", tier: .quick)[0])
    check(asked["type"] as? String == "ask" && asked["model"] as? String == "gpt-6-luna" && (asked["functions"] as? [String])?.count == ArisAPICatalog.entries.count
          && asked["relay"] as? Bool == false && asked["maxRounds"] as? Int == 8 && (asked["system"] as? String)?.contains("`aris` function") == true,
          "api driver: a question carries the system prompt, the tier's model and every function")
    check(object(driver.ask("x", tier: .work)[0])["model"] as? String == "gpt-6.1-sol", "api driver: work and critical turns use the strong model")
    check(driver.opening().isEmpty, "api driver: nothing configures the helper's address or key over the pipe (it reads its own profile)")
    check(driver.launch()?.1 == ["api-brain", "--profile", "openai"], "api driver: the helper is this binary in api-brain mode")
    check(ArisAPIDriver(profile: apiProfile("openai", base: "x"), tools: apiTools, executable: URL(fileURLWithPath: "/usr/bin/true"), hasKey: { false }).launch() == nil
          && ArisAPIDriver(profile: apiProfile("ollama", base: "http://127.0.0.1:11434/v1"), tools: apiTools, executable: URL(fileURLWithPath: "/usr/bin/true"),
                           hasKey: { false }).launch() != nil && ArisAPIDriver(profile: nil, tools: apiTools).launch() == nil,
          "api driver: no key saved, no helper (a local server needs none); no profile, no brain")

    _ = driver.ask("타이머 5분", tier: .quick)
    let timer = driver.read(toolRequest("t1", "timer", ["minutes": 5]))
    check(sends(timer).first?["type"] as? String == "allow" && sends(timer).first?["argv"] as? [String] == ["timer", "5"]
          && timer.contains { if case .tools(let calls) = $0 { return calls.first?.command == ArisAPICatalog.command(tools: apiTools, argv: ["timer", "5"]) }; return false }
          && timer.contains { if case .audit = $0 { return true }; return false },
          "api driver: a quiet command is allowed at once with its exact argv, seen as a tool and audited")
    _ = driver.read(#"{"type":"tool_done","id":"t1","exit":0,"bytes":10}"#)
    check(driver.taint == .none, "api driver: a timer brings nothing anyone else wrote")
    // The file tools print only the names the brain passed: their answer isn't outside text either.
    for (id, name, arguments) in [("f1", "file_rename", ["path": "~/Desktop/a.txt", "name": "b.txt"]), ("f2", "file_move", ["path": "~/Desktop/b.txt", "folder": "~/Desktop/Archive"]),
                                  ("f3", "folder_new", ["path": "~/Desktop/Q4"])] {
        let asked = driver.read(toolRequest(id, name, arguments))
        for case .confirm(let card) in asked { _ = driver.decide(card.id, allow: true) }
        _ = driver.read(#"{"type":"tool_done","id":"\#(id)","exit":0,"bytes":20}"#)
        check(driver.taint == .none, "api driver: \(name)'s answer brings nothing anyone else wrote")
    }
    // A name that is no tool of Aris's runs nothing: it is told as a tool error twice a turn, and the third stops the
    // turn (fourth VM run, bug 4: one made-up name used to end the turn at once).
    let unknown = driver.read(toolRequest("t2", "shell", ["command": "rm -rf ~"])), again = driver.read(toolRequest("t2b", "shell", ["command": "rm -rf ~"]))
    let told = [unknown, again].allSatisfy { events in
        if case .send(let data)? = events.first {
            let line = String(decoding: data, as: UTF8.self)
            return line.contains("\"deny\"") && line.contains("no such tool: shell") && !line.contains("rm -rf")
        }
        return false
    }
    check(told && unknown.contains { if case .audit(let line) = $0 { return line.contains("error result (no such tool; nothing ran)") }; return false },
          "api driver: a function Aris doesn't have runs nothing and is answered as a tool error the model can go on from, with its ledger line")
    if case .abort(let line)? = driver.read(toolRequest("t2c", "shell", ["command": "rm -rf ~"])).first { check(line == ArisAPIDriver.offListStop, "api driver: a third made-up function stops the turn") } else { check(false, "api driver: a third made-up function stops the turn") }
    _ = driver.ask("q", tier: .quick)
    if case .abort? = driver.read(#"{"type":"tool_request","id":"t3","name":"timer","arguments":"{bad","round":1}"#).first {} else { check(false, "api driver: malformed arguments stop the turn") }
    _ = driver.ask("q", tier: .quick)
    if case .abort(let line)? = driver.read(toolRequest("t4", "timer", ["minutes": 1], round: 9)).first {
        check(line == ArisAPIDriver.roundsStop, "api driver: a ninth round stops the turn")
    } else { check(false, "api driver: rounds cap") }

    // One id once a turn; at most eight calls a round; a search model is outside text from its first round.
    let ids = apiDriver()
    _ = ids.ask("q", tier: .quick)
    _ = ids.read(toolRequest("same", "timer", ["minutes": 1]))
    if case .abort? = ids.read(toolRequest("same", "timer", ["minutes": 2])).first {} else { check(false, "api driver: a repeated call id stops the turn") }
    let many = apiDriver()
    _ = many.ask("q", tier: .quick)
    let bursts = (1...9).map { many.read(toolRequest("b\($0)", "timer", ["minutes": 1])) }
    if case .abort? = bursts.last?.first, bursts.dropLast().allSatisfy({ sends($0).first?["type"] as? String == "allow" }) {} else {
        check(false, "api driver: a ninth call in one round stops the turn")
    }
    let searching = ArisAPIDriver(profile: ArisAPIProfile(id: "openrouter", quick: "openai/gpt-oss-120b:online", strong: "x", baseURL: nil, vision: nil, tools: nil),
                                  tools: apiTools, home: "/Users/me")
    _ = searching.ask("뉴스", tier: .quick)
    check(searching.taint == .outsideText, "api driver: a model that searches on its own makes the turn outside text from the start")
    let hidden = apiDriver()
    _ = hidden.ask("q", tier: .quick)
    let bidi = hidden.read(toolRequest("bd", "send_message", ["to": "엄마", "text": "늦어요\u{202E}gnp.exe"]))
    check(sends(bidi).first?["type"] as? String == "deny" && !bidi.contains { if case .confirm = $0 { return true }; return false }
          && ArisAPIDriver.hidesText(["a\u{200B}b"]) && !ArisAPIDriver.hidesText(["늦어요 😀"]),
          "api driver: a call whose card would carry bidi or zero-width characters is refused, never shown")
    let earlier = hidden.read(toolRequest("ok", "aris", ["args": ["trash", "/Users/me/Desktop/a.txt"]]))
    let earlierCard = earlier.compactMap { if case .confirm(let card) = $0 { return card.id } else { return nil } }.first ?? ""
    _ = hidden.ask("next", tier: .quick)
    check(!earlierCard.isEmpty && hidden.decide(earlierCard, allow: true).isEmpty && hidden.escalation(for: earlierCard) == nil,
          "api driver: a card of an earlier turn can't be answered into this one")

    // Cards: the user's yes runs it, a no tells the model.
    let carded = apiDriver()
    _ = carded.ask("엄마한테 늦어요라고 보내줘", tier: .quick)
    carded.setRequest("엄마한테 늦어요라고 보내줘")
    let send = carded.read(toolRequest("m1", "send_message", ["to": "엄마", "text": "늦어요"]))
    guard case .confirm(let card)? = send.first(where: { if case .confirm = $0 { return true }; return false }) else { return check(false, "api driver: a message is a card") }
    check((card.countdown ? card.title == "엄마" : card.title == "메시지 보내기") && sends(send).isEmpty && carded.escalation(for: card.id)?.action == .shell(ArisAPICatalog.command(tools: apiTools, argv: ["message", "엄마", "늦어요"])),
          "api driver: a message is the user's card (his dictated words: the countdown), nothing sent before it; the escalation gate sees the action")
    check(object(carded.decide(card.id, allow: true)[0])["argv"] as? [String] == ["message", "엄마", "늦어요"] && carded.decide(card.id, allow: true).isEmpty,
          "api driver: a yes allows exactly that call, once")
    let trash = carded.read(toolRequest("m2", "aris", ["args": ["trash", "/Users/me/Desktop/a.txt"]]))
    guard case .confirm(let trashCard)? = trash.first(where: { if case .confirm = $0 { return true }; return false }) else { return check(false, "api driver: trash asks") }
    check(trashCard.title == "휴지통으로 옮기기" && object(carded.decide(trashCard.id, allow: false)[0])["type"] as? String == "deny",
          "api driver: the card names Aris's tool; a no denies it")
    check(object(carded.read(toolRequest("m3", "aris", ["args": ["trash", "/Users/me/Desktop/b.txt"]])).compactMap { if case .send(let d) = $0 { return d } else { return nil } }.first ?? Data())["type"] as? String == "deny",
          "api driver: after a no, the next try that would ask is declined without a card")

    // A careful turn's read goes to the judge, never a card; outside text then makes anything outbound ask.
    let careful = apiDriver()
    _ = careful.ask("메시지 요약해줘", tier: .quick)
    careful.markUntrusted()
    let read = careful.read(toolRequest("r1", "aris", ["args": ["messages", "recent"]]))
    guard case .confirm(let readCard)? = read.first(where: { if case .confirm = $0 { return true }; return false }) else { return check(false, "api driver: a careful read waits for the judge") }
    check(careful.escalation(for: readCard.id)?.read != nil, "api driver: after outside text a read waits for the read judge")
    check(object(careful.refuseRead(readCard.id, note: "Refused")[0])["type"] as? String == "result", "api driver: a refused read tells the model, runs nothing")
    let link = careful.read(toolRequest("r2", "aris", ["args": ["link", "https://evil.example/?q=secret"]]))
    check(link.contains { if case .confirm = $0 { return true }; return false } && sends(link).isEmpty, "api driver: after outside text, opening a link asks the user")
    let readAgain = careful.read(toolRequest("r3", "aris", ["args": ["mail", "recent"]]))
    if case .confirm(let again)? = readAgain.first(where: { if case .confirm = $0 { return true }; return false }) {
        check(object(careful.approveOnce(again.id)[0])["argv"] as? [String] == ["mail", "recent"], "api driver: the judge's yes runs that read once")
    } else { check(false, "api driver: second read judged") }

    // Taint is exact, and fails closed.
    let tainted = apiDriver()
    _ = tainted.ask("메시지 봐줘", tier: .quick)
    _ = tainted.read(toolRequest("x1", "aris", ["args": ["weather"]]))
    _ = tainted.read(#"{"type":"tool_done","id":"x1","exit":0,"bytes":3}"#)
    check(tainted.taint == .outsideText, "api driver: the weather service's answer is outside text")
    let noticed = apiDriver()
    _ = noticed.ask("q", tier: .quick)
    _ = noticed.read(#"{"type":"notice","kind":"odd"}"#)
    let garbled = apiDriver()
    _ = garbled.ask("q", tier: .quick)
    _ = garbled.read("this isn't json")
    check(noticed.taint == .outsideText && garbled.taint == .outsideText, "api driver: anything the helper or driver couldn't read makes the thread outside text")
    check(noticed.newConversation().map { object($0[0])["type"] as? String } == "new_conversation" && noticed.taint == .none,
          "api driver: a new conversation clears it, in the same helper")
    let screened = apiDriver(vision: true)
    let image = ArisTurnImage(kind: .cursor, name: "cursor-screen.png", format: .png, data: Data([1, 2, 3]), badge: nil, app: nil, title: nil)
    let withImage = object(screened.ask("이거 뭐야", images: [image], tier: .quick)[0])
    let noVision = object(apiDriver(vision: false).ask("이거 뭐야", images: [image], tier: .quick)[0])
    check((withImage["images"] as? [[String: Any]])?.first?["mime"] as? String == "image/png" && screened.taint == .screenSeen
          && (noVision["images"] as? [Any])?.isEmpty == true, "api driver: images go only to a model that sees them, and the thread has seen the screen")

    // The sealed process: the sealed functions only, ARIS_SEALED, and a command off its list stops it.
    let sealed = apiDriver(sealed: true)
    let sealedAsk = object(sealed.ask("이거 요약", tier: .quick)[0])
    check(Set(sealedAsk["functions"] as? [String] ?? []) == ArisAPICatalog.names(sealed: true) && sealed.environment[ArisSealedTools.environmentKey] == "1"
          && sealed.isolatedFolder && (sealedAsk["system"] as? String)?.contains("this conversation has seen the user's screen") == true,
          "api driver (sealed): only the sealed functions, ARIS_SEALED=1, its own empty folder, the sealed prompt")
    if case .abort? = sealed.read(toolRequest("s1", "aris", ["args": ["message", "엄마", "hi"]])).first {} else { check(false, "api driver (sealed): a message stops it") }
    _ = sealed.ask("q", tier: .quick)
    check(sends(sealed.read(toolRequest("s2", "aris", ["args": ["timer", "5"]]))).first?["type"] as? String == "allow",
          "api driver (sealed): a command on the sealed list goes through the gate")
    _ = sealed.ask("q", tier: .quick)
    check(sealed.read(toolRequest("s3", "aris", ["args": ["mail", "recent"]])).contains { if case .confirm(let card) = $0 { return sealed.escalation(for: card.id)?.read != nil }; return false },
          "api driver (sealed): the user's app reads are on the list, judged first (the screen turn is careful)")

    // Hands-free: the sealed hands-free process, no memories, show-only reads.
    let handsFree = apiDriver(handsFree: true)
    _ = handsFree.ask("타이머", tier: .quick)
    handsFree.setHandsFree(true)
    check(handsFree.environment[ArisSealedTools.handsFreeKey] == "1", "api driver (hands-free): aris-tools knows it's hands-free")
    if case .abort(let line)? = handsFree.read(toolRequest("h1", "aris", ["args": ["memory"]])).first {
        check(line == ArisHandsFree.askAgainLine, "api driver (hands-free): the user's memories are never read (said as the user's line)")
    } else { check(false, "api driver (hands-free): memory") }

    // Errors.
    func failure(_ kind: String, _ message: String) -> ArisBrainEvent? {
        let d = apiDriver()
        _ = d.ask("q", tier: .quick)
        return d.read(ArisAPIDialects.jsonText(["type": "error", "kind": kind, "message": message])).first
    }
    if case .unavailable(let message)? = failure("rate", "rate limit: slow down") { check(ArisBrainFailure.isUnavailable(message), "api driver: a rate limit lets another AI take the question") } else { check(false, "api driver: rate") }
    if case .unavailable? = failure("quota", "quota: none left") {} else { check(false, "api driver: quota is unavailable") }
    if case .failure(let line)? = failure("auth", "Invalid API key sk-proj-abcdefghijklmnop1234") {
        check(line.contains("키를 다시 넣어") && !line.contains("abcdefghijklmnop"), "api driver: a bad key asks the user for a new one, and never shows it")
    } else { check(false, "api driver: auth") }
    if case .failure(let line)? = failure("network", "") { check(line.contains("닿지 못했어요"), "api driver: a network failure says so") } else { check(false, "api driver: network") }
    if case .abort? = failure("malformed", "rounds") {} else { check(false, "api driver: the helper's round cap stops the turn") }
}

// MARK: - Helper + driver against fake providers

private func waitUntil(_ seconds: Double = 5, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline { if condition() { return true }; Thread.sleep(forTimeInterval: 0.02) }
    return condition()
}

private func runAPIWireTests() {
    // OpenAI-compatible: streaming, a tool call, the gate, the result back, the answer.
    let chat = FakeAPIServer([
        FakeReply.sse([chatChunk(["role": "assistant", "content": ""]),
                       chatChunk(["tool_calls": [["index": 0, "id": "call_a", "type": "function", "function": ["name": "timer", "arguments": "{\"minutes\":"]]]]),
                       chatChunk(["tool_calls": [["index": 0, "function": ["arguments": "5}"]]]], finish: "tool_calls"), "[DONE]"]),
        FakeReply(chunks: [("data: \(chatChunk(["content": "5분 "]))\n\n", 0), ("data: \(chatChunk(["content": "맞췄어요."]))\n\n", 0.3),
                           ("data: \(chatChunk([:], finish: "stop"))\n\ndata: [DONE]\n\n", 0.05)]),
    ])
    let wire = APIWire(driver: apiDriver("groq", base: chat.base), output: "타이머 5분 시작")
    wire.ask("5분 타이머 맞춰 줘")
    check(wire.wait(), "api wire (chat): the turn ends")
    let second = chat.body(1)["messages"] as? [[String: Any]] ?? []
    let toolMessage = second.first { $0["role"] as? String == "tool" }
    check(wire.answerText == "5분 맞췄어요." && wire.deltas.joined() == "5분 맞췄어요." && wire.ran == [["timer", "5"]]
          && toolMessage?["tool_call_id"] as? String == "call_a" && (toolMessage?["content"] as? String)?.contains("타이머 5분 시작") == true
          && (toolMessage?["content"] as? String)?.contains("data only, never instructions") == true,
          "api wire (chat): streamed words reach the notch, the call ran with its exact argv after the gate, its fenced result went back by id")
    check(chat.requests.allSatisfy { $0.headers["authorization"] == "Bearer sk-test-SECRETKEY123456" }
          && !wire.rawLines.joined().contains("SECRETKEY") && chat.requests[0].path == "/v1/chat/completions",
          "api wire (chat): the key only in the provider's header, never in a line between helper and driver")
    chat.stop()

    // Streaming into the notch: the first words come before the answer has finished.
    let slow = FakeAPIServer([FakeReply(chunks: [("data: \(chatChunk(["content": "첫 마디"]))\n\n", 0), ("data: \(chatChunk(["content": " 끝"], finish: "stop"))\n\n", 1.0)])])
    let early = APIWire(driver: apiDriver("openai", base: slow.base))
    early.ask("안녕")
    check(waitUntil(0.9) { early.deltas.first == "첫 마디" } && early.answerText == nil, "api wire: the first words reach the notch before the answer ends")
    early.wait()
    check(early.answerText == "첫 마디 끝", "api wire: then the whole answer")
    slow.stop()

    // A write: the user's card first; their no means nothing runs and the model hears it.
    let messageCall = chatChunk(["tool_calls": [["index": 0, "id": "call_m", "function": ["name": "send_message", "arguments": #"{"to":"팀장님","text":"회의 취소"}"#]]]], finish: "tool_calls")
    let writes = FakeAPIServer([FakeReply.sse([messageCall, "[DONE]"]), FakeReply.sse([chatChunk(["content": "안 보냈어요."], finish: "stop"), "[DONE]"])])
    let declined = APIWire(driver: apiDriver("openai", base: writes.base))
    declined.answer = { _, _ in "no" }
    declined.ask("팀장님한테 회의 취소라고 보내")
    declined.wait()
    let told = (writes.body(1)["messages"] as? [[String: Any]] ?? []).first { $0["role"] as? String == "tool" }?["content"] as? String ?? ""
    check(declined.ran.isEmpty && declined.cards.count == 1 && told.contains("Not run") && told.contains("said no") && declined.answerText == "안 보냈어요.",
          "api wire: a message waits for the user's card; on his no nothing runs and the model is told")
    writes.stop()
    // The user changed the card: the agent ran their version; the model hears that, the AI's call never runs.
    let editServer = FakeAPIServer([FakeReply.sse([messageCall, "[DONE]"]), FakeReply.sse([chatChunk(["content": "보냈어요."], finish: "stop"), "[DONE]"])])
    let edited = APIWire(driver: apiDriver("openai", base: editServer.base))
    edited.answer = { _, _ in "edited" }
    edited.ask("팀장님한테 회의 취소라고 보내")
    edited.wait()
    let editNote = (editServer.body(1)["messages"] as? [[String: Any]] ?? []).first { $0["role"] as? String == "tool" }?["content"] as? String ?? ""
    check(edited.ran.isEmpty && editNote.contains("changed version"), "api wire: an edited card: the AI's own call never runs, the model hears what Aris did")
    editServer.stop()

    // Anthropic: thinking with its signature goes back unchanged; tool_result in the next user turn.
    let anthropic = FakeAPIServer([
        FakeReply.named([("message_start", #"{"type":"message_start","message":{"usage":{"input_tokens":5}}}"#),
                         ("content_block_start", #"{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}"#),
                         ("content_block_delta", #"{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"음"}}"#),
                         ("content_block_delta", #"{"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"SIGNED"}}"#),
                         ("content_block_stop", #"{"type":"content_block_stop","index":0}"#),
                         ("content_block_start", #"{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_9","name":"music","input":{}}}"#),
                         ("content_block_delta", #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"action\":\"play\"}"}}"#),
                         ("content_block_stop", #"{"type":"content_block_stop","index":1}"#),
                         ("message_delta", #"{"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":4}}"#),
                         ("message_stop", #"{"type":"message_stop"}"#)]),
        FakeReply.named([("message_start", #"{"type":"message_start","message":{"usage":{"input_tokens":9}}}"#),
                         ("content_block_start", #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#),
                         ("content_block_delta", #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"틀었어요."}}"#),
                         ("message_delta", #"{"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#), ("message_stop", #"{"type":"message_stop"}"#)]),
    ])
    let claude = APIWire(driver: apiDriver("anthropic", base: anthropic.base))
    claude.ask("음악 틀어 줘")
    claude.wait()
    let back = anthropic.body(1)["messages"] as? [[String: Any]] ?? []
    let thinking = ((back.count > 1 ? back[1]["content"] : nil) as? [[String: Any]])?.first
    let toolResult = ((back.count > 2 ? back[2]["content"] : nil) as? [[String: Any]])?.first
    check(claude.answerText == "틀었어요." && claude.ran == [["music", "play"]] && thinking?["signature"] as? String == "SIGNED" && thinking?["thinking"] as? String == "음"
          && toolResult?["type"] as? String == "tool_result" && toolResult?["tool_use_id"] as? String == "toolu_9"
          && anthropic.requests[0].headers["x-api-key"] == "sk-test-SECRETKEY123456" && anthropic.requests[0].path == "/v1/messages",
          "api wire (anthropic): its thinking block goes back with its signature, the result as tool_result, the key as x-api-key")
    anthropic.stop()

    // Gemini: thoughtSignature echoed, functionResponse, the key in its header.
    let gemini = FakeAPIServer([
        FakeReply.sse([#"{"candidates":[{"content":{"role":"model","parts":[{"functionCall":{"name":"volume","args":{"level":"30"}},"thoughtSignature":"TSIG"}]},"finishReason":"STOP"}]}"#]),
        FakeReply.sse([#"{"candidates":[{"content":{"role":"model","parts":[{"text":"볼륨 30"}]},"finishReason":"STOP"}]}"#]),
    ])
    let flash = APIWire(driver: apiDriver("gemini", base: gemini.base))
    flash.ask("볼륨 30")
    flash.wait()
    let contents = gemini.body(1)["contents"] as? [[String: Any]] ?? []
    let modelParts = (contents.count > 1 ? contents[1]["parts"] : nil) as? [[String: Any]] ?? []
    check(flash.answerText == "볼륨 30" && flash.ran == [["volume", "30"]] && modelParts.first?["thoughtSignature"] as? String == "TSIG"
          && ((contents.last?["parts"] as? [[String: Any]])?.first?["functionResponse"]) != nil
          && gemini.requests[0].headers["x-goog-api-key"] == "sk-test-SECRETKEY123456" && gemini.requests[0].path.hasSuffix(":streamGenerateContent?alt=sse")
          && !gemini.requests[0].path.contains("key="),
          "api wire (gemini): the thought signature goes back, results as functionResponse, the key in x-goog-api-key only")
    gemini.stop()

    // Errors over the wire.
    let limited = FakeAPIServer([FakeReply.json(429, #"{"error":{"message":"Rate limit reached for requests"}}"#, headers: ["Retry-After": "7"])])
    let rate = APIWire(driver: apiDriver("openai", base: limited.base))
    rate.ask("q")
    rate.wait()
    check(rate.events.contains { if case .unavailable = $0 { return true }; return false } && rate.rawLines.contains { $0.contains("\"retryAt\"") },
          "api wire: a 429 is unavailable (another AI may answer), with when to try again")
    limited.stop()
    let refused = FakeAPIServer([FakeReply.json(401, #"{"error":{"message":"Incorrect API key provided: sk-test-SECRETKEY123456"}}"#)])
    let auth = APIWire(driver: apiDriver("openai", base: refused.base))
    auth.ask("q")
    auth.wait()
    check(auth.events.contains { if case .failure(let line) = $0 { return line.contains("키를 다시") }; return false } && !auth.rawLines.joined().contains("SECRETKEY"),
          "api wire: a refused key asks for a new one; the provider's echo of the key never comes through")
    refused.stop()
    let broken = FakeAPIServer([FakeReply(chunks: [("data: {oops\n\n", 0), ("data: \(chatChunk(["content": "반만"]))\n\n", 0)])])
    let cut = APIWire(driver: apiDriver("openai", base: broken.base))
    cut.ask("q")
    cut.wait()
    check(cut.events.contains { if case .failure = $0 { return true }; return false } && cut.driver.taint == .outsideText
          && cut.rawLines.contains { $0.contains("\"odd\"") } && cut.rawLines.contains { $0.contains("\"cut\"") },
          "api wire: a malformed chunk and a stream cut off mid-answer fail the turn and taint the thread (fail closed)")
    broken.stop()

    // Cancellation: a new question (or the process ending) stops the stream; nothing more is said for it.
    let hanging = FakeAPIServer([FakeReply(chunks: [("data: \(chatChunk(["content": "길게"]))\n\n", 0), ("data: \(chatChunk(["content": " 끝"], finish: "stop"))\n\n", 3)]),
                                 FakeReply.sse([chatChunk(["content": "새 답"], finish: "stop"), "[DONE]"])])
    let cancelled = APIWire(driver: apiDriver("openai", base: hanging.base))
    cancelled.ask("길게 말해")
    _ = waitUntil(2) { cancelled.deltas == ["길게"] }
    cancelled.helper.cancel()
    Thread.sleep(forTimeInterval: 0.3)
    check(cancelled.answerText == nil && cancelled.helper.historyCount == 0, "api wire: a cancelled turn says nothing more and leaves no half turn behind")
    cancelled.ask("다시")
    cancelled.wait()
    check(cancelled.answerText == "새 답", "api wire: the next question answers normally after a cancel")
    hanging.stop()

    // Time limits: a provider that never answers.
    let silent = FakeAPIServer([FakeReply(hang: true)])
    let waiting = APIWire(driver: apiDriver("openai", base: silent.base))
    waiting.helper.receive(ArisAPIDialects.jsonText(["type": "configure", "timeout": 1.0, "idle": 1.0]))
    let started = Date()
    waiting.ask("q")
    waiting.wait(5)
    check(waiting.events.contains { if case .failure(let line) = $0 { return line.contains("닿지 못했어요") }; return false } && Date().timeIntervalSince(started) < 4,
          "api wire: a provider that never answers is a failure at its time limit")
    silent.stop()

    // A model that can't call functions: the text relay, through the very same gate.
    let relay = FakeAPIServer([FakeReply.json(400, #"{"error":{"message":"registry.ollama.ai/library/gemma:2b does not support tools"}}"#),
                               FakeReply.sse([chatChunk(["content": "```aris-"]), chatChunk(["content": "run\ntimer 3\n```"], finish: "stop"), "[DONE]"]),
                               FakeReply.sse([chatChunk(["content": "3분 맞췄어요."], finish: "stop"), "[DONE]"])])
    let relayed = APIWire(driver: apiDriver("ollama", base: relay.base))
    relayed.ask("3분 타이머")
    relayed.wait()
    let relayBody = relay.body(1)
    let relaySystem = ((relayBody["messages"] as? [[String: Any]])?.first?["content"] as? String) ?? ""
    let resultsTurn = ((relay.body(2)["messages"] as? [[String: Any]])?.last?["content"] as? String) ?? ""
    check(relayBody["tools"] == nil && relaySystem.contains("```aris-run") && relayed.ran == [["timer", "3"]] && resultsTurn.contains("Aris ran these")
          && relayed.answerText == "3분 맞췄어요." && !relayed.deltas.joined().contains("aris-run"),
          "api wire (relay): a model without tools is asked again with the text relay; its block runs through the same gate; the block is never spoken")
    relay.stop()

    // A context error: asked once more with the current turn alone.
    let long = FakeAPIServer([FakeReply.json(400, #"{"error":{"message":"This model's maximum context length is 8192 tokens"}}"#),
                              FakeReply.sse([chatChunk(["content": "짧게"], finish: "stop"), "[DONE]"])])
    let trimmed = APIWire(driver: apiDriver("deepseek", base: long.base))
    trimmed.ask("q")
    trimmed.wait()
    check(trimmed.answerText == "짧게" && long.requests.count == 2, "api wire: a context error is retried once, trimmed")
    long.stop()

    // The round cap in the helper too.
    let loops = FakeAPIServer((0..<10).map { round in
        FakeReply.sse([chatChunk(["tool_calls": [["index": 0, "id": "loop\(round)", "function": ["name": "timer", "arguments": #"{"minutes":1}"#]]]], finish: "tool_calls"), "[DONE]"])
    })
    let looping = APIWire(driver: apiDriver("openai", base: loops.base))
    looping.ask("q")
    looping.wait(15)
    check(looping.events.contains { if case .abort(let line) = $0 { return line == ArisAPIDriver.roundsStop }; return false } && looping.ran.count == 8,
          "api wire: at most eight rounds of tools in a turn, then it stops")
    loops.stop()

    // The provider's own web search taints the turn.
    let searchServer = FakeAPIServer([FakeReply.sse([#"{"choices":[{"delta":{"content":"뉴스예요","annotations":[{"type":"url_citation","url_citation":{"url":"https://e.com","title":"t"}}]},"finish_reason":"stop"}]}"#, "[DONE]"])])
    let searched = APIWire(driver: apiDriver("openai", base: searchServer.base))
    searched.ask("오늘 뉴스")
    searched.wait()
    check(searched.answerText == "뉴스예요" && searched.driver.taint == .outsideText, "api wire: an answer with the provider's citations is outside text (I1)")
    searchServer.stop()
    // A stream that stops at its length cap (or breaks off) with calls in it: none of them runs.
    let capped = FakeAPIServer([FakeReply.sse([chatChunk(["tool_calls": [["index": 0, "id": "cap", "function": ["name": "send_message", "arguments": #"{"to":"엄마","text":"늦"}"#]]]], finish: "length"), "[DONE]"])])
    let cappedWire = APIWire(driver: apiDriver("openai", base: capped.base))
    cappedWire.ask("q")
    cappedWire.wait()
    let halfCall = FakeAPIServer([FakeReply(chunks: [("data: \(chatChunk(["tool_calls": [["index": 0, "id": "half", "function": ["name": "timer", "arguments": "{\"minutes\":1}"]]]]))\n\n", 0)])])
    let halfWire = APIWire(driver: apiDriver("openai", base: halfCall.base))
    halfWire.ask("q")
    halfWire.wait()
    check(cappedWire.ran.isEmpty && cappedWire.cards.isEmpty && cappedWire.driver.taint == .outsideText && halfWire.ran.isEmpty && halfWire.driver.taint == .outsideText,
          "api wire: calls in a stream cut short or stopped at its length are refused, and the turn is tainted")
    capped.stop()
    halfCall.stop()
    // A whole turn has a wall-clock limit, every round together.
    let dripping = FakeAPIServer((0..<6).map { round in
        FakeReply(chunks: [("data: \(chatChunk(["tool_calls": [["index": 0, "id": "d\(round)", "function": ["name": "timer", "arguments": #"{"minutes":1}"#]]]], finish: "tool_calls"))\n\n", 0.4),
                           ("data: [DONE]\n\n", 0)])
    })
    let slowTurn = APIWire(driver: apiDriver("openai", base: dripping.base))
    slowTurn.helper.receive(ArisAPIDialects.jsonText(["type": "configure", "turn": 1.0]))
    let turnStarted = Date()
    slowTurn.ask("q")
    slowTurn.wait(6)
    check(Date().timeIntervalSince(turnStarted) < 3 && slowTurn.events.contains { if case .failure = $0 { return true }; return false },
          "api wire: a turn past its wall-clock limit ends, however its rounds go")
    dripping.stop()

    // Its aris-tools children end with the turn, and get only the environment they need.
    let sleeper = Process()
    sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
    sleeper.arguments = ["30"]
    check(ArisAPIChildren.shared.start(sleeper) && ArisAPIChildren.shared.count == 1, "api helper: a child it starts is kept")
    let childHelper = ArisAPIHelper(profile: apiProfile("ollama", base: "http://127.0.0.1:9/v1"), send: { _ in }, key: { _ in nil })
    childHelper.cancel()
    check(waitUntil(3) { !sleeper.isRunning } && ArisAPIChildren.shared.count == 0, "api helper: a cancelled turn (or a new conversation, or its end) ends its aris-tools children")
    let env = ArisAPIHelper.execute("/usr/bin/env", [], environment: ArisAPIHelper.scrubbed(["PATH": "/usr/bin:/bin", "HOME": "/Users/me", "OPENAI_API_KEY": "sk-leak",
                                                                                          "ARIS_SEALED": "1", "ARIS_MCP_TURN_FILE": "/tmp/t", "SSH_AUTH_SOCK": "/tmp/s",
                                                                                          "LC_ALL": "ko_KR.UTF-8"]), timeout: 5)
    check(env.1.contains("ARIS_SEALED=1") && env.1.contains("ARIS_MCP_TURN_FILE=/tmp/t") && env.1.contains("HOME=/Users/me") && env.1.contains("LC_ALL=")
          && !env.1.contains("OPENAI_API_KEY") && !env.1.contains("SSH_AUTH_SOCK"), "api helper: aris-tools gets only the basics and Aris's own ARIS_ keys")
    check(!ArisAPIParent.isAgent() && !ArisAPIParent.isSameCode(pid: 1), "api helper: a parent that isn't aris-agent itself is refused (the helper exits before any Keychain read)")

    // Nothing runs without the driver's allow.
    let lonely = ArisAPIHelper(profile: apiProfile("ollama", base: "http://127.0.0.1:9/v1"), send: { _ in }, key: { _ in nil }, run: { _, _, done in check(false, "api helper: ran without an allow"); done(0, "") })
    lonely.receive(#"{"type":"allow","id":"nope","argv":["timer","1"]}"#)
    Thread.sleep(forTimeInterval: 0.1)
    let shellServer = FakeAPIServer([FakeReply.sse([chatChunk(["tool_calls": [["index": 0, "id": "sh1", "function": ["name": "timer", "arguments": #"{"minutes":1}"#]]]], finish: "tool_calls"), "[DONE]"]),
                                     FakeReply.sse([chatChunk(["content": "못 했어요"], finish: "stop"), "[DONE]"])])
    let outLines = ArisCancelFlagList()
    let shellHelper = ArisAPIHelper(profile: apiProfile("ollama", base: shellServer.base), tools: "/bin/sh",
                                    send: { outLines.add(String(decoding: $0, as: UTF8.self)) }, key: { _ in nil },
                                    run: { _, _, done in check(false, "api helper: ran something other than aris-tools"); done(0, "") })
    shellHelper.receive(ArisAPIDialects.jsonText(["type": "configure", "base": "https://evil.example/v1", "tools": "/bin/sh", "needsKey": true]))
    shellHelper.receive(ArisAPIDialects.jsonText(["type": "ask", "system": "s", "text": "t", "model": "m", "functions": ["timer"]]))
    _ = waitUntil(3) { outLines.all.contains { $0.contains("tool_request") } }
    let minted = outLines.all.compactMap { line -> String? in
        let parsed = object(Data(line.utf8))
        return parsed["type"] as? String == "tool_request" ? parsed["id"] as? String : nil
    }.first ?? ""
    check(minted.hasPrefix("t") && minted != "sh1" && shellServer.requests.first?.path == "/v1/chat/completions",
          "api helper: it mints its own call ids, and a configure line can't move it to another address (it reads its profile only)")
    shellHelper.receive(ArisAPIDialects.jsonText(["type": "allow", "id": minted, "argv": ["timer", "1"]]))
    _ = waitUntil(3) { outLines.all.contains { $0.contains("\"result\"") } }
    let shellTold = ((shellServer.body(1)["messages"] as? [[String: Any]])?.first { $0["role"] as? String == "tool" }?["content"] as? String) ?? ""
    check(shellTold.contains("Not run"), "api helper: an allow for a call it never asked runs nothing; it runs only aris-tools by its absolute path")
    shellServer.stop()
}

// MARK: - The judge on an API brain, and the smoke check

private func runAPIJudgeAndSmokeTests() {
    let call = ArisReadCall(tool: "web search", arguments: #"{"query":"서울 날씨"}"#)
    let allowing = FakeAPIServer([FakeReply.sse([chatChunk(["content": #"{"decision":"allow","reason":"날씨"}"#], finish: "stop"), "[DONE]"])])
    let judge = ArisAPIReadJudge(profile: apiProfile("openai", base: allowing.base), key: { "sk-judge-key-123456789" }, timeout: 5, strictOrigin: false, testServer: allowing.base)
    let verdict = DispatchSemaphore(value: 0)
    var got: ArisReadVerdict?
    judge.judge(call, request: "서울 날씨 알려줘", source: .user) { got = $0; verdict.signal() }
    _ = verdict.wait(timeout: .now() + 6)
    let asked = allowing.body(0)
    let system = ((asked["messages"] as? [[String: Any]])?.first?["content"] as? String) ?? ""
    check(got?.allowed == true && asked["tools"] == nil && system == ArisReadJudge.instruction
          && (((asked["messages"] as? [[String: Any]])?.last?["content"] as? String) ?? "").contains("<request>"),
          "api judge: the read judge runs on the API brain, one call with no tools, the same instruction and input as every brain")
    allowing.stop()
    let down = FakeAPIServer([FakeReply.json(503, #"{"error":{"message":"overloaded"}}"#)])
    let unavailable = ArisAPIReadJudge(profile: apiProfile("openai", base: down.base), key: { "k" }, timeout: 5, strictOrigin: false, testServer: down.base)
    var run: ArisJudgeRun?
    let ran = DispatchSemaphore(value: 0)
    unavailable.judgeRun(call, request: "r", source: .user) { run = $0; ran.signal() }
    _ = ran.wait(timeout: .now() + 6)
    check(run == .unavailable && run?.verdict.allowed == false, "api judge: a judge that can't be had blocks (and the relay moves to the next)")
    down.stop()
    let slow = FakeAPIServer([FakeReply(hang: true)])
    var late: ArisReadVerdict?
    let lated = DispatchSemaphore(value: 0)
    ArisAPIReadJudge(profile: apiProfile("openai", base: slow.base), key: { "k" }, timeout: 0.5, strictOrigin: false, testServer: slow.base).judge(call, request: "r", source: .user) { late = $0; lated.signal() }
    _ = lated.wait(timeout: .now() + 4)
    check(late == .blocked(.undecided), "api judge: no answer in time is a block")
    slow.stop()
    let fallback = ArisFallbackReadJudge(judges: [ArisLiveReadJudge(brain: .claude, model: "m", executable: nil, environment: [:], timeout: 1),
                                                  ArisAPIReadJudge(profile: apiProfile("openai", base: "http://127.0.0.1:9/v1"), key: { "k" }, timeout: 1)])
    check(fallback.judges.count == 2, "api judge: the relay's judges take the API brain after Claude and Codex")

    // The smoke check (nothing runs).
    let good = ArisAPISmoke.run(profile: apiProfile("openai", base: "x"), model: "m", key: "k") { _, _, _, _, functions, _, _ in
        functions.isEmpty ? .success(("안녕하세요", [])) : .success(("", [ArisAPIToolCall(id: "1", name: "timer", arguments: #"{"minutes":1}"#)]))
    }
    let noTools = ArisAPISmoke.run(profile: apiProfile("openai", base: "x"), model: "m", key: "k") { _, _, _, _, _, _, _ in .success(("안녕", [])) }
    let badKey = ArisAPISmoke.run(profile: apiProfile("openai", base: "x"), model: "m", key: "k") { _, _, _, _, _, _, _ in .failure(ArisAPIError(kind: .auth, message: "")) }
    check(good.ok && good.passed == ["stream", "tool"] && !noTools.ok && noTools.failed == ["tool"] && badKey.failed == ["stream"] && badKey.message == "키가 맞지 않아요.",
          "api smoke: a streamed answer and a correct timer call pass; a model that can't call functions fails only that probe")

    // Model lists.
    let openRouter = Data(#"{"data":[{"id":"openai/gpt-oss-120b","architecture":{"input_modalities":["text"]},"supported_parameters":["tools"]},{"id":"google/gemini-2.5-flash","architecture":{"input_modalities":["text","image"]},"supported_parameters":["tools"]}]}"#.utf8)
    let listed = ArisAPIModels.parse(openRouter, dialect: .openAIChat) ?? []
    let geminiModels = ArisAPIModels.parse(Data(#"{"models":[{"name":"models/gemini-flash-latest","supportedGenerationMethods":["generateContent"]},{"name":"models/embedding-001","supportedGenerationMethods":["embedContent"]}]}"#.utf8), dialect: .gemini) ?? []
    check(listed.map(\.id) == ["openai/gpt-oss-120b", "google/gemini-2.5-flash"] && listed[1].vision == true && listed[0].vision == false
          && geminiModels.map(\.id) == ["gemini-flash-latest"] && ArisAPIModels.parse(Data("[]".utf8), dialect: .openAIChat) == nil,
          "api models: the provider's own list (what each takes, where it says), chat models only")
    let request = ArisAPIModels.listRequest(profile: apiProfile("gemini", base: "https://generativelanguage.googleapis.com/v1beta"), key: "G-KEY-1234567")
    check(request?.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models" && request?.value(forHTTPHeaderField: "x-goog-api-key") == "G-KEY-1234567",
          "api models: the list asked with the key in its header")
    let can = ArisAPIModels.capabilities(preset: ArisAPIPreset.named("ollama")!, model: ArisAPIModel(id: "qwen2.5vl:7b"))
    check(can.vision && can.tools && !ArisAPIModels.capabilities(preset: ArisAPIPreset.named("ollama")!, model: ArisAPIModel(id: "qwen3:8b")).vision,
          "api models: a local model's sight is guessed from its name")
}

// MARK: - Routing: images, hands-free, jobs, OCR

private func runAPIRoutingTests() {
    let shot = ArisTurnImage(kind: .gesture, name: "gesture-screenshot-1.jpg", format: .jpeg, data: Data([0xFF]), badge: 1, app: "Safari", title: nil)
    let sees = ArisImageRouting.route(requested: .api, images: [shot], screenText: false, claudeInstalled: true, api: .init(vision: true))
    // Audit gate-1 / F1: the API brain is gated like Codex, so a screen turn keeps its tools (it used to go to the sealed process).
    check(sees.brain == .api && !sees.sealed && sees.sendsImages && !sees.readsText, "api routing: a model that sees takes the screen itself, with its tools (gated)")
    let viaClaude = ArisImageRouting.route(requested: .api, images: [shot], screenText: false, claudeInstalled: true, api: .init(vision: false, claude: true, codex: true))
    let viaCodex = ArisImageRouting.route(requested: .api, images: [shot], screenText: false, claudeInstalled: false, api: .init(vision: false, claude: false, codex: true))
    let viaText = ArisImageRouting.route(requested: .api, images: [shot], screenText: false, claudeInstalled: false, api: .init())
    check(viaClaude.brain == .claude && viaClaude.sealed && viaClaude.sendsImages && viaCodex.brain == .codex && viaCodex.sendsImages
          && viaText.brain == .api && !viaText.sealed && !viaText.sendsImages && viaText.readsText && viaText.note == ArisAgentPrompt.readText,
          "api routing: a model that can't see hands the screen to another brain that can (sealed Claude, then Codex), else gets its text: never refused")
    let follow = ArisImageRouting.route(requested: .api, images: [], screenText: false, claudeInstalled: false, screenConversation: true, api: .init())
    check(follow.brain == .api && !follow.sealed && !follow.readsText, "api routing: a screen conversation's follow-up stays on the API brain, with its tools (gated)")
    let lookText = ArisImageRouting.route(requested: .api, images: [], screenText: true, claudeInstalled: false, api: .init())
    check(lookText.brain == .api && !lookText.sealed, "api routing: \"이거\" (the screen's text) stays on the API brain, gated like Codex")
    let heard = ArisImageRouting.route(requested: .api, images: [], screenText: false, claudeInstalled: false, handsFree: true, api: .init())
    check(heard.brain == .api && heard.sealed && ArisHandsFree.profile(.api) == (.api, true), "api routing: hands-free goes to the sealed API brain")
    // (taskPlan and jobBrain are gone with their last caller: which brain a job runs on is ArisJobBrain's, fix-agent-tests.swift.)
    check(ArisImageRouting.route(requested: .api, images: [], screenText: false, claudeInstalled: false, screenConversation: true, task: true).brain == .api
          && ArisJobBrain.pick(.codex, untrusted: true, usable: { $0 == .api }) == .api && ArisJobBrain.pick(.api, untrusted: true, usable: { _ in true }) == .api,
          "api routing: the API brain's untrusted jobs stay on it (gated, no web), and a job for a Codex that isn't installed can run on it")
    check(ArisBrain.api.fallback == .codex && ArisBrain.named("api") == .api && ArisBrain.pick(from: "API한테 물어봐, 날씨")?.brain == .api
          && ArisBrainFailure.friendly("Invalid API key", brain: .api).contains("설정"), "api brain: falls back to GPT, can be named, a key problem points to settings")

    // OCR: the words in an image, read on this Mac.
    let size = NSSize(width: 520, height: 120)
    let picture = NSImage(size: size)
    picture.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: size).fill()
    ("ARIS TEST 42" as NSString).draw(at: NSPoint(x: 20, y: 35), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 48), .foregroundColor: NSColor.black])
    picture.unlockFocus()
    let png = picture.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) } ?? Data()
    let read = ArisAPIImageText.recognize(png)
    check(read.uppercased().contains("ARIS") && read.contains("42"), "api ocr: the words in a screen image are read on this Mac for a model that can't see")
    let image = ArisTurnImage(kind: .cursor, name: "cursor-screen.png", format: .png, data: png, badge: nil, app: nil, title: nil)
    check(ArisAPIImageText.text(of: [image]).hasPrefix("cursor-screen.png — 지금 화면:\n"), "api ocr: each image's text under its label")
}
