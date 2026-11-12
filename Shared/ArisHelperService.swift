//
//  ArisHelperService.swift
//  Aris
//
//  What the unsandboxed XPC helper does for the sandboxed app: install and restart aris-agent and change the screen
//  brightness. In both targets. Every reply is a result (false / nil when it didn't work), never an error.
//

import Foundation

@objc protocol ArisHelperService {
    /// `launchctl kickstart -k` of aris-agent, with fixed arguments (ArisAgentKickstart). True when it exited 0.
    func restartAgent(reply: @escaping (Bool) -> Void)
    /// Makes this app's own helper the one that runs: the LaunchAgent pointing at the aris-agent inside the app the XPC
    /// helper is in, written only when it differs, loaded, and answering. Takes nothing from the caller. The reply is
    /// an ArisAgentInstallOutcome word.
    func installAgent(reply: @escaping (String) -> Void)
    /// Sets the level (clamped to 0…1).
    func setScreenBrightness(_ level: Float, reply: @escaping (Bool) -> Void)
    /// Moves the level by `delta` and replies with the level after the change.
    func adjustScreenBrightness(by delta: Float, reply: @escaping (NSNumber?) -> Void)
}

enum ArisHelperName {
    static let service = "com.lumenjsn.aris.XPCHelper"

    static func interface() -> NSXPCInterface { NSXPCInterface(with: ArisHelperService.self) }
}
