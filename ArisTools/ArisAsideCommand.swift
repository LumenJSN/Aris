//
//  ArisAsideCommand.swift
//  aris-tools
//
//  `aside "<brief>"`: website work (signed-in sites, forms, booking, shopping) for Aside, the user's browser agent, the
//  same way on every brain. aris-tools runs nothing itself: it hands the brief to the agent (POST /aside-tool) with its
//  turn's credential, and the agent's one gate decides (the user's card when it asks), runs Aside and marks the conversation
//  outside text. What it prints is the agent's answer: Aside's, fenced, or the line to say when Aside isn't installed.
//

import Foundation

func aside(_ args: [String]) {
    let body: [String: Any]
    switch asideRequest(args, environment: ProcessInfo.processInfo.environment) {
    case .failure(let why): fail(why.text)
    case .success(let made): body = made
    }
    guard let token = ClaudeHookToken.load(), let url = URL(string: "http://127.0.0.1:23351/aside-tool") else {
        fail("Aris's agent isn't set up (no token)")
    }
    // A card waits up to ten minutes for a background job, then Aside may take fifteen.
    let wait: TimeInterval = 1_620
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
