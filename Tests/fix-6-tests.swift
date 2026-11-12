// Tests for the defects the second upgrade run found in 126bc8fb (qa/vm-run-1111/REPORT-second-upgrade.md), fixed on
// fix-6.
// - vm2 1: the look reads the app he was in (the app's word, else the window server's order), never the helper's stale
//   NSWorkspace front app; a read whose window was no longer that app's topmost when it was over teaches no note.
// - vm2 2: a key saved for a thinking AI only picked doesn't make it the brain until it answered once; the API brain's
//   failure lines have their English; a quick commands key TypeSafe refuses is said on the status line.
// - vm2 3: a type whose text went in as the app types it is confirmed; one that changed the field but can't be matched
//   says it typed and couldn't check, never "nothing was added"; a request past the limit is said to be too long.
// - vm2 5: a to-do a tool adds is stored exactly as its card showed (only --due sets a date); his own to-do sentence
//   has a date read only from its start or end.
// - vm2 6: a <say> tag never shows, wherever the model put it; its words stay, and code keeps the tag as written.
// - vm2 7 (the smaller ones): the status line has two lines; a receipt shows once its place stands still; the AI
//   names the Activity tab in the answer's language; an idle API brain process ends after 5 minutes; the ledger
//   keeps the brain's id; the lock's hint is drawn inside the panel.
// Everything runs on values made here: no helper is asked, nothing is restarted, no window of the Mac is read.
// Called from main.swift; uses its check().
import Foundation

func runFix6Tests() {
    fix6FrontNowTests()
    fix6LookTrustTests()
    fix6FrontWiringTests()
    fix6KeyChoiceTests()
    fix6TypeOutcomeTests()
    fix6TodoTitleTests()
    fix6SayTagTests()
    fix6SmallerTests()
}

private let fix6Root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("..")

private func fix6Source(_ path: String) -> String {
    (try? String(contentsOf: fix6Root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

/// The lines of a source file that are code (a comment may name what the code no longer does).
private func fix6Code(_ path: String) -> String {
    fix6Source(path).split(separator: "\n", omittingEmptySubsequences: false)
        .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("///") }
        .joined(separator: "\n")
}

// MARK: - vm2 1: which app a look reads

/// One entry of CGWindowListCopyWindowInfo as the window server writes it.
private func fix6Listed(_ id: Int, pid: Int32, layer: Int, x: Double = 0, y: Double = 0, width: Double = 1024, height: Double = 678,
                        alpha: Double = 1, name: String? = nil) -> [String: Any] {
    var info: [String: Any] = ["kCGWindowNumber": NSNumber(value: id), "kCGWindowOwnerPID": NSNumber(value: pid), "kCGWindowLayer": NSNumber(value: layer),
                               "kCGWindowAlpha": NSNumber(value: alpha), "kCGWindowIsOnscreen": NSNumber(value: true),
                               "kCGWindowBounds": ["X": NSNumber(value: x), "Y": NSNumber(value: y), "Width": NSNumber(value: width), "Height": NSNumber(value: height)]]
    if let name { info["kCGWindowName"] = name }
    return info
}

private func fix6FrontNowTests() {
    typealias F = ArisFrontNow
    let aris: Int32 = 100, agent: Int32 = 50, safari: Int32 = 210, textEdit: Int32 = 220, finder: Int32 = 230, menuExtra: Int32 = 240
    let stepped: (Int32) -> Bool = { ArisLookTarget.steppedOver(pid: $0, bundleId: $0 == aris ? "com.lumenjsn.aris" : "", aris: aris, own: agent) }
    let ordinary: (Int32) -> Bool = { [safari, textEdit, finder, aris].contains($0) }

    // The run's own window list (/tmp/wl at 06:41): Safari's page on top, the memo and blank.txt under it, with the
    // menu bar, the notch and a menu bar extra above all of them.
    let recorded = [fix6Listed(1, pid: 1, layer: 24, width: 1024, height: 30), fix6Listed(2, pid: aris, layer: 27, x: 427, width: 170, height: 32),
                    fix6Listed(3, pid: menuExtra, layer: 25, width: 30, height: 24),
                    fix6Listed(41, pid: safari, layer: 0, y: 30, name: "Printing press - Wikipedia"),
                    fix6Listed(42, pid: textEdit, layer: 0, x: 80, y: 60, width: 700, height: 500, name: "garden-memo.txt"),
                    fix6Listed(43, pid: textEdit, layer: 0, x: 120, y: 90, width: 700, height: 500, name: "blank.txt"),
                    ["kCGWindowNumber": NSNumber(value: 99)]].compactMap(F.window)
    check(recorded.count == 6 && recorded[3] == F.Window(id: 41, pid: safari, layer: 0, width: 1024, height: 678),
          "vm2 1: the window server's entries are read by its own key names, front to back (one with no owner is left out)")
    check(F.lookTarget(told: safari, windows: recorded, steppedOver: stepped, ordinary: ordinary) == F.Target(pid: safari, window: 41, by: .app),
          "vm2 1: Safari just launched over the TextEdit memo, and Aris says he was in Safari: the look reads Safari's page, window 41")
    check(F.lookTarget(told: nil, windows: recorded, steppedOver: stepped, ordinary: ordinary) == F.Target(pid: safari, window: 41, by: .windows),
          "vm2 1: with no word from Aris the window server's order still says Safari, never what the helper's NSWorkspace remembered (TextEdit)")
    check(F.lookTarget(told: aris, windows: recorded, steppedOver: stepped, ordinary: ordinary)?.pid == safari
          && F.lookTarget(told: menuExtra, windows: recorded, steppedOver: stepped, ordinary: ordinary)?.pid == safari,
          "vm2 1: the notch's own windows above both are never read, nor a menu bar extra that shows nothing of its own")
    check(F.lookTarget(told: textEdit, windows: recorded, steppedOver: stepped, ordinary: ordinary) == F.Target(pid: textEdit, window: 42, by: .app),
          "vm2 1: when he was in TextEdit, its topmost window is read (garden-memo.txt), not blank.txt under it")

    // Aris's own reader window (layer 0, on top, Aris's) and a Safari helper's 1-point window: neither is "this".
    let reader = [fix6Listed(5, pid: aris, layer: 0, width: 600, height: 700), fix6Listed(6, pid: safari, layer: 0, width: 1, height: 1),
                  fix6Listed(41, pid: safari, layer: 0), fix6Listed(42, pid: textEdit, layer: 0)].compactMap(F.window)
    check(F.lookTarget(told: nil, windows: reader, steppedOver: stepped, ordinary: ordinary) == F.Target(pid: safari, window: 41, by: .windows),
          "vm2 1: Aris's reader on top and a dot-sized window of Safari's are stepped over: Safari's page is read")

    // A full-screen app: its window covers the display, under the menu bar.
    let fullScreen = [fix6Listed(1, pid: 1, layer: 24, width: 1512, height: 33), fix6Listed(51, pid: safari, layer: 0, width: 1512, height: 982),
                      fix6Listed(42, pid: textEdit, layer: 0)].compactMap(F.window)
    check(F.lookTarget(told: nil, windows: fullScreen, steppedOver: stepped, ordinary: ordinary)?.window == 51
          && F.lookTarget(told: safari, windows: fullScreen, steppedOver: stepped, ordinary: ordinary)?.window == 51,
          "vm2 1: a full-screen app is read like any other: its window is the topmost of an app")

    // Two displays: the window he used last (TextEdit, on the right display) comes first in the one list.
    let twoDisplays = [fix6Listed(61, pid: textEdit, layer: 0, x: 1512, y: 40, width: 900, height: 700),
                       fix6Listed(41, pid: safari, layer: 0, x: 0, y: 40)].compactMap(F.window)
    check(F.lookTarget(told: nil, windows: twoDisplays, steppedOver: stepped, ordinary: ordinary)?.pid == textEdit
          && F.lookTarget(told: safari, windows: twoDisplays, steppedOver: stepped, ordinary: ordinary) == F.Target(pid: safari, window: 41, by: .app),
          "vm2 1: on two displays the window order decides without a word from Aris, and Aris's word picks that app's window on the other display")
    check(F.lookTarget(told: finder, windows: twoDisplays, steppedOver: stepped, ordinary: ordinary)?.pid == textEdit,
          "vm2 1: an app Aris names that shows no window (Finder with only the desktop) is not \"this\": the topmost app's window is read")

    // The read is over: still that app's topmost window?
    let safariTarget = F.Target(pid: safari, window: 41, by: .app), byOrder = F.Target(pid: safari, window: 41, by: .windows)
    let raisedMemo = [fix6Listed(42, pid: textEdit, layer: 0), fix6Listed(41, pid: safari, layer: 0)].compactMap(F.window)
    let otherSafari = [fix6Listed(44, pid: safari, layer: 0), fix6Listed(41, pid: safari, layer: 0)].compactMap(F.window)
    check(F.confirmed(safariTarget, after: recorded, steppedOver: stepped, ordinary: ordinary) && F.confirmed(byOrder, after: recorded, steppedOver: stepped, ordinary: ordinary),
          "vm2 1: a look whose window is still the app's topmost after the read is confirmed")
    check(!F.confirmed(safariTarget, after: otherSafari, steppedOver: stepped, ordinary: ordinary)
          && !F.confirmed(safariTarget, after: [fix6Listed(42, pid: textEdit, layer: 0)].compactMap(F.window), steppedOver: stepped, ordinary: ordinary),
          "vm2 1: another window of the app on top, or the window gone, and the look is not confirmed")
    check(!F.confirmed(byOrder, after: raisedMemo, steppedOver: stepped, ordinary: ordinary) && F.confirmed(safariTarget, after: raisedMemo, steppedOver: stepped, ordinary: ordinary),
          "vm2 1: found by the order, it must still be on top of all; named by Aris, it must still be that app's own topmost")
    check(!F.confirmed(F.Target(pid: textEdit, window: 41, by: .app), after: recorded, steppedOver: stepped, ordinary: ordinary),
          "vm2 1: the window id and the pid must agree: Safari's window 41 is never TextEdit's read")

    // A key press's "which app is in front": the keyboard's app now, else the topmost app window.
    check(F.frontPid(focused: safari, windows: raisedMemo) == safari && F.frontPid(focused: nil, windows: raisedMemo) == textEdit
          && F.frontPid(focused: 0, windows: []) == nil,
          "vm2 1: the app in front for a key is the one Accessibility says has the keyboard now, else the topmost window's owner")
    check(F.bundlePath(executable: "/Applications/Safari.app/Contents/MacOS/Safari") == "/Applications/Safari.app"
          && F.bundlePath(executable: "/Applications/Safari.app/Contents/XPCServices/x.xpc/Contents/MacOS/x") == nil
          && F.bundlePath(executable: "/usr/bin/true") == nil,
          "vm2 1: a process's app is read from its program's own path when AppKit has nothing current to say")
    check(F.ordinary(bundlePath: "/Applications/Safari.app", info: ["CFBundleIdentifier": "com.apple.Safari"])
          && !F.ordinary(bundlePath: "/Applications/Bar.app", info: ["LSUIElement": true]) && !F.ordinary(bundlePath: "/Applications/D.app", info: ["LSBackgroundOnly": "1"])
          && !F.ordinary(bundlePath: nil, info: [:]),
          "vm2 1: an app with no Dock icon (LSUIElement, LSBackgroundOnly) is never the app a look reads")

    // The app's word: the app in front, or the one the notch's field took the keyboard from.
    check(ArisUserApp.pick(front: safari, own: aris, previous: nil) == safari && ArisUserApp.pick(front: aris, own: aris, previous: safari) == safari
          && ArisUserApp.pick(front: aris, own: aris, previous: nil) == nil && ArisUserApp.pick(front: nil, own: aris, previous: textEdit) == textEdit,
          "vm2 1: Aris names the app he was in: the one in front, or while he types into the notch the one he came from (else it doesn't say)")
    check(ArisLookTarget.steppedOver(pid: 7, bundleId: "com.lumenjsn.aris", aris: nil, own: agent) && !ArisLookTarget.steppedOver(pid: 7, bundleId: "com.apple.Safari", aris: nil, own: agent),
          "vm2 1: Aris's own windows are stepped over by its bundle id too")

    // The read names its window, and the tool reads exactly that one or nothing.
    typealias S = ArisScreenTarget
    let listed = [S.Listed(number: 2, pid: aris, layer: 27), S.Listed(number: 41, pid: safari, layer: 0), S.Listed(number: 42, pid: textEdit, layer: 0)]
    check(ArisLookTarget.screenArguments(pid: safari, window: 41) == ["screen", "--pid", "210", "--window", "41"],
          "vm2 1: the look's read names the app and the window it means")
    check(S.window(requested: "41", pid: safari, windows: listed) == .window(41) && S.window(requested: nil, pid: textEdit, windows: listed) == .window(42)
          && S.window(requested: nil, pid: finder, windows: listed) == nil,
          "vm2 1: `screen --pid` reads the window named, or the app's topmost own one")
    check(S.window(requested: "42", pid: safari, windows: listed) == .refused(S.windowGone("42")) && S.window(requested: "2", pid: aris, windows: listed) == .refused(S.windowGone("2"))
          && S.window(requested: "", pid: safari, windows: listed) == .refused(S.windowUsage),
          "vm2 1: a window that is not that app's own window on screen is never read in its place")
}

private func fix6LookTrustTests() {
    let confirmed = ArisLook(app: "Safari", window: "Printing press", selection: nil, editable: false, tab: "https://en.wikipedia.org", screen: nil)
    var unconfirmed = confirmed
    unconfirmed.confirmed = false
    check(!confirmed.context.contains(ArisLookTrust.unconfirmedLine)
          && unconfirmed.context.components(separatedBy: "\n").prefix(2) == ["Front app: Safari", ArisLookTrust.unconfirmedLine],
          "vm2 1: a look that could not be confirmed says so to the AI, at its top where no cut of the screen text loses it")
    let prompt = { (look: ArisLook) in "User: summarize this\n\nOn screen:\n" + look.context }
    check(ArisLookTrust.keepsNotes(prompt: prompt(confirmed)) && !ArisLookTrust.keepsNotes(prompt: prompt(unconfirmed)) && ArisLookTrust.keepsNotes(prompt: nil),
          "vm2 1: a turn over an unconfirmed look keeps no note (the garden memo was learned as Safari's front window); any other turn may")
}

private func fix6FrontWiringTests() {
    let helperAndTools = ["ArisAgent/ArisLook.swift", "ArisAgent/ArisFocusedField.swift", "ArisAgent/ArisInsert.swift", "ArisAgent/ArisDesktopLive.swift",
                          "ArisAgent/ArisQuietOpener.swift", "ArisAgent/main.swift", "ArisTools/ArisWindows.swift", "ArisTools/ArisScreen.swift",
                          "ArisTools/ArisNoteCommand.swift", "ArisTools/main.swift"]
    let stale = helperAndTools.filter { fix6Code($0).contains("frontmostApplication") || fix6Code($0).contains(".isActive") }
    check(stale.isEmpty, "vm2 1: no part of the helper or the tools asks NSWorkspace which app is in front (stale there): \(stale)")
    let allAgent = (try? FileManager.default.contentsOfDirectory(atPath: fix6Root.appendingPathComponent("ArisAgent").path)) ?? []
    let anyStale = allAgent.filter { $0.hasSuffix(".swift") && fix6Code("ArisAgent/" + $0).contains("frontmostApplication") }
    let toolsFiles = (try? FileManager.default.contentsOfDirectory(atPath: fix6Root.appendingPathComponent("ArisTools").path)) ?? []
    let anyToolStale = toolsFiles.filter { $0.hasSuffix(".swift") && fix6Code("ArisTools/" + $0).contains("frontmostApplication") }
    check(allAgent.count > 100 && anyStale.isEmpty && anyToolStale.isEmpty, "vm2 1: nor any other file of theirs: \(anyStale + anyToolStale)")
    let look = fix6Code("ArisAgent/ArisLook.swift"), main = fix6Code("ArisAgent/main.swift")
    check(look.contains("ArisFrontNow.lookTarget(told: told, windows: ArisFrontLive.windows()") && look.contains("look.confirmed = ArisFrontNow.confirmed(target, after: ArisFrontLive.windows()")
          && look.contains("ArisLookTarget.screenArguments(pid: pid, window: windowId)"),
          "vm2 1: wiring: the look reads the target's own window and checks it again once the read is over")
    check(main.contains("told: (object[\"front\"] as? Int).flatMap { Int32(exactly: $0) })") && main.contains("\"confirmed\": look.confirmed"),
          "vm2 1: wiring: /look takes the app Aris names and says whether the read was confirmed")
    let runner = fix6Code("ArisAgent/ArisAgentRunner.swift")
    check(runner.contains("let lookUnconfirmed = !ArisLookTrust.keepsNotes(prompt: asked?.prompt)") && runner.contains("if !noted.notes.isEmpty, !handsFreeTurn, !lookUnconfirmed {"),
          "vm2 1: wiring: notes from a turn over an unconfirmed look are never kept")
    let app = fix6Code("Aris/private/Aris/ArisController+Look.swift"), client = fix6Code("Aris/private/Aris/ArisAgentClient.swift")
    check(app.contains("ArisAgentClient.look(front: ArisUserApp.pick(front: NSWorkspace.shared.frontmostApplication?.processIdentifier")
          && app.contains("previous: ArisPanelKeys.focus.previous") && client.contains("identified(front.map { [\"front\": Int($0)] } ?? [:])"),
          "vm2 1: wiring: the app tells the helper which app he was in")
    check(fix6Code("ArisTools/ArisScreen.swift").contains("ArisScreenTarget.window(requested:") && fix6Code("ArisTools/ArisWindows.swift").contains("guard ArisFrontNow.keysGo(focused: ArisFrontLive.focusedPid(), target: target.processIdentifier) else {"),
          "vm2 1: wiring: the tool reads only the window named, and each key checks the app in front at that moment")
    let build = (try? String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("build-agent.sh"), encoding: .utf8)) ?? ""
    check(build.contains("\"$SRC/ArisAgent/ArisFrontNow.swift\" \"$SRC/ArisAgent/ArisFrontLive.swift\""), "vm2 1: aris-tools is built with the same source of the app in front")
}

// MARK: - vm2 2: a made-up key for another provider

private func fix6KeyChoiceTests() {
    typealias K = ArisAIKeyChoice
    check(!K.activatesOnSave(holder: "groq", pending: "api:groq", think: "api:groq"),
          "vm2 2: a key saved for Groq while DeepSeek thinks (Groq only picked) does not make Groq the brain")
    check(K.activatesOnSave(holder: "deepseek", pending: nil, think: "api:deepseek") && !K.activatesOnSave(holder: "groq", pending: nil, think: "api:deepseek"),
          "vm2 2: a new key for the brain in use replaces its key there; a key for a provider not chosen changes nothing")
    check(K.waits(.key) && K.waits(.install) && K.waits(.check) && !K.waits(.soon) && !K.waits(.model),
          "vm2 2: a pick whose key has never answered waits like one with no key: the working brain goes on answering")

    typealias W = ArisAPIFailureWords
    let korean = W.line(.key, title: "Groq", english: false)
    check(korean == "Groq API 키가 맞지 않아요. 설정 › AI 서비스 › 두뇌에서 키를 다시 넣어 주세요." && W.english(korean) == W.line(.key, title: "Groq", english: true),
          "vm2 2: the refused-key line has its English, the service named as it was")
    check(W.Kind.allCases.allSatisfy { kind in
        let english = W.english(W.line(kind, title: "My server (LAN)", english: false)) ?? ""
        return english == W.line(kind, title: "My server (LAN)", english: true) && !english.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) }
    } && W.english("Groq: rate limit") == nil,
          "vm2 2: every API failure line reads back in English with no Hangul left; any other line is not taken for one")
    check(ArisBrainFailure.english(korean, brain: .api) == "Groq didn't accept its API key. Enter the key again in Settings › AI services › Thinking.",
          "vm2 2: an English request's failure line is English (it was “Groq API 키가 맞지 않아요…” on an English Mac)")
    let driver = fix6Code("ArisAgent/ArisAPIDriver.swift")
    check(driver.contains("return .failure(ArisAPIFailureWords.line(.key, title: title, english: false))")
          && !driver.contains("API 키가 맞지 않아요") && !driver.contains("닿지 못했어요") && !driver.contains("대화가 너무 길어져서"),
          "vm2 2: wiring: the driver's failure lines come from the one table")

    typealias H = ArisRouterKeyHealth
    check(H.after(status: 401) == .some(.rejected) && H.after(status: 403) == .some(.rejected) && H.after(status: 200) == .some(nil)
          && H.after(status: nil) == .none && H.after(status: 503) == .none,
          "vm2 2: TypeSafe's 401 makes the quick commands key refused, an answer clears it, no answer or a server error says nothing")
    let suite = "aris-fix6-router-tests"
    if let defaults = UserDefaults(suiteName: testSuiteName(suite)) {
        defaults.removePersistentDomain(forName: testSuiteName(suite))
        H.write(.unchecked, defaults)
        H.note(status: 503, defaults)
        let afterServerError = H.read(defaults)
        H.note(status: 401, defaults)
        let refused = H.read(defaults)
        H.note(status: 200, defaults)
        check(afterServerError == .unchecked && refused == .rejected && H.read(defaults) == nil, "vm2 2: the key's state is kept as its answers say")
        defaults.removePersistentDomain(forName: testSuiteName(suite))
    }
    typealias G = ArisSettingsCaption
    check(G.greeting(agentDown: false, missingPermissions: 0, quickKey: .refused) == G.quickKeyRefused
          && G.greeting(agentDown: false, missingPermissions: 0, quickKey: .unchecked) == G.quickKeyUnchecked
          && G.greeting(agentDown: false, missingPermissions: 0) == "모두 잘 되고 있어요"
          && G.greeting(agentDown: false, missingPermissions: 0, noAI: true, quickKey: .refused) == G.noAI
          && G.asksForAI(G.quickKeyRefused),
          "vm2 2: a quick commands key TypeSafe refused is never “Everything is working”; the AI comes first, and the line opens AI services")
    let live = fix6Code("Aris/components/Settings/ArisAIServicesLive.swift"), router = fix6Code("Aris/private/Aris/ArisRouter.swift")
    check(live.contains("let becomesBrain = ArisAIKeyChoice.activatesOnSave(holder: holder, pending: pendingThink, think: model.state.choices.think)")
          && live.contains("ArisAICatalogue.lack(provider, in: model.state), ArisAIKeyChoice.waits(lack)")
          && live.contains("ArisRouterKeyHealth.write(.unchecked)") && router.contains("ArisRouterKeyHealth.note(status: status == 0 ? nil : status)"),
          "vm2 2: wiring: a picked provider's key is saved without making it the brain, and the quick commands key is checked")
    let xc = fix6Source("Aris/components/Settings/Settings.xcstrings")
    check(xc.contains("\"빠른 명령 키가 맞지 않아요\"") && xc.contains("The quick commands key doesn't work") && xc.contains("The quick commands key hasn't answered yet"),
          "vm2 2: the new lines have their English")
}

// MARK: - vm2 3: the type card's outcome, and a long request

private func fix6TypeOutcomeTests() {
    typealias R = ArisTypeReadback
    let typed = "start\nseven bakers sell fresh loaves near the quiet river \"daily\" -- it's true\nfinish"
    let asTextEditKeeps = "Start\nSeven bakers sell fresh loaves near the quiet river \u{201C}daily\u{201D} -- it\u{2019}s true \nFinish"
    let capitalised = R.result(typed, app: "TextEdit", before: "", after: asTextEditKeeps)
    check(capitalised.ok && capitalised.line.contains("the app's own capitals"),
          "vm2 3: text TextEdit capitalised, with its curly quotes and a trailing space, is confirmed typed")
    let dropped = R.result("Aunt fresh loaves near the quiet river", app: "TextEdit", before: "", after: "Unt fresh loaves near the quiet river")
    check(!dropped.ok && dropped.line.hasPrefix(R.notConfirmedLead) && dropped.line.contains("입력했어요. 다만 그대로 들어갔는지는 확인하지 못했어요.")
          && dropped.line.contains("I typed it, but I couldn't check that it went in exactly as written.") && !dropped.line.hasPrefix(R.notTypedLead),
          "vm2 3: a field that changed but lost a character says it typed and couldn't check, never that it wasn't typed")
    check(R.notConfirmedLead.contains("never say nothing was added") && !R.notConfirmedLead.contains("don't tell the user it was typed"),
          "vm2 3: the brain is told never to say nothing was added when the keys went in")
    let unreadable = R.result(typed, app: "TextEdit", before: nil, after: nil)
    check(!unreadable.ok && unreadable.line.hasPrefix(R.notConfirmedLead) && unreadable.line.contains("그대로 들어갔는지는 확인하지 못했어요"),
          "vm2 3: a field that can't be read back: typed, not checked")
    let untouched = R.result(typed, app: "TextEdit", before: "Dear club", after: "Dear club")
    check(!untouched.ok && untouched.line.hasPrefix(R.notTypedLead), "vm2 3: only a field that shows no change at all is \"not typed\"")
    check(!R.landedAsTheAppTypes("hello world", before: "", after: "hello") && R.landedAsTheAppTypes("hello  world", before: "", after: "Hello world"),
          "vm2 3: the app's own changes are only case, quotes, dashes and spaces: a missing word is not one")

    let main = fix6Code("ArisAgent/main.swift")
    check(main.contains("let maxText = 20_000") && ArisAgentCopy.requestLimit == 20_000,
          "vm2 3: a pasted page of up to 20,000 characters is taken (it was 2,000), and the app knows the same limit")
    check(main.contains("return respond(connection, \"413 Payload Too Large\"") && fix6Code("Aris/private/Aris/ArisAgentClient.swift").contains("status == 413 ? ArisAgentCopy.tooLong() : refused"),
          "vm2 3: wiring: a longer one is answered 413 and said as too long, never \"didn't take the request\"")
    check(ArisAgentCopy.tooLong(english: true) == "That request is too long: Aris takes up to 20,000 characters at a time. Please send it in parts."
          && ArisAgentCopy.tooLong(english: false).contains("20,000자"),
          "vm2 3: the too-long line names the limit, in the UI's language")
    check(main.components(separatedBy: "learnFrom: clean && request.count <= maxLearned ? request : nil").count == 3 && main.contains("let maxLearned = 2_000"),
          "vm2 3: memory still learns only from requests of a spoken length: a pasted page is no fact about him")
}

// MARK: - vm2 5: the stored to-do is the one the card showed

private func fix6TodoTitleTests() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 7, minute: 52))!
    let orlando = "Check Orlando weather - drizzle today, 70% chance of rain"
    let read = ArisTodoDate.titled(orlando, now: now, calendar: calendar)
    check(read.text == orlando && read.due == nil,
          "vm2 5: “\(orlando)” keeps every word and no due date (it was stored as “…drizzle , 70% chance of rain” due today)")
    check(ArisTodoDate.titled("Check Orlando weather — drizzle today, 70% chance of rain", now: now, calendar: calendar).due == nil
          && ArisTodoDate.titled("call mom today about the trip", now: now, calendar: calendar).due == nil,
          "vm2 5: a date word in the middle of the words stays in the title")
    let edges: [(String, String)] = [("buy milk today", "buy milk"), ("today buy milk", "buy milk"), ("내일까지 보고서", "보고서"), ("우유 사기 내일", "우유 사기"),
                                     ("call mom tomorrow at 5pm", "call mom")]
    for (typed, title) in edges {
        let edge = ArisTodoDate.titled(typed, now: now, calendar: calendar)
        check(edge.text == title && edge.due != nil, "vm2 5: his own “\(typed)” still has its date read at an edge (read: “\(edge.text)”)")
    }
    let middle = ArisTodoDate.atAnEdge(("drizzle , rain", now), of: "drizzle today, rain")
    check(middle.text == "drizzle today, rain" && middle.due == nil,
          "vm2 5: a read that took words out of the middle is not used")
    let handler = fix6Code("Aris/private/Aris/ArisTodoRouteHandler.swift"), model = fix6Code("Aris/private/Aris/ArisTodoModel.swift")
    check(handler.contains("var draft = ArisTodoModel.draft(title: request.text ?? \"\")") && !handler.contains("draft(from:")
          && model.contains("static func draft(title text: String) -> ArisTodoDraft {"),
          "vm2 5: wiring: a tool's `todo add` stores its title as given; the due date comes only from --due")
}

// MARK: - vm2 6: <say> shown as text

private func fix6SayTagTests() {
    typealias S = ArisSpeakable
    let line = "A fridge works by moving heat out of the box and dumping it into your kitchen, using a refrigerant that boils and condenses in a loop."
    let answer = "Here's how a refrigerator works.\n<say>\(line)</say>\n\n## The loop\n- The refrigerant boils inside.\n- It condenses behind the fridge."
    for handling in [S.SayHandling.honour, .unwrap, .keep] {
        let shown = S.shown(answer, korean: false, say: handling)
        check(!shown.lowercased().contains("<say>") && !shown.lowercased().contains("</say>") && shown.contains(line) && shown.contains("## The loop")
              && shown.hasPrefix("Here's how a refrigerator works."),
              "vm2 6: a <say> line after a sentence shows as its words, never as markup (\(handling)): what the notch, the reader, the copy, the history and a saved file get")
    }
    check(S.withoutSayTags(answer) == S.shown(answer, korean: false, say: .unwrap) || !S.withoutSayTags(answer).contains("<say>"),
          "vm2 6: the notch's drawing of a kept answer has no tag either")
    let unclosed = "Here's the short of it. <say>A fridge moves heat out of the box.\nMore below."
    check(S.withoutSay(unclosed, .unwrap) == "Here's the short of it. A fridge moves heat out of the box.\nMore below." && S.withoutSay("Done.</SAY>", .honour) == "Done."
          && S.withoutSayTags("It moves heat.</sa") == "It moves heat." && S.withoutSayTags("It moves heat. <say") == "It moves heat. ",
          "vm2 6: an unclosed, stray or half-arrived tag never shows")
    check(S.withoutSay("<say>Short line.</say>\nThe full answer.", .honour) == "The full answer." && S.withoutSay("<say>Short line.</say>\nThe full answer.", .unwrap) == "Short line.\nThe full answer.",
          "vm2 6: a leading line is honoured as before")
    check(S.withoutSayTags("Use `<say>` at the start.") == "Use `<say>` at the start." && S.withoutSayTags("```\n<say>x</say>\n```") == "```\n<say>x</say>\n```",
          "vm2 6: code that shows the tag keeps it")
    check(S.withoutSayTags("<say>\nHi.\n</say>\nMore.") == "Hi.\nMore." || !S.withoutSayTags("<say>\nHi.\n</say>\nMore.").contains("<"),
          "vm2 6: a tag on a line of its own leaves no markup")
    check(!S.speakable(answer).lowercased().contains("say>") && S.speakable(answer).contains("A fridge works"), "vm2 6: the voice never reads a tag")
}

// MARK: - vm2 7: the smaller ones

private func fix6SmallerTests() {
    let sidebar = fix6Code("Aris/components/Settings/ArisSettingsSidebar.swift")
    check(sidebar.contains(".lineLimit(ArisSettingsCaption.prerequisite(status) == nil ? 2 : 3)"),
          "vm2 7: the sidebar's status line wraps to two lines (it read “Aris's helper isn't answe…”)")

    let now = Date(timeIntervalSince1970: 1_000)
    check(!ArisReceiptSettle.shows(shown: false, movedAt: now, now: now.addingTimeInterval(0.2))
          && ArisReceiptSettle.shows(shown: false, movedAt: now, now: now.addingTimeInterval(0.5))
          && ArisReceiptSettle.shows(shown: true, movedAt: now, now: now),
          "vm2 7: a receipt comes up only once its place has stood still half a second, and once up a move doesn't take it away")
    let row = fix6Code("Aris/private/Aris/Home/ArisReceiptRow.swift")
    check(row.contains(".opacity(visible ? 1 : 0)") && row.contains(".allowsHitTesting(visible)") && row.contains("$0.frame(in: .global).minY"),
          "vm2 7: wiring: the row keeps its room at once and is seen and pressed only once still")
    let clock = ArisReceiptClock()
    let hovered = (0..<100).reduce(clock) { held, _ in held.ticking(hovering: true, speaking: false, undoing: false) }
    check(ArisReceiptClock.stay == 5 && !hovered.isOver(failed: false) && ArisReceiptClock.longestHover == 30,
          "vm2 7: a receipt stays 5 s of its own clock, which stands still while the pointer is on it (up to 30 s)")

    check(ArisAgentPrompt.pastJobsRule.contains("Activity tab") && ArisAgentPrompt.pastJobsRule.contains("only when you answer in Korean"),
          "vm2 7: the AI names the Activity tab in English (it wrote “the 한 일 tab” in an English answer)")
    check(ArisAPIDriver.idleLife == 300 && fix6Code("ArisAgent/ArisAgentRunner.swift").contains("private var idleLimit: TimeInterval { brain == .api ? ArisAPIDriver.idleLife : Self.idleTimeout }")
          && !fix6Code("ArisAgent/ArisAgentRunner.swift").contains("after: Self.idleTimeout"),
          "vm2 7: an idle `aris-agent api-brain` process ends after 5 minutes (three were left half an hour after Aris quit)")
    let routes = fix6Code("ArisAgent/ArisMCPRoutes.swift")
    check(routes.contains("var brainName: String { runner.brain.rawValue }") && routes.contains("var brainName: String { ArisBrain.antigravity.rawValue }")
          && !routes.contains("brain.title }"),
          "vm2 7: the ledger keeps the brain's id (\"api\"), never “API 브레인” on an English Mac")
    let panel = fix6Code("Aris/private/Aris/Side/ArisSidePanelView.swift")
    check(panel.contains("ArisLockHint(text: lockHint)") && !panel.contains(".help(panels.pinned.contains(edge)"),
          "vm2 7: the lock's hint is drawn inside the panel, never past the screen's edge")
    check(fix6Code("Aris/private/Aris/Side/ArisSidePanels.swift").contains("for edge in open where !pinned.contains(edge) && !holdOpen {"),
          "vm2 7: an open side panel closes on a click outside it unless locked open, as designed (leaving with the pointer keeps it)")
}
