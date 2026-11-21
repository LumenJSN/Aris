//
//  ArisWorkInProgressLive.swift
//  aris-agent
//
//  The conversation's <work> block (ArisWorkInProgress) from the task journals on disk: only the journals written in the
//  last day are opened (each one's seal chain is checked as it is read), so a turn pays for a few small files, never
//  the week's. Also what `aris-tools task` looks up a job by.
//

import Foundation

enum ArisWorkInProgressLive {
    /// The tasks whose journals were written in the last day, newest first.
    static func states(home: String, now: Date = Date()) -> [ArisTaskState] {
        let folder = ArisTaskJournal.folder(home: home)
        guard ArisPrivateFile.isRealFolder(folder),
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
        let recent = names.compactMap { name -> String? in
            guard name.hasSuffix(".jsonl") else { return nil }
            let id = String(name.dropLast(6))
            guard UUID(uuidString: id) != nil else { return nil }
            let path = folder.appendingPathComponent(name).path
            guard let modified = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date,
                  now.timeIntervalSince(modified) <= ArisWorkInProgress.staleOpen else { return nil }
            return id
        }
        return recent.compactMap { ArisTaskJournal.state(job: $0, home: home) }.sorted { $0.touched > $1.touched }
    }

    /// The block for a conversation turn (nil for a background task's own turn, or when there is nothing to say).
    static func block(task: Bool, home: String) -> String? {
        guard !task else { return nil }
        return ArisWorkInProgress.block(states(home: home), now: Date())
    }
}
