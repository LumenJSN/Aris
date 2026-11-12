import SwiftUI
import XCTest
@testable import BotAvatarsKit

/// Fabric's own knobs and the per-shading light defaults, as the web's
/// `LIGHT_DEFAULTS` and `BotAvatar` props resolve them.
final class FabricOptionsTests: XCTestCase {
    /// The props `BotAvatar` hands its model, all at their defaults.
    private func props(_ shading: BotAvatarShading) -> BotAvatarProps {
        BotAvatarProps(type: .clover, face: nil, state: .default, size: 96, color: nil, ink: nil, brightness: 1, saturation: 1.5, speed: 1, paused: true, seed: 0.5, shading: shading, light: BotAvatarLightOptions(), fabric: BotAvatarFabricOptions(), depth: 0.65, interactive: false, theme: .dark, whirl: .off, jump: .defaults, scale: 2, reduceMotion: false)
    }

    func testFabricLightDefaults() {
        let d = BotAvatarLighting.defaults(for: .fabric)
        XCTAssertEqual(d, BotAvatarLighting(shadow: 1.15, highlight: 1.45, light: 295, rim: 0.6, spread: 1.6))
    }

    func testOtherShadingsKeepTheirLightDefaults() {
        for shading in [BotAvatarShading.plastic, .crisp, .smooth, .flat] {
            XCTAssertEqual(BotAvatarLighting.defaults(for: shading), BotAvatarLighting(shadow: 0.35, highlight: 1.3, light: 265, rim: 0.5, spread: 1.55), "\(shading)")
        }
    }

    func testLibraryDefaultShadingIsFabricAsOnTheWeb() {
        XCTAssertEqual(BotAvatar().shading, .fabric)
        /* the low-level config keeps its own default; the web's has none */
        XCTAssertEqual(BotAvatarDrawConfig(type: .cat).shading, .plastic)
    }

    func testUnsetLightResolvesPerShading() {
        let fabric = BotAvatarModel.drawConfig(props(.fabric)).lighting
        XCTAssertEqual(fabric, BotAvatarLighting(shadow: 1.15, highlight: 1.45, light: 295, rim: 0.6, spread: 1.6))
        let plastic = BotAvatarModel.drawConfig(props(.plastic)).lighting
        XCTAssertEqual(plastic, BotAvatarLighting(shadow: 0.35, highlight: 1.3, light: 265, rim: 0.5, spread: 1.55))
    }

    func testGivenLightOverridesTheDefault() {
        var p = props(.fabric)
        p.light = BotAvatarLightOptions(shadow: 0.5, highlight: 0.9, light: 200, rim: 1.2, spread: 2)
        XCTAssertEqual(BotAvatarModel.drawConfig(p).lighting, BotAvatarLighting(shadow: 0.5, highlight: 0.9, light: 200, rim: 1.2, spread: 2))
    }

    func testLightClampsToItsRanges() {
        var p = props(.fabric)
        p.light = BotAvatarLightOptions(shadow: 9, highlight: -1, light: 300, rim: 5, spread: 0.1)
        XCTAssertEqual(BotAvatarModel.drawConfig(p).lighting, BotAvatarLighting(shadow: 2, highlight: 0, light: 300, rim: 2, spread: 0.4))
    }

    func testFabricDefaults() {
        let f = BotAvatarModel.drawConfig(props(.fabric)).fabric
        XCTAssertNil(f.backLight)
        XCTAssertEqual(f.lightFront, 32)
        XCTAssertEqual(f.shine, 0)
        XCTAssertEqual(f.sheen, 0)
        XCTAssertEqual(f.backSoftness, 1)
        XCTAssertEqual(f.roundness, 1)
        XCTAssertEqual(f.fur, BotAvatarFurStyle(length: 1, density: 1.6, fuzz: 0.9, clumps: 0.4, curl: 0.7, gravity: 0.9))
        XCTAssertEqual(f.fur, .stock)
    }

    func testFabricClampsToItsRanges() {
        var p = props(.fabric)
        p.fabric = BotAvatarFabricOptions(backLight: 40, lightFront: 120, shine: 3, sheen: -1, backSoftness: 2, roundness: -0.5, furLength: 9, furDensity: 0.1, furFuzz: 2, furClumps: -1, furCurl: 1.5, furGravity: -0.2)
        let f = BotAvatarModel.drawConfig(p).fabric
        XCTAssertEqual(f.backLight, 40)
        XCTAssertEqual(f.lightFront, 85)
        XCTAssertEqual(f.shine, 2)
        XCTAssertEqual(f.sheen, 0)
        XCTAssertEqual(f.backSoftness, 1)
        XCTAssertEqual(f.roundness, 0)
        XCTAssertEqual(f.fur, BotAvatarFurStyle(length: 2.5, density: 0.3, fuzz: 1, clumps: 0, curl: 1, gravity: 0))

        p.fabric = BotAvatarFabricOptions(lightFront: -10, shine: -1, sheen: 7, backSoftness: -1, roundness: 3, furLength: 0, furDensity: 5)
        let g = BotAvatarModel.drawConfig(p).fabric
        XCTAssertEqual(g.lightFront, 0)
        XCTAssertEqual(g.shine, 0)
        XCTAssertEqual(g.sheen, 2)
        XCTAssertEqual(g.backSoftness, 0)
        XCTAssertEqual(g.roundness, 1)
        XCTAssertEqual(g.fur.length, 0.3)
        XCTAssertEqual(g.fur.density, 2)
    }

    func testFurStyleSnapsToTwentieths() {
        /* as the web rounds it, so a slider does not bake a pile per pixel */
        var p = props(.fabric)
        p.fabric = BotAvatarFabricOptions(furLength: 1.234, furCurl: 0.512)
        let f = BotAvatarModel.drawConfig(p).fabric.fur
        XCTAssertEqual(f.length, 1.25, accuracy: 1e-12)
        XCTAssertEqual(f.curl, 0.5, accuracy: 1e-12)
    }

    func testReadmeExamplesCompile() {
        /* README.md's fabric examples, verbatim */
        _ = BotAvatar(type: .cat, size: 96, shading: .fabric)
        _ = BotAvatar(type: .cloud, shading: .fabric, sheen: 0.4, furLength: 1.4, furGravity: 0.5)
    }

    func testViewTakesTheFabricParameters() {
        let v = BotAvatar(type: .cat, shading: .fabric, backLight: 10, lightFront: 40, shine: 0.5, sheen: 0.3, backSoftness: 0.4, roundness: 0.8, furLength: 1.2, furDensity: 1.1, furFuzz: 0.5, furClumps: 0.6, furCurl: 0.2, furGravity: 0.3)
        XCTAssertEqual(v.shading, .fabric)
        XCTAssertNil(v.shadow)
        XCTAssertEqual(v.fabric, BotAvatarFabricOptions(backLight: 10, lightFront: 40, shine: 0.5, sheen: 0.3, backSoftness: 0.4, roundness: 0.8, furLength: 1.2, furDensity: 1.1, furFuzz: 0.5, furClumps: 0.6, furCurl: 0.2, furGravity: 0.3))
    }
}
