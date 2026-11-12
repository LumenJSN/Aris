//
//  ArisActivity.swift
//  aris-tools
//
//  The activity log ("한 일"): what Aris did on the Mac (a file moved or trashed, an event added), one JSON line each in
//  ~/.config/aris/aris/activity.jsonl, with what undoes it. Entries older than 30 days are dropped when the log is read.
//  The log holds titles and file names only, never file contents or message bodies. The folder is 0700 and the file
//  0600. Undoing validates every stored path first: nothing outside ~ or an external disk (ArisExternalDisks), and
//  nothing in Aris's own folder, ~/.ssh or the other places the risk gate calls protected, is ever touched, and nothing
//  is overwritten.
//

import Foundation

struct ArisActivityEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    /// What the work was called (a background task's title, or the conversation).
    let job: String
    /// Which AI did it (Claude, Codex…).
    let worker: String
    let summary: String
    let undo: ArisUndo?
    var undone: Bool
    /// The teammate whose job it was (its id, from ARIS_TEAMMATE): its face is found by this even after a rename. Nil
    /// for Aris's own work and for entries from before it was kept.
    var teammate: String?
}

enum ArisUndo: Codable, Equatable {
    /// A moved file is at `from` now; put it back at `to`.
    case moveBack(from: String, to: String)
    /// A trashed file is at `trash` now (in ~/.Trash); put it back at `original`.
    case restoreFromTrash(trash: String, original: String)
    /// Delete the calendar event Aris created (Calendar's uid).
    case deleteEvent(id: String)
    /// Remove a schedule Aris created (`aris-tools schedule add`).
    case removeSchedule(id: String)
    /// Put back a schedule that was removed (`aris-tools schedule remove`): the job as it was.
    case restoreSchedule(job: ArisScheduledJob)
    /// Files Aris made (a conversion, a merge, a split, a smaller copy): they go to the Trash.
    case trashMade(paths: [String])
    /// The notch app's own changes (QA BUG-18), undone through aris-tools: a to-do added is removed, a ticked one opened
    /// again (Reminders' id), the volume put back to its level before (0–100), a timer set stopped.
    case removeTodo(id: String)
    case reopenTodo(id: String)
    case setVolume(level: Int)
    case stopTimer
    /// A to-do put off until tomorrow from the day-end list (ArisDayEndPush) gets the date it had back: `due` in
    /// seconds since 1970, `timed` when that date had a time of day.
    case restoreTodoDue(id: String, due: Double, timed: Bool)

    /// What the entry did, in the user's words for picking one to undo ("방금 만든 거", "지운 거"): made, removed, moved, done,
    /// changed (QA BUG-42 retest: "만든 거 되돌려" undid a removal, so the schedule came back).
    var action: String {
        switch self {
        case .deleteEvent, .removeSchedule, .trashMade, .removeTodo: "made"
        case .restoreSchedule, .restoreFromTrash: "removed"
        case .moveBack: "moved"
        case .reopenTodo: "done"
        case .setVolume, .stopTimer, .restoreTodoDue: "changed"
        }
    }

    /// What a teammate needs to undo it (N13): files for a file put back or trashed, the calendar for a schedule or an
    /// event.
    var scope: ArisTeammateScope {
        switch self {
        case .moveBack, .restoreFromTrash, .trashMade: .files
        case .deleteEvent, .removeSchedule, .restoreSchedule, .removeTodo, .reopenTodo, .restoreTodoDue: .calendar
        case .setVolume, .stopTimer: .apps
        }
    }
}

enum ArisActivity {
    /// What `folder new` answers: the path as the brain gave it (absolute, the home folder as ~), never the resolved
    /// one (a link in it would show where it points).
    static func madeFolderLine(_ path: String, home: String) -> String {
        let shown = home.count > 1 && (path == home || path.hasPrefix(home + "/")) ? "~" + path.dropFirst(home.count) : path
        return "made folder \(shown)"
    }

    static let keepDays = 30
    /// How long an undo's AppleScript (Calendar deleting an event) may take; then it is stopped, before aris-agent gives
    /// up on aris-tools (ArisActivityBridge.undoTimeout), so the reason is said instead of "didn't answer" (QA BUG-17).
    static let appleScriptLimit: TimeInterval = 45
    /// Set by aris-agent alone for `activity log` (the notch app's own changes); no AI's command gets that far anyway.
    static let localLogKey = "ARIS_LOCAL_LOG"

    /// The log's lock file, opened close-on-exec: a child an undo starts (osascript) never holds the lock, so one that
    /// hangs can't keep the log locked for every later undo (QA BUG-17).
    static func openLock(_ file: URL) -> Int32 {
        open(file.path + ".lock", O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
    }

    /// Runs `program` and waits at most `limit` seconds; past that it is stopped and the error names `app`.
    static func runBounded(_ program: String, _ arguments: [String], limit: TimeInterval, app: String) throws {
        ArisOrigin.refuseUnlessStillAllowed()
        let process = ArisExactProcess()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: program)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        // Read as it comes, so a chatty child never blocks on a full pipe.
        let collected = Collected()
        errors.fileHandleForReading.readabilityHandler = { handle in collected.add(handle.availableData) }
        defer { errors.fileHandleForReading.readabilityHandler = nil }
        do { try process.run() } catch { throw UndoError(message: "couldn't run \(app): \(error.localizedDescription)") }
        let deadline = Date().addingTimeInterval(limit)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.2)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            throw UndoError(message: "\(app) didn't answer in time")
        }
        guard process.terminationStatus == 0 else {
            let complaint = collected.text
            throw UndoError(message: ArisActions.appleScriptProblem(complaint, app: app))
        }
    }

    /// A child's error output, gathered off its pipe's queue.
    private final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        func add(_ chunk: Data) { lock.withLock { if data.count < 100_000 { data.append(chunk) } } }
        var text: String { lock.withLock { String(decoding: data, as: UTF8.self) } }
    }

    /// The undo for a change the notch app made itself (`activity log --kind …`): `.some(nil)` for a change logged with
    /// no undo (a timer cancelled, windows arranged), nil for anything that isn't one of these kinds, well formed.
    static func localUndo(kind: String, id: String?, level: Int?, due: Double? = nil, timed: Bool = false) -> ArisUndo?? {
        let plainID = id.flatMap { $0.isEmpty || $0.count > 200 || $0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) ? nil : $0 }
        switch kind {
        case "todo-add": return plainID.map { .some(.removeTodo(id: $0)) }
        case "todo-done": return plainID.map { .some(.reopenTodo(id: $0)) }
        case "todo-due":
            // Only with the date it had: a moment of this century, never a made-up one.
            guard let plainID, let due, due.isFinite, (946_684_800...4_102_444_800).contains(due) else { return nil }
            return .some(.restoreTodoDue(id: plainID, due: due, timed: timed))
        case "timer-set": return .some(.stopTimer)
        case "timer-cancel", "arrange": return .some(nil)
        case "volume":
            guard let level else { return .some(nil) }
            return (0...100).contains(level) ? .some(.setVolume(level: level)) : nil
        default: return nil
        }
    }
    static let summaryLimit = 200
    /// "방금 거 취소해" only undoes something this recent; older ones are undone by naming them (their id).
    static let recentWindow: TimeInterval = 24 * 3600

    struct UndoError: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static var defaultFile: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/aris/aris/activity.jsonl")
    }

    // MARK: - The log

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// One short line: no line breaks or control characters, cut to the limit.
    static func oneLine(_ text: String, limit: Int = summaryLimit) -> String {
        let cleaned = text.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : String($0) }.joined()
        return String(cleaned.trimmingCharacters(in: .whitespaces).prefix(limit))
    }

    /// A teammate id as aris-agent gives them (lowercase letters, digits, dashes), else nil.
    static func teammateId(_ id: String) -> String? {
        id.range(of: #"^[a-z0-9][a-z0-9-]{0,31}$"#, options: .regularExpression) != nil ? id : nil
    }

    /// Adds an entry. Best effort: a log that can't be written never stops the action it records.
    static func append(_ entry: ArisActivityEntry, file: URL) {
        let clean = ArisActivityEntry(id: entry.id, date: entry.date, job: oneLine(entry.job, limit: 80), worker: oneLine(entry.worker, limit: 80),
                                      summary: oneLine(entry.summary), undo: entry.undo, undone: entry.undone,
                                      teammate: entry.teammate.flatMap(teammateId))
        guard var line = try? encoder.encode(clean) else { return }
        line.append(0x0A)
        withLock(file) {
            prepare(file)
            guard let handle = try? FileHandle(forUpdating: file) else { return }
            defer { try? handle.close() }
            // A line cut off by a crash must not swallow this one.
            if let end = try? handle.seekToEnd(), end > 0, (try? handle.seek(toOffset: end - 1)) != nil,
               let last = try? handle.read(upToCount: 1), last.first != 0x0A {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data([0x0A]))
            }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        }
    }

    /// The entries from `since` on, oldest first. Entries older than 30 days are dropped (also from the file).
    static func load(file: URL, since: Date, now: Date = Date()) -> [ArisActivityEntry] {
        let cutoff = now.addingTimeInterval(-Double(keepDays) * 86_400)
        let all = readAll(file)
        let kept = all.filter { $0.date >= cutoff }
        if kept.count < all.count { withLock(file) { rewrite(readAll(file).filter { $0.date >= cutoff }, file: file) } }
        return kept.filter { $0.date >= since }.sorted { $0.date < $1.date }
    }

    /// The newest entry that can still be undone (it has an undo and isn't undone yet).
    static func lastUndoable(_ entries: [ArisActivityEntry]) -> ArisActivityEntry? {
        entries.filter { $0.undo != nil && !$0.undone }.max { $0.date < $1.date }
    }

    /// What "방금 한 거 되돌려" means: the newest change not undone yet, whether or not it can be (QA BUG-18).
    static func latestChange(_ entries: [ArisActivityEntry]) -> ArisActivityEntry? {
        entries.filter { !$0.undone }.max { $0.date < $1.date }
    }

    /// Gives entry `id` a new summary and undo (a job's entry grows as each of its files lands). False when no entry
    /// has that id.
    @discardableResult
    static func replace(_ id: UUID, summary: String, undo: ArisUndo?, file: URL) -> Bool {
        withLock(file) {
            let all = readAll(file)
            guard all.contains(where: { $0.id == id }) else { return false }
            rewrite(all.map { entry in
                guard entry.id == id else { return entry }
                return ArisActivityEntry(id: entry.id, date: entry.date, job: entry.job, worker: entry.worker, summary: oneLine(summary),
                                         undo: undo, undone: entry.undone, teammate: entry.teammate)
            }, file: file)
            return true
        }
    }

    /// Marks an entry undone. False when no entry has that id.
    @discardableResult
    static func markUndone(_ id: UUID, file: URL) -> Bool {
        withLock(file) { markUndoneLocked(id, file: file) }
    }

    /// With the lock already held.
    private static func markUndoneLocked(_ id: UUID, file: URL) -> Bool {
        let all = readAll(file)
        guard all.contains(where: { $0.id == id }) else { return false }
        rewrite(all.map { entry in
            var copy = entry
            if copy.id == id { copy.undone = true }
            return copy
        }, file: file)
        return true
    }

    /// Whether an undo failed because what it would put back is no longer there (a file moved or deleted since, a
    /// schedule that ran or was removed, files already out of the Trash), by the undo's own reasons. Anything else (no
    /// permission, a name in the way, an app that didn't answer) may work on a later try and leaves the entry as it is.
    /// Whether a row still offers its undo: it has one that was not used, and what it would take away is still there.
    /// A schedule that was removed since (or ran its one time) has nothing left to remove: the row keeps its line and
    /// offers nothing (final VM run: "Scheduled: …" still offered Undo after that schedule was removed).
    static func offersUndo(_ undo: ArisUndo?, undone: Bool, schedules: Set<String>) -> Bool {
        guard let undo, !undone else { return false }
        if case .removeSchedule(let id) = undo { return schedules.contains { $0.caseInsensitiveCompare(id) == .orderedSame } }
        return true
    }

    static func targetGone(_ reason: String) -> Bool {
        ["isn't there", "already gone", "isn't in the Trash"].contains { reason.contains($0) }
    }

    /// The entry keeps its line and loses its undo: nothing offers to undo it again. With the lock already held.
    private static func spendLocked(_ id: UUID, file: URL) {
        rewrite(readAll(file).map { entry in
            guard entry.id == id else { return entry }
            return ArisActivityEntry(id: entry.id, date: entry.date, job: entry.job, worker: entry.worker, summary: entry.summary,
                                     undo: nil, undone: entry.undone, teammate: entry.teammate)
        }, file: file)
    }

    /// The most that a listing shows: the newest ones.
    static let listLimit = 500

    static func capped(_ entries: [ArisActivityEntry]) -> [ArisActivityEntry] {
        Array(entries.suffix(listLimit))
    }

    enum UndoOutcome {
        case done(ArisActivityEntry)
        /// Not done: it deletes an event Aris made, or brings a removed schedule back (work that runs on its own), so it
        /// needs a yes for exactly this entry (`confirmed` with its id).
        case needsConfirm(ArisActivityEntry)
    }

    /// Undos that need the user's yes for that one entry, whoever asks for them.
    static func needsYes(_ undo: ArisUndo) -> Bool {
        switch undo {
        case .deleteEvent, .restoreSchedule: return true
        case .moveBack, .restoreFromTrash, .removeSchedule, .trashMade, .removeTodo, .reopenTodo, .setVolume, .stopTimer, .restoreTodoDue: return false
        }
    }

    /// Undoes entry `id`, or the newest undoable one from the last day. Choosing, undoing and marking happen under
    /// one lock, so two undos can't both pick the same entry. A `confirmed` yes needs an `id`: it is for that entry.
    /// `scopes`: a teammate's job (nil for any other) undoes only what its scopes cover (ArisUndo.scope, N13), and only
    /// its own entries: those logged for `teammate` (the one its job file names); the user's and other teammates' are refused.
    /// `local`: undoes the notch app's own changes (a to-do, the timer, the volume), which need aris-tools' requests.
    static func undo(id: UUID?, confirmed: Bool, file: URL, now: Date = Date(),
                     home: String = FileManager.default.homeDirectoryForCurrentUser.path, scopes: Set<ArisTeammateScope>? = nil,
                     teammate: String? = nil, local: (ArisUndo) throws -> Void = { _ in throw UndoError(message: "that can't be undone") }) throws -> UndoOutcome {
        if confirmed && id == nil { throw UndoError(message: "a yes belongs to one entry: give its id") }
        return try withLock(file) {
            let cutoff = now.addingTimeInterval(-Double(keepDays) * 86_400)
            // A teammate's job sees only its own entries (none when its job file names nobody).
            let entries = readAll(file).filter { $0.date >= cutoff }
                .filter { entry in scopes == nil || (teammate != nil && entry.teammate == teammate) }
            let chosen: ArisActivityEntry
            if let id {
                guard let found = entries.first(where: { $0.id == id }) else {
                    throw UndoError(message: scopes == nil ? "no entry with that id" : "no entry of this teammate's with that id (it undoes only its own)")
                }
                guard !found.undone else { throw UndoError(message: "that was already undone") }
                chosen = found
            } else {
                // The latest change only (QA BUG-18): when it can't be undone that is the answer, never an older entry.
                guard let latest = latestChange(entries.filter { $0.date >= now.addingTimeInterval(-recentWindow) }) else {
                    throw UndoError(message: "nothing to undo")
                }
                chosen = latest
            }
            guard let action = chosen.undo else { throw UndoError(message: "that can't be undone") }
            if let scopes, !scopes.contains(action.scope) { throw UndoError(message: ArisTeammateScope.refusalLine([action.scope])) }
            if needsYes(action), !confirmed { return .needsConfirm(chosen) }
            do { try perform(action, home: home, now: now, local: local) } catch {
                // What it would put back is gone (moved or deleted since): this entry can't be undone any more, so it
                // is not offered again (fourth VM run, bug 5: "undo that" kept coming back to the same dead entry).
                if targetGone(error.localizedDescription) { spendLocked(chosen.id, file: file) }
                throw UndoError(message: "couldn't undo \"\(chosen.summary)\": \(error.localizedDescription)")
            }
            _ = markUndoneLocked(chosen.id, file: file)
            return .done(chosen)
        }
    }

    /// Each line decoded on its own: a damaged line (invalid UTF-8, a cut-off write) is skipped, never the whole log. Only
    /// The user's own private file is read, never through a link (the log holds whole schedules that can be brought back).
    private static func readAll(_ file: URL) -> [ArisActivityEntry] {
        guard let data = ArisPrivateFile.read(file) else { return [] }
        return data.split(separator: 0x0A).compactMap { try? decoder.decode(ArisActivityEntry.self, from: Data($0)) }
    }

    /// The log replaced whole (written beside it, then renamed over it), 0600.
    private static func rewrite(_ entries: [ArisActivityEntry], file: URL) {
        let lines = entries.compactMap { try? encoder.encode($0) }.map { String(decoding: $0, as: UTF8.self) + "\n" }
        let temp = file.deletingLastPathComponent().appendingPathComponent(".activity-\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(atPath: temp.path, contents: Data(lines.joined().utf8), attributes: [.posixPermissions: 0o600]) else { return }
        if rename(temp.path, file.path) != 0 { try? FileManager.default.removeItem(at: temp) }
    }

    /// The folder 0700 and the file 0600 (created that way, never widened).
    private static func prepare(_ file: URL) {
        let folder = file.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        if !FileManager.default.fileExists(atPath: file.path) {
            FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    /// Several aris-tools can run at once (a job doing two things): one writes the log at a time.
    private static func withLock<T>(_ file: URL, _ work: () throws -> T) rethrows -> T {
        let folder = file.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let descriptor = openLock(file)
        guard descriptor >= 0 else { return try work() }
        flock(descriptor, LOCK_EX)
        defer { flock(descriptor, LOCK_UN); close(descriptor) }
        return try work()
    }

    // MARK: - Paths

    /// `path` as an absolute path inside `home` with links resolved (the file itself may be a link; the folder it is
    /// in is resolved), or why not. Never the home folder itself, and nothing ArisProtectedPlaces names (compared
    /// without regard to case, and also when the path contains a protected place).
    /// A new name for an item in its folder: not empty, no slash, not . or .., no control characters.
    static func isPlainName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 255 && !name.contains("/") && name != "." && name != ".."
            && !name.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) || ArisCommandPolicy.isLineBreak($0) }
    }

    /// `disks`: the external disks (ArisExternalDisks): a path on one is checked by its rules instead (a file on a USB
    /// stick is worked on behind the same card; a system place or the disk's own folders never). The tests name their own.
    static func checkedPath(_ path: String, home: String, disks: ArisExternalDisks = .mounted) throws -> String {
        guard path.hasPrefix("/") else { throw UndoError(message: "not an absolute path") }
        let homeURL = URL(fileURLWithPath: home).resolvingSymlinksInPath()
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath()
        let resolved = parent.appendingPathComponent(url.lastPathComponent).path
        guard resolved.hasPrefix(homeURL.path + "/") else {
            if let refusal = disks.refusal(resolved) { throw UndoError(message: "\(url.lastPathComponent) \(refusal)") }
            return resolved
        }
        guard !ArisProtectedPlaces.blocks(resolved, home: homeURL.path) else {
            throw UndoError(message: "\(url.lastPathComponent) is in or holds a protected place")
        }
        return resolved
    }

    /// Moves without ever replacing what is at `to` (one atomic step, so nothing can appear there in between). To
    /// another disk a move is a copy (moveAcrossDisks).
    static func moveWithoutOverwriting(from: String, to: String) throws {
        guard renamex_np(from, to, UInt32(RENAME_EXCL)) == 0 else {
            let failure = errno
            if failure == EXDEV { return try moveAcrossDisks(from: from, to: to) }
            let name = ((failure == ENOENT ? from : to) as NSString).lastPathComponent
            switch failure {
            case EEXIST: throw UndoError(message: "\(name) already exists there, so nothing was overwritten")
            case ENOENT: throw UndoError(message: "\(name) isn't there, or the folder it belongs in is gone")
            default: throw UndoError(message: "couldn't move it: \(String(cString: strerror(failure)))")
            }
        }
    }

    /// A move to another disk ("이 파일 USB로 옮겨줘"): copied there under a name of Aris's own, put in place without
    /// replacing anything, and only then does the original go to its own disk's Trash (`trash`): never deleted, so it
    /// can still be put back. When the original can't be trashed the copy stays and the error says both are there.
    static func moveAcrossDisks(from: String, to: String,
                                trash: (String) throws -> Void = { try FileManager.default.trashItem(at: URL(fileURLWithPath: $0), resultingItemURL: nil) }) throws {
        let name = (to as NSString).lastPathComponent
        let waiting = (to as NSString).deletingLastPathComponent + "/.aris-moving-" + UUID().uuidString
        do { try FileManager.default.copyItem(atPath: from, toPath: waiting) } catch {
            try? FileManager.default.removeItem(atPath: waiting)
            throw UndoError(message: "couldn't copy it to the other disk: \(error.localizedDescription)")
        }
        guard renamex_np(waiting, to, UInt32(RENAME_EXCL)) == 0 else {
            let failure = errno
            try? FileManager.default.removeItem(atPath: waiting)
            throw UndoError(message: failure == EEXIST ? "\(name) already exists there, so nothing was overwritten" : "couldn't put it in place: \(String(cString: strerror(failure)))")
        }
        do { try trash(from) } catch {
            throw UndoError(message: "it was copied to the other disk, but the original couldn't be moved to the Trash (\(error.localizedDescription)): both are there now")
        }
    }

    // MARK: - Undo

    /// Does the undo. Throws (with the reason in words) when it can't or mustn't; nothing is overwritten.
    /// `home` is for tests; the Trash is `home`/.Trash. `now`: a restored schedule's next run counts from it.
    static func perform(_ undo: ArisUndo, home: String = FileManager.default.homeDirectoryForCurrentUser.path, now: Date = Date(),
                        disks: ArisExternalDisks = .mounted, user: uid_t = getuid(),
                        local: (ArisUndo) throws -> Void = { _ in throw UndoError(message: "that can't be undone") }) throws {
        switch undo {
        case .moveBack(let from, let to):
            try relocate(from: from, to: to, home: home, disks: disks)
        case .restoreFromTrash(let trash, let original):
            try restore(trash: trash, to: original, home: home, disks: disks, user: user)
        case .deleteEvent(let id):
            guard let script = ArisActions.deleteEventScript(uid: id) else { throw UndoError(message: "that event's id isn't one Calendar gives") }
            try runAppleScript(script)
        case .removeSchedule(let id):
            guard let uuid = UUID(uuidString: id) else { throw UndoError(message: "that schedule's id isn't one Aris gives") }
            do { try ArisScheduleStore.remove(id: uuid, file: ArisScheduleStore.file(home: home)) } catch {
                throw UndoError(message: "that schedule is already gone (it ran, or was removed)")
            }
        case .restoreSchedule(let job):
            do { try ArisScheduleStore.restore(job, now: now, calendar: .current, file: ArisScheduleStore.file(home: home)) } catch {
                throw UndoError(message: "couldn't bring the schedule back: \(error.localizedDescription)")
            }
        case .trashMade(let paths):
            try trashMade(paths, home: home)
        case .removeTodo, .reopenTodo, .setVolume, .stopTimer, .restoreTodoDue:
            try local(undo)
        }
    }

    /// Every path checked first (inside the home folder, never a protected place), then each file still there goes to
    /// the Trash (one already gone is skipped). Never deleted.
    private static func trashMade(_ paths: [String], home: String) throws {
        let checked = try paths.map { try checkedPath($0, home: home) }
        guard checked.contains(where: { FileManager.default.fileExists(atPath: $0) }) else { throw UndoError(message: "those files are already gone") }
        for path in checked where FileManager.default.fileExists(atPath: path) {
            try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
        }
    }

    private static func relocate(from: String, to: String, home: String, disks: ArisExternalDisks) throws {
        try moveWithoutOverwriting(from: try checkedPath(from, home: home, disks: disks), to: try checkedPath(to, home: home, disks: disks))
    }

    /// Puts a trashed file back: only from the Trash (the home folder's, or for a file that was on an external disk
    /// that disk's own Trash for this user, back onto that same disk), only to a place `checkedPath` allows.
    private static func restore(trash: String, to original: String, home: String, disks: ArisExternalDisks, user: uid_t) throws {
        let destination = try checkedPath(original, home: home, disks: disks)
        let url = URL(fileURLWithPath: trash).standardizedFileURL
        let source = url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(url.lastPathComponent).path
        let inside = { (folder: String) in ArisProtectedPlaces.key(source).hasPrefix(ArisProtectedPlaces.key(folder) + "/") }
        if let disk = disks.place(source)?.disk, disks.kind(disk) == .user {
            guard inside(disks.trash(of: disk, user: user)), disks.place(destination)?.disk == disk else { throw UndoError(message: "that file isn't in the Trash") }
        } else {
            guard inside(URL(fileURLWithPath: home).resolvingSymlinksInPath().appendingPathComponent(".Trash").path) else { throw UndoError(message: "that file isn't in the Trash") }
            _ = try checkedPath(trash, home: home, disks: disks)
        }
        try moveWithoutOverwriting(from: source, to: destination)
    }

    private static func runAppleScript(_ script: String) throws {
        try runBounded("/usr/bin/osascript", ["-e", script], limit: appleScriptLimit, app: "Calendar")
    }
}
