//
//  ArisNoticeCenter.swift
//  Aris
//
//  The live side of the notice pill: the queue (ArisNoticeQueue), the display it shows on (the notch's), what each
//  button and a click on its body do, the pointer on it, and the clock of a notice that goes by itself. The pill is
//  drawn by the notch of that display, 6 under it where the jobs' pill hangs (ArisNoticePillHost in ArisNotchRoot), so
//  it has no window of its own. It steps aside while the notch is open, the setup shows, an Aris turn or a dictation
//  runs, and comes back as it was. A deadline's alert (ArisTodoModel) and a Claude Code session's notice (ClaudeStore)
//  come here as notices too, through ArisController.notify like Aris's own news, so all of them wait their turn and
//  only one pill shows at a time. Nothing here decides when a waiting notice may come up: ArisController.notify waits
//  for the moment (its turn among Aris's news, a pause) and asks `mayShow` for the rest. The pointer's intent is waited
//  out here (ArisNoticeHoverIntent): `hovered`, the card, follows 100 ms after it rests and 150 ms after it leaves.
//

import AppKit
import Combine
import os
import SwiftUI

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "notice")

@MainActor
final class ArisNoticeCenter: ObservableObject {
    static let shared = ArisNoticeCenter()

    @Published private(set) var queue = ArisNoticeQueue()
    /// The notice drawn as the card (the pointer rested on it; ArisNoticeHoverIntent).
    @Published private(set) var hovered: UUID?
    /// Where the pointer is and what the card shows, and the wait between the two.
    private var intent = ArisNoticeHoverIntent()
    private var intentWait: Task<Void, Never>?
    /// The pill steps aside (faded out, still up) while the notch is open, the setup shows, a turn or a dictation runs.
    @Published private(set) var aside = false
    /// The display the pill shows on (its notch draws it).
    @Published private(set) var screenID: String?

    private var watches: Set<AnyCancellable> = []
    private var displayWatch: ArisWorldSubscription?
    /// How many fixes of a problem notice were pressed (a line with several lists opens them one after another).
    private var fixPresses: [UUID: Int] = [:]
    /// The front notice's own clock (its showsFor), while it runs.
    private var clock: Task<Void, Never>?
    private var lastClaudePeek: String?
    /// The notch, as the app's windows tell it (ArisEntry attaches them).
    private var notchOpen: () -> Bool = { false }
    private var notchScreen: () -> NSScreen? = { NSScreen.main }

    private init() {}

    // MARK: - What it watches

    /// The notch's windows: whether one is open, its display, and a signal each time either may have changed. Also the
    /// setup, an Aris turn, the dictation pill and Claude Code's notices.
    func attach(notchOpen: @escaping () -> Bool, screen: @escaping () -> NSScreen?, changes: AnyPublisher<Void, Never>) {
        self.notchOpen = notchOpen
        notchScreen = screen
        watches.removeAll()
        displayWatch?.cancel()
        // The displays, as ArisWorld hears them (one observer for every feature).
        let displays = PassthroughSubject<Void, Never>()
        displayWatch = ArisWorld.shared.subscribe([.displays]) { _, _ in displays.send() }
        let moved: [AnyPublisher<Void, Never>] = [
            changes,
            ArisOnboardingGuide.shared.$phase.map { _ in () }.eraseToAnyPublisher(),
            ArisNotchState.shared.$current.map { _ in () }.eraseToAnyPublisher(),
            ArisDictationPillCenter.shared.$display.map { _ in () }.eraseToAnyPublisher(),
            displays.eraseToAnyPublisher(),
        ]
        // After the didSet (the publishers emit on willSet): the values read are the stored ones.
        Publishers.MergeMany(moved).receive(on: DispatchQueue.main)
            .sink { [weak self] in MainActor.assumeIsolated { self?.notchMoved() } }
            .store(in: &watches)
        ClaudeStore.shared.$transientPeek.receive(on: DispatchQueue.main)
            .sink { [weak self] peek in MainActor.assumeIsolated { self?.claudePeek(peek) } }
            .store(in: &watches)
        notchMoved()
    }

    private var moment: ArisNoticeGate.Moment {
        let state = ArisNotchState.shared
        return ArisNoticeGate.Moment(pause: true, onboarding: ArisOnboardingGuide.shared.showing, notchOpen: notchOpen(),
                                     turn: state.isActive || state.conversing,
                                     dictating: state.isDictating || ArisNoticeGate.dictationBusy(ArisDictationPillCenter.shared.display.phase))
    }

    /// Whether a notice may come up now, the pause aside (ArisController asks that itself).
    var mayShow: Bool { ArisNoticeGate.mayShow(moment) }

    private func notchMoved() {
        let stepAside = ArisNoticeGate.stepsAside(moment)
        if stepAside != aside { aside = stepAside }
        if stepAside { dropHover() }
        let screen = (notchScreen() ?? NSScreen.main)?.displayUUID
        if screen != screenID { screenID = screen }
        runClock()
    }

    // MARK: - The queue

    /// A new notice waits for its moment; true when it replaced one already up (it is up at once).
    @discardableResult
    func enqueue(_ notice: ArisNotice) -> Bool {
        let replacesShown = notice.key.map { key in queue.shown.contains { $0.key == key } } ?? false
        queue = queue.posting(notice)
        if replacesShown {
            log.notice("notice replaced: \(notice.kind.rawValue, privacy: .public)")
            runClock()
        }
        return replacesShown
    }

    func isWaiting(_ id: UUID) -> Bool { queue.isWaiting(id) }

    func dropExpired() { queue = queue.dropping(expiredAt: Date()) }

    /// Its moment came: it is the one drawn.
    func present(_ id: UUID) {
        queue = queue.presenting(id)
        notchMoved()
    }

    /// Never shown after all (its caller was cancelled).
    func withdraw(_ id: UUID) {
        guard queue.isWaiting(id) else { return }
        queue = queue.closing(id)
    }

    /// What `key` stood for is over: its notice goes, waiting or up.
    func withdraw(key: String) {
        let next = queue.withdrawing(key: key)
        guard next != queue else { return }
        queue = next
        settle()
    }

    // MARK: - What the pill asks

    var handlers: ArisNoticeHandlers {
        ArisNoticeHandlers(close: { [weak self] in self?.close($0) }, act: { [weak self] in self?.act($0, $1) },
                           tap: { [weak self] in self?.tap($0) }, hover: { [weak self] in self?.hover($0) })
    }

    func close(_ id: UUID) {
        let notice = queue.shown.first { $0.id == id } ?? queue.pending.first { $0.id == id }
        queue = queue.closing(id)
        fixPresses[id] = nil
        if hovered == id || intent.pointer == id { dropHover() }
        // A deadline's alert is over once its notice goes (ArisTodoModel keeps one at a time).
        if case .deadline = notice?.source { ArisTodoModel.shared.dismissAlert() }
        // An update's ✕ is 나중에 while it is offered; a download goes on, out of sight.
        if notice?.key == ArisUpdateWords.key { ArisUpdater.shared.noticeClosed() }
        settle()
    }

    /// The pointer came onto the pill or left it: the card follows once the intent's wait runs out (a wait already
    /// running is cancelled: brushed past, or back within the grace).
    private func hover(_ id: UUID?) {
        guard !aside || id == nil, id != intent.pointer else { return }
        let (next, wait) = intent.pointing(at: id)
        intent = next
        intentWait?.cancel()
        intentWait = nil
        guard let wait else { return }
        intentWait = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, let self else { return }
            self.intent = self.intent.settled()
            self.intentWait = nil
            guard self.hovered != self.intent.expanded else { return }
            self.hovered = self.intent.expanded
            self.runClock()
        }
    }

    /// No pointer, no card, no wait (it stepped aside, closed, or nothing is up).
    private func dropHover() {
        intentWait?.cancel()
        intentWait = nil
        intent = intent.cleared()
        if hovered != nil { hovered = nil }
    }

    /// A click on the body: what the notice names for it (a deadline opens, Claude Code's terminal comes forward).
    private func tap(_ id: UUID) {
        guard let role = queue.shown.first(where: { $0.id == id })?.tap else { return }
        act(id, ArisNoticeAction(title: "", primary: true, role: role))
    }

    /// A button: what it names, then the notice goes (acted on), unless a problem's next fix is still to press.
    func act(_ id: UUID, _ action: ArisNoticeAction) {
        guard let notice = queue.shown.first(where: { $0.id == id }) else { return }
        let english = ArisUIWords.english
        switch action.role {
        case .fixes(let fixes):
            let pressed = fixPresses[id] ?? 0
            guard pressed < fixes.count else { return close(id) }
            ArisFixModel.shared.press(fixes[pressed])
            fixPresses[id] = pressed + 1
            if let next = ArisNoticeRoute.afterFix(notice, pressed: pressed + 1, english: english) {
                queue = queue.replacing(next)
                return
            }
        case .restartHelper:
            ArisAgentMonitor.shared.restart()
        case .permissionPane(let permission):
            ArisPermissionCenter.shared.openPane(permission)
        case .relaunchApp:
            ArisPermissionCenter.shared.relaunch()
        case .openJob(let job):
            ArisController.shared.openDone(id: job)
        case .openFile(let file):
            ArisBoard.shared.read(file: file)
        case .openAnswer(let question, let text):
            ArisBoard.shared.show(ArisReaderDocument.answer(text, question: question))
        case .retryJob(let job):
            ArisController.shared.retryNotDone(job)
        case .openDue(let due):
            ArisTodoModel.shared.open(due)
        case .focusClaude(let sessionId):
            let store = ClaudeStore.shared
            if let session = store.sessions[sessionId] { TerminalFocus.focus(session, cwd: session.cwd) }
            store.dismissPeek()
        case .installUpdate:
            // The updater puts its next notice (the download) in this one's place.
            return ArisUpdater.shared.installNow()
        case .laterUpdate:
            return ArisUpdater.shared.later()
        }
        close(id)
    }

    // MARK: - Claude Code's notices

    /// A session's done, error or limit notice becomes a notice on the pill (it no longer opens the notch).
    private func claudePeek(_ peek: ClaudePeek?) {
        guard let peek, peek.id != lastClaudePeek else { return }
        lastClaudePeek = peek.id
        let notice = ArisNoticeRoute.claude(peek, english: ArisUIWords.english)
        Task { await ArisController.shared.notify(notice) }
    }

    // MARK: - The clock

    /// Nothing is up any more: no clock, nothing hovered.
    private func settle() {
        if queue.shown.isEmpty { dropHover() }
        runClock()
    }

    /// The front notice's own clock runs while it is seen and not under the pointer (ArisNoticePillRules.clockRuns); it
    /// starts again from its whole showsFor each time it may run again.
    private func runClock() {
        clock?.cancel()
        clock = nil
        guard let front = queue.front, let seconds = front.showsFor,
              ArisNoticePillRules.clockRuns(front, hovered: hovered, aside: aside) else { return }
        clock = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, self.queue.front?.id == front.id else { return }
            self.close(front.id)
        }
    }
}

/// The pill under the notch of the display it shows on: the front notice, or nothing while it steps aside. Aris's star
/// takes the pill's seat (the one star hops down into it, ArisStarStage), Claude Code's ghost is drawn here.
struct ArisNoticePillHost: View {
    @ObservedObject var center = ArisNoticeCenter.shared
    @ObservedObject private var team = ArisTeamModel.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            if let notice = center.queue.front, !center.aside {
                ArisNoticePillView(notice: notice, english: ArisUIWords.english, hovered: center.hovered == notice.id,
                                   handlers: center.handlers) { mark in
                    if mark == .ghost {
                        ArisCharacterView(look: team.claudeLook, size: ArisNoticePillLayout.markSize, follows: false)
                    } else {
                        Color.clear.arisStarSeat(.pill)
                    }
                }
                .id(notice.id)
                .transition(ArisNoticePillView<EmptyView>.exit(reduceMotion: reduceMotion))
            }
        }
        .animation(ArisNoticePillView<EmptyView>.ease(ArisNoticePillLayout.exit), value: center.queue.front?.id)
        .animation(ArisNoticePillView<EmptyView>.ease(ArisNoticePillLayout.exit), value: center.aside)
    }
}
