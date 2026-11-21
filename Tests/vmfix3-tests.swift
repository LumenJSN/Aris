// jv-vmfix3: the defects the second VM run of 2026-11-19 found (aris-vmcheck/notes2, cap2).
// A2 a calendar event after the first-use grant; A3 Reminders at first use; the uninstall; Full Disk Access with SIP
// off; the setup's practice timer in the day in review; the words beside each other in two languages.

import EventKit
import Foundation
import SQLite3

private func vmfix3Source(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../")
    return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

private func vmfix3JSON(_ data: Data) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
}

// MARK: - A2: a calendar event after the first-use grant

private func vmfix3CalendarTests() {
    // The cause, part 1: after "Allow Full Access" this process still read "not asked yet", so the permission layer
    // put up "Calendars is off" and the route answered "no access". This run's yes is now kept for every reader.
    let calendars = ArisPermissionKey(.calendars)
    var model = ArisPermissions()
    model = model.updating(calendars, to: .init(state: .notAsked)).0
    let (asked, first) = model.require(.calendar)
    check(first == .prompt(calendars, reason: ArisPermissionFeature.calendar.reason(english: false)), "A2: the first use asks macOS, after its line of why")
    // What the old reading gave after the yes: still "not asked", and the next use was told "it is off".
    let stale = asked.updating(calendars, to: .init(state: .notAsked)).0
    if case .tellOff = stale.require(.calendar).1 {} else { check(false, "A2: the stale reading is what made the 'off' card") }
    let grants = ArisEventGrants()
    grants.note(.events, granted: true)
    let read = grants.status(.events, read: .notDetermined)
    check(read == .fullAccess, "A2: this run's yes stands while the class status still says 'not asked yet'")
    let (fresh, changes) = asked.updating(calendars, to: .init(state: read == .fullAccess ? .granted : .notAsked))
    check(fresh.require(.calendar).1 == .proceed && changes == [.granted(calendars)],
          "A2: read with the yes kept, the permission is on at once: the request goes ahead, no 'it is off' card")
    check(grants.status(.events, read: .denied) == .denied && grants.status(.reminders, read: .notDetermined) == .notDetermined,
          "A2: a status that says no is a no, and a yes for Calendars is not one for Reminders")
    grants.note(.events, granted: false)
    check(grants.status(.events, read: .notDetermined) == .notDetermined, "A2: a no in this run forgets the earlier yes")
    check(vmfix3Source("Aris/private/Calendar/ArisEventKitStore.swift").contains("static var granted: Bool { ArisEventGrants.shared.allowed(.events) }")
          && vmfix3Source("Aris/private/Aris/Permissions/ArisPermissionsLive.swift").contains("case .calendars: return .init(state: Self.events(ArisEventGrants.shared.status(.events)))")
          && vmfix3Source("Aris/private/Aris/Permissions/ArisPermissionsLive.swift").contains("case .reminders: return .init(state: Self.events(ArisEventGrants.shared.status(.reminders)))")
          && vmfix3Source("Aris/private/Calendar/ArisCalendarStore.swift").contains("ArisEventGrants.shared.note(.events, granted: granted)")
          && vmfix3Source("Aris/private/Aris/ArisReminders.swift").contains("ArisEventGrants.shared.note(.reminders, granted: granted)"),
          "A2: the route, the permission layer, the calendar tab and Reminders read and keep the same answer")
    for file in ["Aris/private/Aris/ArisFixModel.swift", "Aris/private/Aris/Onboarding/ArisOnboardingSystem.swift", "Aris/private/Aris/ArisWidgetModel.swift",
                 "Aris/private/Calendar/ArisOwnPlacesLive.swift", "Aris/private/Aris/Permissions/ArisPermissionsLive.swift", "Aris/private/Calendar/ArisEventKitStore.swift"] {
        check(!vmfix3Source(file).contains("EKEventStore.authorizationStatus(for: .event)") && !vmfix3Source(file).contains("EKEventStore.authorizationStatus(for: .reminder)"),
              "A2: \((file as NSString).lastPathComponent) never reads the bare class status")
    }

    // The cause, part 2: the route gave up 15 s after asking and aris-tools after 20 s, so a person who took 25 s got
    // "Aris isn't running" and had to ask again (a second card). Now every wait on the way holds the dialog's answer.
    typealias W = ArisPermissionWait
    check(W.dialog >= 60 && W.dialog < W.request && W.request < W.run && W.run < ArisTurnLimits.chat.silence,
          "A2: the route waits a minute and more, aris-tools and the helper longer, all inside a chat turn's silence limit")
    check(W.requestLimit(asks: false) == 20 && W.requestLimit(asks: true) == W.request, "A2: a request that can't ask keeps its 20 s")
    let asking = Data(#"{"op":"add","ask":true}"#.utf8), plain = Data(#"{"op":"add"}"#.utf8)
    check(HookLimits.standard.slow(path: "/aris/events", body: asking) == W.request && HookLimits.standard.slow(path: "/aris/todos", body: asking) == W.request
          && HookLimits.standard.slow(path: "/aris/events", body: plain) == 20 && HookLimits.standard.slow(path: "/aris/sessions", body: asking) == 20,
          "A2: the hook server keeps an asking calendar or to-do request open as long as aris-tools waits; the rest as before")
    check(W.runLimit(argv: ["event", "치과", "--start", "2026-11-20 15:00"]) == W.run && W.runLimit(argv: ["remind", "우유"]) == W.run
          && W.runLimit(argv: ["note", "x"]) == nil, "A2: the helper lets a calendar or to-do run wait as long")
    check(vmfix3Source("ArisAgent/ArisAPIHelper.swift").contains("ArisPermissionWait.runLimit(argv: argv) ?? 30"), "A2: wiring: the API brain's runner uses it")
    // aris-tools: a late answer is late, never "Aris isn't running".
    let late = W.reply(status: 504, data: nil, timedOut: false, lineKey: "line")
    check(late?["ok"] as? Bool == false && late?["line"] as? String == W.lateLine && !W.lateLine.contains("needs to be running"),
          "A2: the server giving up is told as late")
    check(W.reply(status: nil, data: nil, timedOut: true, lineKey: "message")?["message"] as? String == W.lateLine,
          "A2: aris-tools' own wait running out is late too")
    check(W.reply(status: nil, data: nil, timedOut: false, lineKey: "line") == nil, "A2: no app at all is the only 'not running'")
    check(W.reply(status: 200, data: Data(#"{"ok":true,"line":"added"}"#.utf8), timedOut: false, lineKey: "line")?["line"] as? String == "added",
          "A2: the app's answer is read as it came")
    let tools = vmfix3Source("ArisTools/ArisEventKit.swift") + vmfix3Source("ArisTools/ArisTodoCommand.swift")
    check(tools.contains("appRouteReply(path: \"/aris/events\"") && tools.contains("appRouteReply(path: \"/aris/todos\"") && !tools.contains("timeoutInterval: 20"),
          "A2: wiring: aris-tools' calendar and to-do requests wait through ArisAppRoute")
    // The route waits for the answer and then does the request under the grant it came with.
    let live = vmfix3Source("Aris/private/Claude/ClaudeHookLive.swift")
    check(live.contains("ArisPermissionWait.first(within: ArisPermissionWait.dialog)") && live.contains("ArisPermissionWait.stillAskingLine")
          && !live.contains("askedLimit") && !live.contains("Run the same command again"),
          "A2: the route waits for macOS's answer and goes on; only a dialog still up after the wait is told, as still asking")
    let consume = live.range(of: "ArisAgentClient.grant(for: ArisActionGrant.key(event: object))")?.lowerBound
    let wait = live.range(of: "await !answered(.calendar)")?.lowerBound
    let handle = live.range(of: "ArisEventRoute.handle(object)")?.lowerBound
    check(consume != nil && wait != nil && handle != nil && consume! < wait! && wait! < handle!,
          "A2: the gate's grant, then the wait, then the event, in the one request")
    check(!W.stillAskingLine.contains("needs to be running") && W.stillAskingLine.contains("Never say Aris isn't running")
          && !W.lateLine.contains("needs to be running") && W.lateLine.contains("never say Aris isn't running"),
          "A2: the still-asking and late lines never say Aris is off")

    // The turn says it waits, with the reason, and a card for the permission goes once it is on.
    let thinking = ArisSession().listening().hearing("일정 추가해 줘").thinking().working("일정 추가 중")
    let waiting = thinking.waitingForPermission(step: ArisPermissionNotice.waitingStep(.calendars, english: false), reason: "일정을 보려면 캘린더가 필요해요.")
    check(waiting.waitingNote == "일정을 보려면 캘린더가 필요해요." && waiting.status == "캘린더 허용 기다리는 중" && waiting.phase == .thinking,
          "A3: the turn shows that it waits for the permission and why")
    let answered = waiting.permissionAnswered()
    check(answered.waitingNote == nil && answered.steps.allSatisfy(\.done) && answered.phase == .thinking, "A2: answered, the turn goes on without the line")
    check(answered.working("일정 추가 중").waitingNote == nil && ArisSession().waitingForPermission(step: "x", reason: "y") == ArisSession(),
          "A2: any next state leaves the line out; no turn, no line")
    check(ArisPermissionNotice.waitingStep(.calendars, english: true).hasPrefix("Waiting for ") && ArisPermissionNotice.waitingStep(.reminders, english: false).hasSuffix("허용 기다리는 중"),
          "A2: the waiting step in both languages")
    check(ArisPermissionNotice.withdrawn(by: .granted(calendars)) == ArisPermissionNotice.key(calendars)
          && ArisPermissionNotice.withdrawn(by: .refused(calendars)) == nil,
          "A2: a permission turned on takes down its 'it is off' card at once")
    let center = vmfix3Source("Aris/private/Aris/Permissions/ArisPermissionCenter.swift")
    check(center.contains("ArisNoticeCenter.shared.withdraw(key: key)") && center.contains("ArisController.shared.showPermissionWait(key, reason: reason)")
          && center.contains("ArisController.shared.endPermissionWait()"),
          "A2: wiring: the permission layer shows the wait in the turn and withdraws the card")
    check(vmfix3Source("Aris/private/Aris/Home/ArisTurnView.swift").contains("let note = session.waitingNote"), "A3: wiring: the turn draws the reason")
}

// MARK: - A3: Reminders at first use

private func vmfix3RemindersTests() {
    // The cause: the typed or spoken "미리 알림 추가해 줘" is done in the app (funnel addTodo), whose access check never asks
    // a fresh "not asked yet" (that was left to the Settings button), so it said "access is off" without a dialog.
    check(!ArisRemindersAccess.asksAgain(fresh: .notAsked, answeredThisRun: false), "A3: the old check never raised the dialog at first use")
    check(ArisRemindersAccess.asksFirst(fresh: .notAsked, answeredThisRun: false, demo: false), "A3: a turn's first use of Reminders asks macOS first")
    check(!ArisRemindersAccess.asksFirst(fresh: .notAsked, answeredThisRun: false, demo: true) && !ArisRemindersAccess.asksFirst(fresh: .denied, answeredThisRun: false, demo: false)
          && !ArisRemindersAccess.asksFirst(fresh: .full, answeredThisRun: false, demo: false) && !ArisRemindersAccess.asksFirst(fresh: .notAsked, answeredThisRun: true, demo: false),
          "A3: never in the demo, never after a no or a yes, never twice in a run")
    let runs = vmfix3Source("Aris/private/Aris/Routing/ArisController+TurnRuns.swift")
    let ask = runs.components(separatedBy: "await ArisTodoModel.shared.askFirstIfNeverAsked()")
    check(ask.count == 3 && ask[1].contains("ArisTodoModel.shared.summary(korean: korean)") && ask[2].hasPrefix("\n            let reply = ArisLocalReply.todoAdded(await addTodo(item)"),
          "A3: wiring: adding a to-do and reading the list from a turn ask first, then go on")
    let model = vmfix3Source("Aris/private/Aris/ArisTodoModel.swift")
    check(model.contains("guard reminders.asksFirst(demo: demo.isOn) else { return }") && model.contains("_ = await ArisPermissionCenter.shared.require(.reminders)"),
          "A3: the ask goes through the permission layer (its one line, then macOS's dialog)")
    check(!vmfix3Source("Aris/private/Aris/ArisController+RoutineStep.swift").contains("askFirstIfNeverAsked"), "A3: a routine's step never raises a dialog")

    // The note above the permission list says what Allow does for what is missing.
    var s = ArisSettingsSnapshot()
    s.permissions = [.init(id: "ax", title: "", desc: "", granted: true), .init(id: "mic", title: "", desc: "", granted: true)]
    s.reminders = .undecided
    s.calendarAccess = .granted
    check(ArisPermissionsNote.note(s) == ArisPermissionsNote.dialogOnly && !ArisPermissionsNote.dialogOnly.contains("끌어다"),
          "A3: with only Reminders to allow, the note says macOS asks in its own window, not 'drag the icon'")
    s.reminders = .granted
    s.permissions[0] = .init(id: "ax", title: "", desc: "", granted: false)
    check(ArisPermissionsNote.note(s) == ArisPermissionsNote.settingsOnly, "A3: Accessibility alone: System Settings and the drag")
    s.calendarAccess = .undecided
    check(ArisPermissionsNote.note(s) == ArisPermissionsNote.both, "A3: both kinds missing: the note says both")
    s.permissions[0] = .init(id: "ax", title: "", desc: "", granted: true)
    s.calendarAccess = .granted
    check(ArisPermissionsNote.note(s) == nil, "A3: nothing missing, no note")
    check([ArisPermissionsNote.dialogOnly, ArisPermissionsNote.settingsOnly, ArisPermissionsNote.both].allSatisfy { ArisSettingsCopy.english($0) != nil },
          "A3: the note in English too")
    check(vmfix3Source("Aris/components/Settings/ArisSettingsBuilder.swift").contains("note: ArisPermissionsNote.note(s)"), "A3: wiring: the list's note")
}

// MARK: - The uninstall

private func vmfix3UninstallTests() {
    let fm = FileManager.default
    func exists(_ url: URL) -> Bool { fm.fileExists(atPath: url.path) || (try? fm.destinationOfSymbolicLink(atPath: url.path)) != nil }
    func write(_ text: String, _ url: URL) {
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: url)
    }

    // The cause: the folder went while this helper still wrote into it (actions.log, children.json, the aris-tools
    // link put back by its watch), so the removal failed and the files came back after it. Now writing stops first.
    let ledgerHome = NSTemporaryDirectory() + "aris-vmfix3-ledger-\(UUID().uuidString)"
    let ledger = ArisChildLedger(home: ledgerHome)
    ArisUninstallQuiet.begin(removingFolder: true)
    ledger.stopAll(grace: 0)
    var repaired = 0
    let linkKept = ArisToolsLink.ensure(app: "/Applications/Aris.app", link: ledgerHome + "/aris-tools", own: "/Applications/Aris.app/Contents/MacOS/aris-tools",
                                        kind: { _ in .nothing }, target: { _ in nil }, repair: { _, _ in repaired += 1; return true }, note: { _ in })
    check(!exists(ArisChildLedger.file(home: ledgerHome)) && repaired == 0 && linkKept && ArisUninstallQuiet.folderIsFrozen,
          "uninstall: once it began, the helper writes no children.json and never puts the tools link back")
    ArisUninstallQuiet.endForTests()
    ArisUninstallQuiet.begin(removingFolder: false)
    check(ArisUninstallQuiet.linkIsFrozen && !ArisUninstallQuiet.folderIsFrozen, "uninstall: with the records kept, only the link is left alone")
    ArisUninstallQuiet.endForTests()
    ledger.stopAll(grace: 0)
    check(exists(ArisChildLedger.file(home: ledgerHome)), "uninstall: otherwise the ledger writes as before")
    try? fm.removeItem(atPath: ledgerHome)
    // An audit line written while the folder goes is dropped: nothing of it reaches any file or the system log, which
    // other processes read and which outlives the uninstall. Only a counted marker is written.
    var markers: [Int] = []
    let liveMarker = ArisUninstallQuiet.marker
    ArisUninstallQuiet.marker = { markers.append($0) }
    ArisUninstallQuiet.begin(removingFolder: true)
    ArisUninstallQuiet.drop(#"{"action":"메일 보내기: 김철수 /Users/me/Documents/secret.pdf"}"#)
    ArisUninstallQuiet.drop("data: uninstall hooks ok: ~/.claude/settings.json: cleaned")
    check(markers == [1, 2], "uninstall: frozen audit lines reach the sink only as a count, never their content")
    ArisUninstallQuiet.endForTests()
    ArisUninstallQuiet.marker = liveMarker
    let quietSource = vmfix3Source("ArisAgent/ArisUninstallQuiet.swift")
    check(vmfix3Source("ArisAgent/ArisAgentRunner.swift").contains("if ArisUninstallQuiet.folderIsFrozen { return ArisUninstallQuiet.drop(line) }")
          && quietSource.contains("static var marker: (Int) -> Void") && !quietSource.contains("\\(line"),
          "uninstall: wiring: actions.log lines are dropped once the folder is going, and the marker is a fixed line with a count")

    // The route: stop writing, then remove; what Aris owns under ~/Library goes; its permission rows are reset; the
    // sandbox folder is said honestly; and a last remover outlives the helper.
    let home = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("aris-vmfix3-home-\(UUID().uuidString)", isDirectory: true)
    let places = ArisDataRoute.Places(home: home)
    let library = home.appendingPathComponent("Library")
    let ladder = library.appendingPathComponent("Application Support/Aris/engine/input-ladder.json")
    let skills = library.appendingPathComponent("Application Support/Aris/Skills/mine/SKILL.md")
    let leftovers = [ladder, library.appendingPathComponent("Caches/com.lumenjsn.aris/Cache.db"),
                     library.appendingPathComponent("HTTPStorages/com.lumenjsn.aris/httpstorages.sqlite"),
                     library.appendingPathComponent("HTTPStorages/com.lumenjsn.aris.binarycookies"),
                     library.appendingPathComponent("Application Scripts/com.lumenjsn.aris/x")]
    let container = library.appendingPathComponent("Containers/com.lumenjsn.aris/Data/Library/x")
    func setUp() {
        write("{}", places.data.appendingPathComponent("actions.log"))
        write("bin", places.folder.appendingPathComponent("aris-agent"))
        try? fm.createSymbolicLink(atPath: places.folder.appendingPathComponent("aris-tools").path, withDestinationPath: "/Applications/Aris.app/Contents/MacOS/aris-tools")
        write("plist", places.plist)
        (leftovers + [skills, container]).forEach { write("x", $0) }
    }
    setUp()
    let app = home.appendingPathComponent("Applications/Aris.app")
    try? fm.createDirectory(at: app, withIntermediateDirectories: true)
    var events: [String] = [], reset: [String] = [], swept: [URL] = [], later: [() -> Void] = []
    var failing: Set<String> = []
    func uninstall(keepData: Bool) -> [String: Any] {
        events = []; reset = []; swept = []; later = []
        var effects = ArisDataRoute.Effects(trash: { _ in events.append("trash") }, bootout: { events.append("bootout") }, reopenLog: {},
                                            later: { later.append($0) }, bundleId: { _ in "com.lumenjsn.aris" },
                                            audit: { events.append($0) }, log: { events.append($0) })
        effects.quiesce = { events.append("quiesce \($0)") }
        effects.resetPermission = { reset.append($0); return !failing.contains($0) }
        effects.sweep = { swept = $0; events.append("sweep") }
        let reply = ArisDataRoute.handle(["op": "uninstall", "confirm": "제거", "keepData": keepData], places: places, appBundle: app, effects: effects)
        return vmfix3JSON(reply.body)
    }
    let all = uninstall(keepData: false)
    let steps = all["steps"] as? [[String: Any]] ?? []
    let names = steps.map { $0["step"] as? String ?? "" }
    check(names == ["app", "hooks", "antigravity", "keychain", "link", "launchAgent", "helperFiles", "skills", "appFiles", "permissions", "sandbox", "folder"],
          "uninstall: every step reported, in order (\(names))")
    let trash = events.firstIndex(of: "trash"), quiet = events.firstIndex(of: "quiesce true"), firstRemoval = events.firstIndex { $0.contains("uninstall hooks") }
    check(trash != nil && quiet != nil && firstRemoval != nil && trash! < quiet! && quiet! < firstRemoval!,
          "uninstall: writing stops right after the app goes to the Trash, before anything is removed (\(events.prefix(4)))")
    check(steps.first { $0["step"] as? String == "folder" }?["ok"] as? Bool == true && !exists(places.folder), "uninstall: ~/.config/aris goes whole")
    check(leftovers.allSatisfy { !exists($0) } && !exists(library.appendingPathComponent("Application Support/Aris")),
          "uninstall: Application Support/Aris, the app id's caches and HTTP storage and its Application Scripts go")
    check(exists(container), "uninstall: the sandbox container is never touched (macOS keeps it for the app)")
    let sandbox = steps.first { $0["step"] as? String == "sandbox" }
    check(sandbox?["ok"] as? Bool == false && (sandbox?["note"] as? String)?.contains("Containers/com.lumenjsn.aris") == true,
          "uninstall: and that is said, not reported as removed")
    check(reset == ArisUninstallCleanup.permissionServices && steps.first { $0["step"] as? String == "permissions" }?["ok"] as? Bool == true
          && ["Microphone", "SpeechRecognition", "Calendar", "Reminders", "AppleEvents", "Accessibility"].allSatisfy(reset.contains),
          "uninstall: Aris's own rows are reset by its bundle id, service by service")
    check(!events.contains("sweep") && !events.contains("bootout") && later.count == 1, "uninstall: the last remover and the bootout wait for the reply")
    later.first?()
    let sweptPaths = swept.map { $0.standardizedFileURL.path }
    check(events.suffix(2) == ["sweep", "bootout"] && sweptPaths.contains(places.folder.standardizedFileURL.path)
          && sweptPaths.contains(library.appendingPathComponent("Application Support/Aris").standardizedFileURL.path)
          && sweptPaths.contains(library.appendingPathComponent("Caches/com.lumenjsn.aris").standardizedFileURL.path),
          "uninstall: after the reply, a remover that outlives the helper takes what was written in its last moment, then the bootout")
    check(vmfix3Source("ArisAgent/ArisUninstallCleanup.swift").contains("POSIX_SPAWN_SETSID") && vmfix3Source("ArisAgent/ArisUninstallCleanup.swift").contains("[\"reset\", service, appId]"),
          "uninstall: wiring: the remover runs in a session of its own; tccutil gets Aris's own bundle id")

    // Records kept: the skills stay, the rest goes; a reset that failed is said.
    setUp()
    failing = ["Accessibility"]
    let kept = uninstall(keepData: true)
    let keptSteps = kept["steps"] as? [[String: Any]] ?? []
    check(events.contains("quiesce false") && exists(skills) && !exists(ladder) && !exists(places.folder.appendingPathComponent("aris-tools"))
          && exists(places.data.appendingPathComponent("actions.log")),
          "uninstall: with the records kept, the user's skills and records stay; the engine's files and the tools link go")
    let rows = keptSteps.first { $0["step"] as? String == "permissions" }
    check(rows?["ok"] as? Bool == false && (rows?["note"] as? String)?.contains("Accessibility") == true, "uninstall: a row tccutil couldn't reset is named")
    try? fm.removeItem(at: home)

    // The sheet: what wasn't removed, each with what to do, in both languages.
    let lines = ArisUninstallReply.leftLines(failedRows: ["sandbox", "permissions", "data"], titles: ["설정과 기록"], oldHelper: true)
    check(lines.count == 3 && lines[0] == "이건 지우지 못했어요: 설정과 기록. Finder에서 직접 지워 주세요." && !lines.contains(ArisUninstallReply.sandboxLine)
          && lines.contains(ArisUninstallReply.permissionsLine) && lines.last == ArisUninstallReply.oldRowsLine,
          "uninstall sheet: each thing left is named with what to do")
    check(ArisUninstallReply.leftLines(failedRows: ["sandbox"], titles: [], oldHelper: true) == [ArisUninstallReply.oldRowsLine],
          "uninstall sheet: only the sandbox folder and the old rows' note when the rest went")
    check([ArisUninstallReply.sandboxLine, ArisUninstallReply.permissionsLine, ArisUninstallReply.oldRowsLine, "권한 기록", "샌드박스 폴더"].allSatisfy { ArisSettingsCopy.english($0) != nil },
          "uninstall sheet: its new words in English")
}

// MARK: - Full Disk Access and the folders with SIP off

private func vmfix3DiskAccessTests() {
    let scratch = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("aris-vmfix3-tcc-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scratch) }
    let db = scratch.appendingPathComponent("TCC.db").path
    var handle: OpaquePointer?
    _ = sqlite3_open(db, &handle)
    _ = sqlite3_exec(handle, """
        CREATE TABLE access (service TEXT, client TEXT, client_type INTEGER, auth_value INTEGER);
        INSERT INTO access VALUES ('kTCCServiceSystemPolicyAllFiles', '/usr/libexec/sshd-keygen-wrapper', 1, 2);
        INSERT INTO access VALUES ('kTCCServiceSystemPolicyAllFiles', 'com.example.other', 0, 2);
        INSERT INTO access VALUES ('kTCCServiceSystemPolicyDesktopFolder', 'com.lumenjsn.aris', 0, 0);
        INSERT INTO access VALUES ('kTCCServiceSystemPolicyDownloadsFolder', 'com.lumenjsn.aris', 0, 2);
        """, nil, nil, nil)
    sqlite3_close(handle)
    let aris = ["com.lumenjsn.aris", "/Applications/Aris.app/Contents/MacOS/aris-agent"]
    // The VM's database after a reset: Full Disk Access rows for others, none for Aris. The old probe opened a
    // guarded file and said "allowed"; macOS's decision says no.
    let disk = ArisTCCReading.allowed(service: ArisTCCReading.diskService, clients: aris, database: db)
    check(disk == false, "SIP off: no row for Aris is no Full Disk Access, whatever others have")
    check(!ArisLocalReadPolicy.hasDiskAccess(probe: db, filesProtected: false, decision: { disk }), "SIP off: the row 'Full Disk Access' reads not allowed")
    check(ArisTCCReading.allowed(service: ArisTCCReading.folderService("Desktop"), clients: aris, database: db) == false
          && ArisTCCReading.allowed(service: ArisTCCReading.folderService("Downloads"), clients: aris, database: db) == true,
          "SIP off: a folder is allowed only by Aris's own yes, a refusal is no")
    check(ArisTCCReading.allowed(service: ArisTCCReading.diskService, clients: aris, database: scratch.appendingPathComponent("none.db").path) == nil,
          "SIP off: a database that can't be read is unknown")
    let desktop = URL(fileURLWithPath: "/Users/x/Desktop")
    check(!ArisFolderAccess.granted(desktop, filesProtected: false, touch: { _ in true }, decision: { _ in false })
          && !ArisFolderAccess.granted(desktop, filesProtected: false, touch: { _ in true }, decision: { _ in nil }),
          "SIP off: a folder that opens is not allowed without macOS's yes (the '3 file folders · Allowed' row)")
    check(ArisFolderAccess.granted(desktop, filesProtected: false, touch: { _ in true }, decision: { $0 == "Desktop" }),
          "SIP off: the folder's own row is asked by its name")
    var decided = false
    check(ArisFolderAccess.granted(desktop, filesProtected: true, touch: { _ in true }, decision: { _ in decided = true; return false }) && !decided
          && ArisLocalReadPolicy.hasDiskAccess(probe: db, filesProtected: true, decision: { decided = true; return false }) && !decided,
          "SIP on (the user's Mac): the touch and the probe decide as before, the database is never read")
    check(vmfix3Source("ArisAgent/main.swift").contains("let granted = ArisFolderAccess.granted(url)"), "SIP off: wiring: 설정's folder answer")
    check(ArisTCCReading.clients.contains("com.lumenjsn.aris") && ArisTCCReading.clients.contains("com.lumenjsn.aris.aris-agent"),
          "SIP off: Aris's row is looked for under the app's id and the helper's own signing identifier")
}

// MARK: - D5: the setup's practice in the day in review

private func vmfix3PracticeTests() {
    // The cause: the practice timer was recorded like any timer ("타이머: 3분", worker user), and the last fix dropped
    // it only when the setup's end turned it off before it rang. This one rang during the setup (set 04:04, 3 minutes),
    // so it stayed in the day in review and counted as "1 done". Now nothing the practice does is recorded.
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let rang = ArisActivityItem(id: "practice", date: now.addingTimeInterval(-1_800), job: "Aris", worker: "user", summary: "타이머: 3분", undoable: false, undone: false, asks: false, teammate: nil)
    check(ArisDayEndPlan.cancelledTimers([rang]).isEmpty, "D5: a recorded practice timer that rang was work done to the day in review (the cause)")
    check(!ArisOnboardingPractice.recordsChanges, "D5: the practice records nothing")
    let practice = vmfix3Source("Aris/private/Aris/ArisController+Practice.swift")
    check(practice.contains("doOnMac(intent, korean: korean, recorded: ArisOnboardingPractice.recordsChanges)") && !practice.contains("cancelLogged()"),
          "D5: wiring: the practice's timer is set without a record line, and goes without one")
    let local = vmfix3Source("Aris/private/Aris/ArisController+Local.swift")
    check(local.contains("if recorded, let logged = change.logged { ArisAgentClient.logLocalChange(kind: logged.kind, summary: logged.summary) }"),
          "D5: wiring: a timer change is recorded only when asked to be")
}

// MARK: - The words: one language

private func vmfix3WordsTests() {
    // The step chips: a taught procedure's run came in the words' language ("‘메모 쓰기’ 하는 중" beside "Did 2 things").
    check(ArisUIWords.status("‘메모 쓰기’ 하는 중", english: true) == "Doing “메모 쓰기”"
          && ArisUIWords.status("‘메모 쓰기’ 하는 중 · 1/2", english: true) == "Doing “메모 쓰기” · 1/2",
          "words: a taught procedure's step in English in the English UI, its count kept")
    check(ArisUIWords.status("Doing “memo”", english: false) == "‘memo’ 하는 중" && ArisUIWords.status("Doing “memo” · 2/3", english: false) == "‘memo’ 하는 중 · 2/3"
          && ArisUIWords.status("Doing the saved steps", english: false) == "저장된 단계대로 하는 중" && ArisUIWords.status("Doing the saved steps", english: true) == "Doing the saved steps",
          "words: and in Korean in the Korean UI, whichever language the agent wrote it in")
    check(vmfix3Source("Shared/Core/Teach/ArisTeachCopy.swift").contains("english ? \"Doing “\\(procedure.name)”\" : \"‘\\(procedure.name)’ 하는 중\""),
          "words: the lines the teach run sends are the ones mapped")
    // Every step the agent names reads in English in the English UI.
    let source = vmfix3Source("ArisAgent/ArisAgentStatus.swift")
    let literals = (try? NSRegularExpression(pattern: #""([^"]*[가-힣][^"]* 중)""#))?.matches(in: source, range: NSRange(source.startIndex..., in: source))
        .compactMap { Range($0.range(at: 1), in: source).map { String(source[$0]) } } ?? []
    let untranslated = Set(literals).filter { ArisUIWords.status($0, english: true) == $0 }
    check(literals.count > 40 && untranslated.isEmpty, "words: every agent step has its English (\(untranslated.sorted().prefix(3)))")

    // A tool's reason after the app's line: in the same language, or left out.
    typealias E = ArisToolErrorWords
    check(E.line("바꾸지 못했어요", "Couldn't replace it", problem: "won't type into Aris", inEnglish: false) == "바꾸지 못했어요: Aris에는 입력하지 않아요"
          && E.line("바꾸지 못했어요", "Couldn't replace it", problem: "won't type into Aris", inEnglish: true) == "Couldn't replace it: Aris won't type into Aris",
          "words: the VM's 'won't type into Aris' in both languages")
    for refusal in [ArisInsertRefusal.noKeyboardApp, ArisInsertRefusal.needsAccessibility, "a password field has the keyboard", ArisDesktopLockWords.insertRefusal] {
        let korean = E.line("넣지 못했어요", "Couldn't type it", problem: refusal, inEnglish: false)
        check(korean.hasPrefix("넣지 못했어요: ") && !korean.contains("keyboard") && !korean.contains("Aris needs"), "words: '\(refusal.prefix(30))' said in Korean")
    }
    check(E.line("바꾸지 못했어요", "Couldn't replace it", problem: "the paste was not confirmed (code 7)", inEnglish: false) == "바꾸지 못했어요."
          && E.line("메모에 저장하지 못했어요", "It wasn't saved to Notes", problem: "메모 앱이 응답하지 않았어요", inEnglish: true) == "It wasn't saved to Notes."
          && E.line("메모에 저장하지 못했어요", "It wasn't saved to Notes", problem: "메모 앱이 응답하지 않았어요", inEnglish: false) == "메모에 저장하지 못했어요: 메모 앱이 응답하지 않았어요",
          "words: an unknown reason in the other language is left out, never shown raw after the line")
    check(vmfix3Source("Aris/private/Aris/ArisController+Look.swift").contains("ArisToolErrorWords.line(\"바꾸지 못했어요\", \"Couldn't replace it\", problem: problem)")
          && vmfix3Source("Aris/private/Aris/ArisController+Dictation.swift").contains("ArisToolErrorWords.line(\"마지막 받아쓰기를 넣지 못했어요\""),
          "words: wiring: the replace and the last dictation's failures")

    // The message card's no-microphone hint wraps instead of being cut.
    let lane = vmfix3Source("Aris/private/Aris/Home/ArisConfirmCard+Countdown.swift")
    check(lane.contains(".lineLimit(2).minimumScaleFactor(0.9).fixedSize(horizontal: false, vertical: true)"), "words: the hint beside the buttons takes two lines when it needs them")
}

func runVmfix3Tests() {
    vmfix3CalendarTests()
    vmfix3RemindersTests()
    vmfix3UninstallTests()
    vmfix3DiskAccessTests()
    vmfix3PracticeTests()
    vmfix3WordsTests()
}
