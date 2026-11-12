//
//  ArisSkills+Add.swift
//  aris-agent
//
//  Adding a skill, one job at a time on the skills queue: a GitHub link (fetched over https as a tarball, read by Aris
//  itself), a folder the user dragged in (copied file by file), a draft 말로 만들기 wrote, or a folder whose files changed
//  (checked again in place). Each lands in Skills/.incoming/<job> first, is checked (ArisSkillCheck), and only a safe
//  one, or a caution the user accepts, moves into Skills/<name>. A danger is deleted at once. The job keeps running when
//  the notch or the settings close; one that ends while nobody watches is said through the inbox.
//

import Foundation

extension ArisSkills {
    static let needsSetup: ArisSkillWhy = "스킬 기능이 아직 꺼져 있어요."

    var incoming: URL { folder.appendingPathComponent(".incoming", isDirectory: true) }

    // MARK: - Status (the app's POST /skills)

    func status() -> [String: Any] {
        let current = state
        let now = deps.now()
        let usable = Set(usableRecords().map(\.name))
        let checking = lock.withLock { Set(jobs.values.filter { $0.kind == .rescan && $0.stage != .done }.map(\.source)) }
        let rows: [[String: Any]] = current.skills.map { record in
            let skillFolder = folder.appendingPathComponent(record.folder)
            let inventory = (try? ArisSkillFolder.inventory(skillFolder).get())?.visibleFiles ?? []
            let manifest = try? ArisSkillFolder.manifest(skillFolder).get()
            let phase = checking.contains(record.folder) ? "checking" : usable.contains(record.name) ? "ready"
                : record.verdict == .danger ? "blocked" : record.verdict == .caution && !record.accepted ? "waiting" : record.enabled ? "changed" : "off"
            var row: [String: Any] = ["name": record.name, "title": record.title, "summary": record.summary, "source": record.source,
                                      "enabled": record.enabled, "verdict": record.verdict.rawValue, "accepted": record.accepted, "phase": phase,
                                      "description": manifest?.description ?? "",
                                      "files": inventory.map { ["path": $0.path, "size": $0.size, "kind": $0.kind.rawValue] },
                                      "findings": record.findings.map(\.json),
                                      "checked": record.checked.map(\.json),
                                      "tested": record.tested.map { ["brain": $0.brain, "model": $0.model, "ok": $0.ok, "at": $0.at.timeIntervalSince1970] }]
            for (key, value) in ["origin": record.origin, "owner": record.owner, "version": record.version] { if let value { row[key] = value } }
            return row
        }
        let list = lock.withLock { jobOrder.compactMap { jobs[$0] } }
        let brokenFolders = lock.withLock { problems }
        return ["enabled": current.enabled, "deferred": current.deferred, "setup": deps.setup.state.json, "skills": rows,
                "jobs": list.suffix(8).map { $0.json(now: now) }, "folder": folder.path,
                "problems": brokenFolders.map { ["folder": $0.key, "message": $0.value] },
                "brains": deps.installedBrains().map(\.rawValue)]
    }

    /// The app is watching these jobs (polled while its flow shows them).
    func seen(_ ids: [UUID]) {
        let now = deps.now()
        lock.withLock { for id in ids { jobs[id]?.lastSeen = now } }
    }

    func job(_ id: UUID) -> ArisSkillJob? { lock.withLock { jobs[id] } }

    private func update(_ id: UUID, _ change: (inout ArisSkillJob) -> Void) {
        lock.withLock {
            guard var job = jobs[id] else { return }
            change(&job)
            jobs[id] = job
        }
        deps.notify()
    }

    private func begin(_ job: ArisSkillJob) {
        lock.withLock {
            jobs[job.id] = job
            jobOrder.append(job.id)
            // The last 20 jobs are kept.
            while jobOrder.count > 20 { jobs[jobOrder.removeFirst()] = nil }
        }
        deps.notify()
    }

    // MARK: - Ways in

    /// A GitHub link: fetched, checked, added (or not). `hold`: stop after fetching until the user says 검사하고 추가 (proceed).
    func addLink(_ text: String, brain: ArisBrain, hold: Bool = false) -> Result<UUID, ArisSkillWhy> {
        guard isOn else { return .failure(Self.needsSetup) }
        let raw = ArisSkillLink.firstLink(in: text) ?? text
        let source: ArisGitHubSource
        switch ArisSkillLink.parse(raw) {
        case .failure(let why): return .failure(why)
        case .success(let parsed): source = parsed
        }
        let job = ArisSkillJob(kind: .link, source: source.display)
        begin(job)
        update(job.id) { $0.owner = source.owner }
        work.async { [self] in fetch(source, job: job.id, brain: brain, hold: hold) }
        return .success(job.id)
    }

    /// 검사하고 추가 for a link that waits after fetching.
    @discardableResult
    func proceed(_ id: UUID) -> Bool {
        guard let job = job(id), job.stage == .review, let staging = job.staging else { return false }
        update(id) { $0.stage = .fetching }
        work.async { [self] in check(id, at: staging, brain: job.brain ?? .claude, origin: job.origin, live: nil, livePrint: nil) }
        return true
    }

    /// A folder the user dragged into the settings (any path; copied file by file into the incoming folder).
    func addFolder(_ path: String, brain: ArisBrain) -> Result<UUID, ArisSkillWhy> {
        guard isOn else { return .failure(Self.needsSetup) }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let job = ArisSkillJob(kind: .folder, source: url.lastPathComponent)
        begin(job)
        work.async { [self] in
            let staging = incoming.appendingPathComponent(job.id.uuidString)
            switch copyFolder(url, to: staging) {
            case .failure(let problem): fail(job.id, problem.message, staging: staging)
            case .success: check(job.id, at: staging, brain: brain, origin: nil, live: nil, livePrint: nil)
            }
        }
        return .success(job.id)
    }

    /// A SKILL.md 말로 만들기 wrote (and the user kept): saved as a folder of its own, then checked like any other.
    func addDraft(_ text: String, brain: ArisBrain) -> Result<UUID, ArisSkillWhy> {
        guard isOn else { return .failure(Self.needsSetup) }
        guard case .success(let manifest) = ArisSkillFormat.parse(text) else { return .failure("초안의 SKILL.md 형식이 맞지 않아요.") }
        let job = ArisSkillJob(kind: .made, source: manifest.name)
        begin(job)
        work.async { [self] in
            let staging = incoming.appendingPathComponent(job.id.uuidString)
            try? FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            guard FileManager.default.createFile(atPath: staging.appendingPathComponent(ArisSkillFormat.skillFile).path, contents: Data(text.utf8)) else {
                return fail(job.id, "초안을 저장하지 못했어요.", staging: staging)
            }
            check(job.id, at: staging, brain: brain, origin: nil, live: nil, livePrint: nil)
        }
        return .success(job.id)
    }

    /// A folder in Skills/ that's new or changed: checked again, on a private copy in the incoming folder (never the
    /// live one: security review I7), and the result kept only if the live folder is still exactly what was copied.
    func queueRescan(_ folderName: String) {
        let job = ArisSkillJob(kind: .rescan, source: folderName)
        begin(job)
        let brain = ArisBrain.named(state.reviewBrain)
        work.async { [self] in
            let live = folder.appendingPathComponent(folderName)
            let livePrint = ArisSkillFolder.fingerprint(live)
            let copy = incoming.appendingPathComponent(job.id.uuidString)
            switch copyFolder(live, to: copy) {
            case .failure(let problem): fail(job.id, problem.message, staging: copy)
            case .success: check(job.id, at: copy, brain: brain, origin: nil, live: live, livePrint: livePrint)
            }
        }
    }

    // MARK: - The steps

    private func fetch(_ source: ArisGitHubSource, job id: UUID, brain: ArisBrain, hold: Bool) {
        if case .success(let data) = deps.downloader.fetch(ArisSkillLink.metaURL(source), maxBytes: 1_048_576, hosts: ArisSkillLink.hosts, progress: { _ in }) {
            let meta = ArisSkillLink.meta(data)
            update(id) { $0.stars = meta.stars; $0.license = meta.license; $0.pushedAt = meta.pushedAt }
        }
        let staging = incoming.appendingPathComponent(id.uuidString)
        switch deps.downloader.fetch(ArisSkillLink.tarballURL(source), maxBytes: ArisSkillLink.maxDownload, hosts: ArisSkillLink.hosts, progress: { _ in }) {
        case .failure(let why): return fail(id, why.message, staging: staging)
        case .success(let data):
            let entries: [ArisArchiveEntry]
            switch ArisSkillArchive.gunzip(data).flatMap(ArisSkillArchive.untar) {
            case .failure(let problem): return fail(id, problem.message, staging: staging)
            case .success(let all): entries = all
            }
            switch ArisSkillLink.locate(entries, path: source.path) {
            case .failure(let why): return fail(id, why.message, staging: staging)
            case .success(let files):
                guard case .success = ArisSkillArchive.write(files, to: staging) else { return fail(id, "받은 파일을 저장하지 못했어요.", staging: staging) }
                guard hold else { return check(id, at: staging, brain: brain, origin: source, live: nil, livePrint: nil) }
                switch (ArisSkillFolder.inventory(staging), ArisSkillFolder.manifest(staging)) {
                case (.success(let inventory), .success(let manifest)):
                    update(id) { job in
                        job.stage = .review
                        job.staging = staging
                        job.brain = brain
                        job.origin = source
                        job.name = manifest.name
                        job.title = manifest.title
                        job.version = manifest.version
                        job.files = inventory.visibleFiles
                    }
                case (.failure(let problem), _), (_, .failure(let problem)):
                    fail(id, problem.message, staging: staging)
                }
            }
        }
    }

    /// Inventory, manifest, the check, then the outcome. `scanned`: the private copy in the incoming folder (for a
    /// rescan, a copy of `live`, whose fingerprint was `livePrint` when it was copied).
    private func check(_ id: UUID, at scanned: URL, brain: ArisBrain, origin: ArisGitHubSource?, live: URL?, livePrint: String?) {
        guard let kind = job(id)?.kind else { return }
        let inventory: ArisSkillInventory
        switch ArisSkillFolder.inventory(scanned) {
        case .failure(let problem): return fail(id, problem.message, staging: scanned)
        case .success(let found): inventory = found
        }
        let manifest: ArisSkillManifest
        switch ArisSkillFolder.manifest(scanned) {
        case .failure(let problem): return fail(id, problem.message, staging: scanned)
        case .success(let found): manifest = found
        }
        // The files the verdict is for, taken before the check (security review I4).
        let print = ArisSkillFolder.fingerprint(scanned)
        update(id) { job in
            job.name = manifest.name
            job.title = manifest.title
            job.version = manifest.version
            job.files = inventory.visibleFiles
            job.stage = .checking
            job.stepStarted = self.deps.now()
        }
        let result = ArisSkillCheck.run(scanned, manifest: manifest, inventory: inventory, scanner: deps.scanner, reviewer: deps.reviewer(brain)) { step in
            update(id) { $0.step = step; $0.stepStarted = self.deps.now() }
        }
        guard print != nil, ArisSkillFolder.fingerprint(scanned) == print else { return fail(id, "검사하는 동안 파일이 바뀌었어요.", staging: scanned) }
        if let live {
            // A rescan counts only for the live folder as it was copied (else sync checks it again).
            let unchanged = ArisSkillFolder.fingerprint(live) == livePrint && ArisSkillFolder.fingerprint(live, skippingIgnored: true) == print
            try? FileManager.default.removeItem(at: scanned)
            guard unchanged, livePrint != nil else { return fail(id, "검사하는 동안 스킬 폴더가 바뀌어서 다시 검사해요.", staging: nil) }
        }
        let title = result.title ?? manifest.title
        update(id) { job in
            job.title = title
            job.summary = result.summary
            job.findings = result.findings
            job.checked = result.checked
        }
        // A rescan's record is the folder's (its name may have changed in SKILL.md); a live folder with none is new to
        // Aris and starts switched off (re-review N3).
        let old = live.map { found in state.skills.first { $0.folder == found.lastPathComponent } } ?? state.record(manifest.name)
        var record = old ?? ArisSkillRecord(
            name: manifest.name, folder: manifest.name, title: title, summary: result.summary ?? ArisSkillPrompt.clean(manifest.description, limit: 120),
            source: kind == .link ? "github" : kind == .made ? "made" : "folder", origin: origin?.display, owner: origin?.owner, version: manifest.version,
            enabled: true, verdict: .unscanned, accepted: false, findings: [], checked: [], fingerprint: nil, scannedAt: nil, tested: [], addedAt: deps.now())
        if let live {
            record.folder = live.lastPathComponent
            record.name = manifest.name
            if old == nil { record.enabled = false }
        } else {
            // A new copy of a skill replaces the old one: where it came from is this one's.
            record.source = kind == .link ? "github" : kind == .made ? "made" : "folder"
            record.origin = origin?.display
            record.owner = origin?.owner
        }
        record.title = title
        record.summary = result.summary ?? record.summary
        record.verdict = result.verdict
        record.findings = result.findings
        record.checked = result.checked
        record.reviewed = result.reviewed
        record.fingerprint = live == nil ? print : livePrint
        record.scannedAt = deps.now()
        record.version = manifest.version
        // The user's 그래도 추가 holds only for exactly the findings they saw, and never for a check that didn't finish (I3).
        let sameAsAccepted = old?.accepted == true && old?.acceptedFindings == result.findings
            && !result.findings.contains(where: ArisSkillCheck.incomplete.contains)
        record.accepted = live != nil && result.verdict == .caution && sameAsAccepted
        if !record.accepted { record.acceptedFindings = nil }
        switch result.verdict {
        case .safe:
            if live != nil {
                ArisSkillStore.update(storeFile) { $0.without(old?.name ?? record.name).with(record) }
            } else if case .failure(let why) = install(scanned, as: record, print: print) {
                return fail(id, why.message, staging: scanned)
            }
            finish(id, .added)
            tryAll(record.name)
        case .caution:
            if live != nil {
                ArisSkillStore.update(storeFile) { $0.without(old?.name ?? record.name).with(record) }
                return finish(id, record.accepted ? .added : .caution)
            }
            update(id) { $0.staging = scanned }
            finish(id, .caution, pending: (record, print))
        case .danger, .unscanned:
            if live != nil {
                // A skill that turned dangerous is switched off too (security review M6).
                record.enabled = false
                ArisSkillStore.update(storeFile) { $0.without(old?.name ?? record.name).with(record) }
            } else {
                try? FileManager.default.removeItem(at: scanned)
            }
            finish(id, .blocked)
        }
    }

    /// The checked incoming folder becomes Skills/<name> (an older one of that name is replaced; its switch is kept),
    /// only while its files are exactly the ones checked (`print`, before and after the move: security review I4).
    private func install(_ staging: URL, as record: ArisSkillRecord, print: String?) -> Result<Void, ArisSkillWhy> {
        guard let print, ArisSkillFolder.fingerprint(staging) == print else { return .failure("검사한 뒤에 파일이 바뀌어서 추가하지 않았어요.") }
        let target = folder.appendingPathComponent(record.name)
        var kept = record
        kept.folder = record.name
        if let old = state.record(record.name) { kept.enabled = old.enabled; kept.addedAt = old.addedAt }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: target)
        do { try FileManager.default.moveItem(at: staging, to: target) } catch { return .failure("스킬 폴더에 넣지 못했어요.") }
        guard ArisSkillFolder.fingerprint(target) == print else {
            try? FileManager.default.removeItem(at: target)
            return .failure("검사한 뒤에 파일이 바뀌어서 추가하지 않았어요.")
        }
        kept.fingerprint = print
        ArisSkillStore.update(storeFile) { $0.with(kept) }
        return .success(())
    }

    /// Records waiting for the user's 그래도 추가 (the incoming folder's), with the fingerprint they were checked at.
    private static let pendingLock = NSLock()
    nonisolated(unsafe) private static var pending: [UUID: (ArisSkillRecord, String?)] = [:]

    private func finish(_ id: UUID, _ outcome: ArisSkillJobOutcome, pending entry: (ArisSkillRecord, String?)? = nil) {
        if let entry { Self.pendingLock.withLock { Self.pending[id] = entry } }
        update(id) { job in
            job.stage = .done
            job.outcome = outcome
        }
        tellIfUnseen(id)
    }

    private func fail(_ id: UUID, _ why: String, staging: URL?) {
        if let staging { try? FileManager.default.removeItem(at: staging) }
        update(id) { job in
            job.stage = .done
            job.outcome = .failed
            job.message = why
        }
        tellIfUnseen(id)
    }

    /// A job that ended with nobody watching (the notch and settings closed) is said through the inbox. A rescan that
    /// came out safe is quiet.
    private func tellIfUnseen(_ id: UUID) {
        guard let job = job(id), deps.now().timeIntervalSince(job.lastSeen) > 5 else { return }
        // A rescan that came out safe is quiet, and so is one that couldn't finish (the folder is looked at again).
        if job.kind == .rescan && (job.outcome == .added || job.outcome == .failed) { return }
        if let line = job.inboxLine(english: ArisSkillLanguage.english) { deps.inbox(line) }
    }

    /// 그래도 추가 (`accept`) or 취소 for a caution.
    @discardableResult
    func decide(_ id: UUID, accept: Bool) -> Bool {
        guard let job = job(id) else { return false }
        if job.stage == .review {
            if accept { return proceed(id) }
            if let staging = job.staging { try? FileManager.default.removeItem(at: staging) }
            update(id) { $0.stage = .done; $0.outcome = .cancelled; $0.staging = nil }
            return true
        }
        guard job.outcome == .caution else { return false }
        let entry = Self.pendingLock.withLock { Self.pending.removeValue(forKey: id) }
        if job.kind == .rescan, let name = job.name {
            var refused = false
            ArisSkillStore.update(storeFile) { old in
                guard var stored = old.record(name) else { return old }
                // Only for the files that were checked (I4).
                if accept, stored.fingerprint != ArisSkillFolder.fingerprint(folder.appendingPathComponent(stored.folder)) { refused = true; return old }
                stored.accepted = accept
                stored.acceptedFindings = accept ? stored.findings : nil
                return old.with(stored)
            }
            if refused {
                update(id) { $0.outcome = .failed; $0.message = "검사한 뒤에 파일이 바뀌었어요. 다시 검사해요." }
                return false
            }
        } else if let staging = job.staging {
            if accept, var record = entry?.0 {
                record.accepted = true
                record.acceptedFindings = record.findings
                if case .failure(let why) = install(staging, as: record, print: entry?.1) {
                    try? FileManager.default.removeItem(at: staging)
                    update(id) { $0.outcome = .failed; $0.message = why.message; $0.staging = nil }
                    return false
                }
            } else {
                try? FileManager.default.removeItem(at: staging)
            }
        }
        update(id) { $0.outcome = accept ? .added : .cancelled; $0.staging = nil }
        if accept, let name = job.name { tryAll(name) }
        return true
    }
}
