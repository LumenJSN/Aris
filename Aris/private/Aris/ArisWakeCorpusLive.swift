//
//  ArisWakeCorpusLive.swift
//  Aris
//
//  The one owner of the wake corpus on disk (ArisWakeCorpusStore) while the app runs: the recording sheet and
//  하루 소리 모으기 both write through it, one at a time on its own queue, so the manifest never loses an entry. And
//  what Settings › 대화 › 호출어 녹음 shows of it (ArisWakeRecordLive): how much is recorded, whether collecting is on
//  and for how long, 다 지우기 asked twice.
//

import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "wake-record")

final class ArisWakeCorpusLive: @unchecked Sendable {
    static let shared = ArisWakeCorpusLive()

    private let queue = DispatchQueue(label: "com.lumenjsn.aris.wake-corpus", qos: .utility)
    private let store = ArisWakeCorpusStore.standard
    /// On `queue`; read from disk on first use.
    private var manifest: ArisWakeManifest?
    /// On `queue`: listened seconds not yet written (written with the next clip, or every five minutes of them).
    private var unwritten: Double = 0

    private func current() -> ArisWakeManifest {
        if let manifest { return manifest }
        let loaded = store?.load() ?? ArisWakeManifest()
        manifest = loaded
        return loaded
    }

    /// Saves one clip and lists it; `done` on the main thread with whether it was written.
    func save(_ samples: [Float], as entry: ArisWakeManifest.Entry, done: (@MainActor (Bool) -> Void)? = nil) {
        queue.async { [self] in
            var ok = false
            if let store {
                do {
                    manifest = try store.save(samples, as: entry, into: current().listening(unwritten))
                    unwritten = 0
                    ok = true
                } catch {
                    log.error("wake corpus: couldn't save a clip: \(String(describing: error), privacy: .public)")
                }
            }
            Task { @MainActor in
                done?(ok)
                ArisWakeRecordLive.shared.refresh()
            }
        }
    }

    /// Sets an ambient candidate's outcome once its check has ended.
    func note(outcome: String, for file: String) {
        queue.async { [self] in
            let now = current()
            guard let store, var entry = now.entries.first(where: { $0.file == file }) else { return }
            entry.outcome = outcome
            manifest = now.adding(entry)
            try? store.write(manifest ?? now)
        }
    }

    /// Adds listened time (하루 소리 모으기's hours); the manifest is rewritten only every five minutes of it.
    func listened(_ seconds: Double) {
        guard seconds > 0 else { return }
        queue.async { [self] in
            unwritten += seconds
            guard let store, unwritten >= 300 else { return }
            manifest = current().listening(unwritten)
            unwritten = 0
            try? store.write(manifest ?? ArisWakeManifest())
        }
    }

    /// Everything, gone: the folder with every clip and the manifest.
    func removeAll(done: @escaping @MainActor (Bool) -> Void) {
        queue.async { [self] in
            var ok = true
            do { try store?.removeAll() } catch {
                ok = false
                log.error("wake corpus: couldn't delete: \(String(describing: error), privacy: .public)")
            }
            manifest = ArisWakeManifest()
            unwritten = 0
            Task { @MainActor in
                done(ok)
                ArisWakeRecordLive.shared.refresh()
            }
        }
    }

    /// The manifest and the clips' bytes, read on the queue (main thread).
    func read(_ done: @escaping @MainActor (ArisWakeManifest, Int) -> Void) {
        queue.async { [self] in
            let now = current(), bytes = store?.bytes(now) ?? 0
            Task { @MainActor in done(now, bytes) }
        }
    }
}

/// Settings › 대화 › 호출어 녹음's state.
@MainActor
final class ArisWakeRecordLive: ObservableObject {
    static let shared = ArisWakeRecordLive()

    @Published private(set) var summary = ArisWakeRecordSummary(total: ArisWakeScript.totalTakes)
    @Published private(set) var recordedTakes: Set<String> = []
    private var clearTimer: Task<Void, Never>?

    private init() {
        refresh()
    }

    /// 하루 소리 모으기 is on now (and still inside its day; past it, it turns itself off here).
    var collecting: Bool {
        let defaults = UserDefaults.standard
        let since = defaults.object(forKey: ArisWakeCollect.sinceKey) as? Double
        let on = ArisWakeCollect.isOn(setting: defaults.bool(forKey: ArisWakeCollect.key), since: since, now: Date().timeIntervalSince1970)
        if !on, defaults.bool(forKey: ArisWakeCollect.key) {
            defaults.set(false, forKey: ArisWakeCollect.key)
            defaults.removeObject(forKey: ArisWakeCollect.sinceKey)
            log.notice("collecting a day of sound: its day is over, off")
        }
        return on
    }

    func setCollecting(_ on: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(on, forKey: ArisWakeCollect.key)
        if on { defaults.set(Date().timeIntervalSince1970, forKey: ArisWakeCollect.sinceKey) } else { defaults.removeObject(forKey: ArisWakeCollect.sinceKey) }
        log.notice("collecting a day of sound: \(on ? "on" : "off", privacy: .public)")
        refresh()
    }

    func refresh() {
        let on = collecting
        let since = UserDefaults.standard.object(forKey: ArisWakeCollect.sinceKey) as? Double
        ArisWakeCorpusLive.shared.read { [weak self] manifest, bytes in
            guard let self else { return }
            var next = self.summary
            next.takes = manifest.recordedTakes.count
            next.total = ArisWakeScript.totalTakes
            next.ambient = manifest.count([.ambientSpeech, .ambientCandidate])
            next.bytes = bytes
            next.collecting = on
            next.hoursLeft = ArisWakeCollect.hoursLeft(since: since, now: Date().timeIntervalSince1970)
            if next != self.summary { self.summary = next }
            if manifest.recordedTakes != self.recordedTakes { self.recordedTakes = manifest.recordedTakes }
        }
    }

    /// First press asks; the second (within 5 s) erases everything. True once erased.
    func clearPressed() async -> Bool {
        guard summary.confirmingClear else {
            summary.confirmingClear = true
            clearTimer?.cancel()
            clearTimer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                self?.summary.confirmingClear = false
            }
            return false
        }
        cancelClear()
        // Nothing more is collected into a folder that is being erased.
        if collecting { setCollecting(false) }
        return await withCheckedContinuation { continuation in
            ArisWakeCorpusLive.shared.removeAll { continuation.resume(returning: $0) }
        }
    }

    func cancelClear() {
        clearTimer?.cancel()
        summary.confirmingClear = false
    }
}
