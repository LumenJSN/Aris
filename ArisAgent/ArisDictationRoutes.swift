//
//  ArisDictationRoutes.swift
//  aris-agent
//
//  Dictation's own routes, for the notch app only (main.swift checks it is the app):
//    POST /caret {}  ->  {"before", "after"} or {}: the words around the caret (ArisFocusedField; polish only)
//    POST /polish {"text", "style", "words"?, "before"?, "after"?}  ->  {"text"} or 500: the brain fallback for
//                 polish: one Claude call on the quick model with no tools, no MCP, no hooks, no session, and the
//                 same instruction as on-device (ArisPolishPrompt). The caret's words are data in it; it can't act.
//    POST /dictionary {"op": "accept"|"dismiss"|"remove", "text"}  ->  {} or 400: the learned dictionary
//

import Foundation
import Network

enum ArisDictationRoutes {
    static let paths: Set<String> = ["/caret", "/polish", "/dictionary"]
    private static let timeout: TimeInterval = 10
    private static let maxReply = 16_384
    private static let wordLength = 40

    static func handle(_ path: String, _ object: [String: Any], on connection: NWConnection) {
        switch path {
        case "/caret":
            ArisEditWatch.queue.async {
                let context = ArisFocusedField.caretContext()
                let body: [String: Any] = context.map { ["before": $0.before, "after": $0.after] } ?? [:]
                respond(connection, "200 OK", (try? JSONSerialization.data(withJSONObject: body)) ?? Data("{}".utf8))
            }
        case "/polish":
            guard let text = object["text"] as? String, !text.isEmpty, text.count <= ArisPolishPrompt.textLimit,
                  let style = (object["style"] as? String).flatMap(ArisWritingStyle.init(rawValue:)), style.polishes else {
                return respond(connection, "400 Bad Request", Data())
            }
            let words = ((object["words"] as? [String]) ?? []).filter { $0.count <= wordLength }.prefix(ArisPolishPrompt.wordLimit)
            let before = (object["before"] as? String).map { String($0.suffix(ArisPolishPrompt.contextLimit)) }
            let after = (object["after"] as? String).map { String($0.prefix(ArisPolishPrompt.contextLimit)) }
            polish(instruction: ArisPolishPrompt.instructions(style: style, words: Array(words)),
                   input: ArisPolishPrompt.input(text, before: before, after: after)) { reply in
                guard let reply else { return respond(connection, "500 Internal Server Error", Data("{}".utf8)) }
                respond(connection, "200 OK", (try? JSONSerialization.data(withJSONObject: ["text": reply])) ?? Data("{}".utf8))
            }
        case "/dictionary":
            guard let op = object["op"] as? String, let text = object["text"] as? String, !text.isEmpty, text.count <= wordLength else {
                return respond(connection, "400 Bad Request", Data())
            }
            ArisEditWatch.queue.async {
                let done = ArisDictionaryStore.apply(op, text: text)
                respond(connection, done ? "200 OK" : "400 Bad Request", Data("{}".utf8))
            }
        default:
            respond(connection, "404 Not Found", Data())
        }
    }

    static func arguments(model: String, instruction: String) -> [String] {
        ["-p", "--model", model, "--effort", "low", "--tools", "", "--permission-mode", "dontAsk",
         "--setting-sources", "", "--settings", #"{"disableAllHooks":true}"#,
         "--strict-mcp-config", "--mcp-config", #"{"mcpServers":{}}"#,
         "--no-session-persistence", "--output-format", "text", "--system-prompt", instruction]
    }

    /// One tool-less Claude call; `done` gets its text, or nil (no Claude, too slow, failed), once, on a background queue.
    private static func polish(instruction: String, input: String, done: @escaping (String?) -> Void) {
        guard let claude = ArisClaudeDriver.installed(["~/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]) else {
            return done(nil)
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let process = ArisExactProcess()
            process.executableURL = claude
            process.arguments = arguments(model: ArisBrain.claude.model(tier: .quick), instruction: instruction)
            process.environment = ArisAgentRunner.environment()
            let stdin = Pipe(), stdout = Pipe()
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = FileHandle.nullDevice
            let finished = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in finished.signal() }
            do { try ArisChildren.run(process) } catch { return done(nil) }
            // On its own queue, under the time limit below: a child that stalls without reading can't hold the polish (ArisChildFeed).
            ArisChildFeed.feed(Data(input.utf8), to: stdin.fileHandleForWriting, closing: true)
            let output = ArisPolishOutput()
            let read = DispatchSemaphore(value: 0)
            DispatchQueue.global(qos: .userInitiated).async {
                output.set((try? stdout.fileHandleForReading.readToEnd()) ?? Data())
                read.signal()
            }
            guard finished.wait(timeout: .now() + timeout) == .success, read.wait(timeout: .now() + 2) == .success,
                  process.terminationStatus == 0 else {
                ArisProcessEnd.end(process)
                return done(nil)
            }
            let text = String(decoding: output.data.prefix(maxReply), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            done(text.isEmpty ? nil : text)
        }
    }
}

/// The polish call's stdout, handed from the reading thread to the waiting one.
private final class ArisPolishOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = Data()

    var data: Data { lock.withLock { stored } }

    func set(_ data: Data) { lock.withLock { stored = data } }
}
