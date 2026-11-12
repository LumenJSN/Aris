//
//  ArisScreenCapture.swift
//  Aris
//
//  Takes the screenshot Aris sends with a turn, and the frames gesture shots are cut from, with ScreenCaptureKit. The
//  order: ScreenCaptureKit first, CGWindowList if it gives nothing, and one retry after 500 ms when a cold start
//  gives a blank frame. Callers capture only with the grant (controller ruling 2026-11-03): nothing here asks macOS
//  for it; only the guide's 허용하기 does (ArisPermissionGuide). Aris's own windows and password apps are never in a
//  frame. Images stay in memory; only sizes, byte counts and timings are logged.
//
//  Behind `ArisScreenCapturing` so the capture can move to aris-agent if the sandboxed app can't capture.
//

import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import os
import ScreenCaptureKit

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "see")

/// The per-turn screenshot: PNG within `ArisImageBudget.cursor`, above the blank floor.
struct ArisCaptured: Sendable {
    let png: Data
    let pixels: CGSize
    let display: CGDirectDisplayID
    let ms: Int
    let retried: Bool
}

protocol ArisScreenCapturing: Sendable {
    /// The display under the cursor, cursor shown, as a budgeted PNG; nil when skipped or nothing came back.
    /// The "화면 같이 보기" setting is the caller's to check; secure input is checked here. Whatever app is in front,
    /// Aris's own windows and the private apps' are filtered out of the frame.
    func cursorDisplayShot() async -> ArisCaptured?
    /// One frame of a display within the budget (for gesture crops and the drawing reference); nil on failure.
    func frame(display: CGDirectDisplayID, budget: ArisImageBudget, showsCursor: Bool) async -> CGImage?
    /// Loads the shareable content once, so the first real capture is quicker.
    func warm() async
    var hasPermission: Bool { get }
}

actor ArisScreenCapture: ArisScreenCapturing {
    static let shared = ArisScreenCapture()

    private let ownPid = getpid()
    private let ownBundleId = Bundle.main.bundleIdentifier ?? "com.lumenjsn.aris"

    nonisolated var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    func cursorDisplayShot() async -> ArisCaptured? {
        let start = ContinuousClock.now
        let (point, screens) = await MainActor.run { Self.pointerAndScreens() }
        if let reason = ArisCaptureRules.skip(secureInput: IsSecureEventInputEnabled(), setting: true) {
            log.info("cursor shot skipped: \(reason, privacy: .public)")
            return nil
        }
        guard let display = ArisCaptureRules.display(containing: point, in: screens) else { return nil }
        var attempt = 0
        while !Task.isCancelled {
            let (frame, declined) = await grab(display: display, budget: .cursor, showsCursor: true)
            guard !Task.isCancelled else { return nil } // the turn was dropped while the frame came in
            if let frame, let shot = ArisImageCodec.budgeted(frame, budget: .cursor, for: .cursor) {
                let ms = Self.milliseconds(since: start)
                log.info("cursor shot ok: \(Int(shot.pixels.width))x\(Int(shot.pixels.height)) \(shot.data.count) B \(ms) ms retried \(attempt > 0)")
                return ArisCaptured(png: shot.data, pixels: shot.pixels, display: display, ms: ms, retried: attempt > 0)
            }
            guard let delay = ArisCaptureRules.retryDelay(afterAttempt: attempt, gotImage: false, declined: declined) else { break }
            try? await Task.sleep(for: delay)
            attempt += 1
        }
        guard !Task.isCancelled else { return nil }
        log.info("cursor shot failed after \(attempt + 1) attempts, \(Self.milliseconds(since: start)) ms")
        return nil
    }

    func frame(display: CGDirectDisplayID, budget: ArisImageBudget, showsCursor: Bool) async -> CGImage? {
        await grab(display: display, budget: budget, showsCursor: showsCursor).image
    }

    /// Only with the grant: without it this would bring up the system prompt outside a turn.
    func warm() async {
        guard CGPreflightScreenCaptureAccess() else { return }
        _ = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
    }

    /// The app's first real capture, taken by the setup once the Screen Recording card is on (ArisFirstCapture): macOS
    /// 26 asks a second time before an app captures the screen itself, and that prompt belongs in the setup. The main
    /// display at 64 pixels, no cursor, through ScreenCaptureKit only (the path a turn's screenshot takes, with Aris's
    /// own windows and the private apps left out as always); the frame is dropped here and only what came of it goes
    /// back. Never without the grant (macOS's own Screen Recording request is never raised) or under secure input.
    func firstCapture() async -> ArisFirstCapture.Outcome {
        guard CGPreflightScreenCaptureAccess(), !IsSecureEventInputEnabled() else { return .unknown }
        let (image, declined) = await screenCaptureKit(display: CGMainDisplayID(), budget: .consent, showsCursor: false)
        let outcome = ArisFirstCapture.outcome(gotImage: image != nil, declined: declined)
        log.info("first capture (setup): \(String(describing: outcome), privacy: .public)")
        return outcome
    }

    // MARK: - Capture chain

    /// ScreenCaptureKit, then CGWindowList. Never under secure input, whoever asks: it's checked before and again
    /// after each grab, and a frame taken while it came on is dropped. The fallback runs only with the grant: without
    /// it CGWindowList still returns a frame, but of the wallpaper and menu bar alone, which would pass the blank floor
    /// and reach the AI as "the screen". `declined` is true when the user turned the permission down (no retry).
    private func grab(display: CGDirectDisplayID, budget: ArisImageBudget, showsCursor: Bool) async -> (image: CGImage?, declined: Bool) {
        guard !IsSecureEventInputEnabled() else { return (nil, false) }
        let (image, declined) = await screenCaptureKit(display: display, budget: budget, showsCursor: showsCursor)
        if let image { return IsSecureEventInputEnabled() ? (nil, false) : (image, false) }
        guard !declined, !Task.isCancelled, !IsSecureEventInputEnabled(), CGPreflightScreenCaptureAccess() else { return (nil, declined) }
        let composite = windowList(display: display, budget: budget)
        return (IsSecureEventInputEnabled() ? nil : composite, false)
    }

    private func screenCaptureKit(display id: CGDirectDisplayID, budget: ArisImageBudget, showsCursor: Bool) async -> (image: CGImage?, declined: Bool) {
        do {
            // Every app, not only those with on-screen windows, so a private app's window that appears mid-grab
            // is still excluded.
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let display = content.displays.first(where: { $0.displayID == id }) else { return (nil, false) }
            let excluded = content.applications.filter {
                ArisCaptureRules.excludes(bundleId: $0.bundleIdentifier, pid: $0.processID, ownPid: ownPid, ownBundleId: ownBundleId)
            }
            let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
            let scale = CGFloat(filter.pointPixelScale)
            let size = budget.fit(CGSize(width: CGFloat(display.width) * scale, height: CGFloat(display.height) * scale))
            guard size != .zero else { return (nil, false) }
            let configuration = SCStreamConfiguration()
            configuration.width = Int(size.width)
            configuration.height = Int(size.height)
            configuration.showsCursor = showsCursor
            configuration.capturesAudio = false
            return (try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration), false)
        } catch {
            let error = error as NSError
            log.error("ScreenCaptureKit gave nothing: \(error.domain, privacy: .public) \(error.code)")
            return (nil, ArisCaptureRules.isUserDeclined(domain: error.domain, code: error.code))
        }
    }

    /// The display composed from every on-screen window except Aris's, the private apps' and any whose owner can't be
    /// resolved (no cursor).
    private func windowList(display: CGDirectDisplayID, budget: ArisImageBudget) -> CGImage? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return nil }
        var bundles: [pid_t: String?] = [:]
        var kept: [UnsafeRawPointer?] = []
        for window in windows {
            guard let number = window[kCGWindowNumber as String] as? Int, number > 0,
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t else { continue }
            if bundles[pid] == nil { bundles[pid] = .some(NSRunningApplication(processIdentifier: pid)?.bundleIdentifier) }
            guard ArisCaptureRules.fallbackKeeps(bundleId: bundles[pid] ?? nil, pid: pid, ownPid: ownPid, ownBundleId: ownBundleId) else { continue }
            kept.append(UnsafeRawPointer(bitPattern: number))
        }
        let bounds = CGDisplayBounds(display)
        let mode = CGDisplayCopyDisplayMode(display)
        let native = mode.map { CGSize(width: $0.pixelWidth, height: $0.pixelHeight) } ?? bounds.size
        // Grab at point size when that still covers the budget: a 5K display then composes 4× fewer pixels.
        let resolution: CGWindowImageOption = ArisCaptureRules.fallbackUsesNominal(native: native, points: bounds.size, budget: budget)
            ? .nominalResolution : .bestResolution
        guard !kept.isEmpty, let array = CFArrayCreate(kCFAllocatorDefault, &kept, kept.count, nil),
              let image = (ArisLegacyCapture() as any ArisLegacyCapturing).image(of: bounds, windows: array, option: [resolution, .boundsIgnoreFraming]) else {
            log.error("CGWindowList gave nothing")
            return nil
        }
        let got = CGSize(width: image.width, height: image.height), target = budget.fit(native)
        return target == got || target.width > got.width ? image : ArisImageCodec.scaled(image, to: target)
    }

    // MARK: - Helpers

    @MainActor
    private static func pointerAndScreens() -> (CGPoint, [(id: CGDirectDisplayID, frame: CGRect)]) {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        let screens = NSScreen.screens.compactMap { screen -> (id: CGDirectDisplayID, frame: CGRect)? in
            (screen.deviceDescription[key] as? NSNumber).map { (CGDirectDisplayID($0.uint32Value), screen.frame) }
        }
        return (NSEvent.mouseLocation, screens)
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Int {
        let elapsed = ContinuousClock.now - start
        return Int(elapsed.components.seconds * 1_000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
    }
}

/// CGWindowList capture is deprecated in favour of ScreenCaptureKit; Aris uses it only as the fallback, and calls it
/// through this protocol so the one deliberate use doesn't warn on every build.
private protocol ArisLegacyCapturing {
    func image(of bounds: CGRect, windows: CFArray, option: CGWindowImageOption) -> CGImage?
}

private struct ArisLegacyCapture: ArisLegacyCapturing {
    @available(macOS, deprecated: 14.0, message: "the fallback when ScreenCaptureKit gives nothing")
    func image(of bounds: CGRect, windows: CFArray, option: CGWindowImageOption) -> CGImage? {
        CGImage(windowListFromArrayScreenBounds: bounds, windowArray: windows, imageOption: option)
    }
}
