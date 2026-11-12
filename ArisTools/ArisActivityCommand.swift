//
//  ArisActivityCommand.swift
//  aris-tools
//
//  `activity [--today] [--json]` lists what Aris did (`activity log …` records a change of the notch app's, for aris-agent); `undo [--id <uuid>] [--confirmed]` puts the latest undoable thing
//  back (from the last day) or the one entry named. Undoing an event Aris created deletes it, and undoing a schedule's
//  removal brings it back to run on its own, so those exit 3 with what they would do unless --confirmed. The agent's risk gate asks before any AI runs `undo` at all; the app's own
//  request (POST /undo) is the user's. Other aris-tools record what they do with `logActivity`.
//

import Foundation

/// Records an action in the activity log. The job, worker and teammate come from ARIS_JOB / ARIS_WORKER / ARIS_TEAMMATE
/// (set by aris-agent for each AI process); run by hand they are "Aris", "aris-tools" and none.
@discardableResult
func logActivity(_ summary: String, undo: ArisUndo?, id: UUID = UUID()) -> UUID {
    let environment = ProcessInfo.processInfo.environment
    ArisActivity.append(ArisActivityEntry(id: id, date: Date(), job: environment["ARIS_JOB"] ?? "Aris",
                                          worker: environment["ARIS_WORKER"] ?? "aris-tools", summary: summary, undo: undo, undone: false,
                                          teammate: environment["ARIS_TEAMMATE"]),
                        file: ArisActivity.defaultFile)
    return id
}

private func asksFirst(_ undo: ArisUndo?) -> Bool {
    undo.map(ArisActivity.needsYes) ?? false
}

func activity(_ args: [String]) {
    if args.first == "log" { return activityLog(Array(args.dropFirst())) }
    let calendar = Calendar.current
    let since = args.contains("--today") ? calendar.startOfDay(for: Date()) : .distantPast
    let entries = ArisActivity.capped(ArisActivity.load(file: ArisActivity.defaultFile, since: since))
    if args.contains("--json") {
        // The schedules there are now: "Scheduled: …" offers no Undo once its schedule was removed or has run.
        let schedules = Set(ArisScheduleStore.load(file: ArisScheduleStore.file(home: FileManager.default.homeDirectoryForCurrentUser.path)).map { $0.id.uuidString })
        let items = entries.map { entry -> [String: Any] in
            var item: [String: Any] = ["id": entry.id.uuidString, "date": ISO8601DateFormatter().string(from: entry.date), "job": entry.job,
                                       "worker": entry.worker, "summary": entry.summary, "undoable": ArisActivity.offersUndo(entry.undo, undone: entry.undone, schedules: schedules),
                                       "undone": entry.undone, "asks": asksFirst(entry.undo)]
            if let teammate = entry.teammate { item["teammate"] = teammate }
            if let undo = entry.undo { item["action"] = undo.action }
            return item
        }
        let data = (try? JSONSerialization.data(withJSONObject: items, options: [.sortedKeys])) ?? Data("[]".utf8)
        return print(String(decoding: data, as: UTF8.self))
    }
    guard !entries.isEmpty else { return print("(nothing yet)") }
    let formatter = DateFormatter()
    formatter.dateFormat = args.contains("--today") ? "HH:mm" : "MM-dd HH:mm"
    print(entries.map { "\(formatter.string(from: $0.date))  \($0.worker) · \($0.job): \($0.summary)\($0.undone ? "  (undone)" : "")  [\($0.id.uuidString)]" }
        .joined(separator: "\n"))
}

/// `activity log --kind <kind> [--id <id>] [--level <0-100>] <summary…>`: a change the notch app made itself (a to-do
/// added or ticked, the timer, the volume, windows arranged), logged for it by aris-agent (POST /activity-log) so "방금 한
/// 거 되돌려" takes the latest change, never an older one (QA BUG-18). Only these kinds, each with its own undo
/// (ArisActivity.localUndo); no AI runs it (the risk gate, the turn gate and the sealed list refuse it).
func activityLog(_ args: [String]) {
    guard ProcessInfo.processInfo.environment[ArisActivity.localLogKey] == "1" else { fail("activity log is aris-agent's, for the notch app") }
    var kind: String?, id: String?, level: Int?, due: Double?, timed = false, words: [String] = []
    var index = 0
    while index < args.count {
        let word = args[index]
        if ["--kind", "--id", "--level", "--due", "--timed"].contains(word), index + 1 < args.count {
            let value = args[index + 1]
            switch word {
            case "--kind": kind = value
            case "--id": id = value
            case "--due": due = Double(value)
            case "--timed": timed = value == "1"
            default: level = Int(value)
            }
            index += 2
        } else {
            words.append(word)
            index += 1
        }
    }
    let summary = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    guard let kind, !summary.isEmpty, let undo = ArisActivity.localUndo(kind: kind, id: id, level: level, due: due, timed: timed) else {
        fail("usage: activity log --kind todo-add|todo-done|todo-due|timer-set|timer-cancel|volume|arrange [--id <id>] [--level <0-100>] [--due <seconds> --timed 0|1] <summary>")
    }
    print(logActivity(summary, undo: undo).uuidString)
}

/// Undoes what the notch app's own changes need (a to-do, the timer, the volume), which ArisActivity leaves to aris-tools.
private func undoLocal(_ undo: ArisUndo) throws {
    switch undo {
    case .removeTodo(let id), .reopenTodo(let id):
        let op: String
        if case .removeTodo = undo { op = "remove" } else { op = "reopen" }
        let reply = todoRequest(["op": op, "id": id])
        guard reply["ok"] as? Bool == true else { throw ArisActivity.UndoError(message: reply["message"] as? String ?? "couldn't change the to-do") }
    case .restoreTodoDue(let id, let due, let timed):
        let reply = todoRequest(["op": ArisTodoRoute.Request.Op.setDue.rawValue, "id": id, "at": due, "timed": timed])
        guard reply["ok"] as? Bool == true else { throw ArisActivity.UndoError(message: reply["message"] as? String ?? "couldn't change the to-do") }
    case .setVolume(let level):
        guard let script = ArisActions.volumeScript(String(level)) else { throw ArisActivity.UndoError(message: "that volume isn't one") }
        // The sound may go out somewhere else by now (HDMI, say): the level is said to be back only when it can be set.
        if let refusal = ArisActions.volumeRefusal(String(level), ArisActions.volumeSettings(appleScript("get volume settings"))) {
            throw ArisActivity.UndoError(message: refusal)
        }
        appleScript(script)
    case .stopTimer:
        try postTimer(["action": "stop"])
    default:
        throw ArisActivity.UndoError(message: "that can't be undone")
    }
}

func undo(_ args: [String]) {
    // The same reading of the arguments the risk gate uses.
    guard let parsed = ArisUndoArguments.parse(args) else {
        fail("usage: undo [--id <uuid> [--confirmed]] (a yes needs the --id of the entry that was shown)")
    }
    let id = parsed.id, confirmed = parsed.confirmed
    do {
        // A teammate's job undoes only what its scopes cover (N13).
        switch try ArisActivity.undo(id: id, confirmed: confirmed, file: ArisActivity.defaultFile, scopes: teammateScopes,
                                     teammate: teammateJob.teammate, local: undoLocal) {
        case .done(let entry):
            print("undone: \(entry.summary)")
        case .needsConfirm(let entry):
            var revives = false
            if case .restoreSchedule = entry.undo { revives = true }
            let shown = ["id": entry.id.uuidString, "summary": entry.summary, "kind": revives ? "restoreSchedule" : "deleteEvent"]
            print(String(decoding: (try? JSONSerialization.data(withJSONObject: shown)) ?? Data(), as: UTF8.self))
            let what = revives ? "this brings a removed schedule back" : "this deletes the calendar event"
            FileHandle.standardError.write(Data("asks first: \(what): \(entry.summary)\n".utf8))
            exit(Int32(3))
        }
    } catch {
        fail(error.localizedDescription)
    }
}

/// `move <from> <to>`: moves a file or folder inside the home folder or to and from an external disk (into `to` when
/// that is a folder). Never overwrites, never touches Aris's own folder or other protected places; logged so it can be
/// undone. To another disk it is a copy, and the original goes to its disk's Trash (ArisActivity.moveAcrossDisks).
func moveItem(_ args: [String]) {
    guard args.count == 2 else { fail("usage: move <from> <to>") }
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    var isFolder: ObjCBool = false
    var destination = absolutePath(args[1])
    if FileManager.default.fileExists(atPath: destination, isDirectory: &isFolder), isFolder.boolValue {
        destination += "/" + (absolutePath(args[0]) as NSString).lastPathComponent
    }
    do {
        let source = try ArisActivity.checkedPath(absolutePath(args[0]), home: home)
        let target = try ArisActivity.checkedPath(destination, home: home)
        // To another disk the move is a copy, and the original goes to its own disk's Trash: said, so it isn't a surprise.
        let disk = { (path: String) -> dev_t? in
            var info = stat()
            return stat((path as NSString).deletingLastPathComponent, &info) == 0 ? info.st_dev : nil
        }
        let across = disk(source) != disk(target)
        try ArisActivity.moveWithoutOverwriting(from: source, to: target)
        logActivity("옮김: \((source as NSString).lastPathComponent) → \((target as NSString).deletingLastPathComponent.replacingOccurrences(of: home, with: "~"))",
                    undo: .moveBack(from: target, to: source))
        print("moved \((source as NSString).lastPathComponent)" + (across ? " to the other disk: it was copied there, and the original is in its own disk's Trash" : ""))
    } catch {
        fail("couldn't move it: \(error.localizedDescription)")
    }
}

/// `rename <path> <new name>`: the file or folder keeps its folder and takes the new name (never over another item),
/// logged with its undo like `move`.
func renameItem(_ args: [String]) {
    guard args.count == 2 else { fail("usage: rename <path> <new name>") }
    let name = args[1].precomposedStringWithCanonicalMapping
    guard ArisActivity.isPlainName(name) else { fail("the new name is a plain file name (no /, no .. and not empty)") }
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let from = absolutePath(args[0])
    do {
        let source = try ArisActivity.checkedPath(from, home: home)
        let target = try ArisActivity.checkedPath((source as NSString).deletingLastPathComponent + "/" + name, home: home)
        try ArisActivity.moveWithoutOverwriting(from: source, to: target)
        logActivity("이름 바꿈: \((source as NSString).lastPathComponent) → \(name)", undo: .moveBack(from: target, to: source))
        print("renamed \((source as NSString).lastPathComponent) to \(name)")
    } catch {
        fail("couldn't rename it: \(error.localizedDescription)")
    }
}

/// `folder new <path>`: a new empty folder there (never over another item), in the home folder and outside the
/// protected places.
func newFolder(_ args: [String]) {
    guard args.count == 1 else { fail("usage: folder new <path of the new folder>") }
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    do {
        let given = absolutePath(args[0].precomposedStringWithCanonicalMapping)
        let path = try ArisActivity.checkedPath(given, home: home)
        guard mkdir(path, 0o755) == 0 else { fail(errno == EEXIST ? "something with that name is already there" : "couldn't make the folder") }
        logActivity("새 폴더: \((path as NSString).lastPathComponent)", undo: nil)
        print(ArisActivity.madeFolderLine(given, home: home))
    } catch {
        fail("couldn't make the folder: \(error.localizedDescription)")
    }
}

/// A path as given, with ~ expanded and a relative one taken from the current folder.
func absolutePath(_ path: String) -> String {
    let expanded = (path as NSString).expandingTildeInPath
    return expanded.hasPrefix("/") ? expanded : FileManager.default.currentDirectoryPath + "/" + expanded
}
