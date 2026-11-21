// Tests for jv-helperbugs (memory): a data wipe leaves no copy of memory in the helper's caches and removes the
// learned shortcuts; learned shortcuts are listed and deleted in 설정 › 기억 › 저장된 단계 and are kept only for words
// said twice that don't point at the moment; the memory cap makes room from what Aris inferred and never drops what
// The user said themselves, and tells them when only their own are left. Fake files only, no model. Called from main.swift; uses
// its check().
import Foundation

private func hbMemoryFolder() -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-hb-memory-\(UUID().uuidString.prefix(8))", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder.resolvingSymlinksInPath()
}

private func hbRecord(_ id: String, _ source: ArisMemorySource, daysAgo: Double, used: Int = 0, until: Date? = nil, now: Date) -> ArisMemoryRecord {
    let at = now.addingTimeInterval(-daysAgo * 86_400)
    return ArisMemoryRecord(id: id, kind: .fact, subject: "", text: id, source: source, turnAt: at, confidence: 0.7, createdAt: at, updatedAt: at,
                            lastUsedAt: nil, useCount: used, validUntil: until)
}

func runHelperbugsMemoryTests() {
    hbWipeTests()
    hbShortcutLearningTests()
    hbShortcutRouteTests()
    hbCapacityTests()
}

// MARK: - 1. A wipe clears every in-memory copy

private func hbWipeTests() {
    let home = hbMemoryFolder()
    defer { try? FileManager.default.removeItem(at: home) }
    let places = ArisDataRoute.Places(home: home)
    try? FileManager.default.createDirectory(at: places.data, withIntermediateDirectories: true)
    let store = ArisMemoryStore.at(places.data)
    let now = Date()
    _ = store.remember(ArisMemoryCandidate(kind: .preference, subject: "커피", text: "커피는 아이스 아메리카노를 좋아해", confidence: 1), source: .said, turnAt: now, now: now)
    try? Data("{\"다음 곡\":{\"commands\":[\"x\"],\"reply\":\"r\",\"learned\":\"2026-11-01T00:00:00Z\"}}".utf8).write(to: places.shortcuts)

    let curator = ArisMemoryCurator(store: store, clock: { now }, extract: { _ in nil }, summarize: { _ in nil })
    curator.refresh()
    curator.drain()
    check(curator.context(for: "커피 뭐 좋아하지", eligible: true, now: now)?.contains("아메리카노") == true, "wipe 1: the cache holds the memory before the wipe")
    curator.drain()

    var wiped: [String] = []
    var audits: [String] = []
    var effects = ArisDataRoute.Effects(trash: { _ in }, bootout: {}, reopenLog: {}, later: { _ in }, bundleId: { _ in nil },
                                        audit: { audits.append($0) }, log: { _ in })
    // The live effect empties the caches at once (main.swift: ArisMemoryCurator.live.wiped()), here this curator's.
    effects.wiped = { items in
        wiped = items
        if items.contains("memory") { curator.wiped() }
    }
    let reply = ArisDataRoute.handle(["op": "wipe", "items": ["memory"], "confirm": ArisTypedConfirm.wipeWord], places: places, appBundle: nil, effects: effects)
    check(reply.status == 200 && wiped == ["memory"], "wipe 1: the route tells what it wiped (\(wiped))")
    // Before the memory queue has even run: the next turn is given nothing.
    check(curator.context(for: "커피 뭐 좋아하지", eligible: true, now: now) == nil, "wipe 1: the very next turn gets no wiped memory (the cache is emptied at once)")
    curator.drain()
    check(curator.context(for: "커피 뭐 좋아하지", eligible: true, now: now) == nil && store.count() == 0, "wipe 1: read again, the cache stays empty")
    check(!FileManager.default.fileExists(atPath: places.shortcuts.path), "wipe 5: a memory wipe removes the learned shortcuts")

    // A wipe of logs only leaves memory's caches alone, and still says what it wiped.
    wiped = []
    _ = ArisDataRoute.handle(["op": "wipe", "items": ["logs"], "confirm": ArisTypedConfirm.wipeWord], places: places, appBundle: nil, effects: effects)
    check(wiped == ["logs"], "wipe 1: every wipe calls the refresh with its items")

    // The live wiring: the server's /data route empties the curator's and the work desk's caches.
    let main = (try? String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("ArisAgent/main.swift"), encoding: .utf8)) ?? ""
    check(main.contains("ArisMemoryCurator.live.wiped()") && main.contains("ArisWorkDesk.live.wiped()"), "wipe 1: the agent empties both caches after a wipe")
}

// MARK: - 5. Learned shortcuts: what is kept

private func hbShortcutLearningTests() {
    // Words that point at the moment are never kept or replayed; "다음 곡" and "next track" are.
    for key in ["이거 열어", "이걸 왼쪽으로", "방금 거 다시", "open that", "put it on the left", "여기 창 오른쪽"] {
        check(!ArisShortcuts.mayKeep(ArisShortcuts.key(for: key)), "shortcut 5: '\(key)' points at the moment, never kept")
    }
    for key in ["다음 곡", "next track", "사파리 열어", "볼륨 30으로", "지금 음악 꺼 줘"] {
        check(ArisShortcuts.mayKeep(ArisShortcuts.key(for: key)), "shortcut 5: '\(key)' may be kept")
    }
    check(!ArisShortcuts.mayKeep(ArisShortcuts.key(for: "노션 캘린더 접근할 수 있어")) && !ArisShortcuts.mayKeep(""), "shortcut 5: questions and empty keys are never kept")

    // One-off phrasing: saved only the second time the same words did the same thing.
    let commands = ["osascript -e 'tell application \"Music\" to next track'"]
    let first = ArisShortcuts.sighted(commands, as: "다음 곡", seen: [:])
    check(!first.save && first.seen["다음 곡"] == commands, "shortcut 5: the first time is only seen, not saved")
    let other = ArisShortcuts.sighted(["open -a \"Safari\""], as: "다음 곡", seen: first.seen)
    check(!other.save && other.seen["다음 곡"] == ["open -a \"Safari\""], "shortcut 5: the same words doing another thing start over")
    let second = ArisShortcuts.sighted(commands, as: "다음 곡", seen: first.seen)
    check(second.save && second.seen["다음 곡"] == nil, "shortcut 5: the second time with the same commands is saved")
    var many: [String: [String]] = [:]
    for index in 0..<(ArisShortcuts.sightingsLimit + 10) { many = ArisShortcuts.sighted(commands, as: "k\(index)", seen: many).seen }
    check(many.count <= ArisShortcuts.sightingsLimit && many["k\(ArisShortcuts.sightingsLimit + 9)"] != nil, "shortcut 5: what waits for a second time is bounded")
    check(ArisShortcuts.keptReply("다음 곡으로 넘겼어요.\n지금은 3시예요") == "다음 곡으로 넘겼어요." && ArisShortcuts.keptReply(String(repeating: "가", count: 500)).count == 200,
          "shortcut 5: only the reply's first line is kept, short")

    // The runner and the replay both use the one rule.
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("ArisAgent")
    let runner = (try? String(contentsOf: root.appendingPathComponent("ArisAgentRunner.swift"), encoding: .utf8)) ?? ""
    let main = (try? String(contentsOf: root.appendingPathComponent("main.swift"), encoding: .utf8)) ?? ""
    check(runner.contains("ArisShortcuts.mayKeep(key), ArisShortcuts.learnable(") && main.contains("guard ArisShortcuts.mayKeep(key) else {"),
          "shortcut 5: learning and replay both refuse keys that may not be kept")
}

// MARK: - 5. Learned shortcuts: listed and deleted

private func hbShortcutRouteTests() {
    let tools = "/Users/x/.config/aris/aris-tools"
    var shortcuts: [String: ArisShortcuts.Learned] = [
        "다음 곡": ArisShortcuts.Learned(commands: ["osascript -e 'tell application \"Music\" to next track'"], reply: "넘겼어요", learned: "2026-11-02T00:00:00Z"),
        "사파리 왼쪽": ArisShortcuts.Learned(commands: ["open -a \"Safari\"", "\(tools) window left Safari"], reply: "됐어요", learned: "2026-11-03T00:00:00Z"),
    ]
    var forgotten: [String] = []
    let access = ArisShortcutsAccess(all: { shortcuts }, forget: { key in
        forgotten.append(key)
        return shortcuts.removeValue(forKey: key) != nil
    })
    let folder = hbMemoryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ArisMemoryStore.at(folder)

    let listed = ArisMemoryRoute.handle(["op": "savedSteps"], store: store, shortcuts: access, tools: tools)
    let body = (try? JSONSerialization.jsonObject(with: listed.body)) as? [String: Any] ?? [:]
    let rows = body["recipes"] as? [[String: Any]] ?? []
    check(listed.status == 200 && rows.count == 2 && body["tampered"] as? Bool == false, "shortcut 5: the learned shortcuts are listed among the saved steps (\(rows.count))")
    let newest = rows.first ?? [:]
    check(newest["key"] as? String == ArisShortcutsRoute.keyPrefix + "사파리 왼쪽" && newest["request"] as? String == "사파리 왼쪽",
          "shortcut 5: newest first, under a key no saved step can have")
    check(newest["steps"] as? [String] == ["Safari 열기", "창 왼쪽 절반 (Safari)"] && newest["stepsEn"] as? [String] == ["Open Safari", "Window to the left half (Safari)"]
          && newest["apps"] as? String == "Safari", "shortcut 5: each command worded in both languages, never the shell text (\((newest["steps"] as? [String] ?? []).joined(separator: " / ")))")
    check((rows.last?["steps"] as? [String]) == ["Music: 다음 곡"], "shortcut 5: an app command reads as app and action")
    // The app's own decoder reads these rows (ArisSavedStepsItem's fields).
    check(rows.allSatisfy { $0["saved"] is String && $0["outside"] as? Bool == false && $0["stepsEn"] is [String] }, "shortcut 5: the rows have the saved steps' fields")

    let deleted = ArisMemoryRoute.handle(["op": "savedStepsDelete", "key": ArisShortcutsRoute.keyPrefix + "다음 곡"], store: store, shortcuts: access, tools: tools)
    let removed = ((try? JSONSerialization.jsonObject(with: deleted.body)) as? [String: Any])?["removed"] as? Bool
    check(deleted.status == 200 && removed == true && forgotten == ["다음 곡"] && shortcuts["다음 곡"] == nil && deleted.audit == "learned shortcut: deleted one",
          "shortcut 5: 지우기 forgets that one shortcut, with an audit line")
    let plain = ArisMemoryRoute.handle(["op": "savedStepsDelete", "key": "사파리 왼쪽"], store: store, shortcuts: access, tools: tools)
    check(plain.status == 200 && forgotten == ["다음 곡"] && shortcuts["사파리 왼쪽"] != nil, "shortcut 5: a saved steps key never deletes a learned shortcut")
    check(ArisMemoryRoute.handle(["op": "savedStepsDelete", "key": ArisShortcutsRoute.keyPrefix], store: store, shortcuts: access, tools: tools).status == 400,
          "shortcut 5: an empty shortcut key is refused")
    check(ArisMemoryRoute.handle(["op": "nope"], store: store, shortcuts: access, tools: tools).status == 400, "shortcut 5: other ops are still 400")
    let without = ArisMemoryRoute.handle(["op": "savedSteps"], store: store)
    check(without.status == 200, "shortcut 5: with no shortcuts given the saved steps answer as before")

    check(ArisShortcutsRoute.describe("\(tools) volume 40", tools: tools, english: false) == "볼륨 40"
          && ArisShortcutsRoute.describe("osascript -e 'set volume with output muted'", tools: tools, english: true) == "Mute"
          && ArisShortcutsRoute.describe("shortcuts run \"집 모드\"", tools: tools, english: false) == "단축어 실행: 집 모드"
          && ArisShortcutsRoute.describe("open \"https://news.ycombinator.com/x\"", tools: tools, english: true) == "Open link: news.ycombinator.com"
          && ArisShortcutsRoute.describe("\(tools) music next", tools: tools, english: false) == "다음 곡"
          && ArisShortcutsRoute.describe("\(tools) calendar", tools: tools, english: false) == "캘린더 열기",
          "shortcut 5: every replayable shape has its words")
}

// MARK: - 6. The memory cap

private func hbCapacityTests() {
    let now = Date()
    let records = [
        hbRecord("said-old", .said, daysAgo: 400, now: now),
        hbRecord("said-new", .said, daysAgo: 1, now: now),
        hbRecord("learned-used", .learned, daysAgo: 2, used: 9, now: now),
        hbRecord("learned-stale", .learned, daysAgo: 300, now: now),
        hbRecord("tool-current", .tool, daysAgo: 300, now: now),
        hbRecord("tool-expired", .tool, daysAgo: 1, until: now.addingTimeInterval(-3_600), now: now),
        hbRecord("imported", .imported, daysAgo: 3, now: now),
    ]
    let order = ArisMemoryStore.evictionOrder(records, now: now).map(\.id)
    check(!order.contains("said-old") && !order.contains("said-new"), "cap 6: what the user said himself is never made room from (\(order))")
    check(order.prefix(2) == ["learned-stale", "learned-used"], "cap 6: what Aris inferred goes first, the stale one before the used one")
    check(order.dropFirst(2).first == "tool-expired", "cap 6: then a tool's or an import's that no longer holds")
    check(Set(order.dropFirst(3)) == ["tool-current", "imported"], "cap 6: then the rest of those")

    // The words the user is told when only their own are past the limit.
    let added = ArisMemoryStore.Outcome.added(hbRecord("x", .said, daysAgo: 0, now: now))
    let full = ArisMemoryAnswer.remembered(added, korean: true, pastCapacity: true)
    check(full.hasPrefix("기억할게요") && full.contains("\(ArisMemoryStore.capacity)") && full.contains("설정 › 기억"), "cap 6: past the limit his 기억해 says so (\(full))")
    check(ArisMemoryAnswer.remembered(added, korean: true, pastCapacity: false) == ArisMemoryAnswer.remembered(added, korean: true),
          "cap 6: under the limit the reply is as before")
    check(ArisMemoryAnswer.remembered(.empty, korean: false, pastCapacity: true) == ArisMemoryAnswer.remembered(.empty, korean: false),
          "cap 6: only a memory that was added gets the line")
    check(ArisMemoryAnswer.fullLine(korean: false).contains("Settings › Memory"), "cap 6: the English line names the page")

    // A real store under the limit: nothing goes, and it is not past capacity.
    let folder = hbMemoryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ArisMemoryStore.at(folder)
    _ = store.remember(ArisMemoryCandidate(kind: .fact, subject: "", text: "내 자전거는 빨간색이야", confidence: 1), source: .said, turnAt: now, now: now)
    check(store.count() == 1 && !store.pastCapacity, "cap 6: one memory is not past capacity")
}
