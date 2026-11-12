//
//  ArisAPIDialects.swift
//  aris-agent
//
//  The three wire formats an API brain speaks (cleanroom spec 14, §3.3): OpenAI-compatible Chat Completions, Anthropic
//  Messages and the Gemini API. Each turns Aris's conversation (ArisAPIEntry) into one streamed request, and its stream
//  back into the answer's words, the function calls (whole, once their arguments are complete) and what must be sent
//  back unchanged on the next round (Anthropic's thinking blocks, Gemini's thought signatures: `echo`). Pure apart from
//  building a URLRequest, so the tests feed recorded and broken streams through it.
//

import Foundation

struct ArisAPIImage: Equatable, Sendable {
    let mime: String
    /// Base64, as checked by ArisTurnImage.
    let base64: String
    /// What the image is (other people's words: fenced before it goes in).
    let label: String
}

struct ArisAPIToolCall: Equatable, Sendable {
    let id: String
    let name: String
    /// The arguments as JSON text.
    let arguments: String
}

/// One function the model may call: a flat JSON schema (strings, integers, enums, arrays of strings only).
struct ArisAPIFunction: @unchecked Sendable {
    let name: String
    let description: String
    let parameters: [String: Any]
}

/// The conversation as Aris keeps it, whatever the provider.
enum ArisAPIEntry: @unchecked Sendable {
    case user(text: String, images: [ArisAPIImage])
    /// `echo`: the provider's own content to send back unchanged (Anthropic blocks, Gemini parts, DeepSeek's reasoning).
    case assistant(text: String, calls: [ArisAPIToolCall], echo: Any?)
    case tool(id: String, name: String, text: String)

    var isUser: Bool { if case .user = self { return true } else { return false } }
}

struct ArisAPIUsage: Equatable, Sendable {
    var input = 0
    var output = 0
    var cacheRead = 0
    var cacheWrite = 0
}

/// Everything one request needs (no state).
struct ArisAPIRequestSpec: @unchecked Sendable {
    let dialect: ArisAPIDialect
    let base: String
    let model: String
    let key: String?
    let headers: [String: String]
    let system: String
    let entries: [ArisAPIEntry]
    let functions: [ArisAPIFunction]
    var maxTokens = 4_096
    var preset = ""
    /// The address must be the preset's own (ArisAPIPreset.allows): off only in the tests' fake servers on 127.0.0.1.
    var strictOrigin = true
}

enum ArisAPIDialects {
    // MARK: - Requests

    static func request(_ spec: ArisAPIRequestSpec) -> URLRequest? {
        let path: String
        let body: [String: Any]
        switch spec.dialect {
        case .openAIChat:
            path = "/chat/completions"
            body = openAIBody(spec)
        case .anthropic:
            path = "/messages"
            body = anthropicBody(spec)
        case .gemini:
            guard let model = spec.model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))),
                  !model.isEmpty else { return nil }
            path = "/models/\(model):streamGenerateContent?alt=sse"
            body = geminiBody(spec)
        }
        guard let url = URL(string: spec.base + path), let scheme = url.scheme, ["https", "http"].contains(scheme),
              let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        // The key goes only to its provider's own host over https (a local server: this Mac only).
        if spec.strictOrigin { guard ArisAPIPreset.named(spec.preset)?.allows(url) == true else { return nil } }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        for (name, value) in spec.headers { request.setValue(value, forHTTPHeaderField: name) }
        authorize(&request, dialect: spec.dialect, key: spec.key)
        return request
    }

    /// The key goes in the provider's header only: never the address (Gemini allows ?key=, which would land in logs).
    static func authorize(_ request: inout URLRequest, dialect: ArisAPIDialect, key: String?) {
        guard let key, !key.isEmpty else { return }
        switch dialect {
        case .openAIChat: request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .anthropic:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .gemini: request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        }
    }

    private static func dataURL(_ image: ArisAPIImage) -> String { "data:\(image.mime);base64,\(image.base64)" }

    private static func imageLabel(_ image: ArisAPIImage) -> String { ArisAgentStream.fenced(image.label) }

    static func openAIBody(_ spec: ArisAPIRequestSpec) -> [String: Any] {
        var messages: [[String: Any]] = [["role": "system", "content": spec.system]]
        for entry in spec.entries {
            switch entry {
            case .user(let text, let images):
                if images.isEmpty {
                    messages.append(["role": "user", "content": text])
                } else {
                    let parts: [[String: Any]] = images.flatMap { image -> [[String: Any]] in
                        [["type": "text", "text": imageLabel(image)], ["type": "image_url", "image_url": ["url": dataURL(image)]]]
                    } + [["type": "text", "text": text]]
                    messages.append(["role": "user", "content": parts])
                }
            case .assistant(let text, let calls, let echo):
                var message: [String: Any] = ["role": "assistant", "content": text.isEmpty && !calls.isEmpty ? NSNull() : text]
                if !calls.isEmpty {
                    message["tool_calls"] = calls.map { ["id": $0.id, "type": "function", "function": ["name": $0.name, "arguments": $0.arguments]] }
                }
                // DeepSeek's thinking mode wants its reasoning back within the same tool loop.
                if let reasoning = echo as? String, !reasoning.isEmpty, spec.preset == "deepseek" { message["reasoning_content"] = reasoning }
                messages.append(message)
            case .tool(let id, let name, let text):
                var message: [String: Any] = ["role": "tool", "tool_call_id": id, "content": text]
                if spec.preset == "mistral" { message["name"] = name }
                messages.append(message)
            }
        }
        var body: [String: Any] = ["model": spec.model, "stream": true, "messages": messages]
        // Usage on the last chunk (OpenAI, OpenRouter, Groq…); a local server that doesn't know it ignores it.
        body["stream_options"] = ["include_usage": true]
        // A cap on the answer: OpenAI's own API takes max_completion_tokens, the compatible ones max_tokens.
        body[spec.preset == "openai" ? "max_completion_tokens" : "max_tokens"] = spec.maxTokens
        if !spec.functions.isEmpty {
            body["tools"] = spec.functions.map { ["type": "function", "function": ["name": $0.name, "description": $0.description, "parameters": $0.parameters]] }
        }
        return body
    }

    static func anthropicBody(_ spec: ArisAPIRequestSpec) -> [String: Any] {
        var messages: [[String: Any]] = []
        /// Anthropic wants turns to alternate: a tool result and what follows from the user go in one user message.
        func append(role: String, _ blocks: [[String: Any]]) {
            if let last = messages.last, last["role"] as? String == role, var content = last["content"] as? [[String: Any]] {
                content.append(contentsOf: blocks)
                messages[messages.count - 1]["content"] = content
            } else {
                messages.append(["role": role, "content": blocks])
            }
        }
        for entry in spec.entries {
            switch entry {
            case .user(let text, let images):
                let blocks: [[String: Any]] = images.flatMap { image -> [[String: Any]] in
                    [["type": "text", "text": imageLabel(image)],
                     ["type": "image", "source": ["type": "base64", "media_type": image.mime, "data": image.base64]]]
                } + [["type": "text", "text": text.isEmpty ? "." : text]]
                append(role: "user", blocks)
            case .assistant(let text, let calls, let echo):
                if let blocks = echo as? [[String: Any]], !blocks.isEmpty {
                    append(role: "assistant", blocks)
                } else {
                    var blocks: [[String: Any]] = text.isEmpty ? [] : [["type": "text", "text": text]]
                    blocks += calls.map { ["type": "tool_use", "id": $0.id, "name": $0.name, "input": jsonObject($0.arguments) ?? [:]] }
                    append(role: "assistant", blocks.isEmpty ? [["type": "text", "text": "."]] : blocks)
                }
            case .tool(let id, _, let text):
                append(role: "user", [["type": "tool_result", "tool_use_id": id, "content": text]])
            }
        }
        // The system prompt and the tool list are long and the same every turn: cached (cache_control on the last of each).
        var body: [String: Any] = ["model": spec.model, "max_tokens": spec.maxTokens, "stream": true, "messages": messages,
                                   "system": [["type": "text", "text": spec.system, "cache_control": ["type": "ephemeral"]]]]
        if !spec.functions.isEmpty {
            var tools: [[String: Any]] = spec.functions.map { ["name": $0.name, "description": $0.description, "input_schema": $0.parameters] }
            tools[tools.count - 1]["cache_control"] = ["type": "ephemeral"]
            body["tools"] = tools
        }
        return body
    }

    static func geminiBody(_ spec: ArisAPIRequestSpec) -> [String: Any] {
        var contents: [[String: Any]] = []
        func append(role: String, _ parts: [[String: Any]]) {
            if let last = contents.last, last["role"] as? String == role, var existing = last["parts"] as? [[String: Any]] {
                existing.append(contentsOf: parts)
                contents[contents.count - 1]["parts"] = existing
            } else {
                contents.append(["role": role, "parts": parts])
            }
        }
        for entry in spec.entries {
            switch entry {
            case .user(let text, let images):
                let parts: [[String: Any]] = images.flatMap { image -> [[String: Any]] in
                    [["text": imageLabel(image)], ["inlineData": ["mimeType": image.mime, "data": image.base64]]]
                } + [["text": text.isEmpty ? "." : text]]
                append(role: "user", parts)
            case .assistant(let text, let calls, let echo):
                if let parts = echo as? [[String: Any]], !parts.isEmpty {
                    append(role: "model", parts)
                } else {
                    var parts: [[String: Any]] = text.isEmpty ? [] : [["text": text]]
                    parts += calls.map { ["functionCall": ["name": $0.name, "args": jsonObject($0.arguments) ?? [:]]] }
                    append(role: "model", parts.isEmpty ? [["text": "."]] : parts)
                }
            case .tool(_, let name, let text):
                append(role: "user", [["functionResponse": ["name": name, "response": ["output": text]]]])
            }
        }
        var body: [String: Any] = ["contents": contents, "systemInstruction": ["parts": [["text": spec.system]]],
                                   "generationConfig": ["maxOutputTokens": spec.maxTokens]]
        if !spec.functions.isEmpty {
            body["tools"] = [["functionDeclarations": spec.functions.map {
                ["name": $0.name, "description": $0.description, "parameters": geminiSchema($0.parameters)]
            }]]
        }
        return body
    }

    /// Gemini's schema is an OpenAPI subset: its type names in capitals and no additionalProperties.
    static func geminiSchema(_ schema: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (key, value) in schema where key != "additionalProperties" {
            switch (key, value) {
            case ("type", let type as String): out[key] = type.uppercased()
            case ("properties", let properties as [String: Any]):
                out[key] = properties.mapValues { ($0 as? [String: Any]).map(geminiSchema) ?? $0 }
            case ("items", let items as [String: Any]): out[key] = geminiSchema(items)
            default: out[key] = value
            }
        }
        return out
    }

    static func jsonObject(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func jsonText(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object), let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    /// A tool-call id for a call that came without one (Ollama, Gemini): nine letters and digits, which every provider
    /// takes (Mistral wants exactly that shape).
    static func newCallId() -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return String((0..<9).map { _ in alphabet.randomElement()! })
    }
}

// MARK: - Streams

/// Reads one request's stream in its dialect. `feed` returns the answer's next words; after the stream ends, `calls`,
/// `echo`, `usage`, `stop` and `error` say what came. `odd` counts what couldn't be read (a malformed chunk, an event
/// of a kind this doesn't know): the driver treats the thread as outside text after any (fail closed).
final class ArisAPIStreamDecoder {
    let dialect: ArisAPIDialect
    private(set) var text = ""
    private(set) var usage = ArisAPIUsage()
    private(set) var stop: String?
    private(set) var error: ArisAPIError?
    private(set) var odd = 0
    private(set) var done = false
    /// The provider searched the web itself (citations, annotations, search results, grounding): outside text.
    private(set) var searched = false
    /// The most one call's arguments may grow while they arrive.
    static let maxArguments = 65_536

    // Chat Completions: tool calls by index.
    private var chatCalls: [Int: (id: String, name: String, arguments: String)] = [:]
    private var reasoning = ""
    // Anthropic: content blocks by index.
    private var blocks: [Int: [String: Any]] = [:]
    private var partialJSON: [Int: String] = [:]
    // Gemini: every part as it came.
    private var parts: [[String: Any]] = []
    private var geminiCalls: [ArisAPIToolCall] = []

    init(dialect: ArisAPIDialect) { self.dialect = dialect }

    func feed(_ event: ArisSSEEvent) -> [String] {
        if event.data == "[DONE]" { done = true; return [] }
        guard let data = event.data.data(using: .utf8), let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            odd += 1
            return []
        }
        if Self.carriesSearch(object) { searched = true }
        if event.name == "json" { return whole(object) }
        if object["error"] != nil && dialect != .anthropic {
            error = ArisAPIError.streamed(object)
            return []
        }
        switch dialect {
        case .openAIChat: return chat(object)
        case .anthropic: return anthropic(event.name, object)
        case .gemini: return gemini(object)
        }
    }

    /// The marks of a provider's own web search anywhere in a chunk (security review I1).
    static let searchKeys: Set<String> = ["annotations", "citations", "search_results", "groundingMetadata", "url_citation", "webSearchQueries"]
    static let searchTypes: Set<String> = ["url_citation", "web_search_tool_result", "server_tool_use", "web_search_call", "citations_delta"]

    static func carriesSearch(_ value: Any, depth: Int = 0) -> Bool {
        guard depth < 12 else { return true }
        if let object = value as? [String: Any] {
            for (key, inner) in object {
                if searchKeys.contains(key), !(inner is NSNull), !((inner as? [Any])?.isEmpty ?? false) { return true }
                if key == "type", let type = inner as? String, searchTypes.contains(type) { return true }
                if carriesSearch(inner, depth: depth + 1) { return true }
            }
        } else if let list = value as? [Any] {
            return list.contains { carriesSearch($0, depth: depth + 1) }
        }
        return false
    }

    /// One call's arguments grew past the cap: the round fails (the driver never sees half a call).
    private func tooLong(_ arguments: String) -> Bool {
        guard arguments.utf8.count > Self.maxArguments else { return false }
        error = ArisAPIError(kind: .malformed, message: "a call's arguments were too long")
        return true
    }

    /// A server that answered with one whole JSON body: read as the stream's single chunk.
    private func whole(_ object: [String: Any]) -> [String] {
        if object["error"] != nil { error = ArisAPIError.streamed(object); return [] }
        switch dialect {
        case .openAIChat:
            guard let choice = (object["choices"] as? [[String: Any]])?.first, var message = choice["message"] as? [String: Any] else { odd += 1; return [] }
            if let calls = message["tool_calls"] as? [[String: Any]] {
                message["tool_calls"] = calls.enumerated().map { index, call in call.merging(["index": index]) { $1 } }
            }
            return chat(["choices": [["delta": message, "finish_reason": choice["finish_reason"] ?? NSNull()]], "usage": object["usage"] ?? NSNull()])
        case .gemini:
            return gemini(object)
        case .anthropic:
            for (index, block) in ((object["content"] as? [[String: Any]]) ?? []).enumerated() { blocks[index] = block }
            stop = object["stop_reason"] as? String
            let said = ((object["content"] as? [[String: Any]]) ?? []).filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
            text += said
            return said.isEmpty ? [] : [said]
        }
    }

    private func chat(_ object: [String: Any]) -> [String] {
        if let usage = object["usage"] as? [String: Any] {
            self.usage.input = usage["prompt_tokens"] as? Int ?? self.usage.input
            self.usage.output = usage["completion_tokens"] as? Int ?? self.usage.output
            self.usage.cacheRead = ((usage["prompt_tokens_details"] as? [String: Any])?["cached_tokens"] as? Int) ?? self.usage.cacheRead
        }
        guard let choice = (object["choices"] as? [[String: Any]])?.first else { return [] }
        if let reason = choice["finish_reason"] as? String { stop = reason }
        guard let delta = choice["delta"] as? [String: Any] else { return [] }
        if let thinking = delta["reasoning_content"] as? String { reasoning += thinking }
        for call in delta["tool_calls"] as? [[String: Any]] ?? [] {
            let index = call["index"] as? Int ?? chatCalls.count
            var current = chatCalls[index] ?? (id: "", name: "", arguments: "")
            if let id = call["id"] as? String, !id.isEmpty { current.id = id }
            let function = call["function"] as? [String: Any] ?? [:]
            if let name = function["name"] as? String { current.name += name }
            if let arguments = function["arguments"] as? String {
                current.arguments += arguments
            } else if let arguments = function["arguments"] as? [String: Any] {
                // Ollama can send the arguments already parsed.
                current.arguments += ArisAPIDialects.jsonText(arguments)
            }
            chatCalls[index] = current
            if tooLong(current.arguments) { return [] }
        }
        guard let words = delta["content"] as? String, !words.isEmpty else { return [] }
        text += words
        return [words]
    }

    private func anthropic(_ name: String, _ object: [String: Any]) -> [String] {
        let type = object["type"] as? String ?? name
        let index = object["index"] as? Int ?? 0
        switch type {
        case "message_start":
            let usage = (object["message"] as? [String: Any])?["usage"] as? [String: Any] ?? [:]
            self.usage.input = usage["input_tokens"] as? Int ?? 0
            self.usage.cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
            self.usage.cacheWrite = usage["cache_creation_input_tokens"] as? Int ?? 0
        case "content_block_start":
            var block = object["content_block"] as? [String: Any] ?? [:]
            if block["type"] as? String == "tool_use" { block["input"] = [String: Any]() }
            blocks[index] = block
            if !["text", "thinking", "redacted_thinking", "tool_use"].contains(block["type"] as? String ?? "") { odd += 1 }
        case "content_block_delta":
            let delta = object["delta"] as? [String: Any] ?? [:]
            var block = blocks[index] ?? [:]
            switch delta["type"] as? String {
            case "text_delta":
                let words = delta["text"] as? String ?? ""
                block["text"] = (block["text"] as? String ?? "") + words
                blocks[index] = block
                text += words
                return words.isEmpty ? [] : [words]
            case "input_json_delta":
                partialJSON[index, default: ""] += delta["partial_json"] as? String ?? ""
                if tooLong(partialJSON[index] ?? "") { return [] }
            case "thinking_delta": block["thinking"] = (block["thinking"] as? String ?? "") + (delta["thinking"] as? String ?? "")
            case "signature_delta": block["signature"] = (block["signature"] as? String ?? "") + (delta["signature"] as? String ?? "")
            default: odd += 1
            }
            blocks[index] = block
        case "content_block_stop":
            if var block = blocks[index], block["type"] as? String == "tool_use" {
                let json = partialJSON[index] ?? ""
                block["input"] = json.isEmpty ? [String: Any]() : (ArisAPIDialects.jsonObject(json) ?? ["__malformed": json])
                blocks[index] = block
            }
        case "message_delta":
            if let reason = (object["delta"] as? [String: Any])?["stop_reason"] as? String { stop = reason }
            if let output = (object["usage"] as? [String: Any])?["output_tokens"] as? Int { usage.output = output }
        case "message_stop": done = true
        case "ping": break
        case "error": error = ArisAPIError.streamed(object)
        default: odd += 1
        }
        return []
    }

    private func gemini(_ object: [String: Any]) -> [String] {
        if let meta = object["usageMetadata"] as? [String: Any] {
            usage.input = meta["promptTokenCount"] as? Int ?? usage.input
            usage.output = meta["candidatesTokenCount"] as? Int ?? usage.output
            usage.cacheRead = meta["cachedContentTokenCount"] as? Int ?? usage.cacheRead
        }
        if let blocked = (object["promptFeedback"] as? [String: Any])?["blockReason"] as? String {
            stop = "blocked: " + blocked
        }
        guard let candidate = (object["candidates"] as? [[String: Any]])?.first else { return [] }
        if let reason = candidate["finishReason"] as? String { stop = reason }
        var said: [String] = []
        for part in ((candidate["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? [] {
            parts.append(part)
            if let call = part["functionCall"] as? [String: Any], let name = call["name"] as? String {
                let arguments = ArisAPIDialects.jsonText(call["args"] ?? [String: Any]())
                if tooLong(arguments) { return said }
                geminiCalls.append(ArisAPIToolCall(id: call["id"] as? String ?? ArisAPIDialects.newCallId(), name: name, arguments: arguments))
            } else if part["thought"] as? Bool == true {
                continue
            } else if let words = part["text"] as? String {
                if !words.isEmpty { said.append(words); text += words }
            } else if part["thoughtSignature"] == nil {
                odd += 1
            }
        }
        return said
    }

    /// The function calls, in order, once the stream ended (an argument that isn't JSON stays as it came: the driver
    /// stops the turn on it).
    var calls: [ArisAPIToolCall] {
        switch dialect {
        case .openAIChat:
            return chatCalls.keys.sorted().compactMap { index in
                guard let call = chatCalls[index], !call.name.isEmpty else { return nil }
                return ArisAPIToolCall(id: call.id.isEmpty ? ArisAPIDialects.newCallId() : call.id, name: call.name,
                                       arguments: call.arguments.isEmpty ? "{}" : call.arguments)
            }
        case .anthropic:
            return blocks.keys.sorted().compactMap { index in
                guard let block = blocks[index], block["type"] as? String == "tool_use", let id = block["id"] as? String,
                      let name = block["name"] as? String else { return nil }
                if let input = block["input"] as? [String: Any], let malformed = input["__malformed"] as? String, input.count == 1 {
                    return ArisAPIToolCall(id: id, name: name, arguments: malformed)
                }
                return ArisAPIToolCall(id: id, name: name, arguments: ArisAPIDialects.jsonText(block["input"] ?? [String: Any]()))
            }
        case .gemini:
            return geminiCalls
        }
    }

    /// What goes back unchanged with this answer on the next round.
    var echo: Any? {
        switch dialect {
        case .openAIChat: return reasoning.isEmpty ? nil : reasoning
        case .anthropic:
            // The blocks as they came (thinking with its signature first), tool inputs as objects. A malformed input
            // never goes back (the turn stops on it).
            return blocks.keys.sorted().compactMap { blocks[$0] }
        case .gemini: return parts
        }
    }

    /// The stream ended without its end mark (a server that broke off mid-answer).
    var cutShort: Bool {
        switch dialect {
        case .openAIChat: return stop == nil && !done
        case .anthropic: return !done && stop == nil
        case .gemini: return stop == nil
        }
    }
}
