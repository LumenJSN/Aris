//
//  ArisCanvasCommand.swift
//  aris-tools
//
//  `canvas`: the next week on Canvas (ArisCanvas), read with the user's token in ~/.config/aris/canvas-key
//  from the school in canvas-host (e.g. q.exampleu.edu). Read only: nothing is ever submitted or posted.
//

import Foundation

/// `canvas` in words for the AI; `canvas --json` the deadlines still to hand in (ArisDue), for the to-do list.
func canvas(_ args: [String]) {
    let items = fetchCanvas()
    guard args.contains("--json") else { return print(ArisCanvas.summary(items, now: Date(), timeZone: .current)) }
    let host = (try? String(contentsOf: arisFolder.deletingLastPathComponent().appendingPathComponent("canvas-host"), encoding: .utf8))?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let due = ArisCanvas.due(items, now: Date()).map {
        ArisDue(id: $0.id, course: $0.course, title: $0.title, at: $0.date,
                url: $0.url.flatMap { $0.hasPrefix("/") ? "https://\(host)\($0)" : nil })
    }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    print(String(decoding: (try? encoder.encode(due)) ?? Data("[]".utf8), as: UTF8.self))
}

/// The planner's items from 3 days back to a week ahead; stops (fail) when Canvas isn't set up or refuses.
func fetchCanvas() -> [ArisCanvas.Item] {
    switch readCanvas() {
    case .success(let items): return items
    case .failure(let problem): fail(problem.message)
    }
}

/// Why Canvas couldn't be read, as a sentence.
struct CanvasProblem: Error {
    let message: String
}

/// The same read, without stopping: the brief leaves Canvas out when it can't be read, and keeps the rest.
func readCanvas() -> Result<[ArisCanvas.Item], CanvasProblem> {
    let folder = arisFolder.deletingLastPathComponent()
    let read = { (name: String) in
        (try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard let token = read("canvas-key"), !token.isEmpty, let host = read("canvas-host"),
          host.range(of: #"^[A-Za-z0-9.-]+$"#, options: .regularExpression) != nil else {
        return .failure(CanvasProblem(message: "Canvas isn't set up (canvas-key and canvas-host in ~/.config/aris)"))
    }
    let now = Date()
    let iso = ISO8601DateFormatter()
    var components = URLComponents()
    components.scheme = "https"
    components.host = host
    components.path = "/api/v1/planner/items"
    components.queryItems = [
        URLQueryItem(name: "start_date", value: iso.string(from: now.addingTimeInterval(-Double(ArisCanvas.daysBack) * 86_400))),
        URLQueryItem(name: "end_date", value: iso.string(from: now.addingTimeInterval(Double(ArisCanvas.daysAhead) * 86_400))),
        URLQueryItem(name: "per_page", value: "100"),
    ]
    guard let url = components.url else { return .failure(CanvasProblem(message: "bad Canvas address")) }
    var request = URLRequest(url: url, timeoutInterval: 10)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    var result: (Data?, Int) = (nil, 0)
    let done = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: request) { data, response, _ in
        result = (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        done.signal()
    }.resume()
    done.wait()
    guard result.1 == 200, let data = result.0 else { return .failure(CanvasProblem(message: ArisCanvas.problem(status: result.1))) }
    return .success(ArisCanvas.items(from: data))
}
