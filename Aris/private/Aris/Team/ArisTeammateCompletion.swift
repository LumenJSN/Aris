//
//  ArisTeammateCompletion.swift
//  Aris
//
//  When a launched Claude Code teammate is done, from the Claude hooks the app already receives. A job finishes on
//  the first Stop of a Claude session that started fresh (SessionStart with source "startup": not a resume, /clear or
//  compaction of an older session) in the job's folder at or after the launch. One
//  job per session. When two jobs wait in the same folder, the earliest launched one is finished first and the other
//  keeps waiting for the next session's Stop. A session closed (SessionEnd) before its Stop ends that job too.
//
//  The folder that counts is the one the session started in (audit team-5): a Stop's own folder is wherever Claude
//  Code had changed to by then (`cd frontend && npm test`), so it is never compared.
//  A Stop whose message ends by asking the user something is not the end (audit imp-3): the job stays with that session
//  and finishes on a later Stop of it. It doesn't wait for ever: Claude Code often ends finished work with an offer
//  ("Want me to also …?"), and a job waiting on that would hold its slots for a day. After `askedWait` with no new
//  word, Aris stops watching and says Claude Code is still waiting in the terminal.
//  `started(job:)` says whether any such session was heard at all (audit team-4): on a Mac without the Claude hooks
//  none ever is, and the job must not wait a day for a Stop that can't come (ArisTeammateSilence).
//

import Foundation

struct ArisTeammateCompletion {
    enum Outcome: Equatable {
        case finished(UUID)
        case closed(UUID)
        /// Its session stopped on a question for the user: the job goes on.
        case asked(UUID)
    }

    private struct Pending {
        let job: UUID
        let cwd: String
        let launchedAt: Date
        /// The session this job belongs to, once one stopped on a question for it.
        var session: String?
        /// When it last stopped on a question.
        var askedAt: Date?
    }

    private struct Start {
        let at: Date
        /// The folder the session started in.
        let folder: String
    }

    private var pending: [Pending] = []
    /// When and where each session started (its SessionStart). Kept even while no job waits: a session's start can
    /// arrive before the app hears that the launch happened.
    private var starts: [String: Start] = [:]
    /// Sessions that already finished a job.
    private var used = Set<String>()
    /// Kept small: a session start is only worth remembering for a while.
    private static let maxRemembered = 200

    mutating func expect(job: UUID, cwd: String, launchedAt: Date) {
        pending.append(Pending(job: job, cwd: Self.folder(cwd), launchedAt: launchedAt, session: nil))
        pending.sort { $0.launchedAt < $1.launchedAt }
    }

    mutating func forget(job: UUID) {
        pending.removeAll { $0.job == job }
    }

    /// Whether a fresh session was heard starting in the job's folder at or after its launch (or one already asked
    /// for it). False for a job nobody waits for.
    func started(job: UUID) -> Bool {
        guard let waiting = pending.first(where: { $0.job == job }) else { return false }
        return waiting.session != nil || starts.values.contains { $0.folder == waiting.cwd && waiting.launchedAt <= $0.at }
    }

    /// Whether the job's session stopped on a question that is still open.
    func asked(job: UUID) -> Bool {
        pending.first { $0.job == job }?.session != nil
    }

    /// When the job's session last stopped on a question (nil: it never did, or the job is over).
    func askedAt(job: UUID) -> Date? {
        pending.first { $0.job == job }?.askedAt
    }

    /// The job this hook event finishes, closes or asks for, if any. `agent` is the event's agent: only Claude counts.
    /// `source`: a SessionStart's source; only "startup" is a new session. `cwd` counts on a SessionStart only.
    /// `asks`: a Stop whose last message ends by asking the user something (`asks(_:)`).
    mutating func observe(_ event: String, session: String, cwd: String, agent: String, source: String? = nil, asks: Bool = false,
                          at: Date) -> Outcome? {
        guard agent == "claude", !used.contains(session) else { return nil }
        switch event {
        case "SessionStart":
            guard source == "startup" else { return nil }
            if starts.count >= Self.maxRemembered { starts = [:] }
            starts[session] = Start(at: at, folder: Self.folder(cwd))
            return nil
        case "Stop", "SessionEnd":
            guard let index = pendingIndex(for: session) else { return nil }
            if event == "Stop", asks {
                pending[index].session = session
                pending[index].askedAt = at
                return .asked(pending[index].job)
            }
            let job = pending.remove(at: index).job
            starts[session] = nil
            if used.count >= Self.maxRemembered { used = [] }
            used.insert(session)
            return event == "Stop" ? .finished(job) : .closed(job)
        default:
            return nil
        }
    }

    /// Whether `session` is a teammate's: it works on a job that waits, or it finished one.
    func isTeammate(session: String) -> Bool { used.contains(session) || pendingIndex(for: session) != nil }

    /// The job `session` works on: the one it already asked for, else the earliest launched job still free in the
    /// folder the session started in.
    private func pendingIndex(for session: String) -> Int? {
        if let mine = pending.firstIndex(where: { $0.session == session }) { return mine }
        guard let start = starts[session] else { return nil }
        return pending.firstIndex { $0.session == nil && $0.cwd == start.folder && $0.launchedAt <= start.at }
    }

    /// Whether Claude Code's last message ends by asking the user something: its last line with words ends in a question
    /// mark (closing quotes, brackets and emphasis marks after it don't hide it).
    static func asks(_ message: String?) -> Bool {
        question(in: message) != nil
    }

    /// That last line, when it is a question (at most `questionLength` characters, cut from the front so the
    /// question mark stays).
    static func question(in message: String?) -> String? {
        guard let line = message?.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) }).last(where: { !$0.isEmpty }) else {
            return nil
        }
        let closing = CharacterSet(charactersIn: "\"'”’)]）】*_`~ ")
        let bare = line.trimmingCharacters(in: closing)
        guard let last = bare.last, last == "?" || last == "？" else { return nil }
        let shown = bare.trimmingCharacters(in: CharacterSet(charactersIn: " \t#*>`-_"))
        guard shown.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
        return shown.count <= questionLength ? shown : "…" + shown.suffix(questionLength)
    }

    static let questionLength = 140

    private static func folder(_ path: String) -> String {
        (path as NSString).standardizingPath
    }
}

/// What to do when a launched Claude Code job hears nothing from its session (audit team-4). The Claude hooks are
/// what tell Aris that a session started and stopped; they are installed outside the app, so a Mac may not have them.
/// The agent says whether they are there when it opens the window (ArisClaudeHookCheck).
enum ArisTeammateSilence: Equatable {
    /// A session was heard starting: keep waiting for its Stop.
    case none
    /// No hooks on this Mac: the job ends now, saying Claude Code is open and that Aris can't tell when it finishes.
    case endUnwatched
    /// Hooks are there but nothing came (Claude Code may be asking in the terminal whether to trust the folder): the
    /// job keeps waiting and its row says where to look.
    case nudge

    /// How long after the launch the first look is taken when the agent found no hooks. Not sooner: the shell must
    /// have read the prompt file before the job's end lets the agent delete it.
    static let unwatchedAfter: TimeInterval = 30
    /// The same when the hooks are there: a session starts within seconds (measured: two), and one that hasn't is
    /// almost always Claude Code asking whether to trust the folder, in a window that is now out of sight.
    static let nudgeAfter: TimeInterval = 45
    /// How long a job waits on a question Claude Code asked before Aris stops watching it (its slots go to the next job).
    static let askedWait: TimeInterval = 600

    /// Whether a job that stopped on a question at `askedAt` has waited long enough: only when no newer question came
    /// (`latest` is when it last asked; nil when the job went on or ended).
    static func askedOut(askedAt: Date, latest: Date?) -> Bool {
        latest == askedAt
    }

    /// `hooks`: what the agent found (nil: an agent that doesn't say, taken as installed).
    static func wait(hooks: Bool?) -> TimeInterval {
        hooks == false ? unwatchedAfter : nudgeAfter
    }

    static func decide(hooks: Bool?, started: Bool) -> ArisTeammateSilence {
        if started { return .none }
        return hooks == false ? .endUnwatched : .nudge
    }

    /// The job's row while it waits on a session that hasn't been heard from.
    static func nudgeStep(korean: Bool) -> String {
        korean ? "Claude Code 소식이 아직 없어요 · Dock이나 다른 창 뒤에 있는 ‘Aris’ 터미널 창을 확인해 주세요"
            : "No word from Claude Code yet · check the terminal window named ‘Aris’ (in the Dock or behind your windows)"
    }
}

/// What Aris says when a Claude Code job's wait ends (or pauses on a question).
enum ArisTeammateWords {
    static func finished(_ message: String?, korean: Bool) -> String {
        message.map { korean ? "Claude Code가 끝냈어요. \($0)" : "Claude Code is done. \($0)" }
            ?? (korean ? "Claude Code가 끝냈어요." : "Claude Code is done.")
    }

    /// `asked`: it had stopped on a question that was never answered.
    static func closed(asked: Bool, korean: Bool) -> String {
        if asked {
            return korean ? "Claude Code가 물어본 것에 답하기 전에 창이 닫혔어요." : "The Claude Code window closed before its question was answered."
        }
        return korean ? "Claude Code 창이 끝나기 전에 닫혔어요." : "The Claude Code window closed before it finished."
    }

    static func lost(korean: Bool) -> String {
        korean ? "Claude Code 작업을 더 지켜볼 수 없어요." : "I lost track of the Claude Code job."
    }

    /// The window is open and working, but this Mac's Claude Code has no hooks to tell Aris when it stops.
    static func unwatched(korean: Bool) -> String {
        korean
            ? "Claude Code를 터미널에 열어서 일을 맡겼어요. 다만 이 Mac의 Claude Code에는 Aris에 소식을 알려 주는 연결(Claude 훅)이 설치돼 있지 않아서, 언제 끝나는지는 제가 알 수 없어요. 터미널 창에서 확인해 주세요."
            : "I opened Claude Code in the terminal and gave it the job. This Mac's Claude Code doesn't have the hooks that report back to Aris, so I can't tell when it finishes. Please check the terminal window."
    }

    static func asks(_ question: String?, korean: Bool) -> String {
        let head = korean ? "Claude Code가 물어봐요. 터미널에서 답해 주세요." : "Claude Code is asking. Please answer in the terminal."
        return question.map { head + " " + $0 } ?? head
    }

    /// Said when a question stayed open past `ArisTeammateSilence.askedWait`: Aris stops watching, Claude Code still waits.
    static func unanswered(_ question: String?, korean: Bool) -> String {
        let head = korean ? "Claude Code가 물어본 뒤 아직 터미널에서 답을 기다리고 있어요. 저는 여기까지만 지켜볼게요."
            : "Claude Code asked something and is still waiting in the terminal. I'll stop watching it here."
        return question.map { head + " " + $0 } ?? head
    }

    /// The job's row while Claude Code waits for the user's answer.
    static func askingStep(korean: Bool) -> String {
        korean ? "Claude Code가 답을 기다려요 · 터미널" : "Claude Code is waiting for your answer · terminal"
    }
}
