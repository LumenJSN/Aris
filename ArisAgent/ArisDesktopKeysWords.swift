//
//  ArisDesktopKeysWords.swift
//  aris-agent
//
//  What `aris-tools keys` prints once Aris's own engine pressed the keys (ArisDesktopKeysRoute), and which way keys
//  for an app go (ArisDesktopKeysPolicy): straight to the engine for an ordinary app; through the desktop gate (its
//  card for a terminal's Return and characters, as typed text there gets) for a terminal or code runner, which would
//  run them; refused for one with no turn to ask in. The agent's own held work sends only the keys it was given
//  (a learned shortcut's own). Pure.
//

import Foundation

enum ArisDesktopKeysWords {
    /// What a press of `keys` × `times` comes to, as aris-tools prints it. Pure.
    static func line(_ written: String, times: Int, app: String, reply: ArisDesktopEnvelope?) -> (ok: Bool, line: String) {
        guard let reply, reply.success else {
            let why = [reply?.code, reply?.message].compactMap { $0 }.joined(separator: ": ")
            return (false, ArisTypeReadbackWords.notSentLead + "the keys weren't sent to \(app) (\(why.isEmpty ? "the engine gave no answer" : why)). Don't tell the user it was done.")
        }
        let count = times > 1 ? " ×\(times)" : ""
        let how = reply.data["delivery"] as? String == "foreground" ? "with \(app) brought forward a moment, then the front app back" : "in the background"
        return (true, "sent \(written)\(count) to \(app), \(how) (keys only: what they did is not checked; look with `desktop see` before telling the user it worked)")
    }

}

/// The lead aris-tools' readback lines share (ArisTypeReadback.notSentLead, which the agent doesn't build).
enum ArisTypeReadbackWords {
    static let notSentLead = "NOT SENT: "
}

enum ArisDesktopKeysPolicy {
    enum Route: Equatable {
        /// An ordinary app: the engine presses them (lock, gap rule, background keys).
        case send
        /// A terminal or code runner: the desktop gate decides, as for `desktop press` there (Return and characters on
        /// The user's card with the exact keys, every time).
        case gate
        case refuse(String)
    }

    static let heldOtherKeysLine = "Refused: Aris's own replay sends only the keys of the shortcut it is replaying, and these aren't among them, so nothing was sent."
    static func heldRunnerLine(_ app: String) -> String {
        "Refused: \(app) runs what is typed into it (a terminal or code runner), and a replay with no AI has no card to ask the user on, so nothing was sent."
    }
    static let unknownAppLine = "Refused: the app the keys would go to can't be told (no bundle id), so nothing was sent."
    static let badKeyLine = "Refused: that isn't a key Aris knows (a key is like cmd+shift+t, return or f5), so nothing was sent."

    /// A key as the engine reads one: a chord its parser knows, never anything shaped like a flag (it would be read as
    /// the engine's own `--window-id`/`--app` and aim the press somewhere else).
    static func isKey(_ key: String) -> Bool {
        guard !key.isEmpty, key.count <= 40, !key.hasPrefix("-"), !key.contains("="), !key.contains(where: \.isWhitespace) else { return false }
        return ArisNativeInput.chord(key, keyboard: nil) != nil
    }

    /// The app runs what it is sent: a terminal (by its bundle id or name) or a code runner.
    static func runsCode(bundle: String?, names: [String]) -> Bool {
        ArisWritingStyles.isTerminal(bundle) || ArisRiskPolicy.isTerminalApp([bundle] + names) || ArisRiskPolicy.isCodeRunner([bundle] + names)
    }

    /// `held`: the agent's own work, with the keys it may send (nil: a brain's turn, whose card can ask).
    static func route(bundle: String?, names: [String], keys: [String], held: Set<String>?) -> Route {
        guard !keys.isEmpty, keys.allSatisfy(isKey) else { return .refuse(badKeyLine) }
        guard let bundle, !bundle.isEmpty else { return .refuse(unknownAppLine) }
        if let held {
            guard keys.allSatisfy({ held.contains($0.lowercased()) }) else { return .refuse(heldOtherKeysLine) }
            return runsCode(bundle: bundle, names: names) ? .refuse(heldRunnerLine(names.first ?? bundle)) : .send
        }
        return runsCode(bundle: bundle, names: names) ? .gate : .send
    }

    /// The keys a learned shortcut's own commands press (`<tools> keys <chord>`), lowercased: all a replay may send.
    static func keys(in commands: [String], tools: String) -> Set<String> {
        Set(commands.compactMap { command -> String? in
            let words = command.split(separator: " ").map(String.init)
            guard words.count >= 3, words[0] == tools, words[1] == "keys" else { return nil }
            return words[2].lowercased()
        })
    }
}
