//
//  ArisJobLedger.swift
//  Aris
//
//  The jobs still under way, kept on disk (audit team-2: jobs lived only in memory, so a quit, a crash or a relaunch
//  dropped them without a word, and the 기록 entry kept "맡겼어요" for good). The agent ends a job's AI when the app's
//  process is gone, and a job half done is never run a second time by itself (it may already have sent or changed
//  something). So the next launch says what was lost: each job is in the done chip and its 기록 entry as cut off, and
//  Aris says it once. A Claude Code job is a terminal window of its own that outlives the app: its line says to look
//  there. Only the id, the name the user's words gave it and who had it are saved, never the prompt. Foundation only.
//

import Foundation
import os

/// One unfinished job as it is saved.
struct ArisJobRecord: Codable, Equatable {
    let id: UUID
    let title: String
    /// It runs in a Claude Code terminal window (which keeps going without the app).
    let claudeCode: Bool
    let created: Date
}

enum ArisJobLedger {
    /// The jobs not finished yet, oldest first.
    static func unfinished(_ jobs: [ArisJob]) -> [ArisJobRecord] {
        jobs.compactMap { job in
            switch job.state {
            case .queued, .running, .awaitingApproval:
                return ArisJobRecord(id: job.id, title: job.title, claudeCode: job.assignee == .teammate(ArisTeammate.claudeCodeId), created: job.created)
            case .done, .failed, .cancelled:
                return nil
            }
        }
    }

    /// What became of a job the app lost when it stopped: in the done chip's tray and the 기록 entry.
    static func lostLine(_ record: ArisJobRecord, korean: Bool) -> String {
        if record.claudeCode {
            return korean ? "Aris가 다시 시작되어 이 일을 더 지켜보지 못했어요. Claude Code는 터미널에서 계속하고 있을 수 있으니 거기서 확인해 주세요."
                : "Aris restarted and stopped watching this job. Claude Code may still be working in its terminal window: check there."
        }
        return korean ? "Aris가 다시 시작되면서 끊겼어요. 끝내지 못했으니 다시 맡겨 주세요."
            : "Cut off when Aris restarted. It wasn't finished: hand it over again."
    }

    /// Said once after a relaunch, for every job lost with it.
    static func lostSaid(_ records: [ArisJobRecord], korean: Bool) -> String {
        guard let first = records.first else { return "" }
        if records.count == 1 {
            if first.claudeCode {
                return korean ? "Aris가 다시 시작되어 ‘\(first.title)’ 일을 더 지켜보지 못했어요. Claude Code 터미널에서 확인해 주세요."
                    : "Aris restarted and stopped watching ‘\(first.title)’. Check the Claude Code terminal window."
            }
            return korean ? "Aris가 다시 시작되면서 ‘\(first.title)’ 일이 끊겼어요. 다시 맡겨 주세요."
                : "‘\(first.title)’ was cut off when Aris restarted. Hand it over again."
        }
        return korean ? "Aris가 다시 시작되면서 맡긴 일 \(records.count)개가 끊겼어요. 기록에서 확인하고 다시 맡겨 주세요."
            : "\(records.count) jobs were cut off when Aris restarted. They are in the history: hand them over again."
    }

    /// The title the notch opens on for that line.
    static func lostTitle(_ records: [ArisJobRecord], korean: Bool) -> String {
        records.count == 1 ? records[0].title : korean ? "끊긴 일 \(records.count)개" : "\(records.count) jobs cut off"
    }

    /// The lost jobs as the done chip shows them: failed, with what happened.
    static func lostJobs(_ records: [ArisJobRecord], korean: (String) -> Bool) -> [ArisJob] {
        records.map { record in
            ArisJob(id: record.id, title: record.title, prompt: "", assignee: record.claudeCode ? .teammate(ArisTeammate.claudeCodeId) : .clone,
                    cwd: nil, appHint: nil, target: .notch, state: .failed(lostLine(record, korean: korean(record.title))), created: record.created)
        }
    }

    // MARK: - The file

    /// Next to the history, in the app's own Application Support.
    static var file: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("Aris/jobs.json")
    }

    /// What was last written, so a job's every status line doesn't rewrite the file.
    nonisolated(unsafe) private static var written: [ArisJobRecord]?

    /// Saves the unfinished jobs when they changed (a job began, finished, failed or was cancelled).
    static func note(_ jobs: [ArisJob], to file: URL? = ArisJobLedger.file) {
        let records = unfinished(jobs)
        guard records != written else { return }
        written = records
        save(records, to: file)
    }

    static func load(from file: URL? = ArisJobLedger.file) -> [ArisJobRecord] {
        guard let file, let data = try? Data(contentsOf: file) else { return [] }
        return (try? JSONDecoder().decode([ArisJobRecord].self, from: data)) ?? []
    }

    static func save(_ records: [ArisJobRecord], to file: URL? = ArisJobLedger.file) {
        guard let file else { return }
        do {
            if records.isEmpty {
                // Nothing under way: no file, so a launch has nothing to report.
                if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
                return
            }
            let data = try JSONEncoder().encode(records)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch {
            Logger(subsystem: "com.lumenjsn.aris", category: "files").error("jobs: couldn't save: \(error.localizedDescription, privacy: .public)")
        }
    }
}
