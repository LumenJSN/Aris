//
//  ArisDataRoute.swift
//  aris-agent
//
//  POST /data: the settings 정보 › 데이터 rows (audit ④ C) for what lives in ~/.config/aris, which the sandboxed app
//  can't write. Only the Aris app itself may call it (ArisPeer, checked in main.swift, which runs this off the server
//  queue). Every op that reads the user's data or removes anything writes an audit line, and so does every refusal.
//  Removing needs the word the user typed (ArisTypedConfirm), checked here again; an unknown op, item or name is refused
//  whole (400) with nothing touched. Nothing is read, emptied or removed through a symbolic link (ArisNoFollow).
//
//    {"op": "summary"}                                   -> {"memoryFacts": n, "logBytes": n}  (memories in memory.sqlite)
//    {"op": "export"}                                    -> {"memory": "...", "teammates": [...]}
//    {"op": "diagnostics"}                               -> {"logs": [{"name", "text"}]}: the ends of agent.log, actions.log
//                                                           and turns.jsonl, filtered to how Aris behaved (never words said
//                                                           or card titles: ArisDiagnosticsFilter) and redacted
//                                                           (ArisRedaction). Never the token, a key, a config file or an image.
//    {"op": "wipe", "items": ["memory"|"words"|"logs"], "confirm": "지우기"}   -> {"wiped": [...]}
//                                                           memory.sqlite's rows, memory.md, teammates/*.md and
//                                                           shortcuts.json (then the helper's caches are read again);
//                                                           dictionary.json and vocabulary.txt (dictation's words); agent.log (emptied in place:
//                                                           launchd holds it open), its copies and turns.jsonl. actions.log
//                                                           (the audit) stays.
//    {"op": "dropKeyFile", "name": "elevenlabs-key"|"typesafe-key"|"soniox-key"|"openai-key", "keychain": "saved"|"deleted"}  -> {}: only once the
//                                                           app read the key (or its delete tombstone) back from the Keychain
//    {"op": "uninstall", "confirm": "제거", "keepData"?: bool (true unless exactly false)}
//                                                        -> {"done": bool, "steps": [{"step", "ok", "note"?}]}: in order,
//                                                           each checked and audited: the calling app's own bundle to the
//                                                           Trash (a translocated or untrashable app stops everything
//                                                           here), Aris's hook entries and Antigravity rules (backups
//                                                           left), the ~/.config/boring-notch link, the LaunchAgent plist,
//                                                           the helpers' caches and old defaults under ~/Library, the
//                                                           binaries (or all of ~/.config/aris; audit lines after that go
//                                                           to the reply's "audit" and the unified log); after the reply,
//                                                           launchctl bootout of this agent.
//

import AppKit
import os

enum ArisDataRoute {
    struct Reply {
        let status: Int
        let body: Data
    }

    struct Places {
        let home: URL

        var folder: URL { home.appendingPathComponent(".config/aris", isDirectory: true) }
        var data: URL { folder.appendingPathComponent("aris", isDirectory: true) }
        var memory: URL { data.appendingPathComponent("memory.md") }
        var teammateNotes: URL { data.appendingPathComponent("teammates", isDirectory: true) }
        /// Learned shortcuts (ArisShortcutStore): requests Aris does again with no AI, learned from the user's words.
        var shortcuts: URL { data.appendingPathComponent("shortcuts.json") }
        var agentLog: URL { data.appendingPathComponent("agent.log") }
        var turns: URL { data.appendingPathComponent("turns.jsonl") }
        /// Dictation's learned dictionary (ArisLearnedDictionary) and the user's word list (ArisVocabulary).
        var words: [URL] { ["dictionary.json", "vocabulary.txt"].map { data.appendingPathComponent($0) } }
        var plist: URL { home.appendingPathComponent("Library/LaunchAgents/\(ArisDataRoute.label).plist") }
        var oldLink: URL { home.appendingPathComponent(".config/boring-notch") }
        /// The link to the tools inside the app, and what an install made the old way may have left beside it.
        var binaries: [URL] { ["aris-agent", "aris-tools", "aris-agent.new", "aris-tools.new"].map { folder.appendingPathComponent($0) } }
    }

    /// What the route does to the world beyond ~/.config/aris (the tests record them instead).
    struct Effects {
        var trash: (URL) throws -> Void
        var bootout: () -> Void
        /// After agent.log is emptied: this process's stderr offset goes to the new end (ArisLogRotation.rotateOpenLog).
        var reopenLog: () -> Void
        /// Runs once the reply has gone out (the bootout, which ends this process).
        var later: (@escaping () -> Void) -> Void
        /// The bundle id of the app bundle at a URL, as its Info.plist on disk has it (appBundleIdOnDisk).
        var bundleId: (URL) -> String?
        /// One actions.log line.
        var audit: (String) -> Void
        /// One unified-log line: where uninstall's audit goes once ~/.config/aris is gone (writing actions.log would
        /// make the folder again).
        var log: (String) -> Void
        /// Stops a skills setup under way and removes the runtime (uninstall, before the folders go).
        var stopSkills: () -> Void = {}
        /// Deletes the helper's Keychain items under one service, never reading them (uninstall). Records nothing
        /// unless set: the tests never touch a real keychain.
        var deleteKeychain: (String) -> Bool = { _ in true }
        /// After a wipe, with what was wiped: every copy this process keeps in memory is read again from the emptied
        /// files (the memories and work lessons a turn is given come from caches: ArisMemoryCurator, ArisWorkDesk).
        var wiped: ([String]) -> Void = { _ in }
        /// Uninstall, once the app is in the Trash: this helper stops writing where the uninstall removes things
        /// (ArisUninstallQuiet; `true`: ~/.config/aris goes whole). Records nothing unless set.
        var quiesce: (_ removingFolder: Bool) -> Void = { _ in }
        /// `tccutil reset <service> com.lumenjsn.aris`: Aris's own row for one permission goes (uninstall). True when
        /// tccutil said it did. Never run unless set: the tests never touch this Mac's permissions.
        var resetPermission: (String) -> Bool = { _ in true }
        /// After the reply, once this helper has stopped: what the uninstall removed is removed once more by a step
        /// that outlives it, for anything written in its last moment. Nothing unless set.
        var sweep: ([URL]) -> Void = { _ in }

        static func live(audit: @escaping (String) -> Void) -> Effects {
            Effects(
                trash: { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) },
                bootout: {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
                    process.arguments = ["bootout", "gui/\(getuid())/\(ArisDataRoute.label)"]
                    try? ArisChildren.run(process)
                    process.waitUntilExit()
                },
                reopenLog: { lseek(STDERR_FILENO, 0, SEEK_END) },
                later: { work in DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1, execute: work) },
                bundleId: ArisDataRoute.appBundleIdOnDisk,
                audit: audit,
                log: { line in Logger(subsystem: "com.lumenjsn.aris.agent", category: "data").notice("\(line, privacy: .public)") },
                deleteKeychain: ArisUninstallCleanup.deleteKeychainItems(service:),
                quiesce: { removingFolder in ArisUninstallQuiet.begin(removingFolder: removingFolder) },
                resetPermission: ArisUninstallCleanup.resetPermission(service:),
                sweep: ArisUninstallCleanup.sweepAfterExit(_:))
        }
    }

    static let label = "com.lumenjsn.aris.agent"
    static let appBundleId = "com.lumenjsn.aris"
    /// In the order the sheet lists them.
    static let wipeItems = ["memory", "words", "logs"]
    static let keyFiles: Set<String> = ["elevenlabs-key", "typesafe-key", "soniox-key", "openai-key"]
    /// What the app checked in the Keychain before asking for a key file to go.
    static let keychainChecks: Set<String> = ["saved", "deleted"]
    /// How much of the end of each log goes into a diagnostics file.
    static let diagnosticLogs: [(name: String, bytes: Int)] = [("agent.log", 512 * 1_024), ("actions.log", 256 * 1_024), ("turns.jsonl", 64 * 1_024)]

    /// `appBundle`: the calling app's own bundle (from its verified pid), the only thing uninstall may put in the Trash.
    static func handle(_ object: [String: Any], places: Places, appBundle: URL?, effects: Effects) -> Reply {
        let op = object["op"] as? String
        switch op {
        case "summary": return ok(["memoryFacts": memoryFacts(places), "logBytes": logBytes(places)])
        case "export": return export(places, effects)
        case "diagnostics": return diagnostics(places, effects)
        case "wipe": return wipe(object, places: places, effects: effects)
        case "dropKeyFile": return dropKeyFile(object, places: places, effects: effects)
        case "uninstall": return uninstall(object, places: places, appBundle: appBundle, effects: effects)
        default: return refuse(String((op ?? "no op").prefix(32)), "unknown op", effects)
        }
    }

    // MARK: - Ops

    private static func export(_ places: Places, _ effects: Effects) -> Reply {
        let memory = memoryStore(places)?.exportText() ?? ""
        let teammates = ArisTeammateStore.load(file: ArisTeammateStore.file(home: places.home.path))
        let list = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(teammates))) ?? []
        effects.audit("data: export")
        // Each memory's source, mark and whole text, and the work memory (review 8, LOW).
        let extras = memoryStore(places).map(ArisDataExport.extras(memory:)) ?? [:]
        let base: [String: Any] = ["memory": memory, "teammates": list]
        return ok(base.merging(extras) { first, _ in first })
    }

    private static func diagnostics(_ places: Places, _ effects: Effects) -> Reply {
        guard ArisNoFollow.isDirectory(places.folder), ArisNoFollow.isDirectory(places.data) else {
            return refuse("diagnostics", "~/.config/aris is not a real folder", effects)
        }
        let secrets = knownSecrets(places)
        let logs = diagnosticLogs.compactMap { log -> [String: Any]? in
            guard let raw = tail(places.data.appendingPathComponent(log.name), bytes: log.bytes) else { return nil }
            // How Aris behaved, never what was said (ArisDiagnosticsFilter), then the secrets out.
            let text = log.name == "agent.log" ? ArisDiagnosticsFilter.agentLog(raw)
                : log.name == "actions.log" ? ArisDiagnosticsFilter.actions(raw) : ArisDiagnosticsFilter.turns(raw)
            return ["name": log.name, "text": ArisRedaction.redact(text, secrets: secrets, home: places.home.path)]
        }
        effects.audit("data: diagnostics")
        return ok(["logs": logs])
    }

    private static func wipe(_ object: [String: Any], places: Places, effects: Effects) -> Reply {
        guard ArisTypedConfirm.matches(object["confirm"] as? String ?? "", ArisTypedConfirm.wipeWord) else {
            return refuse("wipe", "confirm word", effects)
        }
        guard let items = object["items"] as? [String], !items.isEmpty, Set(items).isSubset(of: Set(wipeItems)) else {
            return refuse("wipe", "items", effects)
        }
        guard ArisNoFollow.isDirectory(places.folder), ArisNoFollow.isDirectory(places.data) else {
            return refuse("wipe", "~/.config/aris is not a real folder", effects)
        }
        let picked = wipeItems.filter(items.contains)
        if picked.contains("memory") {
            // Every memory, day note and summary (overwritten on disk), and memory.md.
            memoryStore(places)?.deleteAll()
            // And what Aris learned from its own work, in the same file (ArisWorkStore).
            if let store = memoryStore(places) { ArisWorkStore(memory: store).deleteAll() }
            ArisNoFollow.removeFile(places.memory)
            // And the learned shortcuts, learned from the same words.
            ArisNoFollow.removeFile(places.shortcuts)
            for name in ArisNoFollow.contents(places.teammateNotes) where name.hasSuffix(".md") {
                ArisNoFollow.removeFile(places.teammateNotes.appendingPathComponent(name))
            }
        }
        if picked.contains("words") { places.words.forEach { ArisNoFollow.removeFile($0) } }
        if picked.contains("logs") {
            if ArisNoFollow.truncate(places.agentLog) { effects.reopenLog() }
            for file in [places.agentLog, places.turns] {
                for name in ArisLogRotation.generations(of: file) { ArisNoFollow.removeFile(places.data.appendingPathComponent(name)) }
            }
            ArisNoFollow.removeFile(places.turns)
        }
        effects.wiped(picked)
        effects.audit("data: wipe " + picked.joined(separator: ", "))
        return ok(["wiped": picked])
    }

    private static func dropKeyFile(_ object: [String: Any], places: Places, effects: Effects) -> Reply {
        guard let name = object["name"] as? String, keyFiles.contains(name) else { return refuse("dropKeyFile", "name", effects) }
        // The app sends this only after reading the key (or its delete tombstone) back from the Keychain.
        guard let check = object["keychain"] as? String, keychainChecks.contains(check) else {
            return refuse("dropKeyFile", "no Keychain check for \(name)", effects)
        }
        let file = places.folder.appendingPathComponent(name)
        guard ArisNoFollow.removeFile(file) else { return refuse("dropKeyFile", "\(name) is not a plain file", effects) }
        effects.audit("data: key file \(name) removed (\(check) in the Keychain)")
        return ok([:])
    }

    // MARK: - Uninstall

    private static func uninstall(_ object: [String: Any], places: Places, appBundle: URL?, effects: Effects) -> Reply {
        guard ArisTypedConfirm.matches(object["confirm"] as? String ?? "", ArisTypedConfirm.uninstallWord) else {
            return refuse("uninstall", "confirm word", effects)
        }
        guard let appBundle, appBundle.pathExtension == "app", effects.bundleId(appBundle) == appBundleId else {
            return refuse("uninstall", "not the Aris app's bundle", effects)
        }
        // Only an explicit false removes the records.
        let keepData = (object["keepData"] as? Bool) != false
        effects.audit("data: uninstall start (\(keepData ? "records kept" : "everything"))")
        var steps: [[String: Any]] = []
        var folderGone = false
        var lateAudit: [String] = []
        func record(_ step: String, _ ok: Bool, _ note: String? = nil) {
            var row: [String: Any] = ["step": step, "ok": ok]
            if let note { row["note"] = note }
            steps.append(row)
            let line = "data: uninstall \(step) \(ok ? "ok" : "failed")" + (note.map { ": \($0)" } ?? "")
            // Once the folder is gone, actions.log would bring it back: the line goes to the reply and the unified log.
            if folderGone { lateAudit.append(line); effects.log(line) } else { effects.audit(line) }
        }

        // 1. The app. If it can't go (translocated, or the Trash refuses), nothing else goes either.
        if appBundle.path.contains("/AppTranslocation/") {
            record("app", false, "translocated: move Aris to Applications first")
            return ok(["done": false, "steps": steps])
        }
        do {
            try effects.trash(appBundle)
            record("app", true)
        } catch {
            record("app", false, error.localizedDescription)
            return ok(["done": false, "steps": steps])
        }

        // 1b. From here this helper writes nothing where the uninstall removes things: the aris-tools link is never
        // put back, and with the records going nothing more is written in ~/.config/aris (VM run 2026-11-19: the
        // folder's removal failed while actions.log and children.json were still being written, and the link, the
        // log and the list came back after it).
        effects.quiesce(!keepData)

        // 2. Aris's hook entries and Antigravity rules, each file backed up first.
        let cleanup = ArisUninstallCleanup.run(home: places.home, stamp: stamp())
        // Antigravity's file is the last result.
        let hooks = cleanup.dropLast(), agy = cleanup.last
        record("hooks", hooks.allSatisfy(\.ok), hooks.map(\.description).joined(separator: "; "))
        record("antigravity", agy?.ok ?? true, agy?.description)

        // 2b. The helper's Keychain items (API keys, MCP secrets), deleted by service, never read.
        let keptKeychain = ArisUninstallCleanup.removeKeychain(effects.deleteKeychain)
        record("keychain", keptKeychain.isEmpty, keptKeychain.isEmpty ? nil : "not removed: " + keptKeychain.joined(separator: ", "))

        // 3. The old folder name's link (only a link that points at ~/.config/aris).
        record("link", removeOldLink(places))

        // 4. The LaunchAgent plist, so it never starts again.
        record("launchAgent", remove(places.plist))

        // 4a. What macOS kept for the helper programs under ~/Library (their caches, HTTP storage, old defaults).
        record("helperFiles", ArisUninstallCleanup.helperLibraryItems(home: places.home).map(remove).allSatisfy { $0 })

        // 4b. Skills: the setup is stopped, the runtime (Python and SkillSpector, read-only once installed) and anything
        // fetched but never added go; the user's skills themselves go only when their records do (keepData false).
        effects.stopSkills()
        let aris = places.home.appendingPathComponent("Library/Application Support/Aris")
        let runtime = aris.appendingPathComponent("skills-runtime")
        ArisSkillRuntimeFiles.makeWritable(runtime)
        let skillsGone = remove(runtime) && remove(aris.appendingPathComponent("Skills/.incoming"))
            && (keepData || remove(aris.appendingPathComponent("Skills")))
        record("skills", skillsGone)

        // 4c. The rest Aris keeps under ~/Library outside its sandbox: Application Support/Aris (the engine's input
        // ladder and the rest; the user's skills stay with their records), and the caches and HTTP storage the helper and
        // aris-tools keep under the app's id (VM run 2026-11-19: all of it was left).
        let appFiles = ArisUninstallCleanup.appLibraryItems(home: places.home, keepSkills: keepData)
        record("appFiles", appFiles.map(remove).allSatisfy { $0 })

        // 4d. Aris's own rows in Privacy & Security, reset by its bundle id (tccutil), one service at a time.
        let keptRows = ArisUninstallCleanup.resetPermissions(effects.resetPermission)
        record("permissions", keptRows.isEmpty, keptRows.isEmpty ? nil : "not reset: " + keptRows.joined(separator: ", "))

        // 4e. The app's sandbox folders: macOS keeps ~/Library/Containers/com.lumenjsn.aris for the app (only Finder,
        // or a program with Full Disk Access, may remove it, and the app is still open): never tried here, and said
        // so. Its Application Scripts folder is tried.
        let scripts = ArisUninstallCleanup.sandboxScripts(home: places.home)
        let scriptsGone = remove(scripts)
        record("sandbox", false, "kept by macOS: ~/Library/Containers/com.lumenjsn.aris" + (scriptsGone ? "" : ", ~/Library/Application Scripts/com.lumenjsn.aris"))

        // 5. The binaries, or the whole folder (tried again once what was being written has settled).
        var swept = appFiles + ArisUninstallCleanup.helperLibraryItems(home: places.home)
        if keepData {
            record("binaries", places.binaries.map(removeSettled).allSatisfy { $0 })
            swept += places.binaries
        } else {
            let removed = removeSettled(places.folder)
            folderGone = removed
            record("folder", removed)
            swept.append(places.folder)
        }

        // 6. Last, after the reply: this agent stops itself.
        let gone = folderGone
        effects.later {
            if gone { effects.log("data: uninstall bootout") } else { effects.audit("data: uninstall bootout") }
            // The last remover outlives this helper: anything written in its last moment goes too.
            effects.sweep(swept)
            effects.bootout()
        }
        var reply: [String: Any] = ["done": steps.allSatisfy { $0["ok"] as? Bool == true }, "steps": steps]
        if !lateAudit.isEmpty { reply["audit"] = lateAudit }
        return ok(reply)
    }

    /// `remove`, tried again a few times a moment apart: a folder something was still writing into when it went.
    private static func removeSettled(_ url: URL) -> Bool {
        for attempt in 0..<4 {
            if remove(url) { return true }
            if attempt < 3 { usleep(250_000) }
        }
        return false
    }

    /// Removes a file, a folder (its contents never followed out) or a link itself; true when it's gone.
    private static func remove(_ url: URL) -> Bool {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return true }
        do { try FileManager.default.removeItem(at: url); return true } catch { return false }
    }

    /// ~/.config/boring-notch, only when it is a link to ~/.config/aris (a real folder of that name is left alone).
    private static func removeOldLink(_ places: Places) -> Bool {
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: places.oldLink.path) else { return true }
        let resolved = URL(fileURLWithPath: target, relativeTo: places.oldLink.deletingLastPathComponent()).standardizedFileURL.path
        let folder = places.folder.standardizedFileURL.path
        guard resolved == folder || resolved + "/" == folder || resolved == folder + "/" else { return true }
        return unlink(places.oldLink.path) == 0
    }

    // MARK: - Helpers

    /// The id an app bundle declares in its Info.plist on disk, only for a bundle whose program is Aris's ("Aris"), as
    /// ArisOrigin reads the bundle; nil for anything else, a link, or a file that can't be read.
    /// Never `Bundle(url:)`: Foundation hands back the one bundle object it keeps per path, and inside aris-agent the
    /// app's bundle is the helper's own main bundle, whose id ArisHelperListing changed in memory to
    /// com.lumenjsn.aris.agent, so every uninstall was refused as "not the Aris app's bundle" (VM run 2026-11-18, D3).
    static func appBundleIdOnDisk(_ bundle: URL) -> String? {
        let plist = bundle.appendingPathComponent("Contents/Info.plist")
        guard let data = ArisNoFollow.read(plist),
              let info = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              info["CFBundleExecutable"] as? String == "Aris" else { return nil }
        return info["CFBundleIdentifier"] as? String
    }

    /// The bundle of the running app with this pid (the caller, once ArisPeer has checked it).
    static func appBundle(pid raw: Any?) -> URL? {
        guard let pid = (raw as? Int).flatMap({ Int32(exactly: $0) }) else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.bundleURL
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    /// The token and every key file's contents: what diagnostics must never show (read without following links).
    private static func knownSecrets(_ places: Places) -> [String] {
        ArisNoFollow.contents(places.folder).filter { $0 == "claude-hook-token" || $0.hasSuffix("-key") }
            .compactMap { ArisNoFollow.text(places.folder.appendingPathComponent($0)) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// The last `bytes` of a regular file, from its first whole line; nil for a link or anything unreadable.
    static func tail(_ file: URL, bytes: Int) -> String? {
        guard var data = ArisNoFollow.read(file, tail: bytes) else { return nil }
        if data.count == bytes, let newline = data.firstIndex(of: 0x0A) { data = data[data.index(after: newline)...] }
        return String(decoding: data, as: UTF8.self)
    }

    private static func memoryFacts(_ places: Places) -> Int { memoryStore(places)?.count() ?? 0 }

    /// The memory store in Aris's data folder (memory.md imported once), only when that is a real folder.
    private static func memoryStore(_ places: Places) -> ArisMemoryStore? {
        guard ArisNoFollow.isDirectory(places.data) else { return nil }
        let store = ArisMemoryStore.at(places.data)
        store.importBackupIfNeeded()
        return store
    }

    private static func logBytes(_ places: Places) -> Int {
        guard ArisNoFollow.isDirectory(places.data) else { return 0 }
        return [places.agentLog, places.turns].reduce(0) { total, file in
            let size = { (url: URL) in ArisNoFollow.isFile(url) ? (ArisLogRotation.size(of: url) ?? 0) : 0 }
            return total + size(file) + ArisLogRotation.generations(of: file).reduce(0) { $0 + size(places.data.appendingPathComponent($1)) }
        }
    }

    private static func ok(_ object: [String: Any]) -> Reply {
        Reply(status: 200, body: (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8))
    }

    /// A 400, with its audit line.
    private static func refuse(_ op: String, _ reason: String, _ effects: Effects) -> Reply {
        effects.audit("data: refused \(op) (\(reason))")
        return Reply(status: 400, body: Data("{}".utf8))
    }
}
