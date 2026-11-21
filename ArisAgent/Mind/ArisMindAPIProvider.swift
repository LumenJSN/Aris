//
//  ArisMindAPIProvider.swift
//  aris-agent
//
//  A model provider for the Mind with an API key (Anthropic, OpenAI-compatible, Gemini) or a local server: the
//  conversation and the tools' schemas go out in the provider's own wire format (ArisAPIDialects), its stream comes
//  back as text and whole tool calls (ArisAPIStreamDecoder). The provider only thinks: it is offered Aris's tools and
//  runs none. The key is asked for per round and goes only to its provider's own host (ArisAPIDialects.request); it is
//  never logged. A failure is said as it is, never retried on another provider.
//

import Foundation

final class ArisMindAPIProvider: ArisMindProvider, @unchecked Sendable {
    let profile: ArisAPIProfile
    let model: String
    private let key: () -> String?
    private let strictOrigin: Bool
    private let base: String?
    var maxTokens = 4_096
    var totalTimeout: TimeInterval = 110
    var idleTimeout: TimeInterval = 60
    private let queue = DispatchQueue(label: "com.lumenjsn.aris.mind-provider")
    private let lock = NSLock()
    private var task: ArisAPIStreamTask?

    /// `base`: the tests' fake server on 127.0.0.1 (with `strictOrigin` off); never set otherwise.
    init(profile: ArisAPIProfile, tier: ArisTier = .quick, key: @escaping () -> String?, strictOrigin: Bool = true, base: String? = nil) {
        self.profile = profile
        model = profile.model(tier: tier)
        self.key = key
        self.strictOrigin = strictOrigin
        self.base = base
    }

    static let noKey = "API 키가 없어요. 설정에서 키를 넣어 주세요. (No API key: add one in Settings.)"
    static let noRequest = "이 제공자에 요청을 만들 수 없어요. (Couldn't make a request for this provider.)"

    /// A provider's error for the loop: its kind in front, so the driver can say it in plain words (the message itself
    /// is never shown: ArisMindBrainDriver).
    static func tagged(_ error: ArisAPIError) -> String { "[" + error.kind.rawValue + "] " + error.message }

    /// The kind `tagged` put in front, when there is one.
    static func kind(of failure: String) -> ArisAPIError.Kind? {
        guard failure.hasPrefix("["), let close = failure.firstIndex(of: "]") else { return nil }
        return ArisAPIError.Kind(rawValue: String(failure[failure.index(after: failure.startIndex)..<close]))
    }

    /// Aris's own failure lines, said as they are.
    static let ownLines: Set<String> = [noKey, noRequest]

    static func entries(_ messages: [ArisMindMessage]) -> [ArisAPIEntry] {
        messages.map { message in
            switch message {
            case .owner(let text): return .user(text: text, images: [])
            case .assistant(let text, let calls):
                return .assistant(text: text, calls: calls.map { ArisAPIToolCall(id: $0.id, name: $0.name, arguments: $0.arguments) }, echo: nil)
            case .tool(let id, let name, let text, let isError): return .tool(id: id, name: name, text: isError ? "Error: " + text : text)
            }
        }
    }

    static func functions(_ tools: [ArisMindToolSpec]) -> [ArisAPIFunction] {
        tools.map { tool in
            let schema = (tool.schema.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? ["type": "object", "properties": [:]]
            return ArisAPIFunction(name: tool.name, description: tool.description, parameters: schema)
        }
    }

    func send(system: String, messages: [ArisMindMessage], tools: [ArisMindToolSpec], event: @escaping (ArisMindProviderEvent) -> Void) -> ArisMindProviderEnd {
        let dialect = profile.preset?.dialect ?? .openAIChat
        let needsKey = profile.preset?.needsKey ?? true
        let secret = key()
        if needsKey && (secret ?? "").isEmpty { return .failed(Self.noKey) }
        let spec = ArisAPIRequestSpec(dialect: dialect, base: base ?? profile.base, model: model, key: secret, headers: profile.preset?.headers ?? [:],
                                      system: system, entries: Self.entries(messages), functions: Self.functions(tools), maxTokens: maxTokens,
                                      preset: profile.preset?.id ?? "", strictOrigin: strictOrigin)
        guard let request = ArisAPIDialects.request(spec) else { return .failed(Self.noRequest) }
        let decoder = ArisAPIStreamDecoder(dialect: dialect)
        let done = DispatchSemaphore(value: 0)
        let ended = ArisLocked<ArisAPIError?>(nil)
        let stream = ArisAPIStreamTask(request: request, totalTimeout: totalTimeout, idleTimeout: idleTimeout, queue: queue,
                                       onEvents: { events in for item in events { decoder.feed(item).forEach { event(.text($0)) } } },
                                       onDone: { error in
                                           ended.withLock { $0 = error }
                                           done.signal()
                                       })
        lock.withLock { task = stream }
        stream.start()
        done.wait()
        lock.withLock { task = nil }
        let error = ended.withLock { $0 } ?? decoder.error
        if let error { return error.kind == .cancelled ? .cancelled : .failed(Self.tagged(error)) }
        let calls = decoder.calls
        for call in calls { event(.toolCall(ArisMindToolCall(id: call.id, name: call.name, arguments: call.arguments))) }
        if !calls.isEmpty { return .done(.toolUse) }
        return .done(["max_tokens", "length", "MAX_TOKENS"].contains(decoder.stop ?? "") ? .maxTokens : .endTurn)
    }

    /// Ends the round under way; the next round starts afresh (the loop knows its turn was cancelled).
    func cancel() {
        lock.withLock { task }?.cancel()
    }
}
