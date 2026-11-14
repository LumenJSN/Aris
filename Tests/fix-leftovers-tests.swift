// Tests for the items left over by the night's fix branches (qa/audit-1110: notch.json hook-1 and claude-1,
// firstrun.json practice-calendar, typed-confirm-korean, no-agent-no-os-check, imp-shortcut-anchor, imp-brain-status,
// and the smaller ones the other agents handed on). Everything here is a pure rule or runs on a fake: no port is
// opened, no app is asked what is running, no volume, panel or setting of the user's is touched.
// Called from main.swift; uses its check().
import AppKit
import CoreAudio
import Foundation

func runFixLeftoversTests() {
    hookRetryTests()
    sessionSweepTests()
    MainActor.assumeIsolated { storeSweepTests() }
    limitReachedTests()
    MainActor.assumeIsolated { limitBannerTests() }
    calendarLineTests()
    practiceExampleTests()
    typedConfirmTests()
    prerequisiteTests()
    settingsLinkTests()
    brainStatusTests()
    writtenTimeTests()
    volumeLimitTests()
    sideMenuTests()
    settingsCopyEngineTests()
    MainActor.assumeIsolated { settingsCopyPageTests() }
}

private func leftoversAt(_ minutes: Double) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + minutes * 60) }

// MARK: - hook-1: the hook server comes back within a second or two of "Aris 다시 시작"

private func hookRetryTests() {
    check((1...5).map(ClaudeHookRetry.retryWait) == [1, 2, 4, 8, 16],
          "hook retry: the port is tried again after 1 s, then 2, 4, 8, 16 (it was 15 s before the first)")
    check(ClaudeHookRetry.retryWait(9) == 256 && ClaudeHookRetry.retryWait(10) == 300 && ClaudeHookRetry.retryWait(500) == 300,
          "hook retry: the wait stops growing at five minutes")
    check(ClaudeHookRetry.retryWait(0) == 1 && ClaudeHookRetry.retryWait(-3) == 1, "hook retry: a count below one is the first wait")
    check((1...4).map(ClaudeHookRetry.retryWait).reduce(0, +) <= 15,
          "hook retry: four tries fit in the time one used to take")
}

// MARK: - claude-1: sessions that can't say they ended leave the list

private func leftoverSession(_ id: String, _ state: ClaudeState, quiet minutes: Double, agent: String = "claude", terminal: TerminalRef? = nil) -> ClaudeSession {
    var session = ClaudeSession(id: id, cwd: "/p/\(id)", state: state, lastEvent: leftoversAt(-minutes))
    session.agent = agent
    session.terminal = terminal
    return session
}

private func sessionSweepTests() {
    let now = leftoversAt(0)
    func kept(_ session: ClaudeSession, running: Set<String>? = nil, seen: Set<String> = []) -> ClaudeSession? {
        ClaudeSessionSweep.swept([session.id: session], now: now, runningApps: running, terminalSeen: seen).sessions[session.id]
    }
    check(kept(leftoverSession("a", .idle, quiet: 119)) != nil && kept(leftoverSession("a", .idle, quiet: 120)) == nil
          && kept(leftoverSession("a", .building, quiet: 121)) == nil,
          "sweep: a session not heard from for two hours goes, resting or not")
    check(kept(leftoverSession("c", .idle, quiet: 14, agent: "codex")) != nil && kept(leftoverSession("c", .idle, quiet: 15, agent: "codex")) == nil
          && kept(leftoverSession("c", .happy, quiet: 16, agent: "codex")) == nil,
          "sweep: a Codex session resting for 15 minutes goes (Codex has no SessionEnd)")
    check(kept(leftoverSession("c", .building, quiet: 40, agent: "codex"))?.state == .building
          && kept(leftoverSession("c", .notification, quiet: 40, agent: "codex")) != nil,
          "sweep: a Codex session in the middle of a turn, or waiting on the user, stays")
    check(kept(leftoverSession("a", .idle, quiet: 90)) != nil && kept(leftoverSession("g", .idle, quiet: 90, agent: "gemini")) != nil,
          "sweep: a resting Claude or Gemini session stays its two hours (they say when they end)")
    let long = leftoverSession("a", .building, quiet: 59), stuck = leftoverSession("a", .building, quiet: 60)
    check(kept(long)?.state == .building && kept(stuck)?.state == .idle && kept(stuck)?.lastEvent == stuck.lastEvent,
          "sweep: a working session silent for an hour is shown resting, and a 59-minute build is still working")
    check([ClaudeState.thinking, .typing, .juggling].allSatisfy { kept(leftoverSession("a", $0, quiet: 61))?.state == .idle }
          && kept(leftoverSession("a", .notification, quiet: 61))?.state == .notification && kept(leftoverSession("a", .error, quiet: 61))?.state == .error,
          "sweep: only the working states rest; one waiting on the user or failed keeps saying so")

    let terminal = leftoverSession("t", .thinking, quiet: 2, terminal: .app("com.mitchellh.ghostty"))
    let first = ClaudeSessionSweep.swept(["t": terminal], now: now, runningApps: ["com.mitchellh.ghostty", "com.apple.finder"])
    check(first.sessions["t"] != nil && first.terminalSeen == ["t"], "sweep: a session whose terminal app is running stays, and that is noted")
    check(kept(terminal, running: ["com.apple.finder"], seen: first.terminalSeen) == nil,
          "sweep: once that terminal app has quit, the session goes even in the middle of a turn")
    check(kept(terminal, running: ["com.apple.finder"]) != nil,
          "sweep: a terminal app never seen running is no reason (the app a hook names can be a guess)")
    check(kept(terminal, running: nil, seen: ["t"]) != nil, "sweep: with the running apps unknown, no session goes for its terminal")
    check(kept(leftoverSession("n", .idle, quiet: 2), running: [], seen: ["n"]) != nil, "sweep: a session with no terminal named is left to the other rules")
    let iterm = leftoverSession("i", .idle, quiet: 2, terminal: .iterm("id")), warp = leftoverSession("w", .idle, quiet: 2, terminal: .warp(URL(string: "warp://session/0")!))
    check(kept(iterm, running: ["com.googlecode.iterm2"], seen: ["i"]) != nil && kept(iterm, running: ["dev.warp.Warp-Stable"], seen: ["i"]) == nil
          && kept(warp, running: ["dev.warp.Warp-Preview"], seen: ["w"]) != nil && kept(warp, running: ["com.googlecode.iterm2"], seen: ["w"]) == nil,
          "sweep: an iTerm tab lives in iTerm and a Warp session in any Warp build")
    let two = ClaudeSessionSweep.swept(["t": terminal, "old": leftoverSession("old", .idle, quiet: 500)], now: now, runningApps: ["com.mitchellh.ghostty"], terminalSeen: ["old", "gone"])
    check(two.terminalSeen == ["t"] && Set(two.sessions.keys) == ["t"], "sweep: what was noted about a session goes with it")
}

@MainActor
private func storeSweepTests() {
    let store = ClaudeStore()
    check(!store.isSweeping, "store sweep: with no session listed nothing is looked at")
    let start = leftoversAt(0)
    var apps: Set<String> = ["com.mitchellh.ghostty"]
    store.runningApps = { apps }
    store.apply(ClaudeHookEvent(json: ["hook_event_name": "UserPromptSubmit", "session_id": "live", "cwd": "/p/live"], headers: ["x-bundle-id": "com.mitchellh.ghostty"])!, now: start)
    store.apply(ClaudeHookEvent(json: ["hook_event_name": "Stop", "session_id": "codex", "cwd": "/p/codex"], headers: ["x-agent": "codex"])!, now: start)
    check(store.isSweeping && store.sessions.count == 2, "store sweep: the look starts with the first session")
    store.focus("codex")
    store.sweep(now: start.addingTimeInterval(10 * 60))
    check(store.sessions.count == 2, "store sweep: ten minutes on, both sessions are still listed")
    store.sweep(now: start.addingTimeInterval(16 * 60))
    check(store.sessions["codex"] == nil && store.sessions["live"] != nil && store.focusedSessionId == nil,
          "store sweep: the finished Codex session leaves the list after 15 minutes, and is no longer the picked one")
    apps = ["com.apple.finder"]
    store.sweep(now: start.addingTimeInterval(17 * 60))
    check(store.sessions.isEmpty && !store.hasSessions && !store.isSweeping,
          "store sweep: the session whose terminal was closed goes, the closed notch is free, and the look stops")
    store.apply(event(["hook_event_name": "PreToolUse", "session_id": "back", "tool_name": "Bash"]), now: start.addingTimeInterval(18 * 60))
    check(store.isSweeping && store.sessions["back"]?.state == .building, "store sweep: a new session starts the look again")
    store.sweep(now: start.addingTimeInterval(80 * 60))
    check(store.sessions["back"]?.state == .idle && store.displayState == .idle, "store sweep: a session that died mid-work stops showing 작업 중 after an hour")
    store.apply(event(["hook_event_name": "SessionEnd", "session_id": "back"]), now: start.addingTimeInterval(81 * 60))
    check(!store.isSweeping, "store sweep: the last session ending stops the look")
}

// MARK: - the 80 % / 95 % banner names the limit that was reached

private func leftoverReport(five: Double? = nil, week: Double? = nil, cost: Double? = nil, session: String = "s") -> ClaudeStatusReport {
    var limits: [String: Any] = [:]
    if let five { limits["five_hour"] = ["used_percentage": five, "resets_at": 1_800_000_000] }
    if let week { limits["seven_day"] = ["used_percentage": week, "resets_at": 1_800_300_000] }
    var json: [String: Any] = ["session_id": session, "context_window": ["used_percentage": 5]]
    if !limits.isEmpty { json["rate_limits"] = limits }
    if let cost { json["cost"] = ["total_cost_usd": cost] }
    return ClaudeStatusReport(json: json)!
}

private func limitReachedTests() {
    let now = leftoversAt(0)
    let old = ClaudeUsage(fiveHour: UsageWindow(percent: 70, resetsAt: Date(timeIntervalSince1970: 1_800_000_000)),
                          sevenDay: UsageWindow(percent: 78, resetsAt: Date(timeIntervalSince1970: 1_800_300_000)), updatedAt: now)
    func find(_ report: ClaudeStatusReport, before: Double = 0, after: Double = 0, budget: Double? = nil, ring: ClaudeLimitWindow = .fiveHour) -> ClaudeLimitReached? {
        ClaudeLimitReached.find(old: old, report: report, spentBefore: before, spentAfter: after, budget: budget, ringWindow: ring, now: now)
    }
    check(find(leftoverReport(five: 75, week: 79)) == nil, "limit reached: below every line there is no banner")
    let five = find(leftoverReport(five: 81, week: 79))
    check(five?.detail == "5-hour limit" && five?.title == "80% used" && five?.message(resetTime: { _ in "7:10 PM" }) == "Resets at 7:10 PM",
          "limit reached: the 5-hour limit passing 80 % is said as before")
    let week = find(leftoverReport(five: 75, week: 82))
    check(week?.detail == "weekly limit" && week?.title == "80% used" && week?.message(resetDay: { _ in "Tue 9:00 AM" }) == "Resets Tue 9:00 AM",
          "limit reached: the weekly limit passing 80 % is called the weekly limit, with the day it resets")
    check(find(leftoverReport(five: 81, week: 96))?.detail == "weekly limit" && find(leftoverReport(five: 81, week: 96))?.title == "95% used",
          "limit reached: with two at once the higher line is the one said")
    check(find(leftoverReport(five: 81, week: 81), ring: .sevenDay)?.detail == "weekly limit" && find(leftoverReport(five: 81, week: 81))?.detail == "5-hour limit",
          "limit reached: on a tie it is the one the ear's ring shows")
    let budget = find(leftoverReport(cost: 4.1), before: 3.9, after: 4.1, budget: 5)
    check(budget == .budget(threshold: 80, spent: 4.1, budget: 5) && budget?.detail == "daily budget" && budget?.title == "80% used"
          && budget?.message() == "$4.10 of $5 today", "limit reached: an API key's spend passing 80 % of the budget is called the daily budget")
    check(find(leftoverReport(cost: 4.9), before: 3.9, after: 4.9, budget: 5)?.title == "95% used"
          && find(leftoverReport(cost: 4.9), before: 4.8, after: 4.9, budget: 5) == nil,
          "limit reached: the budget warns again at 95 %, once")
    check(find(leftoverReport(cost: 4.1), before: 3.9, after: 4.1, budget: nil) == nil, "limit reached: with the budget off, spending shows no banner")
    check(ClaudeLimitReached.find(old: nil, report: leftoverReport(five: 99), spentBefore: 0, spentAfter: 0, budget: nil, ringWindow: .fiveHour, now: now) == nil,
          "limit reached: the first report of a run is where things stand, not a line passed")
    check(ClaudeUsageWords.ringLabel(.limit(.sevenDay, 20.2)) == "Claude, weekly limit 21 percent used"
          && ClaudeUsageWords.ringLabel(.limit(.fiveHour, 63)) == "Claude, 5-hour limit 63 percent used"
          && ClaudeUsageWords.ringLabel(.budget(spent: 1.24, budget: 5)) == "Claude, today $1.24 of $5 budget",
          "ring label: VoiceOver hears which limit a small ring shows, and the money for the budget's")
}

@MainActor
private func limitBannerTests() {
    let now = leftoversAt(0)
    let weekly = ClaudeStore()
    weekly.applyStatus(leftoverReport(five: 30, week: 78), now: now)
    weekly.applyStatus(leftoverReport(five: 31, week: 81), now: now.addingTimeInterval(60))
    check(weekly.currentPeek?.kind == .limit && weekly.currentPeek?.detail == "weekly limit" && weekly.currentPeek?.title == "80% used",
          "banner: the weekly limit passing 80 % shows a banner that says weekly (it said nothing before)")

    let defaults = UserDefaults(suiteName: testSuiteName("aris-leftovers-budget-tests"))!
    defaults.removePersistentDomain(forName: testSuiteName("aris-leftovers-budget-tests"))
    defaults.set(2.0, forKey: ClaudeBudget.amountKey)
    let key = ClaudeStore(spendStore: defaults)
    // An API key: a session that spends and never reports a plan's limits.
    key.applyStatus(leftoverReport(cost: 0, session: "k"), now: now)
    key.applyStatus(leftoverReport(cost: 1.0, session: "k"), now: now.addingTimeInterval(60))
    check(key.spend.plan == .apiKey && key.currentPeek == nil, "banner: half the daily budget is no banner")
    key.applyStatus(leftoverReport(cost: 1.7, session: "k"), now: now.addingTimeInterval(120))
    check(key.currentPeek?.kind == .limit && key.currentPeek?.detail == "daily budget" && key.currentPeek?.message == "$1.70 of $2 today",
          "banner: an API key passing 80 % of the daily budget is told so, with the money")
    key.dismissPeek()
    defaults.set(false, forKey: ClaudeBudget.onKey)
    key.applyStatus(leftoverReport(cost: 1.95, session: "k"), now: now.addingTimeInterval(180))
    check(key.currentPeek == nil, "banner: with the budget switched off there is none")
    defaults.removePersistentDomain(forName: testSuiteName("aris-leftovers-budget-tests"))
}

// MARK: - the calendar's no-access line, the guide's example question, the typed confirm words

private func leftoversRoot() -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
}

private func leftoversSource(_ path: String) -> String {
    (try? String(contentsOf: leftoversRoot().appendingPathComponent(path), encoding: .utf8)) ?? ""
}

/// A key's Korean and English values in the app's string catalog.
private func leftoversCatalog(_ key: String) -> (ko: String, en: String) {
    let data = (try? Data(contentsOf: leftoversRoot().appendingPathComponent("Aris/Localizable.xcstrings"))) ?? Data()
    let strings = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["strings"] as? [String: Any]
    let places = (strings?[key] as? [String: Any])?["localizations"] as? [String: Any]
    func value(_ language: String) -> String {
        ((places?[language] as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String ?? ""
    }
    return (value("ko"), value("en"))
}

private func calendarLineTests() {
    let line = ArisEventRoute.noAccessLine
    check(line.contains("System Settings → Privacy & Security → Calendars") && !line.contains("panel") && !line.contains("권한 button"),
          "calendar: with no access the line names System Settings only (the calendar panel's button may be switched off)")
}

private func practiceExampleTests() {
    let line = leftoversCatalog("onboarding.ask.line")
    check(!line.ko.isEmpty && !line.en.isEmpty && ArisOnboardingPractice.question(line.ko) == .time && ArisOnboardingPractice.question(line.en) == .time,
          "practice: the guide's example question is the time, in both languages: it needs no permission, so a new Mac answers it")
    check(ArisOnboardingPractice.question(ArisOnboardingCopy.askLine) == .time, "practice: and the line the guide draws is that one")
    if case .calendar = ArisOnboardingPractice.question(line.ko) { check(false, "practice: the example never needs Calendars") }
    if case .calendar = ArisOnboardingPractice.question(line.en) { check(false, "practice: the example never needs Calendars (English)") }
}

private func typedConfirmTests() {
    let wipe = ArisTypedConfirm.wipeWord, remove = ArisTypedConfirm.uninstallWord
    check(ArisTypedConfirm.shown(wipe, english: true) == "erase" && ArisTypedConfirm.shown(remove, english: true) == "remove"
          && ArisTypedConfirm.shown(wipe, english: false) == "지우기" && ArisTypedConfirm.shown(remove, english: false) == "제거",
          "typed confirm: an English UI asks for erase and remove, a Korean one for 지우기 and 제거")
    check(ArisTypedConfirm.matches("erase", wipe) && ArisTypedConfirm.matches(" Erase\n", wipe) && ArisTypedConfirm.matches("REMOVE", remove),
          "typed confirm: the English word is the answer, in any capitals, spaces around it aside")
    check(!ArisTypedConfirm.matches("erase", remove) && !ArisTypedConfirm.matches("remove", wipe) && !ArisTypedConfirm.matches("eras", wipe)
          && !ArisTypedConfirm.matches("erase it", wipe) && !ArisTypedConfirm.matches("delete", wipe) && !ArisTypedConfirm.matches("", remove),
          "typed confirm: the other act's word, a part of the word or another word is not")
    check(ArisTypedConfirm.matches("지우기", wipe) && ArisTypedConfirm.matches("제거", remove) && !ArisTypedConfirm.matches("지우기", remove),
          "typed confirm: the Korean words work as before")
    check([wipe, remove].allSatisfy { ArisTypedConfirm.matches(ArisTypedConfirm.shown($0, english: true), $0) && ArisTypedConfirm.matches(ArisTypedConfirm.shown($0, english: false), $0) },
          "typed confirm: the word the prompt shows always enables the button")
    let english = ArisTypedConfirm.prompt(wipe, english: true), korean = ArisTypedConfirm.prompt(remove, english: false)
    check(english.before + english.word + english.after == "Type erase to confirm" && korean.before + korean.word + korean.after == "확인하려면 제거라고 써 주세요",
          "typed confirm: the prompt is written around the word in the UI's language")
    // The agent checks the word again with the same rule before it removes anything.
    let route = leftoversSource("ArisAgent/ArisDataRoute.swift")
    check(route.contains("ArisTypedConfirm.matches(object[\"confirm\"] as? String ?? \"\", ArisTypedConfirm.wipeWord)")
          && route.contains("ArisTypedConfirm.matches(object[\"confirm\"] as? String ?? \"\", ArisTypedConfirm.uninstallWord)"),
          "typed confirm: the agent's second check is the same rule, so the English word passes there too")
}

// MARK: - no-agent-no-os-check: what an install lacks is said, not met as a silent failure

private func prerequisiteTests() {
    typealias P = ArisPrerequisites
    check(P.missing(osMajor: 27, helperInstalled: true).isEmpty && P.missing(osMajor: 26, helperInstalled: true).isEmpty,
          "prerequisites: macOS 26 or later with the helper installed lacks nothing")
    // legacy-speech: macOS 14 and 15 talk with the older speech engine (ArisListenEngine); talking is never missing.
    check(P.missing(osMajor: 15, helperInstalled: true).isEmpty && P.missing(osMajor: 14, helperInstalled: true).isEmpty,
          "prerequisites: on macOS 14 and 15 nothing is missing (the older speech engine listens there)")
    check(P.missing(osMajor: 27, helperInstalled: false) == [.helper] && P.missing(osMajor: 15, helperInstalled: false) == [.helper],
          "prerequisites: an Aris.app without its helper says so, and first: nothing answers without it")
    // The listener is no longer gated on a macOS: it picks its engine (ArisListenEngine).
    let listener = leftoversSource("Aris/private/Aris/ArisListener.swift"), key = leftoversSource("Aris/private/Aris/ArisController.swift")
    check(listener.contains("@MainActor\nfinal class ArisListener") && !listener.contains("@available(macOS 26.0, *)\n@MainActor\nfinal class ArisListener")
          && !key.contains("guard #available(macOS 26.0, *) else"),
          "prerequisites: the listener and the talk key have no macOS gate")
    check(!leftoversSource("Aris/private/Aris/ArisController+Typed.swift").contains("#available"),
          "prerequisites: a typed request has no macOS gate, so 'typing works' is true")
    check(P.helperPath(app: "/Applications/Aris.app") == "/Applications/Aris.app/Contents/MacOS/aris-agent"
          && P.helperInstalled(app: "/Applications/Aris.app") { $0.hasPrefix("/Applications/Aris.app/Contents/MacOS/aris-") } && !P.helperInstalled(app: "/Applications/Aris.app") { _ in false },
          "prerequisites: the helper is installed when the app carries it inside (one row: no installer puts it anywhere)")

    check(P.line(.helper, english: true) == "This copy of Aris has no helper inside it" && P.line(.helper, english: false) == "이 Aris에는 도우미가 들어 있지 않아요",
          "prerequisites: the short line says the app has no helper inside it")
    check(P.Missing.allCases.allSatisfy { missing in [true, false].allSatisfy { english in
        let full = P.full(missing, english: english)
        return full.hasPrefix(P.line(missing, english: english)) && full.count > P.line(missing, english: english).count + 10 && full.hasSuffix(".")
    } }, "prerequisites: the full line adds what to do")
    check(P.full(.helper, english: true).contains("install") && !P.full(.helper, english: true).contains(".sh") && !P.full(.helper, english: false).contains(".sh"),
          "prerequisites: what to do is said without a script's name")

    check(P.atLaunch([.helper]) == .helper && P.atLaunch([]) == nil,
          "prerequisites at launch: a missing helper is said at every launch, and a complete install hears nothing")

    typealias G = ArisSettingsCaption
    check(G.greeting(agentDown: true, missingPermissions: 2, noAI: true, missing: [.helper], english: false) == P.line(.helper, english: false)
          && G.greeting(agentDown: false, missingPermissions: 0, missing: [.helper], english: true) == "This copy of Aris has no helper inside it",
          "settings status: a helper that isn't installed is said before a lost connection (다시 시작 can't bring back what isn't there)")
    check(G.greeting(agentDown: true, missingPermissions: 0, missing: []) == "에이전트와 연결이 끊겼어요" && G.greeting(agentDown: false, missingPermissions: 0, noAI: true, missing: []) == G.noAI
          && G.greeting(agentDown: false, missingPermissions: 2, missing: []) == "권한 2개가 더 필요해요",
          "settings status: what the user can fix now is said")
    check(G.greeting(agentDown: false, missingPermissions: 0, missing: [], english: false) == "모두 잘 되고 있어요",
          "settings status: on macOS 14 and 15 all is well too (no macOS line any more)")
    check(G.prerequisite(P.line(.helper, english: false), english: false) == .helper && G.prerequisite("모두 잘 되고 있어요", english: false) == nil,
          "settings status: the row knows when its line is one of these (it shows what to do)")
    check(ArisAgentCopy.notSetUp == P.full(.helper, english: false), "prerequisites: a turn with no helper says the same line, with what to do")
}

// MARK: - imp-shortcut-anchor, imp-brain-status

private func settingsLinkTests() {
    let keys = ArisSettingsBuilder.sections(.keys, ArisSettingsSnapshot()).flatMap(\.rows)
    check(ArisSettingsCaption.talkKey.page == .keys && keys.contains { $0.id == ArisSettingsCaption.talkKey.anchor },
          "shortcut link: the talk key's row is on the 단축키 page under the id the guide opens")
    let page = leftoversSource("Aris/private/Aris/Onboarding/ArisOnboardingTryPage.swift")
    if let go = page.range(of: "ArisSettingsNav.shared.go(ArisSettingsCaption.talkKey.page, anchor: ArisSettingsCaption.talkKey.anchor)"),
       let show = page.range(of: "ArisSettingsWindow.shared.show()") {
        check(go.lowerBound < show.lowerBound, "shortcut link: 'No, I'll change the key' goes to the talk key's row, then shows the window")
    } else {
        check(false, "shortcut link: 'No, I'll change the key' goes to the talk key's row, then shows the window")
    }
}

private func brainStatusTests() {
    // 생각's card and its dropdown (design D, ArisAIServicesBuilder) keep imp-brain-status's promises. aris-agent's
    // "ready" for Claude, Codex and Antigravity means its tool is installed, never that it is signed in.
    func state(_ ready: [String: Bool]?, brain: String, key: Bool = false) -> ArisAIServicesState {
        var state = ArisAIServicesState()
        state.presets = [ArisAIPreset(id: "openai", title: "OpenAI", needsKey: true, local: false, baseURL: "https://api.openai.com/v1", quick: "gpt-6-luna", strong: "gpt-6.1-sol")]
        state.profiles = key ? [ArisAIProfile(id: "openai", quick: "gpt-6-luna", strong: "gpt-6.1-sol", hasKey: true)] : []
        state.brainReady = ready ?? [:]
        state.choices.think = brain
        return state
    }
    func choice(_ state: ArisAIServicesState) -> [ArisAIMenuItem] { Array(ArisAIServicesBuilder.menu(.provider(.think), state).items.prefix(3)) }
    let all = ["claude": true, "codex": true, "antigravity": true, "api": true]
    check(choice(state(all, brain: "claude")).map(\.title) == ["Claude", "ChatGPT", "Gemini"] && choice(state(all, brain: "claude")).allSatisfy { $0.tail == nil }
          && choice(state(nil, brain: "claude")).allSatisfy { $0.tail == nil },
          "brain choice: AIs that are set up, or not yet asked about, read as before")
    let some = ["claude": true, "codex": false, "antigravity": false, "api": false]
    check(choice(state(some, brain: "claude")).map(\.tail) == [nil, "설치 필요", "설치 필요"] && choice(state(some, brain: "claude")).allSatisfy { !$0.disabled }
          && ArisAIServicesBuilder.change(.provider(.think), picked: "codex", in: state(some, brain: "claude")) == .think("codex"),
          "brain choice: an AI that isn't on this Mac says so in the choice, and can still be picked")

    let ready = ArisAIServicesBuilder.page(state(some, brain: "claude"))
    check(ready.think.need == nil && ready.think.rows[0].warn == nil
          && ready.login == ArisAILoginLine(brain: "claude", title: "Claude 로그인", desc: "로그인이 풀렸을 때 눌러요. 터미널에서 claude 명령을 열어 줘요."),
          "brain choice: the AI that answers has a 로그인 row that opens its own login in a terminal")
    let missing = ArisAIServicesBuilder.page(state(some, brain: "codex"))
    if case .button(let how, let title, let action)? = missing.think.need {
        check(missing.login == nil && how.contains("codex login") && how.contains("설치") && title == "다시 확인" && action == .recheckBrains
              && missing.think.rows[0].desc == "ChatGPT" && missing.think.rows[0].warn == "설치 필요",
              "brain choice: picking an AI that isn't installed says so at once, how to get it, and can check again")
    } else {
        check(false, "brain choice: picking an AI that isn't installed says so at once, how to get it, and can check again")
    }
    let key = ArisAIServicesBuilder.page(state(some, brain: "api:openai"))
    check(key.think.need == .button(message: "OpenAI API 키가 필요해요", title: "API 키 추가", .openKey("openai")) && key.think.rows[0].warn == "키 필요" && key.login == nil,
          "brain choice: the API brain with no key leads to the row where a key is entered")
    let keyed = ArisAIServicesBuilder.page(state(all, brain: "api:openai", key: true))
    check(keyed.think.need == nil && keyed.think.rows[0].warn == nil && keyed.login == nil, "brain choice: an API brain with its key needs nothing more")
    let unasked = ArisAIServicesBuilder.page(state(nil, brain: "codex"))
    check(unasked.think.need == nil && unasked.think.rows[0].warn == nil && unasked.login?.brain == "codex" && unasked.login?.desc.contains("codex login") == true,
          "brain choice: before the agent has answered nothing is called missing")
    check([ArisBrain.claude, .codex, .antigravity].allSatisfy { ArisSettingsBuilder.brainHow($0).contains(ArisSettingsBuilder.brainCommand($0) ?? "?") }
          && ArisSettingsBuilder.brainCommand(.api) == nil && ArisSettingsBuilder.brainCommand(.codex) == "codex login",
          "brain choice: each AI's line names the command its login runs")
    check(ArisSettingsBuilder.loginToast(opened: true, brain: .codex).contains("터미널") && ArisSettingsBuilder.loginToast(opened: false, brain: .codex).contains("설치"),
          "brain choice: 로그인 says the terminal opened, or that the AI isn't installed when it couldn't")
}

// MARK: - written times just after midnight

private func writtenTimeTests() {
    typealias L = ArisKoreanTimeLabel
    check(L.text(hour: 0, minute: 32) == "밤 12:32" && L.text(hour: 0, minute: 0) == "밤 12:00",
          "written time: 0:00 to 0:59 is written 밤 12:32, never 오전 12:32 (the spoken time says 밤 12시 32분)")
    check(L.text(hour: 1, minute: 5) == "오전 1:05" && L.text(hour: 9, minute: 0) == "오전 9:00" && L.text(hour: 12, minute: 0) == "오후 12:00"
          && L.text(hour: 15, minute: 0) == "오후 3:00" && L.text(hour: 23, minute: 59) == "오후 11:59",
          "written time: every other hour is written 오전 / 오후 as before")
    check(L.text(hour: 0, minute: 32, period: false) == "12:32" && L.text(hour: 16, minute: 0, period: false) == "4:00",
          "written time: the bare clock for the second half of a range")

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    func at(_ hour: Int, _ minute: Int, day: Int = 4) -> Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))! }
    check(ArisAgenda.timeRange(at(0, 30), at(1, 30), calendar: calendar) == "밤 12:30 – 오전 1:30"
          && ArisAgenda.timeRange(at(23, 30), at(0, 30, day: 5), calendar: calendar) == "오후 11:30 – 밤 12:30"
          && ArisAgenda.timeRange(at(0, 10), at(0, 50), calendar: calendar) == "밤 12:10 – 12:50",
          "agenda: an event around midnight is written with 밤 12, and each half names its own part when they differ")
    check(ArisAgenda.timeRange(at(15, 0), at(16, 0), calendar: calendar) == "오후 3:00 – 4:00" && ArisAgenda.timeRange(at(9, 0), at(15, 0), calendar: calendar) == "오전 9:00 – 오후 3:00",
          "agenda: other ranges read as before")
    let now = at(22, 0)
    func item(_ due: Date) -> ArisTodoItem {
        ArisTodoItem(id: "x", title: "x", notes: nil, due: due, hasTime: true, listID: "l", listName: "미리 알림", colorHex: "#ff9500")
    }
    check(item(at(0, 32, day: 5)).dueText(now: now, calendar: calendar) == "내일 밤 12:32" && item(at(15, 0)).dueText(now: now, calendar: calendar) == "오늘 오후 3:00",
          "to-do: one due just after midnight reads 내일 밤 12:32")
}

// MARK: - 볼륨 올려 at 100 %, 내려 at 0

/// A stand-in output: no real device is read or set.
private final class LeftoversOutput: ArisAudioOutput, @unchecked Sendable {
    var level: Float32
    var muted = false
    var writes: [Float32] = []
    var muteWrites: [Bool] = []
    init(level: Float32) { self.level = level }
    func defaultDevice() -> AudioDeviceID? { 7 }
    func hasMute(_ device: AudioDeviceID) -> Bool { true }
    func isMuted(_ device: AudioDeviceID) -> Bool { muted }
    func setMuted(_ device: AudioDeviceID, _ on: Bool) { muted = on; muteWrites.append(on) }
    func volume(_ device: AudioDeviceID) -> Float32? { level }
    func setVolume(_ device: AudioDeviceID, _ value: Float32) { level = value; writes.append(value) }
}

private func volumeLimitTests() {
    func reading(_ level: Float32, muted: Bool = false, hasMute: Bool = true) -> ArisVolumeReading { ArisVolumeReading(level: level, muted: muted, hasMute: hasMute) }
    var rules = ArisVolumeRules()
    check(rules.plan(.up, reading(1)).limit == .top && rules.plan(.up, reading(1)).mute == nil,
          "volume plan: 올려 at 100 % reports that it is already at the top")
    check(rules.plan(.up, reading(0.98)).limit == nil && rules.plan(.up, reading(0.5)).limit == nil,
          "volume plan: a step that still raises it is no limit")
    check(rules.plan(.up, reading(1, muted: true)) == ArisVolumePlan(level: 1, mute: false),
          "volume plan: 올려 at 100 % while muted unmutes, which is a change")
    check(rules.plan(.down, reading(0, muted: true)).limit == .bottom && rules.plan(.down, reading(0)) == ArisVolumePlan(level: 0, mute: true),
          "volume plan: 내려 at 0 with the sound already off reports the bottom; at 0 and not muted it mutes")
    var soft = ArisVolumeRules()
    _ = soft.plan(.set(0), reading(0.4, hasMute: false))
    check(soft.plan(.down, reading(0, hasMute: false)).limit == .bottom && soft.isSoftMuted && soft.plan(.toggleMute, reading(0, hasMute: false)) == ArisVolumePlan(level: 0.4),
          "volume plan: the same on an output with no mute of its own, and the remembered level is kept")
    check(rules.plan(.set(1), reading(1)).limit == nil && rules.plan(.toggleMute, reading(1)).limit == nil,
          "volume plan: only 올려 and 내려 meet a limit")

    let full = LeftoversOutput(level: 1)
    let volume = ArisVolume(output: full, interval: 0.01)
    let top = volume.act(.up)
    volume.waitUntilIdle()
    check(top == .atLimit(.top) && top.limit == .top && full.writes.isEmpty && full.muteWrites.isEmpty && !volume.perform(.up),
          "volume: 올려 at 100 % changes nothing and says so (it was reported as raised)")
    let down = volume.act(.down)
    volume.waitUntilIdle()
    check(down == .changed && down.limit == nil && full.level == 0.9375, "volume: a real step is still a change")
    let silent = LeftoversOutput(level: 0)
    silent.muted = true
    let quiet = ArisVolume(output: silent, interval: 0.01)
    check(quiet.act(.down) == .atLimit(.bottom) && silent.muteWrites.isEmpty, "volume: 내려 with the sound already off changes nothing and says so")

    check(ArisControl.limitReply(.top, korean: true) == "볼륨이 이미 최대예요." && ArisControl.limitReply(.bottom, korean: true) == "볼륨이 이미 가장 낮아요."
          && ArisControl.limitReply(.top, korean: false) == "The volume is already at its highest." && ArisControl.limitReply(.bottom, korean: false) == "The volume is already at its lowest.",
          "control: at a limit Aris says the volume is already there, never 올렸어요")
    check(!["올렸어요", "낮췄어요"].contains(where: ArisControl.limitReply(.top, korean: true).contains), "control: and never that it changed")
    let controls = leftoversSource("Aris/private/Aris/ArisController+Controls.swift")
    check(controls.contains("if let limit = outcome.limit { return ArisControl.limitReply(limit, korean: korean) }"),
          "control: the spoken volume change answers from the limit before anything is logged")
}

// MARK: - the menu's side panel items, and the 사용량 tab's read on opening

private func sideMenuTests() {
    let leftOff: Set<String> = ["history", "activity", "clipboard", "usage"], rightOff: Set<String> = ["todo", "calendar"]
    check(ArisSideMenu.sides(hidden: []) == [.left, .right], "menu: with tabs on both sides it offers each side, the left first")
    check(ArisSideMenu.sides(hidden: rightOff) == [.left] && ArisSideMenu.sides(hidden: leftOff) == [.right],
          "menu: a side with every tab off is not offered")
    check(ArisSideMenu.sides(hidden: leftOff.union(rightOff)).isEmpty, "menu: with every side tab off there is no side panel item")
    check(ArisSideMenu.sides(hidden: ["history", "todo"]) == [.left, .right], "menu: one tab off leaves its side offered")
    check(ArisSideMenu.title(.left, english: false) == "사이드 패널 열기" && ArisSideMenu.title(.right, english: false) == "오른쪽 사이드 패널 열기"
          && ArisSideMenu.title(.left, english: true) == "Open the side panel" && ArisSideMenu.title(.right, english: true) == "Open the right side panel",
          "menu: the right side has its own item (it could only be opened from the menu when the left was off)")

    let now = leftoversAt(0)
    check(ArisSideTabWork.readsUsageOnOpen(lastRead: nil, now: now) && ArisSideTabWork.readsUsageOnOpen(lastRead: now.addingTimeInterval(-61), now: now)
          && ArisSideTabWork.readsUsageOnOpen(lastRead: now.addingTimeInterval(-60), now: now),
          "usage tab: opening it reads the limits again when the last read is a minute old or was never made")
    check(!ArisSideTabWork.readsUsageOnOpen(lastRead: now.addingTimeInterval(-59), now: now) && !ArisSideTabWork.readsUsageOnOpen(lastRead: now, now: now),
          "usage tab: a read from the last minute is fresh enough")
    check(ArisSideTabWork.showsUsage(open: [.left], leftTab: .usage) && !ArisSideTabWork.showsUsage(open: [.left], leftTab: .history)
          && !ArisSideTabWork.showsUsage(open: [.right], leftTab: .usage) && !ArisSideTabWork.showsUsage(open: [], leftTab: .usage),
          "usage tab: it is open when the left panel is and it is the tab in front")
    check(!leftoversSource("Aris/private/Aris/Side/ArisSidePanels.swift").contains("byKeyboard"),
          "side panels: the set that was written and never read is gone")
}

// MARK: - F5: the settings window in English, by looking each Korean string up where it is drawn

/// The settings catalog's pairs (Korean → English), read from the file the app compiles.
private func leftoversSettingsPairs() -> [String: String] {
    let file = leftoversRoot().appendingPathComponent("Aris/components/Settings/Settings.xcstrings")
    return ArisSettingsCopy.pairs(catalog: (try? Data(contentsOf: file)) ?? Data())
}

private func leftoversHasHangul(_ text: String) -> Bool {
    text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) || (0x3131...0x318E).contains($0.value) }
}

/// Snapshots that between them reach every line the five English pages can draw.
func leftoversSettingsVariants(_ page: ArisSettingsPage) -> [ArisSettingsSnapshot] {
    var base = ArisSettingsSnapshot()
    base.brains = ArisBrain.allCases.map { .init(id: $0.rawValue, title: $0.shortTitle) }
    base.versionLine = "버전 1.4 (212)"
    func with(_ change: (inout ArisSettingsSnapshot) -> Void) -> ArisSettingsSnapshot {
        var copy = base
        change(&copy)
        return copy
    }
    switch page {
    case .aris:
        return [base, with { $0.hasVoiceModel = true; $0.busy = true; $0.systemAudioMissing = true; $0.claudeRing = "sevenDay"; $0.silence = 0; $0.wakeWord = false },
                with { $0.claudeRing = "auto"; $0.talkCaps = []; $0.brain = "api" }, with { $0.claudeRing = "nonsense"; $0.brain = "antigravity" }]
    case .ai:
        let services: [ArisSettingsSnapshot.Service] = [
            .init(id: "claude", title: "Claude", detail: "me@example.com · Max", status: "연결됨", tone: .ok),
            .init(id: "codex", title: "Codex", detail: "", status: "연결 확인 중", tone: .plain),
        ]
        return [base] + ArisBrain.allCases.flatMap { brain in
            [with { $0.brain = brain.rawValue; $0.services = services }, with { $0.brain = brain.rawValue; $0.computerEngine = "codex" }]
        }
    case .notch:
        return [base,
                with { $0.hover = false; $0.heightMode = "custom"; $0.notchHeight = 28; $0.hiddenSides = true; $0.hiddenSideTabs = ["clipboard", "todo", "calendar"]; $0.rightPanelCaps = ["⌃", "⌥", "T"]
                       $0.more.hoverDelay = 0; $0.more.animation = false; $0.more.flatHeightMode = "custom"; $0.more.flatHeight = 0 },
                with { $0.heightMode = "menubar"; $0.gestures = false; $0.more.animationSpeed = 1.5; $0.more.flatHeightMode = "custom"; $0.more.flatHeight = 24; $0.more.hoverDelay = 1; $0.more.gestureSensitivity = 100 }]
    case .general:
        return [base, with { $0.displayMode = "preferred"; $0.screens = [.init(id: "A", title: "Built-in Retina Display")]; $0.screen = "A"; $0.userName = "Alex"; $0.appLanguage = "en"; $0.login = false },
                with { $0.displayMode = "all" }]
    case .about:
        return [base, with { $0.versionLine = "Sol · 버전 1.4 (212)" }]
    default:
        return [base]
    }
}

/// Every string literal in a Swift source that has Korean in it, comments left out. A value written into the string
/// (`\(name)`) reads "7", which stands for a name or a number alike when the catalog is asked.
private func leftoversKoreanLiterals(_ source: String) -> [String] {
    var found: [String] = []
    let text = Array(source)
    var i = 0
    func literal() -> String {
        // `i` is just past the opening quote.
        var out = ""
        while i < text.count, text[i] != "\"" {
            if text[i] == "\\", i + 1 < text.count {
                if text[i + 1] == "(" {
                    i += 2
                    var depth = 1
                    while i < text.count, depth > 0 {
                        if text[i] == "\"" { i += 1; let inner = literal(); if leftoversHasHangul(inner) { found.append(inner) } }
                        else { if text[i] == "(" { depth += 1 } else if text[i] == ")" { depth -= 1 }; i += 1 }
                    }
                    out += "7"
                    continue
                }
                out.append(text[i + 1] == "n" ? "\n" : text[i + 1])
                i += 2
                continue
            }
            out.append(text[i])
            i += 1
        }
        i += 1
        return out
    }
    while i < text.count {
        if text[i] == "/", i + 1 < text.count, text[i + 1] == "/" {
            while i < text.count, text[i] != "\n" { i += 1 }
        } else if text[i] == "\"" {
            i += 1
            let one = literal()
            if leftoversHasHangul(one) { found.append(one) }
        } else {
            i += 1
        }
    }
    return found
}

private func settingsCopyEngineTests() {
    var table = ArisSettingsCopyTable([
        "열기": "Open", "기록": "History", "캘린더": "Calendar",
        "권한 %d개가 더 필요해요": "%d more permissions needed", "권한 1개가 더 필요해요": "1 more permission needed",
        "%@ 탭이 꺼져 있어요": "The %@ tab is off", "%@을 %@에 저장했어요": "Saved to %2$@: %1$@",
        "“%@”을 만들었어요": "Made “%@”", "“%@”을 만들었어요. 앱 기록만 담았어요": "Made “%@”, with the app's log only",
        "못 지운 것: %@.": "Not removed: %@.",
    ])
    check(table.english("열기") == "Open" && table.english("닫기") == nil && table.english("") == nil, "copy: a string is found by itself, and one with no entry is not")
    check(table.english("권한 3개가 더 필요해요") == "3 more permissions needed" && table.english("권한 1개가 더 필요해요") == "1 more permission needed",
          "copy: a sentence with a number in it is one entry, and an exact entry wins over the pattern")
    check(table.english("권한 여러개가 더 필요해요") == nil, "copy: %d takes a number only")
    check(table.english("기록 탭이 꺼져 있어요") == "The History tab is off" && table.english("Notes 탭이 꺼져 있어요") == "The Notes tab is off",
          "copy: a value that is one of the catalog's own words is said in English too; any other stays as it is")
    check(table.english("보고서을 메모에 저장했어요") == "Saved to 메모: 보고서", "copy: the English may put the values in another order")
    check(table.english("“Aris 진단.zip”을 만들었어요") == "Made “Aris 진단.zip”"
          && table.english("“a.zip”을 만들었어요. 앱 기록만 담았어요") == "Made “a.zip”, with the app's log only",
          "copy: of two patterns that fit, the longer sentence is the one used")
    check(table.english("못 지운 것: 기록, 캘린더, 메모.") == "Not removed: History, Calendar, 메모.", "copy: a list of the catalog's words is said word by word")
    check(table.english("기록 탭이 꺼져 있어요") == "The History tab is off", "copy: asked again, the same answer")
    check(ArisSettingsCopyTable.filled("%2$d of %1$@, then %@ and %d", ["a", "2"]) == "2 of a, then a and 2", "copy: values go in by position, then in order")
}

@MainActor
private func settingsCopyPageTests() {
    let pairs = leftoversSettingsPairs()
    ArisSettingsCopy.install(pairs)
    check(pairs.count > 150, "settings catalog: the catalog is read from the file the app compiles")
    check(pairs.allSatisfy { !leftoversHasHangul($0.value) || $0.value == "한국어" } && pairs.allSatisfy { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty },
          "settings catalog: every entry's English is English (한국어 keeps its own name)")
    func placeholders(_ text: String) -> Int { text.components(separatedBy: "%@").count + text.components(separatedBy: "%d").count - 2 }
    func positional(_ text: String) -> Int { (1...9).filter { text.contains("%\($0)$@") || text.contains("%\($0)$d") }.count }
    check(pairs.allSatisfy { placeholders($0.key) == placeholders($0.value) + positional($0.value) },
          "settings catalog: an entry's English takes as many values as its Korean gives")

    let english = ArisSettingsWording.make(page: .general, english: true), korean = ArisSettingsWording.make(page: .general, english: false)
    // A page not listed as translated (there is none now: en-settings-tests), drawn in an English window.
    let elsewhere = ArisSettingsWording(pageEnglish: false, frameEnglish: true), ai = ArisSettingsWording.make(page: .ai, english: true)
    check(english.pageEnglish && english.frameEnglish && !korean.pageEnglish && !korean.frameEnglish && !elsewhere.pageEnglish && elsewhere.frameEnglish,
          "wording: a page is English when the UI is and the page has all its English; the frame whenever the UI is")
    check(english("다시 시작") == "Restart" && korean("다시 시작") == "다시 시작" && elsewhere("다시 시작") == "다시 시작" && elsewhere.frame("일반") == "General",
          "wording: a page that isn't all English yet draws every string in Korean, even one the catalog has")
    check(english.of(.general, "앱 언어") == "App language" && english.of(.voice, "목소리") == "Voice" && korean.of(.general, "앱 언어") == "앱 언어",
          "wording: a search result is named in its own page's language")

    // Every line the English pages can draw is English.
    for page in ArisSettingsPage.allCases where ArisSettingsCopy.translatedPages.contains(page) {
        let wording = ArisSettingsWording.make(page: page, english: true)
        let left = leftoversSettingsVariants(page).flatMap { ArisSettingsWording.shown(wording.sections(ArisSettingsBuilder.sections(page, $0))) }
            .filter { leftoversHasHangul($0.replacingOccurrences(of: "한국어", with: "")) } // the language's own name (alone, or in "한국어 + 1 more") is no leftover
        check(left.isEmpty, "settings in English: \(page.rawValue) has no Korean left" + (left.isEmpty ? "" : " (\(Array(Set(left)).sorted().prefix(4)))"))
        let sections = ArisSettingsBuilder.sections(page, ArisSettingsSnapshot())
        check(wording.sections(sections).map(\.id) == sections.map(\.id) && wording.sections(sections).flatMap(\.rows).map(\.id) == sections.flatMap(\.rows).map(\.id)
              && ArisSettingsWording.korean.sections(sections) == sections,
              "settings in English: \(page.rawValue) keeps every row and id, and in Korean nothing changes")
        let entries = ArisSettingsIndex.entries.filter { $0.page == page && ArisSettingsCopy.english($0.title) == nil && leftoversHasHangul($0.title) }
        check(entries.isEmpty, "settings in English: every setting of \(page.rawValue) can be found by an English name" + (entries.isEmpty ? "" : " (\(entries.map(\.title).prefix(4)))"))
    }
    let voice = ArisSettingsBuilder.sections(.voice, ArisSettingsSnapshot())
    check(elsewhere.sections(voice) == voice, "settings in English: a page still in Korean is drawn exactly as written")

    // The frame: every page's name and line, the groups, the status lines.
    let frame = ArisSettingsPage.allCases.flatMap { [$0.title, $0.subtitle] } + ArisSettingsGroup.allCases.map(\.rawValue)
        + [ArisSettingsCaption.greeting(agentDown: true, missingPermissions: 0, english: false), ArisSettingsCaption.greeting(agentDown: false, missingPermissions: 0, noAI: true, english: false),
           ArisSettingsCaption.greeting(agentDown: false, missingPermissions: 1, english: false), ArisSettingsCaption.greeting(agentDown: false, missingPermissions: 4, english: false),
           ArisSettingsCaption.greeting(agentDown: false, missingPermissions: 0, english: false)]
    let frameLeft = frame.filter { leftoversHasHangul(english.frame($0)) }
    check(frameLeft.isEmpty, "settings in English: the sidebar, the page names and the status line are all English" + (frameLeft.isEmpty ? "" : " (\(frameLeft.prefix(4)))"))
    check(english.frame(ArisSettingsCaption.greeting(agentDown: false, missingPermissions: 3, english: false)) == "3 more permissions needed"
          && ArisSettingsCaption.asksForPermissions(ArisSettingsCaption.greeting(agentDown: false, missingPermissions: 3, english: false)),
          "settings in English: the status line is translated where it is drawn, so what it opens is still read from the Korean")

    // What a change says in the notch preview.
    let sample = english.row(ArisSettingsBuilder.sections(.general, ArisSettingsSnapshot())[0].rows[0])
    check(sample.title == "Open at login" && english(ArisSettingsCaption.changed(sample.title, on: true)) == "Turned on Open at login"
          && english(ArisSettingsCaption.changed(sample.title, on: false)) == "Turned off Open at login" && english(ArisSettingsCaption.changed("App language", on: nil)) == "Changed App language",
          "settings in English: the line after a change is English, whichever particle the Korean took")

    // The search finds a setting by its English name in the English window.
    let alias: (ArisSettingsEntry) -> ArisSettingsIndex.Alias = { .init(title: english.of($0.page, $0.title), page: english.frame($0.page.title)) }
    check(ArisSettingsIndex.search("restart", alias: alias).first?.id == "general.restart" && ArisSettingsIndex.search("restart").isEmpty
          && ArisSettingsIndex.search("다시 시작", alias: alias).first?.id == "general.restart",
          "search: in the English window a setting is found by its English name, and still by its Korean one")
    check(ArisSettingsIndex.search("about", alias: alias).contains { $0.page == .about }, "search: and by its page's English name")

    // The words the pages' own views and models hold: each has its English, and none is drawn past the wording.
    let files = ["Aris/components/Settings/ArisSettingsControls.swift", "Aris/components/Settings/ArisSettingsModal.swift", "Aris/components/Settings/ArisSettingsDropdown.swift",
                 "Aris/components/Settings/ArisSettingsSidebar.swift", "Aris/components/Settings/ArisSettingsShell.swift", "Aris/components/Settings/ArisSettingsArt.swift",
                 "Aris/components/Settings/ArisSettingsPageView.swift", "Aris/components/Settings/ArisSettingsSheets.swift", "Aris/components/Settings/ArisDataSection.swift",
                 "Aris/private/Aris/ArisDataModel.swift", "Aris/private/Aris/ArisAppData.swift"] + leftoversEnglishPageFiles
    // Written both ways where they are (ArisUIWords), or not drawn in the window: the exported files' names.
    let notDrawn: Set<String> = ["Aris 설정", "Aris 데이터", "Aris 진단", "확인 글자"]
    for file in files {
        let source = leftoversSource(file)
        let missing = leftoversKoreanLiterals(source).filter { !notDrawn.contains($0) && ArisSettingsCopy.english($0) == nil }
        check(!source.isEmpty && missing.isEmpty, "settings in English: every Korean string in \((file as NSString).lastPathComponent) has its English" + (missing.isEmpty ? "" : " (\(missing.prefix(3)))"))
        let raw = source.components(separatedBy: "\n").filter { line in
            let code = line.trimmingCharacters(in: .whitespaces)
            guard !code.hasPrefix("//") else { return false }
            return ["Text(\"", ".help(\"", ".accessibilityLabel(\"", ".accessibilityValue(\"", "TextField(\"", "SecureField(\""].contains { start in
                code.components(separatedBy: start).dropFirst().contains { leftoversHasHangul(String($0.prefix { $0 != "\"" })) }
            }
        }
        check(raw.isEmpty, "settings in English: \((file as NSString).lastPathComponent) draws no Korean string past the wording" + (raw.isEmpty ? "" : " (\(raw.prefix(2)))"))
    }
    let toasts = ["“Aris 데이터 2026-11-11.json”을 저장했어요": "Saved “Aris 데이터 2026-11-11.json”", "3가지를 지웠어요": "Erased 3 kinds of data",
                  "“Aris 진단.zip”을 만들었어요. 에이전트가 꺼져 있어서 앱 기록만 담았어요": "Made “Aris 진단.zip”. Aris's helper is off, so it holds the app's log only",
                  "이건 지우지 못했어요: Aris 앱, 설정과 기록. Finder에서 직접 지워 주세요.": "These couldn't be removed: The Aris app, Settings and records. Remove them yourself in Finder."]
    check(toasts.allSatisfy { english($0.key) == $0.value }, "settings in English: what the data sheets say when they finish is English, the file's name as it is")
    // AI 서비스: the lines its rows build while they work, and what the helper answers them with.
    let said = [ArisSettingsBuilder.loginToast(opened: true, brain: .codex), ArisSettingsBuilder.loginToast(opened: false, brain: .codex),
                ArisSettingsBuilder.loginToast(opened: false, brain: .claude), ArisSettingsBuilder.loginToast(opened: false, brain: .api),
                "OpenAI를 API 브레인으로 저장했어요", "테스트 통과 · gpt-6-luna", "DeepSeek 키를 키체인에서 지웠어요", "키를 붙여 넣어 주세요. 키 받는 곳: platform.openai.com",
                "github 서비스를 추가했어요", "github 서비스를 바꿨어요", "github 서비스를 뺐어요", "ElevenLabs 키를 저장했어요",
                "도구 9개 · 읽기 6개, 나머지 3개는 할 때마다 물어봐요", "도구 9개 · 읽기 6개, 나머지 3개는 할 때마다 물어봐요\nsearch, fetch, list, read …",
                "연결됐어요. 도구 9개 (읽기 6개, 나머지는 할 때마다 물어봐요).", "연결하지 못했어요: connection refused", "키체인에 저장하지 못했어요 (오류 -25300).",
                "서비스는 12개까지 넣을 수 있어요.", "이 모델을 쓸 수 없어요: model_not_found", "에이전트가 거절했어요 (403).", "키 받는 곳: elevenlabs.io › 내 계정 › API 키"]
    let saidLeft = said.filter { leftoversHasHangul(ai($0)) }
    check(saidLeft.isEmpty, "settings in English: what AI 서비스's rows say while they work is English" + (saidLeft.isEmpty ? "" : " (\(saidLeft.prefix(3)))"))
    check(ai("도구 9개 · 읽기 6개, 나머지 3개는 할 때마다 물어봐요\nsearch, fetch") == "9 tools · 6 read at once, the other 3 ask every time\nsearch, fetch"
          && ai("Codex가 이 Mac에 설치돼 있지 않아요. 먼저 설치해 주세요") == "Codex isn't installed on this Mac. Install it first"
          && ai("키 받는 곳: elevenlabs.io › 내 계정 › API 키") == "Get a key at elevenlabs.io › My Account › API Keys"
          && ai("Ollama (이 Mac)를 API 브레인으로 저장했어요") == "Saved Ollama (this Mac) as the API model",
          "settings in English: numbers and names keep their places in those lines")
    // The helper's own lines (its sources are read here, never changed): each one that can reach the page has its English.
    let helper = ["ArisAgent/ArisAPIRoutes.swift", "ArisAgent/ArisAPIConnections.swift", "ArisAgent/ArisMCPConfig.swift", "ArisAgent/ArisMCPSecrets.swift"].flatMap { leftoversKoreanLiterals(leftoversSource($0)) }
        + leftoversKoreanLiterals(leftoversSource("ArisAgent/ArisAPIModels.swift")).filter { ($0.hasSuffix("요.") || $0.contains("쓸 수 없어요")) && !$0.contains("인사해 주세요") }
        + leftoversKoreanLiterals(leftoversSource("ArisAgent/ArisMCPHub.swift")).filter { !$0.contains("the user adds") }
        + leftoversKoreanLiterals(leftoversSource("ArisAgent/ArisUsageFetch.swift")) + leftoversKoreanLiterals(leftoversSource("ArisAgent/ArisAPIPreset.swift"))
    let helperLeft = helper.filter { ArisSettingsCopy.english($0) == nil }
    check(helper.count > 40 && helperLeft.isEmpty, "settings in English: every line the helper can answer AI 서비스 with has its English" + (helperLeft.isEmpty ? "" : " (\(helperLeft.prefix(3)))"))
    ArisSettingsCopy.install([:])
}

/// The files that draw the pages added to the English ones after 일반 and 정보.
private let leftoversEnglishPageFiles: [String] = [
    // 대화
    "Aris/components/Settings/ArisClaudeBudgetRow.swift", "Aris/private/Claude/ClaudeBudget.swift",
    // AI 서비스
    "Aris/components/Settings/ArisAPIBrainSection.swift", "Aris/components/Settings/ArisServicesSection.swift", "Aris/components/Settings/ArisKeysSection.swift",
    // AI 서비스, design D: its views, its page as data, and what it says while it works.
    "Aris/components/Settings/ArisAIServicesControls.swift", "Aris/components/Settings/ArisAIServicesPage.swift", "Aris/components/Settings/ArisAIServicesMenu.swift",
    "Aris/components/Settings/ArisAIServicesSheets.swift", "Aris/components/Settings/ArisAIServicesLive.swift", "Aris/components/Settings/ArisAIServicesModel.swift",
    "Aris/components/Settings/ArisAIServicesPageModel.swift", "Aris/components/Settings/ArisAIServicesSheetModel.swift", "Aris/components/Settings/ArisAIVoices.swift",
    "Aris/private/Aris/ArisKeyFile.swift", "Aris/private/Aris/ArisKeychain.swift",
]
