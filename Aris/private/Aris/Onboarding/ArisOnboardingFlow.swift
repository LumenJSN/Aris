//
//  ArisOnboardingFlow.swift
//  Aris
//
//  Where the user is in the setup window after the intro (mockups/onboarding2/js/setup.js, perms.js), as he picked it
//  on 2026-11-11 (qa/design-1111/PICKS.md): 권한 → 눌러서 말하기 → AI 고르기 → 아리스라고 부르기 → 받아쓰기. The permissions page walks
//  three cards once (마이크, 손쉬운 사용, 화면 기록), the open one with its ask; 계속 shows once the mic and Accessibility are on,
//  or every card is decided. 눌러서 말하기 is the shortcut's practice and the first request in one (pick 4-A): holding the
//  talk key lights its keycaps and listens, and the request is answered by the app itself (a timer, pick 1-A), so it
//  shows for everyone. AI 고르기 (fresh install F2) shows which AIs are set up on this Mac and lets one be picked; 아리스라고
//  부르기 (F4) asks whether the wake word is on. Which of these one person sees, and how far along the rail is, is
//  ArisSetupPlan's. Pure: what macOS says comes in from ArisOnboardingSystem.
//
//  Also the onboarding's keys and launch rules (ArisOnboarding): 나중에 할게요, and since 2026-11-11 the window's ×, Esc
//  and the veil's ✕ too, leave it unseen so the pages left resume at a launch (at most once a day, never for a login
//  item, at most three times; the ✦ menu's 설정 안내 이어서 하기 any time); only the last page's button marks it done;
//  Quit & Reopen within 10 minutes resumes the same day.
//

import Foundation

/// A permission Aris can hold (ArisDiagnostics lists them; the onboarding asks for the first four).
enum ArisOnboardingStep: String, CaseIterable, Identifiable {
    case mic, speech, accessibility, screen, calendar, reminders, automation, fullDisk, login

    var id: Self { self }

    /// How it's granted: macOS asks in a dialog, the user turns it on in System Settings, or the user chooses.
    enum Way { case ask, settings, consent }

    var way: Way {
        switch self {
        case .accessibility, .screen, .fullDisk: .settings
        case .login: .consent
        default: .ask
        }
    }

    /// The name in the diagnostics report.
    var title: String {
        switch self {
        case .mic: "마이크"
        case .speech: "음성 인식"
        case .accessibility: ArisFix.Pane.accessibility.title(english: false)
        case .screen: "화면 기록"
        case .calendar: "캘린더"
        case .reminders: "미리 알림"
        case .automation: "자동화"
        case .fullDisk: "전체 디스크 접근"
        case .login: "로그인 시 실행"
        }
    }
}

/// What macOS says about one permission right now.
enum ArisGrant: Equatable {
    case undecided, granted, denied

    /// AEDeterminePermissionToAutomateTarget's answer: noErr, errAEEventNotPermitted (-1743); anything else is open.
    static func automation(status: Int32) -> ArisGrant {
        switch status {
        case 0: .granted
        case -1743: .denied
        default: .undecided
        }
    }
}

/// The setup window's pages in order, among them two questions: which AI answers, and the wake word.
/// The numbers are what a setup put off for later saved (ArisOnboarding.pageKey); 1 was the shortcut page and 3 the
/// question page before they became one.
enum ArisSetupPage: Int, CaseIterable, Equatable {
    case permissions = 0, ask = 1, brain = 2, wake = 4, dictation = 5

    /// A page saved before a quit (Quit & Reopen after Screen Recording); the old question page is the one page the
    /// shortcut and the question now share; anything unknown starts at 권한.
    static func resume(saved: Int) -> ArisSetupPage { saved == 3 ? .ask : ArisSetupPage(rawValue: saved) ?? .permissions }
}

/// What the talk key does while the onboarding shows (QA BUG-31: the shortcut step's ⌥Space opened a real turn, and
/// its silence became a request that played music).
enum ArisOnboardingTalk: Equatable {
    /// A real turn, as always.
    case turn
    /// 눌러서 말하기: the key listens, and what is heard is answered by the app alone (ArisOnboardingPractice): a timer,
    /// the time, the date, the calendar read; no router, no other Mac action, no AI with tools.
    case practice

    static func mode(phase: ArisOnboardingPhase, page: ArisSetupPage) -> ArisOnboardingTalk {
        guard phase == .setup else { return .turn }
        switch page {
        case .ask: return .practice
        case .permissions, .brain, .wake, .dictation: return .turn
        }
    }
}

/// One card on the permissions page.
enum ArisPermissionCard: String, CaseIterable, Equatable {
    case mic, accessibility, screen

    /// What the card asks macOS for: hearing needs the mic and on-device speech recognition (Aris's listener uses both).
    var steps: [ArisOnboardingStep] {
        switch self {
        case .mic: [.mic, .speech]
        case .accessibility: [.accessibility]
        case .screen: [.screen]
        }
    }

    var way: ArisOnboardingStep.Way { self == .mic ? .ask : .settings }
}

/// A card as the page draws it.
enum ArisCardState: Equatable {
    /// Closed, not reached yet.
    case idle
    /// Open, with 허용 and 나중에.
    case active
    /// 허용 was pressed: macOS's dialog or System Settings is up.
    case waiting
    case granted
    /// 나중에, or a no in macOS's dialog: Aris asks again the first time it needs it.
    case later
}

struct ArisSetupFlow: Equatable {
    private(set) var page: ArisSetupPage
    /// The open card.
    private(set) var active: ArisPermissionCard?
    private(set) var waiting: Set<ArisPermissionCard> = []
    private(set) var putOff: Set<ArisPermissionCard> = []
    /// The cards macOS last said are on.
    private(set) var on: Set<ArisPermissionCard> = []
    private(set) var finished = false

    init(page: ArisSetupPage = .permissions) { self.page = page }

    func state(_ card: ArisPermissionCard, granted: Bool) -> ArisCardState {
        if granted { return .granted }
        if putOff.contains(card) { return .later }
        if waiting.contains(card) { return .waiting }
        return active == card ? .active : .idle
    }

    private func decided(_ card: ArisPermissionCard, _ granted: [ArisPermissionCard: Bool]) -> Bool {
        granted[card] == true || putOff.contains(card)
    }

    func allDecided(granted: [ArisPermissionCard: Bool]) -> Bool { ArisPermissionCard.allCases.allSatisfy { decided($0, granted) } }

    /// Opens the first card not decided yet (cards already on show their check).
    mutating func begin(granted: [ArisPermissionCard: Bool]) {
        on = Set(granted.filter(\.value).keys)
        active = ArisPermissionCard.allCases.first { !decided($0, granted) }
    }

    /// 허용: macOS's dialog or System Settings is up for this card.
    mutating func ask(_ card: ArisPermissionCard) {
        waiting.insert(card)
        active = card
    }

    /// 나중에 (or a no): put off, the next card opens.
    mutating func putOff(_ card: ArisPermissionCard) {
        waiting.remove(card)
        putOff.insert(card)
        if active == card || active == nil { active = nextOpen(after: card) }
    }

    /// The live grants changed: a waiting card that's on now is done, and the next opens.
    mutating func settle(granted: [ArisPermissionCard: Bool]) {
        on = Set(granted.filter(\.value).keys)
        for card in waiting where granted[card] == true { waiting.remove(card) }
        if let open = active, granted[open] == true { active = nil }
        if active == nil { active = ArisPermissionCard.allCases.first { !decided($0, granted) && !waiting.contains($0) } }
    }

    private func nextOpen(after card: ArisPermissionCard) -> ArisPermissionCard? {
        let all = ArisPermissionCard.allCases, i = all.firstIndex(of: card) ?? 0
        return (all[(i + 1)...] + all[..<i]).first { !putOff.contains($0) && !waiting.contains($0) && !on.contains($0) && $0 != card }
    }

    /// 계속 on the permissions page: the mic and Accessibility are on, or every card is decided.
    func continueShown(granted: [ArisPermissionCard: Bool]) -> Bool {
        (granted[.mic] == true && granted[.accessibility] == true) || allDecided(granted: granted)
    }

    /// The rail: an equal share for each page this person sees (`shown`: ArisSetupPlan), so a page left out never
    /// makes it jump; on the permissions page a third of a share per decided card; on the try page the whole share
    /// once the first request is done (`tryDone`); full when finished.
    func progress(granted: [ArisPermissionCard: Bool], shown: [ArisSetupPage] = ArisSetupPage.allCases, tryDone: Bool = false) -> Double {
        if finished { return 1 }
        let pages = shown.isEmpty ? ArisSetupPage.allCases : shown
        let index = pages.firstIndex(of: page) ?? pages.filter { $0.rawValue < page.rawValue }.count
        let within: Double
        switch page {
        case .permissions: within = Double(ArisPermissionCard.allCases.filter { decided($0, granted) }.count) / Double(ArisPermissionCard.allCases.count)
        case .ask: within = tryDone ? 1 : 0
        case .brain, .wake, .dictation: within = 0
        }
        return min(1, (Double(index) + within) / Double(pages.count))
    }

    var backShown: Bool { page != .permissions }

    /// The page's own button: on to the next page that isn't left out; false (and finished) when none is left.
    @discardableResult
    mutating func next(skipping skipped: Set<ArisSetupPage> = []) -> Bool {
        guard let following = ArisSetupPage.allCases.first(where: { $0.rawValue > page.rawValue && !skipped.contains($0) }) else {
            finished = true
            return false
        }
        page = following
        return true
    }

    /// Back to the page before that isn't left out; the first page stays.
    mutating func back(skipping skipped: Set<ArisSetupPage> = []) {
        page = ArisSetupPage.allCases.last(where: { $0.rawValue < page.rawValue && !skipped.contains($0) }) ?? .permissions
    }

}

enum ArisOnboarding {
    /// Set once the onboarding has been shown (finished or closed): it doesn't show at launch again.
    static let seenKey = "arisOnboardingSeen"
    /// 나중에 할게요: the pages left come back at a launch (seen stays unset).
    static let laterKey = "arisOnboardingLater"
    /// `-arisOnboardingReplay YES` shows it at launch even when seen; settings › 처음 안내 다시 보기 opens it any time.
    static let replayKey = "arisOnboardingReplay"
    /// The setup page to resume at (Quit & Reopen after Screen Recording).
    static let pageKey = "arisOnboardingPage"
    /// What the user asked Aris to call them (ArisUserName reads it).
    static let nameKey = ArisUserName.key
    /// The onboarding's mute.
    static let mutedKey = "arisOnboardingMuted"
    static let resumeCountKey = "arisOnboardingResumes"
    static let lastResumeKey = "arisOnboardingLastResume"
    static let quitAtKey = "arisOnboardingQuitAt"
    /// Auto-resumes at launch stop after this many (an onboarding that crashes the app can't bring itself back forever).
    static let maxResumes = 3
    static let resumeSpacing: TimeInterval = 24 * 3600
    static let reopenWindow: TimeInterval = 10 * 60

    /// How it was closed: the last page's button (finished), by the user in passing (dismissed: the ×, Esc, the veil's
    /// ✕), or 나중에 할게요 and a quit mid-way (later).
    enum Close { case finished, dismissed, later }

    /// What a close comes to (the owner's ruling, 2026-11-11: the setup's × means "later", not "done for good"). Closed by
    /// the user in passing before the last page is finished, the setup is put off: it stays unseen, keeps its page,
    /// and comes back there. Only finishing the last page marks it done. A setup that was done before this showing (it
    /// is being looked at again from Settings or with the launch flag) is still done when it is closed.
    static func closing(_ reason: Close, phase: ArisOnboardingPhase, doneBefore: Bool) -> Close {
        guard reason == .dismissed else { return reason }
        return phase == .finish || doneBefore ? .finished : .later
    }

    /// The setup was finished at some earlier time and is not waiting to be continued.
    static func doneBefore(seen: Bool, later: Bool) -> Bool { seen && !later }

    /// The setup was begun and put off, and is not on screen: the ✦ menu offers the way back to it.
    static func postponed(later: Bool, showing: Bool) -> Bool { later && !showing }

    struct AfterClose: Equatable {
        let seen: Bool
        let later: Bool
    }

    /// The keys a close leaves: done only when it was finished; anything else waits to be continued.
    static func afterClose(_ close: Close) -> AfterClose {
        close == .finished ? AfterClose(seen: true, later: false) : AfterClose(seen: false, later: true)
    }

    /// The keys while it shows: in the setup window it's "later" (a quit, Quit & Reopen or a crash keep the pages
    /// left); at the finish it's done; the intro leaves them as show() set them.
    static func persisted(phase: ArisOnboardingPhase) -> AfterClose? {
        switch phase {
        case .setup: AfterClose(seen: false, later: true)
        case .finish: AfterClose(seen: true, later: false)
        default: nil
        }
    }

    static func closeOnQuit(phase: ArisOnboardingPhase) -> Close { phase == .finish ? .finished : .later }

    enum Launch: Equatable { case none, intro, resume }

    /// The intro the first time or on replay; after 나중에 할게요 the pages left (quietly), never for a login-item launch,
    /// at most once a day (a Quit & Reopen within 10 minutes excepted), at most 3 times.
    static func launch(seen: Bool, later: Bool, replay: Bool, loginItem: Bool, lastResume: Date?, resumes: Int, quitAt: Date?,
                       now: Date) -> Launch {
        if replay { return .intro }
        if later {
            guard !loginItem, resumes < maxResumes else { return .none }
            let reopened = quitAt.map { now.timeIntervalSince($0) < reopenWindow } ?? false
            let recent = lastResume.map { now.timeIntervalSince($0) < resumeSpacing } ?? false
            return reopened || !recent ? .resume : .none
        }
        return seen ? .none : .intro
    }

    /// Put off for later resumes at the pages (no intro); a replay always starts from the intro.
    static func resumes(later: Bool, replay: Bool) -> Bool { later && !replay }
}
