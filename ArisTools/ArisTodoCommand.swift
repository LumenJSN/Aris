//
//  ArisTodoCommand.swift
//  aris-tools
//
//  `todo` lists the open items of the to-do list, which is Apple Reminders (the notch app owns it; this asks it over
//  the hook server's POST /aris/todos with the shared token). `todo add <text> [--due <words>] [--list <name>]
//  [--note <text>]` adds one and `todo done <words>` ticks off the one item those words name.
//

import Foundation

/// The same question, for an undo (ArisActivityCommand): the app's answer, or a refusal when it didn't answer.
func todoRequest(_ body: [String: Any]) -> [String: Any] { askTodos(body) }

private func askTodos(_ body: [String: Any]) -> [String: Any] {
    guard let token = ClaudeHookToken.load(), let url = URL(string: "http://127.0.0.1:23350/aris/todos") else {
        fail("the notch app isn't set up for to-dos (no hook token)")
    }
    var request = URLRequest(url: url, timeoutInterval: 20)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    let done = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var reply: [String: Any]?
    URLSession.shared.dataTask(with: request) { data, response, _ in
        if (response as? HTTPURLResponse)?.statusCode == 200, let data {
            reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        done.signal()
    }.resume()
    _ = done.wait(timeout: .now() + 21)
    guard let reply else { fail("the notch app didn't answer (is Aris running?)") }
    return reply
}

/// "--due x --list y --note z" and what comes before the first flag.
private func todoOptions(_ args: [String]) -> (words: String, options: [String: String]) {
    var words: [String] = []
    var options: [String: String] = [:]
    var index = 0
    while index < args.count {
        if args[index].hasPrefix("--"), index + 1 < args.count {
            options[String(args[index].dropFirst(2))] = args[index + 1]
            index += 2
        } else {
            words.append(args[index])
            index += 1
        }
    }
    return (words.joined(separator: " "), options)
}

func todo(_ args: [String]) {
    let (words, options) = todoOptions(Array(args.dropFirst()))
    switch args.first {
    case "add":
        guard !words.trimmingCharacters(in: .whitespaces).isEmpty else { fail("usage: todo add <text> [--due <words>] [--list <name>] [--note <text>]") }
        var body: [String: Any] = ["op": "add", "text": words]
        for key in ["due", "list", "note"] { if let value = options[key] { body[key] = value } }
        let reply = askTodos(body)
        guard reply["ok"] as? Bool == true else { fail(reply["message"] as? String ?? "couldn't add it") }
        // Logged, so "방금 한 거 되돌려" takes this one back (QA BUG-18).
        if let id = ((reply["items"] as? [[String: Any]])?.first?["id"] as? String) {
            logActivity("할 일 추가: \(words)", undo: ArisActivity.localUndo(kind: "todo-add", id: id, level: nil) ?? nil)
        }
        print(reply["message"] as? String ?? "added")
    case "done", "remove":
        let reply = askTodos(["op": args[0], "text": words])
        guard reply["ok"] as? Bool == true else { fail(reply["message"] as? String ?? "couldn't change it") }
        let item = (reply["items"] as? [[String: Any]])?.first
        if args[0] == "done", let id = item?["id"] as? String {
            logActivity("할 일 완료: \(item?["title"] as? String ?? words)", undo: ArisActivity.localUndo(kind: "todo-done", id: id, level: nil) ?? nil)
        } else if args[0] == "remove" {
            logActivity("할 일 지움: \(words)", undo: nil)
        }
        print(reply["message"] as? String ?? args[0])
    case "edit":
        // A new due date, note or title for an item already on the list (never a second copy of it).
        guard !words.trimmingCharacters(in: .whitespaces).isEmpty, !options.isEmpty else {
            fail("usage: todo edit <words naming one item> [--due <words>] [--note <text>] [--title <new title>]")
        }
        var body: [String: Any] = ["op": "edit", "text": words]
        for key in ["due", "note", "title"] { if let value = options[key] { body[key] = value } }
        let reply = askTodos(body)
        guard reply["ok"] as? Bool == true else { fail(reply["message"] as? String ?? "couldn't change it") }
        print(reply["message"] as? String ?? "updated")
    default:
        let reply = askTodos(["op": "list"])
        guard reply["ok"] as? Bool == true else { fail(reply["message"] as? String ?? "couldn't read the list") }
        let items = reply["items"] as? [[String: Any]] ?? []
        print(items.isEmpty ? "the to-do list is empty" : items.map { item in
            let due = (item["due"] as? String).map { " (due \($0))" } ?? ""
            return "- \(item["title"] as? String ?? "")\(due) [\(item["list"] as? String ?? "")]"
        }.joined(separator: "\n"))
    }
}
