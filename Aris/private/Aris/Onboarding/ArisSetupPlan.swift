//
//  ArisSetupPlan.swift
//  Aris
//
//  Which of the setup's pages one person sees (the owner's picks of 2026-11-11, qa/design-1111/PICKS.md, onboarding 2 to 4
//  and 6), decided as the setup opens so the rail's steps are the pages that will really come and a page left out
//  never makes it jump:
//   · 권한 is left out when there is nothing on it to do: every card is already on, macOS has its yes for looking at
//     the screen directly, and the install lacks nothing (a replay, a second user of the Mac's own grants).
//   · 눌러서 말하기 shows for everyone: its request is answered by the app itself, and it can be typed when Aris can't hear.
//   · AI 고르기 is left out when exactly one AI is set up (that one answers; there is nothing to pick). With none it
//     shows (a key can be pasted there), with several it shows (one is picked), and while the helper has not said
//     which are set up it shows.
//   · 아리스라고 부르기 and 받아쓰기 always show.
//  What is learned about the AIs after the setup opened (the helper answers a moment later; a key is saved on the AI
//  page) changes the plan only for pages not reached yet. Pure, so the tests walk every kind of user.
//

import Foundation

struct ArisSetupPlan: Equatable {
    /// The pages this person sees, in order.
    let pages: [ArisSetupPage]

    /// Every page (what a still picture of the window, or a test of one page, assumes).
    static let everyPage = ArisSetupPlan(pages: ArisSetupPage.allCases)

    /// `permissionsSettled`: as the setup opens, every permission card is on, macOS's yes for the direct capture is on
    /// record and the install lacks nothing. `readyAIs`: how many AIs the helper says are set up; nil while it hasn't said.
    static func make(permissionsSettled: Bool, readyAIs: Int?) -> ArisSetupPlan {
        ArisSetupPlan(pages: ArisSetupPage.allCases.filter { page in
            switch page {
            case .permissions: !permissionsSettled
            case .brain: picksAI(readyAIs: readyAIs)
            case .ask, .wake, .dictation: true
            }
        })
    }

    /// The AI page has something to decide unless exactly one AI is set up.
    static func picksAI(readyAIs: Int?) -> Bool { readyAIs != 1 }

    /// How many AIs are set up, from the helper's answer; nil until it has answered for every one of them or named
    /// at least one that is (ArisBrainChoice.noneReady: "not known yet" is never "none").
    static func readyCount(_ ready: [ArisBrain: Bool]?) -> Int? {
        guard let ready else { return nil }
        let count = ArisBrainChoice.order.filter { ready[$0] == true }.count
        return count == 0 && !ArisBrainChoice.noneReady(ready) ? nil : count
    }

    /// The same plan after the helper said something new about the AIs while `page` shows: the AI page comes or goes
    /// only while it is still ahead; once reached (or passed) the plan stays as it is.
    func learning(readyAIs: Int?, at page: ArisSetupPage) -> ArisSetupPlan {
        guard page.rawValue < ArisSetupPage.brain.rawValue else { return self }
        let wanted = Self.picksAI(readyAIs: readyAIs)
        guard wanted != pages.contains(.brain) else { return self }
        return ArisSetupPlan(pages: ArisSetupPage.allCases.filter { $0 == .brain ? wanted : pages.contains($0) })
    }

    /// The pages left out (ArisSetupFlow.next and .back step over them).
    var skipped: Set<ArisSetupPage> { Set(ArisSetupPage.allCases).subtracting(pages) }

    /// Where the window opens for a page asked for (the first, or one saved before a quit): that page when it shows,
    /// else the next one that does.
    func opening(at wanted: ArisSetupPage) -> ArisSetupPage {
        pages.first { $0.rawValue >= wanted.rawValue } ?? pages.last ?? wanted
    }

    /// VoiceOver's "Step 2 of 4": counted in the pages this person sees.
    func step(_ page: ArisSetupPage) -> (number: Int, count: Int) {
        let index = pages.firstIndex(of: page) ?? pages.filter { $0.rawValue < page.rawValue }.count
        return (min(index + 1, max(pages.count, 1)), max(pages.count, 1))
    }
}
