import Foundation

/// The eighteen body shapes, in the web library's order.
public enum BotAvatarType: String, CaseIterable, Identifiable, Sendable {
    case clover, flower, triangle, square, blob, ghost, circle, drop, star, droid, mech, alien, hexagon, cat, cloud, pill, pebble, puddle
    public var id: String { rawValue }
}

/// What the face is made of: the eyes alone, or eyes and a small mouth
/// that changes with the state.
public enum BotAvatarFace: String, CaseIterable, Identifiable, Sendable {
    case eyes, mouth
    public var id: String { rawValue }
}

/// What the bot is doing. Each state is a pose plus its own motion.
public enum BotAvatarState: String, CaseIterable, Identifiable, Sendable {
    case `default`, working, sleeping
    public var id: String { rawValue }
    /// The web's `stateLabels`.
    public var label: String {
        switch self {
        case .default: return "idle"
        case .working: return "working"
        case .sleeping: return "sleeping"
        }
    }
}

/// How the body is lit. `plastic` (default): a glossy material shaded per
/// pixel; `crisp`: a lit rim with a clean edge; `smooth`: a soft shadow and
/// highlight over the whole form; `flat`: the depth alone; `fabric`: a
/// plush faux fur — a baked pile of locks and fibres over the inflated
/// body, lit by a low key and a back light, with a soft fringe of hairs
/// past the edge.
public enum BotAvatarShading: String, CaseIterable, Identifiable, Sendable {
    case plastic, crisp, smooth, flat, fabric
    public var id: String { rawValue }
}

/// The light a body is drawn in: the strengths of its shadow and lit
/// sides, where the key comes from, the rim and the spread.
public struct BotAvatarLighting: Equatable, Sendable {
    /// Strength of the shadow side, 0–2.
    public var shadow: Double
    /// Strength of the lit side, 0–2.
    public var highlight: Double
    /// Where the light comes from, in degrees clockwise from the top.
    public var light: Double
    /// The lit rim (`crisp`), the Fresnel rim (`plastic`), the back light (`fabric`), 0–2.
    public var rim: Double
    /// The soft shading's reach (`smooth`), the highlight's width
    /// (`plastic`), how far the light wraps round (`fabric`), 0.4–2.5.
    public var spread: Double

    public init(shadow: Double, highlight: Double, light: Double, rim: Double, spread: Double) {
        self.shadow = shadow; self.highlight = highlight; self.light = light; self.rim = rim; self.spread = spread
    }

    /// The light each material looks its best in where the caller leaves
    /// it (the web's `LIGHT_DEFAULTS`): a plush pile wants a broad, low
    /// studio light that shows its lobes and grain; the other shadings keep
    /// this port's own defaults.
    public static func defaults(for shading: BotAvatarShading) -> BotAvatarLighting {
        shading == .fabric ? fabricDefaults : otherDefaults
    }
    static let fabricDefaults = BotAvatarLighting(shadow: 1.15, highlight: 1.45, light: 295, rim: 0.6, spread: 1.6)
    static let otherDefaults = BotAvatarLighting(shadow: 0.35, highlight: 1.3, light: 265, rim: 0.5, spread: 1.55)
}

/// The pile's style (the web's `FurStyle`): `length` and `density`
/// multiply the base fibres', `fuzz` is how soft the silhouette is,
/// `clumps` how much the fibres gather into tufts, `curl` how wavy they
/// are, `gravity` how much they hang down.
public struct BotAvatarFurStyle: Hashable, Sendable {
    /// Length of the pile, 0.3–2.5.
    public var length: Double
    /// How many fibres, 0.3–2.
    public var density: Double
    /// Softness of the silhouette, 0–1.
    public var fuzz: Double
    /// How much the fibres gather into tufts, 0–1.
    public var clumps: Double
    /// How wavy the fibres are, 0–1.
    public var curl: Double
    /// How much the pile hangs, combed down from a parting at the top, 0–1.
    public var gravity: Double

    public init(length: Double = 1, density: Double = 1.6, fuzz: Double = 0.9, clumps: Double = 0.4, curl: Double = 0.7, gravity: Double = 0.9) {
        self.length = length; self.density = density; self.fuzz = fuzz; self.clumps = clumps; self.curl = curl; self.gravity = gravity
    }

    /// The web's `FUR_STOCK`.
    public static let stock = BotAvatarFurStyle()
}

/// Fabric's own knobs on a draw config, resolved and in range.
public struct BotAvatarFabricLook: Equatable, Sendable {
    /// Where the back light comes from, degrees clockwise from the top;
    /// nil: above the toy, toward the side away from the key.
    public var backLight: Double? = nil
    /// How far round to the front the key sits, degrees, 0–85.
    public var lightFront: Double = 32
    /// Strength of the highlights along single fibres, 0–2.
    public var shine: Double = 0
    /// The smooth, satin sheen over the body's edge, 0–2.
    public var sheen: Double = 0
    /// How soft the back light is, 0–1.
    public var backSoftness: Double = 1
    /// The profile through the depth: 1 a cushion, toward 0 a slab with
    /// softened edges.
    public var roundness: Double = 1
    /// The pile.
    public var fur: BotAvatarFurStyle = .stock

    public init(backLight: Double? = nil, lightFront: Double = 32, shine: Double = 0, sheen: Double = 0, backSoftness: Double = 1, roundness: Double = 1, fur: BotAvatarFurStyle = .stock) {
        self.backLight = backLight; self.lightFront = lightFront; self.shine = shine; self.sheen = sheen
        self.backSoftness = backSoftness; self.roundness = roundness; self.fur = fur
    }
}

/// How the landing squash of a jump plays out.
public enum BotAvatarSquashEase: String, CaseIterable, Identifiable, Sendable {
    case sharp, pulse, soft, bouncy
    public var id: String { rawValue }
}

public struct BotAvatarPreset: Sendable {
    /// Display name, for labels.
    public let label: String
    /// The type's own body colour.
    public let color: BotColor
    /// The face the type ships with.
    public let face: BotAvatarFace
    /// Where the face sits, in the 100×100 body box.
    public let faceX: Double
    public let faceY: Double
    /// Face scale: shapes with a small middle wear a smaller face.
    public let faceScale: Double
    /// The type's own brightness and saturation, used where the props leave
    /// them out (the web's `BotAvatarPreset.brightness` / `.saturation`).
    public var brightness: Double? = nil
    public var saturation: Double? = nil
}

/// The eighteen types: each body has its own colour and says where on it
/// the face sits. Every type wears the eyes alone by default.
public let botAvatarPresets: [BotAvatarType: BotAvatarPreset] = [
    .clover: .init(label: "Clover", color: BotColor("#41C4FF")!, face: .eyes, faceX: 50, faceY: 50, faceScale: 1, brightness: 1.2, saturation: 1.59),
    .flower: .init(label: "Flower", color: BotColor("#2FCB7A")!, face: .eyes, faceX: 50, faceY: 51, faceScale: 0.95),
    .triangle: .init(label: "Triangle", color: BotColor("#DC48FF")!, face: .eyes, faceX: 50, faceY: 61, faceScale: 0.9),
    .square: .init(label: "Square", color: BotColor("#35B8FF")!, face: .eyes, faceX: 50, faceY: 50, faceScale: 1),
    .blob: .init(label: "Blob", color: BotColor("#2FCB7A")!, face: .eyes, faceX: 49.5, faceY: 50, faceScale: 1),
    .ghost: .init(label: "Ghost", color: BotColor("#F4F2FA")!, face: .eyes, faceX: 50, faceY: 48, faceScale: 0.95),
    .circle: .init(label: "Circle", color: BotColor("#9A62FF")!, face: .eyes, faceX: 50, faceY: 50, faceScale: 1),
    .drop: .init(label: "Drop", color: BotColor("#1ED3C6")!, face: .eyes, faceX: 50, faceY: 62, faceScale: 0.9),
    .star: .init(label: "Star", color: BotColor("#EFDB8E")!, face: .eyes, faceX: 50, faceY: 52, faceScale: 0.82, brightness: 1.1, saturation: 1.84),
    .droid: .init(label: "Droid", color: BotColor("#D5DBEA")!, face: .eyes, faceX: 50, faceY: 60, faceScale: 0.95),
    .mech: .init(label: "Mech", color: BotColor("#95A6C4")!, face: .eyes, faceX: 50, faceY: 59, faceScale: 1),
    .alien: .init(label: "Alien", color: BotColor("#9CD66A")!, face: .eyes, faceX: 50, faceY: 45, faceScale: 1.05),
    .hexagon: .init(label: "Hexagon", color: BotColor("#EB7575")!, face: .eyes, faceX: 50, faceY: 50, faceScale: 0.95),
    .cat: .init(label: "Cat", color: BotColor("#EAA06F")!, face: .eyes, faceX: 50, faceY: 58, faceScale: 1, brightness: 1.22, saturation: 1.88),
    .cloud: .init(label: "Cloud", color: BotColor("#CFD5E4")!, face: .eyes, faceX: 50, faceY: 58, faceScale: 0.95),
    .pill: .init(label: "Pill", color: BotColor("#ACAAF3")!, face: .eyes, faceX: 50, faceY: 50, faceScale: 0.9),
    .pebble: .init(label: "Pebble", color: BotColor("#ABC793")!, face: .eyes, faceX: 50, faceY: 50, faceScale: 0.95),
    .puddle: .init(label: "Puddle", color: BotColor("#EE8BDB")!, face: .eyes, faceX: 50, faceY: 50, faceScale: 0.95),
]

public extension BotAvatarType {
    var preset: BotAvatarPreset { botAvatarPresets[self]! }
    /// Body colour by type — the palette on its own.
    var paletteColor: BotColor { preset.color }
}

/// The jump's numbers: an idle flip's and a click's.
public struct BotAvatarJumpConfig: Equatable, Sendable {
    /// how high, in body units (the body is 100 tall)
    public var height: Double = 26
    /// seconds in the air
    public var time: Double = 0.68
    /// how much the body stretches in the air, 0–2
    public var stretch: Double = 1
    /// how much it squashes on the ground, before take-off and on landing, 0–2
    public var squash: Double = 1.15
    /// seconds the landing squash takes, contact to recovered
    public var squashTime: Double = 0.37
    /// the landing squash's shape
    public var squashEase: BotAvatarSquashEase = .pulse
    /// seconds a click's jump takes for its landing squash
    public var clickSquashTime: Double = 0.24
    /// whole turns in the air
    public var spin: Double = 1
    /// degrees of lean into it
    public var lean: Double = 6
    /// seconds between idle jumps, roughly (±40 %); 0 for none
    public var every: Double = 8
    /// when the landing squash begins: seconds before (negative) or after
    /// touch-down; 0 is the moment of contact
    public var land: Double = 0

    /// seconds the body holds its deepest squash on the ground
    public var groundTime: Double = 0.11
    /// how the weight settles through that hold
    public var groundEase: BotAvatarSquashEase = .pulse
    /// seconds the body takes to rise from its deepest squash back to shape
    public var riseTime: Double = 0.33
    /// how it rises
    public var riseEase: BotAvatarSquashEase = .pulse

    public init(height: Double = 26, time: Double = 0.68, stretch: Double = 1, squash: Double = 1.15, squashTime: Double = 0.37, squashEase: BotAvatarSquashEase = .pulse, groundTime: Double = 0.11, groundEase: BotAvatarSquashEase = .pulse, riseTime: Double = 0.33, riseEase: BotAvatarSquashEase = .pulse, clickSquashTime: Double = 0.24, spin: Double = 1, lean: Double = 6, every: Double = 8, land: Double = 0) {
        self.height = height; self.time = time; self.stretch = stretch; self.squash = squash; self.squashTime = squashTime
        self.squashEase = squashEase; self.groundTime = groundTime; self.groundEase = groundEase; self.riseTime = riseTime; self.riseEase = riseEase
        self.clickSquashTime = clickSquashTime; self.spin = spin; self.lean = lean; self.every = every; self.land = land
    }

    /// The web's `JUMP_DEFAULTS`.
    public static let defaults = BotAvatarJumpConfig()
}

/// The whirl round a spin: its strength and the ring's shape. Off by
/// default (`strength` 0); 1 turns it on.
public struct BotAvatarWhirl: Equatable, Sendable {
    /// 0–2; off at 0
    public var strength: Double = 0
    /// size of the ring, 0.6–1.6
    public var size: Double = 1
    /// thickness of the trail, 0.4–2
    public var width: Double = 1
    /// length of the trail round the ring, 0.4–1.6
    public var length: Double = 1
    /// how flat the ring is seen, 0.5–1.8 (higher is more open)
    public var tilt: Double = 1
    public init(strength: Double = 0, size: Double = 1, width: Double = 1, length: Double = 1, tilt: Double = 1) {
        self.strength = strength; self.size = size; self.width = width; self.length = length; self.tilt = tilt
    }
    public static let off = BotAvatarWhirl()
    public static let on = BotAvatarWhirl(strength: 1)
}
