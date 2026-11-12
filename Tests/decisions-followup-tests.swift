// Tests for the follow-up to the owner's 2026-11-08 decisions (review of decisions-1108): a teammate job's identity
// from its job file, the schedule card naming the teammate, and undo limited to a teammate's own entries. Each one
// failed before its change. Called from main.swift; uses its check().
import Foundation

func runDecisionsFollowupTests() {
    followupJobFileTests()
    followupScheduleCardTests()
    followupUndoOwnTests()
}

private let fTools = "/Users/p/.config/aris/aris-tools"

/// 1: the teammate's id goes into its job file at launch; aris-tools reads it through the parent chain, never the env.
private func followupJobFileTests() {
    typealias F = ArisTeammateJobFile
    let home = NSTemporaryDirectory() + "aris-jobfile-\(UUID().uuidString)"
    defer { try? FileManager.default.removeItem(atPath: home) }
    let me = getpid()
    guard let started = F.startTime(of: me) else { return check(false, "job file: this process's start time") }
    check(F.write(pid: me, started: started, scopes: [.calendar], teammate: "mong", home: home), "job file: written with the teammate's id")
    let job = F.lookupJob(ancestors: F.ancestors(), home: home)
    check(job.found == .scopes([.calendar]) && job.teammate == "mong", "job file: the parent chain finds its scopes and its teammate")
    check(F.lookup(ancestors: F.ancestors(), home: home) == .scopes([.calendar]), "job file: lookup still gives the scopes")
    check(F.write(pid: me, started: started, scopes: [.calendar], teammate: "../Boss", home: home)
          && F.lookupJob(ancestors: F.ancestors(), home: home).teammate == nil, "job file: an id that isn't one names nobody")
    // A file from before (no teammate field): its scopes, and no teammate.
    let old = #"{"started":\#(started),"scopes":"calendar"}"#
    let path = F.file(home: home, pid: me).path
    unlink(path)
    FileManager.default.createFile(atPath: path, contents: Data(old.utf8), attributes: [.posixPermissions: 0o600])
    let before = F.lookupJob(ancestors: F.ancestors(), home: home)
    check(before.found == .scopes([.calendar]) && before.teammate == nil, "job file: an older file reads, naming no teammate")
    F.remove(pid: me, home: home)
    check(F.lookupJob(ancestors: F.ancestors(), home: home).teammate == nil, "job file: none, no teammate")

    typealias T = ArisScheduleTool
    check((try? T.owner(nil, teammate: "mong", scoped: true)) == "mong", "owner: the job file's teammate")
    check((try? T.owner(nil, teammate: nil, scoped: true)) == nil, "owner: a scoped job with no teammate in its job file schedules nothing")
    check((try? T.owner("boss", teammate: "mong", scoped: true)) == nil, "owner: never another teammate")
    check((try? T.owner("mong", teammate: nil, scoped: false)) == "mong" && (try? T.owner(nil, teammate: nil, scoped: false)) == .some(nil),
          "owner: main Aris's --teammate as given")
}

/// 2: the user's `schedule add` card says which teammate the job will run as, with what it may use.
private func followupScheduleCardTests() {
    let mate = ArisTeammate(id: "mong", name: "몽실", routing: "", look: .standard, brain: "codex", scopes: ["files", "calendar"], memoryFile: "")
    let line = "\(fTools) schedule add --title 정리 --prompt \"Say: hi\" --daily 08:00"
    let named = ArisCodexDriver.describe(command: line + " --teammate mong", tools: fTools, team: [.claudeCode, mate]).1
    check(named.contains("몽실") && named.contains("파일") && named.contains("캘린더") && !named.contains("터미널"),
          "schedule card: names the teammate and what it may use")
    check(!ArisCodexDriver.describe(command: line, tools: fTools, team: [.claudeCode, mate]).1.contains("팀원"), "schedule card: no teammate, no line")
    check(ArisCodexDriver.describe(command: line + " --teammate gone", tools: fTools, team: [.claudeCode]).1.contains("찾지 못"),
          "schedule card: a teammate that isn't stored is said (it won't run)")
    check(ArisTeammateScope.summary([.files, .calendar]) == "파일, 캘린더 · 미리 알림" && ArisTeammateScope.summary([]) == "없음",
          "schedule card: the scopes in the page's words")
}

/// 3: a teammate's job undoes only its own entries; the user's and other teammates' are refused (main Aris as before).
private func followupUndoOwnTests() {
    let home = NSTemporaryDirectory() + "aris-undoown-\(UUID().uuidString)"
    try? FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: home) }
    let add = { (title: String, teammate: String?) in
        _ = try? ArisScheduleTool.add(["--title", title, "--prompt", "Say: x", "--daily", "08:00"], home: home,
                                      environment: teammate.map { ["ARIS_TEAMMATE": $0] } ?? [:])
    }
    add("mine", "mong")
    add("user's", nil)
    add("boss's", "boss")
    let log = ArisPrivateFile.folder(home: home).appendingPathComponent("activity.jsonl")
    let entries = ArisActivity.load(file: log, since: .distantPast)
    guard entries.count == 3 else { return check(false, "undo own: three entries logged") }
    let refused = { (id: UUID) -> Bool in
        do { _ = try ArisActivity.undo(id: id, confirmed: false, file: log, home: home, scopes: [.calendar], teammate: "mong"); return false }
        catch { return true }
    }
    check(refused(entries[1].id) && refused(entries[2].id), "undo own: the user's and another teammate's entries are refused")
    if case .done(let done)? = try? ArisActivity.undo(id: nil, confirmed: false, file: log, home: home, scopes: [.calendar], teammate: "mong") {
        check(done.id == entries[0].id, "undo own: \"the latest\" is its own latest, not a newer one of someone else's")
    } else { check(false, "undo own: its own latest is undone") }
    check((try? ArisActivity.undo(id: entries[2].id, confirmed: false, file: log, home: home, scopes: [.calendar], teammate: nil)) == nil,
          "undo own: a scoped job that names no teammate undoes nothing")
    if case .done? = try? ArisActivity.undo(id: entries[1].id, confirmed: false, file: log, home: home) {} else {
        check(false, "undo own: main Aris still undoes the user's entry")
    }
}
