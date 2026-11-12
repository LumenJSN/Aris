//
//  ArisBrainSetup.swift
//  Aris
//
//  Keeps the brain that answers one that can (fresh install F2). It asks aris-agent which AIs are set up on this Mac
//  (the same answer the 팀원 page's brain rows show) and applies ArisBrainChoice: a new install is given the first of
//  Claude, Codex, Antigravity and the API brain that is set up; a brain the user already has is left alone unless it
//  can't answer here. What it learned is published for the guide's AI page, the settings status line and the notch.
//  Asked at launch (again a few times while the agent is still starting), when the guide's AI page or the settings
//  window shows, and after a key is saved. One small localhost request each time; nothing polls.
//

import Defaults
import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "brain")

@MainActor
final class ArisBrainSetup: ObservableObject {
    static let shared = ArisBrainSetup()

    /// Which brains are set up here, as the agent last said; nil until it has answered.
    @Published private(set) var ready: [ArisBrain: Bool]?

    /// The brains that are set up but have never answered (an API key whose check failed): not ready, and shown as
    /// needing a check wherever "is an AI ready" is read.
    @Published private(set) var unchecked: Set<ArisBrain> = []

    /// The agent answered and no AI can answer on this Mac.
    var noneReady: Bool { ArisBrainChoice.noneReady(ready) }

    /// No AI can answer, but a key is saved that has never answered.
    var needsCheck: Bool { ArisBrainChoice.needsCheck(ready: ready, unchecked: unchecked) }

    /// How long after launch the agent is asked again while it hasn't answered (it may still be starting).
    private static let launchRetries: [Duration] = [.seconds(2), .seconds(5), .seconds(15), .seconds(45)]
    private var launch: Task<Void, Never>?

    private init() {}

    /// At launch: asks until the agent answers once, then stops.
    func start() {
        guard launch == nil else { return }
        launch = Task { [weak self] in
            for wait in [.zero] + Self.launchRetries {
                try? await Task.sleep(for: wait)
                guard !Task.isCancelled, let self else { return }
                if await self.refresh() { return }
            }
        }
    }

    /// Asks the agent now and, on an install with no brain stored yet, stores one that can answer. False when the agent didn't answer.
    @discardableResult
    func refresh() async -> Bool {
        guard let said = await ArisAgentClient.teamBrainsSaid() else { return false }
        let ready = ArisBrainChoice.ready(said.ready)
        let unchecked = Set(said.unchecked.compactMap(ArisBrain.init(rawValue:)))
        if ready != self.ready { self.ready = ready }
        if unchecked != self.unchecked { self.unchecked = unchecked }
        let stored = Self.stored
        if let pick = ArisBrainChoice.resolve(stored: stored, ready: ready) {
            log.notice("brain: \(stored ?? "none stored", privacy: .public) → \(pick.rawValue, privacy: .public) (set up on this Mac)")
            Defaults[.arisBrain] = pick.rawValue
        }
        return true
    }

    /// The saved key is tried again (the status line's button, the AI services page's 다시 확인): the helper's own short
    /// check, then what it found is read back. True when the key answered.
    func recheck() async -> Bool {
        let result = await ArisAgentClient.testActiveAPIBrain()
        log.notice("brain: the saved key was checked again (\(result.ok ? "it answers" : "no answer", privacy: .public))")
        await refresh()
        return result.ok
    }

    /// He removed a key in Settings: when that was the brain that answered, the Mac is back to having picked none
    /// (ArisBrainChoice.forgetsAfterKeyRemoved), and one that can answer takes over if there is one.
    func keyRemoved() async {
        guard await refresh(), ArisBrainChoice.forgetsAfterKeyRemoved(stored: Self.stored, ready: ready, unchecked: unchecked) else { return }
        log.notice("brain: api → none stored (its key was removed)")
        UserDefaults.standard.removeObject(forKey: ArisFirstRun.brainKey)
        await refresh()
    }

    /// The user's pick on the guide's AI page.
    func choose(_ brain: ArisBrain) {
        Defaults[.arisBrain] = brain.rawValue
        log.notice("brain: \(brain.rawValue, privacy: .public) (picked in the guide)")
    }

    /// The brain this Mac has stored; nil on a new install that hasn't one yet (the key's default isn't a choice).
    static var stored: String? {
        guard let name = Bundle.main.bundleIdentifier else { return nil }
        return UserDefaults.standard.persistentDomain(forName: name)?[ArisFirstRun.brainKey] as? String
    }
}
