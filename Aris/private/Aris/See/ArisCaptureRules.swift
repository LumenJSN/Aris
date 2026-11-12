//
//  ArisCaptureRules.swift
//  Aris (also built into aris-agent and aris-tools)
//
//  When Aris may look at the screen and what is never in a frame: no capture under secure input or with the
//  setting off; Aris's own windows and password apps (and their helpers) are always left out.
//  Pure, so the tests run it.
//

import CoreGraphics
import Foundation

enum ArisCaptureRules {
    /// Apps whose windows are never captured or read (lowercased; compare with `isPrivate`).
    static let privateBundleIds: Set<String> = [
        "com.apple.keychainaccess", "com.apple.passwords", "com.1password.1password", "com.agilebits.onepassword7",
        // Lowercased, as isPrivate compares them.
        "com.bitwarden.desktop", "com.dashlane.dashlane", "com.dashlane.dashlanephonefinal", "com.lastpass.lastpass",
        "me.proton.pass.electron", "in.sinew.enpass-desktop", "org.keepassxc.keepassxc",
    ]

    /// A turn waits at most this long for its screenshot at send, then goes without it.
    static let waitAtSend: Duration = .seconds(3)
    /// A null or blank first capture (a cold start) is tried once more after this.
    static let coldRetry: Duration = .milliseconds(500)

    /// SCStreamErrorDomain (spelled out: this file can't import ScreenCaptureKit) and its "user declined" code.
    static let streamErrorDomain = "com.apple.ScreenCaptureKit.SCStreamErrorDomain"
    static let userDeclinedCode = -3801

    /// One of the private apps, or a helper inside one (its id plus ".…").
    static func isPrivate(_ bundleId: String?) -> Bool {
        guard let id = bundleId?.lowercased(), !id.isEmpty else { return false }
        return privateBundleIds.contains(id) || privateBundleIds.contains { id.hasPrefix($0 + ".") }
    }

    /// Why this turn takes no screenshot, or nil to capture. Whatever app is in front (Aris or a private app),
    /// the capture goes ahead: those windows are filtered out of the frame (`excludes`).
    static func skip(secureInput: Bool, setting: Bool) -> String? {
        if !setting { return "setting off" }
        if secureInput { return "secure input" }
        return nil
    }

    /// Whether an app's windows are left out of every frame: Aris itself (by pid or bundle id) and the private apps.
    static func excludes(bundleId: String?, pid: Int32, ownPid: Int32, ownBundleId: String) -> Bool {
        if pid == ownPid { return true }
        if let bundleId, bundleId.caseInsensitiveCompare(ownBundleId) == .orderedSame { return true }
        return isPrivate(bundleId)
    }

    /// Whether the CGWindowList fallback composes a window: never one whose owner can't be resolved to a bundle id
    /// (it could be a private app's helper that hides its bundle), nor Aris's or a private app's.
    static func fallbackKeeps(bundleId: String?, pid: Int32, ownPid: Int32, ownBundleId: String) -> Bool {
        guard let bundleId else { return false }
        return !excludes(bundleId: bundleId, pid: pid, ownPid: ownPid, ownBundleId: ownBundleId)
    }

    /// How long to wait before trying again, or nil to stop: one retry, only when the first attempt got nothing,
    /// and never after the user declined the permission (asking again can't change that).
    static func retryDelay(afterAttempt attempt: Int, gotImage: Bool, declined: Bool = false) -> Duration? {
        attempt == 0 && !gotImage && !declined ? coldRetry : nil
    }

    static func isUserDeclined(domain: String, code: Int) -> Bool {
        domain == streamErrorDomain && code == userDeclinedCode
    }

    /// Whether the CGWindowList fallback should grab at point size: only when the budget is below the native size
    /// and the point size still covers it, so the frame is scaled down, never up.
    static func fallbackUsesNominal(native: CGSize, points: CGSize, budget: ArisImageBudget) -> Bool {
        let target = budget.fit(native)
        return target != native && target.width <= points.width && target.height <= points.height
    }

    /// The display under the point (Cocoa global coordinates), else the nearest one.
    static func display(containing point: CGPoint, in screens: [(id: CGDirectDisplayID, frame: CGRect)]) -> CGDirectDisplayID? {
        if let hit = screens.first(where: { $0.frame.contains(point) }) { return hit.id }
        return screens.min { distance(point, $0.frame) < distance(point, $1.frame) }?.id
    }

    private static func distance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}
