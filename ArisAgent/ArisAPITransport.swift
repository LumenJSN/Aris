//
//  ArisAPITransport.swift
//  aris-agent
//
//  The HTTP side of the API brains: one streamed request (Server-Sent Events, or a whole JSON body from a server that
//  doesn't stream), read as it arrives, with a time limit between bytes and one for the whole answer, and cancellable
//  at any moment. A failed request becomes one of a few kinds (ArisAPIError.Kind) the driver maps to the brain's
//  events: a quota or rate limit lets another AI take the question, a bad key asks the user for a new one. No key, header
//  or body is ever written to a log here.
//

import Foundation

/// One Server-Sent Event: its `event:` name (empty when none) and its joined `data:` lines.
struct ArisSSEEvent: Equatable, Sendable {
    let name: String
    let data: String
}

/// Reads an SSE stream in whatever pieces it arrives (a line may be split anywhere, \r\n or \n). Comments and fields
/// other than `event` and `data` are skipped; an event ends at a blank line.
struct ArisSSEParser {
    private var buffer = Data()
    private var name = ""
    private var data: [String] = []
    /// Bytes held without a line break: past this the stream is broken (a malformed or hostile server).
    static let maxLine = 4 * 1_024 * 1_024

    private(set) var overflowed = false

    mutating func feed(_ chunk: Data) -> [ArisSSEEvent] {
        buffer.append(chunk)
        var events: [ArisSSEEvent] = []
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            var lineData = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if lineData.last == UInt8(ascii: "\r") { lineData = lineData.dropLast() }
            if let event = take(String(decoding: lineData, as: UTF8.self)) { events.append(event) }
        }
        if buffer.count > Self.maxLine {
            overflowed = true
            buffer = Data()
        }
        return events
    }

    /// The stream ended: an event still being read is dispatched (some servers close without the last blank line).
    mutating func finish() -> [ArisSSEEvent] {
        var events: [ArisSSEEvent] = []
        if !buffer.isEmpty {
            let line = String(decoding: buffer, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            buffer = Data()
            if let event = take(line) { events.append(event) }
        }
        if let event = take("") { events.append(event) }
        return events
    }

    private mutating func take(_ line: String) -> ArisSSEEvent? {
        if line.isEmpty {
            defer { name = ""; data = [] }
            guard !data.isEmpty else { return nil }
            return ArisSSEEvent(name: name, data: data.joined(separator: "\n"))
        }
        if line.hasPrefix(":") { return nil }
        let field: Substring, value: Substring
        if let colon = line.firstIndex(of: ":") {
            field = line[line.startIndex..<colon]
            var rest = line[line.index(after: colon)...]
            if rest.hasPrefix(" ") { rest = rest.dropFirst() }
            value = rest
        } else {
            field = Substring(line)
            value = ""
        }
        switch field {
        case "event": name = String(value)
        case "data": data.append(String(value))
        default: break
        }
        return nil
    }
}

/// Why a request failed, as the driver needs it.
struct ArisAPIError: Error, Equatable, Sendable {
    enum Kind: String, Sendable {
        case auth, quota, rate, overloaded, context, unsupported, network, server, timeout, cancelled, malformed
        /// The provider refused tool definitions for this model: the text relay may still work.
        case noTools
    }

    let kind: Kind
    /// Short, redacted, for the log and the notch (never a body in full).
    let message: String
    /// When the provider said to try again (Retry-After).
    var retryAt: Date? = nil

    /// Another AI may take the question.
    var isUnavailable: Bool { [.quota, .rate, .overloaded].contains(kind) }

    /// Classifies an HTTP error from its status, the start of its body and its headers.
    static func http(status: Int, body: Data, headers: [String: String], now: Date = Date()) -> ArisAPIError {
        let text = String(decoding: body.prefix(4_096), as: UTF8.self)
        let lower = text.lowercased()
        let message = ArisAPISecrets.redacted(errorMessage(text) ?? "HTTP \(status)")
        let retry = headers.first { $0.key.lowercased() == "retry-after" }.flatMap { Double($0.value.trimmingCharacters(in: .whitespaces)) }
            .map { now.addingTimeInterval(min($0, 86_400)) }
        let contextWords = ["context_length", "context length", "maximum context", "prompt is too long", "too many tokens", "token limit", "context window"]
        switch status {
        case 401, 403:
            return ArisAPIError(kind: .auth, message: message)
        case 402:
            return ArisAPIError(kind: .quota, message: "quota: " + message)
        case 429:
            let quota = lower.contains("quota") || lower.contains("insufficient") || lower.contains("billing") || lower.contains("credit")
            return ArisAPIError(kind: quota ? .quota : .rate, message: (quota ? "quota: " : "rate limit: ") + message, retryAt: retry)
        case 503, 529:
            return ArisAPIError(kind: .overloaded, message: "overloaded: " + message, retryAt: retry)
        case 400, 404, 413, 422:
            if contextWords.contains(where: lower.contains) { return ArisAPIError(kind: .context, message: message) }
            if lower.contains("tool"), lower.contains("support") || lower.contains("not available") || lower.contains("unsupported") {
                return ArisAPIError(kind: .noTools, message: message)
            }
            if lower.contains("api key") || lower.contains("api_key") { return ArisAPIError(kind: .auth, message: message) }
            return ArisAPIError(kind: .unsupported, message: message)
        default:
            return ArisAPIError(kind: status >= 500 ? .server : .unsupported, message: message)
        }
    }

    /// The `error.message` (or `message`) of a provider's JSON error body.
    static func errorMessage(_ text: String) -> String? {
        guard let data = text.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let top = (object as? [[String: Any]])?.first ?? object as? [String: Any] ?? [:]
        let error = top["error"] as? [String: Any] ?? top
        let message = error["message"] as? String ?? top["message"] as? String ?? (top["error"] as? String)
        return message.map { String($0.prefix(240)) }
    }

    /// An error object that came inside a stream (`{"error":{...}}`, or Anthropic's `error` event).
    static func streamed(_ object: [String: Any]) -> ArisAPIError {
        let error = object["error"] as? [String: Any] ?? object
        let type = ((error["type"] as? String) ?? (error["status"] as? String) ?? (error["code"] as? String) ?? "").lowercased()
        let message = ArisAPISecrets.redacted(String(((error["message"] as? String) ?? type).prefix(240)))
        let code = (error["code"] as? Int) ?? 0
        if type.contains("overloaded") || code == 529 || code == 503 { return ArisAPIError(kind: .overloaded, message: "overloaded: " + message) }
        if type.contains("rate") || code == 429 || type.contains("resource_exhausted") {
            return ArisAPIError(kind: message.lowercased().contains("quota") ? .quota : .rate, message: "rate limit: " + message)
        }
        if type.contains("auth") || type.contains("permission") || code == 401 || code == 403 { return ArisAPIError(kind: .auth, message: message) }
        return ArisAPIError(kind: .server, message: message)
    }
}

/// One request's answer as it arrives: SSE events (or one whole JSON body, as `name: "json"`), then exactly one end.
final class ArisAPIStreamTask: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    typealias Events = ([ArisSSEEvent]) -> Void
    typealias Done = (ArisAPIError?) -> Void

    /// The longest error body kept, and the longest whole (non-streamed) answer.
    static let maxErrorBody = 65_536
    static let maxWholeBody = 8 * 1_024 * 1_024
    /// The most one streamed answer may bring (a round), whatever it is.
    static let maxStreamBytes = 16 * 1_024 * 1_024
    private var received = 0

    private let request: URLRequest
    private let totalTimeout: TimeInterval
    private let idleTimeout: TimeInterval
    private let onEvents: Events
    private let onDone: Done
    private let queue: DispatchQueue
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var parser = ArisSSEParser()
    private var status = 0
    private var streaming = true
    private var body = Data()
    private var headers: [String: String] = [:]
    private var finished = false
    private var deadline: DispatchWorkItem?

    /// `queue`: where `onEvents` and `onDone` are called (serially).
    init(request: URLRequest, totalTimeout: TimeInterval, idleTimeout: TimeInterval, queue: DispatchQueue,
         onEvents: @escaping Events, onDone: @escaping Done) {
        self.request = request
        self.totalTimeout = totalTimeout
        self.idleTimeout = idleTimeout
        self.queue = queue
        self.onEvents = onEvents
        self.onDone = onDone
    }

    func start() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = idleTimeout
        configuration.timeoutIntervalForResource = totalTimeout + 5
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        delegateQueue.underlyingQueue = queue
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
        self.session = session
        let task = session.dataTask(with: request)
        self.task = task
        let item = DispatchWorkItem { [weak self] in self?.end(ArisAPIError(kind: .timeout, message: "the answer took too long")) }
        deadline = item
        queue.asyncAfter(deadline: .now() + totalTimeout, execute: item)
        task.resume()
    }

    /// Stops the request; `onDone` is called with `.cancelled` unless it already ended.
    func cancel() {
        queue.async { [self] in end(ArisAPIError(kind: .cancelled, message: "cancelled")) }
    }

    private func end(_ error: ArisAPIError?) {
        guard !finished else { return }
        finished = true
        deadline?.cancel()
        task?.cancel()
        session?.invalidateAndCancel()
        session = nil
        onDone(error)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let http = response as? HTTPURLResponse
        status = http?.statusCode ?? 0
        headers = (http?.allHeaderFields as? [String: String]) ?? [:]
        let type = (headers.first { $0.key.lowercased() == "content-type" }?.value ?? "").lowercased()
        streaming = (200..<300).contains(status) && !type.contains("application/json")
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !finished else { return }
        guard (200..<300).contains(status) else {
            if body.count < Self.maxErrorBody { body.append(data.prefix(Self.maxErrorBody - body.count)) }
            return
        }
        guard streaming else {
            body.append(data)
            if body.count > Self.maxWholeBody { end(ArisAPIError(kind: .malformed, message: "the answer was too long")) }
            return
        }
        received += data.count
        if received > Self.maxStreamBytes { return end(ArisAPIError(kind: .malformed, message: "the answer was too long")) }
        let events = parser.feed(data)
        if parser.overflowed { return end(ArisAPIError(kind: .malformed, message: "a stream line was too long")) }
        if !events.isEmpty { onEvents(events) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !finished else { return }
        if let error = error as? URLError {
            let kind: ArisAPIError.Kind = error.code == .timedOut ? .timeout : error.code == .cancelled ? .cancelled : .network
            return end(ArisAPIError(kind: kind, message: kind == .timeout ? "no answer in time" : "couldn't reach the provider (\(error.code.rawValue))"))
        }
        if error != nil { return end(ArisAPIError(kind: .network, message: "couldn't reach the provider")) }
        guard (200..<300).contains(status) else { return end(ArisAPIError.http(status: status, body: body, headers: headers)) }
        if streaming {
            let rest = parser.finish()
            if !rest.isEmpty { onEvents(rest) }
        } else if !body.isEmpty {
            onEvents([ArisSSEEvent(name: "json", data: String(decoding: body, as: UTF8.self))])
        }
        end(nil)
    }

    /// Never follow a redirect: a provider's answer comes from the address asked (a redirect could carry the key off).
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
