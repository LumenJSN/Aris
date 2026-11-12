import SwiftUI

/* Aris addition (not upstream): drawing an avatar outside its view, in a
   pose of the caller's own, so the Sim's frames can be baked once into
   sprites and played without redrawing the fabric. */

/// What a baked frame depends on besides its look: the web source this port is
/// at and the Aris revision of the drawing. Bump it whenever a change here
/// would draw a frame differently, so atlases cached on disk bake again.
public let botAvatarsKitRenderVersion = "1c87c11+aris.2"

public extension BotAvatar {
    /// The config this avatar draws with on a display of `scale` in `theme`,
    /// still: for `drawBotAvatarFrame` with a pose of your own. Its pile
    /// bakes in the background (as a paused view's does); draw once
    /// `botAvatarFabricIsBaked` says so, not before.
    func drawConfig(scale: Double, theme: ColorScheme) -> BotAvatarDrawConfig {
        let props = BotAvatarProps(type: type, face: face, state: state, size: size, color: color, ink: ink, brightness: brightness,
                                   saturation: saturation, speed: speed, paused: true, seed: seed, shading: shading,
                                   light: BotAvatarLightOptions(shadow: shadow, highlight: highlight, light: light, rim: rim, spread: spread),
                                   fabric: fabric, depth: depth, interactive: false, turn: turn, theme: theme, whirl: whirl, jump: jump,
                                   scale: min(2, scale), reduceMotion: false)
        var cfg = BotAvatarModel.drawConfig(props)
        cfg.still = true
        return cfg
    }
}

/// Whether `cfg`'s fabric body is baked for a box of `box` points (other
/// shadings always are): until then a frame draws a stand-in or nothing.
public func botAvatarFabricIsBaked(_ cfg: BotAvatarDrawConfig, box: Double) -> Bool {
    cfg.shading != .fabric || fabricIsBaked(cfg, box: box)
}
