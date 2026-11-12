import XCTest
@testable import BotAvatarsKit

/// The rig, the eyes and the colour as the web package has them at 1c87c11
/// (engine.ts, draw.ts, color.ts, presets.ts, BotAvatar.tsx): each test pins
/// one behaviour the iOS port lacked.
final class UpstreamMotionTests: XCTestCase {
    private let deg = Double.pi / 180

    private func run(_ sim: BotAvatarSim, seconds: Double, dt: Double = 1.0 / 60, each: (BotAvatarPose) -> Void = { _ in }) {
        for _ in 0..<Int((seconds / dt).rounded()) {
            sim.update(dt)
            each(sim.pose)
        }
    }

    func testJumpDefaultsAreTheWebs() {
        let j = BotAvatarJumpConfig.defaults
        XCTAssertEqual(j.groundTime, 0.11)
        XCTAssertEqual(j.groundEase, .pulse)
        XCTAssertEqual(j.riseTime, 0.33)
        XCTAssertEqual(j.riseEase, .pulse)
        XCTAssertEqual(j.squash, 1.15)
        XCTAssertEqual(j.squashTime, 0.37)
        XCTAssertEqual(j.clickSquashTime, 0.24)
        XCTAssertEqual(j.every, 8)
    }

    func testAJumpLandsInThreeParts() {
        let j = BotAvatarJumpConfig.defaults
        XCTAssertEqual(flipDuration(j, true), 0.24 + 0.68 + 2.0 / 7 * 0.24 + 0.11 + 0.33 + 0.05, accuracy: 1e-12)
        XCTAssertEqual(flipDuration(j, false), 0.2 * 0.68 + 0.68 + 2.0 / 7 * 0.37 + 0.11 + 0.33 + 0.05, accuracy: 1e-12)
        /* the press, the hold and the rise meet at the same depth */
        for e in BotAvatarSquashEase.allCases where e != .sharp {
            XCTAssertEqual(groundShape(0, e), 1, accuracy: 1e-12, "\(e)")
            XCTAssertEqual(groundShape(1, e), 1, accuracy: 1e-12, "\(e)")
            XCTAssertEqual(risePulse(0, e), 1, accuracy: 1e-12, "\(e)")
            XCTAssertEqual(risePulse(1, e), 0, accuracy: 1e-12, "\(e)")
        }
        XCTAssertEqual(squashPulse(2.0 / 7, .pulse), 1, accuracy: 1e-12)
    }

    func testSwitchesTakeTheWebsTimesOnASineEase() {
        func weightsAfter(_ from: BotAvatarState, _ to: BotAvatarState, _ seconds: Double) -> SIMD3<Double> {
            let sim = BotAvatarSim(seed: 0.3, state: from)
            sim.setState(to)
            run(sim, seconds: seconds, dt: 0.001)
            return sim.pose.w
        }
        XCTAssertEqual(weightsAfter(.default, .working, 0.7)[1], 1, accuracy: 1e-9)
        XCTAssertLessThan(weightsAfter(.default, .working, 0.69)[1], 1)
        XCTAssertEqual(weightsAfter(.working, .default, 1.2)[0], 1, accuracy: 1e-9)
        XCTAssertLessThan(weightsAfter(.working, .default, 1.15)[0], 1)
        XCTAssertEqual(weightsAfter(.default, .sleeping, 1.4)[2], 1, accuracy: 1e-9)
        XCTAssertEqual(weightsAfter(.sleeping, .default, 1.0)[0], 1, accuracy: 1e-9)
        XCTAssertLessThan(weightsAfter(.sleeping, .default, 0.95)[0], 1)
        /* a quarter of the way through, the sine ease (not the cubic) */
        XCTAssertEqual(weightsAfter(.default, .working, 0.175)[1], easeSine(0.25), accuracy: 1e-6)
    }

    func testIdleBlinksNeverWink() {
        let sim = BotAvatarSim(seed: 0.41)
        var blinks = 0, last = 0.0
        run(sim, seconds: 240) { p in
            XCTAssertEqual(p.blinkL, p.blinkR)
            if p.blinkL > 0.5 && last <= 0.5 { blinks += 1 }
            last = p.blinkL
        }
        XCTAssertGreaterThan(blinks, 40)
    }

    func testIdleHeadLooksToCornersAndHolds() {
        let sim = BotAvatarSim(seed: 0.62)
        sim.setJump(BotAvatarJumpConfig(every: 0))
        run(sim, seconds: 3)
        var held = 0, total = 0, maxYaw = 0.0
        run(sim, seconds: 120) { p in
            total += 1
            maxYaw = max(maxYaw, abs(p.yaw))
            if abs(p.yaw) > 0.8 * 35 * self.deg { held += 1 }
        }
        XCTAssertLessThan(maxYaw, 35.5 * deg, "the gaze reaches 35° at most")
        XCTAssertGreaterThan(Double(held) / Double(total), 0.45, "most of the time it is turned to a corner")
    }

    func testTurnZeroKeepsTheIdleHeadFacingForward() {
        let sim = BotAvatarSim(seed: 0.62)
        sim.setJump(BotAvatarJumpConfig(every: 0))
        sim.setTurn(0)
        run(sim, seconds: 3)
        run(sim, seconds: 60) { p in XCTAssertLessThan(abs(p.yaw), 1 * self.deg) }
    }

    func testIdleFlipsComeRoughlyEveryEightSeconds() {
        let sim = BotAvatarSim(seed: 0.2)
        var flips = 0, inFlip = false
        run(sim, seconds: 160) { p in
            let now = p.y < -15
            if now && !inFlip { flips += 1 }
            inFlip = now
        }
        /* 8 s ± 40 %: 160 s holds between 14 and 32 */
        XCTAssertGreaterThanOrEqual(flips, 14)
        XCTAssertLessThanOrEqual(flips, 32)
    }

    func testWorkingHopsOnItsPeriodAndEveryThirdSpins() {
        let sim = BotAvatarSim(seed: 0.81, state: .working)
        let dt = HOP_T / 68
        var ys: [Double] = [], yaws: [Double] = []
        run(sim, seconds: HOP_T * 9, dt: dt) { p in ys.append(p.y); yaws.append(p.yaw) }
        /* the highest point of each hop: one per period, every third higher */
        let tops = (0..<9).map { k in ys[(k * 68)..<((k + 1) * 68)].min()! }
        XCTAssertLessThan(tops[2], tops[0] - 4)
        XCTAssertLessThan(tops[5], tops[3] - 4)
        XCTAssertLessThan(tops[8], tops[6] - 4)
        /* a spinning hop turns right round */
        let spin = yaws[(2 * 68 + 67)] - yaws[2 * 68]
        XCTAssertEqual(abs(spin), 2 * .pi, accuracy: 0.6)
    }

    func testLeavingWorkSettlesThroughTheHoldAndTheRise() {
        let sim = BotAvatarSim(seed: 0.81, state: .working)
        run(sim, seconds: HOP_T * 3 + HOP_T * 0.5, dt: 0.001)
        sim.setState(.default)
        /* the hop under way flies on (≤ half a period), lands, holds 0.11 s and rises 0.33 s */
        run(sim, seconds: HOP_T * 0.5 + 0.11 + 0.33 + 0.02, dt: 0.001)
        var maxDev = 0.0
        run(sim, seconds: 0.5, dt: 0.001) { p in maxDev = max(maxDev, abs(p.sy - 1)) }
        XCTAssertLessThan(maxDev, 0.06, "only breath and jelly once the last landing has risen")
    }

    func testTheEyesLeadAHeadTurn() {
        let sim = BotAvatarSim(seed: 0.62)
        sim.setJump(BotAvatarJumpConfig(every: 0))
        var lead = 0.0
        var prevYaw = 0.0
        run(sim, seconds: 30) { p in
            let v = p.yaw - prevYaw
            prevYaw = p.yaw
            if abs(v) > 0.004 { lead = max(lead, (v > 0 ? 1 : -1) * p.lookX) }
        }
        XCTAssertGreaterThan(lead, 1, "a fast turn carries the eyes ahead of it")
    }

    func testTheSameSeedMovesTheSame() {
        let a = BotAvatarSim(seed: 0.5), b = BotAvatarSim(seed: 0.5)
        for _ in 0..<1200 {
            a.update(1.0 / 60); b.update(1.0 / 60)
            XCTAssertEqual(a.pose.yaw, b.pose.yaw)
            XCTAssertEqual(a.pose.y, b.pose.y)
        }
    }

    func testEyeMimic() {
        var p = BotAvatarPose.rest(.default)
        XCTAssertEqual(eyeMimic(p).tall, 1)
        XCTAssertEqual(eyeMimic(p).wide, 1)
        p.pitch = -0.26
        XCTAssertEqual(eyeMimic(p).tall, 1.55, accuracy: 1e-12)
        XCTAssertEqual(eyeMimic(p).wide, 0.95, accuracy: 1e-12)
        p.pitch = 0.26
        XCTAssertEqual(eyeMimic(p).tall, 0.45, accuracy: 1e-12)
        p = .rest(.default)
        p.lookX = 4.5
        XCTAssertEqual(eyeMimic(p).tall, 0.9, accuracy: 1e-12)
        XCTAssertEqual(eyeMimic(p).wide, 1.12, accuracy: 1e-12)
        /* a breath's drift keeps the shape */
        p = .rest(.default)
        p.pitch = 0.05
        XCTAssertEqual(eyeMimic(p).tall, 1)
    }

    func testPresetsAreTheWebs() {
        XCTAssertEqual(BotAvatarType.star.preset.brightness, 1.1)
        XCTAssertEqual(BotAvatarType.star.preset.saturation, 1.84)
        XCTAssertEqual(BotAvatarType.clover.preset.color, BotColor("#41C4FF"))
        XCTAssertEqual(BotAvatarType.cat.preset.color, BotColor("#EAA06F"))
        XCTAssertNil(BotAvatarType.ghost.preset.saturation)
    }

    func testRicher() {
        let c = BotColor("#EFDB8E")!
        XCTAssertEqual(c.richer(0), c)
        let r = c.richer(0.34)
        for v in [r.r, r.g, r.b] {
            XCTAssertEqual(v, v.rounded(), "whole channels, as the web's rgb()")
            XCTAssertTrue((0...255).contains(v))
        }
        let (_, s0, _) = rgbToHsl(c.r, c.g, c.b), (_, s1, _) = rgbToHsl(r.r, r.g, r.b)
        XCTAssertGreaterThan(s1, s0, "more vivid")
        XCTAssertEqual(BotColor(r: 128, g: 128, b: 128).richer(1), BotColor(r: 128, g: 128, b: 128), "a grey has no hue to push")
    }

    func testTheStarTakesItsOwnColourAndVivid() {
        let p = BotAvatarProps(type: .star, face: nil, state: .default, size: 64, color: nil, ink: nil, brightness: nil, saturation: nil, speed: 1, paused: true, seed: 0.5, shading: .fabric, light: BotAvatarLightOptions(), fabric: BotAvatarFabricOptions(), depth: 0.65, interactive: false, theme: .dark, whirl: .off, jump: .defaults, scale: 2, reduceMotion: false)
        let cfg = BotAvatarModel.drawConfig(p)
        XCTAssertEqual(cfg.vivid, 0.34, accuracy: 1e-12)
        XCTAssertEqual(cfg.color, BotColor("#EFDB8E")!.shade(0.1 * 0.35, 0.25).richer(0.34 + 0 * 1e-16))
        /* saturation past 1.5 shades only to 1.5; the rest is vivid */
        var q = p
        q.saturation = 2.5
        XCTAssertEqual(BotAvatarModel.drawConfig(q).vivid, 1)
        XCTAssertEqual(BotAvatarModel.drawConfig(q).color, BotColor("#EFDB8E")!.shade(0.1 * 0.35, 0.25).richer(1))
    }

    func testTheViewDefaultsAreTheWebs() {
        let v = BotAvatar()
        XCTAssertEqual(v.shading, .fabric)
        XCTAssertNil(v.brightness)
        XCTAssertNil(v.saturation)
        XCTAssertEqual(v.turn, 1)
    }
}
