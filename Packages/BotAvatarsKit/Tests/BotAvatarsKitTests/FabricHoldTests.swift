import SwiftUI
import XCTest
@testable import BotAvatarsKit

/// A shown fabric avatar keeps its look while a new one bakes (the web's
/// hold): no smooth stand-in between the two.
@MainActor
final class FabricHoldTests: XCTestCase {
    private func props(_ type: BotAvatarType, _ size: Double) -> BotAvatarProps {
        BotAvatarProps(type: type, face: nil, state: .default, size: size, color: nil, ink: nil, brightness: 1, saturation: 1.5, speed: 1, paused: true, seed: 0.5, shading: .fabric, light: BotAvatarLightOptions(), fabric: BotAvatarFabricOptions(), depth: 0.65, interactive: false, theme: .dark, whirl: .off, jump: .defaults, scale: 2, reduceMotion: false)
    }

    /// One frame of the model, as its canvas draws it.
    private func draw(_ m: BotAvatarModel, _ size: Double) {
        let full = size * BOT_AVATAR_OVERSCAN
        let px = Int(full * 2)
        let g = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: px * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let view = Canvas { ctx, s in m.draw(&ctx, size: s, frame: 0) }.frame(width: full, height: full)
        ImageRenderer(content: view).render(rasterizationScale: 2) { _, d in g.scaleBy(x: 2, y: 2); d(g) }
    }

    private func waitForBakes() {
        let deadline = Date(timeIntervalSinceNow: 60)
        while FabricBakes.pendingAny && Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01)) }
        /* the landing's callbacks run on the main queue */
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertFalse(FabricBakes.pendingAny)
    }

    func testHoldsTheShownLookAcrossATierAndATypeChange() {
        FabricBakes.clear()
        let m = BotAvatarModel()
        m.apply(props(.clover, 32))
        waitForBakes()
        draw(m, 32)
        XCTAssertEqual(m.render.standIns, 0)

        /* 32 → 96 pt: 64 → 192 device px, a new form and pile tier */
        m.apply(props(.clover, 96))
        XCTAssertTrue(FabricBakes.pendingAny, "the new size's pile is not baking")
        draw(m, 96)
        XCTAssertEqual(m.render.standIns, 0, "a smooth frame while the new size baked")
        XCTAssertEqual(m.render.fabric.form?.N, 64, "not the held look's own pile")
        waitForBakes()
        draw(m, 96)

        /* a new type */
        m.apply(props(.cat, 96))
        XCTAssertTrue(FabricBakes.pendingAny, "the new type's pile is not baking")
        draw(m, 96)
        XCTAssertEqual(m.render.standIns, 0, "a smooth frame while the new type baked")
        waitForBakes()
        draw(m, 96)
        XCTAssertEqual(m.render.standIns, 0)
        XCTAssertEqual(m.render.fabric.form?.N, 96)
    }
}

/// The show gate never keeps the shared frame loop running for an avatar
/// that is not drawn: a landing nudges one redraw, the fade's frames end
/// with the fade, and a view that disappears lets go at once.
@MainActor
final class FabricGateClockTests: XCTestCase {
    private func land(_ type: BotAvatarType) {
        FabricBakes.clear()
        let landed = expectation(description: "a pile lands")
        let token = FabricBakes.onLanded { landed.fulfill() }
        warmBotAvatarFabric(type, devicePx: 64)
        wait(for: [landed], timeout: 60)
        FabricBakes.stopLanded(token)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
    }
    private func subscribed(_ g: FabricShowGate) -> Bool { BotAvatarClock.shared.isSubscribed(ObjectIdentifier(g)) }

    func testAFadeNobodyDrawsEndsByItself() {
        var ready = false
        let gate = FabricShowGate { ready }
        ready = true
        land(.ghost)
        /* the landing started the fade; nothing draws the avatar */
        guard case .fading = gate.phase else { return XCTFail("not fading in") }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: SHOW_FADE + 0.2))
        XCTAssertFalse(subscribed(gate), "the fade kept the frame loop running")
    }

    func testALandingOnAShownAvatarOnlyNudges() throws {
        let gate = FabricShowGate { true }
        _ = gate.opacity()
        guard case .fading(let start) = gate.phase else { return XCTFail("not fading in") }
        XCTAssertEqual(gate.opacity(at: start + 1), 1)
        gate.stop()
        let frame = BotAvatarClock.shared.frame
        land(.pill)
        XCTAssertFalse(subscribed(gate), "a landing subscribed a shown avatar to the frame loop")
        XCTAssertGreaterThan(BotAvatarClock.shared.frame, frame, "no redraw after the landing")
    }

    func testDisappearingLetsGo() {
        let gate = FabricShowGate { true }
        _ = gate.opacity()
        XCTAssertTrue(subscribed(gate))
        gate.stop()
        XCTAssertFalse(subscribed(gate))
    }
}
