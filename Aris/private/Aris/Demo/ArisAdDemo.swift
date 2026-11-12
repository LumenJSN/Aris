//
//  ArisAdDemo.swift
//  Aris
//
//  Plays the ad's scripted demos (ArisAdDemoScript) through the real notch, status pill, teammate figures, dictation
//  card and ink, from ArisPreview's states:
//  - `team-demo` / `team-demo:off`: the prompt card, then Claude Code and a demo teammate 코디 (in memory only, never in
//    the teammates file) leave the notch, perch on windows (ArisDirector, ArisFigure, ArisTravel as for any job), cycle
//    their steps, say 끝났어요 and come home; the pill says "2개 작업 중", then 끝났어요. Their jobs live only in the
//    controller's list for the demo: no job runs, nothing reaches aris-agent or the history.
//  - `dictation-demo:<text>` / `:off`: the right-⌥ card with a made-up voice level (no microphone), the words coming in
//    one by one, tidied and shown as typed. Nothing is typed anywhere, and ⌃⌘V has nothing to type again.
//  - `circle-demo[:x,y,w,h]` / `:off`: the real ink overlay draws a scripted loop (the cursor never moves, the screen is
//    never captured), then the notch answers "이거 뭐야?" with a written answer, in the answer layout, with no AI.
//  Nothing is kept: `:off`, side-close or quitting puts everything back. A demo never takes the notch from a real turn,
//  and stops writing to it the moment anything else does.
//

import AppKit
import os
import QuartzCore

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "preview")

/// The demo's teammates and stand-in windows, read by ArisDirector. In memory only.
@MainActor
enum ArisAdDemoRoster {
    private(set) static var mates: [ArisAdDemoMate] = []
    /// Stand-in windows (CG coordinates), by number: ArisTeamDemoSeats' fixed points.
    private(set) static var fixedWindows: [Int: CGRect] = [:]

    static func mate(_ id: String) -> ArisAdDemoMate? { mates.first { $0.id == id } }

    /// While the demo's teammates are out: the display they leave from and come home to (the built-in notch's).
    static func notchScreen() -> NSScreen? { mates.isEmpty ? nil : ArisAdDemo.notchScreen() }

    static func fixedWindow(pid: Int32, number: Int) -> CGRect? {
        ArisTeamDemoSeats.isFixed(pid: pid, number: number) ? fixedWindows[number] : nil
    }

    fileprivate static func set(mates: [ArisAdDemoMate], windows: [Int: CGRect]) {
        self.mates = mates
        fixedWindows = windows
    }
}

@MainActor
final class ArisAdDemo {
    static let shared = ArisAdDemo()

    private var board = ArisAdDemoBoard()
    private var runs: [ArisAdDemoKind: Task<Void, Never>] = [:]
    /// The demo whose words are on the notch, and the session it last put there: it writes again only over that one.
    private var owner: ArisAdDemoKind?
    private var shown: ArisSession?
    /// The dictation stage the demo set.
    private var stage: ArisDictationStage?
    private var voice: Timer?
    /// team-demo's jobs, in ArisTeamDemoScript.jobs' order.
    private var jobIds: [UUID] = []
    private var gesture: ArisGestureController?

    private var aris: ArisController { .shared }

    // MARK: switching

    /// Applies a demo state; the line ArisPreview reports.
    func handle(_ command: ArisAdDemoCommand) -> String {
        let kind = command.kind
        if case .off = command {
            stop(kind)
            return "\(kind.rawValue)-demo off"
        }
        // Never over a real turn, dictation or training (a demo's own may be replaced).
        let ours = owner != nil && aris.session == shown
        guard aris.training == nil, (aris.session.phase == .idle && aris.dictation == nil) || ours else {
            return "\(kind.rawValue)-demo skipped: Aris is busy"
        }
        for running in board.start(kind) { stop(running, keepBoard: true) }
        stop(kind, keepBoard: true)
        switch command {
        case .team: return playTeam()
        case .dictation(let text): return playDictation(text)
        case .circle(let rect): return playCircle(rect)
        case .off: return ""
        }
    }

    /// side-close and quitting: every demo stops and takes its state with it.
    func stopAll() {
        for kind in board.stopAll() { stop(kind, keepBoard: true) }
        for kind in ArisAdDemoKind.allCases { stop(kind, keepBoard: true) }
    }

    /// Stops `kind` and undoes what it put up (safe to call when it already ended or never ran).
    private func stop(_ kind: ArisAdDemoKind, keepBoard: Bool = false) {
        if !keepBoard { _ = board.stop(kind) }
        runs[kind]?.cancel()
        runs[kind] = nil
        switch kind {
        case .team: clearTeam()
        case .dictation: break
        case .circle:
            gesture?.cancel()
            gesture = nil
        }
        guard owner == kind else { return }
        setVoice(false)
        if aris.session == shown { aris.session = ArisSession() }
        if let stage, aris.dictation == stage { aris.dictation = nil }
        owner = nil
        shown = nil
        stage = nil
    }

    /// Runs `cues` in order on their times; `apply` false stops the demo.
    private func play<Step>(_ kind: ArisAdDemoKind, _ cues: [ArisAdDemoCue<Step>], _ apply: @escaping (Step) -> Bool) {
        runs[kind] = Task { @MainActor [weak self] in
            let start = ContinuousClock.now
            for cue in cues {
                do { try await Task.sleep(until: start + .milliseconds(Int(cue.at * 1000)), clock: .continuous) } catch { return }
                guard let self, !Task.isCancelled, self.board.running.contains(kind) else { return }
                guard apply(cue.step) else {
                    log.notice("\(kind.rawValue, privacy: .public) demo stopped: the notch was taken")
                    return self.stop(kind)
                }
            }
            guard let self else { return }
            self.runs[kind] = nil
            _ = self.board.stop(kind)
        }
    }

    // MARK: the notch

    /// Puts `next` up when the notch still shows what the demo put there (or nothing, for its first). False otherwise.
    private func show(_ kind: ArisAdDemoKind, _ next: (ArisSession) -> ArisSession) -> Bool {
        if owner == kind, let shown {
            guard aris.session == shown else { return false }
        } else {
            guard owner == nil, aris.session.phase == .idle else { return false }
            owner = kind
        }
        let session = next(aris.session)
        aris.session = session
        shown = session
        return true
    }

    /// A voice-like level for the bars (ArisPreview's), never the microphone.
    private func setVoice(_ on: Bool) {
        voice?.invalidate()
        voice = nil
        aris.level = 0
        guard on else { return }
        let start = Date()
        voice = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            MainActor.assumeIsolated {
                let t = Date().timeIntervalSince(start)
                let syllables = abs(sin(t * 9)) * (0.6 + 0.4 * sin(t * 1.7))
                ArisController.shared.level = Float(0.15 + 0.75 * syllables)
            }
        }
    }

    // MARK: team-demo

    private func playTeam() -> String {
        let seats = Self.teamSeats()
        play(.team, ArisTeamDemoScript.cues()) { [weak self] step in self?.team(step, seats: seats) ?? false }
        let real = seats.filter { if case .window = $0 { true } else { false } }.count
        return "team-demo on: \(real) real window(s), \(seats.count - real) fixed point(s)"
    }

    private func team(_ step: ArisTeamDemoStep, seats: [ArisTeamDemoSeats.Seat]) -> Bool {
        switch step {
        case .listen:
            guard show(.team, { _ in ArisSession().listening() }) else { return false }
            setVoice(true)
        case .hear(let words):
            return show(.team) { $0.hearing(words) }
        case .think:
            setVoice(false)
            return show(.team) { $0.thinking() }
        case .dispatch:
            dispatchTeam(seats)
        case .reply(let line):
            // The turn may be gone (taken by a real one): the jobs go on, the notch isn't touched again.
            _ = show(.team) { $0.answering(line) }
        case .progress(let job, let text):
            setJob(job, .running(step: text))
        case .finish(let job):
            setJob(job, .done(ArisTeamDemoScript.jobs[job].result))
            aris.flashTaskDone()
        case .closeTurn:
            _ = show(.team) { $0.done() }
        case .clear:
            clearTeam()
        }
        return true
    }

    /// The two jobs, as dispatch makes them (queued, then started), each on its seat's window.
    private func dispatchTeam(_ seats: [ArisTeamDemoSeats.Seat]) {
        var fixed: [Int: CGRect] = [:]
        let made = zip(ArisTeamDemoScript.jobs, seats).map { job, seat -> ArisJob in
            let target: ArisJobTarget
            switch seat {
            case .window(let pid, let number): target = .window(pid: pid, windowNumber: number)
            case .fixed(let number, let frame):
                fixed[number] = frame
                target = .window(pid: ArisTeamDemoSeats.fixedPid, windowNumber: number)
            }
            return ArisJob(id: UUID(), title: job.title, prompt: "", assignee: .teammate(job.teammate), cwd: nil, appHint: nil,
                           target: target, state: .queued, created: Date())
        }
        ArisAdDemoRoster.set(mates: [ArisTeamDemoScript.kodi], windows: fixed)
        // Before the jobs: the figures go out the moment they're listed, into panels the recording sees.
        aris.director.showInCaptures(true)
        jobIds = made.map(\.id)
        aris.jobs += made
        for index in made.indices { setJob(index, .running(step: "")) }
    }

    /// A demo job's new state (never over a cancel: a click on its row may stop it like any job).
    private func setJob(_ index: Int, _ state: ArisJobState) {
        guard jobIds.indices.contains(index) else { return }
        let id = jobIds[index]
        aris.jobs = aris.jobs.map { job in
            guard job.id == id, job.state != .cancelled else { return job }
            var changed = job
            changed.state = state
            return changed
        }
    }

    /// The demo's jobs leave the list (their figures go home), with its teammate and stand-in windows.
    private func clearTeam() {
        if !jobIds.isEmpty {
            let ids = Set(jobIds)
            aris.jobs = aris.jobs.filter { !ids.contains($0.id) }
            aris.seenDone.subtract(ids)
            jobIds = []
        }
        ArisAdDemoRoster.set(mates: [], windows: [:])
        aris.director.showInCaptures(false)
    }

    /// Two seats on the notch's display: windows on screen (only their numbers, owners and frames are read), else fixed
    /// points.
    private static func teamSeats() -> [ArisTeamDemoSeats.Seat] {
        let screen = notchScreen()
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let frame = screen.map { CGRect(x: $0.frame.minX, y: primaryHeight - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height) }
            ?? .zero
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let windows = list.compactMap { info -> ArisTeamDemoSeats.Window? in
            guard let number = info[kCGWindowNumber as String] as? Int, let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  info[kCGWindowLayer as String] as? Int == 0, (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            return .init(pid: pid, number: number, bundleId: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier, frame: rect)
        }
        return ArisTeamDemoSeats.pick(windows, screen: frame, own: ProcessInfo.processInfo.processIdentifier)
    }

    /// The display every demo plays on: the built-in one with the notch (ArisAdDemoDisplay), not another one attached.
    static func notchScreen() -> NSScreen? {
        let chosen = ArisNotchNavigation.shared.selectedScreenUUID
        let screens = NSScreen.screens
        let index = ArisAdDemoDisplay.pick(screens.map { screen in
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            return .init(notch: screen.safeAreaInsets.top > 0, builtIn: id.map { CGDisplayIsBuiltin($0) != 0 } ?? false,
                         selected: screen.displayUUID == chosen, main: screen == NSScreen.main)
        })
        return index.map { screens[$0] }
    }

    // MARK: dictation-demo

    private func playDictation(_ text: String) -> String {
        play(.dictation, ArisDictationDemoScript.cues(text)) { [weak self] step in self?.dictation(step) ?? false }
        return "dictation-demo on: \(text.split(whereSeparator: \.isWhitespace).count) word(s)"
    }

    private func dictation(_ step: ArisDictationDemoStep) -> Bool {
        if step != .listen, aris.dictation != stage { return false }
        switch step {
        case .listen:
            guard aris.dictation == nil, show(.dictation, { _ in ArisSession().listening() }) else { return false }
            setStage(.listening)
            setVoice(true)
            // A real dictation keeps the notch closed (its words go where the cursor is); the ad shows its card, so the
            // demo opens the notch on the built-in display, as a hover would. It closes at once when the card goes.
            ArisPreview.shared.notch?(true)
        case .hear(let words):
            return show(.dictation) { $0.hearing(words) }
        case .clean(let words):
            setVoice(false)
            ArisController.heardSound?.play()
            setStage(.cleaning(ArisDictationCleaner.marked(words)))
            return show(.dictation) { $0.hearing(words).thinking() }
        case .typed(let words):
            setStage(.typed)
            return show(.dictation) { $0.answering(words) }
        case .close:
            // Idle again: the controller lets the card go (and the notch closes at once, as after any dictation).
            let ok = show(.dictation) { $0.done() }
            stage = nil
            return ok
        }
        return true
    }

    private func setStage(_ next: ArisDictationStage) {
        aris.dictation = next
        stage = next
    }

    // MARK: circle-demo

    private func playCircle(_ rect: CGRect?) -> String {
        guard let screen = Self.notchScreen() else { return "circle-demo skipped: no display" }
        let area = rect ?? ArisCircleDemoScript.defaultRect(display: screen.frame.size)
        let path = ArisCirclePath(rect: area, screen: screen.frame)
        play(.circle, ArisCircleDemoScript.cues()) { [weak self] step in self?.circle(step, path: path) ?? false }
        return "circle-demo on: \(Int(area.minX)),\(Int(area.minY)) \(Int(area.width))x\(Int(area.height))"
    }

    private func circle(_ step: ArisCircleDemoStep, path: ArisCirclePath) -> Bool {
        switch step {
        case .begin:
            guard show(.circle, { _ in ArisSession().listening() }) else { return false }
            setVoice(true)
            // The live world, but the pen is the script's and no button is ever down; hands-free, so the ink takes no click.
            var environment = ArisGestureController.Environment.live
            let started = CACurrentMediaTime()
            environment.pointer = { path.point(at: CACurrentMediaTime() - started) }
            environment.buttonDown = { false }
            environment.samples = nil
            environment.sampling = { _ in }
            environment.shownInCaptures = true
            let controller = ArisGestureController(capturer: ArisAdDemoCapture(), environment: environment)
            gesture = controller
            controller.keyDown()
            controller.tap()
        case .hear(let words):
            return show(.circle) { $0.hearing(words) }
        case .end:
            gesture?.handsFreeEnd()
            gesture = nil
            setVoice(false)
            return show(.circle) { $0.thinking() }
        case .work(let status):
            return show(.circle) { $0.working(status) }
        case .write(let text), .final(let text):
            return show(.circle) { $0.answering(text) }
        case .close:
            return show(.circle) { $0.done() }
        }
        return true
    }
}
