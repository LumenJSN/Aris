//
//  ArisUpdater.swift
//  Aris
//
//  Sparkle 2 behind Aris's own notice pill (ArisUpdateRules has the decisions). Only a build ArisUpdatePolicy turns on
//  ever makes an SPUUpdater: every other build has no feed and checks nothing. Sparkle shows no window of its own: its
//  user driver (ArisUpdateDriver) turns each step into the pill's state, and the pill's buttons answer it. With
//  자동으로 업데이트 on, Sparkle downloads in the background and hands over its install-and-relaunch, which runs once
//  Aris has been idle for ArisUpdateIdle.settle. After the relaunch, the new version restarts the helper.
//

import AppKit
import Defaults
import Foundation
import Security
import Sparkle
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "update")

extension Defaults.Keys {
    /// Settings › 정보 › 자동으로 업데이트: download in the background, install when Aris is idle.
    static let arisAutoUpdate = Key<Bool>("arisAutoUpdate", default: true)
}

@MainActor
final class ArisUpdater: NSObject, ObservableObject {
    static let shared = ArisUpdater()

    /// Whether this build updates itself at all (the public build with its feed and key).
    /// Whether this build updates itself at all (the public build with its feed and key, signed for the release
    /// channel: a build made from the public source is never overwritten by an official release).
    let isOn = ArisUpdatePolicy.isOn(bundleId: Bundle.main.bundleIdentifier, info: Bundle.main.infoDictionary ?? [:])
        && ArisUpdatePolicy.signedForRelease(signer: ArisUpdater.ownSigner())
    /// Whether a notch is open (set by the app delegate, which owns the notch windows).
    var notchOpen: () -> Bool = { false }
    @Published private(set) var pill = ArisUpdatePill()

    private var updater: SPUUpdater?
    private var driver: ArisUpdateDriver?
    private var autoWatch: Task<Void, Never>?
    /// The pill's answer to "a new version came out", until 지금 업데이트 or 나중에.
    private var foundReply: ((SPUUserUpdateChoice) -> Void)?
    /// A downloaded update's install-and-relaunch, run once Aris is idle.
    private var pendingInstall: (() -> Void)?
    private var idleWatch: Task<Void, Never>?
    /// The check under way was asked for in Settings.
    private var userInitiated = false
    /// The update's notice keeps one id, so a new progress value redraws it instead of bringing it up again.
    private var noticeID = UUID()
    /// The download's notice was closed with its ✕: it goes on out of sight.
    private var hidden = false
    private var presenting: Task<Void, Never>?
    private var postedProgress: Double?

    var currentVersion: String { Bundle.main.releaseVersionNumber ?? "?" }

    private override init() { super.init() }

    // MARK: - Launch

    func start() {
        guard isOn else { return log.notice("updates: off for this build (no feed, no checks)") }
        afterUpdate()
        let driver = ArisUpdateDriver(owner: self)
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: self)
        updater.automaticallyChecksForUpdates = true
        updater.updateCheckInterval = ArisUpdatePolicy.checkInterval
        updater.automaticallyDownloadsUpdates = Defaults[.arisAutoUpdate]
        do {
            try updater.start()
        } catch {
            return log.error("updates: Sparkle did not start: \(error.localizedDescription, privacy: .public)")
        }
        self.driver = driver
        self.updater = updater
        log.notice("updates: on, version \(self.currentVersion, privacy: .public), automatic \(Defaults[.arisAutoUpdate], privacy: .public)")
        autoWatch = Task { [weak self] in
            for await on in Defaults.updates(.arisAutoUpdate, initial: false) {
                self?.updater?.automaticallyDownloadsUpdates = on
                if !on { self?.dropPendingInstall() }
            }
        }
        // The check at launch, once the notch is up; Sparkle's own schedule does every 24 hours after it.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(ArisUpdatePolicy.firstCheckDelay))
            guard let updater = self?.updater, !updater.sessionInProgress else { return }
            updater.checkForUpdatesInBackground()
        }
    }

    /// The first launch of a new version: the helper still runs the old program (it was replaced under it), so it is
    /// restarted from this app once the install check at launch has run, unless that check restarted it already.
    private func afterUpdate() {
        let defaults = UserDefaults.standard
        let last = defaults.string(forKey: ArisUpdateRelaunch.lastVersionKey)
        defaults.set(currentVersion, forKey: ArisUpdateRelaunch.lastVersionKey)
        guard ArisUpdateRelaunch.restartsHelper(last: last, current: currentVersion) else { return }
        log.notice("updates: now \(self.currentVersion, privacy: .public) (was \(last ?? "-", privacy: .public)): the helper starts again from this version")
        Task {
            let outcome = await ArisHelperInstall.shared.install()
            guard outcome == .running else { return }
            let restarted = await ArisHelperClient.shared.restartArisAgent()
            log.notice("updates: helper restarted after the update: \(restarted, privacy: .public)")
        }
    }

    // MARK: - What Settings and the pill ask

    /// 업데이트 확인.
    func checkNow() {
        guard let updater else { return }
        guard updater.canCheckForUpdates else { return log.notice("updates: a check is under way already") }
        updater.checkForUpdates()
    }

    /// 지금 업데이트.
    func installNow() {
        if let reply = foundReply {
            foundReply = nil
            hidden = false
            log.notice("updates: install now")
            reply(.install)
        } else if let pendingInstall {
            self.pendingInstall = nil
            pendingInstall()
        }
    }

    /// 나중에.
    func later() {
        foundReply?(.dismiss)
        foundReply = nil
        apply(.dismissed)
    }

    /// The update's notice was closed with its ✕.
    func noticeClosed() {
        switch pill.phase {
        case .available: later()
        case .downloading, .installing: hidden = true
        default: pill = ArisUpdatePill()
        }
    }

    // MARK: - From the user driver

    func apply(_ event: ArisUpdatePill.Event) {
        let next = pill.on(event)
        guard next != pill else { return }
        pill = next
        post()
    }

    func checkStarted() {
        userInitiated = true
        apply(.checkStarted(userInitiated: true))
    }

    func found(_ item: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        let version = item.displayVersionString
        let asked = state.userInitiated || userInitiated
        userInitiated = false
        log.notice("updates: \(version, privacy: .public) found (stage \(state.stage.rawValue, privacy: .public), asked \(asked, privacy: .public))")
        if item.isInformationOnlyUpdate { return reply(.dismiss) }
        // Downloaded in the background already: installed once Aris is idle, unless the user asked (then it is offered).
        if state.stage != .notDownloaded, Defaults[.arisAutoUpdate], !asked {
            return installWhenIdle(version: version) { reply(.install) }
        }
        foundReply?(.dismiss)
        foundReply = reply
        apply(.found(version: version))
    }

    func notFound() {
        let asked = userInitiated
        userInitiated = false
        apply(.notFound(userInitiated: asked))
    }

    func failed(_ error: Error) {
        let error = error as NSError
        let why = ArisUpdateFailure.of(domain: error.domain, code: error.code)
        log.error("updates: \(error.domain, privacy: .public) \(error.code, privacy: .public): \(error.localizedDescription, privacy: .public)")
        // A background check that failed (offline at launch) says nothing; one the user asked for, or a download, does.
        let busy: Bool = switch pill.phase {
        case .checking, .downloading, .installing, .available: true
        default: false
        }
        let asked = userInitiated
        userInitiated = false
        guard asked || busy else { return }
        foundReply = nil
        hidden = false
        apply(.failed(why))
    }

    /// The session is over. A line that says how it went stays for its own few seconds.
    func dismissed() {
        foundReply = nil
        userInitiated = false
        switch pill.phase {
        case .failed, .upToDate: pill = ArisUpdatePill()
        default: apply(.dismissed)
        }
    }

    // MARK: - Installing when idle

    private func installWhenIdle(version: String, _ install: @escaping () -> Void) {
        pendingInstall = install
        idleWatch?.cancel()
        log.notice("updates: \(version, privacy: .public) is ready; it goes in once Aris is idle")
        idleWatch = Task { [weak self] in
            var idleSince: Date?
            while !Task.isCancelled {
                guard let self else { return }
                let activity = Self.activity()
                let now = Date()
                if ArisUpdateIdle.isIdle(activity) { idleSince = idleSince ?? now } else { idleSince = nil }
                if ArisUpdateIdle.mayInstall(activity, idleSince: idleSince, now: now), let install = self.pendingInstall {
                    self.pendingInstall = nil
                    log.notice("updates: Aris is idle, installing \(version, privacy: .public) and opening again")
                    install()
                    return
                }
                try? await Task.sleep(for: .seconds(ArisUpdateIdle.recheck))
            }
        }
    }

    private func dropPendingInstall() {
        idleWatch?.cancel()
        idleWatch = nil
        pendingInstall = nil
    }

    /// What Aris is doing now: a turn or a conversation, a job, a dictation, the setup.
    static func activity() -> ArisUpdateIdle.Activity {
        let state = ArisNotchState.shared
        return ArisUpdateIdle.Activity(
            turn: state.isActive || state.conversing,
            job: ArisUpdateIdle.jobBusy(ArisController.shared.jobs.map(\.state)),
            dictation: state.isDictating || ArisNoticeGate.dictationBusy(ArisDictationPillCenter.shared.display.phase),
            onboarding: ArisOnboardingGuide.shared.showing,
            notchOpen: shared.notchOpen(),
            settingsOpen: ArisSettingsWindow.shared.visible)
    }

    /// The common name of the certificate this app is signed with; nil when ad hoc or unsigned.
    nonisolated static func ownSigner() -> String? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let certificates = (info as? [String: Any])?[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certificates.first
        else { return nil }
        return SecCertificateCopySubjectSummary(leaf) as String?
    }

    // MARK: - The pill

    private func post() {
        let center = ArisNoticeCenter.shared
        guard let notice = pill.notice(id: noticeID, current: currentVersion, english: ArisUIWords.english) else {
            center.withdraw(key: ArisUpdateWords.key)
            hidden = false
            postedProgress = nil
            noticeID = UUID()
            return
        }
        if notice.progress != nil, hidden { return }
        // A download's bar moves in whole percents.
        if let progress = notice.progress, let posted = postedProgress, abs(progress - posted) < 0.01, progress < 1 { return }
        postedProgress = notice.progress
        let up = center.queue.shown.contains { $0.key == ArisUpdateWords.key }
        if up || presenting != nil {
            center.enqueue(notice)
            return
        }
        presenting = Task { [weak self] in
            await ArisController.shared.notify(notice)
            self?.presenting = nil
        }
    }
}

// MARK: - Sparkle's delegate

extension ArisUpdater: SPUUpdaterDelegate {
    /// The Info.plist's feed, or the test feed on this Mac (never anything Sparkle would read from the defaults itself).
    func feedURLString(for updater: SPUUpdater) -> String? {
        ArisUpdatePolicy.feed(info: Bundle.main.infoDictionary ?? [:], testFeed: UserDefaults.standard.string(forKey: ArisUpdatePolicy.testFeedDefault))
    }

    /// A background download finished: it is installed once Aris is idle, not only at quit.
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        guard Defaults[.arisAutoUpdate] else { return false }
        installWhenIdle(version: item.displayVersionString, immediateInstallHandler)
        return true
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        log.notice("updates: relaunching into the new version")
    }
}

// MARK: - The user driver: no window, only the pill

@MainActor
final class ArisUpdateDriver: NSObject, SPUUserDriver {
    private weak var owner: ArisUpdater?

    init(owner: ArisUpdater) { self.owner = owner }

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) { owner?.checkStarted() }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard let owner else { return reply(.dismiss) }
        owner.found(appcastItem, state: state, reply: reply)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        owner?.notFound()
        acknowledgement()
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        owner?.failed(error)
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) { owner?.apply(.downloadStarted) }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) { owner?.apply(.expectedLength(expectedContentLength)) }
    func showDownloadDidReceiveData(ofLength length: UInt64) { owner?.apply(.received(length)) }
    func showDownloadDidStartExtractingUpdate() { owner?.apply(.extracting) }
    func showExtractionReceivedProgress(_ progress: Double) {}

    /// Only reached after 지금 업데이트 (an automatic download hands its install to the delegate): it goes in now.
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        owner?.apply(.installing)
        reply(.install)
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        owner?.apply(.installing)
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        owner?.apply(.dismissed)
        acknowledgement()
    }

    func showUpdateInFocus() {}

    func dismissUpdateInstallation() { owner?.dismissed() }
}
