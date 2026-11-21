//
//  ArisAppRoute.swift
//  aris-tools
//
//  One request to the Aris app's hook server (POST /aris/events, /aris/todos) with the shared token. From a turn the
//  user is in front of the request says so (`ask`): the app may then raise macOS's Calendars or Reminders dialog and
//  wait for the answer, so aris-tools waits as long (ArisPermissionWait). An answer that comes too late is told as
//  late, never as "Aris isn't running" (VM run 2026-11-19, A2).
//

import Foundation

/// The app's answer; the late line under `lineKey` when it answered too late; nil when no app answered (it isn't
/// running) or there is no token.
func appRouteReply(path: String, body: [String: Any], lineKey: String) -> [String: Any]? {
    guard let token = ClaudeHookToken.load(), let url = URL(string: "http://127.0.0.1:23350" + path) else { return nil }
    var body = body
    let asks = ArisAutomationAsk.isForeground(ProcessInfo.processInfo.environment)
    if asks { body["ask"] = true }
    let limit = ArisPermissionWait.requestLimit(asks: asks)
    var request = URLRequest(url: url, timeoutInterval: limit)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    let done = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var reply: [String: Any]?
    ArisNoStore.session.dataTask(with: request) { data, response, error in
        reply = ArisPermissionWait.reply(status: (response as? HTTPURLResponse)?.statusCode, data: data,
                                         timedOut: (error as? URLError)?.code == .timedOut, lineKey: lineKey)
        done.signal()
    }.resume()
    if done.wait(timeout: .now() + limit + 1) == .timedOut {
        return ArisPermissionWait.reply(status: nil, data: nil, timedOut: true, lineKey: lineKey)
    }
    return reply
}
