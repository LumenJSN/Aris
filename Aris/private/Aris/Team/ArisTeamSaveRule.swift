//
//  ArisTeamSaveRule.swift
//  Aris
//
//  A teammate made or removed by voice is announced only after the agent stored the list (audit team-11: "만들었어요"
//  was said right away, and when the agent was restarting the save failed and the teammate was gone at the next
//  refresh). A save that couldn't reach the agent is tried once more a moment later; a save the agent refused is not
//  (the same list would be refused again). What Aris then says is the outcome: made or removed when it was stored,
//  else that it wasn't saved and where to try again. Pure; ArisTeamModel and ArisController+TeamMaking use it.
//

import Foundation

enum ArisTeamSaveRule {
    /// How long before the one retry: an agent that is restarting is back within a second or two.
    static let retryDelay: Duration = .milliseconds(1_500)
    static let attempts = 2

    /// Whether a save that ended this way is tried again. `unreachable`: the agent didn't answer at all.
    static func retries(unreachable: Bool, attempt: Int) -> Bool {
        unreachable && attempt < attempts
    }

    /// What the 팀원 page shows after a save that still couldn't reach the agent: the list as the agent last stored it,
    /// when that is known and no newer edit is on its way. An unsaved list left on the page looked saved, and its new
    /// teammate could be called by name until the next read took it away.
    static func shownAfterFailure(shown: [ArisTeammate], stored: [ArisTeammate]?, newerEdit: Bool) -> [ArisTeammate] {
        newerEdit ? shown : stored ?? shown
    }

    /// The page's line for that save: that nothing was saved, and whether the list was put back.
    static func failedNotice(putBack: Bool) -> String {
        putBack ? "Aris 도우미에 연결하지 못해 저장하지 못했어요. 목록은 저장돼 있던 대로 되돌렸어요. 잠시 뒤 다시 해 주세요."
            : "Aris 도우미에 연결하지 못해 저장하지 못했어요."
    }

    /// Said after 확인 on the new-teammate card (or a yes to the suggestion).
    static func madeLine(saved: Bool, name: String) -> String {
        saved ? ArisTeamCopy.made(name) : ArisTeamCopy.madeFailed
    }

    /// Said after a yes to removing a teammate.
    static func removedLine(saved: Bool, name: String) -> String {
        saved ? ArisTeamCopy.removed(name) : ArisTeamCopy.removeFailed(name)
    }
}
