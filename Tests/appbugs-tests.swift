// Tests for the audited app bugs fixed on jv-appbugs: the composer's draft holding the notch, the hot keys with no
// default, the toggle notch with no timer, and the rest (see each section). Called from main.swift; uses its check().
import AppKit

func runAppbugsTests() {
    appbugsComposerTests()
    appbugsHotKeyTests()
    appbugsClipboardTests()
    appbugsSideTests()
    appbugsRecordingTests()
    appbugsUpdateTests()
    appbugsDropTests()
    appbugsTurnTests()
    appbugsPreviewTests()
    appbugsSettingsTests()
    appbugsPermissionTests()
    appbugsClaudeConnectTests()
    appbugsCardParkTests()
}

/// A source file of the app, for the wiring checks (what can't be made pure).
func appbugsSource(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("..").standardized
    return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

// MARK: - 2. The composer's draft

private func appbugsComposerTests() {
    typealias D = ArisNotchDecisions
    check(D.composerHolds(draft: "메일 보내", focused: true), "composer: words in a focused field hold the notch")
    check(!D.composerHolds(draft: "메일 보내", focused: false), "composer: a draft without the keyboard doesn't hold it")
    check(!D.composerHolds(draft: "  \n", focused: true), "composer: only spaces don't hold it")
    check(!D.automaticCloseAllowed(open: true, hovering: false, popover: false, sharing: false, approvalsPending: false, turnHolds: false,
                                   typing: true), "composer: no automatic close while typing")
    check(D.automaticCloseAllowed(open: true, hovering: false, popover: false, sharing: false, approvalsPending: false, turnHolds: false,
                                  typing: false), "composer: closes as before when not typing")
    let composer = appbugsSource("Aris/private/Aris/Home/ArisComposer.swift")
    check(!composer.contains("@State private var text") && composer.contains("ArisComposerDraft.shared")
          && composer.contains("text: $draft.text"), "composer wiring: the draft lives outside the view, so closing keeps it")
    check(appbugsSource("Aris/private/Notch/ArisNotchRoot+Behaviour.swift").contains("typing: ArisComposerDraft.shared.holdsNotch"),
          "composer wiring: the hover close asks the draft")
}

// MARK: - 3 and 9. Hot keys

private func appbugsHotKeyTests() {
    let prefs = appbugsSource("Aris/private/Notch/ArisPreferences.swift")
    check(prefs.contains("Self(\"toggleNotchOpen\")") && prefs.contains("Self(\"toggleSneakPeek\")") && !prefs.contains("modifiers: [.shift, .command]"),
          "hot keys: no ⇧⌘I / ⇧⌘H default on a new install")
    let entry = appbugsSource("Aris/private/App/ArisEntry.swift")
    check(!entry.contains("toggleAutoClose") && entry.contains("clickElsewhere = NSEvent.addGlobalMonitorForEvents"),
          "toggle: the shortcut's notch has no 3 s timer; a click in another app closes it")
}

// MARK: - 4. Clipboard history's cost

private func appbugsClipboardTests() {
    func item(_ bytes: Int, _ at: Double, pinned: Bool = false) -> ArisClipboard.Item {
        ArisClipboard.Item(id: UUID(), contents: [ArisClipboard.Content(type: "public.png", data: Data(count: bytes))], title: "",
                           app: nil, appBundle: nil, firstCopied: Date(timeIntervalSince1970: at), lastCopied: Date(timeIntervalSince1970: at),
                           pinned: pinned)
    }
    let big = ArisClipboard.itemLimit
    let images = (1...10).reduce([ArisClipboard.Item]()) { ArisClipboard.adding(item(big - $1, Double($1)), to: $0) }
    let held = images.reduce(0) { $0 + $1.size }
    check(held <= ArisClipboard.memoryLimit && images.count < 10 && images.first?.firstCopied == Date(timeIntervalSince1970: 10),
          "clipboard: big copies are bounded by memory too, the newest kept first")
    check(ArisClipboard.trimmed([item(ArisClipboard.memoryLimit + 1, 1)]).count == 1, "clipboard: the newest copy always stays")
    let withPin = ArisClipboard.trimmed(ArisClipboard.sorted([item(big, 1, pinned: true)] + (2...6).map { item(big - $0, Double($0)) }))
    check(withPin.contains { $0.pinned }, "clipboard: a pinned item is never trimmed")
    let model = appbugsSource("Aris/private/Aris/ArisClipboardModel.swift")
    check(model.contains("saving = Task.detached(priority: .utility)") && model.contains("nonisolated private static func save(")
          && model.contains("Task.detached(priority: .utility) {\n            let loaded = Self.load()") && model.contains("break reading"),
          "clipboard wiring: loading, encoding and writing are off the main thread; an oversized copy stops being read")
}

// MARK: - 5 and 7. The side windows: hit area and the pointer watch

private func appbugsSideTests() {
    typealias R = ArisSideEdgeRules
    check(!R.closedTakesMouse(revealed: false, onSliver: false, inPopover: false)
          && !R.closedTakesMouse(revealed: true, onSliver: false, inPopover: false),
          "side: the bare edge lets clicks through, sliver out or not")
    check(R.closedTakesMouse(revealed: true, onSliver: true, inPopover: false) && !R.closedTakesMouse(revealed: false, onSliver: true, inPopover: false),
          "side: the sliver takes clicks only once it shows")
    check(R.closedTakesMouse(revealed: false, onSliver: false, inPopover: true), "side: the popover takes clicks")
    let screens = [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: 1512, y: 0, width: 2560, height: 1440)]
    check(!R.moveMatters(pointer: CGPoint(x: 700, y: 400), screens: screens, busy: false, reach: 300),
          "side: a move in the middle of a display runs nothing")
    check(R.moveMatters(pointer: CGPoint(x: 1400, y: 400), screens: screens, busy: false, reach: 300)
          && R.moveMatters(pointer: CGPoint(x: 1600, y: 400), screens: screens, busy: false, reach: 300),
          "side: near either edge of the display the pointer is on, the move is checked")
    check(R.moveMatters(pointer: CGPoint(x: 700, y: 400), screens: screens, busy: true, reach: 300), "side: while a side shows, every move counts")
    check(!R.watchesMoves(sidesOn: 0) && R.watchesMoves(sidesOn: 1), "side: with every tab off nothing watches the pointer")
    let side = appbugsSource("Aris/private/Aris/Side/ArisSidePanels.swift")
    check(side.contains("ArisSideEdgeRules.closedTakesMouse(") && !side.contains("setIgnoresMouse(edge, !(near || inPopover))"),
          "side wiring: the closed window takes the pointer only on what shows")
    check(side.contains("moveWatch.forEach(NSEvent.removeMonitor)") && side.contains("guard ArisSideEdgeRules.moveMatters("),
          "side wiring: the move monitors come and go with the tabs, and a far move returns at once")
    let entry = appbugsSource("Aris/private/App/ArisEntry.swift")
    check(entry.contains("case .displaysAsleep(true): ArisStallWatch.shared.stop()")
          && appbugsSource("Aris/private/Platform/ArisStallWatch.swift").contains("func stop()"),
          "stall watch: no beat while the displays sleep")
}

// MARK: - 8. Hide from screen recording, every window

private func appbugsRecordingTests() {
    check(ArisCaptureSharing.recording(hidden: true) == .none && ArisCaptureSharing.recording(hidden: false) == .readWrite,
          "recording: hidden is out of captures, off is as usual")
    let followers = ["Aris/private/Aris/Side/ArisSidePanels.swift", "Aris/private/Aris/ArisBoard.swift", "Aris/private/Aris/ArisPermissionGuide.swift",
                     "Aris/components/Settings/ArisSettingsWindow.swift", "Aris/private/Aris/Onboarding/ArisOnboardingWindow.swift",
                     "Aris/private/Aris/Onboarding/ArisOnboardingOverlay.swift"]
    let missing = followers.filter { !appbugsSource($0).contains("ArisRecordingPrivacy.follow(") }
    check(missing.isEmpty, "recording wiring: the side panels, the reader, the guides and Settings follow the setting (missing: \(missing))")
}

// MARK: - 6. The updater

private func appbugsUpdateTests() {
    typealias I = ArisUpdateIdle
    check(!I.isIdle(I.Activity(notchOpen: true)) && !I.isIdle(I.Activity(settingsOpen: true)) && I.isIdle(I.Activity()),
          "update: never installs (and restarts) while the notch or Settings is open")
    check(!I.mayInstall(I.Activity(notchOpen: true), idleSince: Date(timeIntervalSince1970: 0), now: Date(timeIntervalSince1970: 1_000)),
          "update: an open notch holds the install however long it waited")
    check(ArisUpdatePolicy.signedForRelease(signer: "Aris Release (Lumen JS)") && !ArisUpdatePolicy.signedForRelease(signer: nil)
          && !ArisUpdatePolicy.signedForRelease(signer: "Apple Development: Someone (ABC123)"),
          "update: only a copy signed with the release certificate updates (a build from source is never overwritten)")
    let updater = appbugsSource("Aris/private/Aris/Update/ArisUpdater.swift")
    check(updater.contains("&& ArisUpdatePolicy.signedForRelease(signer: ArisUpdater.ownSigner())")
          && updater.contains("settingsOpen: ArisSettingsWindow.shared.visible"), "update wiring: the signer and the open windows are asked")
}

// MARK: - 10. Drops that aren't files; shelf files kept

private func appbugsDropTests() {
    check(ArisDropCopy.draft("", adding: ["https://q.exampleu.edu"]) == "https://q.exampleu.edu"
          && ArisDropCopy.draft("요약해 줘", adding: [" 첫 줄 ", ""]) == "요약해 줘\n첫 줄" && ArisDropCopy.draft("그대로", adding: []) == "그대로",
          "drop: text and links dropped on Aris go into the composer after what is typed")
    check(!ArisDropCopy.unreadable(english: false).isEmpty && ArisDropCopy.unreadable(english: true).hasPrefix("Aris couldn't"),
          "drop: a drop with nothing readable is said, in both languages")
    check(ArisShelfTempFiles.standardRoot.path.hasSuffix("Application Support/Aris/Shelf/Files")
          && ArisShelfTempFiles().root == ArisShelfTempFiles.standardRoot,
          "shelf: dropped pictures and text are kept in Application Support, not the temporary folder a reboot empties")
    let chips = appbugsSource("Aris/private/Aris/Home/ArisShelfChips.swift")
    check(chips.contains("ArisDropModel.shared.refused()") && chips.contains("ArisDropCopy.draft(draft.text, adding: texts)"),
          "drop wiring: Aris's half takes text and links into the composer and refuses the rest out loud")
}

// MARK: - 23, 24, 25. A replaced turn

private func appbugsTurnTests() {
    let card = ArisConfirmation(id: "c1", title: "Move to Trash", detail: "qa-trashthree")
    let working = ArisSession().listening().hearing("please qa-trashthree").thinking().working("Moving to the Trash").asking(card)
    let replaced = working.replaced()
    check(replaced.question == nil && replaced.steps.isEmpty, "replaced turn: its card goes and its cut-off step is never kept")
    check(replaced.answering("FAKE ANSWER").tags.allSatisfy { $0.label != "Moving to the Trash" },
          "replaced turn: an answer written over it never ticks the cut-off step")
    let finished = ArisSession().listening().hearing("a").thinking().working("웹 검색 중").working("파일 읽는 중")
    check(finished.replaced().steps.map(\.label) == ["웹 검색 중"], "replaced turn: a step that finished keeps its tick")
    let kernel = appbugsSource("Aris/private/Aris/ArisController+Kernel.swift")
    check(kernel.contains("writeReplacedTurnLine()") && kernel.contains("setSession(session.replaced(), from: id)"),
          "turn wiring: opening a turn writes the last one's line and starts from a clean session")
    let stats = appbugsSource("Aris/private/Aris/ArisController+Stats.swift")
    check(stats.contains("writeTurnLine(\"replaced\")"), "turns.jsonl: a replaced turn's line says replaced")
    let typed = appbugsSource("Aris/private/Aris/ArisController+Typed.swift")
    check(typed.contains("startTypedTurnClock(opened)"), "turns.jsonl: a typed turn's stage clock starts at submit")
    var clock = ArisStageClock()
    let start = ContinuousClock.now
    clock.begin(at: start)
    clock.mark(.requestSent, at: start + .milliseconds(40))
    clock.mark(.firstDelta, at: start + .milliseconds(900))
    let fields = clock.fields()
    check(fields["requestSentAtMs"] == 40 && fields["firstDeltaAtMs"] == 900 && fields["firstVoiceAtMs"] == nil && fields["firmEndAtMs"] == nil,
          "turns.jsonl: a typed turn has its request and first delta, and no voice-only stages")
}

// MARK: - 22. The preview harness

private func appbugsPreviewTests() {
    check(!ArisPreviewGate.enabled(bundleId: ArisUpdatePolicy.publicBundleId, debug: false), "preview: never in the public release")
    check(ArisPreviewGate.enabled(bundleId: ArisUpdatePolicy.publicBundleId, debug: true), "preview: a debug build keeps it")
    // rel11 (RISKS.md A): closed for every bundle id unless the build was compiled with DEBUG.
    for id in [ArisUpdatePolicy.publicBundleId, "com.lumenjsn.aris", "com.lumenjsn.aris", "com.example.owner", "com.lumenjsn.aris.dev", "", nil] as [String?] {
        check(!ArisPreviewGate.enabled(bundleId: id, debug: false), "preview: a build without DEBUG never listens (\(id ?? "no id"))")
    }
    let gate = appbugsSource("Aris/private/Aris/ArisPreviewGate.swift")
    check(gate.components(separatedBy: "#if ").count == 2 && gate.contains("#if DEBUG\n        let debug = true\n        #else\n        let debug = false"),
          "preview: the one compile flag that opens it is DEBUG")
    let project = appbugsSource("Aris.xcodeproj/project.pbxproj")
    check(project.components(separatedBy: "SWIFT_ACTIVE_COMPILATION_CONDITIONS").count == 2 && project.contains("SWIFT_ACTIVE_COMPILATION_CONDITIONS = \"DEBUG $(inherited)\";"),
          "preview: only the Debug configuration sets DEBUG")
    let preview = appbugsSource("Aris/private/Aris/ArisPreview.swift")
    check(preview.contains("guard ArisPreviewGate.here else { return }")
          && preview.contains("aris.setSession(ArisSession().listening().hearing(text).thinking())"),
          "preview wiring: nothing listens in the release; an intent turn starts from its own prompt")
}

// MARK: - 12 to 16. Settings and the setup guide

private func appbugsSettingsTests() {
    // 12: the uninstall takes the container's leftovers too, and waits a few seconds before anything irreversible.
    let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("appbugs-container-\(UUID().uuidString)")
    let support = scratch.appendingPathComponent("support"), caches = scratch.appendingPathComponent("caches")
    let places = ArisAppData.Places(support: support, caches: caches, bundleId: "com.example.aris")
    for folder in [places.arisFolder.appendingPathComponent("Whisper"), places.arisFolder.appendingPathComponent("wake-corpus"),
                   support.appendingPathComponent("boringNotch/Shelf"), caches.appendingPathComponent("com.example.aris")] {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    check(places.containerData().count == 3 && places.removeContainerData().isEmpty && places.containerData().isEmpty,
          "uninstall: the Whisper model, the wake recordings, the shelf and the caches go with the app")
    try? FileManager.default.removeItem(at: scratch)
    let model = appbugsSource("Aris/private/Aris/ArisDataModel.swift")
    check(model.contains("uninstallCountdown = left") && model.contains("func cancelUninstall()")
          && model.contains("guard uninstallCountdown != nil else { return }"),
          "uninstall: a countdown before the helper is asked, and 취소 stops it with nothing touched")
    let live = appbugsSource("Aris/private/Aris/ArisSettingsLive.swift")
    check(live.contains("ClaudeConnect.removeQuietly()") && live.contains("removeContainerData()"),
          "uninstall wiring: the app's Claude Code hooks and its container data go too")
    // 13: through the guide once, finished or put off.
    check(ArisOnboarding.pastFirstRun(seen: false, later: true) && ArisOnboarding.pastFirstRun(seen: true, later: false)
          && !ArisOnboarding.pastFirstRun(seen: false, later: false), "guide: closed early (put off) still lets the key taps and the wake word start")
    check(appbugsSource("Aris/private/App/ArisKeyTaps.swift").contains("ArisOnboarding.pastFirstRunNow")
          && appbugsSource("Aris/private/Aris/ArisController+Wake.swift").contains("onboardingSeen: ArisOnboarding.pastFirstRunNow"),
          "guide wiring: the taps and the wake word ask the same rule")
    // 14: the real home's folder, and the word list made through the user's own Save.
    let settings = appbugsSource("Aris/components/Settings/ArisLiveSettings.swift")
    check(!settings.contains("homeDirectoryForCurrentUser.appendingPathComponent(\".config/aris\")")
          && settings.contains("URL(fileURLWithPath: ArisKeyFile.folder, isDirectory: true)") && settings.contains("let panel = NSSavePanel()"),
          "settings: 기록 폴더 열기 opens the real ~/.config/aris; 내 단어 편집 makes the list on a fresh install")
    // 15: the gear follows its switch.
    check(ArisNotchHeaderLayout.placeCount(settingsIcon: true) == 3 && ArisNotchHeaderLayout.placeCount(settingsIcon: false) == 2
          && appbugsSource("Aris/private/Aris/Home/ArisNotchHeader.swift").contains("if settingsIcon {"),
          "settings: 노치에 설정 아이콘 off takes the gear out of the open notch")
    // 16: a failed Keychain read isn't kept.
    let keychain = appbugsSource("Aris/private/Aris/ArisKeychain.swift")
    check(keychain.contains("if cachesRead(status: status)") && keychain.contains("status == errSecSuccess || status == errSecItemNotFound"),
          "keychain: only a found key or a clear not-there is kept in memory")
}

// MARK: - 17 and 18. Permissions

private func appbugsPermissionTests() {
    typealias D = ArisPermissionDrift
    let needed = D.needed(seesScreen: true)
    check(needed.contains(.screen) && !D.needed(seesScreen: false).contains(.screen) && needed.contains(.listen),
          "permissions: the screen only while Aris may look; Input Monitoring for the key taps")
    check(D.lost(needed: needed, granted: [.microphone, .speech], before: nil).isEmpty, "permissions: no record yet, nothing said")
    let lost = D.lost(needed: needed, granted: [.microphone], before: D.record([.microphone, .speech, .accessibility]))
    check(lost == [.speech, .accessibility], "permissions: what was on last launch and is off now, in order")
    check(D.lost(needed: needed, granted: [.microphone], before: ["microphone"]).isEmpty, "permissions: never granted is not lost")
    let notice = D.notice(lost: lost, english: false)
    check(notice?.kind == .problem && notice?.actions.first?.role == .fixes([.pane(.speech), .pane(.accessibility)])
          && notice?.body.contains("음성 인식") == true && D.notice(lost: [], english: true) == nil,
          "permissions: one card, its button opening each list in turn")
    check(ArisFix.Pane.listen.anchor == "Privacy_ListenEvent" && ArisFix.Pane.listen.title(english: true) == "Input Monitoring",
          "permissions: Input Monitoring has its list")
    check(appbugsSource("Aris/private/App/ArisEntry.swift").contains("ArisPermissionDriftLive.checkAtLaunch()"), "permissions wiring: checked at launch")
    let taps = appbugsSource("Aris/private/App/ArisKeyTaps.swift")
    check(taps.contains("CGRequestListenEventAccess()") && taps.contains("pastFirstRun && !granted && !askedBefore"),
          "key taps: Input Monitoring is asked for once, only after the guide, and the wait says it isn't granted")
}

// MARK: - 19. Claude Code 연결

private func appbugsClaudeConnectTests() {
    typealias H = ClaudeHookSettings
    let script = "/Applications/Aris.app/Contents/Resources/aris-claude-hook.sh"
    let status = "/Applications/Aris.app/Contents/Resources/aris-claude-statusline.sh"
    let other: [String: Any] = ["type": "command", "command": "clawd-hook"]
    let start: [String: Any] = ["model": "opus", "hooks": ["Stop": [["matcher": "", "hooks": [other]]]]]
    let once = H.connecting(start, script: script, statusScript: status, replaceTheirs: false)
    check(H.connected(once) && once["model"] as? String == "opus", "claude connect: every event gets Aris's hook, the rest stays")
    let stop = (once["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]] ?? []
    check(stop.count == 2 && (stop.first?["hooks"] as? [[String: Any]])?.first?["command"] as? String == "clawd-hook",
          "claude connect: someone else's hook is kept")
    let data = (try? JSONSerialization.data(withJSONObject: once)) ?? Data()
    check(!String(decoding: data, as: UTF8.self).lowercased().contains("x-aris-token"), "claude connect: no token in settings.json")
    let permission = ((once["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]]
    check(permission?.first?["command"] as? String == "/bin/sh \"\(script)\" 130" && permission?.first?["timeout"] as? Int == 130,
          "claude connect: the approval waits past the card's 120 s")
    let twice = H.connecting(once, script: script, statusScript: status, replaceTheirs: false)
    check(NSDictionary(dictionary: once).isEqual(to: twice), "claude connect: running it again changes nothing")
    let theirs: [String: Any] = ["statusLine": ["type": "command", "command": "~/bin/my-line"]]
    check(H.statusLine(theirs) == .theirs("~/bin/my-line")
          && (H.connecting(theirs, script: script, statusScript: status, replaceTheirs: false)["statusLine"] as? [String: Any])?["command"] as? String == "~/bin/my-line"
          && H.statusLine(H.connecting(theirs, script: script, statusScript: status, replaceTheirs: true)) == .ours,
          "claude connect: someone else's status line is kept unless the user said to replace it")
    let old: [String: Any] = ["hooks": ["Stop": [["matcher": "", "hooks": [["type": "http", "url": H.url]]]],
                                        "SubagentStop": [["matcher": "", "hooks": [["type": "http", "url": H.url]]]]],
                              "statusLine": ["command": "/Users/x/.config/aris/statusline.sh"]]
    let upgraded = H.connecting(old, script: script, statusScript: status, replaceTheirs: false)
    let upgradedHooks = upgraded["hooks"] as? [String: Any] ?? [:]
    check(((upgradedHooks["Stop"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])?.count == 1 && upgradedHooks["SubagentStop"] == nil
          && H.statusLine(old) == .ours, "claude connect: an install from the script keeps its hook, loses the retired ones")
    let removed = H.disconnecting(once)
    check(!H.connected(removed) && removed["statusLine"] == nil && removed["model"] as? String == "opus"
          && ((removed["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])?.count == 1
          && (removed["hooks"] as? [String: Any])?["SessionStart"] == nil,
          "claude connect: disconnecting takes off only Aris's hooks and status line")
    check(H.backupName(stamp: "20261118-120000") == "settings.json.pre-aris.20261118-120000", "claude connect: a dated backup")
    let hook = appbugsSource("Aris/private/Claude/aris-claude-hook.sh")
    check(hook.contains("-H @/dev/fd/3") && hook.contains("claude-hook-token") && !hook.contains("-H \"X-Aris-Token: $token\""),
          "claude connect: the script reads the token from its 0600 file and never passes it as an argument")
    let row = ArisSettingsBuilder.sections(.aris, ArisSettingsSnapshot()).flatMap(\.rows).first { $0.id == "aris.claudeConnect" }
    check(row?.control == .status(ok: false, ArisSettingButton(title: "연결", action: .claudeConnect)), "claude connect: the Settings row offers 연결")
}

// MARK: - 20. A job's question when the helper doesn't answer

private func appbugsCardParkTests() {
    check(ArisParkedAsk.unreachableWait(tries: 1) == .seconds(5) && ArisParkedAsk.unreachableWait(tries: 3) == .seconds(20)
          && ArisParkedAsk.unreachableWait(tries: 20) == .seconds(300), "parked question: asked again after 5 s, doubling to 5 min")
    let park = appbugsSource("Aris/private/Aris/ArisController+CardPark.swift")
    check(!park.contains("case nil: return .unreachable") && park.contains("try? await Task.sleep(for: ArisParkedAsk.unreachableWait(tries: unreachable))"),
          "parked question: one failed check no longer drops it; it waits in 확인 대기")
}
