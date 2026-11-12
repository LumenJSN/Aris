import XCTest
import BotAvatarsKit
import BotAvatarsRendering

/// The shadings that were there before fabric draw exactly as they did:
/// a still of each, hashed, against the hash the vendored package gave
/// (at bfb396b, before fabric). Clover's and cat's were re-pinned at the
/// 1c87c11 sync: their palette colours are the web's now (#41C4FF, #EAA06F);
/// cloud's colour did not change, and its still is the same as before.
@MainActor
final class ExistingShadingsTests: XCTestCase {
    private func stillHash(_ type: BotAvatarType, _ shading: BotAvatarShading) throws -> String {
        var cfg = BotAvatarDrawConfig(type: type)
        cfg.shading = shading
        cfg.still = true
        let img = try XCTUnwrap(StillRenderer.render(cfg, box: 96, scale: 2))
        return StillRenderer.hash(img)
    }

    private func assertUnchanged(_ shading: BotAvatarShading, _ golden: [BotAvatarType: String]) throws {
        for type in [BotAvatarType.clover, .cat, .cloud] {
            let got = try stillHash(type, shading)
            XCTAssertEqual(got, golden[type], "\(type) \(shading) still changed")
        }
    }

    func testPlasticStillsAreUnchanged() throws {
        try assertUnchanged(.plastic, [
            .clover: "932274e3869e69a1e4d674d43814f0eeddbe3dd46b514c49cf789048ffc3bab9",
            .cat: "e569a2be62ab81541f2e9b09a20628e6f86212f7ec6d248bb9760a7f328fc6df",
            .cloud: "9fcd61b9fd913aa507e756e09f765ae7d6f15dc91641860b9d4ad1dfcbb571ba",
        ])
    }

    func testCrispStillsAreUnchanged() throws {
        try assertUnchanged(.crisp, [
            .clover: "726fcf3e7fbaf92046ff94f3d193a60aeb9dbbe631c896798b70286d9593ca18",
            .cat: "aa355be5ded9a76e7616d910de13f4e8f82c5a3ca339da32d4137780b7f507bf",
            .cloud: "2bb8bcc0b95a4d67187504167e6d542c24eb3191b8f9446b323b5550f9ac9482",
        ])
    }

    func testSmoothStillsAreUnchanged() throws {
        try assertUnchanged(.smooth, [
            .clover: "b45c241828e3b213e011cacfba9484baf4a0ee0a95b08c7b905fceffb9d48894",
            .cat: "ed0907fca2fb3112a163e25983e49f71d2db0a94dab959a3f544c0dfcb7b2dd0",
            .cloud: "7ad8aa777f61d7406bcbf7fa2a682f3b75b0042e2dbc3ea102907c22764394a2",
        ])
    }

    func testFlatStillsAreUnchanged() throws {
        try assertUnchanged(.flat, [
            .clover: "a6928f058c53f7a7e35ae10cfbe716a6d7713fdc151a2751fee8301216a63f7b",
            .cat: "6e736e7422e199e181c0cc8cca252de68f61af616d3cccb6a37175f0d9115a95",
            .cloud: "dd877fb7ab83fed45b9deffbe1c6caf29b87e06d9235b34609dd987cf2fedb36",
        ])
    }
}
