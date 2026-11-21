//
//  ArisController+WakeDown.swift
//  Aris
//
//  The wake word's microphone that won't open or whose checks can't listen (ArisWakeDown): it keeps being tried, starts
//  again from the shortest pause on the events that usually fix it, and once it has been down a while the user is told
//  once on the notice pill. While the microphone or speech permission is missing it is looked at every ten seconds
//  (no microphone, no prompt), so giving it in System Settings arms the wake word without a relaunch.
//

import Defaults
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "turn")

extension ArisController {
    /// The run of failures the user may be told about.
    static var wakeDown = ArisWakeDown()
    private static var wakePermissionWatch: Task<Void, Never>?
    /// How often a missing permission is looked at again.
    static let wakePermissionRecheck: Duration = .seconds(10)

    /// Something that usually brings a dead wake microphone back happened: the backoff starts from its shortest pause.
    /// The caller arms the wake word again.
    func wakeMicMayWorkAgain(_ why: String) {
        guard Self.wakeDown.isDown || Self.wakeListenFailures > 0 || Self.wakeRestarts > 1 else { return }
        log.notice("wake word: \(why, privacy: .public): the microphone is tried again from the shortest pause")
        Self.wakeListenFailures = 0
        Self.wakeRestarts = 0
    }

    /// The microphone couldn't open, or a check couldn't listen: told once when it has lasted (ArisWakeDown).
    func wakeMicFailed() {
        Self.wakeDown.failed(at: Self.uptime)
        ArisWakeStatusLive.shared.update { $0.micDown = true }
        guard Defaults[.arisWakeWord], Self.wakeDown.shouldTell(at: Self.uptime) else { return }
        log.notice("wake word: the microphone has been down for a while; telling the user once")
        let english = ArisUIWords.english
        let notice = ArisNoticeRoute.announcement(title: ArisWakeDown.title(english: english), text: ArisWakeDown.body(english: english), kind: .problem)
        // The notice waits its moment on its own: no turn's.
        ArisTurnScope.outside { Task { [weak self] in await self?.notify(notice) } }
    }

    /// The microphone opened with no failed check behind it, or a check listened.
    func wakeMicWorked() {
        guard Self.wakeListenFailures == 0 else { return }
        Self.wakeDown.worked()
        ArisWakeStatusLive.shared.update { $0.micDown = false }
    }

    /// The wake word's state for Settings and the diagnostics (ArisWakeStatus). `playing`: this Mac's playback, when it
    /// was just read.
    func noteWakeStatus(blocker: ArisWakeArm.Blocker?, playing: Bool? = nil) {
        let trained = hasWakeModel, down = Self.wakeDown.isDown, on = Defaults[.arisWakeWord]
        ArisWakeStatusLive.shared.update {
            $0.settingOn = on
            $0.blocker = blocker
            $0.micDown = down
            $0.trained = trained
            $0.whisperReady = ArisWhisper.chosen != nil
            if let playing { $0.playing = playing }
        }
    }

    /// The wake word waits for the microphone or speech permission: looked at again every ten seconds until it is given
    /// (or the wake word is turned off), then armed.
    func watchWakePermission() {
        guard Self.wakePermissionWatch == nil else { return }
        Self.wakePermissionWatch = ArisTurnScope.outside {
            Task { [weak self] in
                while !Task.isCancelled, Defaults[.arisWakeWord], Self.permissionProblem() != nil {
                    try? await Task.sleep(for: Self.wakePermissionRecheck)
                }
                // Free before arming: a wait that still finds a permission missing starts the next watch.
                Self.wakePermissionWatch = nil
                guard !Task.isCancelled, Defaults[.arisWakeWord] else { return }
                self?.wakeMicMayWorkAgain("the permission was given")
                self?.waitForWakeWord()
            }
        }
    }
}
