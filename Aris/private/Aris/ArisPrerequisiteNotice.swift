//
//  ArisPrerequisiteNotice.swift
//  Aris
//
//  At launch, what the install lacks (ArisPrerequisites) goes to the log, and into the notch as one line with what to
//  do: a missing helper every launch, the older macOS once. While the guide shows it says so itself on its first
//  page, so the notch stays the guide's.
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
            // Never over the guide or a turn the user already started.
            guard !ArisOnboardingGuide.shared.showing, ArisController.shared.session.phase == .idle else { return }
            ArisController.shared.fail(ArisPrerequisites.full(first))
            if first == .voice { defaults.set(true, forKey: ArisPrerequisites.voiceSaidKey) }
        }
    }
}
