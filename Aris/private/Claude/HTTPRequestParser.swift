//
//  HTTPRequestParser.swift
//  Aris
//
//  Minimal HTTP/1.1 request parser for the local Claude Code hook endpoint.
//

import Foundation

struct HTTPRequest: Equatable {
    let method: String
    let path: String
    let body: Data
    /// Header names lowercased.
    var headers: [String: String] = [:]

    /// A request a browser page or DNS-rebinding attacker could have sent: any Origin, or a Host
    /// that isn't this loopback listener. Claude Code's own hook client sends neither Origin nor a foreign Host.
    var isLocalClient: Bool { isLocalClient(port: 23350) }

    func isLocalClient(port: Int) -> Bool {
        guard headers["origin"] == nil else { return false }
        let host = (headers["host"] ?? "").lowercased()
        return host == "127.0.0.1:\(port)" || host == "localhost:\(port)"
    }

    var isJSON: Bool { (headers["content-type"] ?? "").lowercased().hasPrefix("application/json") }

    /// Origin/Host checks stop browsers; this stops other local processes that can't read the token file.
    func hasToken(_ expected: String) -> Bool {
        let given = headers[ClaudeHookToken.header] ?? headers[ClaudeHookToken.legacyHeader] ?? ""
        return ClaudeHookToken.matches(given, expected)
    }
}

enum HTTPParseResult: Equatable {
    case incomplete
    case invalid
    case complete(HTTPRequest)
}

/// A request's first line and headers, and where its body starts in the buffer they were read from.
struct HTTPHead: Equatable {
    let method: String
    let path: String
    /// Header names lowercased.
    let headers: [String: String]
    let bodyStart: Data.Index
}

enum HTTPHeadResult: Equatable {
    case incomplete
    case invalid
    case complete(HTTPHead)
}

enum HTTPRequestParser {
    static let maxBytes = 1_048_576
    /// The request line and headers: a head that doesn't end by then is refused, whatever the body limit.
    static let maxHeadBytes = 65_536
    /// aris-agent's `POST /ask`, which may carry screen images (8 shots, 3 references and the base64 overhead).
    static let askBytes = 24 * 1_048_576
    private static let terminator = Data("\r\n\r\n".utf8)

    /// The body limit for aris-agent's listener: 24 MiB for `POST /ask` whose head carries the agent's token (`token`;
    /// none: never), 1 MiB for everything else, so a caller without the token can't make the agent buffer 24 MiB.
    static func agentLimit(token: String?) -> (String, String, [String: String]) -> Int {
        { method, path, headers in
            guard method == "POST", path == "/ask", let token,
                  HTTPRequest(method: method, path: path, body: Data(), headers: headers).hasToken(token) else { return maxBytes }
            return askBytes
        }
    }

    /// The request line and the headers alone, as soon as they are all there, whatever has come of the body: the hook
    /// server reads from them how the body will come (its length, in chunks, after a "100 Continue").
    static func head(_ buffer: Data) -> HTTPHeadResult {
        let searched = buffer.prefix(maxHeadBytes + terminator.count)
        guard let headerEnd = searched.range(of: terminator) else {
            return buffer.count > maxHeadBytes ? .invalid : .incomplete
        }

        guard let head = String(data: buffer[buffer.startIndex..<headerEnd.lowerBound], encoding: .utf8) else {
            return .invalid
        }
        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines[0].split(separator: " ")
        guard requestLine.count >= 2 else { return .invalid }

        let headers = lines.dropFirst().reduce(into: [String: String]()) { result, line in
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { return }
            result[parts[0].lowercased()] = parts[1].trimmingCharacters(in: .whitespaces)
        }
        return .complete(HTTPHead(method: String(requestLine[0]), path: String(requestLine[1]), headers: headers, bodyStart: headerEnd.upperBound))
    }

    /// The head is read first; `limit(method, path, headers)` then caps the body, so an oversized Content-Length is
    /// refused before its body arrives. The default keeps every listener (the hook server on :23350) at 1 MiB.
    static func parse(_ buffer: Data, limit: (String, String, [String: String]) -> Int = { _, _, _ in maxBytes }) -> HTTPParseResult {
        let method: String, path: String, headers: [String: String], bodyStart: Data.Index
        switch head(buffer) {
        case .incomplete: return .incomplete
        case .invalid: return .invalid
        case .complete(let found): (method, path, headers, bodyStart) = (found.method, found.path, found.headers, found.bodyStart)
        }
        let bodyLimit = min(limit(method, path, headers), askBytes)
        // Whatever Content-Length says, the buffer never grows past the head and this request's limit.
        guard buffer.endIndex - bodyStart <= bodyLimit else { return .invalid }
        var contentLength = 0
        if let declared = headers["content-length"] {
            guard let length = Int(declared) else { return .invalid }
            contentLength = length
        }
        guard contentLength >= 0, contentLength <= bodyLimit else { return .invalid }

        guard buffer.endIndex - bodyStart >= contentLength else { return .incomplete }

        let body = buffer[bodyStart..<(bodyStart + contentLength)]
        return .complete(HTTPRequest(method: method, path: path, body: Data(body), headers: headers))
    }
}
