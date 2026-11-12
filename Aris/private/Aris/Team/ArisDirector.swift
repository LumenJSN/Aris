//
//  ArisDirector.swift
//  Aris
//
//  The character director's effects (its rules are ArisCharacterDirector's, its bookkeeping ArisCast's): the jobs drive
//  it. A job that starts and has a window (its appHint's app, or the terminal Claude Code opened in) sends its teammate
//  gliding from the notch to that window, where it perches with a live bubble and follows the window while it moves.
//  At most 3 are out at once, one per window; the others, and jobs with no window, wait in the home slot. The
//  notch-down status pill shows who works (the user's B: the star for Aris's own job, else the teammate's face; small faces
//  and "+N" from two jobs on). When the job ends the teammate says "끝났어요" (or "못 끝냈어요"), glides home and merges
//  into the notch. A closed window sends its teammate back to the slot for good; one that is only out of sight
//  (minimised, hidden, another Space) parks it there until the window shows again. A display change seats everyone
//  again in the new panels, or sends them home.
//
//  Idle cost is zero: no timer, observer or display link runs while nobody is out or parked, and the overlay panels
//  close 30 s after the last one comes home. A follower runs only while its teammate is out.
//

import AppKit
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "team")

@MainActor
final class ArisDirector: ObservableObject {
    /// Who works on a live job: Aris itself (`aris`, its star) or a teammate, with its look and name.
    struct SlotMate: Identifiable, Equatable {
        let id: UUID
        let look: ArisCharacterLook
        let name: String?
        let aris: Bool
    }

    /// When the only job waits in the slot: who it is and what it does, for the pill's line.
    struct SlotLine: Equatable {
        let name: String?
        let text: String
    }

    /// Who works on each live job, oldest first, out on a window or waiting in the home slot (the pill's face slot).
    @Published private(set) var crew: [SlotMate] = []
    @Published private(set) var single: SlotLine?

    private let panels = ArisOverlayPanels()
    private var jobs: [ArisJob] = []
    private var figures: [UUID: ArisFigure] = [:]
    private var cast = ArisCast()
    /// Jobs whose window closed or can't be sat on: they wait in the slot from now on.
    private var lost: Set<UUID> = []
    /// Jobs whose window is out of sight (minimised, hidden, another Space): in the slot until it shows again.
    private var parked: Set<UUID> = []
    private var parkWatch: ArisParkWatch?
    private var parkChecked = Date.distantPast
    /// Each job's window, once known.
    private var windows: [UUID: ArisWindowKey] = [:]
    /// When a job's app hint was last looked up (at most every 2 s while it runs without a window).
    private var hintTried: [UUID: Date] = [:]
    private var seen: Set<UUID> = []
    private var idleTeardown: DispatchWorkItem?
    private static let retry: TimeInterval = 2

    private var faceWatch: NSObjectProtocol?

    /// A job's window was closed for good (not merely out of sight): a Claude Code job waiting on that terminal ends
    /// (audit team-4; ArisController.teammateWindowClosed).
    var onWindowClosed: ((UUID) -> Void)?

    init() {
        panels.onRebuild = { [weak self] in self?.screensChanged() }
        // Aris's face changed (the 팀원 page): the slot's faces are looked up again (figures out on windows follow it
        // themselves, ArisFigureCharacter).
        faceWatch = NotificationCenter.default.addObserver(forName: ArisFace.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restage() }
        }
    }

    /// An ad demo's teammates are out (ArisAdDemo): the panels show in screen recordings until it ends.
    func showInCaptures(_ on: Bool) { panels.shownInCaptures = on }

    // MARK: the jobs

    /// The jobs changed (any state, step or target): idempotent and cheap, it runs on every status line.
    func update(_ jobs: [ArisJob]) {
        self.jobs = jobs
        for job in jobs where seen.insert(job.id).inserted { prefetch(look(of: job), on: Self.homeScreen()) }
        resolveWindows()
        recheckParked(force: false)
        for (id, figure) in figures where cast.phase(of: id) != .returning {
            // A job dropped from the list (only the last few finished ones are kept): its teammate just goes home.
            guard let job = jobs.first(where: { $0.id == id }) else {
                sendHome(id, after: 0)
                continue
            }
            if job.isFinished {
                end(job, figure)
            } else {
                figure.say(ArisBubbleText.text(for: job.state, korean: figure.model.korean), tone: ArisBubbleText.tone(for: job.state))
            }
        }
        restage()
    }

    /// Who goes out, who waits; sends out the newly picked and publishes the slot.
    private func restage() {
        let byId = Dictionary(jobs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var stage: ArisCharacterDirector.Stage
        repeat {
            let current = cast.out.sorted { (byId[$0]?.created ?? .distantPast) < (byId[$1]?.created ?? .distantPast) }
            stage = ArisCharacterDirector.stage(jobs.map(stageJob), out: current, returning: cast.returning)
        } while !stage.out.filter({ figures[$0] == nil }).allSatisfy(goOut)
        publishSlot(stage.slot.compactMap { byId[$0] })
        scheduleIdleTeardown()
    }

    private func stageJob(_ job: ArisJob) -> ArisCharacterDirector.StageJob {
        let started = job.state != .queued && !job.isFinished
        let free = started && !lost.contains(job.id) && !parked.contains(job.id)
        return .init(id: job.id, created: job.created, live: !job.isFinished, window: free ? windows[job.id] : nil)
    }

    private func publishSlot(_ waiting: [ArisJob]) {
        let live = jobs.filter { !$0.isFinished }
        let mates = live.sorted { $0.created < $1.created }.map(mate)
        if mates != crew { crew = mates }
        var line: SlotLine?
        if live.count == 1, let only = waiting.first, only.id == live.first?.id,
           let text = ArisBubbleText.text(for: only.state, korean: ArisSpeech.language(of: only.title) == "ko-KR") {
            line = SlotLine(name: name(of: only), text: text)
        }
        if line != single { single = line }
    }

    // MARK: windows

    /// A job's window: the one Claude Code opened (its target), else the front window of the app its hint names.
    private func resolveWindows() {
        let now = Date()
        for job in jobs where !job.isFinished {
            if case .window(let pid, let number) = job.target {
                let key = ArisWindowKey(pid: pid, number: number)
                guard windows[job.id] != key else { continue }
                // A new window (Claude Code opened another): forget the old one; a teammate on it comes home first.
                windows[job.id] = key
                lost.remove(job.id)
                parked.remove(job.id)
                if figures[job.id] != nil, cast.phase(of: job.id) != .returning { sendHome(job.id, after: 0) }
                continue
            }
            guard windows[job.id] == nil, !lost.contains(job.id), job.appHint != nil, job.state != .queued,
                  now.timeIntervalSince(hintTried[job.id] ?? .distantPast) >= Self.retry else { continue }
            hintTried[job.id] = now
            let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
                .map { ArisRunningApp(pid: $0.processIdentifier, bundleId: $0.bundleIdentifier, name: $0.localizedName,
                                    bundleName: $0.bundleURL?.deletingPathExtension().lastPathComponent) }
            guard let pid = ArisAppHint.pid(for: job.appHint, in: apps, excluding: ProcessInfo.processInfo.processIdentifier),
                  let front = ArisWindowLocator.frontWindow(pid: pid) else { continue }
            windows[job.id] = ArisWindowKey(pid: pid, number: front.number)
        }
        // Forget jobs no longer listed (only the last few finished ones are kept), so nothing grows.
        let live = Set(jobs.filter { !$0.isFinished }.map(\.id)), listed = Set(jobs.map(\.id))
        windows = windows.filter { live.contains($0.key) || figures[$0.key] != nil }
        hintTried = hintTried.filter { live.contains($0.key) }
        lost.formIntersection(listed)
        seen.formIntersection(listed)
    }

    /// The perch on a window at `cg` (CG coordinates), never over the menu bar (M2 inside a maximised one).
    private func perch(on cg: CGRect, titleBar: CGFloat?) -> (point: CGPoint, window: CGRect)? {
        let screens = NSScreen.screens
        let primaryHeight = screens.first?.frame.height ?? 0
        guard let point = ArisPerchGeometry.perchPoint(windowCG: cg, screens: screens.map(\.frame), visibleFrames: screens.map(\.visibleFrame),
                                                       primaryHeight: primaryHeight, size: ArisCharacterDirector.perchSize,
                                                       titleBarHeight: titleBar ?? ArisPerchGeometry.titleBarHeight)
        else { return nil }
        return (point, ArisPerchGeometry.toAppKit(cg, primaryHeight: primaryHeight))
    }

    // MARK: going out

    /// Sends `id`'s teammate from the notch to its window; false when the window is out of sight (parked) or gone
    /// (lost): the job then waits in the slot.
    private func goOut(_ id: UUID) -> Bool {
        guard let job = jobs.first(where: { $0.id == id }), let key = windows[id] else {
            lost.insert(id)
            return false
        }
        let presence = Self.presence(key.pid, key.number)
        guard case .onScreen(let cg) = presence else {
            if ArisCharacterDirector.whenGone(presence) == .park { park(id) } else { lost.insert(id) }
            return false
        }
        // An ad demo's stand-in window (ArisAdDemoRoster) has no process to ask or follow.
        let standIn = ArisAdDemoRoster.fixedWindow(pid: key.pid, number: key.number) != nil
        let titleBar = standIn ? nil : ArisTitleBarProbe.height(pid: key.pid, windowCG: cg)
        guard let seat = perch(on: cg, titleBar: titleBar) else {
            lost.insert(id)
            return false
        }
        idleTeardown?.cancel()
        idleTeardown = nil
        let clone = if case .clone = job.assignee { true } else { false }
        let figure = ArisFigure(id: id, look: look(of: job), name: name(of: job), aris: clone, pid: key.pid, windowNumber: key.number)
        figure.titleBarHeight = titleBar
        figure.model.korean = ArisSpeech.language(of: job.title) == "ko-KR"
        figure.say(ArisBubbleText.text(for: job.state, korean: figure.model.korean), tone: ArisBubbleText.tone(for: job.state))
        prefetch(figure.look, on: NSScreen.screens.first { $0.frame.contains(seat.point) })
        figures[id] = figure
        cast.goOut(id)
        figure.spawn(at: Self.home(), panels: panels)
        figure.follower = standIn ? nil : follower(for: id, key)
        log.notice("a teammate goes out to its window")
        figure.travel(to: seat.point, window: seat.window, panels: panels) { [weak self] in self?.landed(id) }
        return true
    }

    private func follower(for id: UUID, _ key: ArisWindowKey) -> ArisWindowFollower {
        ArisWindowFollower(pid: key.pid, windowNumber: key.number) { [weak self] frame in self?.windowChanged(id, frame) }
    }

    /// It landed: ArisCast says what comes next (a second glide, a step to where the window went, the end of its job,
    /// or the bubble).
    private func landed(_ id: UUID) {
        guard let figure = figures[id] else { return }
        let pending = figure.pendingPerch
        figure.pendingPerch = nil
        let move = pending.flatMap { p in figure.perch.map { hypot(p.point.x - $0.x, p.point.y - $0.y) } }
        for step in cast.landed(id, pendingMove: move) {
            switch step {
            case .glideAgain:
                guard let pending else { continue }
                figure.travel(to: pending.point, window: pending.window, panels: panels) { [weak self] in self?.landed(id) }
            case .sit:
                if let pending { figure.sit(at: pending.point, window: pending.window, panels: panels) }
            case .end:
                finishOnWindow(id, figure, figure.ending ?? .cancelled)
            case .showBubble:
                figure.showBubble(panels: panels, reveal: true)
            }
        }
    }

    /// The follower saw the window move or go. It may call inside a system callout: moving is done here and now, going
    /// waits for the next turn (the follower is never released inside its own callback).
    private func windowChanged(_ id: UUID, _ frame: CGRect?) {
        guard let figure = figures[id], cast.phase(of: id) != .returning else { return }
        switch ArisCharacterDirector.react(frame.map { .windowMoved($0) } ?? .windowGone) {
        case .follow(let cg):
            guard let seat = perch(on: cg, titleBar: figure.titleBarHeight) else {
                DispatchQueue.main.async { [weak self] in self?.windowGone(id) }
                return
            }
            if figure.travelling { figure.pendingPerch = seat } else { figure.sit(at: seat.point, window: seat.window, panels: panels) }
        case .goToNotchSlot:
            DispatchQueue.main.async { [weak self] in self?.windowGone(id) }
        default:
            break
        }
    }

    /// Closed: the slot for good. Out of sight: parked in the slot until it shows. Still there after all: sit again.
    private func windowGone(_ id: UUID) {
        guard let figure = figures[id], cast.phase(of: id) != .returning, let key = windows[id] else { return }
        let presence = Self.presence(key.pid, key.number)
        switch ArisCharacterDirector.whenGone(presence) {
        case .stay:
            guard case .onScreen(let cg) = presence, let seat = perch(on: cg, titleBar: figure.titleBarHeight) else { return }
            figure.follower = follower(for: id, key)
            if figure.travelling { figure.pendingPerch = seat } else { figure.sit(at: seat.point, window: seat.window, panels: panels) }
        case .park:
            log.notice("a teammate's window is out of sight: parked in the slot")
            park(id)
            sendHome(id, after: 0)
        case .lose:
            log.notice("a teammate's window closed: back to the slot")
            lost.insert(id)
            sendHome(id, after: 0)
            DispatchQueue.main.async { [weak self] in self?.onWindowClosed?(id) }
        }
    }

    // MARK: parked

    private func park(_ id: UUID) {
        parked.insert(id)
        if parkWatch == nil { parkWatch = ArisParkWatch { [weak self] in self?.recheckParked(force: true) } }
    }

    /// A parked window that shows again lets its teammate go out again. Checked on a Space change, an app unhiding or
    /// activating (the watch, only while something is parked), and at most every 2 s as the jobs change.
    private func recheckParked(force: Bool) {
        guard !parked.isEmpty else { return }
        guard force || Date().timeIntervalSince(parkChecked) >= Self.retry else { return }
        parkChecked = Date()
        let live = Set(jobs.filter { !$0.isFinished }.map(\.id))
        for id in parked {
            guard live.contains(id), let key = windows[id] else {
                parked.remove(id)
                continue
            }
            switch Self.presence(key.pid, key.number) {
            case .onScreen: parked.remove(id)
            case .offScreen: break
            case .closed:
                parked.remove(id)
                lost.insert(id)
                DispatchQueue.main.async { [weak self] in self?.onWindowClosed?(id) }
            }
        }
        if parked.isEmpty { parkWatch = nil }
        if force { restage() }
    }

    // MARK: coming home

    /// The job ended: now if it sits, on landing if it's on its way (ArisCast).
    private func end(_ job: ArisJob, _ figure: ArisFigure) {
        switch cast.end(job.id) {
        case .now: finishOnWindow(job.id, figure, job.state)
        case .onLanding: figure.ending = job.state
        case .ignored: break
        }
    }

    /// "끝났어요" (and the poke) or "못 끝냈어요" on the window, then home; cancelled goes straight home.
    private func finishOnWindow(_ id: UUID, _ figure: ArisFigure, _ state: ArisJobState) {
        switch state {
        case .done:
            figure.celebrate()
            figure.showBubble(panels: panels, reveal: false)
            sendHome(id, after: ArisCharacterDirector.celebrate)
        case .failed:
            figure.model.mood = "default"
            figure.say(ArisBubbleText.text(for: state, korean: figure.model.korean), tone: .failed)
            figure.showBubble(panels: panels, reveal: false)
            sendHome(id, after: ArisCharacterDirector.failHold)
        default:
            sendHome(id, after: 0)
        }
    }

    /// After `delay`, the bubble tucks away and the teammate glides home and merges into the notch.
    private func sendHome(_ id: UUID, after delay: TimeInterval) {
        guard let figure = figures[id] else { return }
        cast.goHome(id)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak figure] in
            guard let self, let figure, self.figures[id] === figure else { return }
            figure.follower?.stop()
            figure.follower = nil
            if figure.travelling { figure.stopTravel() }
            figure.travel(to: Self.home(), window: nil, panels: self.panels) { [weak self, weak figure] in
                figure?.merge { [weak self] in self?.gone(id) }
            }
        }
    }

    private func gone(_ id: UUID) {
        figures[id] = nil
        cast.home(id)
        restage()
    }

    // MARK: displays

    /// The panels were rebuilt (a display came, went or moved): every view they held is out of them. Teammates whose
    /// window is still on a display sit on it again; the others go home at once (no trip over a display that's gone).
    private func screensChanged() {
        for (id, figure) in figures {
            if figure.travelling { figure.stopTravel() }
            let presence = Self.presence(figure.pid, figure.windowNumber)
            var seat: (point: CGPoint, window: CGRect)?
            if case .onScreen(let cg) = presence { seat = perch(on: cg, titleBar: figure.titleBarHeight) }
            let reperch = cast.phase(of: id) != .returning
                && ArisCharacterDirector.react(.screensChanged(perchStillValid: seat != nil)) == .reperch
            if reperch, let seat {
                figure.sit(at: seat.point, window: seat.window, panels: panels)
                figure.showBubble(panels: panels, reveal: false)
                continue
            }
            if cast.phase(of: id) != .returning {
                log.notice("a teammate's display went: home")
                if ArisCharacterDirector.whenGone(presence) == .park { park(id) } else { lost.insert(id) }
            }
            figure.removeNow()
            figures[id] = nil
            cast.home(id)
        }
        restage()
    }

    // MARK: pieces

    /// The overlay panels close once nobody has been out for a while (only when there are panels to close).
    private func scheduleIdleTeardown() {
        guard figures.isEmpty else {
            idleTeardown?.cancel()
            idleTeardown = nil
            return
        }
        guard idleTeardown == nil, panels.isBuilt else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.idleTeardown = nil
            if self.figures.isEmpty { self.panels.tearDown() }
        }
        idleTeardown = work
        DispatchQueue.main.asyncAfter(deadline: .now() + ArisCharacterDirector.panelsIdle, execute: work)
    }

    /// Who works on `job`, for the pill's face slot.
    private func mate(_ job: ArisJob) -> SlotMate {
        let aris = if case .clone = job.assignee { true } else { false }
        return SlotMate(id: job.id, look: look(of: job), name: name(of: job), aris: aris)
    }

    /// A clone is Aris's star; a teammate has its own character (the same one the 한 일 tab shows); a helper a default
    /// face (ArisHelpers).
    private func look(of job: ArisJob) -> ArisCharacterLook {
        switch job.assignee {
        case .clone: .main
        case .teammate(let id):
            if let mate = ArisAdDemoRoster.mate(id) { ArisFace.shown(mate.look, name: mate.name, aris: .main) }
            else { ArisTeamModel.shared.look(teammateId: id, name: name(of: job) ?? id) }
        case .helper(let index): ArisHelpers.look(index, teammates: ArisTeamModel.shared.teammates, aris: .main)
        }
    }

    /// A teammate's name as the user gave it (ArisTeamModel); Claude Code's seed until the list is in; any other its id.
    private func name(of job: ArisJob) -> String? {
        switch job.assignee {
        case .clone: nil
        case .teammate(let id):
            ArisAdDemoRoster.mate(id)?.name ?? (ArisTeamModel.shared.teammates + [ArisTeammate.claudeCode]).first { $0.id == id }?.name ?? id
        case .helper(let index): ArisHelpers.name(index)
        }
    }

    /// Asks for the look's atlases (at `screen`'s scale) as soon as the job exists, so the character shows at once
    /// and its first trip turns to face its way (Task 9: the facing grid bakes on demand).
    private func prefetch(_ look: ArisCharacterLook, on screen: NSScreen?) {
        let scale = min(2, screen?.backingScaleFactor ?? 2)
        let sprite = ArisSpriteLook(type: look.type, colorHex: look.colorHex, shading: look.shading,
                                    size: ArisSpriteLook.bakeSize(ArisCharacterDirector.perchSize), scale: scale, dark: true)
        for clip in [ArisSpriteClip.still, .working, .idle, .facing] { _ = ArisSpriteStore.shared.sheet(sprite, clip) }
    }

    /// Where a job's window is: an ad demo's stand-in window (ArisAdDemoRoster) is always on screen, at its place.
    private static func presence(_ pid: Int32, _ number: Int) -> ArisWindowPresence {
        if let standIn = ArisAdDemoRoster.fixedWindow(pid: pid, number: number) { return .onScreen(standIn) }
        return ArisWindowLocator.presence(pid: pid, windowNumber: number)
    }

    /// The display the notch is on (the owner's pick in Settings), else the one with a camera housing, else the main one.
    private static func homeScreen() -> NSScreen? {
        // An ad demo's teammates leave from the notch on the built-in display, whatever display the owner picked.
        if let demo = ArisAdDemoRoster.notchScreen() { return demo }
        let chosen = ArisNotchNavigation.shared.selectedScreenUUID
        return NSScreen.screens.first { $0.displayUUID == chosen } ?? NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
            ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// Under the notch (or the menu bar, on a display without one): where teammates leave from and merge back into.
    private static func home() -> CGPoint {
        guard let screen = homeScreen() else { return .zero }
        let top = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : screen.frame.maxY - screen.visibleFrame.maxY
        return ArisCharacterDirector.home(screen: screen.frame, topInset: top, size: ArisCharacterDirector.perchSize)
    }
}

/// While a teammate is parked: a Space change, an app unhiding or activating asks the director to look again. Exists
/// only while something is parked; its observers go when it does (not an actor, so its deinit may remove them).
private final class ArisParkWatch {
    private var observers: [NSObjectProtocol] = []

    init(_ recheck: @escaping @MainActor @Sendable () -> Void) {
        let center = NSWorkspace.shared.notificationCenter
        let names = [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didUnhideApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification]
        observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { _ in MainActor.assumeIsolated { recheck() } }
        }
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
    }
}
