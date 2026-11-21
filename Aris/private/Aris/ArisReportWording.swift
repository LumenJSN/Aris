//
//  ArisReportWording.swift
//  Aris
//
//  A finished job's spoken line: the conversation brain's worded one (ArisController+Report) or the job's own.
//

import Foundation

/// How long the app waits for the worded line, and which line it says. Foundation only.
enum ArisReportWording {
    /// A little over the helper's own 12 s deadline.
    static let wait: TimeInterval = 15

    /// The worded line when it came and is one a voice can say; the job's own line otherwise.
    static func said(worded: String?, own: String) -> String {
        guard let worded = worded?.trimmingCharacters(in: .whitespacesAndNewlines), !worded.isEmpty else { return own }
        return worded
    }

    /// The conversation's last turns as the one-shot reads them.
    static func recent(_ turns: [ArisContext.Turn]) -> String {
        turns.map { "user: \($0.heard)\nyou: \($0.reply)" }.joined(separator: "\n")
    }
}
