//
//  ArisMCPClient.swift
//  aris-agent
//
//  One MCP session: initialize, tools/list and tools/call over a transport, JSON-RPC 2.0. Aris offers the server
//  nothing back: no sampling, roots or elicitation, so a server can't ask a model anything, read the user's files or put a
//  form in front of him; every request it sends is refused (a ping is answered). What it lists is checked and cut to
//  size here. Calls block their caller (never the agent's server queue) until the answer or the time limit.
//

import Foundation

enum ArisMCPError: Error, Equatable {
    case closed(String)
    case timeout
    case server(String)
    case malformed

    var message: String {
        switch self {
        case .closed(let why): return why
        case .timeout: return "the server didn't answer in time"
        case .server(let why): return why
        case .malformed: return "the server's answer couldn't be read"
        }
    }
}

/// What one tools/call brought back, before the gate wraps it for a brain.
struct ArisMCPCallResult: Equatable {
    let text: String
    let isError: Bool
}

final class ArisMCPClient {
    /// The protocol version Aris asks for (the server may answer with another it speaks).
    static let protocolVersion = "2025-06-18"
    static let maxTools = 200
    static let maxSchemaBytes = 64 * 1_024
    static let maxDescription = 1_000
    /// The most of a result kept before the gate cuts it to what a brain reads.
    static let maxResultText = 256 * 1_024

    private let transport: ArisMCPTransport
    private let lock = NSLock()
    private var nextId = 0
    private var waiting: [Int: (DispatchSemaphore, Result<[String: Any], ArisMCPError>?)] = [:]
    private var closedWhy: String?
    private var pings: [Date] = []

    private func pingAllowed() -> Bool {
        lock.withLock {
            let now = Date()
            pings = pings.filter { now.timeIntervalSince($0) < 10 }
            guard pings.count < 10 else { return false }
            pings.append(now)
            return true
        }
    }

    /// The server said its tool list changed.
    var onToolsChanged: (() -> Void)?

    init(transport: ArisMCPTransport) {
        self.transport = transport
        transport.onMessage = { [weak self] value in self?.receive(value) }
        transport.onClose = { [weak self] why in self?.closed(why ?? "the server closed the connection") }
    }

    var isClosed: Bool { lock.withLock { closedWhy != nil } }

    /// What the server itself said about a failure (ArisMCPTransport.diagnostics): for the user's settings, never a brain.
    var diagnostics: String { transport.diagnostics }

    /// Starts the transport and shakes hands. Nil when ready, else why not.
    func connect(timeout: TimeInterval = 20) -> ArisMCPError? {
        if let why = transport.start() { closed(why); return .closed(why) }
        let params: [String: Any] = ["protocolVersion": Self.protocolVersion, "capabilities": [String: Any](),
                                     "clientInfo": ["name": "Aris", "version": "1.0"]]
        switch request("initialize", params, timeout: timeout) {
        case .failure(let error): return error
        case .success(let result):
            guard let version = result["protocolVersion"] as? String,
                  version.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return .malformed }
            transport.agreed(version: version)
            notify("notifications/initialized", [:])
            return nil
        }
    }

    /// Every tool the server lists (pages followed, at most `maxTools`), each checked: a usable name, an object schema
    /// no bigger than `maxSchemaBytes` (else the tool is left out: its arguments couldn't be checked).
    func listTools(timeout: TimeInterval = 20) -> Result<[ArisMCPTool], ArisMCPError> {
        var tools: [ArisMCPTool] = []
        var cursor: String?
        for _ in 0..<10 {
            let params: [String: Any] = cursor.map { ["cursor": $0] } ?? [:]
            switch request("tools/list", params, timeout: timeout) {
            case .failure(let error): return .failure(error)
            case .success(let result):
                guard let listed = result["tools"] as? [Any] else { return .failure(.malformed) }
                tools += listed.compactMap(Self.tool)
                cursor = result["nextCursor"] as? String
            }
            if cursor == nil || tools.count >= Self.maxTools { break }
        }
        var seen: Set<String> = []
        return .success(Array(tools.filter { seen.insert($0.name).inserted }.prefix(Self.maxTools)))
    }

    static func tool(_ raw: Any) -> ArisMCPTool? {
        guard let object = raw as? [String: Any], let name = object["name"] as? String,
              name.range(of: #"^[A-Za-z0-9_.\-/]{1,128}$"#, options: .regularExpression) != nil else { return nil }
        let schema = object["inputSchema"] as? [String: Any] ?? ["type": "object"]
        guard (schema["type"] as? String ?? "object") == "object", JSONSerialization.isValidJSONObject(schema),
              let data = try? JSONSerialization.data(withJSONObject: schema), data.count <= maxSchemaBytes else { return nil }
        let annotations = object["annotations"] as? [String: Any] ?? [:]
        let hint = { (key: String) -> Bool? in (annotations[key] as? NSNumber).flatMap { ArisMCPSchema.isBool($0) ? $0.boolValue : nil } }
        let title = (object["title"] as? String ?? annotations["title"] as? String).map { ArisMCPPolicy.clean($0, limit: 80) }
        return ArisMCPTool(name: name, title: title?.isEmpty == false ? title : nil,
                           description: ArisMCPPolicy.clean(object["description"] as? String ?? "", limit: maxDescription),
                           inputSchema: schema, readOnlyHint: hint("readOnlyHint"), destructiveHint: hint("destructiveHint"))
    }

    func call(_ tool: String, arguments: [String: Any], timeout: TimeInterval) -> Result<ArisMCPCallResult, ArisMCPError> {
        switch request("tools/call", ["name": tool, "arguments": arguments], timeout: timeout) {
        case .failure(let error): return .failure(error)
        case .success(let result): return .success(Self.result(result))
        }
    }

    /// A result's text: each text part, a resource's text, the structured content as JSON; images, audio and binary
    /// parts only named. Cut at `maxResultText`.
    static func result(_ object: [String: Any]) -> ArisMCPCallResult {
        var parts: [String] = []
        for item in object["content"] as? [Any] ?? [] {
            guard let part = item as? [String: Any] else { continue }
            switch part["type"] as? String {
            case "text": parts.append(part["text"] as? String ?? "")
            case "resource":
                let resource = part["resource"] as? [String: Any] ?? [:]
                parts.append((resource["text"] as? String).map { $0 } ?? "[a file the tool attached, not shown]")
            case "resource_link": parts.append("[a link the tool gave: \(ArisMCPPolicy.clean(part["uri"] as? String ?? "", limit: 200))]")
            case "image": parts.append("[an image the tool gave, not shown]")
            case "audio": parts.append("[audio the tool gave, not shown]")
            default: parts.append("[a part Aris can't show]")
            }
        }
        if parts.isEmpty, let structured = object["structuredContent"], JSONSerialization.isValidJSONObject([structured]),
           let data = try? JSONSerialization.data(withJSONObject: structured, options: [.sortedKeys, .withoutEscapingSlashes]) {
            parts.append(String(decoding: data, as: UTF8.self))
        }
        var text = parts.joined(separator: "\n")
        if text.count > maxResultText { text = String(text.prefix(maxResultText)) }
        let isError = (object["isError"] as? NSNumber).map { ArisMCPSchema.isBool($0) && $0.boolValue } ?? false
        return ArisMCPCallResult(text: text, isError: isError)
    }

    func close() {
        closed("closed by Aris")
        transport.close()
    }

    // MARK: - JSON-RPC

    private func request(_ method: String, _ params: [String: Any], timeout: TimeInterval) -> Result<[String: Any], ArisMCPError> {
        let signal = DispatchSemaphore(value: 0)
        let id: Int? = lock.withLock {
            guard closedWhy == nil else { return nil }
            nextId += 1
            waiting[nextId] = (signal, nil)
            return nextId
        }
        guard let id else { return .failure(.closed(lock.withLock { closedWhy } ?? "closed")) }
        transport.send(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
        let timedOut = signal.wait(timeout: .now() + timeout) == .timedOut
        let outcome = lock.withLock { waiting.removeValue(forKey: id)?.1 }
        if let outcome { return outcome }
        if timedOut {
            notify("notifications/cancelled", ["requestId": id, "reason": "timeout"])
            return .failure(.timeout)
        }
        return .failure(.closed(lock.withLock { closedWhy } ?? "closed"))
    }

    private func notify(_ method: String, _ params: [String: Any]) {
        guard !isClosed else { return }
        transport.send(["jsonrpc": "2.0", "method": method, "params": params])
    }

    private func receive(_ value: Any) {
        if let batch = value as? [Any] { return batch.forEach(receive) }
        guard let message = value as? [String: Any] else { return }
        if let method = message["method"] as? String {
            if let id = message["id"] {
                // A request from the server: only a ping is answered (at most 10 in 10 s: M6); Aris offered nothing else.
                if method == "ping", !pingAllowed() { return }
                let reply: [String: Any] = method == "ping"
                    ? ["jsonrpc": "2.0", "id": id, "result": [String: Any]()]
                    : ["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Aris doesn't take requests from servers"]]
                if JSONSerialization.isValidJSONObject(reply) { transport.send(reply) }
            } else if method == "notifications/tools/list_changed" {
                onToolsChanged?()
            }
            return
        }
        guard let id = (message["id"] as? NSNumber)?.intValue ?? (message["id"] as? String).flatMap(Int.init) else { return }
        let outcome: Result<[String: Any], ArisMCPError>
        if let error = message["error"] as? [String: Any] {
            outcome = .failure(.server(ArisMCPPolicy.clean(error["message"] as? String ?? "the server refused", limit: 300)))
        } else if let result = message["result"] as? [String: Any] {
            outcome = .success(result)
        } else {
            outcome = .failure(.malformed)
        }
        lock.withLock {
            guard let entry = waiting[id], entry.1 == nil else { return }
            waiting[id] = (entry.0, outcome)
            entry.0.signal()
        }
    }

    private func closed(_ why: String) {
        lock.withLock {
            guard closedWhy == nil else { return }
            closedWhy = why
            for (id, entry) in waiting where entry.1 == nil {
                waiting[id] = (entry.0, .failure(.closed(why)))
                entry.0.signal()
            }
        }
    }
}
