//
//  ArisWebCommand.swift
//  aris-tools
//
//  `web fetch <address>`: one public page as text (ArisWebFetch), for agy's relay, which runs it as Aris only after the
//  read judge allowed the address. `web search` is the relay's own (a searcher agy with only the judged query:
//  ArisAgySearch), never aris-tools'. The address and every redirect pass ArisWebFetch.allows (each name resolved, every
//  address public), and the body is streamed with a hard cap: past ArisWebFetch.maxBytes the transfer stops. After
//  it, the address every transaction actually connected to (redirects included: URLSessionTaskTransactionMetrics) must
//  be public too, or the body is thrown away (R4: a name that resolved one way for the check and another for the fetch).
//

import Foundation

/// Gathers the body as it streams, stopping at the cap; refuses a redirect to anything ArisWebFetch.allows doesn't.
private final class ArisWebReader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var problemText: String?
    private var typeText = ""
    let done = DispatchSemaphore(value: 0)
    let measured = DispatchSemaphore(value: 0)
    private var connectedTo: [String?] = []

    var body: Data { lock.withLock { data } }
    /// Whether every transaction connected to a public address (none recorded: no).
    var connectedPublicly: Bool { lock.withLock { ArisWebFetch.connectedPublicly(connectedTo) } }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        lock.withLock { connectedTo = metrics.transactionMetrics.map(\.remoteAddress) }
        measured.signal()
    }
    var problem: String? { lock.withLock { problemText } }
    var type: String { lock.withLock { typeText } }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let next = request.url, ArisWebFetch.allows(next.absoluteString) != nil else {
            lock.withLock { problemText = "it redirected to an address that isn't public" }
            return completionHandler(nil)
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let http = response as? HTTPURLResponse
        let refused = lock.withLock { () -> Bool in
            typeText = (http?.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            if let http, !(200..<300).contains(http.statusCode) { problemText = "the page answered \(http.statusCode)" }
            return problemText != nil
        }
        completionHandler(refused ? .cancel : .allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        let full = lock.withLock { () -> Bool in
            data.append(chunk.prefix(ArisWebFetch.maxBytes - data.count))
            return data.count >= ArisWebFetch.maxBytes
        }
        // The cap: what came so far is kept, the rest never read.
        if full { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.withLock {
            if let error, (error as NSError).code != NSURLErrorCancelled, problemText == nil { problemText = error.localizedDescription }
        }
        done.signal()
    }
}

func web(_ args: [String]) {
    guard args.first == "fetch" else {
        fail(args.first == "search" ? "aris-tools web search runs only through Aris's relay" : "usage: aris-tools web fetch <https://…>")
    }
    guard args.count == 2, let url = ArisWebFetch.allows(args[1]) else { fail("web fetch: only a public http(s) address, as one word") }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = ArisWebFetch.timeout
    configuration.timeoutIntervalForResource = ArisWebFetch.timeout
    configuration.httpCookieAcceptPolicy = .never
    configuration.httpShouldSetCookies = false
    configuration.urlCache = nil
    let reader = ArisWebReader()
    let session = URLSession(configuration: configuration, delegate: reader, delegateQueue: nil)
    var request = URLRequest(url: url, timeoutInterval: ArisWebFetch.timeout)
    request.setValue("Mozilla/5.0 (Macintosh) Aris", forHTTPHeaderField: "User-Agent")
    request.setValue("text/html,text/plain;q=0.9,*/*;q=0.5", forHTTPHeaderField: "Accept")
    session.dataTask(with: request).resume()
    _ = reader.done.wait(timeout: .now() + ArisWebFetch.timeout + 5)
    _ = reader.measured.wait(timeout: .now() + 3)
    session.invalidateAndCancel()
    if let problem = reader.problem { fail("web fetch failed: \(problem)") }
    guard reader.connectedPublicly else { fail("web fetch: it connected to an address that isn't public, so the page was thrown away") }
    let body = reader.body, type = reader.type
    guard !body.isEmpty else { fail("web fetch: the page was empty") }
    guard type.isEmpty || type.contains("text") || type.contains("html") || type.contains("json") || type.contains("xml") else {
        fail("web fetch: not a text page (\(type))")
    }
    let raw = String(decoding: body, as: UTF8.self)
    print(type.contains("html") || raw.range(of: "<html", options: .caseInsensitive) != nil ? ArisWebFetch.text(fromHTML: raw) : String(raw.prefix(ArisWebFetch.maxText)))
}
