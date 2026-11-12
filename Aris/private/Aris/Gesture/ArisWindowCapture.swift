//
//  ArisWindowCapture.swift
//  Aris
//
//  One picked window, captured on its own with ScreenCaptureKit (`desktopIndependentWindow`): only that window's
//  pixels, nothing over it (Aris's wash included), no cursor, no shadow, within a 2560 px long edge. Never under
//  secure input (checked before and after), only with the grant (nothing here asks for it), and never a window of
//  Aris, a private app or an owner with no bundle id (checked again here, whatever the click said). In memory only.
//

import AppKit
import Carbon.HIToolbox
import os
import ScreenCaptureKit

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "gesture")

actor ArisWindowCapture {
    static let shared = ArisWindowCapture()

    private let ownPid = getpid()
    private let ownBundleId = Bundle.main.bundleIdentifier ?? "com.lumenjsn.aris"

    func image(window id: CGWindowID) async -> CGImage? {
        guard !IsSecureEventInputEnabled(), CGPreflightScreenCaptureAccess() else {
            log.notice("window pick capture: skipped (secure input or no grant)")
            return nil
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            guard let window = content.windows.first(where: { $0.windowID == id }), let app = window.owningApplication,
                  ArisWindowPick.mayCapture(bundleId: app.bundleIdentifier, pid: app.processID, ownPid: ownPid,
                                            ownBundleId: ownBundleId) else {
                log.notice("window pick capture: window gone or not allowed")
                return nil
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let scale = CGFloat(filter.pointPixelScale)
            let size = ArisGestureGeometry.scaledCropSize(CGSize(width: (window.frame.width * scale).rounded(),
                                                                 height: (window.frame.height * scale).rounded()))
            guard size.width >= 8, size.height >= 8 else { return nil }
            let configuration = SCStreamConfiguration()
            configuration.width = Int(size.width)
            configuration.height = Int(size.height)
            configuration.showsCursor = false
            configuration.capturesAudio = false
            configuration.ignoreShadowsSingleWindow = true
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            guard !IsSecureEventInputEnabled() else { return nil } // it came on mid-grab: drop the frame
            return image
        } catch {
            let error = error as NSError
            log.error("window pick capture failed: \(error.domain, privacy: .public) \(error.code)")
            return nil
        }
    }
}
