//
//  ArisSkillProcess.swift
//  aris-agent
//
//  Runs one program for the skills feature (the setup's uv, SkillSpector, a skill's script): plain argv, its own
//  environment and folder, a time limit (then it and its children are ended), and output kept up to a cap.
//  And the https downloads the setup and a GitHub link need: only to the hosts named, never following a redirect
//  anywhere else, stopped past a byte cap.
//

import Foundation

struct ArisSkillProcessResult: Equatable {
    let status: Int32
    let stdout: String
    let stderr: String
    let timedOut: Bool

    var ok: Bool { status == 0 && !timedOut }
}

enum ArisSkillProcess {
    static func run(_ executable: String, _ arguments: [String], environment: [String: String], directory: String? = nil,
                    timeout: TimeInterval, maxOutput: Int = 256 * 1_024, cancelled: @escaping () -> Bool = { false }) -> ArisSkillProcessResult {
        let process = ArisExactProcess()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        if let directory { process.currentDirectoryURL = URL(fileURLWithPath: directory, isDirectory: true) }
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        let collected = ArisSkillOutput(limit: maxOutput)
        // An empty read is that output's end: its handler goes (it would fire again at once, for as long as it stayed).
        for (pipe, isError) in [(out, false), (err, true)] {
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty { handle.readabilityHandler = nil }
                collected.add(chunk, error: isError)
            }
        }
        do { try ArisChildren.run(process) } catch {
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            return ArisSkillProcessResult(status: -1, stdout: "", stderr: "couldn't start \((executable as NSString).lastPathComponent)", timedOut: false)
        }
        let group = process.processIdentifier
        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false
        while process.isRunning {
            if Date() > deadline || cancelled() {
                timedOut = true
                // It leads its own process group: what it started is told to stop with it.
                kill(-group, SIGTERM)
                ArisProcessEnd.end(process)
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        process.waitUntilExit()
        if timedOut { kill(-group, SIGKILL) }
        // A program that has ended has said all it will: its output is waited for only a moment. Something it left
        // running in the background (a preview server, a watcher) keeps the pipes open for as long as it lives, and
        // reading to their end would hang `skill run` on a script that worked (audit imp-skill-drain).
        let patience = Date().addingTimeInterval(Self.drainGrace)
        while !collected.ended, Date() < patience { Thread.sleep(forTimeInterval: 0.01) }
        out.fileHandleForReading.readabilityHandler = nil
        err.fileHandleForReading.readabilityHandler = nil
        let (stdout, stderr) = collected.texts
        return ArisSkillProcessResult(status: process.terminationStatus, stdout: stdout, stderr: stderr, timedOut: timedOut)
    }

    /// How long a finished program's output is still read.
    static let drainGrace: TimeInterval = 0.5
}

/// Output gathered on the pipes' queues, up to a cap each.
private final class ArisSkillOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var out = Data(), err = Data()
    private var outEnded = false, errEnded = false
    private let limit: Int

    init(limit: Int) { self.limit = limit }

    /// Both outputs have reached their end (an empty read).
    var ended: Bool { lock.withLock { outEnded && errEnded } }

    func add(_ data: Data, error: Bool) {
        guard !data.isEmpty else {
            lock.withLock { if error { errEnded = true } else { outEnded = true } }
            return
        }
        lock.withLock {
            if error { if err.count < limit { err.append(data.prefix(limit - err.count)) } }
            else if out.count < limit { out.append(data.prefix(limit - out.count)) }
        }
    }

    var texts: (String, String) { lock.withLock { (String(decoding: out, as: UTF8.self), String(decoding: err, as: UTF8.self)) } }
}

/// One https download into memory.
protocol ArisSkillDownloading: AnyObject {
    /// The bytes at `url`, or why not. `progress` gets the bytes so far.
    func fetch(_ url: URL, maxBytes: Int, hosts: Set<String>, progress: @escaping (Int) -> Void) -> Result<Data, ArisSkillWhy>
}

final class ArisSkillDownloader: NSObject, ArisSkillDownloading, URLSessionDataDelegate {
    private let lock = NSLock()
    private var buffers: [Int: Data] = [:]
    private var limits: [Int: (max: Int, hosts: Set<String>, progress: (Int) -> Void)] = [:]
    private var failures: [Int: String] = [:]
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        configuration.httpAdditionalHeaders = ["User-Agent": "Aris-skills", "Accept": "*/*"]
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    func fetch(_ url: URL, maxBytes: Int, hosts: Set<String>, progress: @escaping (Int) -> Void) -> Result<Data, ArisSkillWhy> {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(), hosts.contains(host) else { return .failure("https 주소가 아니에요.") }
        let done = DispatchSemaphore(value: 0)
        let task = session.dataTask(with: URLRequest(url: url, timeoutInterval: 30))
        let box = ArisSkillFetchBox()
        lock.withLock {
            buffers[task.taskIdentifier] = Data()
            limits[task.taskIdentifier] = (maxBytes, hosts, progress)
            observers[task.taskIdentifier] = { error in
                box.error = error
                done.signal()
            }
        }
        task.resume()
        done.wait()
        let id = task.taskIdentifier
        let (data, failure) = lock.withLock { () -> (Data, String?) in
            defer { buffers[id] = nil; limits[id] = nil; failures[id] = nil; observers[id] = nil }
            return (buffers[id] ?? Data(), failures[id])
        }
        if let failure { return .failure(ArisSkillWhy(failure)) }
        if let error = box.error { return .failure("다운로드가 끊겼어요 (\(error.localizedDescription))") }
        if let status = (task.response as? HTTPURLResponse)?.statusCode, status != 200 {
            return .failure(status == 404 ? "찾을 수 없어요 (404). 링크를 확인해 주세요." : "서버가 \(status)로 답했어요.")
        }
        return .success(data)
    }

    private var observers: [Int: (Error?) -> Void] = [:]

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let hosts = lock.withLock { limits[task.taskIdentifier]?.hosts ?? [] }
        guard let url = request.url, url.scheme?.lowercased() == "https", let host = url.host?.lowercased(), hosts.contains(host) else {
            lock.withLock { failures[task.taskIdentifier] = "다른 곳으로 보내려고 해서 멈췄어요." }
            return completionHandler(nil)
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let (count, report, over) = lock.withLock { () -> (Int, ((Int) -> Void)?, Bool) in
            buffers[dataTask.taskIdentifier]?.append(data)
            let count = buffers[dataTask.taskIdentifier]?.count ?? 0
            let limit = limits[dataTask.taskIdentifier]
            let over = count > (limit?.max ?? 0)
            if over { failures[dataTask.taskIdentifier] = "너무 커요 (\((limit?.max ?? 0) / 1_048_576)MB 넘음)." }
            return (count, limit?.progress, over)
        }
        if over { return dataTask.cancel() }
        report?(count)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let observer = lock.withLock { observers[task.taskIdentifier] }
        observer?(error)
    }
}

private final class ArisSkillFetchBox: @unchecked Sendable {
    var error: Error?
}
