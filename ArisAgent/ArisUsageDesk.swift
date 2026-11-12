//
//  ArisUsageDesk.swift
//  aris-agent
//
//  The usage sources and what each last said. Every source is asked on its own, and a report waits a stated time for
//  them, then goes out with what is known and the ids still being asked: one AI that is slow, logged out or not on
//  this Mac never holds the others back (VM run 2026-11-10, bug 3: the 사용량 tab never finished loading).
//  Foundation only (tested with made-up sources).
//

import Foundation

protocol ArisUsageSource {
    var id: String { get }
    var every: TimeInterval { get }
    /// True for a source that takes seconds (it refreshes in the background; the report doesn't wait).
    var background: Bool { get }
    /// This AI's limits now; nil when it isn't on this Mac or said nothing new.
    func limits(now: Date) -> ArisUsageProvider?
}

extension ArisUsageSource {
    var background: Bool { false }
}

final class ArisUsageDesk: @unchecked Sendable {
    /// How long the command line's report (`aris-agent --usage-report`, every source) waits.
    static let waitForAll: TimeInterval = 16

    let sources: [ArisUsageSource]
    private let lock = NSLock()
    private var cached: [String: (at: Date, value: ArisUsageProvider?)] = [:]
    private var refreshing: Set<String> = []

    init(sources: [ArisUsageSource]) {
        self.sources = sources
    }

    /// What is known now. Sources that are due are asked first, each on its own; the report waits at most `wait` for
    /// them (a background source is not waited for, unless `waitForAll`) and names the ones still being asked.
    func report(now: Date, wait: TimeInterval, waitForAll: Bool = false) -> ArisUsageReport {
        let group = DispatchGroup()
        for source in sources {
            guard begin(source, now: now) else { continue }
            let work = { [self] in finish(source, with: source.limits(now: now)) }
            if source.background && !waitForAll {
                DispatchQueue.global(qos: .utility).async(execute: work)
            } else {
                DispatchQueue.global(qos: .userInitiated).async(group: group, execute: work)
            }
        }
        _ = group.wait(timeout: .now() + wait)
        return lock.withLock {
            let pending = sources.map(\.id).filter(refreshing.contains)
            return ArisUsageReport(providers: sources.compactMap { cached[$0.id]?.value }, pending: pending.isEmpty ? nil : pending)
        }
    }

    /// Whether `source` is asked now: it is due and isn't being asked already.
    private func begin(_ source: ArisUsageSource, now: Date) -> Bool {
        lock.withLock {
            let due = !refreshing.contains(source.id) && (cached[source.id].map { now.timeIntervalSince($0.at) >= source.every } ?? true)
            if due { refreshing.insert(source.id) }
            return due
        }
    }

    /// A source that said nothing new keeps what it said before.
    private func finish(_ source: ArisUsageSource, with fresh: ArisUsageProvider?) {
        lock.withLock {
            cached[source.id] = (Date(), fresh ?? cached[source.id]?.value)
            refreshing.remove(source.id)
        }
    }
}
