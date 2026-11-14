//
//  ArisController+Inbox.swift
//  Aris
//
//  Scheduled work runs in aris-agent, whether or not the app is open; what it produced waits in the agent's inbox.
//  The app fetches it at launch and whenever the agent nudges (com.lumenjsn.aris.inbox): results come up on a card
//  under the notch (and are said) when Aris is free, and a parked question is asked when the user is at the Mac (only if
//  the agent still waits for it). Each item is acknowledged once it has been delivered, so one the app couldn't show
//  (it quit first) comes back next launch.
//  A question the user's turn covered, or nobody answered, waits in 확인 대기 (ArisController+CardPark): it is never sent as
//  his no, and it is acknowledged only once he answered or the agent stopped waiting for it.
//

import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "inbox")

extension ArisController {
    static let inboxNotification = "com.lumenjsn.aris.inbox"

    /// At launch: what waited while the app was closed, then every nudge.
    func watchInbox() {
        DistributedNotificationCenter.default().addObserver(forName: .init(Self.inboxNotification), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.deliverInbox() }
        }
        deliverInbox()
    }

    /// One delivery at a time; a nudge during one fetches again when it ends.
    func deliverInbox() {
        guard inboxDelivery == nil else {
            inboxAgain = true
            return
        }
        inboxDelivery = Task { [weak self] in
            repeat {
                self?.inboxAgain = false
                await self?.deliverInboxOnce()
            } while self?.inboxAgain == true && !Task.isCancelled
            self?.inboxDelivery = nil
        }
    }

    private func deliverInboxOnce() async {
        guard let items = await ArisAgentClient.inbox(), !items.isEmpty else { return }
        log.notice("inbox: \(items.count, privacy: .public) item(s)")
        for item in items {
            guard !Task.isCancelled else { return }
            if let ask = item.confirmation {
                // Asked by a task of its own, so a question nobody answers (it waits in 확인 대기) never holds up the
                // results after it. It is acknowledged there, once settled.
                askParked(item, ask)
                continue
            }
            guard await say(item) else { return }
            await ArisAgentClient.acknowledge([item.id])
        }
    }

    /// A scheduled job's parked question, if the agent still waits for it: asked at a pause, kept in 확인 대기 when
    /// The user's turn covers it or nobody answers (never sent as their no), and acknowledged once they answered or the agent
    /// stopped waiting. One the agent refused, or couldn't be asked about, stays in the inbox to be asked again.
    private func askParked(_ item: ArisInboxItem, _ ask: ArisConfirmation) {
        let desk = ArisCardDesk.shared
        guard desk.beginInbox(item.id) else { return }
        Task { [weak self] in
            defer { desk.endInbox(item.id) }
            guard let self else { return }
            switch await self.settleCard(ask, title: item.title, job: nil, handsFree: false, streamEnded: { false }) {
            case .answered(let result):
                if result == .refused { log.error("inbox: an answer was refused") }
                if result.acknowledges { await ArisAgentClient.acknowledge([item.id]) }
            case .gone:
                await ArisAgentClient.acknowledge([item.id])
            case .unreachable:
                // The agent didn't say whether it still waits: the question stays in the inbox and is fetched again.
                try? await Task.sleep(for: .seconds(30))
                desk.endInbox(item.id)
                self.deliverInbox()
            case .cancelled:
                break
            }
        }
    }

    /// Puts a result, failure or note on a card at the next pause, in its turn, and says it once when Aris may speak;
    /// false when the delivery was cancelled first (it waits for the next delivery).
    private func say(_ item: ArisInboxItem) async -> Bool {
        guard !item.spoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
        // Shown and said like any answer: no code or data block, nothing read aloud as code (ArisSpeakable).
        let report = ArisSpeakable.report(item.spoken, korean: ArisSpeech.language(of: item.title) == "ko-KR")
        let said = report.spoken
        let card = ArisNoticeRoute.inbox(kind: item.kind, title: item.title, shown: report.shown, file: item.file, english: ArisUIWords.english)
        let shown = await notify(card, saying: said, parking: report.shown) { self.flashTaskDone() }
        guard shown else {
            inboxAgain = true
            return false
        }
        // Recorded once it was shown, so a retried result isn't in the history twice.
        if item.kind == "result" {
            remember(ArisHistory.jobEntry(title: item.title, shown: report.shown, file: item.file, date: item.date))
            // A scheduled job's long rest opens in Aris's reader, as a handed-out job's does.
            if let file = item.file { ArisBoard.shared.read(file: file) }
            // A scheduled job's answer in the context is outside text: the conversation dispatches nothing after it.
            outsideConversation = true
            history = ArisContext.remembering(ArisContext.Turn(heard: item.title, reply: report.shown), after: history)
        }
        return true
    }
}
