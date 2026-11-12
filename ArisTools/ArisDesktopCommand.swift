//
//  ArisDesktopCommand.swift
//  aris-tools
//
//  `desktop <verb> …`: computer use in another app (Peekaboo, through the agent). aris-tools holds no rule: it hands
//  the words to the agent (POST /desktop-tool) with its turn's credential, and the agent's desktop engine reads them
//  again, gates the call (reads judged on a careful turn, actions on the user's card, never in password stores, Keychain or
//  Aris) and runs it. A type, set-value or dialog input takes its text on stdin only (`--stdin`), so the text is never in
//  the brain's shell line or aris-tools' argv; the agent hands it to Peekaboo itself.
//

import Foundation

/// The text on stdin for `--stdin`: at most `limit` bytes (more is refused), one final line break taken off (a heredoc
/// always ends with one). Nil for anything that isn't UTF-8.
func desktopText(from handle: FileHandle, limit: Int) -> String? {
    guard let data = try? handle.read(upToCount: limit + 1), data.count <= limit else { return nil }
    guard var text = String(data: data, encoding: .utf8), !text.contains("\0") else { return nil }
    if text.hasSuffix("\n") { text.removeLast() }
    return text
}

func desktop(_ args: [String]) {
    guard let path = ProcessInfo.processInfo.environment["ARIS_MCP_TURN_FILE"], path.hasPrefix("/"), let turn = readCredential(path), !turn.isEmpty else {
        fail("aris-tools desktop works only inside an Aris turn")
    }
    var body: [String: Any] = ["turn": turn, "words": args]
    if args.contains("--stdin") {
        guard let text = desktopText(from: FileHandle.standardInput, limit: 131_072) else { fail("the text on stdin must be UTF-8, at most 128 KiB") }
        body["text"] = text
    }
    guard let token = ClaudeHookToken.load(), let url = URL(string: "http://127.0.0.1:23351/desktop-tool") else { fail("Aris's agent isn't set up (no token)") }
    // A card waits up to ten minutes for a background job, a minute in a conversation; an install downloads first.
    let wait: TimeInterval = 780
    var request = URLRequest(url: url, timeoutInterval: wait)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = wait
    configuration.timeoutIntervalForResource = wait
    let done = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var reply: [String: Any]?
    URLSession(configuration: configuration).dataTask(with: request) { data, _, _ in
        if let data { reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] }
        done.signal()
    }.resume()
    _ = done.wait(timeout: .now() + wait + 5)
    guard let reply, let output = reply["output"] as? String else { fail("Aris's agent didn't answer (is it running?)") }
    let status = (reply["status"] as? Int) ?? 1
    if status == 0 { print(output) } else { FileHandle.standardError.write(Data((output + "\n").utf8)) }
    exit(Int32(clamping: status))
}
