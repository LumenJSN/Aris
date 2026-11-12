// Tests for the owner's 2026-11-08 decisions on the bug hunt's "Needs the user" table (BUGHUNT-2026-11-08.md, N1-N18) and the
// sealed Claude's messages. Each one failed before its change. Called from main.swift; uses its check().
import Foundation

func runDecisions1108Tests() {
    decisionSealedMessageTests()
    decisionAgyMessageLineTests()
    decisionPromptLineTests()
    decisionNameTests()
    decisionOnboardingTests()
    decisionScopeTests()
    decisionScheduleTeammateTests()
    decisionHeaderTests()
    decisionFaceWordTests()
    decisionUndoScopeTests()
    decisionHelperTests()
    decisionTeamMakingTests()
    decisionEditStampTests()
    decisionTeammateFileTests()
}

private let dTools = "/Users/p/.config/aris/aris-tools"
private let dDictated = "엄마한테 곧 간다고 문자 보내줘"

/// A turn as the message gate sees it.
private final class DecisionMessageTurn: ArisMessageTurn {
    var request = dDictated
    var isTask = false
    var taint = ArisTaint.none
    var handsFree = false
    var critical = false
    var sealed = false
    var scopes: Set<ArisTeammateScope>? = nil
    var answer = ArisMCPAnswer.yes([:])
    func stillSendable() -> Bool { true }
    private(set) var cards: [ArisMCPCard] = []
    func ask(_ card: ArisMCPCard, answer: @escaping (ArisMCPAnswer) -> Void) { cards.append(card); answer(self.answer) }
    func audit(_ fields: [String: String]) {}
}

private func sealedCard(_ configure: (DecisionMessageTurn) -> Void = { _ in }) -> ArisMessageGate.Card {
    let turn = DecisionMessageTurn()
    turn.sealed = true
    configure(turn)
    return ArisMessageGate.card(to: "엄마", text: "곧 갈게", turn: turn, tools: dTools, home: "/Users/p")
}

private func isPlainCard(_ card: ArisMessageGate.Card) -> Bool { if case .ask = card { return true } else { return false } }

/// The words between `flag` and the next flag of a Claude command line.
private func flagList(_ arguments: [String], _ flag: String) -> [String] {
    guard let start = arguments.firstIndex(of: flag) else { return [] }
    return Array(arguments[(start + 1)...].prefix { !$0.hasPrefix("--") })
}

/// Decision 1: the sealed Claude (a screen-seen or hands-free turn) may send a message, on the user's plain card only (never
/// a countdown), through the agent's /message-tool path; every other gate stays.
private func decisionSealedMessageTests() {
    typealias T = ArisSealedTools
    let message = ["message", "엄마", "곧 갈게"]
    check(!T.allows(message) && !ArisAgyRelay.permitted(message, sealed: true) && !ArisAgyRelay.permitted(message, sealed: false),
          "sealed message: off the shared sealed list (agy's relay and the turn gate's clean reads never send one)")
    check(T.allows(message, messages: true) && T.allows(["message", "엄마", "곧", "갈게"], messages: true),
          "sealed message: the sealed Claude's own list has it")
    check(!T.allows(["message", "-v", "x"], messages: true) && !T.allows(["message", "엄마"], messages: true),
          "sealed message: only `message <to> <text>`")

    for driver in [ArisClaudeDriver(model: "m", tools: dTools, sealed: true), ArisClaudeDriver(model: "m", tools: dTools, handsFree: true)] {
        let rule = "Bash(\(dTools) message:*)"
        check(flagList(driver.arguments, "--allowedTools").contains(rule) && !flagList(driver.arguments, "--disallowedTools").contains(rule),
              "sealed message: Claude Code allows it (\(driver.handsFree ? "hands-free" : "screen"))")
        check(driver.environment[T.messageKey] == "1", "sealed message: aris-tools is told it may hand a message to the agent")
    }
    check(ArisClaudeDriver(model: "m", tools: dTools).environment[T.messageKey] == nil, "sealed message: never set for the open Claude")

    let line = "\(dTools) message 엄마 \"곧 갈게\""
    check(T.permits(command: line, tools: dTools, messages: true) && !T.permits(command: line, tools: dTools),
          "sealed message: the hook's shape check takes it only for the sealed Claude")
    check(!T.permits(command: line + " && \(dTools) timer 5", tools: dTools, messages: true),
          "sealed message: nothing rides along with it")
    let input = try! JSONSerialization.data(withJSONObject: ["tool_name": "Bash", "tool_input": ["command": line]])
    check(T.hookVerdict(input: input, tools: dTools, messages: true) == .allow && T.hookVerdict(input: input, tools: dTools) == .block,
          "sealed message: its hook lets it through (the agent's gate decides it)")
    check(T.refusal(environment: [T.environmentKey: "1", T.messageKey: "1"], arguments: message) == nil
          && T.refusal(environment: [T.environmentKey: "1"], arguments: message) != nil,
          "sealed message: aris-tools refuses it under ARIS_SEALED unless the sealed Claude's key is set")

    let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("aris-dmsg-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let credential = folder.appendingPathComponent("turn")
    try? "t42".write(to: credential, atomically: true, encoding: .utf8)
    check(messageRouting(["엄마", "곧", "갈게"], environment: [T.environmentKey: "1", T.messageKey: "1", "ARIS_MCP_TURN_FILE": credential.path],
                         consume: { _, _ in false }) == .agent(to: "엄마", text: "곧 갈게", turn: "t42"),
          "sealed message: aris-tools hands it to the agent (POST /message-tool)")
    if case .refused = messageRouting(["엄마", "곧 갈게"], environment: [T.environmentKey: "1", T.messageKey: "1"], consume: { _, _ in false }) {} else {
        check(false, "sealed message: no credential, nothing sent")
    }

    // The agent's decision: the user's plain card, never the countdown; refused after outside text, outside scopes.
    check(isPlainCard(sealedCard()), "sealed message gate: a dictated message is the user's plain card, not a countdown")
    check(isPlainCard(sealedCard { $0.taint = .screenSeen }) && isPlainCard(sealedCard { $0.handsFree = true }),
          "sealed message gate: a screen-seen or hands-free turn gets the card")
    check(isPlainCard(sealedCard { $0.isTask = true }), "sealed message gate: a job's message is a card too")
    check(sealedCard { $0.taint = .outsideText } == .refused(ArisMessageGate.afterOutsideText),
          "sealed message gate: refused after outside text")
    check(sealedCard { $0.scopes = [.files] } == .refused(ArisMessageGate.refusal), "sealed message gate: a teammate without 보내기 is refused")
    let open = DecisionMessageTurn()
    check(ArisMessageGate.card(to: "엄마", text: "곧 갈게", turn: open, tools: dTools, home: "/Users/p") == .countdown(to: "엄마", text: "곧 갈게"),
          "sealed message gate: the open Claude keeps its countdown")
    let turn = DecisionMessageTurn()
    turn.sealed = true
    var ran: [[String]] = []
    let sent = ArisMessageGate.answer(to: "엄마", text: "곧 갈게", turn: turn, tools: dTools, home: "/Users/p", limit: 1) { words in
        ran.append(words)
        return ArisMCPOutcome(status: 0, output: "sent to 엄마")
    }
    check(turn.cards.count == 1 && turn.cards.first?.countdown == false && ran == [message] && sent.status == 0,
          "sealed message gate: one plain card, and on the user's yes the agent sends exactly that message")

    for prompt in [ArisAgentPrompt.sealed(tools: dTools), ArisAgentPrompt.sealed(tools: dTools, handsFree: true)] {
        check(prompt.contains("`\(dTools) message \"<name, number or email>\" \"<text>\"`"), "sealed message: the sealed prompt teaches the command")
    }
}

/// Decision 2: agy still never sends a message, and its prompts say why in one line.
private func decisionAgyMessageLineTests() {
    let line = ArisAgentPrompt.agyMessageLine
    check(!line.contains("\n") && line.contains("web search"), "agy message line: one line, with the reason")
    check(ArisAgentPrompt.system(tools: dTools, relay: true).contains(line), "agy message line: in agy's prompt")
    check(ArisAgentPrompt.sealedAgy(tools: dTools, handsFree: false, task: false).contains(line)
          && ArisAgentPrompt.sealedAgy(tools: dTools, handsFree: true, task: true).contains(line), "agy message line: in the sealed agy's too")
    check(!ArisAgentPrompt.system(tools: dTools, reads: true).contains(line) && !ArisAgentPrompt.system(tools: dTools, gated: true).contains(line),
          "agy message line: only agy's")
}

/// N10 and N12: every brain's prompt names the user sparingly, and points to the 한 일 tab for past jobs.
private func decisionPromptLineTests() {
    let prompts = [ArisAgentPrompt.system(tools: dTools, gated: true), ArisAgentPrompt.system(tools: dTools, reads: true),
                   ArisAgentPrompt.system(tools: dTools, gated: true, functions: true), ArisAgentPrompt.system(tools: dTools, relay: true),
                   ArisAgentPrompt.sealed(tools: dTools), ArisAgentPrompt.sealed(tools: dTools, handsFree: true),
                   ArisAgentPrompt.sealedAgy(tools: dTools, handsFree: false, task: false)]
    check(prompts.allSatisfy { $0.contains(ArisAgentPrompt.nameRule) }, "N10: every conversation brain's prompt has the name rule")
    check(ArisAgentPrompt.nameRule.contains("occasionally") && ArisAgentPrompt.nameRule.contains("never in every"),
          "N10: the name is used occasionally, never in every message")
    check(ArisAgentPrompt.system(tools: dTools, gated: true, task: true).contains(ArisAgentPrompt.nameRule),
          "N10: a job's prompt has it too (its finished line)")
    check(prompts.allSatisfy { $0.contains(ArisAgentPrompt.pastJobsRule) } && ArisAgentPrompt.pastJobsRule.contains("한 일"),
          "N12: every conversation brain points to the 한 일 tab for an earlier conversation's jobs")
    check(!ArisAgentPrompt.system(tools: dTools, gated: true, task: true).contains(ArisAgentPrompt.pastJobsRule),
          "N12: not a job's (it has no conversation)")
}

/// N10: the name the user gave in the onboarding is read, cleaned, put in the context and used in a few lines.
private func decisionNameTests() {
    // One fixed suite, cleared before and after (a new UUID-named suite each run left a plist behind in Preferences).
    let suite = testSuiteName("aris-name-tests")
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let saved = ArisUserName.store
    ArisUserName.store = defaults
    defer {
        ArisUserName.store = saved
        defaults.removePersistentDomain(forName: suite)
    }
    check(ArisUserName.key == ArisOnboarding.nameKey, "N10: the onboarding's key is the one read")
    check(ArisUserName.current == nil, "N10: no name until one is given")
    ArisUserName.set("  Alex \n")
    check(ArisUserName.current == "Alex", "N10: kept trimmed")
    ArisUserName.set("   ")
    check(ArisUserName.current == nil && defaults.string(forKey: ArisUserName.key) == nil, "N10: an empty name clears it")
    check(ArisUserName.clean("<b>Alex</b>") == nil && ArisUserName.clean(String(repeating: "가", count: 40)) == nil && ArisUserName.clean("폴") == "폴",
          "N10: only a plain, short name")
    defaults.set("<script>", forKey: ArisUserName.key)
    check(ArisUserName.current == nil, "N10: a stored name that isn't plain isn't used")

    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let context = ArisContext.make(now: now, timeZone: TimeZone(identifier: "UTC")!, frontApp: nil, music: nil, events: [], recent: [], userName: "Alex")
    check(context.contains("user's name: Alex"), "N10: the context names the user")
    check(!ArisContext.make(now: now, timeZone: TimeZone(identifier: "UTC")!, frontApp: nil, music: nil, events: [], recent: []).contains("name:"),
          "N10: and says nothing without a name")

    check(ArisPillFinish.text(name: nil) == "Done" && ArisPillFinish.text(name: "Alex") == "Done, Alex",
          "N10: the pill's done line (English default)")
    guard let catalog = decisionCatalog(prefixes: ["team.", "onboarding."]) else { return check(false, "N10: the catalog reads") }
    let (language, bundle) = (ArisTeamCopy.language, ArisTeamCopy.bundle)
    defer { (ArisTeamCopy.language, ArisTeamCopy.bundle) = (language, bundle) }
    ArisTeamCopy.use("ko", in: catalog)
    check(ArisPillFinish.text(name: "Alex") == "Alex님, 끝났어요" && ArisPillFinish.text(name: nil) == "끝났어요",
          "N10: 'Alex님, 끝났어요' in Korean")
    let (obLanguage, obBundle) = (ArisOnboardingCopy.language, ArisOnboardingCopy.bundle)
    defer { (ArisOnboardingCopy.language, ArisOnboardingCopy.bundle) = (obLanguage, obBundle) }
    ArisOnboardingCopy.use("ko", in: catalog)
    check(ArisOnboardingCopy.greetName == ["반가워요!", "이제 몇 가지만 같이 준비해 볼게요."], "N2: the greet-name caption is what the recording says")
    check(ArisOnboardingCopy.permsNarration(name: "Alex").hasPrefix("Alex님,") && !ArisOnboardingCopy.permsNarration(name: nil).contains("님"),
          "N2/N10: the name shows on the next line instead")
    check(ArisOnboardingCopy.finishLine(name: "Alex").contains("Alex님") && ArisOnboardingCopy.finishLine(name: nil) == "여기 있을게요. 부르면 와요.",
          "N10: the finish line by name")
    ArisOnboardingCopy.use("en", in: catalog)
    check(ArisOnboardingCopy.greetName.first == "Nice to meet you!" && ArisOnboardingCopy.finishLine(name: "Alex").contains("Alex"),
          "N10: English too")

    var snapshot = ArisSettingsSnapshot()
    snapshot.userName = "Alex"
    let rows = ArisSettingsBuilder.sections(.general, snapshot).flatMap(\.rows)
    guard let row = rows.first(where: { $0.id == "general.name" }) else { return check(false, "N10: 설정 › 일반 has the name row") }
    if case .field(.userName, let text, _, let button) = row.control {
        check(text == "Alex" && button.action == .clearName && button.enabled, "N10: the name is edited in place and can be cleared")
    } else {
        check(false, "N10: the name row is a text field")
    }
    check(ArisSettingsIndex.entries.contains { $0.id == "general.name" }, "N10: the name row can be searched")
}

/// The catalog's strings under `prefixes`, compiled as Xcode would into <lang>.lproj/Localizable.strings.
func decisionCatalog(prefixes: [String]) -> Bundle? {
    let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let catalog = tests.appendingPathComponent("../Aris/Localizable.xcstrings")
    guard let data = try? Data(contentsOf: catalog),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let all = json["strings"] as? [String: [String: Any]] else { return nil }
    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("aris-catalog-\(UUID().uuidString)")
    for language in ["ko", "en"] {
        var table: [String: String] = [:]
        for (key, entry) in all where prefixes.contains(where: key.hasPrefix) {
            let localizations = entry["localizations"] as? [String: [String: [String: String]]] ?? [:]
            if let value = localizations[language]?["stringUnit"]?["value"] { table[key] = value }
        }
        let lproj = dir.appendingPathComponent("\(language).lproj")
        try? FileManager.default.createDirectory(at: lproj, withIntermediateDirectories: true)
        guard let plist = try? PropertyListSerialization.data(fromPropertyList: table, format: .binary, options: 0),
              (try? plist.write(to: lproj.appendingPathComponent("Localizable.strings"))) != nil else { return nil }
    }
    return Bundle(path: dir.path)
}

/// N1, N3, N11: the onboarding's notch and stage stars wear Aris's face; a notch already open when the guide starts is
/// held until it closes; 시작 안내로 돌아가기 during the finish beat brings the setup window back.
private func decisionOnboardingTests() {
    typealias S = ArisOnboardingStage
    check(S.wearsFace(.notch) && S.wearsFace(.stage), "N1: the notch's and the stage's star wear the face")
    check(!S.wearsFace(.intro) && !S.wearsFace(.preview), "N1: the intro's sunrise stays the star")
    check(S.realHolds(active: false, dictating: false, notchOpen: true, holding: S.holdingAtStart),
          "N3: a notch already open when the guide starts stays the real one's (its approval is answered first)")
    check(!S.realHolds(active: false, dictating: false, notchOpen: false, holding: S.holdingAtStart), "N3: a closed one is the guide's at once")
    check(S.surfaceReopensSetup(phase: .finish) && !S.surfaceReopensSetup(phase: .setup) && !S.surfaceReopensSetup(phase: .intro),
          "N11: 시작 안내로 돌아가기 works during the finish beat")
}

/// N4, N6, N16, N18 (Notion): what a teammate may use, as shown and as kept.
private func decisionScopeTests() {
    typealias S = ArisTeammateScope
    check(!S.shown(brain: "claude").contains(.terminal) && S.shown(brain: "codex") == S.allCases && S.shown(brain: "antigravity") == S.allCases,
          "N4: a Claude teammate's page has no terminal switch")
    check(!ArisTeamCopy.terminalOnClaude.isEmpty && !ArisTeamCopy.terminalOnClaude.contains("\n"), "N4: one line says why")

    let seven = S.allCases.filter { $0 != .aside }.map(\.rawValue)
    let old = #"{"id":"mong","name":"몽실","routing":"메일","look":{"type":"cat","shading":"fabric"},"brain":"antigravity","memoryFile":"teammates/mong.md","scopes":"# + jsonList(seven) + "}"
    let migrated = try? JSONDecoder().decode(ArisTeammate.self, from: Data(old.utf8))
    check(migrated.map { S.isAll($0.scopeSet) } == true, "N6: a teammate saved with all seven scopes on gets Aside too")
    let picked = #"{"id":"mong","name":"몽실","routing":"메일","look":{"type":"cat","shading":"fabric"},"brain":"antigravity","memoryFile":"teammates/mong.md","scopesVersion":2,"scopes":"# + jsonList(seven) + "}"
    check((try? JSONDecoder().decode(ArisTeammate.self, from: Data(picked.utf8))).map { !$0.scopeSet.contains(.aside) } == true,
          "N6: one saved since keeps Aside off")
    let fewer = #"{"id":"mong","name":"몽실","routing":"메일","look":{"type":"cat","shading":"fabric"},"brain":"codex","memoryFile":"teammates/mong.md","scopes":["files","web"]}"#
    check((try? JSONDecoder().decode(ArisTeammate.self, from: Data(fewer.utf8)))?.scopes == ["files", "web"], "N6: fewer scopes are left as they were")
    if let migrated, let data = try? JSONEncoder().encode(migrated), let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
        check(object["scopesVersion"] as? Int == 2, "N6: what is written says it has Aside's switch")
    }

    let scoped = ArisAgentPrompt.sealedAgy(tools: dTools, handsFree: false, task: true, scoped: true)
    check(scoped.contains(ArisAgentPrompt.scopedReason) && !scoped.contains("read the user's private messages"),
          "N16: a sealed agy teammate's prompt gives the scopes as the reason")
    check(ArisAgentPrompt.sealedAgy(tools: dTools, handsFree: false, task: false).contains("read the user's private messages"),
          "N16: the other sealed agy keeps its reason")

    check(S.needed(server: "aris_notion") == S.needed(forTools: ["mcp", "call", "notion", "notion-search", "{}"]),
          "N18: Notion needs the same scopes through Codex as through aris-tools mcp")
}

private func jsonList(_ list: [String]) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: list), as: UTF8.self)
}

/// N5: a job a teammate schedules keeps that teammate (and so its scopes) when it runs.
private func decisionScheduleTeammateTests() {
    let home = NSTemporaryDirectory() + "aris-sched-\(UUID().uuidString)"
    defer { try? FileManager.default.removeItem(atPath: home) }
    let base = ["--title", "주간 정리", "--prompt", "Say: hi", "--daily", "08:00"]
    let stored = { ArisScheduleStore.load(file: ArisScheduleStore.file(home: home)) }
    // Who the job is comes from its job file (decisions-followup-tests.swift), never ARIS_TEAMMATE.
    _ = try? ArisScheduleTool.add(base, home: home, environment: [:], scoped: true, teammate: "mong")
    check(stored().last?.teammate == "mong", "N5: a teammate's schedule is filed under that teammate")
    check((try? ArisScheduleTool.add(base + ["--teammate", "boss"], home: home, environment: [:], scoped: true, teammate: "mong")) == nil,
          "N5: a teammate can't schedule work for another one")
    check((try? ArisScheduleTool.add(base, home: home, environment: ["ARIS_TEAMMATE": "mong"], scoped: true)) == nil,
          "N5: a teammate's job that can't say which teammate it is schedules nothing")
    _ = try? ArisScheduleTool.add(base + ["--teammate", "mong"], home: home, environment: [:])
    check(stored().last?.teammate == "mong", "N5: main Aris's --teammate is honoured")

    typealias J = ArisTeammateJobs
    let mate = ArisTeammate(id: "mong", name: "몽실", routing: "메일", look: .standard, brain: "claude", scopes: ["calendar"], memoryFile: "")
    check(J.scheduled(nil, in: [.claudeCode, mate]) == .aris && J.scheduled(ArisTeammate.claudeCodeId, in: [.claudeCode, mate]) == .aris,
          "N5: a schedule for no teammate runs as Aris (untrusted, on Codex)")
    check(J.scheduled("mong", in: [.claudeCode, mate]) == .teammate(mate), "N5: a teammate's schedule runs with its scopes")
    check(J.scheduled("gone", in: [.claudeCode]) == .missing, "N5: a schedule for a removed teammate is refused, never run as Aris")
}

/// N7: the Claude page keeps the voice bars and working dots in the band (only the resting star steps aside).
private func decisionHeaderTests() {
    typealias L = ArisNotchHeaderLayout
    check(!L.showsGlyph(showsStar: false, voiceOrWork: false), "N7: the resting star stays hidden on the Claude page")
    check(L.showsGlyph(showsStar: false, voiceOrWork: true) && L.showsGlyph(showsStar: true, voiceOrWork: false),
          "N7: a turn's bars and dots show there")
}

/// N9: the face picker's words come from the catalog, in Korean and English.
private func decisionFaceWordTests() {
    guard let catalog = decisionCatalog(prefixes: ["team."]) else { return check(false, "N9: the catalog reads") }
    let (language, bundle) = (ArisTeamCopy.language, ArisTeamCopy.bundle)
    defer { (ArisTeamCopy.language, ArisTeamCopy.bundle) = (language, bundle) }
    let codi = ArisTeammate(id: "codi", name: "코디", routing: "", look: ArisCharacterLook(type: "star", colorHex: nil, shading: "fabric"),
                            brain: "codex", memoryFile: "")
    ArisTeamCopy.use("ko", in: catalog)
    check(ArisFace.name("cat") == "고양이" && ArisFace.notice(moved: codi, aris: "cat") == "코디도 고양이였어요. 이제 코디는 별이에요.",
          "N9: Korean from the catalog, particles and all")
    check(ArisFaceStage.caption(.rest) == "쉴 때 · 카메라 옆에서 기다려요" && ArisFaceStage.Pin.auto.title == "자동", "N9: the stage in Korean")
    ArisTeamCopy.use("en", in: catalog)
    check(ArisFace.name("cat") == "cat" && ArisFace.notice(moved: codi, aris: "cat") == "코디 was the cat too. Now 코디 is the star.",
          "N9: English on an English system")
    check(ArisFace.noticeAction(moved: codi) == "Pick 코디's face" && ArisFaceStage.workLine == "Sorting mail", "N9: the button and the pill in English")
    ArisTeamCopy.use("ko", in: catalog)
    check(ArisCharacterLook.types.allSatisfy { ArisFace.name($0) != $0 }, "N9: every face has a Korean name in the catalog")
}

/// N13: undo needs the scope of what it undoes.
private func decisionUndoScopeTests() {
    check(ArisUndo.moveBack(from: "/a", to: "/b").scope == .files && ArisUndo.trashMade(paths: []).scope == .files
          && ArisUndo.restoreFromTrash(trash: "/t", original: "/o").scope == .files, "N13: a file undo needs files")
    check(ArisUndo.removeSchedule(id: "x").scope == .calendar && ArisUndo.deleteEvent(id: "e").scope == .calendar,
          "N13: a schedule or event undo needs the calendar")
    let home = NSTemporaryDirectory() + "aris-undo-\(UUID().uuidString)"
    try? FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: home) }
    // A schedule the teammate made logs its undo (removeSchedule); it undoes only its own (decisions-followup-tests.swift).
    _ = try? ArisScheduleTool.add(["--title", "x", "--prompt", "Say: x", "--daily", "08:00"], home: home, environment: ["ARIS_TEAMMATE": "mong"])
    let log = ArisPrivateFile.folder(home: home).appendingPathComponent("activity.jsonl")
    guard let entry = ArisActivity.load(file: log, since: .distantPast).last else { return check(false, "N13: the schedule's undo is logged") }
    var refused = false
    do { _ = try ArisActivity.undo(id: entry.id, confirmed: false, file: log, home: home, scopes: [.files], teammate: "mong") } catch {
        refused = (error as? ArisActivity.UndoError)?.message.contains("calendar") == true
    }
    check(refused, "N13: a files-only teammate can't undo a schedule")
    let undone = try? ArisActivity.undo(id: entry.id, confirmed: false, file: log, home: home, scopes: [.calendar], teammate: "mong")
    if case .done = undone {} else { check(false, "N13: with the calendar it can") }
}

/// N14: helpers are numbered across hand-outs that run at once, each with its own face; the 한 일 tab names them.
private func decisionHelperTests() {
    let clone = { (title: String) in ArisJobSpec(title: title, prompt: "p", assignee: .clone, cwd: nil, appHint: nil) }
    let first = ArisHelpers.assign([clone("a"), clone("b")])
    check(first.map(\.assignee) == [.helper(1), .helper(2)], "N14: a first hand-out's helpers are 1 and 2")
    let second = ArisHelpers.assign([clone("c"), clone("d")], taken: [1, 2])
    check(second.map(\.assignee) == [.helper(3), .helper(4)], "N14: a hand-out while those run goes on from 3")
    check(ArisHelpers.assign([clone("e"), clone("f")], taken: [2]).map(\.assignee) == [.helper(1), .helper(3)], "N14: a free number is used again")
    let looks = (1...4).map { ArisHelpers.look($0, teammates: [], aris: .star) }
    check(Set(looks.map(\.type)).count == 4, "N14: each helper at once has a face of its own")
    let jobs = [ArisJob(id: UUID(), title: "a", prompt: "p", assignee: .helper(1), cwd: nil, appHint: nil, target: .notch, state: .running(step: "s"), created: Date()),
                ArisJob(id: UUID(), title: "b", prompt: "p", assignee: .helper(2), cwd: nil, appHint: nil, target: .notch, state: .done("ok"), created: Date()),
                ArisJob(id: UUID(), title: "c", prompt: "p", assignee: .clone, cwd: nil, appHint: nil, target: .notch, state: .queued, created: Date())]
    check(ArisHelpers.taken(jobs) == [1], "N14: only the helpers still working hold their numbers")
    let turn = ArisHandOutPlan.Turn(words: "a랑 b 해줘", brain: .codex, turnId: nil)
    let plans = ArisHandOutPlan.plan([clone("c"), clone("d")], turn: turn, helpersTaken: [1, 2])
    check(plans.map(\.spec.assignee) == [.helper(3), .helper(4)], "N14: the hand-out plan numbers on")
    check(plans.filter(\.countsTowardSuggestion).count == 1 && plans.first?.countsTowardSuggestion == true,
          "N14: still only the hand-out's first helper counts toward the teammate offer (F6)")
    check(ArisActivityBridge.worker(teammate: nil, helper: "도우미 3", brain: "Codex") == "도우미 3"
          && ArisActivityBridge.worker(teammate: "몽실", helper: nil, brain: "Codex") == "몽실"
          && ArisActivityBridge.worker(teammate: nil, helper: nil, brain: "Codex") == "Codex", "N14: the 한 일 tab names a helper, not its brain")
    check(ArisActivityBridge.helperLabel("도우미 3") == "도우미 3" && ArisActivityBridge.helperLabel("x\ny") == nil
          && ArisActivityBridge.helperLabel(String(repeating: "a", count: 40)) == nil && ArisActivityBridge.helperLabel(3) == nil,
          "N14: only a short plain helper name is taken")
}

/// N15: "팀원 만들어줘" by voice only when it's asked for, not a question or a no.
private func decisionTeamMakingTests() {
    for said in ["팀원 추가하는 방법 알려줘", "팀원 만들지 마", "how do I add a teammate?", "팀원 추가하지 말아 줘", "팀원 만들 수 있어?",
                 "can I make a teammate?", "don't add a teammate", "어떻게 팀원 만들어?"] {
        check(ArisTeamMaking.parse(said) == nil, "N15: \(said) doesn't open the card")
    }
    for said in ["팀원 하나 만들어줘", "메일 담당 팀원 추가해 줘", "팀원 만들어 주세요", "팀원 하나 추가해", "Make a teammate named Cody",
                 "add a teammate", "can you make me a teammate?", "please create a new teammate"] {
        check(ArisTeamMaking.parse(said) != nil, "N15: \(said) still does")
    }
}

/// N17: a refresh never puts back a list older than an edit made while it ran.
private func decisionEditStampTests() {
    var stamp = ArisEditStamp()
    let read = stamp.now
    check(stamp.isCurrent(read), "N17: a read with no edit since is taken")
    stamp.edit()
    check(!stamp.isCurrent(read) && stamp.isCurrent(stamp.now), "N17: one with an edit since is dropped")
}

/// N18: a removed teammate's notes file goes with it.
private func decisionTeammateFileTests() {
    let mate = ArisTeammate(id: "mong", name: "몽실", routing: "", look: .standard, brain: "codex", scopes: ["files"], memoryFile: "teammates/mong.md")
    var stored = [ArisTeammate.claudeCode, mate]
    var removed: [String] = []
    let entry = { (m: ArisTeammate) -> [String: Any] in
        ["id": m.id, "name": m.name, "routing": m.routing, "brain": m.brain, "scopes": m.scopes, "look": ["type": m.look.type, "shading": m.look.shading]]
    }
    let reply = ArisTeammateRoute.handle(["op": "save", "teammates": [entry(.claudeCode)]], fromApp: true, load: { stored },
                                         save: { stored = $0 }, removed: { removed += $0 })
    check(reply.status == 200 && removed == ["mong"], "N18: the route names the teammate that went")
    let home = NSTemporaryDirectory() + "aris-notes-\(UUID().uuidString)"
    defer { try? FileManager.default.removeItem(atPath: home) }
    guard let file = ArisNotesStore.teammateFile(home: home, id: "mong") else { return check(false, "N18: a notes file") }
    try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? "- note".write(to: file, atomically: true, encoding: .utf8)
    ArisNotesStore.removeTeammate(ids: ["mong", ArisTeammate.claudeCodeId, "../x"], home: home)
    check(!FileManager.default.fileExists(atPath: file.path), "N18: and its teammates/<id>.md is deleted")
}
