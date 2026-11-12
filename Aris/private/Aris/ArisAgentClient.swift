//
//  ArisAgentClient.swift
//  Aris
//
//  Sends Aris's questions to aris-agent, the login agent that runs claude, codex or agy
//  (installed by install-aris-agent.sh). Loopback only, with the hook token.
//

import AppKit
import Foundation

enum ArisAgentClient {
    private static let url = URL(string: "http://127.0.0.1:23351/ask")!
    private static let confirmURL = URL(string: "http://127.0.0.1:23351/confirm")!
    private static let warmURL = URL(string: "http://127.0.0.1:23351/warm")!
    private static let openURL = URL(string: "http://127.0.0.1:23351/open")!
    private static let logURL = URL(string: "http://127.0.0.1:23351/log")!
    private static let arrangeURL = URL(string: "http://127.0.0.1:23351/arrange")!
    /// Opening up to nine windows takes a few seconds; the agent gives up after 20 a command.
    private static let arrangeTimeout: TimeInterval = 45

    private static let insertURL = URL(string: "http://127.0.0.1:23351/insert")!
    private static let insertTimeout: TimeInterval = 5

    /// `count` new windows of `app` in a grid, by aris-agent. Nil when it worked, else what went wrong.
    static func arrange(app: String, count: Int) async -> String? {
        await post(arrangeURL, ["app": app, "count": count], timeout: arrangeTimeout)
    }

    private static let pasteURL = URL(string: "http://127.0.0.1:23351/paste")!

    /// ⌘V for what's on the clipboard now, pressed by aris-agent. Nil when it was, else why not.
    static func pressPaste() async -> String? {
        await post(pasteURL, [:], timeout: insertTimeout)
    }

    /// Dictated words typed where the cursor is, by aris-agent. Nil when they were, else why not.
    static func insert(_ text: String) async -> String? {
        await post(insertURL, ["text": text], timeout: insertTimeout)
    }

    private static let todosURL = URL(string: "http://127.0.0.1:23351/todos")!

    struct Todos {
        let todos: [ArisTodo]
        let due: [ArisDue]
        /// What "<…> 다 했어" ticked off, if anything.
        let finished: String?
    }

    /// The to-do list after `op` (list, add, toggle, remove, hide, finish); nil when the agent didn't answer.
    static func todos(_ op: String, text: String? = nil, id: String? = nil) async -> Todos? {
        guard let token = ClaudeHookToken.load() else { return nil }
        var request = URLRequest(url: todosURL, timeoutInterval: 25)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
        var body: [String: Any] = ["op": op]
        if let text { body["text"] = text }
        if let id { body["id"] = id }
        request.httpBody = try? JSONSerialization.data(withJSONObject: identified(body))
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        struct Reply: Decodable { let todos: [ArisTodo]; let due: [ArisDue]; let finished: String? }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let reply = try? decoder.decode(Reply.self, from: data) else { return nil }
        return Todos(todos: reply.todos, due: reply.due, finished: reply.finished)
    }

    private static let briefURL = URL(string: "http://127.0.0.1:23351/brief")!

    /// The morning brief's facts (weather, Canvas due, unread announcements); nil when the agent couldn't get them.
    static func brief() async -> [String: Any]? {
        guard let token = ClaudeHookToken.load() else { return nil }
        var request = URLRequest(url: briefURL, timeoutInterval: 25)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
        request.httpBody = try? JSONSerialization.data(withJSONObject: identified([:]))
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static let usageURL = URL(string: "http://127.0.0.1:23351/usage")!

    /// Every AI's plan limits (aris-agent reads them the way CodexBar does); nil when it can't be asked or doesn't
    /// answer within ArisUsagePatience.ask (the agent itself answers within ArisUsagePatience.report).
    static func usage() async -> ArisUsageReport? {
        guard let token = ClaudeHookToken.load() else { return nil }
        var request = URLRequest(url: usageURL, timeoutInterval: ArisUsagePatience.ask)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
        request.httpBody = Data("{}".utf8)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return ArisUsageReport.decode(data)
    }

    struct Look {
        let context: String
        let selected: Bool
        let editable: Bool
        /// The agent's line for when the front window's words didn't come; left out when the app's own picture goes along.
        var unread: String? = nil
        /// Its line for when a selection couldn't be read (aris-agent has no Accessibility).
        var unselected: String? = nil
        /// Which of its own permissions aris-agent did without: "accessibility", "screen".
        var needs: [String] = []
    }
    private static let lookURL = URL(string: "http://127.0.0.1:23351/look")!
    /// Reading a window's text (Vision) takes a second or two.
    private static let lookTimeout: TimeInterval = 10

    /// What "이거" points at, read by aris-agent; nil when it couldn't look. `front`: the app he was in when he asked
    /// (ArisUserApp; nil: the helper goes by the window order).
    static func look(front: Int32? = nil) async -> Look? {
        guard let token = ClaudeHookToken.load() else { return nil }
        // The app captures before the helper does, so macOS's question about the screen names Aris.
        await ArisAppCaptureFirst.ensure()
        var request = URLRequest(url: lookURL, timeoutInterval: lookTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
        request.httpBody = try? JSONSerialization.data(withJSONObject: identified(front.map { ["front": Int($0)] } ?? [:]))
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let context = body["context"] as? String else { return nil }
        let line = { (key: String) in (body[key] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        return Look(context: context, selected: body["selected"] as? Bool ?? false, editable: body["editable"] as? Bool ?? false,
                    unread: line("unread"), unselected: line("unselected"), needs: body["needs"] as? [String] ?? [])
    }

    /// A request to aris-agent that answers {} or {"error": "..."}: nil when it worked, else what went wrong.
    private static func post(_ url: URL, _ body: [String: Any], timeout: TimeInterval) async -> String? {
        guard let token = ClaudeHookToken.load() else { return Self.notSetUp }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
        request.httpBody = try? JSONSerialization.data(withJSONObject: identified(body))
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if (response as? HTTPURLResponse)?.statusCode == 200 { return nil }
            let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            return body?["error"] as? String ?? Self.refused
        } catch {
            return Self.failure(describing: error)
        }
    }

    // MARK: - What the user reads when the agent can't be reached (never a script name)

    static let notSetUp = ArisAgentCopy.notSetUp
    static let notRunning = ArisAgentCopy.notRunning
    static let notAnswering = ArisAgentCopy.notAnswering
    static let refused = ArisAgentCopy.refused

    static func failure(describing error: Error) -> String {
        if let error = error as? URLError {
            switch error.code {
            case .cannotConnectToHost, .networkConnectionLost: return notRunning
            case .timedOut: return notAnswering
            default: break
            }
        }
        return ArisAgentCopy.errorPrefix + error.localizedDescription
    }

    /// False only when nothing listens on the agent's port (the connection is refused): the turn then fails in a
    /// moment with a clear line. Anything else, a slow answer past `timeout` included, lets the turn go ahead and
    /// meet the stream's own limits.
    static func reachable(timeout: TimeInterval = 1.5) async -> Bool {
        guard let token = ClaudeHookToken.load() else { return false }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:23351/health")!, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
        request.httpBody = Data("{}".utf8)
        do {
            _ = try await URLSession.shared.data(for: request)
            return true
        } catch let error as URLError {
            return !Self.refusedCodes.contains(error.code)
        } catch {
            return true
        }
    }

    /// Who answers on the helper's port now: nothing, or a process (which one, when its /health says so).
    static func helperSeen(timeout: TimeInterval = 1.5) async -> ArisHelperSeen {
        guard let token = ClaudeHookToken.load() else { return .refused }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:23351/health")!, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
        request.httpBody = Data("{}".utf8)
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return .answered(ArisHelperIdentity(json: data))
        } catch let error as URLError {
            return Self.refusedCodes.contains(error.code) ? .refused : .answered(nil)
        } catch {
            return .answered(nil)
        }
    }

    /// As `reachable`, but a token that won't load is told apart from a refused connection (ArisAgentMonitor never
    /// restarts the agent for a missing token).
    static func probe(timeout: TimeInterval = 1.5) async -> ArisAgentProbe {
        guard ClaudeHookToken.load() != nil else { return .noToken }
        return ArisAgentProbe.from(hasToken: true, refused: !(await reachable(timeout: timeout)))
    }

    /// Nothing is listening (not a slow or odd answer).
    static let refusedCodes: Set<URLError.Code> = [.cannotConnectToHost, .cannotFindHost, .networkConnectionLost]

    /// One turn's numbers (ArisTurnStats), for turns.jsonl. Fire and forget.
    static func log(_ turn: [String: Any]) {
        guard let token = ClaudeHookToken.load() else { return }
        var request = URLRequest(url: logURL, timeoutInterval: 3)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["turn": turn])
        URLSession.shared.dataTask(with: request).resume()
    }

    /// Opens a saved task result again (the agent opens only files in its result folders).
    static func open(_ path: String) async -> Bool {
        guard let token = ClaudeHookToken.load() else { return false }
        var request = URLRequest(url: openURL, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["path": path])
        let response = try? await URLSession.shared.data(for: request).1
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    /// The user started talking: have the agent start `brain` now, so it's ready when the question comes.
    static func warm(_ brain: ArisBrain) {
        guard let token = ClaudeHookToken.load() else { return }
        var request = URLRequest(url: warmURL, timeoutInterval: 3)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["brain": brain.rawValue])
        URLSession.shared.dataTask(with: request).resume()
    }
    /// A little longer than the agent's own limits, so its error message arrives first.
    private static let timeout: TimeInterval = 130
    /// A background job's stream: it may go quiet for a day while a question is parked (the agent sends a blank
    /// line every few minutes), so it may be quiet 26 h and last 48 h (a day parked plus the work around it).
    static let taskSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = ArisParkedCard.streamTimeout
        configuration.timeoutIntervalForResource = ArisParkedCard.streamLifetime
        return URLSession(configuration: configuration)
    }()

    /// This app's process start time, sent with its pid so the agent can tell it apart from a later process that
    /// reuses the pid.
    static let started = ArisProcessStart.of(pid: ProcessInfo.processInfo.processIdentifier)

    /// `body` with this app's pid and start time: the agent answers /cancel, /permissions, /activity, /undo, /inbox and
    /// /confirm only for the Aris app itself (ArisPeer).
    static func identified(_ body: [String: Any]) -> [String: Any] {
        var body = body
        body["pid"] = Int(ProcessInfo.processInfo.processIdentifier)
        if let started { body["started"] = started }
        return body
    }

    /// `context`: the moment (time, front app, music, calendar, recent turns). `tier`: how much the request asks,
    /// which picks each brain's model. What the AI is doing, pieces of its answer and questions for the user come
    /// as they happen; the last reply is the answer or what went wrong.
    /// `task`: long work in the background, in its own AI process (`title` names the file a long answer is saved in).
    /// `browser`: the task takes several steps on websites, so the AI hands it to Aside.
    /// `screen`: what "이거" points at (look()); the agent then asks Codex only and treats it as outside text.
    /// `untrusted`: `text` was written by the model (a dispatched job). `request`: the user's original utterance, for policy.
    /// `fresh`: a new conversation; the agent starts the AI on a new thread instead of carrying on the last one.
    /// `job`: a background job's id, which `cancel(job:)` names.
    /// `images`: the turn's screenshot or circled shots (plan D3), with `focus` saying what "이거" most likely means.
    /// They live in memory only and are taken out of the box when the body is written, so nothing holds them while
    /// the answer streams.
    static func ask(_ text: String, context: String, tier: ArisTier, brain: ArisBrain, task: String? = nil, job: UUID? = nil,
                    browser: Bool = false, screen: String? = nil, fresh: Bool = false,
                    untrusted: Bool = false, request: String? = nil, screenConversation: Bool = false, outsideConversation: Bool = false,
                    handsFree: Bool = false, images: ArisOutgoingImages? = nil, focus: ArisReferenceFocus? = nil,
                    teammate: String? = nil, helper: String? = nil, noActions: Bool = false) -> AsyncStream<ArisAgentReply> {
        let provenance = ArisProvenance(untrusted: untrusted, screenConversation: screenConversation, outsideConversation: outsideConversation,
                                        handsFree: handsFree, noActions: noActions)
        return AsyncStream { continuation in
            let work = Task {
                // A turn may have the helper read the screen: the app's own capture comes first (ArisAppCaptureFirst).
                await ArisAppCaptureFirst.ensure()
                let reply = await stream(text, context: context, tier: tier, brain: brain, task: task, job: job, browser: browser, screen: screen, fresh: fresh,
                                         provenance: provenance, userRequest: request, images: images, focus: focus, teammate: teammate,
                                         helper: helper) { continuation.yield($0) }
                continuation.yield(await plain(reply))
                continuation.finish()
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    /// A failure that blames an AI nobody picked (the preference's default, on a Mac with no AI set up) says instead
    /// that no AI is ready here (ArisBrainChoice.failureLine). Anything else is passed on as it came.
    private static func plain(_ reply: ArisAgentReply) async -> ArisAgentReply {
        guard case .failure(let line) = reply else { return reply }
        let (stored, ready) = await MainActor.run { (ArisBrainSetup.stored, ArisBrainSetup.shared.ready) }
        return .failure(ArisBrainChoice.failureLine(line, stored: stored, ready: ready))
    }

    /// The user's yes or no to a `.confirm`: delivered, refused (403), or gone (nobody waits for it any more).
    /// `shown`: the card as it was shown: a yes counts only when its details are the card the agent made.
    @discardableResult
    /// `unanswered`: the card closed at its limit with no answer from the user (the agent tells that from their no).
    static func confirm(_ id: String, allow: Bool, shown: ArisConfirmation? = nil, unanswered: Bool = false) async -> ArisConfirmResult {
        guard let token = ClaudeHookToken.load() else { return .gone }
        var request = URLRequest(url: confirmURL, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
        // This app's pid and start time: every card is answered only by the app itself (ArisPeer).
        var body: [String: Any] = ["id": id, "allow": allow, "pid": Int(ProcessInfo.processInfo.processIdentifier)]
        if !allow, unanswered { body["unanswered"] = true }
        if let started { body["started"] = started }
        if let shown {
            body["detail"] = shown.detail
            if let full = shown.full { body["full"] = full }
        }
        // The owner's ②A: what they changed on the card and the card's text as finally shown, with a yes only.
        if let edited = ArisCardEditLedger.take(id), allow {
            body["edits"] = edited.edits
            body["shown"] = edited.shown
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let response = try? await URLSession.shared.data(for: request).1
        return ArisConfirmResult.from(status: (response as? HTTPURLResponse)?.statusCode)
    }

    /// Passes on everything before the last reply, and returns the last one.
    private static func stream(_ text: String, context: String, tier: ArisTier, brain: ArisBrain, task: String?, job: UUID? = nil, browser: Bool,
                               screen: String?, fresh: Bool, provenance: ArisProvenance, userRequest: String?,
                               images: ArisOutgoingImages? = nil, focus: ArisReferenceFocus? = nil, teammate: String? = nil,
                               helper: String? = nil, progress: (ArisAgentReply) -> Void) async -> ArisAgentReply {
        guard let token = ClaudeHookToken.load() else { return .failure(notSetUp) }
        // The helper as it is just before the question: asked again if the stream ends with no last line, to tell a
        // helper that went away from an AI that did not answer (ArisHelperGone).
        let helperBefore = await helperSeen()
        guard helperBefore.answers else { return .failure(notRunning) }
        var request = URLRequest(url: url, timeoutInterval: task == nil ? timeout : ArisParkedCard.streamTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
        var body: [String: Any] = ["text": text, "context": context, "tier": tier.rawValue, "brain": brain.rawValue,
                                   "task": task != nil, "title": task ?? "", "browser": browser, "fresh": fresh]
        if let screen { body["screen"] = screen }
        body["computerEngine"] = ArisComputerEngine.named(UserDefaults.standard.string(forKey: ArisComputerEngine.preferenceKey)).rawValue
        // A teammate's task: the activity log names it (ARIS_TEAMMATE), so its rows show its face.
        if let teammate { body["teammate"] = teammate }
        // A helper's job: the log names it as the user sees it ("도우미 2"), not by its brain (N14).
        if let helper { body["helper"] = helper }
        // The shelf's files, for `--shelf`: the agent keeps them for aris-tools, never for a brain to read (ArisShelfFiles).
        body["shelf"] = await MainActor.run { ShelfStateViewModel.shared.items.compactMap { $0.fileURL?.path } }
        // The app in front as the user asked (as the context names it): `--finder` acts only when that was Finder.
        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier { body["frontApp"] = front }
        // Where it comes from (ArisProvenance): a model-written job (untrusted: outside text, policy against `request`, the
        // user's own words), a conversation that saw the screen or took in outside text, a turn heard hands-free.
        for (key, value) in provenance.fields { body[key] = value }
        if let userRequest { body["request"] = userRequest }
        if let sending = images?.take(), !sending.isEmpty {
            body["images"] = sending.map(\.json)
            if let focus { body["focus"] = focus.rawValue }
        }
        // This app's process, on every request: a turn vouches for a Claude Code launch only when the app itself asked
        // (ArisPeer), and the agent ends a task whose stream closed only when that process is gone.
        body["pid"] = Int(ProcessInfo.processInfo.processIdentifier)
        if let started { body["started"] = started }
        // A task names its job (for POST /cancel).
        if task != nil, let job { body["job"] = job.uuidString }
        // A conversation's turn: this app answers a routine's steps offered back to it (ArisRoutineLocalStep).
        if task == nil { body["localSteps"] = true }
        // A conversation's turn: whether the list and calendar unnamed to-dos and events go into are his own (review 9, L2).
        if task == nil { body["ownPlaces"] = await ArisOwnPlacesLive.current() }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        body = [:] // the base64 copies go; only the request's own body remains while it's sent
        // Whether the stream delivered anything before failing: a drop mid-way means the job ran and is gone.
        var started = false
        do {
            let (bytes, response) = try await (task == nil ? URLSession.shared : taskSession).bytes(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode
            guard status == 200 else { return .failure(status == 413 ? ArisAgentCopy.tooLong() : refused) }
            for try await line in bytes.lines {
                // The button this turn's failure earned, sent just before its last line (a conversation's only).
                if task == nil, let fix = ArisFix.parse(line: line) { await ArisFixModel.arrived(fix) }
                // A step of the routine this turn runs, which the app may do by itself: done and answered before the next line.
                if task == nil, let step = ArisRoutineLocalStep.parse(line: line) { await answerRoutineStep(step) }
                guard let reply = ArisAgentReply.parse(line) else { continue }
                started = true
                if reply.isLast { return reply }
                progress(reply)
            }
            // No last line. A helper that was killed closes the stream cleanly: that is the helper's failure (its line,
            // its restart, the question asked again: ArisHelperWatch), never "<AI> didn't answer" (final VM run).
            if ArisHelperGone.wentAway(before: helperBefore, after: await helperSeen()) {
                if let task, let line = ArisJobLoss.line(title: task, code: .networkConnectionLost, started: started) { return .failure(line) }
                return .failure(notRunning)
            }
            return .failure(ArisAgentCopy.noAnswer(brain.title(english: ArisUIWords.english)))
        } catch is CancellationError {
            return .failure(ArisAgentCopy.stopped)
        } catch let error as URLError {
            // A task's loss is told apart by the error's code: not running, not answering, or dropped mid-way.
            if let task, let line = ArisJobLoss.line(title: task, code: error.code, started: started) { return .failure(line) }
            return .failure(failure(describing: error))
        } catch {
            return .failure(failure(describing: error))
        }
    }
}

/// A turn's images on their way into one /ask body: taken out once, so the caller and the answer stream don't keep
/// the image bytes for the rest of the turn.
final class ArisOutgoingImages: @unchecked Sendable {
    private let lock = NSLock()
    private var images: [ArisTurnImage]

    init(_ images: [ArisTurnImage]) {
        self.images = images
    }

    func take() -> [ArisTurnImage] {
        lock.withLock {
            defer { images = [] }
            return images
        }
    }
}
