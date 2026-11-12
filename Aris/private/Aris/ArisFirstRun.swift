//
//  ArisFirstRun.swift
//  Aris
//
//  What a Mac that already ran Aris keeps when a new build changes what a brand-new install starts with (fresh install
//  F2, F4). A new install starts with the wake word off and with whichever AI is really set up; an install from before
//  that never chose has been running with the wake word on and Codex answering, so at the first launch of this build
//  both are written down as its own choice, once. After that, "nothing stored" only ever means a new install.
//  Foundation only, so the tests run it.
//

import Foundation

enum ArisFirstRun {
    /// Set at the first launch of a build that has this: the pinning below never runs twice.
    static let pinnedKey = "arisFirstRunPinned"
    static let wakeWordKey = "arisWakeWord"
    static let brainKey = "arisBrain"
    /// What every install ran on before the new defaults.
    static let earlierWakeWord = true
    static let earlierBrain = "codex"

    /// Aris's own keys all start this way; macOS's, Sparkle's and the shortcut recorder's don't.
    private static let prefix = "aris"
    /// Set from outside to replay the guide (`-arisOnboardingReplay YES`, or `defaults write`): never proof of an earlier run.
    private static let ignored: Set<String> = ["arisOnboardingReplay"]

    /// Whether Aris has stored anything on this Mac before (`keys`: what its preferences hold, not their defaults).
    static func isEarlierInstall(keys: Set<String>) -> Bool {
        keys.contains { $0.hasPrefix(prefix) && !ignored.contains($0) }
    }

    /// What to write down for an install from before; nil leaves the key as it is.
    struct Pins: Equatable {
        let wakeWord: Bool?
        let brain: String?
    }

    static func pins(keys: Set<String>) -> Pins {
        guard isEarlierInstall(keys: keys) else { return Pins(wakeWord: nil, brain: nil) }
        return Pins(wakeWord: keys.contains(wakeWordKey) ? nil : earlierWakeWord, brain: keys.contains(brainKey) ? nil : earlierBrain)
    }

    /// At launch, before anything reads a preference. `stored`: the keys this Mac's preferences hold right now.
    static func pinEarlierDefaults(in defaults: UserDefaults, stored: Set<String>) {
        guard !stored.contains(pinnedKey), !defaults.bool(forKey: pinnedKey) else { return }
        let pins = pins(keys: stored)
        if let wakeWord = pins.wakeWord { defaults.set(wakeWord, forKey: wakeWordKey) }
        if let brain = pins.brain { defaults.set(brain, forKey: brainKey) }
        defaults.set(true, forKey: pinnedKey)
    }

    /// The keys Aris's preferences hold on this Mac (registered defaults left out).
    static func storedKeys(in defaults: UserDefaults = .standard, bundle: Bundle = .main) -> Set<String> {
        guard let name = bundle.bundleIdentifier else { return [] }
        return Set((defaults.persistentDomain(forName: name) ?? [:]).keys)
    }
}
