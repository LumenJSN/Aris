//
//  ArisMCPTransport.swift
//  aris-agent
//
//  How the agent's MCP client reaches one server: a program it starts (stdio, one JSON-RPC message per line) or a URL
//  (streamable HTTP: each message POSTed, the answer as JSON or as server-sent events). Neither runs a shell, follows a
//  redirect, keeps cookies or takes more than a few megabytes back. A stdio server gets a bare environment (no Aris
//  token, no other service's secret) and an empty folder of its own.
//

import Foundation

protocol ArisMCPTransport: AnyObject {
    /// One decoded JSON-RPC value (an object, or a batch array), on the transport's own queue.
    var onMessage: ((Any) -> Void)? { get set }
    /// The server went away (with why, when known).
    var onClose: ((String?) -> Void)? { get set }
    /// Nil when started, else why not.
    func start() -> String?
    func send(_ message: [String: Any])
    func close()
    /// The protocol version agreed in initialize, sent on every later HTTP request.
    func agreed(version: String)
    /// What the server itself said about a failure (a program's last stderr lines), for 연결 테스트 and the settings
    /// row only: never shown to a brain. Empty when there is nothing.
    var diagnostics: String { get }
}

extension ArisMCPTransport {
    func agreed(version: String) {}
    var diagnostics: String { "" }
}

enum ArisMCPWire {
    static func encode(_ message: [String: Any]) -> Data? {
        guard JSONSerialization.isValidJSONObject(message) else { return nil }
        return try? JSONSerialization.data(withJSONObject: message, options: [.withoutEscapingSlashes])
    }

    static func decode(_ data: Data) -> Any? {
        try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    /// Server-sent events: the `data:` lines of each event joined, an event ending at a blank line. Returns the events
    /// complete in `buffer` and leaves the rest there.
    static func events(_ buffer: inout Data) -> [String] {
        var found: [String] = []
        while true {
            guard let text = String(data: buffer, encoding: .utf8) else { return found }
            let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            guard let end = normalized.range(of: "\n\n") else { return found }
            let block = String(normalized[..<end.lowerBound])
            let rest = String(normalized[end.upperBound...])
            buffer = Data(rest.utf8)
            let data = block.split(separator: "\n", omittingEmptySubsequences: false).compactMap { line -> String? in
                guard line.hasPrefix("data:") else { return nil }
                let value = line.dropFirst(5)
                return String(value.hasPrefix(" ") ? value.dropFirst() : value)
            }
            if !data.isEmpty { found.append(data.joined(separator: "\n")) }
        }
    }
}

// MARK: - stdio

final class ArisMCPStdio: ArisMCPTransport {
    /// A line longer than this ends the server: no message is that big.
    static let maxLine = 4 * 1_024 * 1_024

    var onMessage: ((Any) -> Void)?
    var onClose: ((String?) -> Void)?
    private let executable: URL
    private let arguments: [String]
    private let environment: [String: String]
    private let queue = DispatchQueue(label: "com.lumenjsn.aris.mcp.stdio")
    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var folder: URL?
    /// The end of what the server wrote to stderr (for 연결 테스트), never shown to a brain.
    private(set) var stderrTail = ""

    var diagnostics: String { queue.sync { stderrTail } }

    init(executable: URL, arguments: [String], environment: [String: String]) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
    }

    /// The program for `command`: an absolute path, or the first of `path`'s folders that has it. Only an
    /// executable regular file (links followed).
    static func resolve(_ command: String, path: [String]) -> URL? {
        let candidates = command.hasPrefix("/") ? [command] : command.contains("/") ? [] : path.map { ($0 as NSString).appendingPathComponent(command) }
        for candidate in candidates {
            let resolved = URL(fileURLWithPath: candidate).resolvingSymlinksInPath()
            var directory: ObjCBool = false
            if FileManager.default.fileExists(atPath: resolved.path, isDirectory: &directory), !directory.boolValue,
               FileManager.default.isExecutableFile(atPath: resolved.path) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }

    /// The bare environment a server gets: a PATH (Aris's usual folders, then the user's own from their login shell, so
    /// an `npx` under nvm finds its node: audit mcp-4), HOME, USER and language, a temp folder, and its own secret
    /// (`extra`), nothing else of the agent's.
    static func environment(extra: [String: String], base: [String: String] = ProcessInfo.processInfo.environment,
                            login: [String] = ArisLoginPath.folders) -> [String: String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = ArisPrograms.childPath(first: ArisPrograms.knownFolders(home: home) + ["/usr/bin", "/bin", "/usr/sbin", "/sbin"], inherited: nil, login: login)
        var environment: [String: String] = ["PATH": paths, "HOME": home, "USER": NSUserName(), "LOGNAME": NSUserName(),
                                             "LANG": base["LANG"] ?? "en_US.UTF-8", "TMPDIR": NSTemporaryDirectory()]
        environment.merge(extra) { $1 }
        return environment
    }

    /// Where a server's program is looked for: Aris's usual folders, then the user's own PATH (`npx`, `bunx` and `uvx`
    /// under a version manager).
    static var searchPath: [String] { searchPath(login: ArisLoginPath.folders) }

    static func searchPath(login: [String]) -> [String] {
        ArisPrograms.childPath(first: ArisPrograms.knownFolders() + ["/usr/bin", "/bin"], inherited: nil, login: login)
            .split(separator: ":").map(String.init)
    }

    func start() -> String? {
        let process = ArisExactProcess()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-mcp-" + UUID().uuidString.prefix(8))
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        self.folder = folder
        process.currentDirectoryURL = folder
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        // An empty read is the end of that output: its handler goes (it would fire again at once, forever), and the end
        // of stdout ends the server, which can't answer any more.
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                self?.queue.async { self?.finish("the server closed its output") }
                return
            }
            self?.queue.async { self?.receive(chunk) }
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            self?.queue.async {
                guard let self else { return }
                self.stderrTail = String((self.stderrTail + String(decoding: chunk, as: UTF8.self)).suffix(2_000))
            }
        }
        process.terminationHandler = { [weak self] ended in
            self?.queue.async {
                guard let self, self.process === ended else { return }
                self.finish("the server ended (status \(ended.terminationStatus))")
            }
        }
        do {
            try ArisChildren.run(process)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            return "couldn't start \(executable.lastPathComponent): \(error.localizedDescription)"
        }
        self.process = process
        input = stdin.fileHandleForWriting
        return nil
    }

    private func receive(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            let trimmed = line.filter { $0 != UInt8(ascii: "\r") }
            guard !trimmed.isEmpty else { continue }
            if let value = ArisMCPWire.decode(Data(trimmed)) { onMessage?(value) }
        }
        if buffer.count > Self.maxLine { finish("the server wrote a line too long to read") }
    }

    func send(_ message: [String: Any]) {
        guard let data = ArisMCPWire.encode(message) else { return }
        queue.async { [self] in
            guard let input else { return }
            do { try input.write(contentsOf: data + Data("\n".utf8)) } catch { finish("couldn't write to the server") }
        }
    }

    func close() {
        queue.sync { finish(nil) }
    }

    private func finish(_ why: String?) {
        guard let running = process else { return }
        process = nil
        (running.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        if let errors = (running.standardError as? Pipe)?.fileHandleForReading {
            errors.readabilityHandler = nil
            // Its last words (why it stopped) may not have been handed over yet: what is waiting is taken now, without
            // waiting for more (something it started may still hold the pipe).
            stderrTail = String((stderrTail + Self.waiting(in: errors)).suffix(2_000))
        }
        try? input?.close()
        input = nil
        if running.isRunning {
            running.terminate()
            let pid = running.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { if running.isRunning { kill(pid, SIGKILL) } }
        }
        if let folder { try? FileManager.default.removeItem(at: folder) }
        folder = nil
        onClose?(why)
    }
}

extension ArisMCPStdio {
    /// What a pipe holds right now, at most 8 KB, never blocking.
    static func waiting(in handle: FileHandle) -> String {
        let descriptor = handle.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else { return "" }
        var buffer = [UInt8](repeating: 0, count: 8_192)
        let count = read(descriptor, &buffer, buffer.count)
        return count > 0 ? String(decoding: buffer[0..<count], as: UTF8.self) : ""
    }
}

// MARK: - streamable HTTP

final class ArisMCPHTTP: NSObject, ArisMCPTransport, URLSessionDataDelegate {
    /// The most one response may bring.
    static let maxResponse = 8 * 1_024 * 1_024

    var onMessage: ((Any) -> Void)?
    var onClose: ((String?) -> Void)?
    private let url: URL
    private let headers: [String: String]
    private let queue = DispatchQueue(label: "com.lumenjsn.aris.mcp.http")
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 60
        configuration.connectionProxyDictionary = [:]
        let operations = OperationQueue()
        operations.underlyingQueue = queue
        operations.maxConcurrentOperationCount = 1
        return URLSession(configuration: configuration, delegate: self, delegateQueue: operations)
    }()
    private var sessionId: String?
    private var version: String?
    private struct Reply { var data = Data(); var stream = false; var status = 0 }
    private var replies: [Int: Reply] = [:]
    private var closed = false

    /// `headers`: the secret's header (and nothing the agent sets itself).
    init(url: URL, headers: [String: String]) {
        self.url = url
        self.headers = headers
    }

    func start() -> String? { nil }

    func agreed(version: String) { queue.async { self.version = version } }

    func send(_ message: [String: Any]) {
        guard let body = ArisMCPWire.encode(message) else { return }
        queue.async { [self] in
            guard !closed else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
            request.setValue("Aris", forHTTPHeaderField: "User-Agent")
            if let sessionId { request.setValue(sessionId, forHTTPHeaderField: "Mcp-Session-Id") }
            if let version { request.setValue(version, forHTTPHeaderField: "MCP-Protocol-Version") }
            for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
            let task = session.dataTask(with: request)
            replies[task.taskIdentifier] = Reply()
            task.resume()
        }
    }

    func close() {
        queue.sync {
            guard !closed else { return }
            closed = true
            // The session ends on the server too, best effort.
            if let sessionId {
                var request = URLRequest(url: url, timeoutInterval: 5)
                request.httpMethod = "DELETE"
                request.setValue(sessionId, forHTTPHeaderField: "Mcp-Session-Id")
                for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
                session.dataTask(with: request).resume()
            }
            session.finishTasksAndInvalidate()
        }
    }

    // MARK: URLSession (on `queue`)

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // A redirect would carry the secret somewhere else.
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else { return completionHandler(.cancel) }
        if let id = http.value(forHTTPHeaderField: "Mcp-Session-Id"), id.count <= 256, id.allSatisfy({ $0.isASCII && !$0.isWhitespace }) {
            sessionId = id
        }
        let type = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        replies[dataTask.taskIdentifier]?.status = http.statusCode
        replies[dataTask.taskIdentifier]?.stream = type.hasPrefix("text/event-stream")
        switch http.statusCode {
        case 200..<300: completionHandler(.allow)
        case 401, 403:
            completionHandler(.cancel)
            onClose?("the server refused the key (HTTP \(http.statusCode))")
        case 404 where sessionId != nil:
            completionHandler(.cancel)
            onClose?("the server ended the session")
        default:
            completionHandler(.cancel)
            onClose?("the server answered HTTP \(http.statusCode)")
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard var reply = replies[dataTask.taskIdentifier] else { return }
        reply.data.append(data)
        if reply.data.count > Self.maxResponse {
            replies[dataTask.taskIdentifier] = nil
            dataTask.cancel()
            onClose?("the server's answer was too large")
            return
        }
        if reply.stream {
            for event in ArisMCPWire.events(&reply.data) {
                if let value = ArisMCPWire.decode(Data(event.utf8)) { onMessage?(value) }
            }
        }
        replies[dataTask.taskIdentifier] = reply
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let reply = replies.removeValue(forKey: task.taskIdentifier) else { return }
        if let error, (error as NSError).code != NSURLErrorCancelled {
            onClose?("couldn't reach the server: \(error.localizedDescription)")
            return
        }
        guard (200..<300).contains(reply.status) else { return }
        if reply.stream {
            var rest = reply.data + Data("\n\n".utf8)
            for event in ArisMCPWire.events(&rest) {
                if let value = ArisMCPWire.decode(Data(event.utf8)) { onMessage?(value) }
            }
        } else if !reply.data.isEmpty, let value = ArisMCPWire.decode(reply.data) {
            onMessage?(value)
        }
    }
}
