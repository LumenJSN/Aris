//
//  ArisController+TaskFollow.swift
//  Aris
//
//  Handed-out jobs followed by id (ArisTaskFollowing): what the helper says of a job whose stream is gone, and the
//  inbox items it leaves under a job's id (its result, its failure, a card it waits on), which finish that job here.
//

import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "turn")

extension ArisAgentClient {
    private static let tasksURL = URL(string: "http://127.0.0.1:23351/tasks")!

    /// What the helper knows of these jobs; nil when it didn't answer (or is too old to keep journals).
    static func tasks(_ ids: [UUID]) async -> [ArisTaskSeen]? {
        guard !ids.isEmpty, let token = ClaudeHookToken.load() else { return nil }
        var request = URLRequest(url: tasksURL, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
        request.httpBody = try? JSONSerialization.data(withJSONObject: identified(["op": "list", "jobs": ids.map(\.uuidString)]))
        guard let (data, response) = try? await ArisNoStore.session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return ArisTaskSeen.decode(data)
    }

    /// The same, asked again while the helper may be starting again (ArisTaskFollowing.attempts).
    static func tasksSoon(_ ids: [UUID]) async -> [ArisTaskSeen]? {
        for attempt in 1...ArisTaskFollowing.attempts {
            if let seen = await tasks(ids) { return seen }
            if attempt < ArisTaskFollowing.attempts { try? await Task.sleep(for: ArisTaskFollowing.spacing) }
        }
        return nil
    }
}

extension ArisController {
    /// A job's stream ended without its end: when the helper still has the job (it took it back after a restart, or it
    /// simply goes on), its row says so and its end comes through the inbox. True then.
    func followsAfterLoss(_ job: ArisJob) async -> Bool {
        guard let seen = await ArisAgentClient.tasksSoon([job.id])?.first(where: { $0.job == job.id }), seen.goesOn else { return false }
        log.notice("a job's stream ended; the helper still has it (\(seen.recovered ?? "going on", privacy: .public))")
        // It waits on a card (shown before the app quit; the inbox asks it again): the row says so.
        if seen.state == .waiting, let card = seen.card {
            setState(job.id, .awaitingApproval(id: card))
            return true
        }
        let korean = ArisSpeech.language(of: job.title) == "ko-KR"
        setState(job.id, .running(step: ArisTaskFollowing.pickedUpLine(recovered: seen.recovered, korean: korean)))
        return true
    }

    /// An inbox item under a job's id: the job it finishes, if it is one this app still shows as under way. True when
    /// it was handled here (and acknowledged); false: it is said as any inbox item.
    func deliverJobItem(_ item: ArisInboxItem) async -> Bool {
        guard let id = item.jobId, let job = jobs.first(where: { $0.id == id }) else { return false }
        // A job reported once is never reported again (a second result after a restart).
        if ArisTaskFollowing.isRepeat(kind: item.kind, finished: job.isFinished) {
            log.notice("a followed job's second report was dropped")
            await ArisAgentClient.acknowledge([item.id])
            return true
        }
        guard !job.isFinished else { return false }
        switch ArisTaskFollowing.outcome(kind: item.kind, text: item.text, file: item.file) {
        case .done(let answer, let file):
            log.notice("a followed job finished")
            await reportDone(job, answer: answer, file: file)
        case .failed(let line) where ArisJobCancelLine.isCancel(line):
            setState(id, .cancelled)
            finish(id)
        case .failed(let line):
            await reportFailure(job, line)
        case .asks:
            // Its card is asked as any parked card (askParked); the row shows it waits.
            if let ask = item.confirmation { setState(id, .awaitingApproval(id: ask.id)) }
            return false
        case .other:
            return false
        }
        await ArisAgentClient.acknowledge([item.id])
        return true
    }
}
