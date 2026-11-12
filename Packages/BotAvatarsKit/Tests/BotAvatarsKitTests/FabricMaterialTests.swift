import CryptoKit
import QuartzCore
import XCTest
@testable import BotAvatarsKit
import BotAvatarsRendering

/// The pile: baked the same every time, off the main thread, and drawn.
final class FabricMaterialTests: XCTestCase {
    private func hash(_ fur: Fur) -> String {
        var h = SHA256()
        for img in [fur.mask, fur.haze, fur.core, fur.dark, fur.light, fur.glint, fur.back, fur.backSoft] {
            guard let img = img else { h.update(data: Data([0])); continue }
            h.update(data: Data(StillRenderer.rgba(img).bytes))
        }
        return h.finalize().map { String(format: "%02x", $0) }.joined()
    }

    func testPileIsDeterministic() {
        for (type, px) in [(BotAvatarType.clover, 192.0), (.cat, 128.0)] {
            let a = bakeFabricPile(type, devicePx: px), b = bakeFabricPile(type, devicePx: px)
            XCTAssertNotNil(a.1.dark)
            XCTAssertNotNil(a.1.mask)
            XCTAssertEqual(hash(a.1), hash(b.1), "\(type) at \(px) px baked two different piles")
            XCTAssertEqual(a.0.sd, b.0.sd)
        }
    }

    func testPilesDifferByShapeAndStyle() {
        let clover = hash(bakeFabricPile(.clover, devicePx: 128).1)
        XCTAssertNotEqual(clover, hash(bakeFabricPile(.cat, devicePx: 128).1))
        XCTAssertNotEqual(clover, hash(bakeFabricPile(.clover, devicePx: 128, style: BotAvatarFurStyle(length: 1.5)).1))
    }

    func testBakeRunsOffTheMainThread() {
        FabricBakes.clear()
        let before = FabricBakes.stats.count
        let landed = expectation(description: "the pile lands")
        let token = FabricBakes.onLanded { landed.fulfill() }
        defer { FabricBakes.stopLanded(token) }
        let t0 = CACurrentMediaTime()
        warmBotAvatarFabric(.cloud, devicePx: 128)
        /* the call only queues the bake */
        XCTAssertLessThan(CACurrentMediaTime() - t0, 0.05)
        XCTAssertTrue(FabricBakes.pendingAny)
        wait(for: [landed], timeout: 30)
        let stats = FabricBakes.stats
        XCTAssertEqual(stats.count, before + 1)
        XCTAssertFalse(stats.onMainThread)
        XCTAssertFalse(FabricBakes.pendingAny)
        var cfg = BotAvatarDrawConfig(type: .cloud)
        cfg.shading = .fabric
        cfg.scale = 2
        XCTAssertTrue(fabricIsBaked(cfg, box: 64))
    }

    @MainActor
    func testFabricStillDrawsThePileTheSameEachTime() throws {
        var cfg = BotAvatarDrawConfig(type: .blob)
        cfg.shading = .fabric
        cfg.still = true
        let a = try XCTUnwrap(StillRenderer.render(cfg, box: 96, scale: 2))
        let b = try XCTUnwrap(StillRenderer.render(cfg, box: 96, scale: 2))
        XCTAssertEqual(StillRenderer.hash(a), StillRenderer.hash(b))
        /* the material, not the smooth stand-in */
        cfg.shading = .smooth
        let smooth = try XCTUnwrap(StillRenderer.render(cfg, box: 96, scale: 2))
        XCTAssertNotEqual(StillRenderer.hash(a), StillRenderer.hash(smooth))
    }
}

/// An avatar that changes type keeps no light from the old outline.
final class FabricStateTests: XCTestCase {
    @MainActor
    func testChangingTypeDrawsTheNewOutlinesLight() throws {
        func cfg(_ type: BotAvatarType) -> BotAvatarDrawConfig {
            var c = BotAvatarDrawConfig(type: type, color: BotColor("#35B8FF"))
            c.shading = .fabric
            c.still = true
            return c
        }
        let st = BotAvatarRenderState()
        _ = StillRenderer.render(cfg(.clover), box: 96, scale: 2, state: st)
        let reused = try XCTUnwrap(StillRenderer.render(cfg(.cat), box: 96, scale: 2, state: st))
        let fresh = try XCTUnwrap(StillRenderer.render(cfg(.cat), box: 96, scale: 2))
        XCTAssertEqual(StillRenderer.hash(reused), StillRenderer.hash(fresh))
    }
}

/// Not shown until the pile is made, then the web's 0.3 s ease-out fade.
final class FabricShowGateTests: XCTestCase {
    func testWaitsThenFadesIn() throws {
        var ready = false
        let gate = FabricShowGate { ready }
        XCTAssertNil(gate.opacity(), "drawn before its pile is made")
        ready = true
        let a = try XCTUnwrap(gate.opacity())
        guard case .fading(let start) = gate.phase else { return XCTFail("not fading in") }
        XCTAssertLessThan(a, 0.2)
        let mid = try XCTUnwrap(gate.opacity(at: start + 0.15))
        XCTAssertGreaterThan(mid, 0.5)
        XCTAssertLessThan(mid, 1)
        XCTAssertEqual(gate.opacity(at: start + 0.31), 1)
        XCTAssertEqual(gate.phase, .shown)
    }

    func testEaseOutIsCSSs() {
        XCTAssertEqual(easeOut(0), 0, accuracy: 1e-9)
        XCTAssertEqual(easeOut(1), 1, accuracy: 1e-9)
        /* cubic-bezier(0, 0, 0.58, 1) at x = 0.5 */
        XCTAssertEqual(easeOut(0.5), 0.6847, accuracy: 0.002)
        var last = 0.0
        for i in 1...20 { let v = easeOut(Double(i) / 20); XCTAssertGreaterThanOrEqual(v, last); last = v }
    }
}
