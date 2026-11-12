//
//  ArisHelpers.swift
//  Aris
//
//  Temporary helpers (zero setup): when a request splits into several jobs and no teammate matches one of them, each
//  such job goes to a helper of its own instead of a copy of Aris: "도우미 1", "도우미 2", each with a default face no
//  teammate wears (never Aris's), drawn on its window while it works and gone with its job. Numbers (and so faces) run
//  on across hand-outs working at once (N14): a second one while 1 and 2 work gets 3 and 4. Nothing is stored. Pure.
//

import Foundation

enum ArisHelpers {
    /// Several jobs: each one for Aris itself becomes the next helper whose number isn't `taken` by a helper still
    /// working (one job alone stays Aris's own).
    static func assign(_ specs: [ArisJobSpec], taken: Set<Int> = []) -> [ArisJobSpec] {
        guard specs.count > 1 else { return specs }
        var used = taken
        return specs.map { spec in
            guard spec.assignee == .clone else { return spec }
            let next = (1...).first { !used.contains($0) } ?? 1
            used.insert(next)
            return ArisJobSpec(title: spec.title, prompt: spec.prompt, assignee: .helper(next), cwd: spec.cwd, appHint: spec.appHint)
        }
    }

    /// The numbers the helpers still at work hold (a finished one's is free again).
    static func taken(_ jobs: [ArisJob]) -> Set<Int> {
        Set(jobs.compactMap { job in
            guard case .helper(let index) = job.assignee else { return nil }
            switch job.state {
            case .queued, .running, .awaitingApproval: return index
            case .done, .failed, .cancelled: return nil
            }
        })
    }

    /// The first helper of a hand-out (the lowest number it gave out); nil when it has none.
    static func firstHelper(_ specs: [ArisJobSpec]) -> Int? {
        specs.compactMap { spec -> Int? in if case .helper(let index) = spec.assignee { index } else { nil } }.min()
    }

    /// Whether a finished job counts toward the offer to make a teammate (ArisTeamSuggestion): Aris's own job, and of a
    /// hand-out's helpers only the first (`firstHelper`), since they all carry the same request (bug hunt 2026-11-08, F6).
    static func countsTowardSuggestion(_ assignee: ArisJobAssignee, firstHelper: Int? = 1) -> Bool {
        switch assignee {
        case .clone: true
        case .helper(let index): index == firstHelper
        case .teammate: false
        }
    }

    /// Helper `index`'s face: the faces no teammate (nor Aris) wears first, in the picker's order, then any of them.
    static func look(_ index: Int, teammates: [ArisTeammate], aris: ArisCharacterLook) -> ArisCharacterLook {
        let pickable = ArisFace.pickableTypes(aris: aris.type)
        let used = Set(teammates.map(\.look.type))
        let free = pickable.filter { !used.contains($0) }
        let pool = free.isEmpty ? pickable : free
        let type = pool[(max(1, index) - 1) % max(1, pool.count)]
        return ArisCharacterLook(type: type, colorHex: helperColor, shading: ArisCharacterLook.standard.shading)
    }

    /// Helpers share one quiet grey, so they read as temporary next to the user's teammates.
    static let helperColor: String? = "#D5DBEA"

    static func name(_ index: Int) -> String {
        String(localized: "team.helper.name", defaultValue: "Helper \(index)", bundle: ArisTeamCopy.bundle, locale: ArisTeamCopy.locale,
               comment: "A temporary helper's name: %lld is its number")
    }
}
