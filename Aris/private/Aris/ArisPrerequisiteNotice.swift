//
//  ArisPrerequisiteNotice.swift
//  Aris
//
//  At launch, what the install lacks (ArisPrerequisites) goes to the log, and onto a card under the notch with what to
//  do: a missing helper every launch, the older macOS once. While the guide shows it says so itself on its first
//  page, so then there is no card.
//

import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "app")

@MainActor
enum ArisPrerequisiteNotice {
    /// Long enough after launch that the notch is on screen.
    static let delay: Duration = .seconds(3)

    static func sayAtLaunch(defaults: UserDefaults = .standard) {
        let missing = ArisPrerequisites.current()
        guard !missing.isEmpty else { return }
        log.error("install is missing: \(missing.map(\.rawValue).joined(separator: ", "), privacy: .public)")
        guard let first = ArisPrerequisites.atLaunch(missing, voiceSaidBefore: defaults.bool(forKey: ArisPrerequisites.voiceSaidKey)) else { return }
        Task {
            try? await Task.sleep(for: delay)
            // The guide says it itself on its first page. Otherwise a card under the notch, never over a turn the user
            // already started (it waits for it).
            guard !ArisOnboardingGuide.shared.showing else { return }
            let card = ArisNoticeRoute.problem(line: ArisPrerequisites.remedy(first), title: ArisPrerequisites.line(first), english: ArisUIWords.english)
            guard await ArisController.shared.notify(card) else { return }
            if first == .voice { defaults.set(true, forKey: ArisPrerequisites.voiceSaidKey) }
        }
    }
}
