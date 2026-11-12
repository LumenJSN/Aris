//
//  ClaudeHookWire.swift
//  Aris
//
//  What the hook server reads off a connection and what it writes back. A request is read to its end however it
//  comes: in one piece or many, of any size up to the limit, with a Content-Length or in chunks, and after a
//  "100 Continue" when the client waits for one. Every answer closes its connection (`Connection: close`): a client
//  that keeps connections alive opens a new one for its next request, and a second request sent ahead on the same
//  connection is never read, so it can never sit there unanswered.
//  The bytes are read as they arrive (HookRequestStream, security review 9, L3): appended, never copied again; the
//  head is read once, and a head announcing a big body (chunked, or over 64 KiB) without the server's token is turned
//  away (401) before any of that body is waited for; a chunked body is decoded from where the last arrival stopped,
//  never from its start again. (A small body is read first and its token checked with it, as before: there the check
//  runs under the server's deadlines and its limit on requests looked at once.)
//  Foundation only (tested).
//

import Foundation

/// One answer of the hook server.
struct HookReply: Equatable {
    let status: String
    let body: Data

    /// "No decision": Claude Code carries on as if no hook were there (its tool runs, its own prompt asks).
    static let neutral = HookReply(status: "200 OK", body: Data("{}".utf8))

    static func ok(_ body: Data) -> HookReply { HookReply(status: "200 OK", body: body) }

    /// A refusal has no body.
    static func refusal(_ status: String) -> HookReply { HookReply(status: status, body: Data()) }

    /// The bytes on the wire: the body's exact length, and the connection is closed after it.
    var bytes: Data {
        Data("HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8) + body
    }

    static let continueBytes = Data("HTTP/1.1 100 Continue\r\n\r\n".utf8)
}

/// What the bytes received so far amount to.
enum HookRead: Equatable {
    /// Not all there yet. `wantsContinue`: the client sent `Expect: 100-continue` and holds its body back until told.
    case more(wantsContinue: Bool)
    /// Not a request the server reads (the status to refuse it with).
    case refuse(String)
    /// A body over the limit: only its head was read.
    case tooBig(HTTPHead)
    /// One whole request. Bytes after it are not read.
    case request(HTTPRequest)
}

/// One request read as its bytes arrive. `admits`: whether a head announcing a big body may go on to it (the hook
/// server's token); nil when that can't be told now (the body is then read, and the token checked with it).
struct HookRequestStream {
    /// A body to come larger than this (or in chunks) has its head's token checked before it is read.
    static let earlyCheckBytes = 65_536
    private let admits: (HTTPHead) -> Bool?
    /// Everything received so far, appended in place.
    private(set) var buffer = Data()
    private var head: HTTPHead?
    /// A chunked body: where the next size line starts, and the body decoded up to there.
    private var chunkAt: Data.Index?
    private var body = Data()

    init(admits: @escaping (HTTPHead) -> Bool? = { _ in nil }) { self.admits = admits }

    mutating func take(_ data: Data) -> HookRead {
        buffer.append(data)
        if head == nil {
            switch HTTPRequestParser.head(buffer) {
            case .incomplete: return .more(wantsContinue: false)
            case .invalid: return .refuse(HookRequestReader.badRequest)
            case .complete(let found):
                if Self.bigBody(found), admits(found) == false { return .refuse(HookRequestReader.unauthorized) }
                head = found
            }
        }
        guard let head else { return .refuse(HookRequestReader.badRequest) }
        if HookRequestReader.isChunked(head) {
            var at = chunkAt ?? head.bodyStart
            defer { chunkAt = at }
            return HookRequestReader.chunked(buffer, head, at: &at, body: &body)
        }
        // A body by its length is looked at whole only once all of it is in (or the length can't be one).
        if let declared = head.headers["content-length"], let length = Int(declared), length >= 0, length <= HTTPRequestParser.maxBytes,
           buffer.endIndex - head.bodyStart < length {
            return .more(wantsContinue: HookRequestReader.expectsContinue(head))
        }
        return HookRequestReader.whole(buffer, head)
    }

    /// A body in chunks, or one whose length is over `earlyCheckBytes` (and within the limit: a longer one is refused
    /// 413 from its head alone, never read).
    private static func bigBody(_ head: HTTPHead) -> Bool {
        if HookRequestReader.isChunked(head) { return true }
        guard let length = head.headers["content-length"].flatMap({ Int($0) }) else { return false }
        return length > earlyCheckBytes && length <= HTTPRequestParser.maxBytes
    }

    /// The request is answered: what was kept of it goes.
    mutating func drop() {
        buffer = Data()
        body = Data()
    }
}

enum HookRequestReader {
    static let badRequest = "400 Bad Request"
    static let unauthorized = "401 Unauthorized"
    private static let lineEnd = Data("\r\n".utf8)
    private static let blankLine = Data("\r\n\r\n".utf8)
    /// A chunk's size line ("1f4a;name=value") is never longer than this.
    private static let longestSizeLine = 256

    /// The bytes as one piece (a stream that takes them all at once).
    static func read(_ buffer: Data) -> HookRead {
        var stream = HookRequestStream()
        return stream.take(buffer)
    }

    /// A body given by its length, once enough of it has come.
    fileprivate static func whole(_ buffer: Data, _ head: HTTPHead) -> HookRead {
        switch HTTPRequestParser.parse(buffer) {
        case .complete(let request): return .request(request)
        case .incomplete: return .more(wantsContinue: expectsContinue(head))
        case .invalid:
            // A length that is a number over the limit is a body too big; anything else isn't HTTP.
            if let declared = head.headers["content-length"].flatMap({ Int($0) }), declared > HTTPRequestParser.maxBytes { return .tooBig(head) }
            return .refuse(badRequest)
        }
    }

    fileprivate static func isChunked(_ head: HTTPHead) -> Bool {
        (head.headers["transfer-encoding"] ?? "").lowercased().split(separator: ",").contains { $0.trimmingCharacters(in: .whitespaces) == "chunked" }
    }

    fileprivate static func expectsContinue(_ head: HTTPHead) -> Bool {
        (head.headers["expect"] ?? "").lowercased() == "100-continue"
    }

    /// A body sent in chunks (`Transfer-Encoding: chunked`): each is a hexadecimal size line and that many bytes; a
    /// size of zero ends it. Decoded on from `at` with `body` as far as it went (a body is at most 1 MiB); both are
    /// left where the bytes ran out.
    fileprivate static func chunked(_ buffer: Data, _ head: HTTPHead, at: inout Data.Index, body: inout Data) -> HookRead {
        let limit = HTTPRequestParser.maxBytes
        // The framing of very small chunks can outweigh the body: the raw bytes are capped as well.
        guard buffer.endIndex - head.bodyStart <= 2 * limit else { return .tooBig(head) }
        while true {
            guard let sizeEnd = buffer[at...].range(of: lineEnd) else {
                guard buffer.endIndex - at <= longestSizeLine else { return .refuse(badRequest) }
                return .more(wantsContinue: at == head.bodyStart && expectsContinue(head))
            }
            let sizeText = String(decoding: buffer[at..<sizeEnd.lowerBound], as: UTF8.self)
                .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            guard sizeText.count <= 8, let size = Int(sizeText, radix: 16), size >= 0 else { return .refuse(badRequest) }
            guard body.count + size <= limit else { return .tooBig(head) }
            if size == 0 {
                // The last chunk, then optional trailer lines, then an empty line.
                guard buffer[sizeEnd.lowerBound...].range(of: blankLine) != nil else { return .more(wantsContinue: false) }
                return .request(HTTPRequest(method: head.method, path: head.path, body: body, headers: head.headers))
            }
            let dataStart = sizeEnd.upperBound
            guard buffer.endIndex - dataStart >= size + lineEnd.count else { return .more(wantsContinue: false) }
            let dataEnd = dataStart + size
            guard buffer[dataEnd..<(dataEnd + lineEnd.count)] == lineEnd else { return .refuse(badRequest) }
            body.append(buffer[dataStart..<dataEnd])
            at = dataEnd + lineEnd.count
        }
    }
}
