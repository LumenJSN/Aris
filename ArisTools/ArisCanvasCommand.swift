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
    guard var url = components.url else { return .failure(CanvasProblem(message: "bad Canvas address")) }
    // Every page of the planner (Link: rel="next", on this host only), each request with its own limit, and the reason
    // said when no answer came (it used to be dropped: "Canvas didn't answer").
    var items: [ArisCanvas.Item] = []
    let deadline = Date().addingTimeInterval(ArisCanvas.allPagesWithin)
    for _ in 0..<ArisCanvas.maxPages {
        let page = canvasPage(url, token: token, deadline: deadline)
        guard page.status == 200, let data = page.data else {
            let message = page.status == 0 ? ArisCanvas.problem(noAnswer: page.error, host: host) : ArisCanvas.problem(status: page.status)
            // A later page that fails leaves what was read; the first one is the whole answer.
            return items.isEmpty ? .failure(CanvasProblem(message: message)) : .success(items)
        }
        items += ArisCanvas.items(from: data)
        guard let next = ArisCanvas.nextPage(link: page.link, host: host), Date() < deadline else { break }
        url = next
    }
    return .success(items)
}

/// One page: its body, HTTP status (0: no answer), URLSession's error code and `Link` header; tried once more after a
/// quick failure of the network that may pass (ArisCanvas.retries).
private func canvasPage(_ url: URL, token: String, deadline: Date) -> (data: Data?, status: Int, error: URLError.Code?, link: String?) {
    for attempt in 0..<2 {
        let started = Date()
        let left = deadline.timeIntervalSince(started)
        guard left > 1 else { return (nil, 0, .timedOut, nil) }
        var request = URLRequest(url: url, timeoutInterval: min(ArisCanvas.requestTimeout, left))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        var result: (data: Data?, status: Int, error: URLError.Code?, link: String?) = (nil, 0, nil, nil)
        let done = DispatchSemaphore(value: 0)
        ArisNoStore.session.dataTask(with: request) { data, response, error in
            let http = response as? HTTPURLResponse
            result = (data, http?.statusCode ?? 0, (error as? URLError)?.code, http?.value(forHTTPHeaderField: "Link"))
            done.signal()
        }.resume()
        done.wait()
        guard attempt == 0, result.status == 0, ArisCanvas.retries(result.error, elapsed: Date().timeIntervalSince(started)) else { return result }
        Thread.sleep(forTimeInterval: 1)
    }
    return (nil, 0, nil, nil)
}
