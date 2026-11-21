//
//  ArisStarCardModel.swift
//  Aris
//
//  The repository card on the setup's last page, live (ArisStarCard holds its rules): as the page shows, aris-agent
//  is asked through gh who is logged in and whether the repository is starred, and GitHub's public API for the star
//  count, both off the main thread; the star is left only from the card's button; skipped or starred, it is recorded
//  and the card never shows again. Every way in is injected (Actions), so a still render or a test never asks gh.
//

import AppKit
import Foundation

@MainActor
final class ArisStarCardModel: ObservableObject {
    struct Actions: Sendable {
        /// POST /github-star {"do": "check"}.
        var check: @MainActor @Sendable () async -> [String: Any]?
        /// POST /github-star {"do": "star"}.
        var star: @MainActor @Sendable () async -> [String: Any]?
        /// The public star count; nil hides the chip.
        var count: @MainActor @Sendable () async -> Int?
        /// Opens the repository's page in the default browser.
        var open: @MainActor @Sendable (URL) -> Void

        static let live = Actions(check: { await ArisAgentClient.githubStar("check") },
                                  star: { await ArisAgentClient.githubStar("star") },
                                  count: { await ArisStarCardModel.publicCount() },
                                  open: { NSWorkspace.shared.open($0) })
    }

    /// The busy sweep plays at least once (1.1 s), so a quick answer never flashes it.
    static let busyAtLeast: Duration = .milliseconds(1100)

    @Published var state: ArisStarCard.State
    /// The public count as it was read; the card shows one more once the star was left here.
    @Published var count: Int?
    /// Goes up each time the star is left on this page: the star's pop, its sparks and the count's roll play once.
    @Published private(set) var celebrations = 0

    private let actions: Actions
    private let defaults: UserDefaults
    private var asked = false

    init(actions: Actions = .live, defaults: UserDefaults = .standard) {
        self.actions = actions
        self.defaults = defaults
        state = ArisStarCard.opening(settled: defaults.string(forKey: ArisStarCard.settledKey))
    }

    /// A new showing of the setup: the card starts again from what is recorded (gone once skipped or starred).
    func reopen() {
        guard !isBusy else { return }
        asked = false
        state = ArisStarCard.opening(settled: defaults.string(forKey: ArisStarCard.settledKey))
    }

    private var isBusy: Bool { if case .busy = state { true } else { false } }

    /// The page showed: gh and the count are asked once, unless the card is settled.
    func begin() {
        guard !asked, state == .looking else { return }
        asked = true
        Task { [actions] in
            let count = await actions.count()
            self.count = count
        }
        Task { [actions] in
            let reply = await actions.check()
            guard ArisStarCard.takes(check: self.state) else { return }
            self.settle(ArisStarCard.checked(reply))
        }
    }

    /// The card's button: the star with gh logged in, the repository's page without.
    func press() {
        switch ArisStarCard.press(state) {
        case .star:
            state = ArisStarCard.pressing(state)
            Task { [actions] in
                let started = ContinuousClock.now
                let reply = await actions.star()
                let left = Self.busyAtLeast - (ContinuousClock.now - started)
                if left > .zero { try? await Task.sleep(for: left) }
                let next = ArisStarCard.starred(reply)
                if next == .done { self.celebrations += 1 }
                self.settle(next)
            }
        case .open:
            actions.open(ArisStarCard.page)
        case .none:
            break
        }
    }

    /// 건너뛰기: the card folds away and is never shown again.
    func skip() {
        guard ArisStarCard.skips(state) else { return }
        defaults.set(ArisStarCard.Settled.skipped.rawValue, forKey: ArisStarCard.settledKey)
        state = .gone
    }

    private func settle(_ next: ArisStarCard.State) {
        state = next
        if let settled = ArisStarCard.settles(next) { defaults.set(settled.rawValue, forKey: ArisStarCard.settledKey) }
    }

    /// `stargazers_count` from GitHub's public API, with no login, within 5 s; nil for anything else.
    nonisolated static func publicCount() async -> Int? {
        var request = URLRequest(url: ArisStarCard.api, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: ArisStarCard.countTimeout)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await ArisNoStore.session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return ArisStarCard.count(from: data)
    }
}
