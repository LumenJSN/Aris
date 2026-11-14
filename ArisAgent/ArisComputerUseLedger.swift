//
//  ArisComputerUseLedger.swift
//  aris-agent
//
//  Computer use's memory for one conversation, shared by every brain (the owner: no feature locked out by the brain). It
//  holds the user's per-app "computer use OK" (ArisComputerUseMemory, held by Aris, never by a brain), the apps outside text
//  wiped from it, and what the desktop controller saw: every look it took (ArisDesktopObservation: the app, the exact
//  window, Peekaboo's snapshot and each element, so a ref's app is always Aris's record, never the brain's word), each
//  window's latest look (an action must use it: the stale-snapshot guard). Locked: the runner's queue and the desktop
//  route's threads both use it.
//

import Foundation

/// "Computer use OK" for each app for the conversation, held by Aris rather than by Codex (a session-wide yes there
/// couldn't be taken back once outside text came in). Only an untainted yes is kept, and it answers only untainted
/// calls; the app's own screen doesn't count as outside text for it (ArisBrainDriver.taint(forApp:)).
struct ArisComputerUseMemory: Equatable {
    private var apps: Set<String> = []

    func allows(_ app: String, tainted: Bool) -> Bool { !tainted && apps.contains(app) }

    /// The apps it holds (to tell the user, once outside text wiped them, why they're asked again).
    var known: Set<String> { apps }

    func remembering(_ app: String, tainted: Bool) -> ArisComputerUseMemory {
        tainted ? self : ArisComputerUseMemory(apps: apps.union([app]))
    }
}

/// The app a snapshot was taken of, as Aris resolved it (ArisDesktopApps), never as the brain named it.
struct ArisDesktopTarget: Equatable {
    /// The app's name as the Mac shows it (what the card says; Peekaboo gets the bundle id).
    let name: String
    /// Its bundle id; nil when it couldn't be resolved (always asked, never remembered).
    let bundle: String?
    let pid: Int32
    /// Installed in the usual places, registered once and signed (ArisAppIdentity.url(ofBundle:)): only then may a yes
    /// for it be remembered.
    let known: Bool
    /// Never computer use there (ArisRiskPolicy.computerUseIsNever: password stores, Keychain, terminals, Aris itself).
    let never: Bool
    /// A web browser: websites are Aside's.
    let browser: Bool
    /// Mail, chat or calls: every action there asks, with the exact text.
    let sending: Bool
    /// System Settings: an ordinary app, but no action in its permission, account or profile panes.
    var settings = false
    /// Apple's own signed app as this bundle (ArisAppIdentity.isAppleSigned), checked only for the safe typing apps: a
    /// type of the user's words runs at once only there (QA follow-up to BUG-15).
    var appleSigned = false

    /// What the per-app memory is keyed by: the bundle id of a known app, under this engine's own name (Peekaboo's
    /// desktop controller), nothing otherwise. Each engine keeps its own yeses, so a yes for Codex's own computer use
    /// (cua_repl, keyed by the bare bundle id) never opens the desktop path, nor the other way round (security review I14).
    var memoryKey: String? { known ? bundle.map { Self.enginePrefix + $0 } : nil }
    static let enginePrefix = "desktop:"
    /// What the turn's per-app taint is keyed by (the app's own screen isn't outside text for it).
    var readKey: String { bundle ?? "pid:\(pid)" }
}

final class ArisComputerUseLedger {
    private let lock = NSLock()
    private var memory = ArisComputerUseMemory()
    private var wiped: Set<String> = []
    private var snapshots: [String: ArisDesktopObservation] = [:]
    private var snapshotOrder: [String] = []
    /// Each window's latest look: an action must use it (the stale-snapshot guard).
    private var latest: [Int: String] = [:]
    /// The tier of the System Settings pane the latest look at it showed (ArisSettingsPane), for Codex's own computer
    /// use too: it judges its steps there by it.
    private var settingsPane = ArisSettingsPane.unknown
    /// Peekaboo's snapshot folders to remove once forgotten (ArisPeekabooSnapshots).
    private let forget: ([String]) -> Void

    /// At most this many snapshots (and elements) are remembered; the oldest go first.
    static let maxSnapshots = 64
    static let maxElements = 4_000

    init(forget: @escaping ([String]) -> Void = { _ in }) { self.forget = forget }

    // MARK: - the user's per-app yes

    func allows(_ app: String, tainted: Bool) -> Bool { lock.withLock { memory.allows(app, tainted: tainted) } }

    func remember(_ app: String, tainted: Bool) { lock.withLock { memory = memory.remembering(app, tainted: tainted) } }

    var known: Set<String> { lock.withLock { memory.known } }

    /// Outside text came in: every yes is gone, and the apps it held are kept to say why the user is asked again.
    func wipe() {
        lock.withLock {
            wiped.formUnion(memory.known)
            memory = ArisComputerUseMemory()
        }
    }

    /// The user's yes for this app was wiped by outside text in this conversation.
    func wasWiped(_ app: String) -> Bool { lock.withLock { wiped.contains(app) } }

    // MARK: - Cards that wait for the user (one action, one card)

    /// The apps (ArisDesktopTarget.readKey) an action's card waits for the user in, how many each.
    private var waitingCards: [String: Int] = [:]

    /// An action's card for `app` went up (it may wait in 확인 대기 for long).
    func cardUp(_ app: String) { lock.withLock { waitingCards[app, default: 0] += 1 } }

    /// That card was answered (a yes, a no, or none in time).
    func cardDown(_ app: String) {
        lock.withLock {
            let left = (waitingCards[app] ?? 1) - 1
            waitingCards[app] = left > 0 ? left : nil
        }
    }

    /// An action's card for `app` waits for the user: no other look or action there until it is answered (eighth VM pass:
    /// the API brain looked again and clicked again while a job's card was parked, so one action showed two cards).
    func cardWaits(_ app: String) -> Bool { lock.withLock { waitingCards[app] != nil } }

    /// Any action's card of this conversation waits for the user.
    var anyCardWaits: Bool { lock.withLock { !waitingCards.isEmpty } }

    // MARK: - A saved-steps replay's cards (no more than the live run asked)

    /// The apps the user said yes to on a card during this ledger's turn (any taint): a replay's step the live run did on the
    /// app's yes then runs on this one, as it did (eighth VM pass: the replay asked two cards where the live run asked one).
    private var cardYeses: Set<String> = []
    /// The replay's step under way was done on the app's yes in the live run (ArisSavedStep.afterYes).
    private var replayStepAfterYes = false

    /// The user said yes on an action's card for `app` (its memory key).
    func noteCardYes(_ app: String) { lock.withLock { _ = cardYeses.insert(app) } }

    /// The replay's step under way (its look and its action) was done with no outside text for its app in the live run
    /// (ArisSavedStep.appClean): the replay's turn reads its taint for it from the conversation alone
    /// (ArisSavedStepsReplay.stepTaint).
    private var replayClean = false

    /// A saved-steps replay starts (`afterYes`, `clean`) or ends (false) one step.
    func replayStep(afterYes: Bool, clean: Bool = false) {
        lock.withLock {
            replayStepAfterYes = afterYes
            replayClean = clean
        }
    }

    /// The replay's step under way was done with no outside text for its app in the live run.
    var replayStepClean: Bool { lock.withLock { replayClean } }

    /// The replay's step under way runs on the user's yes to an earlier card of the same replay for `app`, as in the live run.
    func replayCovers(_ app: String) -> Bool { lock.withLock { replayStepAfterYes && cardYeses.contains(app) } }

    // MARK: - How a look was decided (a replay's look decided as the live run's was)

    /// The looks (snapshot ids) the read judge had to allow: a step done on such a look is saved as needing the judge.
    private var judgedLooks: Set<String> = []
    /// The replay's look under way ran without the read judge in the live run (ArisSavedStep.lookJudged false).
    private var replayLookUnjudged = false

    func noteJudged(_ snapshot: String) { lock.withLock { _ = judgedLooks.insert(snapshot) } }
    func wasJudged(_ snapshot: String) -> Bool { lock.withLock { judgedLooks.contains(snapshot) } }

    /// A saved-steps replay starts (`unjudged`, `clean` as its step) or ends (false) the look before a step.
    func replayLook(unjudged: Bool, clean: Bool = false) {
        lock.withLock {
            replayLookUnjudged = unjudged
            replayClean = clean
        }
    }

    /// The look under way is a replay's, of a step whose live look ran without the judge: it runs without it again
    /// (a replay has no AI: what it reads goes to no model, only to find the step's control).
    var replayLookSkipsJudge: Bool { lock.withLock { replayLookUnjudged } }

    // MARK: - What the desktop engine saw

    /// A look Aris took: the window's latest from now on; the oldest go once there are too many.
    func record(_ observation: ArisDesktopObservation) {
        let dropped: [String] = lock.withLock {
            if snapshots[observation.snapshot] == nil { snapshotOrder.append(observation.snapshot) }
            snapshots[observation.snapshot] = observation
            latest[observation.window] = observation.snapshot
            lastRecorded = observation.snapshot
            if observation.target.settings { settingsPane = observation.settingsPane }
            var gone: [String] = []
            while snapshotOrder.count > Self.maxSnapshots {
                let old = snapshotOrder.removeFirst()
                if let peekaboo = snapshots.removeValue(forKey: old)?.peekaboo { gone.append(peekaboo) }
                latest = latest.filter { $0.value != old }
            }
            return gone
        }
        if !dropped.isEmpty { forget(dropped) }
    }

    /// A look (by Aris's id) taken in this conversation; nil for one Aris didn't take.
    func observation(_ id: String) -> ArisDesktopObservation? { lock.withLock { snapshots[id] } }

    /// The look recorded last, of any window (saved steps find their control in the look they just took).
    private var lastRecorded: String?
    var lastLook: ArisDesktopObservation? { lock.withLock { lastRecorded.flatMap { snapshots[$0] } } }

    /// The app a snapshot was taken of.
    func target(ofSnapshot id: String) -> ArisDesktopTarget? { observation(id)?.target }

    /// The window a snapshot read.
    func window(ofSnapshot id: String) -> Int? { observation(id)?.window }

    /// The snapshot is still its window's latest (nothing was done or seen there since).
    func isLatest(_ id: String) -> Bool { lock.withLock { snapshots[id].map { latest[$0.window] == id } ?? false } }

    /// The element a ref names, for the card.
    func element(_ ref: ArisDesktopRef) -> ArisDesktopElement? { observation(ref.snapshot)?.element(ref) }

    /// The latest look at this window in this conversation (the title a card shows: I4).
    func latestLook(window: Int) -> ArisDesktopObservation? { lock.withLock { latest[window].flatMap { snapshots[$0] } } }

    /// The tier of the System Settings pane last seen in this conversation (unknown when none was).
    func lastSettingsPane() -> ArisSettingsPane { lock.withLock { settingsPane } }

    /// A step that may have moved System Settings to another pane (Codex's own computer use): unknown until seen again.
    func forgetSettingsPane() { lock.withLock { settingsPane = .unknown } }

    /// A look that is never recorded (the one a card is drawn from): Peekaboo's folder for it goes at once (I1).
    func discard(_ peekaboo: String) { forget([peekaboo]) }

    // MARK: - Windows this turn (QA BUG-47 reopened)

    private var doneWindow: (window: String, typed: Bool)?
    /// Actions of this turn that weren't done (refused, a no, not confirmed).
    private var notDone = 0

    /// Actions of this turn that came back ok, whether or not a window was read after (a click that closed its window,
    /// an app launched, a menu item: security review of BUG-33's rewrite).
    private var acted = 0

    func noteNotDone() { lock.withLock { notDone += 1 } }
    /// Actions of this turn the user said no to (their card): only then may the reply say "알겠어요".
    private var declined = 0
    func noteDeclined() { lock.withLock { declined += 1 } }
    var declinedThisTurn: Int { lock.withLock { declined } }
    /// Why the turn's last desktop call wasn't done (the engine's own reason line).
    private var refusal: String?
    /// The turn's latest "not done" was the user's own no (their card), not a refusal or a failure after it (security review of
    /// 4d40bb80: a later, unrelated failure was worded as his no).
    private var lastWasUsersNo = false
    /// `action`: the call would have changed something (a look that failed says nothing about the user's no).
    func noteRefusal(_ why: String, usersNo: Bool = false, action: Bool = true) {
        lock.withLock {
            refusal = why
            if action { lastWasUsersNo = usersNo }
        }
    }
    /// The user said no on a card of the turn that isn't a desktop call (a gate, service or file card).
    func noteUsersNo() { lock.withLock { lastWasUsersNo = true } }
    var lastRefusal: String? { lock.withLock { refusal } }
    var latestNoIsUsers: Bool { lock.withLock { lastWasUsersNo } }
    /// Windows where a select-all was pressed this turn (and not yet typed over): typing there next replaces.
    private var selectAllWindows: Set<Int> = []
    func noteSelectAll(window: Int?) { if let window { lock.withLock { _ = selectAllWindows.insert(window) } } }
    func selectedAll(in window: Int?) -> Bool { window.map { id in lock.withLock { selectAllWindows.contains(id) } } ?? false }
    /// The selection there is gone (typed over, deleted, or the caret moved): typing there next adds again.
    func clearSelectAll(window: Int?) { if let window { lock.withLock { _ = selectAllWindows.remove(window) } } }
    /// What Aris typed this turn, on the user's card, into a message field that gives no value (KakaoTalk's), by window, once
    /// the window showed it: what a send from that field is asked about (audit desk-4). Gone once a send was tried.
    private var blindTexts: [Int: String] = [:]
    func noteBlindTyped(window: Int, text: String) { lock.withLock { blindTexts[window, default: ""] += text } }
    func blindTyped(window: Int?) -> String? { window.flatMap { id in lock.withLock { blindTexts[id] } } }
    func clearBlindTyped(window: Int?) { if let window { lock.withLock { _ = blindTexts.removeValue(forKey: window) } } }
    /// The window the user's words pinned for a look this turn (QA BUG-47 retest: recorded, so it can be checked).
    private var pinnedTitle: String?
    func notePinned(_ title: String) { lock.withLock { pinnedTitle = title } }
    var pinnedThisTurn: String? { lock.withLock { pinnedTitle } }
    func noteActed() { lock.withLock { acted += 1 } }

    /// A brain's desktop action began (POST /desktop-tool): until its answer comes it counts as not done, so a reply
    /// can't claim it while its card is still up.
    func noteActionStarted() { noteNotDone() }

    /// That action's answer came: done, it no longer counts as not done (seventh VM pass: every action of a turn stayed
    /// "not done" for good, so no turn's steps were ever saved); not done, it stays so.
    func noteActionEnded(ok: Bool) {
        guard ok else { return }
        lock.withLock {
            notDone = max(0, notDone - 1)
            acted += 1
        }
    }

    /// What this turn's actions came to: whether any was done, and how many weren't.
    var actionsThisTurn: (done: Bool, notDone: Int) { lock.withLock { (doneWindow != nil || acted > 0, notDone) } }
    private var titles: Set<String> = []

    /// Titles of the windows the engine saw this turn.
    func noteTitles(_ seen: [String]) { lock.withLock { titles.formUnion(seen.filter { !$0.isEmpty }) } }

    /// An action was done in this window (a type, or another action).
    func noteDone(window: String, typed: Bool) { lock.withLock { doneWindow = (window, typed); titles.insert(window) } }

    var windowsThisTurn: (done: (window: String, typed: Bool)?, titles: Set<String>) { lock.withLock { (done: doneWindow, titles: titles) } }

    /// A new turn: no window acted in yet.
    func startTurn() { lock.withLock { doneWindow = nil; titles = []; notDone = 0; declined = 0; refusal = nil; lastWasUsersNo = false; acted = 0; pinnedTitle = nil; selectAllWindows = []; blindTexts = [:] } }

    /// A new conversation: nothing of the old one counts (Peekaboo's folders for it go too).
    func reset() {
        let dropped: [String] = lock.withLock {
            let gone = snapshots.values.map(\.peekaboo)
            memory = ArisComputerUseMemory()
            wiped = []
            snapshots = [:]
            snapshotOrder = []
            latest = [:]
            settingsPane = .unknown
            return gone
        }
        if !dropped.isEmpty { forget(dropped) }
    }
}

/// A locked count of one turn's desktop calls. `onReset`: what else starts over with a new turn.
final class ArisDesktopStepCount {
    private let lock = NSLock()
    private var count = 0
    private let onReset: () -> Void

    init(onReset: @escaping () -> Void = {}) { self.onReset = onReset }

    func next() -> Int { lock.withLock { count += 1; return count } }
    func reset() {
        lock.withLock { count = 0 }
        onReset()
    }
}
