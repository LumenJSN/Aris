//
//  ArisTeammateJobs.swift
//  aris-agent
//
//  How a teammate's job runs (every brain, the user 2026-11-07): on the brain the owner picked for it, behind the same gates
//  main Aris has on that brain, limited to its scopes. A job whose prompt came from a model or outside content
//  (untrusted) keeps that brain but is handled the way main Aris handles outside text there: Codex with its web search
//  off and every action through the risk gate; the open Claude with its turn gate marked from the start (every read and
//  web call judged, nothing outbound, the ungated list refused); the API brain gated as ever; Antigravity sealed (no
//  tools: it can't be watched, so outside words never reach a process that has them). The brain, scopes and
//  instructions always come from the stored teammate, never from the request. Pure.
//

import Foundation

struct ArisTeammatePlan: Equatable {
    let brain: ArisBrain
    /// Codex's own web search (off for an untrusted job, or without the `web` scope).
    let webSearch: Bool
    /// The sealed process (agy's, for an untrusted job).
    let sealed: Bool
}

enum ArisTeammateJobs {
    static func plan(brain: ArisBrain, untrusted: Bool, scopes: Set<ArisTeammateScope>) -> ArisTeammatePlan {
        let web = scopes.contains(.web) && !untrusted
        // agy has no per-call gate and can't be watched: limited scopes (or outside words) run it sealed, words only.
        return ArisTeammatePlan(brain: brain, webSearch: web, sealed: brain == .antigravity && (untrusted || !ArisTeammateScope.isAll(scopes)))
    }

    /// The stored teammate a job names (never Claude Code: it opens in a terminal), from `list`.
    static func teammate(_ id: Any?, in list: [ArisTeammate]) -> ArisTeammate? {
        guard let id = id as? String, id != ArisTeammate.claudeCodeId else { return nil }
        return list.first { $0.id == id }
    }

    /// A job naming a teammate that isn't in `list` (removed while its job waited, or a list that couldn't be read): it
    /// is refused, never run as main Aris without the teammate's scopes (bug hunt 2026-11-08, F1). No teammate named
    /// (main Aris, a helper) or Claude Code is not missing.
    static func missing(_ id: Any?, in list: [ArisTeammate]) -> Bool {
        guard let id else { return false }
        guard let named = id as? String, !named.isEmpty else { return true }
        return named != ArisTeammate.claudeCodeId && !list.contains { $0.id == named }
    }

    /// How a scheduled job runs (N5): one filed under a teammate runs with that stored teammate's scopes; one for no
    /// teammate (or Claude Code, which opens in a terminal) as Aris; one for a teammate no longer stored is refused.
    enum Scheduled: Equatable {
        case aris
        case teammate(ArisTeammate)
        case missing
    }

    static func scheduled(_ id: String?, in list: [ArisTeammate]) -> Scheduled {
        if missing(id, in: list) { return .missing }
        return teammate(id, in: list).map(Scheduled.teammate) ?? .aris
    }

    /// The brain a teammate's job asks for: its own (the request's is ignored); one that isn't a brain falls back to Codex.
    static func brain(of teammate: ArisTeammate) -> ArisBrain {
        ArisBrain.allCases.first { $0.rawValue == teammate.brain } ?? .codex
    }
}
