//
//  ArisBrainFailure.swift
//  aris-agent
//
//  What a brain's command-line tool says when it can't answer, turned into one line the user can read: a login that
//  expired, a quota or load limit (another AI can take the question), or the tool's own words, named. Also the small
//  pieces the runner uses to tell a changed CLI apart from a slow one: the last bytes of a child's stderr, and a count
//  of lines its driver didn't recognise.
//

import Foundation

enum ArisBrainFailure {
    /// The tool can't answer right now (quota, rate limit, overloaded): the question may go to another AI.
    static func isUnavailable(_ text: String) -> Bool {
        // Whole words (an underscore may join them, as in rate_limit_error): "1429" or "quotas.md" don't count.
        text.range(of: #"(?i)(?<![a-z0-9])(usage limits?|rate limits?|rate_limits?|overloaded|quotas?|too many requests|429|529|capacity)(?![a-z0-9])"#,
                   options: .regularExpression) != nil
    }

    /// The tool's login is missing or expired: only the user can fix it, in a terminal.
    static func isLoginProblem(_ text: String) -> Bool {
        let lower = text.lowercased()
        return ["not logged in", "/login", "login", "log in", "unauthorized", "401", "authentication", "oauth token", "credentials", "api key"]
            .contains { lower.contains($0) }
    }

    /// The command the user runs in a terminal to log in again.
    static func command(for brain: ArisBrain) -> String {
        switch brain {
        case .claude: return "claude"
        case .codex: return "codex"
        case .antigravity: return "agy"
        case .api: return "aris"
        }
    }

    /// The longest a tool's own message is shown.
    static let longest = 200

    /// One line for the notch, in the language of the request it answers (`korean`; VM run, bug 4: the limit, login
    /// and key lines were Korean under an English request). `now` and `timeZone` only matter for a reset time the
    /// message names (ArisBrainHealth.resetDate).
    static func friendly(_ text: String, brain: ArisBrain, korean: Bool = true, now: Date = Date(), timeZone: TimeZone = .current) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = brain.title(english: !korean)
        if trimmed.isEmpty { return korean ? "\(brain.title)가 답하지 않았어요." : "\(name) didn't answer." }
        if isUnavailable(trimmed) {
            guard let reset = ArisBrainHealth.resetDate(in: trimmed, now: now, timeZone: timeZone) else {
                return korean ? "\(brain.title) 한도에 닿았어요. 잠시 뒤에 다시 해 주세요." : "\(name) has reached its limit. Please try again in a little while."
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: korean ? "ko_KR" : "en_US")
            formatter.timeZone = timeZone
            formatter.dateFormat = korean ? "M월 d일 a h:mm" : "MMM d, h:mm a"
            return korean ? "\(brain.title) 한도에 닿았어요. \(formatter.string(from: reset))부터 다시 돼요."
                : "\(name) has reached its limit. It works again from \(formatter.string(from: reset))."
        }
        if isLoginProblem(trimmed) {
            // An API brain's login is its key, which the user saves in settings (never a terminal). The English names the
            // page alone: the app writes it as its own window names it (ArisSettingsPath).
            if brain == .api {
                return korean ? "\(brain.title) 키가 맞지 않아요. 설정 › AI 서비스 › 두뇌에서 키를 다시 넣어 주세요."
                    : "The key for the \(name) isn't right. Enter it again in Settings › AI 서비스."
            }
            return korean ? "\(brain.title) 로그인이 필요해요: 터미널에서 \(command(for: brain)) 를 한 번 실행해 주세요."
                : "\(name) needs you to log in: run \(command(for: brain)) once in Terminal."
        }
        return "\(name): \(String(trimmed.prefix(longest)))"
    }

    /// A line `friendly` made in Korean, said in English. A driver makes its failure line before the turn's language is
    /// known to it (ArisBrainFailure.event), so the runner, which knows, puts it into English for an English request.
    /// Any other line (a gate's reason, the tool's own words) stays as it is.
    static func english(_ line: String, brain: ArisBrain) -> String {
        // The API brain's own lines (a refused key, too long, unreachable): its words in English (second upgrade run, bug 2).
        if let api = ArisAPIFailureWords.english(line) { return api }
        for sample in ["", "not logged in"] where line == friendly(sample, brain: brain) { return friendly(sample, brain: brain, korean: false) }
        let lead = "\(brain.title): "
        return line.hasPrefix(lead) ? "\(brain.title(english: true)): " + line.dropFirst(lead.count) : line
    }

    // MARK: - A process that ended on its own

    /// What the runner does when a brain's process ends while a question waits (audit imp-brain-died-16).
    enum Death: Equatable {
        /// Nothing had been done yet: the process is started again and the question asked once more.
        case askAgain
        /// A quota or load limit: another AI may take the question.
        case unavailable(String)
        /// The turn ends with this line.
        case say(String)
    }

    /// The tool's own last words: the last line it wrote to stderr that says anything, cut.
    static func lastWords(_ stderr: String) -> String {
        let line = stderr.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.last { !$0.isEmpty } ?? ""
        return String(line.prefix(longest))
    }

    /// A process that died before anything came from it is tried once more, in a conversation only (a job's process
    /// is its own), and never when its last words say why it can't answer (a login, a limit).
    static func death(stderr: String, brain: ArisBrain, korean: Bool, acted: Bool, isTask: Bool, events: Int, retried: Bool) -> Death {
        // Only its last few lines count as why it ended: older ones are whatever it logged along the way.
        let tail = stderr.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            .suffix(3).joined(separator: "\n")
        if isUnavailable(tail) { return .unavailable(tail) }
        let login = isLoggedOut(tail)
        if !login, !acted, !isTask, events == 0, !retried { return .askAgain }
        let said = lastWords(tail)
        if login {
            if brain == .api { return .say(friendly(tail, brain: brain, korean: korean)) }
            let run = command(for: brain)
            return .say(korean ? "\(brain.title) 로그인이 필요해요: 터미널에서 \(run) 를 한 번 실행해 주세요."
                               : "\(brain.title(english: true)) needs you to log in: run \(run) once in Terminal.")
        }
        // The tool's own words say why (a flag a new version dropped, a crash); never a log file's name.
        if !said.isEmpty { return .say(korean ? "\(brain.title)가 멈췄어요: \(said)" : "\(brain.title(english: true)) stopped: \(said)") }
        return .say(korean ? "\(brain.title)가 갑자기 멈췄어요. 한 번 더 말해 주세요." : "\(brain.title(english: true)) stopped unexpectedly. Please ask again.")
    }

    /// A tool whose last words plainly say it isn't logged in (stricter than isLoginProblem: these words end a process).
    static func isLoggedOut(_ text: String) -> Bool {
        let lower = text.lowercased()
        return ["not logged in", "please run /login", "run /login", "login required", "please log in", "codex login", "401 unauthorized",
                "invalid api key", "oauth token has expired", "authentication_error", "not authenticated"].contains { lower.contains($0) }
    }

    /// A failure from a process that nobody is asking and whose conversation never opened ends that process (a warmed
    /// Codex whose thread/start was refused). One that is being asked, or already has its conversation, is left alone:
    /// a stray late error doesn't throw a good process away.
    static func stopsIdleProcess(waiting: Bool, ready: Bool) -> Bool { !waiting && !ready }

    /// Why a brain couldn't be started at all: what it lacks (ArisBrainTrouble), else that starting failed, never a guess
    /// that it isn't installed.
    static func startLine(brain: ArisBrain, missing: ArisBrainTrouble.Missing?, korean: Bool) -> String {
        if let missing { return ArisBrainTrouble(brain: brain, missing: missing).line(korean: korean) }
        return korean ? "\(brain.title)를 시작하지 못했어요. 잠시 뒤에 다시 해 주세요." : "Couldn't start \(brain.title(english: true)). Please try again in a moment."
    }

    /// The brain didn't answer within its limit.
    static func slowLine(brain: ArisBrain, korean: Bool) -> String {
        korean ? "\(brain.title)가 너무 오래 걸려서 멈췄어요. 다시 한번 말해 주세요." : "\(brain.title(english: true)) took too long to answer. Please ask again."
    }

    /// The turn ended with neither an answer nor a reason.
    static func silentLine(brain: ArisBrain, korean: Bool) -> String {
        korean ? "\(brain.title)가 답하지 않았어요." : "\(brain.title(english: true)) didn't answer."
    }

    /// A line couldn't be written to the brain's process.
    static func unreachableLine(brain: ArisBrain, korean: Bool) -> String {
        korean ? "\(brain.title)에 닿지 못했어요. 다시 한번 말해 주세요." : "Couldn't reach \(brain.title(english: true)). Please ask again."
    }

    /// The language of a turn's lines: the user's own words decide; with none (a schedule), the prompt's. The note Aris
    /// itself adds to a request with files ("(첨부한 파일: …") is Aris's own Korean, never their words: it is left out of
    /// both (final check on a new Mac: "Mail this to minsu" with a dropped file was answered "지금 쓸 수 있는 AI가 없어요…"
    /// on an English Mac, because the note made the request read as Korean).
    static func korean(request: String, prompt: String) -> Bool {
        let own = ArisMemoryText.ownWords(request).trimmingCharacters(in: .whitespacesAndNewlines)
        return ArisBrainTrouble.isKorean(own.isEmpty ? ArisMemoryText.ownWords(prompt) : own)
    }

    /// The driver's event for a tool's error text: unavailable (raw, so the reset time can still be read) or a failure
    /// the user can read.
    static func event(_ text: String, brain: ArisBrain) -> ArisBrainEvent {
        isUnavailable(text) ? .unavailable(text) : .failure(friendly(text, brain: brain))
    }
}

/// The last `capacity` bytes a child wrote to stderr, kept in memory and written to the log only when the process
/// ends unexpectedly (a changed flag, a crash), so agent.log says why instead of "stopped unexpectedly".
struct ArisStderrTail {
    static let defaultCapacity = 4_096

    let capacity: Int
    private var bytes = Data()

    init(capacity: Int = ArisStderrTail.defaultCapacity) {
        self.capacity = capacity
    }

    mutating func append(_ data: Data) {
        bytes.append(data)
        if bytes.count > capacity { bytes = bytes.suffix(capacity) }
    }

    var text: String { String(decoding: bytes, as: UTF8.self) }
}

/// Lines a driver read but made nothing of while a turn was waiting. A renamed message type in a new CLI version would
/// otherwise look like a slow answer; the first few are named in the log (their type or method only, never the
/// payload), the rest counted.
struct ArisEventDrift {
    static let notesPerTurn = 5

    private(set) var count = 0

    /// The log line for an unrecognised `line`, for the first few of a turn; nil afterwards, and nil (uncounted) for
    /// a kind in `quiet`: one the driver knows and had nothing to say about (a name, or a "prefix/" of JSON-RPC
    /// methods; "response" for a JSON-RPC reply).
    mutating func note(_ line: String, quiet: Set<String> = []) -> String? {
        guard let data = line.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            count += 1
            return count <= Self.notesPerTurn ? "unrecognised line: (not JSON)" : nil
        }
        for key in ["type", "method", "event"] {
            guard let name = object[key] as? String else { continue }
            if quiet.contains(name) || name.split(separator: "/").first.map({ quiet.contains($0 + "/") }) == true { return nil }
            count += 1
            return count <= Self.notesPerTurn ? "unrecognised line: \(key)=\(name)" : nil
        }
        if object["id"] != nil, object["result"] != nil || object["error"] != nil, quiet.contains("response") { return nil }
        count += 1
        return count <= Self.notesPerTurn ? "unrecognised line: keys \(object.keys.sorted().joined(separator: ","))" : nil
    }

    mutating func reset() { count = 0 }

    /// What to log when a turn ends with lines read but nothing recognised.
    static func summary(count: Int, events: Int, brain: String) -> String? {
        guard count > 0, events == 0 else { return nil }
        return "\(brain): \(count) unrecognised lines, no event this turn (did the CLI's output change?)"
    }
}
