//
//  ArisWorkDesk.swift
//  aris-agent
//
//  Where the agent's turn code meets the work memory: a few calls, one line each where they are made.
//  - context(…): at POST /ask, the block a clean turn gets before it starts (ArisWorkRecall), from a cache.
//  - begin(…): at POST /ask, what the agent knows about the turn (whose it is, what came with it, what was offered).
//  - bind(…): a job's runner to its stream (a conversation's runner names its connection itself).
//  - started / saw / sawLine / finished: from the runner, as the brain's process works: each tool call as it is
//    announced, a step that failed, a card that went up, the tokens the brain reported, and how the turn ended.
//  - audited(…): every line for actions.log, for the gate's verdict on a step and the user's answer to its card.
//  - relayed(…): what Aris ran itself for Antigravity.
//  - heard(…): a job's result file.
//  When a turn that used tools ends, its episode is written on this desk's own queue (never the server's or the
//  runner's), the lessons it teaches are saved, and the cache is read again. A turn that used no tool leaves nothing.
//  The model call for an episode's one-line title and the activity log are passed in, so the tests run without
//  The user's files. Foundation only (tested); the agent's own is ArisWorkDesk.live (ArisWorkLive).
//

import Foundation

/// What POST /ask decided about a turn before any brain ran.
struct ArisWorkStart: Equatable, Sendable {
    /// The user's request as it came (an attached file's text may follow their words).
    var request: String
    /// Everything the taint rule reads, but the brain's own taint (known when the turn ends).
    var facts = ArisWorkTurnFacts()
    /// A job's teammate (its id) and what the activity log calls the work ("대화" for a conversation).
    var teammate = ""
    var job = ArisWorkDesk.conversationJob
    /// What was put into the turn's context, and the first step of each way offered.
    var offered: [String] = []
    var firstSteps: [ArisWorkStep] = []
}

/// The tokens a brain's own line reports, when it reports them.
enum ArisWorkTokens {
    enum Reading: Equatable {
        /// This turn's own count (Claude's result line, the API helper's).
        case turn(Int)
        /// A thread's running total and its latest part (Codex).
        case running(total: Int, last: Int?)
    }

    static func read(_ line: String) -> Reading? {
        guard line.contains("\"usage\"") || line.contains("tokenUsage"), let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { return nil }
        let number = { (raw: Any?) in (raw as? NSNumber)?.intValue ?? 0 }
        if object["method"] as? String == "thread/tokenUsage/updated", let usage = (object["params"] as? [String: Any])?["tokenUsage"] as? [String: Any],
           let total = usage["total"] as? [String: Any] {
            return .running(total: number(total["totalTokens"]), last: (usage["last"] as? [String: Any]).map { number($0["totalTokens"]) })
        }
        guard let kind = object["type"] as? String ?? object["kind"] as? String, kind == "result", let usage = object["usage"] as? [String: Any] else { return nil }
        let count = ["input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "in", "out", "cacheRead", "cacheWrite"]
            .reduce(0) { $0 + number(usage[$1]) }
        return count > 0 ? .turn(count) : nil
    }
}

final class ArisWorkDesk: @unchecked Sendable {
    static let conversationJob = "대화"

    /// What the activity log calls a job: its title as the log keeps it, never the conversation's own "대화" (a model
    /// could title a job so, and the turn running beside it would take what the job made as its own: review 8, M1).
    static func taskLabel(_ title: String) -> String {
        let label = ArisActivityBridge.label(title, fallback: "Aris")
        return label == conversationJob ? label + " (작업)" : label
    }
    /// The lines the runner ends a turn with when nobody waits for it any more: a cancelled job, a stop, a dropped
    /// stream (ArisAgentRunner.cancelTask, stop, abandon). The tests hold these to the runner's own source.
    static let cancelLines: Set<String> = ["cancelled", "Stopped.", "연결이 끊겨서 답을 멈췄어요."]
    /// How long what /ask knew about a stream is kept when no turn ever started on it.
    static let startLife: TimeInterval = 26 * 3_600

    /// A turn under way on one runner.
    private struct Turn {
        var start: ArisWorkStart
        var stream: AnyHashable?
        var brain: String
        var began: Date
        /// What /ask knew about this turn's stream when it started (cleared once its episode is written).
        var token: UUID?
        var seen: [ArisWorkSteps.Seen] = []
        var times: [Date] = []
        var taint = ArisWorkTaint.clean
        var tokens: Int?
        /// Codex's running total when this turn began on its runner.
        var totalBefore: Int?
        var stopped = false
        var unavailable = false
        /// The index of the step a card is up for.
        var asked: Int?
    }

    let store: ArisWorkStore
    private let tools: String
    private let home: String
    private let log: URL
    private let clock: @Sendable () -> Date
    private let title: @Sendable (ArisWorkEpisode) -> String?
    private let queue = DispatchQueue(label: "com.lumenjsn.aris.agent.work", qos: .utility)
    private let lock = NSLock()
    private var starts: [AnyHashable: (start: ArisWorkStart, at: Date, token: UUID)] = [:]
    private var bound: [ObjectIdentifier: AnyHashable] = [:]
    private var turns: [ObjectIdentifier: Turn] = [:]
    private var keys: [String: ObjectIdentifier] = [:]
    /// A turn that ended with nothing run yet, which Aris's relay may still add to (by its stream).
    private var paused: [AnyHashable: Turn] = [:]
    private var lastEpisode: [AnyHashable: Int] = [:]
    private var totals: [ObjectIdentifier: Int] = [:]
    private var cache: (lessons: [ArisWorkLesson], episodes: [ArisWorkEpisode], on: Bool) = ([], [], true)
    private var lastKept = Date.distantPast

    /// `log`: the activity log. `title`: one line about an episode from the on-device model (unchecked: ArisWorkTitle
    /// checks it), or nil.
    init(store: ArisWorkStore, tools: String, home: String, log: URL, clock: @escaping @Sendable () -> Date = { Date() },
         title: @escaping @Sendable (ArisWorkEpisode) -> String? = { _ in nil }) {
        self.store = store
        self.tools = tools
        self.home = home
        self.log = log
        self.clock = clock
        self.title = title
    }

    /// At launch (and after the settings page changed something): the cache fills, old episodes are compacted.
    func refresh() { queue.async { [self] in keepAndRefresh(force: true) } }

    /// Waits until everything queued so far has run (tests).
    func drain() { queue.sync {} }

    private func keepAndRefresh(force: Bool = false) {
        let now = clock()
        if force || now.timeIntervalSince(lastKept) > 3_600 {
            store.retain(now: now)
            lastKept = now
        }
        let fresh = (store.lessons(), store.teachingTurns(), store.isOn)
        lock.withLock { cache = fresh }
    }

    // MARK: - Before the turn

    /// The work-memory block for a turn about `request`, and what it holds; nothing unless the turn may have it (the
    /// same turns that get the user's memories: ArisMemoryLearning.mayRecall) and the switch is on. From the cache.
    func context(for request: String, eligible: Bool) -> (block: String?, picked: ArisWorkRecall.Picked) {
        let cached = lock.withLock { cache }
        guard eligible, cached.on else { return (nil, ArisWorkRecall.Picked()) }
        let picked = ArisWorkRecall.pick(lessons: cached.lessons, episodes: cached.episodes, for: request, now: clock())
        let used = picked.lessons.map(\.id)
        if !used.isEmpty { queue.async { [self] in store.markUsed(used) } }
        // Each turn's block carries its own random value (review 8, M2).
        return (ArisWorkRecall.block(picked, nonce: ArisWorkRecall.nonce()), picked)
    }

    func begin(_ start: ArisWorkStart, on stream: AnyHashable) {
        let now = clock()
        lock.withLock {
            starts = starts.filter { now.timeIntervalSince($0.value.at) < Self.startLife }
            starts[stream] = (start, now, UUID())
            paused[stream] = nil
        }
        // What the user undid since counts against the lessons that rested on it.
        queue.async { [self] in syncUndone(now: now) }
    }

    /// A job's runner answers `stream` (a conversation's runner says so itself, by its connection).
    func bind(_ runner: AnyObject, to stream: AnyHashable) {
        lock.withLock { bound[ObjectIdentifier(runner)] = stream }
    }

    // MARK: - From the runner

    /// `runner` starts a turn for the stream it is bound to, or for `owner` (the connection its question came on).
    func started(_ runner: AnyObject, key: String, brain: String, owner: AnyObject?) {
        let id = ObjectIdentifier(runner)
        let now = clock()
        lock.withLock {
            let stream = bound[id] ?? owner.map { AnyHashable(ObjectIdentifier($0)) }
            keys = keys.filter { $0.value != id }
            guard let stream, let start = starts[stream]?.start else { return turns[id] = nil }
            keys[key] = id
            // Antigravity's turn goes on in Aris's relay: the steps so far stay with it.
            if var going = paused.removeValue(forKey: stream) {
                going.brain = brain
                turns[id] = going
                return
            }
            turns[id] = Turn(start: start, stream: stream, brain: brain, began: now, token: starts[stream]?.token, totalBefore: totals[id])
        }
    }

    /// Something the brain's process said, with the driver's taint once it was read.
    func saw(_ event: ArisBrainEvent, taint: ArisTaint, from runner: AnyObject) {
        let id = ObjectIdentifier(runner)
        let now = clock()
        lock.withLock {
            guard var turn = turns[id] else { return }
            turn.taint = max(turn.taint, ArisWorkTaint(taint))
            switch event {
            case .tools(let calls):
                for call in calls {
                    let seen = call.name == "Bash" ? call.command.map { ArisWorkSteps.seen(command: $0, tools: tools, home: home) } ?? [] : [ArisWorkSteps.brainTool(call.name)]
                    for one in seen where turn.seen.count < Self.mostSteps {
                        turn.seen.append(one)
                        turn.times.append(now)
                    }
                }
            case .stepFailed:
                // The step running now: the newest one that hasn't been settled otherwise.
                if let index = turn.seen.lastIndex(where: { $0.step.status == "ok" }) { turn.seen[index].step.status = "failed" }
            case .confirm:
                if let index = turn.seen.indices.last {
                    turn.seen[index].step.gate = "asked"
                    turn.asked = index
                }
            case .abort: turn.stopped = true
            case .unavailable: turn.unavailable = true
            case .send, .status, .delta, .audit, .result, .failure: break
            }
            turns[id] = turn
        }
    }

    static let mostSteps = 40

    /// A line the brain's process wrote: only the tokens it reports are read from it.
    func sawLine(_ line: String, from runner: AnyObject) {
        guard let reading = ArisWorkTokens.read(line) else { return }
        let id = ObjectIdentifier(runner)
        lock.withLock {
            switch reading {
            case .turn(let count):
                guard var turn = turns[id] else { return }
                turn.tokens = (turn.tokens ?? 0) + count
                turns[id] = turn
            case .running(let total, let last):
                totals[id] = total
                guard var turn = turns[id] else { return }
                let before = turn.totalBefore ?? 0
                turn.tokens = total >= before ? total - before : last
                turns[id] = turn
            }
        }
    }

    /// A line for actions.log from `key`: the gate's verdict on a command (its risk), or the user's answer to a card.
    func audited(_ line: String, key: String) {
        guard line.contains("\"risk\"") || line.contains("\"answer\""), let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { return }
        lock.withLock {
            // The runner's own lines by its key; a route's line (a hand-off, a service) for the one turn under way.
            guard let id = keys[key] ?? (turns.count == 1 ? turns.keys.first : nil), var turn = turns[id] else { return }
            if let risk = object["risk"] as? String, let action = object["action"] as? String, action.hasPrefix("shell: ") {
                let verdict = ["auto": "auto", "confirm": "asked", "countdown": "asked", "never": "refused"][risk]
                let steps = ArisWorkSteps.seen(command: String(action.dropFirst("shell: ".count)), tools: tools, home: home).map(\.step)
                for index in turn.seen.indices.reversed() where turn.seen[index].step.gate.isEmpty && steps.contains(where: { $0.sameCall(as: turn.seen[index].step) }) {
                    turn.seen[index].step.gate = verdict ?? ""
                    if verdict == "refused" { turn.seen[index].step.status = "refused" }
                    if verdict == "asked" { turn.asked = index }
                    break
                }
            } else if let answer = object["answer"] as? String, let index = turn.asked, turn.seen.indices.contains(index) {
                let said: String? = answer == "yes" || answer.hasPrefix("yes (") || answer.hasPrefix("yes, ") ? "yes"
                    : answer == "no" || answer.hasPrefix("no (") ? "no" : answer == "unanswered" || answer == "expired" ? "unanswered" : nil
                guard let said else { return }
                turn.seen[index].step.gate = said
                if said != "yes" { turn.seen[index].step.status = "declined" }
                turn.asked = nil
            }
            turns[id] = turn
        }
    }

    /// The runner's turn ended. `answered`: with an answer; `error`: the line the user was shown instead (read only to tell
    /// a cancel or a timeout by Aris's own fixed lines); `handingOff`: another brain takes the question from the start.
    func finished(_ runner: AnyObject, answered: Bool, error: String?, handingOff: Bool, taint: ArisTaint) {
        let id = ObjectIdentifier(runner)
        let now = clock()
        let ended = lock.withLock { () -> Turn? in
            guard var turn = turns.removeValue(forKey: id) else { return nil }
            turn.taint = max(turn.taint, ArisWorkTaint(taint))
            guard !handingOff else { return nil }
            // A job's runner ends with its job: its binding goes (an address can be reused by another object later).
            bound[id] = nil
            if turn.seen.isEmpty {
                // Nothing ran: no episode. Antigravity may have asked Aris to run things, which come next (relayed).
                if answered, turn.brain == ArisBrain.antigravity.rawValue, let stream = turn.stream { paused[stream] = turn }
                return nil
            }
            return turn
        }
        guard let ended else { return }
        let slow = Set(ArisBrain.allCases.flatMap { brain in [true, false].map { ArisBrainFailure.slowLine(brain: brain, korean: $0) } })
        let outcome: ArisWorkOutcome = answered ? .done : error.map(Self.cancelLines.contains) == true ? .cancelled : .failed
        let failure: ArisWorkError = outcome != .failed ? .none : ended.stopped ? .stopped : ended.unavailable ? .brain
            : error.map(slow.contains) == true ? .timeout : .other
        queue.async { [self] in write(ended, outcome: outcome, error: failure, at: now) }
    }

    /// What Aris ran itself for Antigravity's `aris-run` block, on `stream` (how each went isn't known here).
    func relayed(_ commands: [[String]], on stream: AnyHashable) {
        let now = clock()
        lock.withLock {
            guard var turn = paused[stream] else { return }
            for words in commands where !words.isEmpty && turn.seen.count < Self.mostSteps {
                var step = ArisWorkSteps.arisStep(words, home: home, clean: false)
                step.status = "unknown"
                step.gate = "relayed"
                // How it went isn't known, so nothing that only a success keeps clean counts.
                step.clean = ArisWorkSteps.bringsNothingIn(words)
                turn.seen.append(ArisWorkSteps.Seen(step: step, cleanWhenFailed: step.clean))
                turn.times.append(now)
            }
            paused[stream] = turn
        }
    }

    /// The connection `stream` closed: nothing more is kept for it (its address may be another connection's next).
    func closed(_ stream: AnyHashable) {
        lock.withLock {
            starts[stream] = nil
            paused[stream] = nil
            lastEpisode[stream] = nil
            bound = bound.filter { $0.value != stream }
        }
    }

    /// What the desk still holds for `stream` (the tests).
    func held(stream: AnyHashable) -> (starts: Bool, bound: Int, lastEpisode: Bool) {
        lock.withLock { (starts[stream] != nil, bound.values.filter { $0 == stream }.count, lastEpisode[stream] != nil) }
    }

    /// A line sent to the app on `stream`: a job's result file belongs on its episode.
    func heard(_ reply: ArisAgentReply, on stream: AnyHashable) {
        guard case .file(let path) = reply else { return }
        let short = ArisWorkSteps.short(path, home: home)
        guard ArisWorkSafe.arg(.path, short) != nil else { return }
        queue.async { [self] in
            // After the episode's own write, which is queued before this line is heard or just after: both run here in turn.
            queue.asyncAfter(deadline: .now() + 0.5) { [self] in
                if let id = lock.withLock({ lastEpisode[stream] }) { store.setResult(short, episode: id) }
            }
        }
    }

    // MARK: - Writing (on `queue`)

    private func write(_ turn: Turn, outcome: ArisWorkOutcome, error: ArisWorkError, at now: Date) {
        guard store.isOn else { return }
        var steps: [ArisWorkStep] = []
        for (index, seen) in turn.seen.enumerated() {
            var step = ArisWorkSteps.settled(seen)
            let next = index + 1 < turn.times.count ? turn.times[index + 1] : now
            step.ms = max(0, Int(next.timeIntervalSince(turn.times[index]) * 1_000))
            steps.append(step)
        }
        var facts = turn.start.facts
        facts.driver = turn.taint
        let asked = ArisWorkSafe.asked(turn.start.request)
        let done = Self.made(in: log, from: turn.began, to: now, job: turn.start.job, home: home, steps: steps)
        var episode = ArisWorkEpisode(
            at: turn.began, seconds: max(0, now.timeIntervalSince(turn.began)), kind: facts.task ? .job : .turn, asked: asked,
            key: ArisWorkAsk.key(asked), brain: turn.brain, steps: steps, made: done.made, acts: done.acts, outcome: outcome, error: error,
            taint: ArisWorkTaintRule.taint(of: facts, steps: steps), tokens: turn.tokens, offered: turn.start.offered,
            followed: turn.start.offered.isEmpty ? nil : steps.first.map { first in turn.start.firstSteps.contains { $0.tool == first.tool && $0.verb == first.verb } },
            teammate: turn.start.teammate, place: facts.task ? turn.start.job : "", teaches: ArisWorkTaintRule.teaches(facts))
        episode.title = ArisWorkTitle.checked(title(episode), for: episode) ?? ArisWorkTitle.plain(episode)
        guard let id = store.add(episode) else { return }
        episode.id = id
        if let stream = turn.stream {
            lock.withLock {
                // Only while the stream is still the one this turn started on (open, no newer turn on it): a job's
                // result file comes after, on it. What /ask knew about it is no longer needed.
                guard let token = turn.token, starts[stream]?.token == token else { return }
                if turn.start.facts.task { lastEpisode[stream] = episode.id }
                starts[stream] = nil
            }
        }
        // Lessons: what a turn that may teach did, clean or not (the rule again in the store, which marks one that rests
        // on outside text).
        if ArisWorkTaintRule.feedsLessons(episode) {
            for lesson in ArisWorkLessons.learn(from: episode, lessons: store.lessons(expired: true), earlier: store.teachingTurns(), now: now) {
                store.save(lesson)
            }
        }
        keepAndRefresh()
    }

    /// The episodes whose every logged change the user undid since are marked, and their lessons made less sure.
    private func syncUndone(now: Date) {
        guard store.isOn, let undone = Self.undoneActs(in: log), !undone.isEmpty else { return }
        let ids = store.episodes(tainted: true, limit: 300).filter { $0.outcome == .done && !$0.acts.isEmpty && Set($0.acts).isSubset(of: undone) }.map(\.id)
        guard !ids.isEmpty else { return }
        store.markUndone(ids)
        for lesson in ArisWorkLessons.undone(ids, lessons: store.lessons(), now: now) { store.save(lesson) }
        keepAndRefresh()
    }

    // MARK: - The activity log (what a turn made, from its undo records)

    private static func entries(in file: URL) -> [[String: Any]]? {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        guard let data = ArisPrivateFile.read(file) else { return nil }
        return data.split(separator: 0x0A).compactMap { (try? JSONSerialization.jsonObject(with: Data($0))) as? [String: Any] }
    }

    static func undoneActs(in file: URL) -> Set<String>? {
        entries(in: file).map { Set($0.filter { $0["undone"] as? Bool == true }.compactMap { $0["id"] as? String }) }
    }

    /// What the brain's own commands logged for `job` from `from` to `to`: each entry's id, and what its undo record
    /// says was made (a file by its path, an event, a schedule or a to-do by its id). Never the entry's words. Another
    /// conversation can log under the same label in the same seconds (a screen turn on another brain), so an entry is
    /// the turn's only when what it made belongs to the turn's own `steps` (ArisWorkDesk.belongs).
    static func made(in file: URL, from: Date, to: Date, job: String, home: String, steps: [ArisWorkStep]) -> (made: [ArisWorkMade], acts: [String]) {
        let formatter = ISO8601DateFormatter()
        let start = Date(timeIntervalSince1970: from.timeIntervalSince1970.rounded(.down))
        var made: [ArisWorkMade] = [], acts: [String] = []
        for entry in entries(in: file) ?? [] {
            guard let date = (entry["date"] as? String).flatMap(formatter.date(from:)), date >= start, date <= to, entry["job"] as? String == job,
                  entry["worker"] as? String != ArisWhyActivity.appWorker, let id = entry["id"] as? String, UUID(uuidString: id) != nil,
                  let undo = entry["undo"] as? [String: Any] else { continue }
            let path = { (raw: Any?) -> String? in (raw as? String).map { ArisWorkSteps.short($0, home: home) }.flatMap { ArisWorkSafe.arg(.path, $0)?.value } }
            let item = { (raw: Any?) -> String? in (raw as? String).flatMap { ArisWorkSafe.id($0)?.value } }
            var mine: [ArisWorkMade] = []
            if let files = (undo["trashMade"] as? [String: Any])?["paths"] as? [Any] {
                mine = files.compactMap(path).map { ArisWorkMade(kind: "file", value: $0) }
            } else if let moved = undo["moveBack"] as? [String: Any], let now = path(moved["from"]) {
                mine = [ArisWorkMade(kind: "moved", value: now)]
            } else if let id = item((undo["deleteEvent"] as? [String: Any])?["id"]) {
                mine = [ArisWorkMade(kind: "event", value: id)]
            } else if let id = item((undo["removeSchedule"] as? [String: Any])?["id"]) {
                mine = [ArisWorkMade(kind: "schedule", value: id)]
            } else if let id = item((undo["removeTodo"] as? [String: Any])?["id"]) {
                mine = [ArisWorkMade(kind: "todo", value: id)]
            }
            mine = mine.filter { belongs($0, to: steps) }
            guard !mine.isEmpty else { continue }
            acts.append(id)
            made += mine
        }
        return (Array(made.prefix(12)), Array(acts.prefix(24)))
    }

    /// Whether something an activity entry made belongs to a turn that ran `steps`: a file or a moved one is the path
    /// a step named, inside a folder a step named, or beside a file a step named (a merge's or a conversion's result);
    /// an event, a schedule or a to-do needs a step of its own command.
    static func belongs(_ made: ArisWorkMade, to steps: [ArisWorkStep]) -> Bool {
        let ran = steps.filter { $0.worked || $0.status == "unknown" }
        switch made.kind {
        case "file", "moved":
            let folder = (made.value as NSString).deletingLastPathComponent
            return ran.flatMap(\.args).contains { arg in
                arg.kind == .path && (arg.value == made.value || made.value.hasPrefix(arg.value + "/") || (arg.value as NSString).deletingLastPathComponent == folder)
            }
        case "event": return ran.contains { $0.verb.hasPrefix("event") || $0.verb == "calendar" }
        case "schedule": return ran.contains { $0.verb.hasPrefix("schedule") || $0.verb == "remind" }
        case "todo": return ran.contains { $0.verb.hasPrefix("todo") || $0.verb == "remind" }
        default: return false
        }
    }
}

extension ArisWorkTaint {
    init(_ taint: ArisTaint) {
        switch taint {
        case .none: self = .clean
        case .screenSeen: self = .screen
        case .outsideText: self = .outside
        }
    }
}
