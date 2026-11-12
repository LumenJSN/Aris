import AppKit
import SwiftUI
import XCTest
@testable import BotAvatarsKit

/// A fabric avatar's canvas renders asynchronously, but its drawing — which
/// reads and writes the rig, the material caches, the show gate and the
/// hold — runs on the main thread: in a real window, through changes of
/// type, size and light and the bakes landing for them.
@MainActor
final class CanvasThreadTests: XCTestCase {
    @Observable final class Look {
        var type: BotAvatarType = .clover
        var size = 64.0
        var light = 295.0
    }
    struct Host: View {
        let look: Look
        var body: some View {
            BotAvatar(type: look.type, size: look.size, shading: .fabric, light: look.light).frame(width: 160, height: 160)
        }
    }

    func testFabricCanvasDrawsOnTheMainThread() throws {
        guard NSScreen.main != nil else { throw XCTSkip("no screen to show a window on") }
        XCTAssertTrue(BotAvatarRendering.asynchronousFabric)
        let look = Look()
        let win = NSWindow(contentRect: NSRect(x: 20, y: 20, width: 160, height: 160), styleMask: [.borderless], backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.contentView = NSHostingView(rootView: Host(look: look))
        win.orderFrontRegardless()
        defer { win.orderOut(nil) }
        BotAvatarRendering.resetThreads()
        let bakes0 = BotAvatarFabricBakeInfo.last.count
        for (i, (type, size)) in [(BotAvatarType.clover, 64.0), (.cat, 32), (.cloud, 96), (.blob, 64)].enumerated() {
            look.type = type
            look.size = size
            look.light = 300 + 20 * Double(i)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.5))
        }
        let t = BotAvatarRendering.threads
        print("canvas draws: \(t.main) on the main thread, \(t.offMain) off it; \(BotAvatarFabricBakeInfo.last.count - bakes0) bakes landed")
        if t.main + t.offMain == 0 { throw XCTSkip("the window was never drawn (no display)") }
        XCTAssertGreaterThan(t.main, 100)
        XCTAssertEqual(t.offMain, 0, "drawn off the main thread on \(t.offMainNames)")
        XCTAssertGreaterThanOrEqual(BotAvatarFabricBakeInfo.last.count - bakes0, 4)
    }
}
