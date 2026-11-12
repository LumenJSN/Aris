//
//  ArisSkillLive.swift
//  aris-agent
//
//  The check's live halves: SkillSpector's static scan from the skills runtime (static only: no AI provider, no keys;
//  its home, cache and temp files inside the runtime), and the AI review on the user's chosen brain, sealed with no tools
//  (ArisSealedOneShot). And the agent's one ArisSkills, wired to the real setup, downloads, inbox and app nudge.
//

import Foundation

final class ArisSkillSpectorScanner: ArisSkillStaticScanning {
    private let setup: ArisSkillSetup
    static let timeout: TimeInterval = 600

    init(setup: ArisSkillSetup) { self.setup = setup }

    func scan(_ folder: URL) -> ArisSkillStaticReport? {
        // A runtime changed since it was installed is never run (the setup turns to 다시 시도).
        guard let tool = setup.scanner, setup.verify() else { return nil }
        let runtime = setup.folder
        let work = runtime.appendingPathComponent("tmp/scan-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: work) }
        let real = ArisSkillSandbox.real(work.path)
        let report = URL(fileURLWithPath: real).appendingPathComponent("report.json")
        var environment = ArisSkillInstaller.environment(runtime)
        environment["HOME"] = real
        environment["TMPDIR"] = real
        environment["SKILLSPECTOR_LOG_LEVEL"] = "ERROR"
        let arguments = ArisSkillSandbox.arguments(profile: ArisSkillSandbox.scanProfile,
                                                   parameters: ArisSkillSandbox.scanParameters(runtime: runtime.path, target: folder.path, work: real))
            + [tool, "scan", ArisSkillSandbox.real(folder.path), "--no-llm", "--format", "json", "--output", report.path]
        let result = ArisSkillProcess.run(ArisSkillSandbox.tool, arguments, environment: environment, directory: real, timeout: Self.timeout)
        guard !result.timedOut, let data = FileManager.default.contents(atPath: report.path) else { return nil }
        return ArisSkillStaticReport.parse(data)
    }
}

final class ArisSkillAIReviewer: ArisSkillReviewing {
    private let asker: ArisOneShotAsking
    private let brain: ArisBrain
    static let timeout: TimeInterval = 240

    init(asker: ArisOneShotAsking, brain: ArisBrain) {
        self.asker = asker
        self.brain = brain
    }

    func review(input: String, manifest: ArisSkillManifest) -> ArisSkillReview? {
        // The brain the owner chose; only when it can't run at all, the next available one (security review M1: an answer
        // that doesn't parse is a caution, never a reason to ask someone else).
        let order = [brain] + [ArisBrain.claude, .codex, .api, .antigravity].filter { $0 != brain }
        for candidate in order where ArisSealedOneShot.available(candidate) {
            guard let answer = asker.ask(candidate, instruction: ArisSkillCheck.instruction(english: ArisSkillLanguage.english), input: input, timeout: Self.timeout) else { continue }
            return ArisSkillReview.parse(answer)
        }
        return nil
    }
}

extension ArisSkills {
    static let notification = "com.lumenjsn.aris.skills"

    /// The agent's skills, made once.
    static let live: ArisSkills = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let setup = ArisSkillSetup(folder: ArisSkillStore.runtimeFolder(home: home), installer: ArisSkillInstaller())
        let asker = ArisSealedOneShot(environment: ArisAgentRunner.environment())
        let skills = ArisSkills(ArisSkillDeps(
            home: home, setup: setup, scanner: ArisSkillSpectorScanner(setup: setup),
            reviewer: { ArisSkillAIReviewer(asker: asker, brain: $0) }, asker: asker, downloader: ArisSkillDownloader(),
            installedBrains: { ArisBrain.allCases.filter(ArisSealedOneShot.available) },
            notify: { ArisSkills.nudge() },
            inbox: { line in
                let file = ArisInbox.file(home: home)
                ArisInbox.append(ArisInboxEntry(id: UUID(), date: Date(), kind: .note, schedule: nil, title: ArisSkillJob.inboxTitle(english: ArisSkillLanguage.english), text: line, file: nil, confirm: nil), file: file)
                DistributedNotificationCenter.default().postNotificationName(.init(ArisScheduler.notification), object: nil, userInfo: nil,
                                                                             deliverImmediately: true)
            },
            builtins: ArisAppBundle.skillsFolder(home: home).appendingPathComponent("builtin", isDirectory: true)))
        setup.changed = { _ in ArisSkills.nudge() }
        return skills
    }()

    /// Tells the app to read the status again (coalesced: at most every 0.3 s).
    static func nudge() {
        nudgeLock.withLock {
            guard !nudgePending else { return }
            nudgePending = true
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
                nudgeLock.withLock { nudgePending = false }
                DistributedNotificationCenter.default().postNotificationName(.init(notification), object: nil, userInfo: nil, deliverImmediately: true)
            }
        }
    }

    private static let nudgeLock = NSLock()
    nonisolated(unsafe) private static var nudgePending = false

    /// At the agent's start, and every minute: the folder is looked at again (new or changed skills are checked).
    func watch() {
        // What an earlier run fetched and nobody decided on is gone (a job lives only as long as the agent).
        try? FileManager.default.removeItem(at: incoming)
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 5, repeating: 60)
        timer.setEventHandler { [weak self] in self?.sync() }
        timer.resume()
        Self.timers.append(timer)
    }

    nonisolated(unsafe) private static var timers: [DispatchSourceTimer] = []
}
