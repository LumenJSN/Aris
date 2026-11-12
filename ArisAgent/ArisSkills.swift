//
//  ArisSkills.swift
//  aris-agent
//
//  The user's skills, as the agent keeps them: the feature switch and its one-time setup, the folder in Application
//  Support (anything that appears or changes there is checked before any AI sees it), the list each brain's prompt
//  carries, `skill read` and `skill run`'s lookups, and the add jobs (ArisSkills+Add). Everything it needs from the
//  outside (the setup, the scan, the review, downloads, the inbox) is handed in, so the tests run it in a temp home.
//

import Foundation

struct ArisSkillDeps {
    var home: String
    var setup: ArisSkillSetup
    var scanner: ArisSkillStaticScanning
    var reviewer: (ArisBrain) -> ArisSkillReviewing
    var asker: ArisOneShotAsking
    var downloader: ArisSkillDownloading
    var installedBrains: () -> [ArisBrain]
    /// The app is nudged to read the status again.
    var notify: () -> Void
    /// A line for the inbox (a job that ended while nobody watched).
    var inbox: (String) -> Void
    var now: () -> Date = Date.init
    /// Where install-aris-agent.sh puts the built-in skills (skill-creator).
    var builtins: URL
}

final class ArisSkills: @unchecked Sendable {
    let deps: ArisSkillDeps
    let storeFile: URL
    let folder: URL
    let lock = NSLock()
    var jobs: [UUID: ArisSkillJob] = [:]
    var jobOrder: [UUID] = []
    /// Folders that couldn't be read as skills, with why (shown in the list).
    var problems: [String: String] = [:]
    /// (signature, fingerprint) per folder: a fingerprint is only computed again when a file's size, times, inode or device changed.
    private var prints: [String: (String, String?)] = [:]
    /// One check at a time.
    let work = DispatchQueue(label: "com.lumenjsn.aris.skills.work")

    init(_ deps: ArisSkillDeps) {
        self.deps = deps
        storeFile = ArisSkillStore.file(home: deps.home)
        folder = ArisSkillStore.skillsFolder(home: deps.home)
    }

    var state: ArisSkillState { ArisSkillStore.load(storeFile) }
    var isOn: Bool { state.enabled && deps.setup.isReady }

    // MARK: - The switch

    /// 스킬 기능 on: the setup (if it isn't there), then the built-in skills and a look at the folder. Off: the runtime goes.
    func setFeature(_ on: Bool, brain: ArisBrain?) {
        ArisSkillStore.update(storeFile) { old in
            var next = old
            next.enabled = on
            if on { next.deferred = false }
            if let brain { next.reviewBrain = brain.rawValue }
            return next
        }
        if on {
            deps.setup.start { [weak self] state in
                guard state == .ready else { return }
                self?.seedBuiltins()
                self?.sync()
                self?.deps.notify()
            }
        } else {
            deps.setup.remove { [weak self] in self?.deps.notify() }
        }
        deps.notify()
    }

    /// 나중에: Aris doesn't ask again on its own.
    func deferFeature() {
        ArisSkillStore.update(storeFile) { old in
            var next = old
            next.deferred = true
            return next
        }
        deps.notify()
    }

    /// Copies each built-in skill (skill-creator) into the folder when it isn't there, recorded as Aris's own.
    func seedBuiltins() {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: deps.builtins.path) else { return }
        for name in names.sorted() where ArisSkillFormat.isName(name) {
            let source = deps.builtins.appendingPathComponent(name)
            let target = folder.appendingPathComponent(name)
            guard !FileManager.default.fileExists(atPath: target.path), case .success(let manifest) = ArisSkillFolder.manifest(source),
                  case .success = copyFolder(source, to: target) else { continue }
            let record = ArisSkillRecord(name: manifest.name, folder: name, title: manifest.title, summary: ArisSkillPrompt.clean(manifest.description, limit: 120),
                                         source: "builtin", origin: "github.com/anthropics/skills", owner: "Anthropic", version: manifest.version,
                                         enabled: true, verdict: .safe, accepted: false, findings: [], checked: [],
                                         fingerprint: ArisSkillFolder.fingerprint(target), scannedAt: deps.now(), tested: [], addedAt: deps.now())
            ArisSkillStore.update(storeFile) { $0.with(record) }
        }
    }

    // MARK: - What brains see

    /// The skills a brain may use now: the feature on, each switched on and checked for exactly its current files.
    func listings() -> [ArisSkillListing] {
        guard isOn else { return [] }
        return usableRecords().compactMap { record in
            guard case .success(let manifest) = ArisSkillFolder.manifest(folder.appendingPathComponent(record.folder)) else { return nil }
            return ArisSkillListing(name: record.name, title: record.title, description: manifest.description)
        }
    }

    func usableRecords() -> [ArisSkillRecord] {
        state.skills.filter { $0.usable(currentFingerprint: fingerprint(of: $0.folder)) }
    }

    /// `aris-tools skill read <name> [file]`: the record (for the tag) and the fenced text, or why not.
    func read(_ name: String, file: String?) -> Result<(ArisSkillRecord, String), ArisSkillWhy> {
        guard isOn else { ArisFixTurns.shared.note(.settings(.skills)); return .failure("Skills are switched off (설정 › 스킬).") }
        guard let record = usableRecords().first(where: { $0.name == name }) else {
            return .failure("No usable skill named \(ArisSkillPrompt.clean(name, limit: 64)). See: aris-tools skill list")
        }
        let path = file ?? ArisSkillFormat.skillFile
        // Only what the check's reviewer read whole (re-review N2).
        guard record.serves(path) else { return .failure("Aris didn't check \(ArisSkillPrompt.clean(path, limit: 120)) whole, so it isn't read.") }
        switch ArisSkillFolder.readText(path, in: folder.appendingPathComponent(record.folder)) {
        case .failure(let problem): return .failure("Can't read \(ArisSkillPrompt.clean(path, limit: 120)): \(problem.message)")
        case .success(let text): return .success((record, ArisSkillPrompt.fencedRead(name: name, file: path, text: text)))
        }
    }

    /// `aris-tools skill list`.
    func listText() -> String {
        let records = usableRecords()
        var files: [String: [String]] = [:]
        for record in records {
            if case .success(let inventory) = ArisSkillFolder.inventory(folder.appendingPathComponent(record.folder)) {
                files[record.name] = inventory.files.map(\.path).filter(record.serves)
            }
        }
        return ArisSkillPrompt.list(listings(), files: files)
    }

    /// `aris-tools skill run`'s plan for a usable skill's script, or why not.
    func plan(_ name: String, script: String, arguments: [String], node: String?) -> Result<(ArisSkillRecord, ArisSkillRunPlan), ArisSkillWhy> {
        guard isOn else { ArisFixTurns.shared.note(.settings(.skills)); return .failure("Skills are switched off (설정 › 스킬).") }
        guard let record = usableRecords().first(where: { $0.name == name }) else { return .failure("No usable skill named \(ArisSkillPrompt.clean(name, limit: 64)).") }
        guard record.serves(script) else { return .failure("Aris didn't check \(ArisSkillPrompt.clean(script, limit: 120)) whole, so it doesn't run.") }
        let skillFolder = folder.appendingPathComponent(record.folder)
        switch (ArisSkillFolder.resolve(script, in: skillFolder), ArisSkillFolder.readData(script, in: skillFolder, limit: 4 * 1_048_576)) {
        case (.failure(let problem), _), (_, .failure(let problem)): return .failure(ArisSkillWhy(problem.message))
        case (.success(let resolved), .success(let content)):
            return ArisSkillScript.plan(script: script, resolved: resolved, content: content, folder: skillFolder, arguments: arguments,
                                        python: deps.setup.basePython, node: node).map { (record, $0) }
        }
    }

    // MARK: - The folder

    /// The fingerprint of Skills/<name> now (computed again only when a file's size or time changed).
    func fingerprint(of name: String) -> String? {
        let url = folder.appendingPathComponent(name)
        guard case .success(let inventory) = ArisSkillFolder.inventory(url) else { return nil }
        let signature = inventory.files.map { file -> String in
            var info = stat()
            lstat(url.appendingPathComponent(file.path).path, &info)
            // Size, both times, the inode and the device (security review I5): any rewrite or swap shows.
            return "\(file.path):\(file.size):\(info.st_mtimespec.tv_sec).\(info.st_mtimespec.tv_nsec):\(info.st_ctimespec.tv_sec).\(info.st_ctimespec.tv_nsec):\(info.st_ino):\(info.st_dev)"
        }.joined(separator: "|")
        if let known = lock.withLock({ prints[name] }), known.0 == signature { return known.1 }
        let value = ArisSkillFolder.fingerprint(url)
        lock.withLock { prints[name] = (signature, value) }
        return value
    }

    /// The skill folders there now (plain folders, not hidden ones).
    func folderNames() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { name in
            guard !name.hasPrefix(".") else { return false }
            var info = stat()
            return lstat(folder.appendingPathComponent(name).path, &info) == 0 && info.st_mode & S_IFMT == S_IFDIR
        }.sorted()
    }

    /// Matches the records to the folder: a new or changed folder is checked (a job), a removed one's record goes.
    func sync() {
        guard isOn else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let names = folderNames()
        let current = state
        var found: [String: String] = [:]
        for name in names {
            switch ArisSkillFolder.manifest(folder.appendingPathComponent(name)) {
            case .failure(let problem):
                found[name] = problem.message
                continue
            case .success(let manifest):
                if let other = current.skills.first(where: { $0.name == manifest.name && $0.folder != name }), names.contains(other.folder) {
                    found[name] = "같은 이름(\(manifest.name))의 스킬이 이미 있어요."
                    continue
                }
                let print = fingerprint(of: name)
                if let record = current.skills.first(where: { $0.folder == name }) {
                    if record.fingerprint != print && !isChecking(name) { queueRescan(name) }
                } else if !isChecking(name) {
                    // Found in the folder: off until the user switches it on in settings (security review I8).
                    let record = ArisSkillRecord(name: manifest.name, folder: name, title: manifest.title,
                                                 summary: ArisSkillPrompt.clean(manifest.description, limit: 120), source: "folder", origin: nil, owner: nil,
                                                 version: manifest.version, enabled: false, verdict: .unscanned, accepted: false, findings: [], checked: [],
                                                 fingerprint: nil, scannedAt: nil, tested: [], addedAt: deps.now())
                    ArisSkillStore.update(storeFile) { $0.with(record) }
                    queueRescan(name)
                }
            }
        }
        lock.withLock { problems = found }
        ArisSkillStore.update(storeFile) { old in
            var next = old
            next.skills.removeAll { !names.contains($0.folder) }
            return next
        }
    }

    func isChecking(_ folderName: String) -> Bool {
        lock.withLock { jobs.values.contains { $0.kind == .rescan && $0.source == folderName && $0.stage != .done } }
    }

    // MARK: - Settings

    func setEnabled(_ name: String, _ on: Bool) -> Bool {
        var found = false
        ArisSkillStore.update(storeFile) { old in
            guard var record = old.record(name) else { return old }
            found = true
            record.enabled = on
            return old.with(record)
        }
        deps.notify()
        return found
    }

    /// Removes the skill's folder and record (the user's 삭제).
    func remove(_ name: String) -> Bool {
        guard let record = state.record(name), ArisSkillFormat.isName(record.name) else { return false }
        let target = folder.appendingPathComponent(record.folder)
        if target.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL { try? FileManager.default.removeItem(at: target) }
        ArisSkillStore.update(storeFile) { $0.without(name) }
        deps.notify()
        return true
    }

    /// Copies a folder file by file (no links: the inventory refuses them), within the caps.
    func copyFolder(_ source: URL, to target: URL) -> Result<Void, ArisSkillProblem> {
        guard case .success(let inventory) = ArisSkillFolder.inventory(source) else {
            if case .failure(let problem) = ArisSkillFolder.inventory(source) { return .failure(problem) }
            return .failure(.noSkillFile)
        }
        // Finder's, git's and archivers' own files stay behind (security review I2).
        for file in inventory.files where !file.path.split(separator: "/").contains(where: { ArisSkillFolder.isIgnored(String($0)) }) {
            guard case .success(let from) = ArisSkillFolder.resolve(file.path, in: source),
                  let data = FileManager.default.contents(atPath: from.path) else { return .failure(.unreadable(file.path)) }
            let to = target.appendingPathComponent(file.path)
            try? FileManager.default.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            let executable = FileManager.default.isExecutableFile(atPath: from.path)
            guard FileManager.default.createFile(atPath: to.path, contents: data, attributes: [.posixPermissions: executable ? 0o755 : 0o644]) else {
                return .failure(.unreadable(file.path))
            }
        }
        return .success(())
    }
}
