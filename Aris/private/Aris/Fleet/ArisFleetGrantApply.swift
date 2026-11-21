//
//  ArisFleetGrantApply.swift
//  Aris
//
//  The owner said yes on a `fleet.answer` allow card: the one Claude Code permission card in the notch for that session
//  and that exact request (ArisFleetGrant's fingerprint) is allowed, as a tap on its 허용 would. A plan or a question is
//  never answered this way, and nothing is when the request changed. Foundation only (tested).
//

import Foundation

@MainActor
enum ArisFleetGrantApply {
    /// Whether a card was allowed.
    @discardableResult
    static func apply(after allow: Bool, on card: ArisConfirmation, store: ClaudeStore = .shared) -> Bool {
        guard allow, !card.stopped, let grant = card.fleetGrant,
              let approval = store.approvals.first(where: { $0.sessionId == grant.session && $0.fleetFingerprint == grant.fingerprint }),
              case .tool = approval.kind else { return false }
        store.decide(approval.id, .allow)
        return true
    }
}
