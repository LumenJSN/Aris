//
//  ArisAgentMonitor.swift
//  Aris
//
//  Runs ArisAgentLink against the real agent: ArisAgentClient.reachable every 30 s (10 s while it's down), the quiet
//  restarts, and the user's 다시 시작, all through the XPC helper's launchctl kickstart. One localhost request every
//  30 s; nothing per frame.
//

import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "agent-link")

@MainActor
final class ArisAgentMonitor: ObservableObject {
    static let shared = ArisAgentMonitor()

    @Published private(set) var link: ArisAgentLink = .up
    /// Whether the helper answered the last time it was asked. False from the first refused probe, long before the
    /// star dozes (two quiet restarts later): the settings' status line says a stopped helper at once, whatever else
    /// is missing (final check on a new Mac: with no AI it kept saying "No AI is set up yet").
    @Published private(set) var answering = true
    /// The pointer is on the dozing star or its chip.
    @Published private(set) var hovered = false

    private var quietTries = 0
    /// The app's and the agent's commits that were last compared, so the log says it once per pair.
    private var comparedBuilds: String?
    /// Refused probes in a row (a missing token is not one).
    private var refusals = 0
    private var loop: Task<Void, Never>?
    private var restartTask: Task<Void, Never>?
    private var unhover: Task<Void, Never>?

    /// Made (and started) by the first view that watches it: the resting star, at launch.
    private init() { start() }

    private func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.probe()
                let wait = self?.link.dozes == true ? ArisAgentLink.probeDownEvery : ArisAgentLink.probeEvery
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    /// The star or the chip under the pointer; leaving waits a moment so the pointer can cross from one to the other.
    func hover(_ on: Bool) {
        unhover?.cancel()
        if on {
            hovered = true
            return
        }
        unhover = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.hovered = false
        }
    }

    /// The user's 다시 시작: the agent is kicked, then asked every half second for up to 8 s.
    func restart() { restart(asked: false) }

    /// `asked`: the helper was just asked and did not answer (the button under a failure), so it is restarted even
    /// if the last probe here still had it up.
    func restart(asked: Bool) {
        guard ArisAgentLink.restarts(link, asked: asked) else { return }
        link = .restarting
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            let kicked = await ArisHelperClient.shared.restartArisAgent()
            log.notice("restart requested (launchctl \(kicked ? "ok" : "refused", privacy: .public))")
            let deadline = Date().addingTimeInterval(ArisAgentLink.restartWait)
            while Date() < deadline, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                if await ArisAgentClient.probe() == .answered { break }
            }
            guard let self, !Task.isCancelled else { return }
            if await ArisAgentClient.probe() == .answered {
                self.apply(.back)
                try? await Task.sleep(for: .seconds(ArisAgentLink.backHold))
                if self.link == .back { self.apply(.up) }
            } else {
                self.apply(ArisAgentLink.restartTimedOut(self.link))
            }
        }
    }

    /// One probe; a refusal is asked again in a few seconds (a quiet restart in between from the second in a row), until
    /// it answers or the star dozes. A token that won't load is left alone: nothing to restart.
    private func probe() async {
        guard link != .restarting, link != .back else { return }
        let result = await ArisAgentClient.probe()
        refusals = result == .refused ? refusals + 1 : 0
        if ArisAgentLink.answering(result, was: answering) != answering { answering.toggle() }
        let (next, quietRestart) = ArisAgentLink.afterProbe(link, probe: result, refusals: refusals, quietTries: quietTries)
        if result == .answered {
            quietTries = 0
            compareBuilds()
        }
        apply(next)
        guard result == .refused, !next.dozes else { return }
        if quietRestart {
            quietTries += 1
            log.notice("agent refused \(self.refusals, privacy: .public)× in a row; quiet restart \(self.quietTries, privacy: .public)")
            _ = await ArisHelperClient.shared.restartArisAgent()
        }
        try? await Task.sleep(for: .seconds(quietRestart ? ArisAgentLink.restartSettle : ArisAgentLink.quietSettle))
        await probe()
    }

    /// The agent that just answered writes its commit at start (ArisBuildInfo): when it is not this app's, the app was
    /// replaced while the helper kept running, and the helper is restarted from this app (once per pair of commits).
    private func compareBuilds() {
        let app = ArisBuildInfo.commit
        let agent = ArisBuildInfo.runningAgent(in: URL(fileURLWithPath: UserHome.path).appendingPathComponent(".config/aris/aris"))
        let pair = "\(app) \(agent ?? "-")"
        guard pair != comparedBuilds else { return }
        comparedBuilds = pair
        if let mismatch = ArisBuildInfo.mismatch(app: app, agent: agent) {
            // The app was replaced under a running helper: the helper inside this app is started in its place.
            log.notice("\(mismatch, privacy: .public)")
            Task { await ArisHelperInstall.shared.install() }
        } else {
            log.notice("app build \(app, privacy: .public), agent build \(agent ?? "unknown", privacy: .public)")
        }
    }

    private func apply(_ next: ArisAgentLink) {
        guard next != link else { return }
        log.notice("agent link \(String(describing: next), privacy: .public)")
        link = next
        if next == .up { quietTries = 0; refusals = 0 }
    }
}
