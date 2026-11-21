//
//  ArisPermissionCenter.swift
//  Aris
//
//  Where features ask for a permission (`require(.feature)`), on top of the pure ArisPermissions: a card with the
//  feature's reason before macOS asks, once; a refusal told once with its pane's button; a feature that does without
//  after that. What macOS says is read again when Aris becomes the active app and every second while a pane Aris
//  opened is in front, so a switch turned on in System Settings counts without a relaunch where macOS allows it; where
//  it does not (Screen Recording), one card offers to reopen Aris. What was asked and told is kept across launches.
//  Nothing is asked at launch: `start` only reads.
//

import AppKit
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "permissions")

@MainActor
final class ArisPermissionCenter {
    static let shared = ArisPermissionCenter()
    static let savedKey = "arisPermissionRecords"

    private(set) var model: ArisPermissions
    /// What changed at a reading (the setup's list follows it).
    var onChange: (ArisPermissionChange) -> Void = { _ in }

    private let checker: ArisPermissionChecking
    private let defaults: UserDefaults
    private var watch = ArisPaneWatch()
    private var poll: Timer?
    private var activation: NSObjectProtocol?

    /// The permissions read at activation: every one macOS can answer for the app without asking.
    static let watched: [ArisPermissionKey] = ArisPermission.allCases.filter { $0 != .automation && $0.ask != .onUse }.map(ArisPermissionKey.init)

    private init(checker: ArisPermissionChecking = ArisPermissionsLive(), defaults: UserDefaults = .standard) {
        self.checker = checker
        self.defaults = defaults
        model = ArisPermissions.restored(from: defaults.data(forKey: Self.savedKey))
    }

    /// At launch: read, and read again whenever Aris comes to the front. Asks nothing.
    func start() {
        guard activation == nil else { return }
        // The screen lines of the circle and the per-turn shot are told once across launches, like every other.
        let screen = ArisPermissionKey(.screenRecording)
        ArisScreenPermissionNotice.shownBefore = { line in
            let record = ArisPermissionCenter.shared.model.record(screen)
            return line == .permission ? record.toldOffAt != nil : record.relaunchOfferedAt != nil
        }
        ArisScreenPermissionNotice.noteShown = { line in
            let center = ArisPermissionCenter.shared
            center.set(line == .permission ? center.model.notingToldOff(screen) : center.model.notingRelaunchOffered(screen))
        }
        activation = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Task { await ArisPermissionCenter.shared.refresh() } }
        }
        Task { await refresh() }
    }

    /// Reads `keys` (every watched one, and the Automation targets asked before) and acts on what changed.
    func refresh(_ keys: [ArisPermissionKey]? = nil) async {
        let asked = model.records.keys.filter { $0.permission == .automation }
        var readings: [(ArisPermissionKey, ArisPermissionReading)] = []
        for key in keys ?? (Self.watched + asked) { readings.append((key, await checker.reading(key))) }
        let (next, changes) = model.updating(readings)
        set(next)
        for change in changes { handle(change) }
    }

    // MARK: - A feature's question

    /// Whether `feature` may go ahead now. Asks macOS only when the feature is used and the permission was never
    /// asked; says why first; says a refusal once. False: the feature does without (and says so in its own words).
    @discardableResult
    func require(_ feature: ArisPermissionFeature) async -> Bool {
        await refresh(model.keys(for: feature))
        while true {
            let (next, decision) = model.require(feature, english: ArisUIWords.english)
            set(next)
            log.notice("require \(feature.rawValue, privacy: .public): \(String(describing: decision), privacy: .public)")
            switch decision {
            case .proceed:
                return true
            case .prompt(let key, let reason):
                // In a turn, the reason and that the turn waits are shown in the turn itself, where the user looks: a card
                // under the notch waits for the turn to end (VM run 2026-11-19, A3: the line was only logged and spoken).
                let inTurn = ArisController.shared.showPermissionWait(key, reason: reason)
                if !inTurn { say(decision) }
                _ = await checker.prompt(key)
                await refresh([key])
                if inTurn { ArisController.shared.endPermissionWait() }
                // Granted: on to the next permission the feature needs; refused: the next turn of the loop tells it.
                if model.state(key) != .granted { return false }
            case .openPane(let key, _, _):
                say(decision)
                openPane(key.permission)
                return false
            case .proceedAfterSaying:
                say(decision)
                return true
            case .tellOff, .offerRelaunch:
                say(decision)
                return false
            case .doWithout:
                return false
            }
        }
    }

    /// Whether `feature` has what it needs, as last read (never asks, never tells).
    func ready(_ feature: ArisPermissionFeature) -> Bool { model.ready(feature) }

    // MARK: - Panes and relaunch

    /// Opens the pane for `permission` (the drag panel for Accessibility and Screen Recording) and watches its switch.
    func openPane(_ permission: ArisPermission) {
        switch permission {
        case .accessibility: ArisPermissionGuide.shared.show(.accessibility)
        case .screenRecording: ArisPermissionGuide.shared.show(.screen)
        default: Task { await checker.open(link: permission.paneLink) }
        }
        watch = watch.opened(ArisPermissionKey(permission), at: Date())
        startPolling()
    }

    /// The one "reopen" card for `permission`, when `feature` needs it and only a new process can use it (read again
    /// first). Once per grant (ArisPermissions.require); anything else that decision would say is left unsaid.
    func offerRelaunch(_ permission: ArisPermission, for feature: ArisPermissionFeature) {
        let key = ArisPermissionKey(permission)
        Task {
            await refresh([key])
            let (next, decision) = model.require(key, for: feature, english: ArisUIWords.english)
            guard case .offerRelaunch = decision else { return }
            log.notice("relaunch offered: \(permission.rawValue, privacy: .public) for \(feature.rawValue, privacy: .public)")
            set(next)
            say(decision)
        }
    }

    /// Quit and open again (a switch only a new process sees). What was asked is saved first.
    func relaunch() {
        save()
        ApplicationRelauncher.restart()
    }

    // MARK: - Inside

    private func startPolling() {
        guard poll == nil else { return }
        poll = Timer.scheduledTimer(withTimeInterval: ArisPaneWatch.interval, repeats: true) { _ in
            MainActor.assumeIsolated { Task { await ArisPermissionCenter.shared.pollPanes() } }
        }
    }

    private func pollPanes() async {
        let (due, next) = watch.due(at: Date(), in: model)
        watch = next
        guard !due.isEmpty else {
            poll?.invalidate()
            poll = nil
            return
        }
        await refresh(due)
    }

    private func handle(_ change: ArisPermissionChange) {
        log.notice("changed: \(String(describing: change), privacy: .public)")
        onChange(change)
        // On now: its "it is off" card (or the reason card left from the ask) goes at once.
        if let key = ArisPermissionNotice.withdrawn(by: change) { ArisNoticeCenter.shared.withdraw(key: key) }
        // Key access given (or given but needing a reopen): the dictation and gesture keys look again now, not at the
        // next launch (VM run 2026-11-18, D1).
        if Self.wakesKeyTaps(change) { ArisKeyTaps.startWhenAllowed() }
        // The setup handles its own Quit & Reopen (it resumes where it was): no second offer over it.
        guard case .relaunchNeeded(let key) = change, !ArisOnboardingGuide.shared.showing,
              let feature = ArisPermissionFeature.allCases.first(where: { $0.needs.contains(key.permission) }) else { return }
        let (next, decision) = model.require(key, for: feature, english: ArisUIWords.english)
        set(next)
        say(decision)
    }

    /// A change that may let the key taps start: Accessibility or Input Monitoring turned on.
    static func wakesKeyTaps(_ change: ArisPermissionChange) -> Bool {
        switch change {
        case .granted(let key), .relaunchNeeded(let key): [.accessibility, .inputMonitoring].contains(key.permission)
        default: false
        }
    }

    private func say(_ decision: ArisPermissionDecision) {
        guard let card = ArisPermissionNotice.notice(for: decision, english: ArisUIWords.english) else { return }
        Task { _ = await ArisController.shared.notify(card) }
    }

    private func set(_ next: ArisPermissions) {
        guard next != model else { return }
        let recordsChanged = next.records != model.records
        model = next
        if recordsChanged { save() }
    }

    private func save() { defaults.set(model.saved, forKey: Self.savedKey) }
}
