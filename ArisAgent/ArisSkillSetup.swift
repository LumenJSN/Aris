//
//  ArisSkillSetup.swift
//  aris-agent
//
//  The skills feature's one-time setup (the owner, 2026-11-06: off by default; the first yes installs it): a pinned Python
//  3.12 and NVIDIA SkillSpector in ~/Library/Application Support/Aris/skills-runtime/, nowhere else. Its states are
//  what the settings chat and the notch draw: nothing yet, installing (a step and megabytes), ready, or failed (why,
//  and how far it got; 다시 시도 starts over). Turning skills off or uninstalling removes the folder. The installer is
//  handed in, so the tests drive the machine with a fake one.
//

import Foundation

struct ArisSkillSetupProgress: Equatable {
    /// What is happening ("SkillSpector 설치 중").
    let step: String
    let doneMB: Int
    let totalMB: Int
}

enum ArisSkillSetupState: Equatable {
    case absent
    case installing(ArisSkillSetupProgress)
    case ready
    case failed(message: String, doneMB: Int, totalMB: Int)

    var json: [String: Any] {
        switch self {
        case .absent: return ["state": "absent"]
        case .ready: return ["state": "ready"]
        case .installing(let progress): return ["state": "installing", "step": progress.step, "doneMB": progress.doneMB, "totalMB": progress.totalMB]
        case .failed(let message, let done, let total): return ["state": "failed", "message": message, "doneMB": done, "totalMB": total]
        }
    }
}

protocol ArisSkillInstalling: AnyObject {
    /// Installs everything into `folder` (which exists and is empty). `progress` as it goes; `cancelled` is checked
    /// between steps. The error is the user's words.
    func install(into folder: URL, progress: @escaping (ArisSkillSetupProgress) -> Void, cancelled: @escaping () -> Bool) -> Result<Void, ArisSkillWhy>
    /// Whether `folder` holds a finished install of exactly the pinned versions.
    func isInstalled(_ folder: URL) -> Bool
    /// Whether the installed runtime is still byte for byte what was installed (its hash manifest: security review I6).
    func verify(_ folder: URL) -> Bool
}

enum ArisSkillRuntimeFiles {
    /// Gives the owner write access back under `folder` (the installed runtime is read-only), so it can be removed.
    static func makeWritable(_ folder: URL) {
        _ = chmod(folder.path, 0o700)
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil, options: []) else { return }
        for case let url as URL in walker {
            var info = stat()
            guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT != S_IFLNK else { continue }
            _ = chmod(url.path, (info.st_mode & 0o777) | 0o200)
        }
    }

    /// Removes the runtime even though it's read-only.
    static func remove(_ folder: URL) {
        makeWritable(folder)
        try? FileManager.default.removeItem(at: folder)
    }
}

final class ArisSkillSetup: @unchecked Sendable {
    let folder: URL
    private let installer: ArisSkillInstalling
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var current: ArisSkillSetupState
    private var generation = 0
    /// Told on every change (the agent nudges the app).
    var changed: (ArisSkillSetupState) -> Void = { _ in }

    init(folder: URL, installer: ArisSkillInstalling, queue: DispatchQueue = DispatchQueue(label: "com.lumenjsn.aris.skills.setup")) {
        self.folder = folder
        self.installer = installer
        self.queue = queue
        current = installer.isInstalled(folder) ? .ready : .absent
    }

    var state: ArisSkillSetupState { lock.withLock { current } }
    var isReady: Bool { state == .ready }

    private func set(_ state: ArisSkillSetupState, generation expected: Int? = nil) {
        let applied = lock.withLock { () -> Bool in
            if let expected, expected != generation { return false }
            current = state
            return true
        }
        if applied { changed(state) }
    }

    /// Starts the install unless it is under way or done (a failed one starts over from nothing). `done` once it ends.
    func start(done: ((ArisSkillSetupState) -> Void)? = nil) {
        let run = lock.withLock { () -> Int? in
            if case .installing = current { return nil }
            if current == .ready { return nil }
            generation += 1
            current = .installing(ArisSkillSetupProgress(step: "준비 중", doneMB: 0, totalMB: ArisSkillPins.downloadMB))
            return generation
        }
        guard let run else { done?(state); return }
        changed(state)
        queue.async { [self] in
            ArisSkillRuntimeFiles.remove(folder)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            } catch {
                set(.failed(message: "Aris 폴더를 만들지 못했어요.", doneMB: 0, totalMB: ArisSkillPins.downloadMB), generation: run)
                done?(state)
                return
            }
            var last = ArisSkillSetupProgress(step: "준비 중", doneMB: 0, totalMB: ArisSkillPins.downloadMB)
            let result = installer.install(into: folder, progress: { [weak self] progress in
                guard let self else { return }
                // Never backwards.
                last = ArisSkillSetupProgress(step: progress.step, doneMB: max(last.doneMB, min(progress.doneMB, progress.totalMB)), totalMB: progress.totalMB)
                self.set(.installing(last), generation: run)
            }, cancelled: { [weak self] in self?.lock.withLock { self?.generation != run } ?? true })
            switch result {
            case .success where installer.isInstalled(folder):
                set(.ready, generation: run)
            case .success:
                ArisSkillRuntimeFiles.remove(folder)
                set(.failed(message: "설치를 확인하지 못했어요. 다시 시도해 주세요.", doneMB: last.doneMB, totalMB: last.totalMB), generation: run)
            case .failure(let message):
                // Nothing half-installed is left behind.
                ArisSkillRuntimeFiles.remove(folder)
                set(.failed(message: message.message, doneMB: last.doneMB, totalMB: last.totalMB), generation: run)
            }
            done?(state)
        }
    }

    /// Stops any install and removes the runtime (skills off, or uninstall).
    func remove(done: (() -> Void)? = nil) {
        lock.withLock {
            generation += 1
            current = .absent
        }
        changed(.absent)
        queue.async { [self] in
            ArisSkillRuntimeFiles.remove(folder)
            done?()
        }
    }

    /// Before every scan: the runtime is checked against its manifest; a changed one is never used (the setup shows the
    /// failure, and 다시 시도 installs it again).
    func verify() -> Bool {
        guard isReady else { return false }
        if installer.verify(folder) { return true }
        lock.withLock {
            generation += 1
            current = .failed(message: Self.damaged, doneMB: 0, totalMB: ArisSkillPins.downloadMB)
        }
        changed(state)
        return false
    }

    static let damaged = "검사 도구가 설치 뒤에 바뀌어 있어요. 다시 시도를 눌러 새로 설치해 주세요."

    /// The runtime's tools, once ready. `basePython`: the managed interpreter itself (never the scanner's venv), from
    /// which each script run makes an ephemeral environment of its own.
    var basePython: String? {
        guard isReady, let names = try? FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("python").path),
              let dir = names.sorted().first(where: { $0.hasPrefix("cpython-\(ArisSkillPins.python)-") }) else { return nil }
        let path = folder.appendingPathComponent("python/\(dir)/bin/python3").path
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }
    var scanner: String? { isReady ? folder.appendingPathComponent("venv/bin/skillspector").path : nil }
}
