//
//  ArisGitHubStar.swift
//  aris-agent
//
//  The Aris repository's star, asked of GitHub through the user's own gh (GitHub's CLI) for the setup's last page
//  (ArisStarCard reads the answers; ArisStarCardView draws them). aris-agent runs it because the app is sandboxed and
//  can't use gh's login. Three calls, each with a 10 s limit (gh's first call after a while can take more than 5 s:
//  that is no "signed out"), never on the main thread:
//   · who is logged in: `gh api user --jq .login`;
//   · whether the repository is starred: `gh api -i /user/starred/LumenJSN/Aris` (204 yes, 404 no);
//   · the star itself: `gh api -X PUT /user/starred/LumenJSN/Aris`, run only for POST /github-star {"do": "star"},
//     which the app sends from its own button (isAppItself), never by itself.
//  No token is read or printed: gh holds it. Only the login and the status line are read from what gh prints. The
//  runner is injected, so the tests never run gh and never star anything.
//

import Foundation

enum ArisGitHubStar {
    static let repo = "LumenJSN/Aris"
    static let starredPath = "/user/starred/\(repo)"
    /// Each gh call's limit (the app waits ArisAgentClient's 20 s for both, run at once).
    static let timeout: TimeInterval = 10
    /// Where Homebrew puts gh (Apple silicon, Intel), looked at before PATH.
    static let places = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]

    /// One finished run of a program: its exit status, what it printed on stdout and stderr, and whether its time ran out.
    struct Run: Equatable {
        let status: Int32
        let out: String
        var err = ""
        var timedOut = false
    }

    /// Runs `program` with `arguments` for at most `timeout` seconds; nil when it couldn't start.
    typealias Runner = (_ program: String, _ arguments: [String], _ timeout: TimeInterval) -> Run?

    /// What the request asks for.
    enum Ask: String { case check, star }

    /// What the check found.
    enum Check: Equatable {
        /// gh isn't installed.
        case noGH
        /// gh is there and said it has no login (or GitHub refused its token).
        case signedOut
        /// gh didn't say who is logged in: its time ran out, or it failed for another reason (no network). Never read
        /// as signed out.
        case unknown
        /// Logged in as `login`; `starred` nil when GitHub's answer was neither 204 nor 404.
        case ready(login: String, starred: Bool?)
    }

    // MARK: - Finding gh

    /// gh's path: Homebrew's two places first, then each folder of `path`; nil when none has it.
    static func find(path: String?, executable: (String) -> Bool) -> String? {
        let folders = (path ?? "").split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
        return (places + folders.map { ($0.hasSuffix("/") ? String($0.dropLast()) : $0) + "/gh" }).first(where: executable)
    }

    // MARK: - Reading what gh printed

    /// The login `gh api user --jq .login` printed: GitHub's own shape (letters, digits and single inner hyphens, at
    /// most 39); nil for anything else, a failed run or one whose time ran out.
    static func login(_ run: Run?) -> String? {
        guard let run, run.status == 0, !run.timedOut else { return nil }
        let login = run.out.trimmingCharacters(in: .whitespacesAndNewlines)
        return validLogin(login) ? login : nil
    }

    static func validLogin(_ login: String) -> Bool {
        guard (1...39).contains(login.count), !login.hasPrefix("-"), !login.hasSuffix("-"), !login.contains("--") else { return false }
        return login.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-") }
    }

    /// The HTTP status on the first line `gh api -i` printed ("HTTP/2.0 204 No Content"); nil when there is none.
    static func status(_ run: Run?) -> Int? {
        guard let run, !run.timedOut, let first = run.out.split(whereSeparator: \.isNewline).first else { return nil }
        let words = first.split(separator: " ")
        guard words.count >= 2, words[0].hasPrefix("HTTP/"), let code = Int(words[1]), (100...599).contains(code) else { return nil }
        return code
    }

    /// Whether the repository is starred: 204 yes, 404 no, anything else unknown.
    static func starred(_ run: Run?) -> Bool? {
        switch status(run) {
        case 204: true
        case 404: false
        default: nil
        }
    }

    /// The PUT went through: gh exited 0 in time (GitHub answers 204 with no body).
    static func starDone(_ run: Run?) -> Bool {
        guard let run else { return false }
        return run.status == 0 && !run.timedOut
    }

    // MARK: - The calls

    /// Who is logged in and whether the repository is starred, asked at the same time (each within `timeout`).
    static func check(gh: String?, run: Runner) -> Check {
        guard let gh else { return .noGH }
        var runs: [Run?] = [nil, nil]
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: 2) { i in
            let arguments = i == 0 ? ["api", "user", "--jq", ".login"] : ["api", "-i", starredPath]
            let result = run(gh, arguments, timeout)
            lock.withLock { runs[i] = result }
        }
        guard let login = login(runs[0]) else { return signedOut(runs[0]) ? .signedOut : .unknown }
        return .ready(login: login, starred: starred(runs[1]))
    }

    /// gh itself said there is no login: it finished in time, failed, and named `gh auth login`, "not logged in" or
    /// GitHub's 401. A slow or failed run that says none of that is not a "signed out".
    static func signedOut(_ run: Run?) -> Bool {
        guard let run, !run.timedOut, run.status != 0 else { return false }
        let said = (run.err + "\n" + run.out).lowercased()
        return said.contains("gh auth login") || said.contains("not logged in") || said.contains("http 401") || said.contains("bad credentials")
    }

    /// Stars the repository; true when GitHub took it.
    static func star(gh: String?, run: Runner) -> Bool {
        guard let gh else { return false }
        return starDone(run(gh, ["api", "-X", "PUT", starredPath], timeout))
    }

    // MARK: - POST /github-star

    /// What the app asked for: {"do": "check"} or {"do": "star"}; nil for anything else.
    static func ask(request object: [String: Any]) -> Ask? { (object["do"] as? String).flatMap(Ask.init(rawValue:)) }

    /// The answer's body: {"gh": "missing" | "signedOut" | "unknown" | "ready", "login": …, "starred": true | false} for a check
    /// ("starred" left out when GitHub's answer was neither), {"starred": true | false} for a star.
    static func reply(_ check: Check) -> [String: Any] {
        switch check {
        case .noGH: return ["gh": "missing"]
        case .signedOut: return ["gh": "signedOut"]
        case .unknown: return ["gh": "unknown"]
        case .ready(let login, let starred):
            var body: [String: Any] = ["gh": "ready", "login": login]
            if let starred { body["starred"] = starred }
            return body
        }
    }

    static func reply(starred: Bool) -> [String: Any] { ["starred": starred] }

    /// The whole answer to one request, with gh found on `environment`'s PATH and run by `run`.
    static func answer(_ ask: Ask, environment: [String: String], run: Runner? = nil,
                       executable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> Data {
        let gh = find(path: environment["PATH"], executable: executable), run = run ?? runner(environment: environment)
        let body = ask == .check ? reply(check(gh: gh, run: run)) : reply(starred: star(gh: gh, run: run))
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data("{}".utf8)
    }

    // MARK: - The live runner

    /// Process, with its output read as it comes and the program stopped when its time runs out. gh is told not to
    /// prompt, page or check for updates; HOME and PATH are the agent's own.
    static func runner(environment: [String: String]) -> Runner {
        { program, arguments, timeout in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: program)
            process.arguments = arguments
            var env = environment
            env["GH_PROMPT_DISABLED"] = "1"
            env["GH_NO_UPDATE_NOTIFIER"] = "1"
            env["GH_PAGER"] = ""
            env["NO_COLOR"] = "1"
            process.environment = env
            process.standardInput = FileHandle.nullDevice
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            let ended = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in ended.signal() }
            // Through ArisChildren, as everything the helper starts (it is written down, and checked first).
            do { try ArisChildren.run(process) } catch { return nil }
            var outData = Data(), errData = Data()
            let reading = DispatchGroup()
            reading.enter()
            DispatchQueue.global(qos: .userInitiated).async { outData = out.fileHandleForReading.readDataToEndOfFile(); reading.leave() }
            reading.enter()
            DispatchQueue.global(qos: .userInitiated).async { errData = err.fileHandleForReading.readDataToEndOfFile(); reading.leave() }
            let timedOut = ended.wait(timeout: .now() + timeout) == .timedOut
            if timedOut {
                process.terminate()
                _ = ended.wait(timeout: .now() + 1)
            }
            _ = reading.wait(timeout: .now() + 1)
            return Run(status: timedOut ? -1 : process.terminationStatus, out: String(decoding: outData, as: UTF8.self),
                       err: String(decoding: errData, as: UTF8.self), timedOut: timedOut)
        }
    }
}
