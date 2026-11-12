// Tests for audit picks ② B (first-run onboarding) and ④ C (API keys, diagnostics, wipe, export, uninstall).
// Called from main.swift; uses its check(). Every file operation runs in a temp folder, never in the real home.
import Foundation

private func tempHome() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("aris-data-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func write(_ text: String, _ url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? Data(text.utf8).write(to: url)
}

private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

private func json(_ data: Data) -> [String: Any] { ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:] }

func runSettingsDataTests() {
    redactionTests()
    typedConfirmTests()
    keyTests()
    onboardingTests()
    appDataTests()
    dataRouteTests()
}

// MARK: - Redaction

private func redactionTests() {
    let token = String(repeating: "a1b2", count: 16)
    let r = { (text: String) in ArisRedaction.redact(text, secrets: [token, "my-eleven-key-123456"], home: "/Users/user") }
    check(!r("token \(token) end").contains(token) && r("token \(token) end").contains(ArisRedaction.mark), "redact: a known secret is replaced")
    check(r("key=my-eleven-key-123456;").contains(ArisRedaction.mark) && !r("key=my-eleven-key-123456;").contains("my-eleven"), "redact: a stored API key is replaced")
    check(!r("Authorization: Bearer abc.DEF-123_xyz").contains("abc.DEF"), "redact: a Bearer token")
    check(!r("using sk-ant-api03-AbCdEfGhIjKlMnOpQrSt").contains("AbCdEf") && !r("sk-proj-1234567890abcdefXYZ").contains("1234567890abcdef"),
          "redact: sk- keys")
    check(!r("xi-api-key: 0123abcdZZZZ9876").contains("0123abcd") && !r(#"{"api_key": "qwertyuiop12"}"#).contains("qwertyuiop"),
          "redact: key=value and header forms")
    check(!r("x-aris-token=\(String(repeating: "f", count: 20))").contains(String(repeating: "f", count: 20)), "redact: the Aris token header")
    check(!r("jwt eyJhbGciOiJIUzI1.eyJzdWIiOiIxMjM0NTY3.SflKxwRJSMeKKF2QT4fw").contains("eyJhbGci"), "redact: a JWT")
    check(!r("hash \(String(repeating: "9f", count: 20)) ok").contains(String(repeating: "9f", count: 20)), "redact: a long hex run")
    check(!r("blob AbCdEfGh1234IjKlMnOp5678QrStUvWx9012YzAbCd").contains("AbCdEfGh1234"), "redact: a long mixed run")
    check(r("mail user@example.com now") == "mail \(ArisRedaction.email) now", "redact: an email address")
    check(r("/Users/user/.config/aris/aris/agent.log") == "~/.config/aris/aris/agent.log", "redact: the home folder becomes ~")
    let plain = "aris-agent: a connection sent no request in 60 s; closed (uuid 5F0E6E0B-3A44-4E7B-9B53-1C2D3E4F5A6B)"
    check(r(plain) == plain, "redact: ordinary log lines and UUIDs are kept (\(r(plain)))")
    check(r("/Applications/Aris.app/Contents/MacOS/Aris-very-long-name-of-a-folder-path") == "/Applications/Aris.app/Contents/MacOS/Aris-very-long-name-of-a-folder-path",
          "redact: a long path without digits is kept")
    check(ArisRedaction.redact("short ab", secrets: ["ab"], home: "/Users/user") == "short ab", "redact: a secret too short to be one isn't used")
}

// MARK: - Typed confirmation

private func typedConfirmTests() {
    let word = ArisTypedConfirm.wipeWord
    check(ArisTypedConfirm.matches("지우기", word), "confirm: the exact word")
    check(ArisTypedConfirm.matches("  지우기 \n", word), "confirm: spaces around are fine")
    check(ArisTypedConfirm.matches("지우기".decomposedStringWithCanonicalMapping, word), "confirm: decomposed Hangul (NFD) matches")
    check(!ArisTypedConfirm.matches("지우", word) && !ArisTypedConfirm.matches("지우기요", word) && !ArisTypedConfirm.matches("", word),
          "confirm: partial, longer or empty never match")
    check(!ArisTypedConfirm.matches("지 우기", word), "confirm: a space inside doesn't match")
    check(ArisTypedConfirm.matches("제거", ArisTypedConfirm.uninstallWord) && !ArisTypedConfirm.matches("지우기", ArisTypedConfirm.uninstallWord),
          "confirm: each action has its own word")
    check(!ArisTypedConfirm.matches("제거", ""), "confirm: an empty word never matches")
}

// MARK: - API keys

private func keyTests() {
    check(ArisKeyFile.check("") == .failure(.empty) && ArisKeyFile.check("   \n") == .failure(.empty), "key: empty")
    check(ArisKeyFile.check("short-key") == .failure(.tooShort), "key: under 20 characters is too short")
    check(ArisKeyFile.check("abcd efgh ijkl mnop qrst") == .failure(.spaces), "key: a space inside is refused")
    check(ArisKeyFile.check("  sk_0123456789abcdefghij \n") == .success("sk_0123456789abcdefghij"), "key: trimmed and kept")
    check(ArisKeyFile.masked("sk_0123456789abcdef3f2a") == "••••••••3f2a", "key: shown as dots and the last four")
    check(ArisKeyFile.masked("abc") == "••••••••", "key: a short one shows dots only")
    check(ArisKeyFile.Problem.tooShort.message.contains("짧아요"), "key: Korean messages")
    // The Keychain comes first; the file is only a fallback for a key not moved yet.
    let saved = ArisKeyFile.secureStore
    ArisKeyFile.secureStore = { $0 == "elevenlabs-key" ? "from-keychain" : nil }
    check(ArisKeyFile.load("elevenlabs-key") == "from-keychain", "key: the Keychain is read first")
    ArisKeyFile.secureStore = saved
    check(ArisKeyFile.names == ["elevenlabs-key", "typesafe-key"], "key: the two keys the settings page manages")
    // A deleted key never comes back from an old file: the tombstone stops the fallback and the migration.
    check(ArisKeyFile.resolve(keychain: "k-chain", tombstoned: false, file: { "k-file" }) == "k-chain", "key: the Keychain wins")
    check(ArisKeyFile.resolve(keychain: nil, tombstoned: false, file: { "k-file" }) == "k-file", "key: an unmigrated file is the fallback")
    check(ArisKeyFile.resolve(keychain: nil, tombstoned: true, file: { "k-file" }) == nil, "key: a deleted key's old file is never read")
    check(ArisKeyFile.resolve(keychain: "new-key", tombstoned: true, file: { "k-file" }) == "new-key", "key: a key saved after a delete is used")
    check(ArisKeyFile.migration(fileKey: nil, keychainKey: nil, tombstoned: false) == .none, "migrate: no file, nothing to do")
    check(ArisKeyFile.migration(fileKey: "f", keychainKey: nil, tombstoned: false) == .importThenDrop, "migrate: a file key moves in")
    check(ArisKeyFile.migration(fileKey: "f", keychainKey: "k", tombstoned: false) == .dropOnly, "migrate: already in the Keychain, the file just goes")
    check(ArisKeyFile.migration(fileKey: "f", keychainKey: nil, tombstoned: true) == .dropOnly, "migrate: a deleted key's file is removed, never imported")
    check(ArisKeyFile.tombstone("elevenlabs-key") == "elevenlabs-key.deleted", "key: the tombstone's Keychain account")
    // The agent removes an old key file only after the app read the Keychain back.
    check(ArisKeyFile.keychainCheck(stored: "k", expected: "k", tombstoned: false) == "saved", "key check: the key read back is the one saved")
    check(ArisKeyFile.keychainCheck(stored: "k", expected: nil, tombstoned: false) == "saved", "key check: some key is in the Keychain")
    check(ArisKeyFile.keychainCheck(stored: "other", expected: "k", tombstoned: false) == nil, "key check: a different key read back is no proof")
    check(ArisKeyFile.keychainCheck(stored: nil, expected: "k", tombstoned: false) == nil, "key check: nothing read back, the file stays")
    check(ArisKeyFile.keychainCheck(stored: nil, expected: nil, tombstoned: true) == "deleted", "key check: a delete's tombstone read back")
    check(ArisKeyFile.keychainCheck(stored: nil, expected: "k", tombstoned: true) == nil, "key check: a save that didn't stick is never a delete")
    check(ArisKeyFile.dropExpectation(fileKey: "f", tombstoned: false) == "f" && ArisKeyFile.dropExpectation(fileKey: "f", tombstoned: true) == nil,
          "key check: an old file goes only when its own key is the Keychain's (or the key was deleted)")
    check(ArisKeyFile.keychainCheck(stored: "k", expected: ArisKeyFile.dropExpectation(fileKey: "f", tombstoned: false), tombstoned: false) == nil,
          "key check: a file holding another key than the Keychain's stays")
}

// MARK: - Onboarding

private func onboardingTests() {
    typealias Step = ArisOnboardingStep
    // The permissions the diagnostics report lists (the onboarding v4 asks for the first four; onboarding-tests.swift).
    check(Step.allCases.count == 9 && Step.allCases.first == .mic && Step.allCases.last == .login && Step.allCases.allSatisfy { !$0.title.isEmpty },
          "onboarding: the nine permissions the diagnostics list, each named")
    check(Step.accessibility.way == .settings && Step.screen.way == .settings && Step.login.way == .consent && Step.mic.way == .ask,
          "onboarding: settings steps, the consent step, asked steps")
    check(ArisGrant.automation(status: 0) == .granted && ArisGrant.automation(status: -1743) == .denied
          && ArisGrant.automation(status: -1744) == .undecided && ArisGrant.automation(status: -600) == .undecided,
          "onboarding: Apple Events answers")
}

// MARK: - The app's own data

private func appDataTests() {
    let root = tempHome()
    let support = root.appendingPathComponent("Application Support"), caches = root.appendingPathComponent("Caches")
    let places = ArisAppData.Places(support: support, caches: caches, bundleId: "com.lumenjsn.aris")
    let aris = support.appendingPathComponent("Aris")
    write("[]", aris.appendingPathComponent("history.json"))
    write("x", aris.appendingPathComponent("history.json.corrupt-2026-11-01"))
    write("[]", aris.appendingPathComponent("clipboard.json"))
    write("{}", aris.appendingPathComponent("router-log.jsonl"))
    write("{}", aris.appendingPathComponent("router-log.jsonl.2026-11-01"))
    write("keep", aris.appendingPathComponent("settings-note.txt"))
    write("png", caches.appendingPathComponent("com.lumenjsn.aris/ArisSprites/a.png"))
    write("other", caches.appendingPathComponent("com.lumenjsn.aris/other.bin"))
    check(Set(places.paths(for: .history).map(\.lastPathComponent)) == ["history.json", "history.json.corrupt-2026-11-01"], "app data: history and its salvaged copies")
    check(places.paths(for: .clipboard).map(\.lastPathComponent) == ["clipboard.json"], "app data: clipboard")
    check(Set(places.paths(for: .logs).map(\.lastPathComponent)) == ["router-log.jsonl", "router-log.jsonl.2026-11-01"], "app data: the app's logs")
    check(places.paths(for: .sprites).map(\.lastPathComponent) == ["ArisSprites"], "app data: the sprite cache")
    check(places.paths(for: .memory).isEmpty, "app data: memory is the agent's")
    let failed = places.remove([.history, .logs, .sprites])
    check(failed.isEmpty && !exists(aris.appendingPathComponent("history.json")) && !exists(aris.appendingPathComponent("router-log.jsonl.2026-11-01"))
          && !exists(caches.appendingPathComponent("com.lumenjsn.aris/ArisSprites")), "app data: removed what was picked")
    check(exists(aris.appendingPathComponent("clipboard.json")) && exists(aris.appendingPathComponent("settings-note.txt"))
          && exists(caches.appendingPathComponent("com.lumenjsn.aris/other.bin")), "app data: nothing else is touched")
    check(ArisAppData.Item.memory.agentSide && ArisAppData.Item.logs.agentSide && ArisAppData.Item.words.agentSide
          && !ArisAppData.Item.clipboard.agentSide, "app data: which items the agent wipes")
    check(ArisAppData.Item.allCases.filter(\.agentSide).map(\.rawValue).allSatisfy(ArisDataRoute.wipeItems.contains),
          "app data: every agent-side item is one the /data route wipes")
    try? FileManager.default.removeItem(at: root)

    // The export: history, memory and teammates as one JSON file.
    let now = Date(timeIntervalSince1970: 1_793_000_000)
    let old = ArisHistoryEntry(date: now.addingTimeInterval(-40 * 86_400), heard: "옛날", reply: "응")
    let new = ArisHistoryEntry(date: now.addingTimeInterval(-86_400), heard: "어제", reply: "네")
    let data = ArisAppData.exportJSON(history: [old, new], memory: "- 커피 좋아함 (2026-11-01)\n", teammates: [["id": "claude-code", "name": "클코"]],
                                      since: now.addingTimeInterval(-30 * 86_400), now: now)
    let root2 = json(data)
    let history = root2["history"] as? [[String: Any]] ?? []
    check(history.count == 1 && history.first?["heard"] as? String == "어제", "export: the period keeps the last 30 days")
    check((root2["memory"] as? [String]) == ["커피 좋아함 (2026-11-01)"], "export: memory as a list of facts")
    check(((root2["teammates"] as? [[String: Any]])?.first?["name"] as? String) == "클코" && root2["exported"] is String && root2["app"] as? String == "Aris",
          "export: teammates and a header")
    let none = json(ArisAppData.exportJSON(history: nil, memory: nil, teammates: nil, since: nil, now: now))
    check(none["history"] == nil && none["memory"] == nil && none["teammates"] == nil, "export: unpicked parts are left out")
    check(ArisAppData.fileName("Aris 데이터", ext: "json", now: now).hasPrefix("Aris 데이터 2026-") && ArisAppData.fileName("Aris 진단", ext: "zip", now: now).hasSuffix(".zip"),
          "export: dated file names")
}

// MARK: - The agent's /data route

private final class Effects {
    var trashed: [URL] = []
    var trashFails = false
    var bootedOut = false
    var reopened = 0
    var later: [() -> Void] = []
    var audits: [String] = []
    var logged: [String] = []
}

private func makeHome() -> (home: URL, places: ArisDataRoute.Places, app: URL, token: String) {
    let home = tempHome()
    let places = ArisDataRoute.Places(home: home)
    let folder = places.folder, data = places.data
    let token = String(repeating: "c0ffee", count: 10) + "abcd"
    write(token, folder.appendingPathComponent("claude-hook-token"))
    write("ELEVEN-SECRET-KEY-0123456789", folder.appendingPathComponent("elevenlabs-key"))
    write("- 커피 좋아함 (2026-11-01)\n- 고양이 이름은 보리 (2026-11-02)\n", data.appendingPathComponent("memory.md"))
    write("- 클코 메모\n", data.appendingPathComponent("teammates/claude-code.md"))
    write("aris-agent: started with \(token) and ELEVEN-SECRET-KEY-0123456789 at /x\n", data.appendingPathComponent("agent.log"))
    write("old\n", data.appendingPathComponent("agent.log.20261101-120000"))
    write("{\"totalMs\":900,\"heard\":\"내일 엄마한테 전화해\",\"apple\":\"내일 엄마\",\"path\":\"voice\"}\n", data.appendingPathComponent("turns.jsonl"))
    write("{\"answer\":\"yes\",\"question\":\"card 은행 송금 확인\",\"scope\":\"메일 보내기: 김철수\",\"time\":\"t\"}\n", data.appendingPathComponent("actions.log"))
    write("PNGDATA-SCREENSHOT", data.appendingPathComponent("shot.png"))
    write("{\"brain\":\"claude\"}", folder.appendingPathComponent("config.json"))
    write("bin", folder.appendingPathComponent("aris-agent"))
    write("bin", folder.appendingPathComponent("aris-tools"))
    write("plist", places.plist)
    try? FileManager.default.createSymbolicLink(at: places.oldLink, withDestinationURL: folder)
    let app = home.appendingPathComponent("Applications/Aris.app")
    try? FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
    return (home, places, app, token)
}

private func dataRouteTests() {
    var (home, places, app, token) = makeHome()
    var folder = places.folder, data = places.data
    var fx = Effects()
    func call(_ object: [String: Any], bundle: URL? = nil, appBundleId: String? = "com.lumenjsn.aris") -> ArisDataRoute.Reply {
        let effects = ArisDataRoute.Effects(trash: { url in if fx.trashFails { throw CocoaError(.fileWriteNoPermission) }; fx.trashed.append(url) },
                                            bootout: { fx.bootedOut = true }, reopenLog: { fx.reopened += 1 },
                                            later: { fx.later.append($0) }, bundleId: { _ in appBundleId }, audit: { fx.audits.append($0) },
                                            log: { fx.logged.append($0) })
        return ArisDataRoute.handle(object, places: places, appBundle: bundle, effects: effects)
    }

    check(call(["op": "nope"]).status == 400 && call([:]).status == 400, "data route: an unknown op is 400")
    check(fx.audits.count == 2 && fx.audits.allSatisfy { $0.hasPrefix("data: refused") }, "data route: every 400 is audited (\(fx.audits))")
    let summary = json(call(["op": "summary"]).body)
    check(summary["memoryFacts"] as? Int == 2 && (summary["logBytes"] as? Int ?? 0) > 0, "data route: summary counts facts and log bytes")

    // Export: memory and teammates, nothing else.
    let export = call(["op": "export"])
    let exported = json(export.body)
    check(export.status == 200 && (exported["memory"] as? String)?.contains("보리") == true && exported["teammates"] is [Any] && fx.audits.last == "data: export",
          "data route: export gives memory and teammates, with an audit line")
    check(!String(decoding: export.body, as: UTF8.self).contains(token), "data route: export never carries the token")

    // Diagnostics: the named logs only, redacted; never the token, config, keys or a screenshot.
    let diag = call(["op": "diagnostics"])
    let text = String(decoding: diag.body, as: UTF8.self)
    let logs = (json(diag.body)["logs"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
    check(diag.status == 200 && Set(logs) == ["agent.log", "actions.log", "turns.jsonl"], "data route: diagnostics are the three logs (\(logs))")
    check(!text.contains(token) && !text.contains("ELEVEN-SECRET") && !text.contains("PNGDATA") && !text.contains("\"brain\"") && text.contains(ArisRedaction.mark),
          "data route: diagnostics redact secrets and leave out the token, config and screenshots")
    check(!text.contains(home.path), "data route: diagnostics hide the home folder")
    check(!text.contains("엄마") && !text.contains("송금") && !text.contains("김철수") && text.contains("totalMs") && text.contains("voice"),
          "data route: diagnostics never carry spoken text or card titles (\(text.prefix(400)))")

    // Links are never followed: a log or a notes folder that points elsewhere is left alone and never read.
    let outside = home.appendingPathComponent("outside", isDirectory: true)
    write("SECRET-OUTSIDE-LOG", outside.appendingPathComponent("target.log"))
    write("outside note", outside.appendingPathComponent("notes/keep.md"))
    try? FileManager.default.removeItem(at: data.appendingPathComponent("turns.jsonl"))
    try? FileManager.default.createSymbolicLink(at: data.appendingPathComponent("turns.jsonl"), withDestinationURL: outside.appendingPathComponent("target.log"))
    check(!String(decoding: call(["op": "diagnostics"]).body, as: UTF8.self).contains("SECRET-OUTSIDE"), "data route: diagnostics never read through a link")

    // Wipe: the typed word and a known list, or nothing happens (and the refusal is audited).
    check(call(["op": "wipe", "items": ["memory"], "confirm": "지우"]).status == 400 && exists(data.appendingPathComponent("memory.md"))
          && fx.audits.last?.hasPrefix("data: refused wipe") == true, "data route: wipe without the exact word is refused and audited")
    check(call(["op": "wipe", "items": ["memory", "teammates"], "confirm": "지우기"]).status == 400 && exists(data.appendingPathComponent("memory.md")),
          "data route: wipe with an unknown item is refused whole")
    check(call(["op": "wipe", "items": [], "confirm": "지우기"]).status == 400 && call(["op": "wipe", "items": "memory", "confirm": "지우기"]).status == 400,
          "data route: wipe needs a list of items")
    let wipe = call(["op": "wipe", "items": ["memory", "logs"], "confirm": "지우기"])
    check(wipe.status == 200 && fx.audits.last == "data: wipe memory, logs", "data route: wipe answers and is audited")
    check(!exists(data.appendingPathComponent("memory.md")) && !exists(data.appendingPathComponent("teammates/claude-code.md"))
          && !exists(data.appendingPathComponent("agent.log.20261101-120000")),
          "data route: memory, teammate notes and logs are gone")
    check(exists(data.appendingPathComponent("agent.log")) && ((try? Data(contentsOf: data.appendingPathComponent("agent.log")))?.isEmpty ?? false) && fx.reopened == 1,
          "data route: the open agent.log is emptied in place, not removed")
    check((try? String(contentsOf: outside.appendingPathComponent("target.log"), encoding: .utf8)) == "SECRET-OUTSIDE-LOG",
          "data route: wipe never empties or removes a file a link points to")
    check(exists(data.appendingPathComponent("actions.log")) && exists(folder.appendingPathComponent("claude-hook-token")),
          "data route: the audit log and the token stay")
    try? FileManager.default.removeItem(at: data.appendingPathComponent("teammates"))
    try? FileManager.default.createSymbolicLink(at: data.appendingPathComponent("teammates"), withDestinationURL: outside.appendingPathComponent("notes"))
    _ = call(["op": "wipe", "items": ["memory"], "confirm": "지우기"])
    check(exists(outside.appendingPathComponent("notes/keep.md")), "data route: a linked notes folder is never walked")
    write("{}", data.appendingPathComponent("dictionary.json"))
    write("노션\n", data.appendingPathComponent("vocabulary.txt"))
    write("keep me", data.appendingPathComponent("memory.md"))
    let words = call(["op": "wipe", "items": ["words"], "confirm": "지우기"])
    check(words.status == 200 && fx.audits.last == "data: wipe words" && !exists(data.appendingPathComponent("dictionary.json"))
          && !exists(data.appendingPathComponent("vocabulary.txt")) && exists(data.appendingPathComponent("memory.md")),
          "data route: wiping words removes dictation's dictionary and word list, nothing else")

    // Old key files: only the two names, only once the app read the key back from the Keychain.
    check(call(["op": "dropKeyFile", "name": "../claude-hook-token", "keychain": "saved"]).status == 400
          && call(["op": "dropKeyFile", "name": "canvas-key", "keychain": "saved"]).status == 400,
          "data route: dropKeyFile takes only the settings page's two key names")
    check(call(["op": "dropKeyFile", "name": "elevenlabs-key"]).status == 400 && call(["op": "dropKeyFile", "name": "elevenlabs-key", "keychain": true]).status == 400
          && exists(folder.appendingPathComponent("elevenlabs-key")), "data route: dropKeyFile without the app's Keychain check is refused")
    let drop = call(["op": "dropKeyFile", "name": "elevenlabs-key", "keychain": "saved"])
    check(drop.status == 200 && !exists(folder.appendingPathComponent("elevenlabs-key")) && fx.audits.last == "data: key file elevenlabs-key removed (saved in the Keychain)",
          "data route: an old key file is removed once the key is in the Keychain")

    // Uninstall: the word and the real app bundle, or nothing.
    check(call(["op": "uninstall", "confirm": "제거"]).status == 400, "data route: uninstall needs the caller's app bundle")
    check(call(["op": "uninstall", "confirm": "삭제"], bundle: app).status == 400, "data route: uninstall needs the exact word")
    check(call(["op": "uninstall", "confirm": "제거"], bundle: app, appBundleId: "com.other.app").status == 400, "data route: never trashes another app")
    check(call(["op": "uninstall", "confirm": "제거"], bundle: home.appendingPathComponent("Applications/Aris")).status == 400, "data route: only an .app bundle")
    check(fx.later.isEmpty && exists(folder) && fx.trashed.isEmpty, "data route: nothing happened yet")

    // A translocated or untrashable app stops everything before the agent or its folder is touched.
    let translocated = home.appendingPathComponent("private/var/folders/x/AppTranslocation/ABC/d/Aris.app")
    try? FileManager.default.createDirectory(at: translocated, withIntermediateDirectories: true)
    let stopped = call(["op": "uninstall", "confirm": "제거", "keepData": false], bundle: translocated)
    let stoppedSteps = json(stopped.body)["steps"] as? [[String: Any]] ?? []
    check(stopped.status == 200 && json(stopped.body)["done"] as? Bool == false && stoppedSteps.count == 1 && stoppedSteps.first?["ok"] as? Bool == false
          && exists(places.plist) && exists(folder.appendingPathComponent("aris-agent")) && fx.later.isEmpty,
          "data route: a translocated app stops the uninstall before anything else")
    fx.trashFails = true
    _ = call(["op": "uninstall", "confirm": "제거", "keepData": false], bundle: app)
    check(exists(places.plist) && exists(folder) && !fx.bootedOut && fx.audits.last?.contains("app failed") == true,
          "data route: a failed trash stops before the agent and folder, and says so in the audit")
    fx.trashFails = false

    // keepData missing or not a bool keeps the records.
    let runtime = places.home.appendingPathComponent("Library/Application Support/Aris/skills-runtime/venv")
    try? FileManager.default.createDirectory(at: runtime, withIntermediateDirectories: true)
    let skillsFolder = places.home.appendingPathComponent("Library/Application Support/Aris/Skills")
    try? FileManager.default.createDirectory(at: skillsFolder.appendingPathComponent(".incoming/job"), withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: skillsFolder.appendingPathComponent("mine"), withIntermediateDirectories: true)
    // The runtime is read-only once installed: uninstall removes it anyway.
    _ = chmod(runtime.path, 0o555)
    let keep = call(["op": "uninstall", "confirm": "제거", "keepData": "no"], bundle: app)
    let steps = json(keep.body)["steps"] as? [[String: Any]] ?? []
    check(keep.status == 200 && json(keep.body)["done"] as? Bool == true && steps.map { $0["step"] as? String ?? "" } == ["app", "hooks", "antigravity", "link", "launchAgent", "skills", "binaries"]
          && steps.allSatisfy { $0["ok"] as? Bool == true }, "data route: uninstall reports each step's real result (\(steps))")
    check(!exists(runtime.deletingLastPathComponent()) && !exists(skillsFolder.appendingPathComponent(".incoming")) && exists(skillsFolder.appendingPathComponent("mine")),
          "data route: uninstall removes the skills runtime and what was fetched but never added; with the records kept, the user's skills stay")
    check(fx.trashed == [app] && !exists(folder.appendingPathComponent("aris-agent")) && !exists(folder.appendingPathComponent("aris-tools"))
          && exists(data.appendingPathComponent("actions.log")) && !exists(places.plist) && fx.later.count == 1 && !fx.bootedOut,
          "data route: a malformed keepData keeps the records; the binaries and LaunchAgent go")
    check((try? FileManager.default.destinationOfSymbolicLink(atPath: places.oldLink.path)) == nil, "data route: the old folder's link is removed")
    check(fx.audits.filter { $0.hasPrefix("data: uninstall") }.count >= 7, "data route: every uninstall step is audited")
    fx.later.removeFirst()()
    check(fx.bootedOut, "data route: the agent boots itself out last, after the reply")
    try? FileManager.default.removeItem(at: home)

    (home, places, app, token) = makeHome()
    folder = places.folder; data = places.data
    fx = Effects()
    let allSkills = places.home.appendingPathComponent("Library/Application Support/Aris/Skills/mine")
    try? FileManager.default.createDirectory(at: allSkills, withIntermediateDirectories: true)
    let all = call(["op": "uninstall", "confirm": "제거", "keepData": false], bundle: app)
    check(!exists(allSkills.deletingLastPathComponent()), "data route: a full uninstall removes the skills too")
    check(all.status == 200 && !exists(folder) && json(all.body)["done"] as? Bool == true, "data route: keepData false removes ~/.config/aris")
    let replyAudit = json(all.body)["audit"] as? [String] ?? []
    check(replyAudit.contains { $0.contains("folder ok") } && !fx.audits.contains { $0.contains("folder ok") } && fx.logged.contains { $0.contains("folder ok") },
          "data route: once the folder is gone its audit lines go to the reply and the unified log, never recreating it")
    fx.later.removeFirst()()
    check(fx.bootedOut && fx.logged.last == "data: uninstall bootout" && !exists(folder), "data route: the bootout line too")
    try? FileManager.default.removeItem(at: home)

    hookCleanupTests()
}

// MARK: - Uninstall: Aris's own hook entries and Antigravity rules

private func diagnosticsFilterTests() {
    let agent = "aris-agent: made a new token file\naris-agent: claude: {\"type\":\"text\",\"text\":\"secret answer\"}\nchild stderr: the prompt was X\naris-agent: a connection sent no request in 60 s; closed\n"
    check(ArisDiagnosticsFilter.agentLog(agent) == "aris-agent: made a new token file\naris-agent: a connection sent no request in 60 s; closed\n",
          "diagnostics filter: agent.log keeps the agent's own lines, not a model's or a child's output")
    let actions = "{\"answer\":\"refused (the user said no to 송금)\",\"question\":\"x/1\",\"scope\":\"메일\",\"time\":\"2026\"}\n{\"action\":\"insert: 3 characters\",\"risk\":\"dictated\"}\nnot json\n"
    let filtered = ArisDiagnosticsFilter.actions(actions)
    check(filtered.contains("\"answer\":\"refused\"") && filtered.contains("\"action\":\"insert\"") && filtered.contains("dictated")
          && !filtered.contains("송금") && !filtered.contains("메일") && !filtered.contains("x/1") && !filtered.contains("not json"),
          "diagnostics filter: actions.log keeps the kind of each line, not its card or details (\(filtered))")
    let turns = ArisDiagnosticsFilter.turns("{\"heard\":\"전화해\",\"whisper\":\"전화\",\"apple\":\"전\",\"tier\":\"quick\",\"totalMs\":800}\n")
    check(!turns.contains("전") && turns.contains("quick") && turns.contains("800"), "diagnostics filter: turns.jsonl keeps the numbers, never the words")
}

private func hookCleanupTests() {
    diagnosticsFilterTests()
    // Codex's hooks feature goes back off only when Aris's installer turned it on.
    let added = "model = \"o3\"\n\n[features]\ncodex_hooks = true\n"
    check(ArisUninstallCleanup.codexConfig(added, before: "model = \"o3\"\n") == "model = \"o3\"\n", "cleanup: an added [features] codex_hooks goes")
    check(ArisUninstallCleanup.codexConfig("[features]\nweb = true\ncodex_hooks = true\n", before: "[features]\nweb = true\n") == "[features]\nweb = true\n",
          "cleanup: an added codex_hooks line goes, the section stays")
    check(ArisUninstallCleanup.codexConfig("[features]\ncodex_hooks = true\n", before: "[features]\ncodex_hooks = false\n") == "[features]\ncodex_hooks = false\n",
          "cleanup: a flipped codex_hooks goes back to false")
    check(ArisUninstallCleanup.codexConfig(added, before: added) == nil && ArisUninstallCleanup.codexConfig(added, before: nil) == nil,
          "cleanup: codex_hooks the user had on, or no proof Aris added it, stays")
    let aris = "/Users/p/.config/aris"
    let claude: [String: Any] = [
        "model": "opus",
        "hooks": ["Stop": [["matcher": "", "hooks": [["type": "http", "url": "http://127.0.0.1:23350/hook"]]],
                           ["matcher": "", "hooks": [["type": "command", "command": "clawd stop"]]]],
                  "SessionStart": [["matcher": "", "hooks": [["type": "http", "url": "http://127.0.0.1:23350/hook"], ["type": "command", "command": "mine"]]]]],
        "statusLine": ["type": "command", "command": aris + "/statusline.sh"],
    ]
    let cleaned = ArisUninstallCleanup.claude(claude, arisFolders: [aris, "/Users/p/.config/boring-notch"])
    let hooks = cleaned?["hooks"] as? [String: Any]
    let stop = hooks?["Stop"] as? [[String: Any]]
    let start = (hooks?["SessionStart"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]]
    check(stop?.count == 1 && ((stop?.first?["hooks"] as? [[String: Any]])?.first?["command"] as? String) == "clawd stop", "cleanup: Claude keeps others' hooks, drops Aris's group")
    check(start?.count == 1 && start?.first?["command"] as? String == "mine", "cleanup: inside a shared group only Aris's hook goes")
    check(cleaned?["statusLine"] == nil && cleaned?["model"] as? String == "opus", "cleanup: Aris's status line goes, other settings stay")
    let theirs: [String: Any] = ["statusLine": ["type": "command", "command": "~/my-line.sh"], "hooks": ["Stop": [["hooks": [["type": "command", "command": "x"]]]]]]
    check(ArisUninstallCleanup.claude(theirs, arisFolders: [aris]) == nil, "cleanup: nothing of Aris's, nothing changed")
    let codex: [String: Any] = ["hooks": ["Stop": [["hooks": [["type": "command", "command": "\"\(aris)/agent-hook.sh\" codex", "timeout": 5]]],
                                                   ["hooks": [["type": "command", "command": "orca stop"]]]]]]
    let codexOut = ArisUninstallCleanup.agentHooks(codex, arisFolders: [aris])
    check(((codexOut?["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])?.count == 1, "cleanup: Codex/Gemini hooks lose only agent-hook.sh")
    let agy: [String: Any] = ["permissions": ["allow": ["command(\(aris)/aris-tools)", "read_url(*)", "command(git status)"],
                                              "deny": ["command(rm)", "write_file(\(aris)/aris/shortcuts.json)", "command(\(aris)/aris-tools message)", "command(sudo)"]],
                              "theme": "dark"]
    let before: [String: Any] = ["permissions": ["allow": ["command(git status)"], "deny": ["command(sudo)"]]]
    let agyOut = ArisUninstallCleanup.antigravity(agy, before: before, arisFolders: [aris])
    let perms = agyOut?["permissions"] as? [String: Any]
    check((perms?["allow"] as? [String]) == ["command(git status)"] && (perms?["deny"] as? [String]) == ["command(sudo)"] && agyOut?["theme"] as? String == "dark",
          "cleanup: Antigravity loses Aris's rules and keeps what was there before Aris")
    let lost: [String: Any] = ["permissions": ["allow": [], "deny": ["command(\(aris)/aris-tools message)"]]]
    let lostBefore: [String: Any] = ["permissions": ["allow": [], "deny": ["command(my-own-rule)"]]]
    check(((ArisUninstallCleanup.antigravity(lost, before: lostBefore, arisFolders: [aris])?["permissions"] as? [String: Any])?["deny"] as? [String]) == ["command(my-own-rule)"],
          "cleanup: deny rules that were there before Aris come back")
    let agyNoBefore = ArisUninstallCleanup.antigravity(agy, before: nil, arisFolders: [aris])
    check(((agyNoBefore?["permissions"] as? [String: Any])?["allow"] as? [String]) == ["read_url(*)", "command(git status)"],
          "cleanup: without the before-Aris copy only rules naming Aris's folder go")

    // On disk: a backup is left next to each file changed, and a linked settings file is never written through.
    let home = tempHome()
    let settings = home.appendingPathComponent(".claude/settings.json")
    try? FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
    let arisHere = home.appendingPathComponent(".config/aris").path
    var withOurs = claude
    withOurs["statusLine"] = ["type": "command", "command": arisHere + "/statusline.sh"]
    try? JSONSerialization.data(withJSONObject: withOurs).write(to: settings)
    let results = ArisUninstallCleanup.run(home: home, stamp: "20261104-120000")
    let names = (try? FileManager.default.contentsOfDirectory(atPath: settings.deletingLastPathComponent().path)) ?? []
    check(results.allSatisfy(\.ok) && names.contains("settings.json.aris-uninstall-20261104-120000"), "cleanup: a backup is left (\(names), \(results))")
    let mode = (try? FileManager.default.attributesOfItem(atPath: settings.deletingLastPathComponent().appendingPathComponent("settings.json.aris-uninstall-20261104-120000").path))?[.posixPermissions] as? Int
    check(mode == 0o600, "cleanup: the backup is 0600 (\(String(mode ?? 0, radix: 8)))")
    let after = json((try? Data(contentsOf: settings)) ?? Data())
    check(after["statusLine"] == nil && after["model"] as? String == "opus", "cleanup: the file is rewritten without Aris's entries")
    let target = home.appendingPathComponent("elsewhere.json")
    let geminiHooks: [String: Any] = ["hooks": ["Stop": [["hooks": [["type": "command", "command": "\"\(arisHere)/agent-hook.sh\" gemini"]]]]]]
    try? JSONSerialization.data(withJSONObject: geminiHooks).write(to: target)
    let gemini = home.appendingPathComponent(".gemini/settings.json")
    try? FileManager.default.createDirectory(at: gemini.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? FileManager.default.createSymbolicLink(at: gemini, withDestinationURL: target)
    _ = ArisUninstallCleanup.run(home: home, stamp: "20261104-120001")
    check(((json((try? Data(contentsOf: target)) ?? Data())["hooks"] as? [String: Any])?["Stop"] as? [Any])?.count == 1,
          "cleanup: a settings file that is a link is left alone")
    try? FileManager.default.removeItem(at: home)
}
