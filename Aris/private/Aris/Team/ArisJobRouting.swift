//
//  ArisJobRouting.swift
//  Aris
//
//  Which AI a job asks for (audit team-7, imp-4; the user: no feature locked to one brain). A job whose prompt a model
//  wrote, or that comes out of a turn with outside content, is run by the agent behind a per-call gate: on the API
//  brain when that is the turn's brain, on Codex for every other brain's turn (ArisImageRouting.taskPlan in aris-agent:
//  Codex is the one whose web search can be turned off). So the job asks for the brain it will run on, and when that
//  one isn't set up on this Mac (not installed, not logged in) for the other gated brain if that is; with neither, for
//  the turn's own brain, so the job says what is missing instead of being lost to a rule. A teammate whose own brain
//  isn't set up hands its job to Aris itself, which says so. Pure.
//

import Foundation

enum ArisJobRouting {
    /// Whether `brain` is set up on this Mac as the agent last said (`ready`, by the brain's raw name). A brain it said
    /// nothing about counts as set up: the list may not be in yet, and the job then says itself what is missing.
    static func isReady(_ brain: ArisBrain, _ ready: [String: Bool]) -> Bool { ready[brain.rawValue] ?? true }

    /// The brain to ask for, for a job handed out untrusted (a model wrote its prompt, or its turn saw outside content),
    /// from the brain that answered the turn.
    static func brain(forDispatched parent: ArisBrain, ready: [String: Bool] = [:]) -> ArisBrain {
        // Where the agent runs such a job: the API brain's own stay on it, every other brain's on Codex.
        let gated: ArisBrain = parent == .api ? .api : .codex
        if isReady(gated, ready) { return gated }
        let other: ArisBrain = gated == .codex ? .api : .codex
        return isReady(other, ready) ? other : parent
    }

    /// A teammate (not Claude Code, which opens in a terminal) whose own brain isn't set up here: its job goes to Aris
    /// itself on the turn's brain instead of failing a moment after "맡겼어요". The specs as they run, and who fell back.
    static func withoutUnreadyTeammates(_ specs: [ArisJobSpec], brains: [String: ArisBrain], ready: [String: Bool]) -> (specs: [ArisJobSpec], fellBack: [String]) {
        var fellBack: [String] = []
        let kept = specs.map { spec -> ArisJobSpec in
            guard case .teammate(let id) = spec.assignee, id != ArisTeammate.claudeCodeId, let brain = brains[id], !isReady(brain, ready) else { return spec }
            if !fellBack.contains(id) { fellBack.append(id) }
            return ArisJobSpec(title: spec.title, prompt: spec.prompt, assignee: .clone, cwd: spec.cwd, appHint: spec.appHint)
        }
        return (kept, fellBack)
    }

    /// Said after the hand-off line when a teammate's job went to Aris: who, which brain is missing, and where to fix it.
    static func fallbackLine(name: String, brain: ArisBrain, korean: Bool) -> String {
        // The page is named as the settings window names it on this Mac.
        let place = ArisSettingsPath.path(.team), koreanPlace = ArisUIWords.english ? place : "설정의 팀원"
        return korean ? "\(name)의 \(brain.shortTitle)는 이 Mac에서 아직 쓸 수 없어서 제가 대신 해요. \(koreanPlace)에서 로그인하거나 두뇌를 바꿀 수 있어요."
            : "\(name)'s \(brain.shortTitle(english: true)) isn't set up on this Mac, so I'm doing it myself. You can log in or change its brain in \(place)."
    }
}
