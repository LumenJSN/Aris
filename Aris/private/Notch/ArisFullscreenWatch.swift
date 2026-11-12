//
//  ArisFullscreenWatch.swift
//  Aris
//
//  Which displays show a full-screen space right now, for hiding the closed notch over full-screen apps. Spaces come
//  from the MacroVisionKit package (MIT); the "now playing only" option needs the music source's app in the space.
//

import AppKit
import Combine
import Defaults
import MacroVisionKit

@MainActor
final class ArisFullscreenWatch: ObservableObject {
    static let shared = ArisFullscreenWatch()

    /// Display UUID → a full-screen space counts there.
    @Published private(set) var fullscreenStatus: [String: Bool] = [:]

    private var spaces: [ArisNotchRules.FullscreenSpace] = []
    private var watchers: Set<AnyCancellable> = []
    private var listening: Task<Void, Never>?

    private init() {
        listening = Task { [weak self] in
            let changes = await FullScreenMonitor.shared.spaceChanges()
            for await spaces in changes {
                guard let self else { return }
                self.spaces = spaces.map { ArisNotchRules.FullscreenSpace(displayUUID: $0.screenUUID, apps: $0.runningApps) }
                self.update()
            }
        }
        // The music source is another singleton: subscribe on the next turn, never while `shared` is being created.
        Task { @MainActor [weak self] in
            guard let self else { return }
            Defaults.publisher(.hideNotchOption, options: [])
                .map { _ in () }
                .merge(with: ArisNowPlaying.shared.$bundleIdentifier.removeDuplicates().map { _ in () })
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in self?.update() }
                .store(in: &self.watchers)
        }
    }

    private func update() {
        let status = ArisNotchRules.fullscreen(spaces: spaces, displays: NSScreen.screens.compactMap(\.displayUUID),
                                               option: Defaults[.hideNotchOption], musicBundle: ArisNowPlaying.shared.bundleIdentifier)
        if status != fullscreenStatus { fullscreenStatus = status }
    }
}
