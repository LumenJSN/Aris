//
//  ArisNativeShot.swift
//  aris-agent
//
//  Aris's own engine: a picture of one app's window only (ScreenCaptureKit, the window by its window-server id, covered
//  or in the background alike; `screencapture -l` when ScreenCaptureKit can't), saved as a PNG; the annotated copy has
//  each element's box and number drawn on it, for a brain that looks at the picture.
//

import AppKit
import Foundation
import ScreenCaptureKit

enum ArisNativeShot {
    /// The error a look's picture that couldn't be taken carries (the controller asks macOS about Screen Recording again).
    static let failedCode = "CAPTURE_FAILED"

    /// ScreenCaptureKit needs the window server's connection made (an AppKit app's own start makes it).
    private static let prepared: Void = {
        if Thread.isMainThread { _ = NSApplication.shared } else { DispatchQueue.main.sync { _ = NSApplication.shared } }
    }()

    /// The window's picture at `path`; false when none could be taken.
    static func capture(window: Int, to path: String) -> Bool {
        if captureKit(window: window, to: path) { return true }
        let result = ArisSkillProcess.run("/usr/sbin/screencapture", ["-x", "-o", "-l", String(window), path], environment: [:], timeout: 10)
        return result.ok && FileManager.default.fileExists(atPath: path)
    }

    private static func captureKit(window id: Int, to path: String) -> Bool {
        _ = prepared
        let done = DispatchSemaphore(value: 0)
        let box = ArisNativeImageBox()
        Task.detached {
            defer { done.signal() }
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false),
                  let window = content.windows.first(where: { Int($0.windowID) == id }) else { return }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let configuration = SCStreamConfiguration()
            let scale = Double(filter.pointPixelScale)
            configuration.width = max(1, Int(window.frame.width * scale))
            configuration.height = max(1, Int(window.frame.height * scale))
            configuration.showsCursor = false
            box.image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        }
        guard done.wait(timeout: .now() + 8) == .success, let image = box.image else { return false }
        return write(image, to: path)
    }

    static func write(_ image: CGImage, to path: String) -> Bool {
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: URL(fileURLWithPath: path), options: .atomic)) != nil
    }

    /// The picture at `source` with each element's box and its number drawn on it (`frame`: the window's, global points),
    /// written to `path`.
    static func annotate(source: String, to path: String, frame: CGRect, elements: [(number: Int, box: CGRect)]) -> Bool {
        guard let image = NSImage(contentsOfFile: source)?.cgImage(forProposedRect: nil, context: nil, hints: nil), frame.width > 0 else { return false }
        let scale = CGFloat(image.width) / frame.width
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let height = CGFloat(image.height)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        defer { NSGraphicsContext.current = nil }
        for (number, box) in elements where box.width > 2 && box.height > 2 {
            let rect = CGRect(x: (box.minX - frame.minX) * scale, y: height - (box.maxY - frame.minY) * scale, width: box.width * scale, height: box.height * scale)
            context.setStrokeColor(CGColor(red: 1, green: 0.2, blue: 0.2, alpha: 0.9))
            context.setLineWidth(2)
            context.stroke(rect)
            let label = NSAttributedString(string: "\(number)", attributes: [.font: NSFont.boldSystemFont(ofSize: 11 * scale / 2 + 6),
                                                                            .foregroundColor: NSColor.white, .backgroundColor: NSColor.systemRed])
            label.draw(at: CGPoint(x: rect.minX + 1, y: rect.maxY - label.size().height - 1))
        }
        guard let made = context.makeImage() else { return false }
        return write(made, to: path)
    }
}

private final class ArisNativeImageBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: CGImage?
    var image: CGImage? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
