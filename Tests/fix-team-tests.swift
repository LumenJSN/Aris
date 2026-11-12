// Tests for the 2026-11-10 audit's teammate and circle-gesture findings (qa/audit-1110/team.json). Called from
// main.swift; uses its check(). Pure state machines and fakes only: no overlay, microphone, terminal or stored list.
import AppKit
import Foundation

func runFixTeamTests() {
    gestureReleaseBackstopTests()
    teammateSubfolderTests()
    teammateSilenceTests()
    teammateQuestionTests()
    scopeTableTests()
    scopeRefusalTests()
    voiceMadeScopeTests()
    teamSaveRuleTests()
    teammateFolderTests()
    MainActor.assumeIsolated { lateCircleTests() }
}

// MARK: - gesture-1: a ⌥⇧ release the tap never heard

/// A held ⌥⇧ turn: both keys down at 0, the debounce tick at 120 ms starts it.
private func heldGestureKey() -> ArisGestureKey.State {
    var key = ArisGestureKey.State()
    _ = key.handle(.modifiers(option: true, shift: true, other: false, at: 0))
    _ = key.handle(.tick(at: 120))
    return key
}

private func gestureReleaseBackstopTests() {
    typealias K = ArisGestureKey
    // The release is lost (the tap was off). The timer's looks at the real keys end the turn as the release would have.
    var key = heldGestureKey()
    var watch = K.ReleaseWatch()
    check(key.pressing, "gesture-1: the held turn is on")
    check(watch.look(pressing: key.pressing, option: true, shift: true, other: false, at: 500) == nil,
          "gesture-1: while ⌥⇧ is really down, the backstop does nothing")
    check(watch.look(pressing: key.pressing, option: false, shift: false, other: false, at: 1_000) == nil,
          "gesture-1: one look with the keys up isn't enough (the real release may be on its way)")
    let lost = watch.look(pressing: key.pressing, option: false, shift: false, other: false, at: 1_000 + K.ReleaseWatch.confirmMs)
    check(lost == .modifiers(option: false, shift: false, other: false, at: 1_000),
          "gesture-1: the keys still up a moment later: the release is made up, timed when they were first seen up")
    check(lost.map { key.handle($0) } == .finish(heldForMs: 1_000) && !key.pressing,
          "gesture-1: the made-up release finishes the turn (the overlay and the microphone close) and the key is free again")

    // The real release arrives after the made-up one: nothing more happens.
    check(key.handle(.modifiers(option: false, shift: false, other: false, at: 1_100)) == .none, "gesture-1: a late real release after the backstop does nothing")

    // Only one key let go, never heard: the turn still ends, and nothing starts until both are up.
    var half = heldGestureKey()
    var halfWatch = K.ReleaseWatch()
    _ = halfWatch.look(pressing: true, option: true, shift: false, other: false, at: 2_000)
    let halfEvent = halfWatch.look(pressing: true, option: true, shift: false, other: false, at: 2_100)
    check(halfEvent.map { half.handle($0) } == .finish(heldForMs: 2_000), "gesture-1: ⇧ let go unheard ends the turn too")
    _ = half.handle(.modifiers(option: true, shift: true, other: false, at: 2_200))
    check(half.handle(.tick(at: 3_000)) == .none && !half.pressing, "gesture-1: after it, ⌥⇧ starts nothing until both keys were up")

    // A look that sees the keys down again forgets the earlier one.
    var flicker = K.ReleaseWatch()
    _ = flicker.look(pressing: true, option: false, shift: false, other: false, at: 100)
    _ = flicker.look(pressing: true, option: true, shift: true, other: false, at: 150)
    check(flicker.look(pressing: true, option: false, shift: false, other: false, at: 300) == nil,
          "gesture-1: keys seen down in between: the count of looks starts again")

    // Two looks run back to back (the main thread was busy) don't count as a moment apart.
    var burst = K.ReleaseWatch()
    _ = burst.look(pressing: true, option: false, shift: false, other: false, at: 100)
    check(burst.look(pressing: true, option: false, shift: false, other: false, at: 101) == nil,
          "gesture-1: two looks back to back aren't a moment apart")

    // Nothing held: the backstop never makes up an event (an ad demo, a hands-free turn).
    var idle = K.ReleaseWatch()
    _ = idle.look(pressing: false, option: false, shift: false, other: false, at: 0)
    check(idle.look(pressing: false, option: false, shift: false, other: false, at: 500) == nil, "gesture-1: with no press on, the backstop is silent")

    // A press still inside its debounce whose release was lost never becomes a turn.
    var pending = K.State()
    _ = pending.handle(.modifiers(option: true, shift: true, other: false, at: 0))
    var pendingWatch = K.ReleaseWatch()
    _ = pendingWatch.look(pressing: pending.pressing, option: false, shift: false, other: false, at: 20)
    let dropped = pendingWatch.look(pressing: pending.pressing, option: false, shift: false, other: false, at: 20 + K.ReleaseWatch.confirmMs)
    check(dropped.map { pending.handle($0) } == K.Action.none && pending.handle(.tick(at: 200)) == .none && pending.dueAt == nil,
          "gesture-1: a press let go unheard inside the debounce never starts a turn")

    // The tap came back on after the system turned it off: one look is enough, events were lost for sure.
    var afterOff = heldGestureKey()
    let resync = K.ReleaseWatch.afterTapCameBack(pressing: afterOff.pressing, option: false, shift: false, other: false, at: 4_000)
    check(resync.map { afterOff.handle($0) } == .finish(heldForMs: 4_000), "gesture-1: when the tap comes back on with the keys up, the turn ends at once")
    check(K.ReleaseWatch.afterTapCameBack(pressing: true, option: true, shift: true, other: false, at: 4_000) == nil,
          "gesture-1: when the tap comes back on with ⌥⇧ still down, the turn goes on")
    check(K.ReleaseWatch.afterTapCameBack(pressing: false, option: true, shift: true, other: false, at: 4_000) == nil,
          "gesture-1: the tap coming back never starts a press by itself")
}

// MARK: - team-5: the folder that counts is the one the session started in

private let fixT0 = Date(timeIntervalSince1970: 1_800_000_000)

private func teammateSubfolderTests() {
    var watch = ArisTeammateCompletion()
    let job = UUID()
    watch.expect(job: job, cwd: "/Users/x/proj", launchedAt: fixT0)
    _ = watch.observe("SessionStart", session: "s", cwd: "/Users/x/proj", agent: "claude", source: "startup", at: fixT0 + 2)
    check(watch.observe("Stop", session: "s", cwd: "/Users/x/proj/frontend", agent: "claude", at: fixT0 + 60) == .finished(job),
          "team-5: a session that changed into a subfolder still finishes its job on Stop")

    var closing = ArisTeammateCompletion()
    let closed = UUID()
    closing.expect(job: closed, cwd: "/Users/x/proj", launchedAt: fixT0)
    _ = closing.observe("SessionStart", session: "s", cwd: "/Users/x/proj/", agent: "claude", source: "startup", at: fixT0 + 2)
    check(closing.observe("SessionEnd", session: "s", cwd: "/tmp/elsewhere", agent: "claude", at: fixT0 + 60) == .closed(closed),
          "team-5: and its SessionEnd from another folder still closes it")

    // Where the Stop comes from never makes a session the job's: only where it started does.
    var other = ArisTeammateCompletion()
    let mine = UUID()
    other.expect(job: mine, cwd: "/Users/x/proj", launchedAt: fixT0)
    _ = other.observe("SessionStart", session: "sub", cwd: "/Users/x/proj/frontend", agent: "claude", source: "startup", at: fixT0 + 2)
    check(other.observe("Stop", session: "sub", cwd: "/Users/x/proj/frontend", agent: "claude", at: fixT0 + 9) == nil,
          "team-5: a session the user started himself in a subfolder doesn't finish the job")
    _ = other.observe("SessionStart", session: "wander", cwd: "/Users/x/else", agent: "claude", source: "startup", at: fixT0 + 2)
    check(other.observe("Stop", session: "wander", cwd: "/Users/x/proj", agent: "claude", at: fixT0 + 9) == nil,
          "team-5: a session from another folder that changed into the job's folder doesn't finish it")
    check(other.observe("SessionStart", session: "real", cwd: "/Users/x/proj", agent: "claude", source: "startup", at: fixT0 + 3) == nil
          && other.observe("Stop", session: "real", cwd: "/", agent: "claude", at: fixT0 + 20) == .finished(mine),
          "team-5: the job's own session does, wherever it ended up")
}

// MARK: - team-4: a job whose session is never heard from (no Claude hooks on this Mac)

private func teammateSilenceTests() {
    var watch = ArisTeammateCompletion()
    let job = UUID()
    check(!watch.started(job: job), "team-4: a job nobody waits for hasn't started")
    watch.expect(job: job, cwd: "/Users/x/proj", launchedAt: fixT0)
    check(!watch.started(job: job), "team-4: right after the launch no session was heard yet")
    _ = watch.observe("SessionStart", session: "before", cwd: "/Users/x/proj", agent: "claude", source: "startup", at: fixT0 - 30)
    _ = watch.observe("SessionStart", session: "elsewhere", cwd: "/Users/x/other", agent: "claude", source: "startup", at: fixT0 + 1)
    _ = watch.observe("SessionStart", session: "resumed", cwd: "/Users/x/proj", agent: "claude", source: "resume", at: fixT0 + 1)
    _ = watch.observe("SessionStart", session: "codex", cwd: "/Users/x/proj", agent: "codex", source: "startup", at: fixT0 + 1)
    check(!watch.started(job: job), "team-4: an older session, another folder, a resumed session or another agent isn't the job's session starting")
    _ = watch.observe("SessionStart", session: "s", cwd: "/Users/x/proj", agent: "claude", source: "startup", at: fixT0 + 4)
    check(watch.started(job: job), "team-4: a fresh session in the job's folder after the launch is")

    typealias S = ArisTeammateSilence
    check(S.decide(hooks: false, started: false) == .endUnwatched, "team-4: no hooks and no session heard: the job ends as opened but unwatched, not a day later")
    check(S.decide(hooks: true, started: false) == .nudge && S.decide(hooks: nil, started: false) == .nudge,
          "team-4: hooks there (or an agent that doesn't say) and nothing heard: the job keeps waiting and says where to look")
    check(S.decide(hooks: false, started: true) == .none && S.decide(hooks: true, started: true) == .none,
          "team-4: a session that was heard is waited for, whatever the settings file said")
    check(S.wait(hooks: false) == S.unwatchedAfter && S.wait(hooks: true) == S.nudgeAfter && S.wait(hooks: nil) == S.nudgeAfter
          && S.unwatchedAfter >= 20 && S.unwatchedAfter < S.nudgeAfter,
          "team-4: without hooks the look comes sooner, but never before the shell has read the prompt file")
    for korean in [true, false] {
        let said = ArisTeammateWords.unwatched(korean: korean)
        check(said.contains(korean ? "터미널" : "terminal") && said.contains(korean ? "훅" : "hooks") && !said.contains(korean ? "끝냈어요" : "is done"),
              "team-4: the unwatched line says Claude Code is open, why Aris can't tell when it ends, and where to look (\(korean ? "ko" : "en"))")
    }

    // The agent's look at Claude Code's settings (a parsed copy: the real file is never read here).
    let ours: [String: Any] = ["hooks": [["type": "http", "url": "http://127.0.0.1:23350/hook"]]]
    let theirs: [String: Any] = ["hooks": [["type": "command", "command": "~/clawd/hook.sh"]]]
    func settings(_ events: [String: [[String: Any]]], extra: [String: Any] = [:]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["hooks": events].merging(extra) { $1 })
    }
    check(ArisClaudeHookCheck.reports(settings(["SessionStart": [ours], "Stop": [theirs, ours], "SessionEnd": [ours]])),
          "team-4: Aris's hook on SessionStart and Stop: this Mac's Claude Code reports to Aris")
    check(!ArisClaudeHookCheck.reports(nil) && !ArisClaudeHookCheck.reports(Data("not json".utf8)) && !ArisClaudeHookCheck.reports(Data("{}".utf8)),
          "team-4: no settings file, an unreadable one or one without hooks: it doesn't")
    check(!ArisClaudeHookCheck.reports(settings(["SessionStart": [theirs], "Stop": [theirs]])), "team-4: someone else's hooks alone don't report to Aris")
    check(!ArisClaudeHookCheck.reports(settings(["SessionStart": [ours]])) && !ArisClaudeHookCheck.reports(settings(["Stop": [ours]])),
          "team-4: both the start and the stop must be hooked")
    check(!ArisClaudeHookCheck.reports(settings(["SessionStart": [ours], "Stop": [ours]], extra: ["disableAllHooks": true])),
          "team-4: hooks switched off altogether don't report")

    // The agent says what it found with the launch; an older agent says nothing.
    let launch = ArisTeammateLaunch(job: job, pid: 7, cwd: "/Users/x/proj", at: fixT0, window: nil, hooks: false)
    let line = String(data: ArisAgentReply.launched(launch).line, encoding: .utf8)
    check(line.flatMap(ArisAgentReply.parse) == .launched(launch), "team-4: the launch line carries whether the hooks are there")
    check(ArisAgentReply.parse(#"{"launched":{"job":"\#(job.uuidString)","pid":7,"cwd":"/Users/x/proj","at":1800000000}}"#)
          == .launched(ArisTeammateLaunch(job: job, pid: 7, cwd: "/Users/x/proj", at: fixT0, window: nil, hooks: nil)),
          "team-4: a launch line without it still reads (hooks unknown)")
}

// MARK: - imp-3: a Stop that is a question isn't the end

private func teammateQuestionTests() {
    typealias C = ArisTeammateCompletion
    check(C.asks("Which branch should I use?") && C.asks("I looked at both.\n\n**Which branch should I use?**\n") && C.asks("어느 브랜치로 할까요？")
          && C.asks("Should I \"force\" it?\"") && C.question(in: "Done so far.\n- Which one?") == "Which one?",
          "imp-3: a last line that ends in a question mark is a question (emphasis and quotes around it don't hide it)")
    check(!C.asks("All tests pass.") && !C.asks(nil) && !C.asks("") && !C.asks("Why did it fail? The path was wrong.\nFixed it.") && !C.asks("?"),
          "imp-3: a statement, nothing, or a question followed by its answer is not")
    check(C.question(in: String(repeating: "가", count: 300) + "?").map { $0.count <= C.questionLength + 1 && $0.hasSuffix("?") } == true,
          "imp-3: a very long question is cut from the front, keeping its end")

    var watch = C()
    let (job, next) = (UUID(), UUID())
    watch.expect(job: job, cwd: "/u/p", launchedAt: fixT0)
    watch.expect(job: next, cwd: "/u/p", launchedAt: fixT0 + 1)
    _ = watch.observe("SessionStart", session: "s1", cwd: "/u/p", agent: "claude", source: "startup", at: fixT0 + 2)
    _ = watch.observe("SessionStart", session: "s2", cwd: "/u/p", agent: "claude", source: "startup", at: fixT0 + 3)
    check(watch.observe("Stop", session: "s1", cwd: "/u/p", agent: "claude", asks: true, at: fixT0 + 10) == .asked(job) && watch.asked(job: job),
          "imp-3: a first Stop that asks the user something doesn't finish the job")
    check(watch.observe("Stop", session: "s2", cwd: "/u/p", agent: "claude", at: fixT0 + 11) == .finished(next) && !watch.asked(job: next),
          "imp-3: the other session in that folder finishes the other job, not the one that asked")
    check(watch.observe("Stop", session: "s1", cwd: "/u/p", agent: "claude", asks: true, at: fixT0 + 20) == .asked(job),
          "imp-3: it may ask again")
    check(watch.observe("Stop", session: "s1", cwd: "/u/p/sub", agent: "claude", at: fixT0 + 30) == .finished(job),
          "imp-3: the same session's next Stop that isn't a question finishes it")
    check(watch.observe("Stop", session: "s1", cwd: "/u/p", agent: "claude", at: fixT0 + 40) == nil, "imp-3: and only once")

    // A question left open isn't waited on for ever (Claude Code often ends finished work with an offer).
    var open = C()
    let offered = UUID()
    open.expect(job: offered, cwd: "/u/o", launchedAt: fixT0)
    _ = open.observe("SessionStart", session: "s", cwd: "/u/o", agent: "claude", source: "startup", at: fixT0 + 1)
    check(open.askedAt(job: offered) == nil, "imp-3: a job that never asked has no question waiting")
    _ = open.observe("Stop", session: "s", cwd: "/u/o", agent: "claude", asks: true, at: fixT0 + 5)
    check(open.askedAt(job: offered) == fixT0 + 5 && ArisTeammateSilence.askedOut(askedAt: fixT0 + 5, latest: open.askedAt(job: offered)),
          "imp-3: a question still open after the wait: Aris stops watching the job")
    _ = open.observe("Stop", session: "s", cwd: "/u/o", agent: "claude", asks: true, at: fixT0 + 90)
    check(!ArisTeammateSilence.askedOut(askedAt: fixT0 + 5, latest: open.askedAt(job: offered)),
          "imp-3: a newer question starts the wait again (the older wait ends nothing)")
    _ = open.observe("Stop", session: "s", cwd: "/u/o", agent: "claude", at: fixT0 + 120)
    check(!ArisTeammateSilence.askedOut(askedAt: fixT0 + 90, latest: open.askedAt(job: offered)), "imp-3: a job that went on to finish is never ended by an old wait")
    check(ArisTeammateSilence.askedWait >= 300 && ArisTeammateSilence.askedWait <= 1_800
          && ArisTeammateWords.unanswered("Want tests too?", korean: true).contains("터미널") && !ArisTeammateWords.unanswered(nil, korean: false).contains("is done"),
          "imp-3: the wait is minutes, and the line says Claude Code is still waiting in the terminal, not that it is done")

    var closing = C()
    let left = UUID()
    closing.expect(job: left, cwd: "/u/q", launchedAt: fixT0)
    _ = closing.observe("SessionStart", session: "s", cwd: "/u/q", agent: "claude", source: "startup", at: fixT0 + 1)
    _ = closing.observe("Stop", session: "s", cwd: "/u/q", agent: "claude", asks: true, at: fixT0 + 5)
    check(closing.observe("SessionEnd", session: "s", cwd: "/u/q", agent: "claude", at: fixT0 + 9) == .closed(left),
          "imp-3: the session closed with its question open ends the job")
    for korean in [true, false] {
        check(ArisTeammateWords.closed(asked: true, korean: korean) != ArisTeammateWords.closed(asked: false, korean: korean)
              && ArisTeammateWords.asks("Which branch?", korean: korean).hasSuffix("Which branch?")
              && ArisTeammateWords.asks("Which branch?", korean: korean).contains(korean ? "터미널" : "terminal")
              && !ArisTeammateWords.asks("Which branch?", korean: korean).contains(korean ? "끝냈어요" : "is done"),
              "imp-3: Aris says Claude Code is asking and where to answer, never that it is done (\(korean ? "ko" : "en"))")
    }
}

// MARK: - team-10, team-9: the scope table

private func scopeTableTests() {
    typealias S = ArisTeammateScope
    let all = Set(S.allCases)
    check(S.needed(forTools: ["shelf"]) == [.files] && S.refusal(scopes: all, arguments: ["shelf"]) == nil && S.refusal(scopes: [.files], arguments: ["shelf"]) == nil,
          "team-10: `aris-tools shelf` is in the table: a teammate with files may look at the shelf")
    check(S.refusal(scopes: [.web], arguments: ["shelf"])?.contains("files") == true, "team-10: without files it is refused, naming files")
    check(S.knownSubcommands.contains("shelf") && S.claudeDenied([.web], tools: "/t/aris-tools").contains("Bash(/t/aris-tools shelf:*)")
          && !S.claudeDenied([.files], tools: "/t/aris-tools").contains("Bash(/t/aris-tools shelf:*)"),
          "team-10: a Claude teammate's deny rules name the shelf only without files")

    // Skills: the user's own, switched on by them; reading one is a read, and every script run asks on its own card in the
    // agent (ArisSkillTool), so no brain needs the terminal switch for them (a Claude teammate has none to turn on).
    for call in [["skill", "list"], ["skill", "read", "x"], ["skill", "run", "x", "scripts/a.py"]] {
        check(S.refusal(scopes: [], arguments: call) == nil && S.refusal(scopes: Set(S.shown(brain: "claude")), arguments: call) == nil,
              "team-9: `aris-tools \(call.prefix(2).joined(separator: " "))` isn't locked behind the terminal switch")
    }
    check(!S.claudeDenied(Set(S.shown(brain: "claude")), tools: "/t/aris-tools").contains { $0.contains(" skill:") },
          "team-9: a Claude teammate with every switch it has on is not denied skills")
    check(S.permits(.shell("/t/aris-tools skill run x scripts/a.py"), scopes: [.files], tools: "/t/aris-tools")
          && !S.permits(.shell("python3 scripts/a.py"), scopes: [.files], tools: "/t/aris-tools"),
          "team-9: through the risk gate too; a script run any other way still needs the terminal")
}

// MARK: - team-8: a refusal names the switch and where to turn it on

private func scopeRefusalTests() {
    typealias S = ArisTeammateScope
    let line = S.refusal(scopes: [.web], arguments: ["schedule", "add"]) ?? ""
    check(line.hasPrefix("Refused") && line.contains("Don't try another way"), "team-8: a call outside the scopes is still refused, never run")
    check(line.contains("캘린더 · 미리 알림") && line.contains("설정 › 팀원") && line.contains("쓸 수 있는 것") && line.contains("tell the user"),
          "team-8: the refusal tells the brain to say which switch is off and that the user can turn it on in 설정 › 팀원")
    check(S.missingLine([.send, .files]).contains("‘파일’, ‘보내기’") && !S.missingLine([.files]).contains("보내기"),
          "team-8: every missing switch is named, in the page's order and words")
    check(S.refusalLine(nil).hasPrefix("Refused") && !S.refusalLine(nil).contains("설정 › 팀원") && S.refusalLine([]) == S.refusalLine(nil),
          "team-8: a call no switch would allow (an unknown command, the environment) gets no switch to point at")

    // What the gate stops on a teammate's own command (Codex), as the user reads it.
    check(S.missing(for: .shell("/t/aris-tools event add x"), scopes: [.files], tools: "/t/aris-tools") == [.calendar]
          && S.missing(for: .shell("python3 x.py"), scopes: [.files], tools: "/t/aris-tools") == [.terminal]
          && S.missing(for: .shell("cat a.txt"), scopes: [.web], tools: "/t/aris-tools") == [.files]
          && S.missing(for: .fileChange(["a"]), scopes: [], tools: "/t/aris-tools") == [.files]
          && S.missing(for: .computerUse(app: "Notes"), scopes: [.files], tools: "/t/aris-tools") == [.apps]
          && S.missing(for: .browserTask("x"), scopes: [.files], tools: "/t/aris-tools") == [.aside]
          && S.missing(for: .shell("/t/aris-tools event add x"), scopes: [.calendar], tools: "/t/aris-tools").isEmpty
          && S.missing(for: .shell("env -u ARIS_TEAMMATE_SCOPES ls"), scopes: [.files], tools: "/t/aris-tools").isEmpty,
          "team-8: the switch an action needs and lacks; none for one that fits, or one no switch allows")
    let stop = ArisCodexDriver.scopeStop(missing: [.calendar])
    check(stop.contains("‘캘린더 · 미리 알림’") && stop.contains("설정 › 팀원") && ArisCodexDriver.scopeStop(missing: []).contains("설정 › 팀원")
          && !ArisCodexDriver.scopeStop(missing: []).contains("‘"),
          "team-8: a Codex teammate stopped by the gate says which switch is off and where to turn it on")

    // The teammate's own prompt: what is off for it, and what to tell the user when the job needs it.
    let block = ArisTeamPrompt.job(ArisTeammate(id: "mate-t", name: "번역이", routing: "", instructions: "", look: .standard, brain: "codex",
                                                scopes: ["web"], memoryFile: ""), notes: [])
    check(block.contains("You may use: the web.") && block.contains("“파일”") && block.contains("Settings › 팀원") && !block.contains("“웹”"),
          "team-8: a teammate's prompt lists the switches that are off for it by their names on the page, and says to tell the user where to turn one on")
    let open = ArisTeamPrompt.job(ArisTeammate(id: "mate-o", name: "만능", routing: "", instructions: "", look: .standard, brain: "codex",
                                               scopes: ArisTeammateScope.allCases.map(\.rawValue), memoryFile: ""), notes: [])
    check(!open.contains("Off for you"), "team-8: a teammate with everything on has nothing listed as off")
}

// MARK: - team-8: a teammate made by voice starts with what its job obviously needs

private func voiceMadeScopeTests() {
    func made(_ said: String) -> ArisTeammate? {
        ArisTeamMaking.parse(said).flatMap { ArisTeamMaking.make($0, in: [.claudeCode], aris: .star, brain: "claude") }
    }
    check(made("번역하는 팀원 만들어줘, 이름은 번역이").map { $0.scopes == ["files"] } == true,
          "team-8: “번역하는 팀원” starts with files (it could do nothing before)")
    check(made("메일 정리하는 팀원 하나 만들어줘").map { Set($0.scopes) == ["files", "mail"] } == true,
          "team-8: a mail teammate may read mail as well as the docs template's files")
    check(made("뉴스 검색하고 일정 잡아주는 팀원 만들어줘, 이름은 비서").map { Set($0.scopes).isSuperset(of: ["web", "calendar"]) } == true,
          "team-8: a role that names the web and the calendar gets both")
    check(made("make a teammate that translates documents, named Lin").map { $0.scopes.contains("files") } == true
          && made("create a teammate that looks up prices on the web").map { $0.scopes.contains("web") } == true,
          "team-8: the same in English")
    check(made("메일 답장 보내는 팀원 만들어줘").map { !$0.scopes.contains("send") && !$0.scopes.contains("apps") && !$0.scopes.contains("terminal") && !$0.scopes.contains("aside") } == true,
          "team-8: sending, using apps, websites through Aside and the terminal are never switched on from spoken words")
    check(made("숫자 계산만 하는 팀원 하나 만들어 줘, 이름은 큐에이봇").map { $0.scopes.isEmpty } == true
          && made("식물 물 주는 팀원 만들어줘, 이름은 초록이").map { $0.scopes.isEmpty } == true
          && made("팀원 하나 만들어줘").map { $0.scopes.isEmpty } == true,
          "team-8: a role that needs nothing (or no role at all) still starts with nothing")
    check(made("코딩하는 팀원 만들어줘").map { Set($0.scopes) == ["files", "terminal"] } == true,
          "team-8: a template's own scopes are kept as they were")
    check(ArisTeamMaking.scopes(forRole: "번역") == [.files] && ArisTeamMaking.scopes(forRole: nil).isEmpty
          && ArisTeamMaking.scopes(forRole: "webcam 보는").isEmpty,
          "team-8: the role's words are matched as words (an English word inside another doesn't count)")
    check(made("메일 정리하는 팀원 하나 만들어줘").map { $0.scopes == ArisTeammateScope.canonical($0.scopes) } == true,
          "team-8: the scopes are stored in the page's order")
}

// MARK: - team-11: made or removed by voice is said only as the save ended

private func teamSaveRuleTests() {
    typealias R = ArisTeamSaveRule
    check(R.retries(unreachable: true, attempt: 1) && !R.retries(unreachable: true, attempt: 2),
          "team-11: a save that couldn't reach the agent (it may be restarting) is tried once more, not for ever")
    check(!R.retries(unreachable: false, attempt: 1), "team-11: a save the agent answered (stored or refused) is never sent again")
    check(R.retryDelay >= .seconds(1) && R.retryDelay <= .seconds(5), "team-11: the retry waits long enough for a restarting agent, not long enough to seem stuck")
    check(R.madeLine(saved: true, name: "코디") == ArisTeamCopy.made("코디") && R.madeLine(saved: false, name: "코디") == ArisTeamCopy.madeFailed
          && R.madeLine(saved: false, name: "코디") != R.madeLine(saved: true, name: "코디"),
          "team-11: “made” is said only when the teammate was stored; a failed save says it wasn't saved")
    check(R.removedLine(saved: true, name: "코디") == ArisTeamCopy.removed("코디") && R.removedLine(saved: false, name: "코디") == ArisTeamCopy.removeFailed("코디")
          && R.removedLine(saved: false, name: "코디").contains("코디") && R.removedLine(saved: false, name: "코디") != R.removedLine(saved: true, name: "코디"),
          "team-11: “removed” is said only when the list was stored; a failed save says the teammate is still there")
}

// MARK: - imp-2: a Claude Code job with no folder

private func teammateFolderTests() {
    typealias F = ArisTeammateFolder
    let home = "/Users/x"
    func session(_ cwd: String, _ ago: TimeInterval, agent: String = "claude") -> F.Session {
        F.Session(cwd: cwd, lastEvent: fixT0 - ago, agent: agent)
    }
    check(F.isMissing(nil) && F.isMissing("") && F.isMissing("  ") && !F.isMissing("~/proj"), "imp-2: no folder, or only spaces, is a missing folder")
    check(F.proposed([session("/Users/x/old", 900), session("/Users/x/proj/", 30), session("/Users/x/codex", 5, agent: "codex")], home: home) == "/Users/x/proj",
          "imp-2: the most recently active Claude Code session's folder is proposed")
    check(F.proposed([session("/Users/x", 5), session("/tmp/work", 6), session("/Users/x/Library/Application Support/a", 7), session("/Users/xy/proj", 8)], home: home) == nil
          && F.proposed([], home: home) == nil,
          "imp-2: never the home folder itself, ~/Library or a folder outside home; with no session nothing is proposed")
    for korean in [true, false] {
        check(F.proposingStep("/Users/x/proj", home: home, korean: korean).contains("~/proj") && F.noFolder(korean: korean).contains("~/Projects"),
              "imp-2: the row names the proposed folder, and with none the line says how to name one (\(korean ? "ko" : "en"))")
    }
}

// MARK: - imp-1: a circle drawn just before the key is let go

/// A display's clean frame, handed out after `delay` (a capture that is still under way).
private final class FixSlowScreen: ArisGestureFrameSource, @unchecked Sendable {
    let image: CGImage
    let delay: Duration
    init(_ image: CGImage, delay: Duration) {
        self.image = image
        self.delay = delay
    }
    func frame(display: CGDirectDisplayID, budget: ArisImageBudget, showsCursor: Bool) async -> CGImage? {
        try? await Task.sleep(for: delay)
        return image
    }
}

@MainActor private func lateCircleTests() {
    func textured(_ w: Int, _ h: Int) -> CGImage {
        var state: UInt32 = 7
        var bytes = [UInt8](repeating: 255, count: w * h * 4)
        for i in 0..<(w * h) {
            state = state &* 1_664_525 &+ 1_013_904_223
            let v = UInt8(120 + Int(state >> 28))
            bytes[i * 4] = v; bytes[i * 4 + 1] = v; bytes[i * 4 + 2] = v
        }
        let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }
    func spin(_ seconds: Double = 5, until done: () -> Bool) {
        let deadline = Date().addingTimeInterval(seconds)
        while !done(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
    }
    let display = ArisGestureScreen(id: 7, frame: CGRect(x: 0, y: 0, width: 756, height: 491))
    func service(delay: Duration) -> ArisGestureCapture {
        ArisGestureCapture(dependencies: .init(screen: FixSlowScreen(textured(1512, 982), delay: delay), windowsAt: { _ in [] },
                                               displayBounds: { _ in CGRect(x: 0, y: 0, width: 756, height: 491) }, now: { 50_000 }, secureInput: { false }))
    }
    func loop(_ origin: CGPoint) -> ArisGesture {
        let points = (0...24).map { i -> ArisGesturePoint in
            let a = Double(i) / 24 * 2 * Double.pi
            return ArisGesturePoint(x: origin.x + 60 * cos(a), y: origin.y + 40 * sin(a), t: 49_400 + Double(i) * 25)
        }
        return ArisGesture(kind: .circle, bbox: CGRect(x: origin.x - 60, y: origin.y - 40, width: 120, height: 80), points: points)
    }
    func request(_ id: Int, badge: Int, _ gesture: ArisGesture) -> ArisGestureCaptureRequest {
        ArisGestureCaptureRequest(captureId: id, badge: badge, revision: 0, gesture: gesture, screen: display, hit: nil,
                                  inkAfterMs: 0, strokes: [gesture.points], handsFree: false)
    }
    func collected(_ capture: ArisGestureCapture) -> ArisGestureResult? {
        var result: ArisGestureResult??
        Task { @MainActor in result = .some(await capture.collect()) }
        spin { result != nil }
        return result ?? nil
    }

    // The circle closes, its shot is still being made, and the key is let go: the shot is in the turn's result.
    let capture = service(delay: .milliseconds(150))
    capture.strokeStarted(on: display)
    let circle = loop(CGPoint(x: 300, y: 250))
    capture.pickWindow(captureId: 1, for: circle, on: display, handsFree: false) { _ in }
    var done: Bool?
    capture.capture(request(1, badge: 1, circle)) { done = $0 }
    capture.finalize(strokes: [7: [circle.points]], handsFree: false)
    // The session reducer, finalized by now, calls the late shot dropped: the result still has it.
    spin { done != nil }
    capture.drop(captureId: 1, reason: "finalized")
    let result = collected(capture)
    check(done == true && result?.shots.map(\.badge) == [1] && result?.references.count == 1,
          "imp-1: a circle whose shot was still being made when the key was let go is kept in the turn's result")
    check(capture.heldFrames == 0 && capture.keptBadges.isEmpty, "imp-1: nothing of the finished session is left held")

    // Shots kept before the release come with it, in order.
    let both = service(delay: .milliseconds(60))
    both.strokeStarted(on: display)
    let first = loop(CGPoint(x: 200, y: 200)), second = loop(CGPoint(x: 500, y: 300))
    both.pickWindow(captureId: 1, for: first, on: display, handsFree: false) { _ in }
    var firstDone: Bool?
    both.capture(request(1, badge: 1, first)) { firstDone = $0 }
    spin { firstDone != nil }
    both.keep(captureId: 1, badge: 1)
    both.pickWindow(captureId: 2, for: second, on: display, handsFree: false) { _ in }
    both.capture(request(2, badge: 2, second)) { _ in }
    both.finalize(strokes: [7: [first.points, second.points]], handsFree: false)
    check(collected(both)?.shots.map(\.badge) == [1, 2], "imp-1: with the shots kept before it, numbered in order")

    // A turn dropped instead of released keeps nothing, late or not.
    let dropped = service(delay: .milliseconds(60))
    dropped.strokeStarted(on: display)
    dropped.pickWindow(captureId: 1, for: circle, on: display, handsFree: false) { _ in }
    var droppedDone: Bool?
    dropped.capture(request(1, badge: 1, circle)) { droppedDone = $0 }
    dropped.abort()
    spin { droppedDone != nil }
    check(droppedDone == false && !dropped.isParked, "imp-1: a cancelled turn still keeps nothing")

    // A new turn right after the release never gets the old turn's late shot.
    let next = service(delay: .milliseconds(120))
    next.strokeStarted(on: display)
    next.pickWindow(captureId: 1, for: circle, on: display, handsFree: false) { _ in }
    var staleDone: Bool?
    next.capture(request(1, badge: 1, circle)) { staleDone = $0 }
    next.finalize(strokes: [7: [circle.points]], handsFree: false)
    next.dropParked() // the next ⌥⇧ press (ArisGestureHooks.begin)
    next.finalize(strokes: [7: [second.points]], handsFree: false)
    spin { staleDone != nil }
    check(collected(next)?.shots.isEmpty == true, "imp-1: a late shot never lands in the next turn's result")
}
