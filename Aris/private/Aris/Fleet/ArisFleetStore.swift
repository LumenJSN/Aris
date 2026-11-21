//
//  ArisFleetStore.swift
//  Aris
//
//  The app's fleet (ArisFleet): every coding-agent session on this Mac, from the Claude Code hook events ArisWorld
//  hears (ArisController.watchFleet), from Claude Code's own list as the helper reads it on each fleet call (POST /aris/sessions {"op": "fleet"}),
//  and swept once a minute. It feeds the turn's fleet block (ArisFleetContext) and its news (ArisFleetNotices), which
//  goes out through the one notice path (ArisController.notify), so the interruption policy (ArisInterruption, asked
//  there each time the moment is looked at) decides when it is said. Its card takes the place of Claude Code's own
//  done/error card on the pill (the same key): one card, said once.
//

import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "fleet")

@MainActor
final class ArisFleetStore {
    static let shared = ArisFleetStore()

    private(set) var fleet = ArisFleet()
    private var book = ArisFleetNoticeBook()
    private var sweeper: Task<Void, Never>?
    private var flush: Task<Void, Never>?
    /// Who started a session (the teammate watch knows Aris's), and whose news Aris already says (set by the app).
    var isTeammate: (String) -> Bool = { _ in false }
    var finishSaid: (String) -> Bool = { _ in false }
    /// Where the news goes (the app's notify); nil in the tests, which read `book`.
    var announce: ((String, ArisFleetNotice.Kind) -> Void)?
    let home: String

    init(home: String = UserHome.path) { self.home = home }

    /// Sweeps once a minute (the hook events come in through `heard`: ArisController.watchFleet).
    func start() {
        guard sweeper == nil else { return }
        sweeper = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.sweep(now: Date())
            }
        }
        log.notice("fleet: watching")
    }

    // MARK: - What comes in

    func heard(_ event: ClaudeHookEvent, at now: Date) {
        let starter: ArisFleetStarter = isTeammate(event.sessionId) ? .arisTeammate : .user
        update(ArisFleetReducer.apply(event.fleetEvent(at: now), to: fleet, home: home, starter: starter), at: now)
    }

    /// Claude Code's own list, as the helper read it.
    func listed(_ rows: [ArisFleetListing], complete: Bool, at now: Date) {
        update(ArisFleetReducer.apply(listing: rows, complete: complete, at: now, to: fleet, home: home), at: now)
    }

    func sweep(now: Date) {
        update(ArisFleetReducer.swept(fleet, now: now), at: now)
    }

    /// The fleet with which sessions hold a card in the notch (only those can be answered from here).
    func withCards(_ approvals: [ClaudeApproval]) -> ArisFleet {
        var marked = fleet
        marked.sessions = fleet.sessions.map { session in
            var copy = session
            copy.answerable = approvals.contains { $0.sessionId == session.id && $0.fleetFingerprint == session.pending?.fingerprint }
            return copy
        }
        return marked
    }

    // MARK: - News

    private func update(_ next: ArisFleet, at now: Date) {
        let old = fleet
        fleet = next
        let quiet = Set(next.sessions.filter { isTeammate($0.id) }.map(\.id))
        let quietFinish = Set(next.sessions.filter { finishSaid($0.id) }.map(\.id))
        let news = ArisFleetNotices.news(from: old, to: next, home: home, quiet: quiet, quietFinish: quietFinish)
        book = ArisFleetNotices.noting(news, fleet: next, at: now, in: book)
        guard book.since != nil, flush == nil else { return }
        flush = Task { [weak self] in
            try? await Task.sleep(for: .seconds(ArisFleetNotices.window))
            self?.flushNews()
        }
    }

    private func flushNews() {
        flush = nil
        guard let due = ArisFleetNotices.due(book, at: Date().addingTimeInterval(1), korean: !ArisUIWords.english) else { return }
        let kind = book.pending.map(\.kind).min { Self.rank($0) < Self.rank($1) } ?? .finished
        book = due.book
        announce?(due.sentence, kind)
    }

    /// Which news leads a batch's card: a wait first, then a failure, then a finish.
    private static func rank(_ kind: ArisFleetNotice.Kind) -> Int {
        switch kind {
        case .permission, .question: return 0
        case .failed: return 1
        case .finished: return 2
        }
    }

    /// The card a batch of news goes out on: a wait asks for the owner (incoming), a failure is a problem, a finish is
    /// done. ArisNoticeRoute.want turns those into the interruption policy's kinds (teammateAsks, problem, jobDone).
    static func notice(_ sentence: String, kind: ArisFleetNotice.Kind, english: Bool) -> ArisNotice {
        let noticeKind: ArisNoticeKind
        switch kind {
        case .permission, .question: noticeKind = .incoming
        case .failed: noticeKind = .problem
        case .finished: noticeKind = .done
        }
        return ArisNotice(key: ArisNoticeRoute.claudeKey, kind: noticeKind, title: english ? "Coding sessions" : "코딩 세션", body: sentence,
                          showsFor: ArisNoticeRoute.claudeShowsFor)
    }
}
