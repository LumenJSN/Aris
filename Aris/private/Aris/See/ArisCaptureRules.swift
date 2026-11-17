//
//  ArisCaptureRules.swift
//  Aris (also built into aris-agent and aris-tools)
//
//  When Aris may look at the screen and what is never in a frame: no capture under secure input or with the
//  setting off; Aris's own windows are always left out. Password managers, Keychain Access and System Information are
//  in the frame like any other app's windows (the owner, 2026-11-16: nothing shows in them until they reveals it).
//  Pure, so the tests run it.
//

import CoreGraphics
import Foundation

enum ArisCaptureRules {
    /// A turn waits at most this long for its screenshot at send, then goes without it.
    static let waitAtSend: Duration = .seconds(3)
    /// A null or blank first capture (a cold start) is tried once more after this.
    static let coldRetry: Duration = .milliseconds(500)

    /// SCStreamErrorDomain (spelled out: this file can't import ScreenCaptureKit) and its "user declined" code.
    static let streamErrorDomain = "com.apple.ScreenCaptureKit.SCStreamErrorDomain"
    static let userDeclinedCode = -3801

    /// Why this turn takes no screenshot, or nil to capture. Whatever app is in front (Aris too), the capture goes
    /// ahead: Aris's windows are filtered out of the frame (`excludes`).
    static func skip(secureInput: Bool, setting: Bool) -> String? {
        if !setting { return "setting off" }
        if secureInput { return "secure input" }
        return nil
    }

    /// Whether an app's windows are left out of every frame: Aris itself (by pid or bundle id).
    static func excludes(bundleId: String?, pid: Int32, ownPid: Int32, ownBundleId: String) -> Bool {
        if pid == ownPid { return true }
        if let bundleId, bundleId.caseInsensitiveCompare(ownBundleId) == .orderedSame { return true }
        return false
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
