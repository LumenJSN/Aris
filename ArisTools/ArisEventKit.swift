//
//  ArisEventKit.swift
//  aris-tools
//
//  `aris-tools event find|delete|change` (its words: ArisEventWords), and the add when the app may use the calendars: asked of the Aris app over
//  POST /aris/events (ArisEventRoute), which holds the Calendar grant. aris-tools never asks for one of its own (QA
//  BUG-53 retest). A missing grant is told by a fixed line naming the app.
//

import Foundation

/// The app's answer to an event request; nil when the app didn't answer (it isn't running).
func askEvents(_ body: [String: Any]) -> [String: Any]? {
    guard let token = ClaudeHookToken.load(), let url = URL(string: "http://127.0.0.1:23350/aris/events") else { return nil }
    var request = URLRequest(url: url, timeoutInterval: 20)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    let done = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var reply: [String: Any]?
    URLSession.shared.dataTask(with: request) { data, response, _ in
        if (response as? HTTPURLResponse)?.statusCode == 200, let data { reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] }
        done.signal()
    }.resume()
    _ = done.wait(timeout: .now() + 21)
    return reply
}

/// `event find|delete|change …`.
func eventEdit(_ args: [String]) {
    guard let body = ArisEventWords.body(args) else { fail(ArisEventWords.usage) }
    guard let reply = askEvents(body) else { fail("The Aris app didn't answer, so nothing was found or changed. Tell the user Aris needs to be running.") }
    let line = reply["line"] as? String ?? "no answer"
    guard reply["ok"] as? Bool == true else { fail(line) }
    if args.first != "find" {
        logActivity(args.first == "delete" ? "일정 삭제: \(body["title"] as? String ?? "")" : "일정 변경: \(body["rename"] as? String ?? body["title"] as? String ?? "")", undo: nil)
    }
    print(line)
}
