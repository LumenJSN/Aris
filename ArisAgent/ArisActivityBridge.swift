//
//  ArisActivityBridge.swift
//  aris-agent
//
//  What the app asks of the activity log through the agent (the app is sandboxed and can't read ~/.config/aris):
//  POST /activity lists it, POST /undo undoes one entry. Both run aris-tools, which does the work and the path checks;
//  this only validates what it is asked and turns the result into an HTTP reply. Also the job and worker names the
//  agent gives each AI process (ARIS_JOB, ARIS_WORKER), which aris-tools writes into the log.
//

import Foundation

enum ArisActivityBridge {
    /// aris-tools' exit status when the undo needs the user's yes (an event it created would be deleted).
    static let needsConfirmStatus: Int32 = 3
    /// How long an undo may take: macOS may be asking the user whether aris-agent may touch a folder (Desktop, Documents,
    /// Downloads) meanwhile, and the app says so after a few seconds (QA BUG-17). The app waits a little longer.
    static let undoTimeout: TimeInterval = 60
    /// The 500's reason when aris-tools didn't finish in time (the app says it in words: ArisUndoWords).
    static let noAnswer = "aris-tools didn't answer"
    /// Set for `aris-tools activity log` (ArisActivity.localLogKey): only the agent sets it, for the app.
    static let localLogKey = "ARIS_LOCAL_LOG"
    /// The notch app's own changes that go in the log (QA BUG-18).
    static let localKinds: Set<String> = ["todo-add", "todo-done", "todo-due", "timer-set", "timer-cancel", "volume", "arrange"]

    /// `aris-tools activity log --kind <kind> [--id <id>] [--level <n>] <summary>` for a change the app made itself;
    /// nil for any other kind, an empty or overlong summary, a to-do without its id, or a level outside 0–100. A to-do
    /// put off until tomorrow (`todo-due`) also needs the date it had (`due`, seconds since 1970; `timed`: with a time).
    static func localLogArguments(kind: String, summary: String, id: String?, level: Int?, due: Double? = nil, timed: Bool = false) -> [String]? {
        let line = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard localKinds.contains(kind), !line.isEmpty, line.count <= 200, !line.hasPrefix("-"),
              !line.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        var arguments = ["activity", "log", "--kind", kind]
        if kind.hasPrefix("todo-") {
            guard let id, !id.isEmpty, id.count <= 200, !id.hasPrefix("-"), !id.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
            arguments += ["--id", id]
        }
        if kind == "todo-due" {
            guard let due, due.isFinite, due > 0 else { return nil }
            arguments += ["--due", String(Int(due)), "--timed", timed ? "1" : "0"]
        }
        if let level {
            guard (0...100).contains(level) else { return nil }
            if kind == "volume" { arguments += ["--level", String(level)] }
        }
        return arguments + [line]
    }

    /// The protected folder undoing entry `id` (or, with none, the latest change) touches, read from the log alone.
    static func folder(ofEntry id: String?, file: URL = defaultLog,
                       home: String = FileManager.default.homeDirectoryForCurrentUser.path, now: Date = Date()) -> String? {
        let all = objects(file)
        let object = id.map { id in all.first { ($0["id"] as? String)?.lowercased() == id.lowercased() } } ?? latestObject(all, now: now)
        return ArisFolderAccess.folder(ofUndo: object?["undo"] as? [String: Any], home: home)
    }

    /// Whether undoing entry `id` (or, with none, the latest change, as a bare `undo` picks it) reopens or removes a
    /// to-do, read from the log alone: only such an undo needs the agent's to-do grant (security review 3, L4).
    static func undoWritesTodo(ofEntry id: String?, file: URL = defaultLog, now: Date = Date()) -> Bool {
        let all = objects(file)
        let object = id.map { id in all.first { ($0["id"] as? String)?.lowercased() == id.lowercased() } } ?? latestObject(all, now: now)
        guard let undo = object?["undo"] as? [String: Any] else { return false }
        return undo["removeTodo"] != nil || undo["reopenTodo"] != nil || undo["restoreTodoDue"] != nil
    }

    /// The arguments for `aris-tools undo`; nil when `id` isn't a UUID (it is never passed on as is), or when a yes
    /// (`confirmed`) comes without the id of the entry it was given for.
    static func undoArguments(id: String?, confirmed: Bool) -> [String]? {
        if confirmed && id == nil { return nil }
        var arguments = ["undo"]
        if let id {
            guard let uuid = UUID(uuidString: id) else { return nil }
            arguments += ["--id", uuid.uuidString]
        }
        if confirmed { arguments.append("--confirmed") }
        return arguments
    }

    /// ARIS_TEAMMATE for a teammate's task: its id when it is one (ArisTeammate.isValidId), else nothing.
    /// Who a job's log rows are filed under (ARIS_WORKER): a teammate by its name, a helper by the name the app gave it
    /// ("도우미 2", N14), anything else by its brain.
    static func worker(teammate: String?, helper: String?, brain: String) -> String {
        teammate ?? helper ?? brain
    }

    /// The helper name a job's request carries, from the app only: one short plain line, else nil.
    static func helperLabel(_ raw: Any?) -> String? {
        guard let text = raw as? String, !text.isEmpty, text.count <= 20,
              !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0) || $0 == "<" || $0 == ">" })
        else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func teammateEnvironment(_ id: String?) -> [String: String] {
        guard let id, ArisTeammate.isValidId(id) else { return [:] }
        return ["ARIS_TEAMMATE": id]
    }

    static func activityArguments(today: Bool) -> [String] {
        ["activity", "--json"] + (today ? ["--today"] : [])
    }

    /// 200 with what was undone, 409 when it needs a yes first (the body says which entry: "id" and "summary", which
    /// the yes must repeat), else 500 with the reason.
    static func undoReply(status: Int32, out: String, err: String) -> (code: Int, body: String) {
        func json(_ fields: [String: String]) -> String {
            let cut = fields.mapValues { String($0.prefix(300)) }
            return String(decoding: (try? JSONSerialization.data(withJSONObject: cut, options: [.sortedKeys])) ?? Data("{}".utf8), as: UTF8.self)
        }
        let said = err.trimmingCharacters(in: .whitespacesAndNewlines)
        switch status {
        case 0: return (200, json(["summary": out.trimmingCharacters(in: .whitespacesAndNewlines)]))
        case needsConfirmStatus:
            let shown = (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [String: Any] ?? [:]
            // What the yes is for: deleting an event, or bringing a removed schedule back.
            let kind = shown["kind"] as? String == "restoreSchedule" ? "restoreSchedule" : "deleteEvent"
            return (409, json(["confirm": said, "id": shown["id"] as? String ?? "", "summary": shown["summary"] as? String ?? "", "kind": kind]))
        default: return (500, json(["error": said.isEmpty ? "couldn't undo" : said]))
        }
    }

    /// What the log says about one entry: its summary, and whether undoing it deletes a calendar event or brings a
    /// removed schedule back.
    struct Entry {
        let summary: String
        let deletesEvent: Bool
        let revivesSchedule: Bool
    }

    /// The log's entries as JSON objects, read only from the user's own private file (never through a link). Read-only.
    private static func objects(_ file: URL) -> [[String: Any]] {
        guard let data = ArisPrivateFile.read(file) else { return [] }
        return data.split(separator: 0x0A).compactMap { (try? JSONSerialization.jsonObject(with: Data($0))) as? [String: Any] }
    }

    private static func describe(_ object: [String: Any]) -> Entry {
        let undo = object["undo"] as? [String: Any]
        return Entry(summary: String((object["summary"] as? String ?? "").prefix(200)), deletesEvent: undo?["deleteEvent"] != nil,
                     revivesSchedule: undo?["restoreSchedule"] != nil)
    }

    /// Entry `id`; nil when unknown.
    static func entry(id: String, file: URL = defaultLog) -> Entry? {
        objects(file).first { ($0["id"] as? String)?.lowercased() == id.lowercased() }.map(describe)
    }

    /// What a bare `undo` would undo: the latest change from the last day that isn't undone, when it has an undo (as
    /// ArisActivity.undo picks it: never an older entry, QA BUG-18). Nil when none, or when the latest can't be undone.
    static func latestUndoable(file: URL = defaultLog, now: Date = Date()) -> Entry? {
        guard let latest = latestObject(objects(file), now: now), latest["undo"] is [String: Any] else { return nil }
        return describe(latest)
    }

    /// The newest entry from the last day that isn't undone.
    private static func latestObject(_ all: [[String: Any]], now: Date) -> [String: Any]? {
        let formatter = ISO8601DateFormatter()
        let since = now.addingTimeInterval(-24 * 3600)
        let candidates = all.compactMap { object -> (Date, [String: Any])? in
            guard object["undone"] as? Bool != true, let date = (object["date"] as? String).flatMap(formatter.date(from:)), date >= since else { return nil }
            return (date, object)
        }
        return candidates.max { $0.0 < $1.0 }?.1
    }

    /// The summary the log keeps for entry `id`; nil when unknown.
    static func summary(ofEntry id: String, file: URL = defaultLog) -> String? {
        entry(id: id, file: file)?.summary
    }

    static var defaultLog: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/aris/aris/activity.jsonl")
    }

    /// A job or worker name for the environment: one short line, `fallback` when nothing is left.
    static func label(_ text: String, fallback: String) -> String {
        let line = text.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : String($0) }.joined()
            .trimmingCharacters(in: .whitespaces)
        return line.isEmpty ? fallback : String(line.prefix(80))
    }

    /// Collects a pipe's output as it arrives, so a child that writes more than the pipe holds never blocks.
    private final class Drain: @unchecked Sendable {
        private let lock = NSLock()
        private let ended = DispatchGroup()
        private var data = Data()
        private var finished = false
        private static let limit = 4_000_000

        func attach(to pipe: Pipe) {
            ended.enter()
            pipe.fileHandleForReading.readabilityHandler = { [self] handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    return end()
                }
                lock.withLock { if data.count < Self.limit { data.append(chunk) } }
            }
        }

        private func end() {
            let first = lock.withLock { () -> Bool in defer { finished = true }; return !finished }
            if first { ended.leave() }
        }

        /// Everything the child wrote: waits for the end of the stream, so no last chunk is lost.
        func finish(_ pipe: Pipe) -> String {
            if ended.wait(timeout: .now() + 2) == .timedOut {
                // A grandchild still holds the pipe open: stop reading (never block on it) and keep what arrived.
                pipe.fileHandleForReading.readabilityHandler = nil
                try? pipe.fileHandleForReading.close()
            }
            return lock.withLock { String(decoding: data, as: UTF8.self) }
        }
    }

    /// Runs aris-tools and waits (at most `timeout`); nil when it couldn't start or didn't finish. Output is read while
    /// it runs, so a long answer (a big activity list) can't fill the pipe and stall it.
    static func run(tools: String, arguments: [String], environment: [String: String], timeout: TimeInterval = 20)
        -> (status: Int32, out: String, err: String)? {
        let process = ArisExactProcess()
        let output = Pipe(), errors = Pipe()
        let outDrain = Drain(), errDrain = Drain()
        process.executableURL = URL(fileURLWithPath: ArisAppBundle.executed(tools))
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = output
        process.standardError = errors
        outDrain.attach(to: output)
        errDrain.attach(to: errors)
        guard (try? ArisChildren.run(process)) != nil else {
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            return nil
        }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning {
            ArisProcessEnd.end(process)
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            return nil
        }
        return (process.terminationStatus, outDrain.finish(output), errDrain.finish(errors))
    }
}
