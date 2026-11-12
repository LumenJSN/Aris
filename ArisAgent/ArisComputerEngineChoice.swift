//
//  ArisComputerEngineChoice.swift
//  aris-agent
//
//  The one seam for which engine works other apps' windows (ArisComputerEngine). The app stores the user's pick and
//  sends it with each question; here it is what the Codex driver (its plugin, its prompt) and the desktop controller's
//  poor-tree advice read. Peekaboo until told otherwise, and whenever Codex isn't installed. Every brain but Codex keeps
//  `aris-tools desktop`, since Codex's computer use only runs inside Codex; with Codex picked, a window with nothing for
//  accessibility goes to Codex (a job).
//

import Foundation

enum ArisComputerEngineChoice {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var picked = ArisComputerEngine.peekaboo

    /// The engine in force now.
    static var current: ArisComputerEngine {
        ArisComputerEngine.effective(picked: lock.withLock { picked }, codexInstalled: ArisReadJudge.executable(.codex) != nil)
    }

    /// The app's stored pick (a word from it: anything unknown is the default). True when it changed, so Codex's running
    /// processes must go (their plugin and prompt were set for the old one).
    static func set(_ raw: String?) -> Bool {
        let new = ArisComputerEngine.named(raw)
        return lock.withLock {
            defer { picked = new }
            return picked != new
        }
    }
}

/// What a window with nothing for accessibility does next, by the engine in force.
enum ArisDesktopFallback: Equatable {
    /// Peekaboo: the text on screen, or look and click (ArisDesktopObservation.poorLine).
    case lookAndClick
    /// The Codex brain, Codex's computer use picked: its own cua_repl.
    case codexRepl
    /// Another brain, Codex's computer use picked: the step goes out as a job (dispatched jobs run on Codex).
    case codexJob

    static func next(brain: ArisBrain, engine: ArisComputerEngine) -> ArisDesktopFallback {
        guard engine == .codex else { return .lookAndClick }
        return brain == .codex ? .codexRepl : .codexJob
    }

    /// What the brain is told; nil for the default line.
    func line(app: String) -> String? {
        switch self {
        case .lookAndClick: return nil
        case .codexRepl:
            return "\(app) shows almost nothing to the accessibility tree, so desktop refs can't reach it. Use your computer use (cua_repl) for \(app) instead."
        case .codexJob:
            return "\(app) shows almost nothing to the accessibility tree, so desktop refs can't reach it. Hand this step out as a job (the jobs block): it runs on GPT, which can work \(app) from its screen."
        }
    }
}
