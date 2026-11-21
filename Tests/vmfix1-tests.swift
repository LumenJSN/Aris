// Tests for the defects the VM run of 2026-11-18 found (aris-vmcheck/notes): D3 uninstall, D1 the key taps after the
// first setup, D6 permissions shown as allowed, D8 and the settings text.

import AppKit

private func vmfixTemp(_ name: String) -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("vmfix1-\(name)-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func vmfixRoot() -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("..").standardizedFileURL
}

private func vmfixSource(_ path: String) -> String {
    (try? String(contentsOf: vmfixRoot().appendingPathComponent(path), encoding: .utf8)) ?? ""
}

/// An app bundle with only its Info.plist.
private func vmfixBundle(at url: URL, id: String, executable: String = "Aris") {
    try? FileManager.default.createDirectory(at: url.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
    let info: NSDictionary = ["CFBundleIdentifier": id, "CFBundleExecutable": executable, "CFBundlePackageType": "APPL"]
    info.write(to: url.appendingPathComponent("Contents/Info.plist"), atomically: true)
}

private func vmfixCatalog() -> [String: String] {
    ArisSettingsCopy.pairs(catalog: (try? Data(contentsOf: vmfixRoot().appendingPathComponent("Aris/components/Settings/Settings.xcstrings"))) ?? Data())
}

func runVmfix1Tests() {
    vmfixUninstallTests()
    vmfixKeyTapsTests()
    vmfixPermissionStateTests()
    vmfixSmallTests()
}

// MARK: - D3. Uninstall removes nothing

private func vmfixUninstallTests() {
    let scratch = vmfixTemp("uninstall")
    defer { try? FileManager.default.removeItem(at: scratch) }

    // The helper runs from inside Aris.app: the app's bundle is its own main bundle, whose id ArisHelperListing changed
    // in memory. Foundation keeps one bundle object per path, so Bundle(url:) gave the changed id back.
    let app = scratch.appendingPathComponent("Applications/Aris.app")
    vmfixBundle(at: app, id: "com.lumenjsn.aris")
    _ = Bundle(url: app)?.bundleIdentifier
    if let bundle = CFBundleCreate(nil, app as CFURL), let raw = CFBundleGetInfoDictionary(bundle),
       let info = (raw as NSDictionary) as? [String: Any],
       let changes = ArisHelperListing.changes(info: info, program: app.appendingPathComponent("Contents/MacOS/aris-agent").path) {
        ArisHelperListing.apply(changes, to: unsafeBitCast(raw, to: NSMutableDictionary.self))
    }
    check(Bundle(url: app)?.bundleIdentifier == "com.lumenjsn.aris.agent", "D3 setup: the bundle object for the app's path carries the helper's changed id")
    let live = ArisDataRoute.Effects.live(audit: { _ in })
    check(live.bundleId(app) == "com.lumenjsn.aris",
          "D3: uninstall reads the app's id from its Info.plist on disk, not the helper's changed copy in memory (\(live.bundleId(app) ?? "nil"))")

    // As strict as before: another app, or a bundle that only claims the id, is refused.
    let other = scratch.appendingPathComponent("Applications/Other.app")
    vmfixBundle(at: other, id: "com.other.app")
    let pretender = scratch.appendingPathComponent("Applications/Pretender.app")
    vmfixBundle(at: pretender, id: "com.lumenjsn.aris", executable: "Pretender")
    let linked = scratch.appendingPathComponent("Applications/Linked.app")
    try? FileManager.default.createDirectory(at: linked.appendingPathComponent("Contents"), withIntermediateDirectories: true)
    try? FileManager.default.createSymbolicLink(at: linked.appendingPathComponent("Contents/Info.plist"), withDestinationURL: app.appendingPathComponent("Contents/Info.plist"))
    check(live.bundleId(other) == "com.other.app" && live.bundleId(pretender) == nil && live.bundleId(linked) == nil
          && live.bundleId(scratch.appendingPathComponent("Applications/Missing.app")) == nil,
          "D3: another app, a bundle whose program isn't Aris's, a linked Info.plist and a missing bundle are never taken for Aris")

    // The route with the live check: the real app goes ahead, another app is refused with nothing touched.
    let home = scratch.appendingPathComponent("home")
    let places = ArisDataRoute.Places(home: home)
    try? FileManager.default.createDirectory(at: places.data, withIntermediateDirectories: true)
    let library = home.appendingPathComponent("Library")
    let leftovers = ["Preferences/aris-agent.plist", "Caches/aris-agent/x", "Caches/aris-tools/x", "Caches/com.lumenjsn.aris.agent/x",
                     "HTTPStorages/aris-agent/x", "HTTPStorages/aris-tools/x", "HTTPStorages/com.lumenjsn.aris.tools.binarycookies"]
    let appOwn = ["Caches/com.lumenjsn.aris/x", "Preferences/com.lumenjsn.aris.plist", "HTTPStorages/com.lumenjsn.aris/x"]
    for path in leftovers + appOwn {
        let url = library.appendingPathComponent(path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data("x".utf8).write(to: url)
    }
    var trashed: [URL] = [], audits: [String] = [], keychain: [String] = []
    var effects = ArisDataRoute.Effects(trash: { trashed.append($0) }, bootout: {}, reopenLog: {}, later: { _ in },
                                        bundleId: live.bundleId, audit: { audits.append($0) }, log: { _ in },
                                        deleteKeychain: { keychain.append($0); return true })
    effects.stopSkills = {}
    let refused = ArisDataRoute.handle(["op": "uninstall", "confirm": "제거"], places: places, appBundle: other, effects: effects)
    check(refused.status == 400 && trashed.isEmpty && audits.last == "data: refused uninstall (not the Aris app's bundle)"
          && FileManager.default.fileExists(atPath: library.appendingPathComponent("Caches/aris-agent/x").path),
          "D3: an uninstall from another app is still refused, audited, with nothing touched")
    let done = ArisDataRoute.handle(["op": "uninstall", "confirm": "제거"], places: places, appBundle: app, effects: effects)
    let steps = ((try? JSONSerialization.jsonObject(with: done.body)) as? [String: Any])?["steps"] as? [[String: Any]] ?? []
    check(done.status == 200 && trashed == [app] && steps.first?["step"] as? String == "app",
          "D3: the real Aris app's uninstall goes ahead while the helper's own bundle id is changed in memory")
    check(steps.contains { $0["step"] as? String == "helperFiles" && $0["ok"] as? Bool == true }
          && leftovers.allSatisfy { !FileManager.default.fileExists(atPath: library.appendingPathComponent($0).path) }
          && !FileManager.default.fileExists(atPath: library.appendingPathComponent("Caches/aris-agent").path),
          "D3: the helpers' caches, HTTP storage and old defaults under ~/Library go")
    // vmfix3: the caches and HTTP storage under the app's id outside its sandbox are the helper's and aris-tools' (both
    // run from inside the app) and go too; the app's preferences stay (the app removes its own domain).
    check(FileManager.default.fileExists(atPath: library.appendingPathComponent("Preferences/com.lumenjsn.aris.plist").path)
          && !FileManager.default.fileExists(atPath: library.appendingPathComponent("Caches/com.lumenjsn.aris").path)
          && !FileManager.default.fileExists(atPath: library.appendingPathComponent("HTTPStorages/com.lumenjsn.aris").path),
          "D3: the app's id's caches and HTTP storage outside the sandbox go; its preferences are left to the app")
    check(keychain.contains("com.lumenjsn.aris.keys") && keychain.contains("com.lumenjsn.aris.voiceid")
          && ArisUninstallCleanup.keychainServices.contains("com.lumenjsn.aris.brains"),
          "D3: uninstall deletes the app's key and voice Keychain services too, by service")

    // The app says what happened: a refusal is not "couldn't reach".
    let unreachable = ArisUninstallReply.from(status: nil, body: nil)
    let refusal = ArisUninstallReply.from(status: 400, body: [:]), forbidden = ArisUninstallReply.from(status: 403, body: nil)
    check(unreachable == .unreachable && refusal == .refused && forbidden == .refused
          && refusal.stoppedLine != unreachable.stoppedLine && refusal.stoppedLine?.contains("거절") == true
          && unreachable.stoppedLine?.contains("연결하지 못해서") == true,
          "D3: a helper that answered and refused is said as a refusal, not as unreachable")
    let worked = ArisUninstallReply.from(status: 200, body: ["steps": [["step": "app", "ok": true], ["step": "hooks", "ok": false, "note": "x"]]])
    check(worked.steps?.count == 2 && worked.stoppedLine == nil, "D3: steps that got past the app are the list's to show")
    let stuck = ArisUninstallReply.from(status: 200, body: ["steps": [["step": "app", "ok": false, "note": "translocated: move"]]])
    check(stuck.stoppedLine?.contains("응용 프로그램 폴더") == true, "D3: a translocated app still says to move it first")
    let catalog = vmfixCatalog()
    check([unreachable, refusal, stuck, ArisUninstallReply.steps([.init(step: "app", ok: false)])].compactMap(\.stoppedLine).allSatisfy { catalog[$0] != nil },
          "D3: every line the uninstall sheet can stop with has its English")
    let login = vmfixSource("Aris/private/Aris/ArisLoginItem.swift")
    check(login.contains("[.enabled, .requiresApproval].contains(SMAppService.mainApp.status)"),
          "D3: open at login is unregistered only when it is on (macOS refuses to unregister one it doesn't list)")
}

// MARK: - D1. Dictation and circle keys dead after the first setup until a relaunch

private func vmfixKeyTapsTests() {
    // The VM: Accessibility turned on during the setup, no Input Monitoring row; this process's listen check still no.
    check(ArisListenOutlook.of(listenNow: false, trustedNow: true, trustedAtLaunch: false) == .afterRelaunch
          && ArisListenOutlook.of(listenNow: true, trustedNow: true, trustedAtLaunch: false) == .ready
          && ArisListenOutlook.of(listenNow: false, trustedNow: true, trustedAtLaunch: true) == .notAllowed,
          "D1: key access given while Aris runs is known to need a reopen; one this process sees starts the taps")
    let key = ArisPermissionKey(.inputMonitoring)
    let (waiting, changes) = ArisPermissions().updating(key, to: ArisListenOutlook.afterRelaunch.reading(listenState: .notAsked))
    let (offered, decision) = waiting.require(key, for: .dictationKey)
    check(changes == [.relaunchNeeded(key)] && decision == .offerRelaunch(key) && offered.require(key, for: .dictationKey).1 == .doWithout(key),
          "D1: the reopen card for Input Monitoring is offered once, never again for the same grant")
    check(ArisPermissionNotice.notice(for: decision, english: true)?.actions.first?.role == .relaunchApp,
          "D1: the card is the existing one with its Reopen button")

    let taps = vmfixSource("Aris/private/App/ArisKeyTaps.swift")
    let center = vmfixSource("Aris/private/Aris/Permissions/ArisPermissionCenter.swift")
    let live = vmfixSource("Aris/private/Aris/Permissions/ArisPermissionsLive.swift")
    let guide = vmfixSource("Aris/private/Aris/Onboarding/ArisOnboardingGuide.swift")
    check(center.contains("if Self.wakesKeyTaps(change) { ArisKeyTaps.startWhenAllowed() }")
          && center.contains("case .granted(let key), .relaunchNeeded(let key): [.accessibility, .inputMonitoring].contains(key.permission)"),
          "D1: a grant of Accessibility or Input Monitoring the permission layer sees makes the taps look again at once")
    check(guide.contains("if !wasQuitting { ArisKeyTaps.startWhenAllowed() }"),
          "D1: the guide's end makes the taps look again (Input Monitoring asked once, or the reopen card), not the next launch")
    check(taps.contains("ArisPermissionCenter.shared.offerRelaunch(.inputMonitoring, for: .dictationKey)")
          && taps.contains("let seen = ArisOnboarding.pastFirstRunNow && !ArisOnboardingGuide.shared.showing")
          && taps.contains("_ = ArisListenNow.trustedAtLaunch") && taps.contains("listenAllowed: outlook == .ready"),
          "D1: past the guide the taps offer the reopen card for a grant only a new process sees; nothing is asked over the guide")
    // The wait used to look only at this process's cached listen answer, so the ask and the offer never came.
    check(taps.contains("try? await Task.sleep(for: .seconds(5))\n                startWhenAllowed()"),
          "D1: each look while waiting goes through the whole rule (ask once, offer the reopen), not the cached answer alone")
    check(live.contains("case .inputMonitoring: return ArisListenNow.outlook.reading("),
          "D1: the permission layer reads Input Monitoring with the reopen it needs")
}

// MARK: - D6. Permissions shown as allowed with no grant

private func vmfixPermissionStateTests() {
    let scratch = vmfixTemp("disk")
    defer { try? FileManager.default.removeItem(at: scratch) }
    // The TCC database opened in the VM with no Full Disk Access: SIP's file protection is off there.
    let tcc = scratch.appendingPathComponent("TCC.db").path
    FileManager.default.createFile(atPath: tcc, contents: Data("x".utf8))
    // vmfix3: with SIP off a folder only Full Disk Access opens opens too, so macOS's own decision is read instead.
    check(!ArisLocalReadPolicy.hasDiskAccess(probe: tcc, filesProtected: false, decision: { nil }),
          "D6: with SIP's file protection off, an opened TCC database alone is not Full Disk Access; unknown is never allowed")
    check(ArisLocalReadPolicy.hasDiskAccess(probe: tcc, filesProtected: false, decision: { true }), "D6: macOS's own yes for Aris confirms it")
    check(ArisLocalReadPolicy.hasDiskAccess(probe: tcc, filesProtected: true, decision: { false })
          && !ArisLocalReadPolicy.hasDiskAccess(probe: scratch.appendingPathComponent("none.db").path, filesProtected: false, decision: { true }),
          "D6: with SIP on the TCC database decides as before; a database that doesn't open is never allowed")
    // The three folders follow Full Disk Access (one row), so they were "allowed" with it.
    check(ArisSettingsSnapshot.folderPermissions(granted: [:]).allSatisfy { !$0.granted },
          "D6: no answer for a folder is not allowed")

    // System audio: macOS answers nothing until it is used; "allowed" only once a tap heard real sound.
    var s = ArisSettingsSnapshot()
    check(ArisSettingsBuilder.systemAudioRow(s).control != .said("허용됨"), "D6: system audio never heard is not shown as allowed")
    s.systemAudioProven = true
    check(ArisSettingsBuilder.systemAudioRow(s).control == .said("허용됨"), "D6: system audio a tap really heard is allowed")
    s.systemAudioMissing = true
    check(ArisSettingsBuilder.systemAudioRow(s).control != .said("허용됨"), "D6: only zeros while an app plays is missing, whatever was heard before")
    let catalog = vmfixCatalog()
    check(catalog[ArisSettingsBuilder.systemAudioRow(ArisSettingsSnapshot()).desc ?? ""] != nil, "D6: the not-yet-known line has its English")
}

// MARK: - D8. The greeting names the permission, the setup's receipt goes with it, the adapter dies with Aris

private func vmfixSmallTests() {
    typealias G = ArisSettingsCaption
    let one = G.greeting(agentDown: false, missingPermissions: 1, missingNames: ["입력 모니터링"])
    let three = G.greeting(agentDown: false, missingPermissions: 3, missingNames: ["마이크", "화면 기록", "손쉬운 사용"])
    check(one == "입력 모니터링 권한이 더 필요해요" && three == "마이크 외 권한 2개가 더 필요해요",
          "D8: the settings line names the permission it needs (\(one) / \(three))")
    check(G.asksForPermissions(one) && G.asksForPermissions(three) && G.asksForPermissions(G.greeting(agentDown: false, missingPermissions: 2)),
          "D8: the named line still opens the permission rows")
    ArisSettingsCopy.install(vmfixCatalog())
    let english = [one, three, G.greeting(agentDown: false, missingPermissions: 2, missingNames: ["마이크", "화면 기록"])].map(ArisSettingsCopy.t)
    check(english == ["Input Monitoring permission needed", "Microphone and 2 more permissions needed", "Microphone and one more permission needed"],
          "D8: in English too, the name translated (\(english))")

    // The practice's "✓ Set a timer · Undo" leaves with the setup and is never read back.
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let timer = ArisActivityItem(id: "T", date: start.addingTimeInterval(2), job: "대화", worker: "Aris", summary: "타이머: 3분", undoable: true,
                                 undone: false, asks: false, teammate: nil)
    let speaking = ArisSession().listening().hearing("3분 타이머").thinking().answering("맞췄어요.")
    let shown = ArisReceiptDesk().beginning(at: start).reading([timer], session: speaking)
    let away = shown.puttingAwaySetup()
    check(shown.line != nil && away.line == nil && !away.reads(at: start.addingTimeInterval(3))
          && away.beginning(at: start.addingTimeInterval(60)).reading([timer], session: speaking).line == nil,
          "D8: the setup's practice receipt goes when the setup ends, and never comes back on a later turn")
    let practice = vmfixSource("Aris/private/Aris/ArisController+Practice.swift")
    check(practice.contains("ArisReceiptModel.shared.setupEnded()"), "D8 wiring: clearing the practice clears its receipt")
    vmfixAdapterTests()
    vmfixSettingsTextTests()
}

/// The Now Playing stream ends once the Aris that started it is gone (its lifeline pipe closes, however Aris ended).
private func vmfixAdapterTests() {
    let scratch = vmfixTemp("adapter")
    defer { try? FileManager.default.removeItem(at: scratch) }
    let script = scratch.appendingPathComponent("stream.pl")
    try? Data("$| = 1; print \"up @ARGV\\n\"; sleep 60; print \"still here\\n\";\n".utf8).write(to: script)
    let files = ArisAdapterFiles(script: script, framework: scratch.appendingPathComponent("F.framework"), testClient: script)
    check(files.streamArguments(["stream", "--micros"]).suffix(4) == [script.path, scratch.appendingPathComponent("F.framework").path, "stream", "--micros"]
          && files.streamArguments([]).first == "-e", "D8: the stream runs behind its watcher, with the script's own arguments")
    func run() -> (Process, Pipe, Pipe)? {
        let process = Process(), lifeline = Pipe(), output = Pipe()
        process.executableURL = ArisAdapterFiles.perl
        process.arguments = files.streamArguments(["stream"])
        process.standardInput = lifeline
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        return (process, lifeline, output)
    }
    func waitEnd(_ process: Process, seconds: Double) -> Bool {
        let until = Date().addingTimeInterval(seconds)
        while process.isRunning, Date() < until { usleep(50_000) }
        return !process.isRunning
    }
    guard let (kept, keptLine, _) = run(), let (orphan, orphanLine, orphanOut) = run() else {
        return check(false, "D8: the stream's test processes started")
    }
    _ = waitEnd(kept, seconds: 1.5)
    check(kept.isRunning, "D8: while Aris holds the lifeline the stream runs")
    // Aris gone: the kernel closes its end of the pipe.
    try? orphanLine.fileHandleForWriting.close()
    check(waitEnd(orphan, seconds: 5) && orphan.terminationReason == .uncaughtSignal,
          "D8: once Aris is gone the stream is ended, not left an orphan")
    let said = String(decoding: orphanOut.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    check(said.hasPrefix("up ") && said.contains("F.framework stream") && !said.contains("still here"), "D8: the script itself ran with its arguments (\(said))")
    kept.terminate()
    _ = waitEnd(kept, seconds: 5)
    try? keptLine.fileHandleForWriting.close()
    let source = vmfixSource("Aris/private/Music/ArisNowPlayingAdapter.swift")
    check(source.contains("process.arguments = files.streamArguments([\"stream\", \"--micros\"])") && source.contains("process.standardInput = lifeline"),
          "D8 wiring: the app's stream runs behind the watcher with its lifeline")
}

// MARK: - D8. The settings text

private func vmfixSettingsTextTests() {
    let catalog = vmfixCatalog()
    ArisSettingsCopy.install(catalog)
    // MCP's two short fields: the hint fits in the English window too (Name (for example gith…).
    let services = vmfixSource("Aris/components/Settings/ArisServicesSection.swift")
    func fieldWidth(_ hint: String) -> CGFloat? {
        guard let range = services.range(of: "placeholder: \"\(hint)\""), let width = services[range.upperBound...].range(of: #"width: (\d+)"#, options: .regularExpression)
        else { return nil }
        return CGFloat(Int(services[width].dropFirst("width: ".count)) ?? 0)
    }
    let font = NSFont.systemFont(ofSize: 13)
    for hint in ["이름 (예: github)", "헤더 또는 환경 변수 이름 (선택)"] {
        let room = (fieldWidth(hint) ?? 0) - 24
        let widest = [hint, ArisSettingsCopy.t(hint)].map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? .infinity
        check(room > 0 && widest <= room, "D8: the MCP field “\(ArisSettingsCopy.t(hint))” shows its whole hint (\(Int(widest)) of \(Int(room)) pt)")
    }
    // The uninstall sheet: a path is one line cut in the middle, a description wraps whole.
    let sheet = vmfixSource("Aris/components/Settings/ArisDataSection.swift")
    check(sheet.contains("sub: isPath ? nil : row.path, path: isPath ? row.path : nil"),
          "D8: the uninstall list's descriptions wrap instead of being cut mid-word")
    // The quick-command row: a card like every row, named by its service.
    let ai = vmfixSource("Aris/components/Settings/ArisAIServicesPage.swift")
    check(!ai.contains("TypeSafe Jev") && ai.contains(".padding(ArisSettingsMetrics.rowInset)\n        .frame(maxWidth: .infinity, alignment: .leading)\n        .arisCard()"),
          "D8: 짧은 명령 빨리 알아듣기 is a card and says TypeSafe, not TypeSafe Jev")
    check(ArisSettingsCopy.t("1명") == "1 teammate" && ArisSettingsCopy.t("3명") == "3 teammates", "D8: 1 teammate, 3 teammates")
    // The skills switch: the page's title already says what it is.
    let skills = vmfixSource("Aris/components/Settings/ArisSkillsPage.swift")
    check(!skills.contains("Text(w(\"스킬 기능\"))") && skills.contains("ArisSwitch(isOn: on, label: \"스킬 기능\")"),
          "D8: the skills switch has no second label beside it (its accessibility label stays)")
    // A red button that can't be pressed is drawn plain.
    check(ArisSettingButtonKind.drawn(.danger, enabled: false) == .ghost && ArisSettingButtonKind.drawn(.danger, enabled: true) == .danger
          && ArisSettingButtonKind.drawn(.primary, enabled: false) == .primary, "D8: 모두 지우기 with nothing learned no longer looks pressable")
    check(ArisDropLearnedSetting.section(0).rows.first.map { if case .buttons(let b) = $0.control { !b[0].enabled } else { false } } == true,
          "D8: and it can't be pressed with nothing learned")
    // The wake name in the English window.
    if case .field(_, let text, let placeholder, let reset) = ArisWakeNameRows.row(name: "아리스", english: true).control {
        check(text == "Aris" && placeholder == "Aris" && !reset.enabled, "D8: the English window shows the wake name as Aris")
    } else { check(false, "D8: the wake name row is a field") }
    check(ArisWakeName(name: "Aris").isDefault && ArisWakeName(name: "aris").spellings.contains("아리스"),
          "D8: Aris typed in the English window is the default name with all its spellings")
    // Search: 하루 정리 finds the row that offers the day's summary first, then the detail.
    let found = ArisSettingsIndex.search("하루 정리").map(\.id)
    check(found.prefix(2) == ["aris.dayEnd", "aris.recap"], "D8: 하루 정리 finds the evening summary's row first (\(found))")
    check(ArisSettingsIndex.search("오늘 정리 알려주기").first?.id == "aris.dayEnd" && catalog[ArisDayEndSetting.title] != nil,
          "D8: its old name still finds it, and the new one has its English")
    // One row teaches the voice.
    let rows = ArisVoiceIDRows.rows(ArisVoiceIDSummary(on: true), busy: false, wakeTrained: false)
    let call = ArisSettingsBuilder.sections(part: "talk.call", ArisSettingsSnapshot()).flatMap(\.rows).map(\.id)
    check(!call.contains("aris.train") && rows.filter { $0.title.contains("목소리") && $0.title.contains("익히") || $0.title.contains("등록") }.count == 1
          && ArisSettingsIndex.entries.filter { $0.title == ArisVoiceIDRows.learnTitle }.count == 1,
          "D8: one row, 내 목소리 익히기, teaches Aris the voice (\(call))")
    if case .buttons(let buttons) = rows[1].control {
        check(buttons.map(\.action) == [.enrolVoice, .trainVoice], "D8: the row enrols the voice and learns the wake word")
    } else { check(false, "D8: the voice row has its buttons") }
    for wake in [false, true] {
        for enrolled in [false, true] {
            let line = ArisVoiceIDRows.learnLine(ArisVoiceIDSummary(enrolled: enrolled), wakeTrained: wake)
            check(ArisSettingsCopyMore.english[line] != nil, "D8: “\(line)” has its English")
        }
    }
    check(ArisSettingsCopy.t(ArisVoiceIDRows.learnTitle) == "Learn my voice"
          && ArisSettingsIndex.search("내 목소리 등록").first?.id == "aris.voiceEnrol", "D8: one name in both languages, the old one still found")
    // Step chips in the UI's language, whichever way the line came.
    check(ArisUIWords.status("TextEdit 보는 중…", english: true) == "Looking at TextEdit…"
          && ArisUIWords.status("Looking at TextEdit…", english: false) == "TextEdit 보는 중…"
          && ArisUIWords.status("Typing in Notes…", english: false) == "Notes에서 입력 중…"
          && ArisUIWords.status("입력하는 중", english: true) == "Typing",
          "D8: computer use's app line follows the UI's language like every step")
    let controller = vmfixSource("Aris/private/Aris/ArisController.swift")
    check(controller.contains("setSession(session.working(ArisUIWords.status(target.line)))"), "D8 wiring: the app line goes through the UI's words")
}
