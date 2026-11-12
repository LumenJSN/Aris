//
//  ArisNoteRow.swift
//  Aris
//
//  A note (a teammate's 기억, or 앱 노하우) as the 팀원 page shows it, read from aris-agent's answer (ArisTeamExtrasRoute).
//

import Foundation

/// A note as the page shows it.
struct ArisNoteRow: Identifiable, Equatable, Sendable {
    let id: String
    let text: String
    let app: String?
    let date: Date?
    /// The user's own (written by hand, or asked for on a clean job), or learned on a job.
    let fromUser: Bool
    /// Learned on a turn that had read outside content (an app's window, a page, mail).
    let tainted: Bool
    let by: String?
    /// The user kept it (a tainted note is read by turns only then).
    var kept = false

    /// Learned from outside content and not kept yet: shown as 확인 필요 with 유지 and ✕.
    var needsReview: Bool { tainted && !kept }
}

extension ArisNoteRow {
    /// The agent's {"notes": [...]}; rows that can't be read are skipped.
    static func list(from data: Data) -> [ArisNoteRow]? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let rows = root["notes"] as? [[String: Any]] else { return nil }
        let dates = ISO8601DateFormatter()
        return rows.compactMap { row in
            guard let id = row["id"] as? String, let text = row["text"] as? String else { return nil }
            return ArisNoteRow(id: id, text: text, app: row["app"] as? String, date: (row["date"] as? String).flatMap(dates.date(from:)),
                               fromUser: row["source"] as? String == "user", tainted: row["tainted"] as? Bool ?? true, by: row["by"] as? String,
                               kept: row["kept"] as? Bool ?? false)
        }
    }
}
