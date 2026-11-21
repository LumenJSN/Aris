//
//  ArisWorld+Sources.swift
//  Aris
//
//  One observer per source, owned by ArisWorld. System notices (the front app, the lock, sleep, the displays) are
//  observed on the main queue, as the features' own observers were, so a subscriber hears each one at the same moment
//  it used to. Sources that live in other singletons (Now Playing, the calendar, deadlines, jobs, Claude Code's hooks,
//  Aris's own voice) are read from their published values after the controller exists.
//

import AppKit
import Combine
import CoreGraphics
import Foundation

extension ArisWorld {
    // MARK: - The system

    func startSystemSources() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { world, note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            world.note(.frontApp(app.map(Self.app) ?? NSWorkspace.shared.frontmostApplication.map(Self.app)))
        }
        observe(workspace, NSWorkspace.willSleepNotification) { world, _ in world.note(.systemWillSleep) }
        observe(workspace, NSWorkspace.didWakeNotification) { world, _ in world.note(.systemDidWake) }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { world, _ in world.note(.displaysAsleep(true)) }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { world, _ in world.note(.displaysAsleep(false)) }
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { world, _ in world.note(.screenLocked(true)) }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { world, _ in world.note(.screenLocked(false)) }
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { world, _ in
            world.note(.displays(Self.displays()))
        }
        // As things are now, without publishing: nothing changed yet.
        var now = snapshot
        now.frontApp = NSWorkspace.shared.frontmostApplication.map(Self.app)
        now.locked = Self.sessionLocked()
        now.displaysAsleep = CGDisplayIsAsleep(CGMainDisplayID()) != 0
        now.displays = Self.displays()
        seed(now)
        audio = ArisWorldAudio(world: self)
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ action: @escaping @MainActor (ArisWorld, Notification) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated { if let self { action(self, note) } }
        }
        tokens.append((center, token))
    }

    static func app(_ app: NSRunningApplication) -> ArisWorldSnapshot.App {
        .init(name: app.localizedName, bundleID: app.bundleIdentifier, pid: app.processIdentifier)
    }

    static func sessionLocked() -> Bool {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    static func displays() -> [ArisWorldSnapshot.Display] {
        NSScreen.screens.compactMap { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map {
                ArisWorldSnapshot.Display(id: $0.uint32Value, builtIn: CGDisplayIsBuiltin($0.uint32Value) != 0)
            }
        }
    }

    // MARK: - Aris and the other stores

    func startAppSources(_ aris: ArisController) {
        let main = DispatchQueue.main
        // @Published emits on willSet: each sink reads the value it was handed, never the property.
        watches.append(ArisNowPlaying.shared.$isPlaying.removeDuplicates().receive(on: main)
            .sink { [weak self] playing in MainActor.assumeIsolated { self?.note(.otherAudio(playing)) } })
        watches.append(aris.$session.map { $0.phase == .speaking }.removeDuplicates().receive(on: main)
            .sink { [weak self] speaking in MainActor.assumeIsolated { self?.note(.arisSpeaking(speaking)) } })
        watches.append(aris.$jobs.receive(on: main)
            .sink { [weak self] jobs in MainActor.assumeIsolated { self?.note(Self.work(jobs)) } })
        let todos = ArisTodoModel.shared
        watches.append(Publishers.CombineLatest(todos.$due, todos.$items).receive(on: main)
            .sink { [weak self] due, items in MainActor.assumeIsolated { self?.note(.deadlines(Self.deadlines(due: due, items: items))) } })
        watches.append(ArisCalendarStore.shared.$revision.receive(on: main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.readCalendar() } })
    }

    /// Claude Code's hook events: the store's one slot is the world's, and the teammate watch subscribes here. Taken
    /// at once (as the teammate watch took it), so no event comes before it. The whole event is `lastHook` while its
    /// subscribers hear of it.
    func startHooks() {
        ClaudeStore.shared.onEvent = { [weak self] event, now in
            guard let self else { return }
            self.lastHook = event
            defer { self.lastHook = nil }
            self.note(.claude(.init(name: event.name, sessionId: event.sessionId, at: now)))
        }
    }

    /// The jobs still running, and the teammates working on them.
    static func work(_ jobs: [ArisJob]) -> ArisWorldChange {
        let open = jobs.filter { !$0.isFinished }
        let teammates = open.compactMap { job -> String? in
            if case .teammate(let name) = job.assignee { return name }
            return nil
        }
        var seen = Set<String>()
        return .work(jobs: open.count, teammates: teammates.filter { seen.insert($0).inserted })
    }

    /// Canvas deadlines and the user's own dated to-dos, as the deadline alerts read them (ArisDeadlineDate).
    static func deadlines(due: [ArisDue], items: [ArisTodoItem]) -> [ArisWorldSnapshot.Deadline] {
        let own = items.compactMap { item in
            item.due.map { ArisWorldSnapshot.Deadline(title: item.title, at: ArisDeadlineDate.deadline($0, hasTime: item.hasTime)) }
        }
        return (due.map { ArisWorldSnapshot.Deadline(title: $0.title, at: $0.at) } + own).sorted { $0.at < $1.at }
    }

    /// Today's and tomorrow's events, read again when the calendar store says it changed (it is never asked for here).
    private func readCalendar() {
        Task { @MainActor [weak self] in
            let events = await ArisCalendarStore.shared.upcomingEvents(days: 2)
            let next = events.filter { $0.end > Date() }.sorted { $0.start < $1.start }.prefix(Self.eventsKept)
            self?.note(.calendar(next.map { .init(start: $0.start, end: $0.end, title: $0.title, allDay: $0.isAllDay) }))
        }
    }

    static let eventsKept = 8

    /// The user's voice, as the wake detector's gate hears it (ArisController.heardVoice).
    func heardVoice(_ talking: Bool) {
        note(.userVoice(talking: talking, at: ProcessInfo.processInfo.systemUptime))
    }

    /// The front window's title, read now (Accessibility, only when Aris already has it; never asked for here).
    func readWindowTitle() -> String? {
        guard AXIsProcessTrusted(), let pid = snapshot.frontApp?.pid else { return nil }
        let app = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success, let window else { return nil }
        var title: CFTypeRef?
        guard CFGetTypeID(window) == AXUIElementGetTypeID(),
              AXUIElementCopyAttributeValue(unsafeBitCast(window, to: AXUIElement.self), kAXTitleAttribute as CFString, &title) == .success else { return nil }
        let text = title as? String
        note(.windowTitle(text))
        return text
    }
}
