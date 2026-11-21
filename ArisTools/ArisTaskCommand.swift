//
//  ArisTaskCommand.swift
//  aris-tools
//
//  `task list`, `task status <id>`, `task add <id> "<instruction>"` (or `--stdin`), `task cancel <id>`,
//  `task pause <id>`: the background tasks the conversation handed out, by the ids of its <work> block. aris-tools
//  reads and writes nothing itself: it hands the words to the agent (POST /task-tool) with its turn's credential, and
//  prints the agent's answer.
//

import Foundation

func task(_ args: [String]) {
    let body: [String: Any]
    let readStdin = { String(decoding: FileHandle.standardInput.readDataToEndOfFile().prefix(8_192), as: UTF8.self) }
    switch taskRequest(args, environment: ProcessInfo.processInfo.environment, stdin: readStdin) {
    case .failure(let why): fail(why.text)
    case .success(let made): body = made
    }
    guard let token = ClaudeHookToken.load(), let url = URL(string: "http://127.0.0.1:23351/task-tool") else {
        fail("Aris's agent isn't set up (no token)")
    }
    let wait: TimeInterval = 20
    var request = URLRequest(url: url, timeoutInterval: wait)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    let configuration = ArisNoStore.configuration()
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
