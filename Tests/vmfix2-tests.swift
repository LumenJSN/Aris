// jv-vmfix2: the defects the VM run of 2026-11-19 found under Core 2 (aris-vmcheck/notes/c2-*.log).
// D2 the switches the helper obeys are the app's settings, sent over the app↔helper channel; D4 a desktop batch is as
// strong as its strongest part; D5 the day in review; D7 the message card; the fast lane's words.

import Foundation

private func vmfixSource(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../")
    return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

// MARK: - D2: the switches

private func vmfixSwitchTests() {
    // The cause: the helper read `arisCore2` from its own defaults, which neither the app's Settings nor a `defaults
    // write` of either domain reached. Now the helper obeys only what the app sent: a value in its defaults is nothing.
    let saved = ArisHelperSwitches.shared.set
    defer { ArisHelperSwitches.shared.adopt(environment: [ArisSwitchSet.environmentKey: saved.environmentValue ?? ""]) }
    ArisHelperSwitches.shared.adopt(environment: [:])
    UserDefaults.standard.set(true, forKey: "arisCore2")
    UserDefaults.standard.set(true, forKey: "arisTeach")
    check(!ArisCore2.isOn() && !ArisTrustSwitch.isOn() && !ArisTeachSwitch.isOn(),
          "switches: a helper the app hasn't spoken to runs with every switch off, whatever its defaults say")
    UserDefaults.standard.removeObject(forKey: "arisCore2")
    UserDefaults.standard.removeObject(forKey: "arisTeach")

    let switches = ArisHelperSwitches()
    check(switches.take(["arisCore2": true], fromApp: false).isEmpty && !switches.isOn(.core2), "switches: only the app itself turns one on")
    check(switches.take(["arisCore2": true, "arisTeach": "yes", "other": true], fromApp: true) == [.core2] && switches.isOn(.core2) && !switches.isOn(.teach),
          "switches: only a true of a known switch turns it on")
    check(switches.take("on", fromApp: true).isEmpty && switches.isOn(.core2), "switches: a field that is no object changes nothing")
    check(switches.take([:], fromApp: true) == [.core2] && !switches.isOn(.core2), "switches: the app's set is whole: a switch it doesn't name is off")

    // The app sends them, the helper's children take them from their environment.
    ArisHelperSwitches.shared.take(["arisCore2": true, "arisTeach": true], fromApp: true)
    check(ArisCore2.isOn() && ArisTrustSwitch.isOn() && ArisTeachSwitch.isOn(), "switches: Core 2 and show it once on, as the app sent them")
    let child = ArisHelperSwitches()
    child.adopt(environment: [ArisSwitchSet.environmentKey: ArisHelperSwitches.shared.set.environmentValue ?? ""])
    check(child.isOn(.core2) && child.isOn(.teach), "switches: a child started by the helper has the helper's switches")
    child.adopt(environment: [:])
    check(!child.isOn(.core2), "switches: a child started by anyone else has none")
    ArisHelperSwitches.shared.take(["arisCore2": false, "arisTeach": true], fromApp: true)
    check(!ArisTeachSwitch.isOn(), "switches: show it once works only with Core 2 on")

    check(ArisSwitchEffects.brainsToRetire([.core2]).sorted { $0.rawValue < $1.rawValue } == [.api, .claude] && ArisSwitchEffects.brainsToRetire([.teach]).isEmpty,
          "switches: Core 2 changed retires the brains it changes (their runners chose their driver when they started)")
    var retired: [ArisBrain] = []
    let local = ArisHelperSwitches()
    ArisSwitchEffects.take([ArisSwitchSet.field: ["arisCore2": true]], fromApp: true, switches: local) { retired.append($0) }
    ArisSwitchEffects.take([ArisSwitchSet.field: ["arisCore2": true]], fromApp: true, switches: local) { retired.append($0) }
    check(retired.count == 2, "switches: a change retires once; the same set again retires nothing")

    // The app's side: it owns them and sends them with /health, /warm and /ask.
    let client = vmfixSource("Aris/private/Aris/ArisAgentClient.swift")
    check(client.components(separatedBy: "request.httpBody = healthBody").count == 3 && client.contains("ArisSwitchSet.field: switches,")
          && client.contains("body[ArisSwitchSet.field] = switches"), "switches: the app sends them with every /health, /warm and /ask")
    let main = vmfixSource("ArisAgent/main.swift")
    check(main.components(separatedBy: "ArisSwitchEffects.take(object").count == 4, "switches: the helper takes them on /health, /warm and /ask")
    check(vmfixSource("ArisAgent/ArisAgentRunner.swift").contains("environment[ArisSwitchSet.environmentKey] = ArisHelperSwitches.shared.set.environmentValue"),
          "switches: the helper's children get them in their environment")
    for path in ["ArisAgent/ArisCapabilityCore2.swift", "ArisAgent/Trust/ArisTrustGate.swift", "ArisAgent/Teach/ArisTeachStore.swift", "ArisAgent/ArisHandsFace.swift"] {
        check(!vmfixSource(path).contains("defaults write aris-agent"), "switches: \(path) documents no `defaults write` that never reached the helper")
    }

    // The owner's voice had the ElevenLabs voice's key: picking a voice turned it off, a voice id starting with a digit on.
    check(ArisVoiceID.key != ArisAIPrefKey.voiceID, "switches: 내 목소리만 듣기 has a key of its own, not the speaking voice's")
}

private func vmfixLabsSettingTests() {
    let sections = ArisSettingsBuilder.sections(part: "able.control", ArisSettingsSnapshot())
    let labs = sections.first { $0.id == ArisLabsSetting.sectionID }
    check(labs?.heading == "실험 기능" && labs?.rows.map(\.id) == [ArisLabsSetting.core2ID, ArisLabsSetting.teachID],
          "labs: 컴퓨터 제어 has a 실험 기능 section with Core 2 and show it once")
    check(labs?.rows.map(\.control) == [.toggle(.core2, false), .toggle(.teach, false)], "labs: both off by default")
    check(labs?.rows.allSatisfy { ($0.desc ?? "").count > 10 } == true, "labs: each says in one line what it changes")
    check(ArisSettingsParts.all.first { $0.id == "able.control" }?.rows.contains(ArisLabsSetting.core2ID) == true, "labs: the part lists its rows")
    check(ArisSettingsIndex.search("Core 2").first?.id == ArisLabsSetting.core2ID && ArisSettingsIndex.search("가르치기").contains { $0.id == ArisLabsSetting.teachID }
          && ArisSettingsIndex.search("실험").contains { $0.id == ArisLabsSetting.core2ID }, "labs: a search finds them")
    let catalog = vmfixSource("Aris/components/Settings/Settings.xcstrings")
    for words in [ArisLabsSetting.heading, ArisLabsSetting.note, ArisLabsSetting.core2Title, ArisLabsSetting.core2Detail, ArisLabsSetting.teachTitle, ArisLabsSetting.teachDetail] {
        check(catalog.contains("\"\(words)\""), "labs: \(words) has English")
    }
    var on = ArisSettingsSnapshot()
    on.core2 = true
    check(ArisSettingsBuilder.sections(part: "able.control", on).first { $0.id == ArisLabsSetting.sectionID }?.rows.first?.control == .toggle(.core2, true),
          "labs: the row shows the stored switch")
    if let defaults = UserDefaults(suiteName: testSuiteName("aris-vmfix2-tests")) {
        check(ArisSwitchSet.stored(in: defaults) == ArisSwitchSet(), "labs: nothing stored is all off")
        defaults.set(true, forKey: ArisExperimentSwitch.core2.rawValue)
        check(ArisSwitchSet.stored(in: defaults).json == ["arisCore2": true, "arisTeach": false], "labs: what the row stored is what the app sends")
        defaults.removeObject(forKey: ArisExperimentSwitch.core2.rawValue)
    }
}

// MARK: - D4: a desktop call is as strong as its strongest part

private func vmfixDesktopEffectTests() {
    let batch = ArisCapabilityBook.entry(named: "desktop_batch")
    let replaceAll: [String: Any] = ["app": "TextEdit", "steps": "click @s1abcd:e3\npress cmd+a\ntype @s1abcd:e3 코어2 테스트"]
    let append: [String: Any] = ["app": "TextEdit", "steps": "press cmd+down\ntype @s1abcd:e3 코어2 테스트"]
    check(batch?.effect(replaceAll) == .changePermanent, "desktop: click, cmd+a, type replaces the document: change-permanent (it was change-reversible)")
    check(batch?.effect(append) == .changeReversible, "desktop: cmd+down, type adds at the end: change-reversible")
    check(batch?.effect(["app": "TextEdit", "steps": "press cmd+a delete"]) == .changePermanent, "desktop: one press that selects and deletes is permanent")
    check(batch?.effect(["app": "TextEdit", "steps": "type @s1abcd:e3 안녕\nset-value @s1abcd:e4 새 값"]) == .changePermanent,
          "desktop: a batch is its strongest step (set-value replaces a field's value)")
    check(batch?.effect(["app": "Mail", "steps": "type @s1abcd:e3 안녕\nclick \"Send\""]) == .outward, "desktop: a step that presses Send is outward")
    check(batch?.effect(["app": "TextEdit", "steps": "frobnicate everything"]) == .changePermanent, "desktop: steps that can't be read are the strongest short of never")
    check(ArisCapabilityBook.entry(named: "desktop_see")?.effect(["app": "TextEdit"]) == .observe, "desktop: a look is observe (it was recorded as change-reversible)")
    check(ArisCapabilityBook.entry(named: "desktop_press")?.effect(["app": "TextEdit", "keys": "cmd+x"]) == .changePermanent
          && ArisCapabilityBook.entry(named: "desktop_press")?.effect(["app": "TextEdit", "keys": "cmd+s"]) == .changeReversible, "desktop: a cut takes something away; a save doesn't")
    check(ArisCapabilityBook.entry(named: "desktop_set_value")?.effect(["ref": "@s1abcd:e3", "text": "x"]) == .changePermanent, "desktop: set-value replaces")
    check(ArisCapabilityBook.entry(named: "desktop_type")?.effect(["ref": "@s1abcd:e3", "text": "x"]) == .changeReversible, "desktop: typing at the caret is reversible")
    // Never below the inventory row's class unless the call is a look on the allowlist (security review of D4).
    let row = ArisCapabilities.capability(["desktop", "click", "@s1abcd:e3"])?.effectClass ?? .changePermanent
    let rank: (ArisEffectClass) -> Int = { ArisEffectClass.strongest([$0, row]) == $0 ? 1 : 0 }
    for words in [["desktop", "click", "@s1abcd:e3"], ["desktop", "click-at", "--app", "Notes", "--target", "the blue button"],
                  ["desktop", "frobnicate", "@s1abcd:e3"], ["desktop", "scroll", "@s1abcd:e3", "--direction", "down"], ["desktop", "menu", "click", "--app", "Notes", "--path", "File > Export"]] {
        let effect = ArisCapabilityBook.effect(ofArisTools: words)
        check(rank(effect) == 1 && effect != .observe, "desktop: \(words.dropFirst().prefix(2).joined(separator: " ")) is never below the row's class (\(effect))")
    }
    check((ArisCapabilityBook.entry(named: "desktop_click_at")?.effect(["app": "Notes", "target": "the blue button"])).map(rank) == 1,
          "desktop: a coordinate click through its function is never below the row's class")
    check(ArisCapabilityBook.effect(ofArisTools: ["desktop", "see", "--app", "Notes"]) == .observe
          && ArisCapabilityBook.effect(ofArisTools: ["desktop", "window", "list", "--app", "Notes"]) == .observe, "desktop: a pure look is observe")
    let seeThenClick = batch?.effect(["app": "Notes", "steps": "see\nclick @s1abcd:e3"]) ?? .observe
    check(rank(seeThenClick) == 1 && seeThenClick != .observe, "desktop: a batch with a look and a click is at least the click's class (\(seeThenClick))")
    check(ArisDesktopEffect.looks == [.see, .menuList, .dialogList, .windowList, .dockList], "desktop: the looks are an explicit allowlist")

    // Opening an app: the same class on every path (the trust table's change-reversible row; observe would ask less).
    let opens = [ArisCapabilityBook.entry(named: "open_app")?.effect(["name": "Calendar"]), ArisCapabilityBook.entry(named: "desktop_app")?.effect(["app": "Calendar", "operation": "launch"]),
                 ArisCapabilityBook.effect(ofArisTools: ["app", "Calendar"])]
    check(opens.allSatisfy { $0 == .changeReversible }, "desktop: opening an app is change-reversible however it is asked (\(opens))")
    // The shell's form of the same batch (a heredoc) reads the same.
    let line = "\(ArisAppBundle.toldTools) desktop batch --app TextEdit --stdin <<'ARIS'\nclick @s1abcd:e3\npress cmd+a\ntype @s1abcd:e3 x\nARIS"
    check(ArisCore2.shellEffect(line, tools: ArisAppBundle.toldTools) == .changePermanent, "desktop: the shell's heredoc batch is read the same way")
    check(ArisCapabilityBook.effect(ofArisTools: ["keys", "cmd+a", "delete", "--app", "TextEdit"]) == .changePermanent, "desktop: aris-tools keys that delete are permanent")

    // The verdict: owner-asked and permanent is said first with a moment to stop, never run-with-undo; the same batch
    // gets the same verdict every time.
    let home = NSTemporaryDirectory() + "aris-vmfix2-tests-\(UUID().uuidString)"
    defer { try? FileManager.default.removeItem(atPath: home) }
    let gate = ArisTrustGate(home: home, world: { _ in ArisWorldFacts(home: home) })
    gate.ownerTurn(session: "s", text: "TextEdit의 Untitled 창에 '코어2 테스트'라고 써 줘")
    guard let batch else { return check(false, "desktop: desktop_batch is in the book") }
    func decided(_ call: String, _ arguments: [String: Any]) -> ArisDecision {
        gate.decide(session: "s", call: call, capability: batch.id, effect: batch.effect(arguments), arguments: arguments,
                    argv: batch.argv(arguments), stdin: arguments["steps"] as? String).decision
    }
    func silent(_ decision: ArisDecision) -> Bool {
        switch decision {
        case .run, .runWithUndo: return true
        default: return false
        }
    }
    let first = decided("c1", replaceAll), again = decided("c2", replaceAll)
    check(first == again && !silent(first), "desktop: the replacing batch is not run without a word, the same every time (\(first), \(again))")
    check(decided("c3", append) == .runWithUndo(announce: false), "desktop: the appending batch still runs with its undo kept (nothing asks more than it must)")
}

// MARK: - D5: the day in review

private func vmfixRow(_ summary: String, _ minutes: Double, undone: Bool = false) -> ArisActivityItem {
    ArisActivityItem(id: UUID().uuidString, date: Date(timeIntervalSince1970: 1_800_000_000 + minutes * 60), job: "대화", worker: "Aris", summary: summary,
                     undoable: false, undone: undone, asks: false, teammate: nil)
}

private func vmfixRecapTests() {
    // Every capability in the book has a name the owner reads; a new one without a row fails here.
    let missing = ArisCapabilityBook.all.map(\.id).filter { ArisCapabilityNames.name($0) == nil }
    check(missing.isEmpty, "names: every capability in the book has a Korean and English name (missing: \(missing))")
    check(ArisCapabilityNames.table.values.allSatisfy { !$0.korean.isEmpty && !$0.english.isEmpty && !$0.korean.contains(".") },
          "names: each name is words, never an id")

    // The record's rows read as names, and a call that wrote its own log lines is listed once, by those lines.
    let at = Date()
    var batch = ArisRecordEntry.call(at: at, session: "s", task: nil, capability: "aris.desktop_batch", effect: .changePermanent, provenance: .ownerSaid,
                                     decision: .sayThenRun(delay: 3), arguments: [.init(kind: .app, value: "TextEdit")], result: nil, ok: true, undo: nil)
    var rename = ArisRecordEntry.call(at: at, session: "s", task: nil, capability: "aris.file_rename", effect: .changeReversible, provenance: .ownerSaid,
                                      decision: .runWithUndo(announce: false), arguments: [.init(kind: .path, value: "/Users/x/a.txt")], result: nil, ok: true, undo: nil)
    rename.logged = ["9b2c1a3e-0000-4000-8000-000000000001"]
    let look = ArisRecordEntry.call(at: at, session: "s", task: nil, capability: "aris.desktop_see", effect: .observe, provenance: .ownerSaid,
                                    decision: .run, arguments: [.init(kind: .app, value: "TextEdit")], result: nil, ok: true, undo: nil)
    batch.logged = nil
    let rows = ArisRecord.activityRows(ArisRecordState([batch, rename, look]))
    check(rows.count == 1 && rows.first?["summary"] as? String == "앱에서 여러 단계: TextEdit", "day: a record row reads as a name, a look and a call the log lists are left out (\(rows))")
    check(rows.allSatisfy { !(($0["summary"] as? String) ?? "").contains("aris.") }, "day: no capability id reaches the user")
    check(ArisActivityWords.english("앱에서 여러 단계: TextEdit") == "Steps in an app: TextEdit", "day: the English card says it in English")
    check(ArisActivity.callMarkKey == ArisMindExecutor.callMarkKey, "day: aris-tools and the helper name the call's mark the same")

    // The executor learns which log lines its call wrote, by the mark it gave the run.
    var executor = ArisMindExecutor(tools: "/x/aris-tools", environment: [:], home: NSTemporaryDirectory(), runTools: { _, _ in .printed("ran") },
                                    shell: { _, _, _ in .printed("ran") }, store: ArisUndoStore(folder: URL(fileURLWithPath: NSTemporaryDirectory() + "/aris-vmfix2-undo")))
    var given: String?
    executor.markedTools = { _, _, mark in given = mark; return .printed("renamed") }
    executor.activity = { [["id": "9B2C1A3E-0000-4000-8000-000000000002", "call": given ?? "-"], ["id": "9b2c1a3e-0000-4000-8000-000000000003", "call": "other"]] }
    if let entry = ArisCapabilityBook.entry(named: "file_rename") {
        let arguments: [String: Any] = ["path": "/Users/x/a.txt", "name": "b.txt"]
        let result = executor.run(entry, arguments: arguments, argv: entry.argv(arguments), stdin: nil, caller: ArisUndoCaller(session: "s", provenance: .ownerSaid))
        check(result.logged == ["9b2c1a3e-0000-4000-8000-000000000002"], "day: the call knows the log line its run wrote, and only that one (\(result.logged))")
    }

    // A cancelled timer, the setup's practice one included, is no work done; one that rang is.
    let set = vmfixRow("타이머: 3분", 0), off = vmfixRow(ArisDayEndPlan.timerOffLine, 1), rang = vmfixRow("타이머: 5분", 10), later = vmfixRow("타이머 끔", 30)
    check(ArisDayEndPlan.cancelledTimers([set, off, rang, later]) == [set.id, off.id, later.id], "day: a timer turned off before it rang, and the turning off, are left out")
    // vmfix3: the practice is never in the record at all (its timer may ring before the setup ends), so its cancel isn't either.
    check(vmfixSource("Aris/private/Aris/ArisController+Practice.swift").contains("ArisTimerModel.shared.cancel()"),
          "day: the setup's practice timer, cancelled with the setup, goes without a record line")
    check(vmfixSource("Aris/private/Aris/ArisTimerEar.swift").contains("timer.cancelLogged()"), "day: the timer's own off button says so too")
    var facts = ArisDayEndFacts()
    let now = Date(timeIntervalSince1970: 1_800_000_000 + 3_600)
    facts.activity = [set, off].map { ArisActivityItem(id: $0.id, date: now.addingTimeInterval(-60), job: $0.job, worker: $0.worker, summary: $0.summary, undoable: false,
                                                       undone: false, asks: false, teammate: nil) }
    check(ArisDayEnd.make(facts, now: now).counts.extra == 0, "day: the first setup's cancelled practice timer is not listed as done")

    // Said and shown agree; a light day still has its parts.
    var recap = ArisRecapFacts()
    recap.record = ArisRecordDigest(total: 5, families: ["apps": 3, "files": 1, "calendar": 1])
    recap.extra = 6
    let day = ArisRecap.make(recap, focus: .day, today: now, now: now, english: false)
    check(day.spoken.contains("여섯 가지") && (3...5).contains(day.sentences.count), "day: the count said is the list's, in three to five sentences (\(day.spoken))")
}

// MARK: - D7: one card for one message

private func vmfixMessageCardTests() {
    let send = ArisAskItem(call: "c1", facts: ArisCallFacts(capability: "aris.send_message", arguments: [.init(kind: .recipient, value: "010-0000-0000"),
                                                                                                     .init(kind: .body, value: "테스트 메시지")]),
                           effect: .outward, decision: .sayThenRun(delay: 3), provenance: .ownerSaid)
    let card = ArisAskPlan.card([send], id: "t1", intent: "i", countdown: true, home: NSTemporaryDirectory())
    check(card.title == "010-0000-0000" && card.detail == "테스트 메시지" && card.isMessage,
          "message: the countdown card's To is the recipient and its Message the text, nothing else (\(card.title) / \(card.detail))")
    let shown = ArisTrustGate.confirmation(card)
    check(shown.countdown && !shown.action, "message: it is drawn as the message card")
    // Only a plain message is reduced to To and Message: anything more is read back whole (security review of D7).
    func countdownCard(_ capability: String, _ arguments: [ArisKeyArgument], payment: Bool = false) -> ArisAskCard {
        let item = ArisAskItem(call: "c", facts: ArisCallFacts(capability: capability, arguments: arguments, payment: payment), effect: .outward,
                               decision: .sayThenRun(delay: 3), provenance: .ownerSaid)
        return ArisAskPlan.card([item], id: "t", intent: "i", countdown: true, home: NSTemporaryDirectory())
    }
    let attached = countdownCard("aris.send_message", [.init(kind: .recipient, value: "엄마"), .init(kind: .body, value: "사진이야"), .init(kind: .path, value: "/Users/x/사진.jpg")])
    check(!attached.isMessage && attached.detail.contains("사진.jpg") && ArisTrustGate.confirmation(attached).action,
          "message: a message with an attachment shows the attachment on the card (\(attached.detail))")
    for (capability, extra, payment) in [("aris.pay", ArisKeyArgument(kind: .amount, value: "30000원"), true), ("shop.order", ArisKeyArgument(kind: .payee, value: "가게"), true),
                                         ("social.post", ArisKeyArgument(kind: .url, value: "https://x.example"), false), ("aris.send_message", ArisKeyArgument(kind: .app, value: "카카오톡"), false)] {
        let other = countdownCard(capability, [.init(kind: .recipient, value: "엄마"), .init(kind: .body, value: "안녕"), extra], payment: payment)
        check(!other.isMessage && other.detail.contains(extra.value), "message: \(capability) with \(extra.kind) never gets the reduced card (\(other.detail))")
    }
    let posted = countdownCard("social.post", [.init(kind: .recipient, value: "팔로워"), .init(kind: .body, value: "안녕")])
    check(!posted.isMessage, "message: a post is no plain message, even with only a recipient and a text")
    let paying = countdownCard("aris.send_message", [.init(kind: .recipient, value: "엄마"), .init(kind: .body, value: "안녕")], payment: true)
    check(!paying.isMessage, "message: a payment never gets the reduced card")
    let plain = countdownCard("message.send", [.init(kind: .recipient, value: "엄마"), .init(kind: .body, value: "곧 갈게")])
    check(plain.isMessage && plain.title == "엄마" && plain.detail == "곧 갈게", "message: a plain message still gets the clean To / Message card")
    let wipe = ArisAskItem(call: "c2", facts: ArisCallFacts(capability: "aris.desktop_batch", arguments: [.init(kind: .app, value: "TextEdit")]),
                           effect: .changePermanent, decision: .sayThenRun(delay: 3), provenance: .ownerSaid)
    let action = ArisTrustGate.confirmation(ArisAskPlan.card([wipe], id: "t2", intent: "i", countdown: true, home: NSTemporaryDirectory()))
    check(action.countdown && action.action, "message: a permanent change said first is an action's countdown, never 받는 사람/메시지")
    let line = ArisAgentReply.confirm(action).line
    if case .confirm(let parsed)? = ArisAgentReply.parse(String(decoding: line, as: UTF8.self)) {
        check(parsed.action && parsed.countdown, "message: the app reads the action flag from the confirm line")
    } else {
        check(false, "message: the confirm line parses")
    }
    let asking = ArisTrustGate.confirmation(ArisAskPlan.card([wipe], id: "t3", intent: "i", countdown: false, home: NSTemporaryDirectory()))
    check(!asking.action && !asking.countdown, "message: an asking card is unchanged")

    // No microphone: the same card stays up and waits for a press; no second card with other words.
    let countdown = vmfixSource("Aris/private/Aris/ArisController+Countdown.swift")
    check(!countdown.contains("title: \"메시지 보내기\"") && countdown.contains("return await pausedCountdown(ask, key: key)")
          && countdown.contains("ArisCountdownMic.shared.listening = false"), "message: with no microphone the countdown pauses in place")
    check(ArisCountdownCopy.hint(listening: false, action: false) != ArisCountdownCopy.hint && ArisCountdownCopy.hint(listening: true, action: false) == ArisCountdownCopy.hint,
          "message: its hint asks for a press when it can't listen")
    let catalog = vmfixSource("Aris/Localizable.xcstrings")
    for key in ["countdown.presshint", "countdown.go", "countdown.gopresshint", "countdown.doing", "countdown.notdone", "countdown.noanswer"] {
        check(catalog.contains("\"\(key)\"") , "message: \(key) has Korean and English")
    }
    // Unanswered is never logged or shown as a no.
    check(ArisCardWait.answerLog(allow: false, unanswered: true) == "nobody answered" && ArisCardWait.answerLog(allow: false, unanswered: false) == "you said no to",
          "message: the log tells unanswered from no")
    let question = ArisConfirmation(id: "q", title: "엄마", detail: "곧 갈게", countdown: true)
    let session = ArisSession().asking(question)
    check(session.counted(sent: false, unanswered: true).countdownEnd?.unanswered == true && session.counted(sent: false).countdownEnd?.unanswered == false,
          "message: the settled line says nobody answered, not cancelled")
}

// MARK: - The fast lane's words

private func vmfixFastLaneTests() {
    for (name, prompt) in [("API", ArisAgentPrompt.system(tools: ArisAPICatalog.generic, gated: true, task: false, functions: true)),
                           ("Claude", ArisAgentPrompt.system(tools: "/x/aris-tools", task: false, reads: true)),
                           ("Core 2 Claude", ArisHandsPrompt.system(task: false)), ("Mind", ArisMindSession.rules)] {
        check(prompt.contains(ArisAgentPrompt.koreanSpeech), "fast lane: the \(name) prompt asks for whole Korean endings")
        check(prompt.range(of: #"(?i)(append|add|end (with|in)|attach)[^.\n]{0,30}[“\"']?요[”\"']?"#, options: .regularExpression) == nil,
              "fast lane: the \(name) prompt never asks for a 요 to be added")
    }
    // vmfix4: the broken ending is described, never spelled out (a shown "파리의요" was copied: "파리의 수도예요.").
    check(ArisAgentPrompt.koreanSpeech.contains("도쿄예요") && ArisAgentPrompt.koreanSpeech.contains("이에요") && !ArisAgentPrompt.koreanSpeech.contains("파리의요"),
          "fast lane: the rule shows the copula after a noun and describes the broken ending without spelling it out")
    check(ArisMindBrainDriver.serves(core2: true, sealed: false, handsFree: false, scopes: nil), "fast lane: with Core 2 on, a plain turn of an API brain is the Mind's, whatever its tier")
    check(vmfixSource("ArisAgent/ArisAgentRunner.swift").contains("The fast lane is not a way around the Mind"), "fast lane: the route says it")
}

func runVmfix2Tests() {
    vmfixSwitchTests()
    vmfixLabsSettingTests()
    vmfixDesktopEffectTests()
    vmfixRecapTests()
    vmfixMessageCardTests()
    vmfixFastLaneTests()
}
