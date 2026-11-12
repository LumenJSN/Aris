import QuartzCore
import SwiftUI

/// An animated bot avatar: one of eighteen glossy 3D shapes with a living
/// face, in one of three states. The SwiftUI port of the web `<BotAvatar>`:
/// the same rig, renderer and plastic material, drawn into a `Canvas`.
///
/// The view lays out `size` square; its canvas is 1.5× that and pulls
/// itself back, so a hop or a flip is never clipped while the layout stays
/// exactly `size`.
public struct BotAvatar: View {
    /// Body shape. Default `clover`.
    public var type: BotAvatarType = .clover
    /// Face kind. Defaults to the type's own.
    public var face: BotAvatarFace? = nil
    /// What the bot is doing: `default` (idle), `working` (hopping, spinning) or `sleeping`.
    public var state: BotAvatarState = .default
    /// Rendered size in points. Default 64.
    public var size: Double = 64
    /// Body colour. Defaults to the type's palette colour.
    public var color: BotColor? = nil
    /// Face ink. Defaults to dark, or light on a dark body.
    public var ink: BotColor? = nil
    /// Lightness of the body colour: 1 as the palette has it. Default: the
    /// type's own (`BotAvatarPreset.brightness`), else 1.
    public var brightness: Double? = nil
    /// Saturation of the body colour: 1 as the palette has it, up to 2.5
    /// (past 1.5 the colour is pushed toward its most vivid shade). Default:
    /// the type's own (`BotAvatarPreset.saturation`), else 1.5.
    public var saturation: Double? = nil
    /// Multiplier on every animation's speed. Default 1.
    public var speed: Double = 1
    /// Freeze every animation on its current frame.
    public var paused: Bool = false
    /// 0–1. Offsets the blink and glance timing. Defaults to a random value per instance.
    public var seed: Double? = nil
    /// How the body is lit. Default `fabric`, as on the web since 0.2.0.
    public var shading: BotAvatarShading = .fabric
    /// Strength of the shadow side, 0–2. Default 0.35 (1.15 for `fabric`).
    public var shadow: Double? = nil
    /// Strength of the lit side, 0–2. Default 1.3 (1.45 for `fabric`).
    public var highlight: Double? = nil
    /// Thickness of the body, 0.2–2. Default 0.65.
    public var depth: Double = 0.65
    /// Where the light comes from, in degrees clockwise from the top. Default 265 (295 for `fabric`).
    public var light: Double? = nil
    /// Width of the lit rim in `crisp`, strength of the Fresnel rim in `plastic`, of the back light in `fabric`, 0–2. Default 0.5 (0.6 for `fabric`).
    public var rim: Double? = nil
    /// Reach of the soft shading in `smooth`, width of the highlight in `plastic`, how far the light wraps round in `fabric`, 0.4–2.5. Default 1.55 (1.6 for `fabric`).
    public var spread: Double? = nil
    /// `fabric`'s own knobs, as given (clamped when drawn).
    var fabric = BotAvatarFabricOptions()
    /// Touch play: a tap makes the avatar hop and turn right round, and
    /// while a finger drags over it the eyes and head follow the finger (it
    /// stands in for the web's pointer). Default true.
    public var interactive: Bool = true
    /// The surface the avatar sits on; `nil` (auto) reads the colour scheme.
    /// Resolved but unused by the drawing, as on the web.
    public var theme: ColorScheme? = nil
    /// The whirl round a spin. Off by default.
    public var whirl: BotAvatarWhirl = .off
    /// The jump's numbers (an idle flip's and a tap's).
    public var jump: BotAvatarJumpConfig = .defaults
    /// How far the head turns to the side while idle: 1 as the gaze has it,
    /// 0 keeps it facing forward, 0–2. Default 1.
    public var turn: Double = 1

    @State private var model = BotAvatarModel()
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - shadow, highlight, light, rim, spread: the light; nil takes the
    ///     shading's own default (`BotAvatarLighting.defaults(for:)`).
    ///   - backLight: `fabric`: where the back light comes from, degrees
    ///     clockwise from the top. Default: above the toy, toward the side
    ///     away from `light`.
    ///   - lightFront: `fabric`: how far round to the front the key sits,
    ///     degrees — 0 grazes the toy from the side, 85 lights it nearly from
    ///     the camera. 0–85, default 32.
    ///   - shine: `fabric`: the highlights along single fibres where the key
    ///     grazes the pile, 0–2. Default 0 (a soft, matte pile).
    ///   - sheen: `fabric`: the smooth, satin sheen over the body's edge, 0–2.
    ///     Default 0.
    ///   - backSoftness: `fabric`: how soft the back light is — 0 a small
    ///     source caught on single fibres, 1 a large one, an even glow. 0–1,
    ///     default 1.
    ///   - roundness: `fabric`: the body's profile through its depth — 1 a
    ///     cushion, toward 0 a slab with softened edges. 0–1, default 1.
    ///   - furLength: `fabric`: length of the pile, 0.3–2.5. Default 1.
    ///   - furDensity: `fabric`: how many fibres, 0.3–2. Default 1.6.
    ///   - furFuzz: `fabric`: softness of the silhouette, 0–1. Default 0.9.
    ///   - furClumps: `fabric`: how much the fibres gather into tufts, 0–1. Default 0.4.
    ///   - furCurl: `fabric`: how wavy the fibres are, 0–1. Default 0.7.
    ///   - furGravity: `fabric`: how much the pile hangs, 0–1. Default 0.9.
    public init(type: BotAvatarType = .clover, face: BotAvatarFace? = nil, state: BotAvatarState = .default, size: Double = 64, color: BotColor? = nil, ink: BotColor? = nil, brightness: Double? = nil, saturation: Double? = nil, speed: Double = 1, paused: Bool = false, seed: Double? = nil, shading: BotAvatarShading = .fabric, shadow: Double? = nil, highlight: Double? = nil, depth: Double = 0.65, light: Double? = nil, rim: Double? = nil, spread: Double? = nil, backLight: Double? = nil, lightFront: Double = 32, shine: Double = 0, sheen: Double = 0, backSoftness: Double = 1, roundness: Double = 1, furLength: Double = 1, furDensity: Double = 1.6, furFuzz: Double = 0.9, furClumps: Double = 0.4, furCurl: Double = 0.7, furGravity: Double = 0.9, interactive: Bool = true, turn: Double = 1, theme: ColorScheme? = nil, whirl: BotAvatarWhirl = .off, jump: BotAvatarJumpConfig = .defaults) {
        self.type = type; self.face = face; self.state = state; self.size = size; self.color = color; self.ink = ink
        self.brightness = brightness; self.saturation = saturation; self.speed = speed; self.paused = paused; self.seed = seed
        self.shading = shading; self.shadow = shadow; self.highlight = highlight; self.depth = depth; self.light = light; self.rim = rim; self.spread = spread
        self.fabric = BotAvatarFabricOptions(backLight: backLight, lightFront: lightFront, shine: shine, sheen: sheen, backSoftness: backSoftness, roundness: roundness, furLength: furLength, furDensity: furDensity, furFuzz: furFuzz, furClumps: furClumps, furCurl: furCurl, furGravity: furGravity)
        self.interactive = interactive; self.turn = turn; self.theme = theme; self.whirl = whirl; self.jump = jump
    }

    private var props: BotAvatarProps {
        BotAvatarProps(type: type, face: face, state: state, size: size, color: color, ink: ink, brightness: brightness, saturation: saturation, speed: speed, paused: paused, seed: seed, shading: shading, light: BotAvatarLightOptions(shadow: shadow, highlight: highlight, light: light, rim: rim, spread: spread), fabric: fabric, depth: depth, interactive: interactive, turn: turn, theme: theme ?? colorScheme, whirl: whirl, jump: jump, scale: min(2, displayScale), reduceMotion: reduceMotion)
    }

    public var body: some View {
        BotAvatarBody(model: model, props: props, label: "\(type.preset.label) bot, \(state.label)")
    }
}

/// The view proper: the canvas overlaid on a `size`-square frame, the
/// gestures and the prop sync.
private struct BotAvatarBody: View {
    let model: BotAvatarModel
    let props: BotAvatarProps
    let label: String
    @Environment(\.botAvatarStage) private var stage

    var body: some View {
        let size = props.size
        let full = size * BOT_AVATAR_OVERSCAN
        Color.clear
            .frame(width: size, height: size)
            .overlay {
                /* on a stage the stage's canvas draws this avatar */
                if stage == nil {
                    BotAvatarCanvas(model: model)
                        .frame(width: full, height: full)
                        .offset(y: -BOT_AVATAR_RISE * size)
                        .allowsHitTesting(false)
                }
            }
            .background(GeometryReader { g in
                let global = g.frame(in: .global)
                let local = stage.map { g.frame(in: .named($0.spaceName)) } ?? .zero
                Color.clear
                    .onAppear { model.globalFrame = global; stage?.register(model, frame: local) }
                    .onChange(of: global) { _, f in model.globalFrame = f }
                    .onChange(of: local) { _, f in stage?.register(model, frame: f) }
                    .onDisappear { stage?.unregister(model) }
            })
            .contentShape(Rectangle())
            .onTapGesture { if props.interactive && !props.paused && props.speed > 0 { model.sim.poke() } }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { v in if props.interactive { BotAvatarPointer.shared.location = v.location } }
                    .onEnded { _ in BotAvatarPointer.shared.location = nil }
            )
            .onChange(of: props, initial: true) { _, p in model.apply(p) }
            .onDisappear { model.disappear() }
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isImage)
    }
}

/// Everything the view hands its model, compared as a whole.
struct BotAvatarProps: Equatable {
    var type: BotAvatarType
    var face: BotAvatarFace?
    var state: BotAvatarState
    var size: Double
    var color: BotColor?
    var ink: BotColor?
    var brightness: Double?
    var saturation: Double?
    var speed: Double
    var paused: Bool
    var seed: Double?
    var shading: BotAvatarShading
    var light: BotAvatarLightOptions
    var fabric: BotAvatarFabricOptions
    var depth: Double
    var interactive: Bool
    var turn: Double = 1
    var theme: ColorScheme
    var whirl: BotAvatarWhirl
    var jump: BotAvatarJumpConfig
    var scale: Double
    var reduceMotion: Bool
}

/// The light as the view was given it: nil takes the shading's default.
struct BotAvatarLightOptions: Equatable {
    var shadow: Double? = nil
    var highlight: Double? = nil
    var light: Double? = nil
    var rim: Double? = nil
    var spread: Double? = nil
}

/// Fabric's knobs as the view was given them.
struct BotAvatarFabricOptions: Equatable {
    var backLight: Double? = nil
    var lightFront: Double = 32
    var shine: Double = 0
    var sheen: Double = 0
    var backSoftness: Double = 1
    var roundness: Double = 1
    var furLength: Double = 1
    var furDensity: Double = 1.6
    var furFuzz: Double = 0.9
    var furClumps: Double = 0.4
    var furCurl: Double = 0.7
    var furGravity: Double = 0.9

    /// In range; the pile's style rounded to twentieths, as the web does, so
    /// a slider does not bake a pile per pixel.
    var look: BotAvatarFabricLook {
        func q(_ v: Double, _ lo: Double, _ hi: Double) -> Double { (clamp(v, lo, hi) * 20).rounded() / 20 }
        let fur = BotAvatarFurStyle(length: q(furLength, 0.3, 2.5), density: q(furDensity, 0.3, 2), fuzz: q(furFuzz, 0, 1), clumps: q(furClumps, 0, 1), curl: q(furCurl, 0, 1), gravity: q(furGravity, 0, 1))
        return BotAvatarFabricLook(backLight: backLight.flatMap { $0.isFinite ? $0 : nil }, lightFront: clamp(lightFront, 0, 85), shine: clamp(shine, 0, 2), sheen: clamp(sheen, 0, 2), backSoftness: clamp(backSoftness, 0, 1), roundness: clamp(roundness, 0, 1), fur: fur)
    }
}

/// How avatars' canvases render, and on which threads their drawing ran.
public enum BotAvatarRendering {
    /// A standalone fabric avatar's canvas renders asynchronously (RenderBox
    /// encodes its layers off the main thread; the drawing itself still runs
    /// on the main thread). Default true.
    public static var asynchronousFabric = true

    /// Every canvas draw so far: how many ran on the main thread, how many
    /// off it, and the names of the threads off it (the bench's evidence).
    public struct Threads: Sendable { public var main = 0, offMain = 0; public var offMainNames: Set<String> = [] }
    private static let lock = NSLock()
    private static var _threads = Threads()
    public static var threads: Threads { lock.lock(); defer { lock.unlock() }; return _threads }
    public static func resetThreads() { lock.lock(); _threads = Threads(); lock.unlock() }
    static func noteCanvasDraw() {
        let main = Thread.isMainThread
        let name = main ? "" : (Thread.current.name.flatMap { $0.isEmpty ? nil : $0 } ?? String(cString: __dispatch_queue_get_label(nil)))
        lock.lock()
        if main { _threads.main += 1 } else { _threads.offMain += 1; _threads.offMainNames.insert(name) }
        lock.unlock()
    }
}

/// The canvas: observes the shared clock and draws the model's pose.
private struct BotAvatarCanvas: View {
    let model: BotAvatarModel
    var body: some View {
        /* reading the clock's frame here makes the canvas redraw each tick */
        let frame = BotAvatarClock.shared.frame
        /* fabric's frame is the body's layer, its sprites' and the films: its
           rendering (RenderBox encoding the layers for the GPU) takes most of a
           frame's main-thread time when done there, so it is done off it; the
           recording stays on the main thread, the pixels are the same */
        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: model.props?.shading == .fabric && BotAvatarRendering.asynchronousFabric) { ctx, size in
            BotAvatarRendering.noteCanvasDraw()
            model.draw(&ctx, size: size, frame: frame)
        }
    }
}

/// How far the pointer's pull reaches, in head widths.
private let REACH = 3.0

@inline(__always) private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, v.isFinite ? v : 1)) }

/// The state behind one avatar: its rig, its draw config and the material
/// caches. Plain class, not observed: the clock drives the redraws.
final class BotAvatarModel {
    let sim: BotAvatarSim
    var cfg: BotAvatarDrawConfig
    let render = BotAvatarRenderState()
    var props: BotAvatarProps? = nil
    var globalFrame = CGRect.zero
    private var running = false
    private var frozen = false
    private var restOnly = false
    private var lastDrawnFrame = -1
    /// fabric: not shown until its pile is made, then faded in
    private var gate: FabricShowGate? = nil
    /// fabric: the last look drawn in its own pile, and the device size that
    /// pile was made for — drawn while a new look bakes (the web's `hold`),
    /// for SHOW_WITHIN at most
    private var held: (cfg: BotAvatarDrawConfig, tierPx: Double)? = nil
    private var holdSince: CFTimeInterval? = nil
    /// CPU seconds of the last tick and the last draw, for the demo.
    private(set) var lastTick = 0.0
    private(set) var lastDraw = 0.0

    init() {
        sim = BotAvatarSim(seed: Double.random(in: 0..<1))
        cfg = BotAvatarDrawConfig(type: .clover)
    }

    /// The draw config for a set of props: the body colour, the light
    /// (the shading's defaults where the props leave it), every knob in range.
    static func drawConfig(_ p: BotAvatarProps) -> BotAvatarDrawConfig {
        let preset = p.type.preset
        let picked = p.color ?? preset.color
        /* the type's own brightness and saturation where the props leave them out */
        let brightness = p.brightness ?? preset.brightness ?? 1
        let saturation = p.saturation ?? preset.saturation ?? 1.5
        /* past 1.5 the colour itself is as saturated as it goes for most of the
           palette: the rest deepens it and makes the light keep more of it */
        let vivid = clamp(saturation, 1.5, 2.5) - 1.5
        let body = (brightness == 1 && saturation == 1
            ? picked
            : picked.shade((min(2, max(0, brightness)) - 1) * 0.35, (min(1.5, max(0, saturation)) - 1) * 0.5)).richer(vivid)
        var c = BotAvatarDrawConfig(type: p.type, face: p.face, color: body, ink: p.ink)
        c.vivid = vivid
        c.shading = p.shading
        let d = BotAvatarLighting.defaults(for: p.shading)
        c.shadow = clamp(p.light.shadow ?? d.shadow, 0, 2)
        c.highlight = clamp(p.light.highlight ?? d.highlight, 0, 2)
        c.depth = clamp(p.depth, 0.2, 2)
        c.light = p.light.light ?? d.light
        c.rim = clamp(p.light.rim ?? d.rim, 0, 2)
        c.spread = clamp(p.light.spread ?? d.spread, 0.4, 2.5)
        c.fabric = p.fabric.look
        c.theme = p.theme
        c.scale = p.scale
        c.whirl = BotAvatarWhirl(strength: clamp(p.whirl.strength, 0, 2), size: clamp(p.whirl.size, 0.6, 1.6), width: clamp(p.whirl.width, 0.4, 2), length: clamp(p.whirl.length, 0.4, 1.6), tilt: clamp(p.whirl.tilt, 0.5, 1.8))
        c.still = p.paused || !(p.speed > 0) || p.reduceMotion
        /* a still avatar's pile bakes in the background all the same: the
           view waits for it (see FabricShowGate) and draws again when it lands */
        c.bakeFabricOnIdle = true
        return c
    }

    func apply(_ p: BotAvatarProps) {
        let first = props == nil
        let old = props
        props = p
        let c = BotAvatarModel.drawConfig(p)
        frozen = p.paused || !(p.speed > 0)
        restOnly = p.reduceMotion
        cfg = c
        if first, let seed = p.seed {
            /* a given seed replaces the random one: rebuild the rig */
            sim.reseed(min(1, max(0, seed)), state: p.state)
        } else if old?.seed != p.seed, let seed = p.seed {
            sim.reseed(min(1, max(0, seed)), state: p.state)
        } else {
            sim.setState(p.state, immediate: first)
        }
        var j = p.jump
        j.time = max(0.2, j.time)
        j.spin = max(0, j.spin.rounded())
        j.squashTime = max(0.05, j.squashTime)
        j.groundTime = max(0, j.groundTime)
        j.riseTime = max(0.05, j.riseTime)
        j.clickSquashTime = max(0.05, j.clickSquashTime)
        sim.setJump(j)
        sim.setTurn(clamp(p.turn, 0, 2))
        /* plastic bakes its form per type; start that in the background now */
        if p.shading == .plastic && !c.still {
            warmBotAvatarPlastic(p.type, devicePx: p.size * p.scale, depth: c.depth)
        }
        /* fabric bakes its form and pile per type and size: in the
           background, the avatar not shown until they land */
        if p.shading == .fabric {
            warmBotAvatarFabric(p.type, devicePx: p.size * p.scale, depth: c.depth, light: c.lighting.light, look: c.fabric)
            if gate == nil {
                gate = FabricShowGate { [weak self] in
                    guard let self = self, let p = self.props else { return false }
                    return fabricIsBaked(self.cfg, box: p.size)
                }
            }
        }
        if frozen || restOnly { stop() } else { start() }
    }

    private func start() {
        if running { return }
        running = true
        BotAvatarClock.shared.subscribe(ObjectIdentifier(self)) { [weak self] dt in self?.tick(dt) }
    }
    /// The view is gone: no frames for it, its fade's included.
    func disappear() {
        stop()
        gate?.stop()
    }

    func stop() {
        if !running { return }
        running = false
        BotAvatarClock.shared.unsubscribe(ObjectIdentifier(self))
    }

    private func tick(_ dt: Double) {
        guard let p = props else { return }
        let t0 = CFAbsoluteTimeGetCurrent()
        if p.interactive, let ptr = BotAvatarPointer.shared.location, globalFrame.width > 0 {
            let box = globalFrame.width
            let dx = (ptr.x - globalFrame.midX) / box
            let dy = (ptr.y - globalFrame.midY) / box
            let d = (dx * dx + dy * dy).squareRoot()
            /* full pull up close, gone by REACH */
            let strength = d < 1 ? 1 : d > REACH ? 0 : 1 - (d - 1) / (REACH - 1)
            sim.setPointer(x: dx / max(1, d), y: dy / max(1, d), strength: strength)
        } else {
            sim.setPointer(x: 0, y: 0, strength: 0)
        }
        sim.update(dt * p.speed)
        let cost = CFAbsoluteTimeGetCurrent() - t0
        lastTick = cost
        BotAvatarClock.shared.stats.tickSeconds += cost
        BotAvatarClock.shared.stats.ticks += 1
    }

    /// The look to draw a shown fabric avatar in: its own once its pile is
    /// made; until then the last one drawn, in the pile it was made for (a
    /// shown avatar keeps its picture while a new shape, size or light
    /// bakes, rather than standing in with the smooth look). Main thread
    /// only, as the gate is: the canvas draws on it.
    private func fabricLook(box: Double) -> BotAvatarDrawConfig {
        if fabricIsBaked(cfg, box: box) {
            held = (cfg, box * cfg.scale)
            holdSince = nil
            return cfg
        }
        guard let h = held else { return cfg }
        let now = CACurrentMediaTime()
        if holdSince == nil { holdSince = now }
        var old = h.cfg
        old.fabricTierPx = h.tierPx
        guard now - holdSince! < SHOW_WITHIN, fabricIsBaked(old, box: box) else { return cfg }
        return old
    }

    func draw(_ ctx: inout GraphicsContext, size: CGSize, frame: Int) {
        guard let p = props else { return }
        let t0 = CFAbsoluteTimeGetCurrent()
        let box = size.width / BOT_AVATAR_OVERSCAN
        let pose = restOnly ? BotAvatarPose.rest(p.state) : sim.pose
        if cfg.shading == .fabric, let gate = gate {
            dispatchPrecondition(condition: .onQueue(.main))
            /* waiting for its pile: nothing; fading in: as one layer */
            guard let a = gate.opacity() else { return }
            let look = fabricLook(box: box)
            if a < 1 {
                var c = ctx
                let t = c.transform
                c.opacity *= a
                c.drawLayer { l in
                    l.transform = t
                    l.opacity = 1
                    drawBotAvatarFrame(&l, box: box, pose: pose, cfg: look, state: render)
                }
            } else {
                drawBotAvatarFrame(&ctx, box: box, pose: pose, cfg: look, state: render)
            }
        } else {
            drawBotAvatarFrame(&ctx, box: box, pose: pose, cfg: cfg, state: render)
        }
        let cost = CFAbsoluteTimeGetCurrent() - t0
        lastDraw = cost
        if running && frame != lastDrawnFrame {
            BotAvatarClock.shared.stats.drawSeconds += cost
            BotAvatarClock.shared.stats.draws += 1
        }
        lastDrawnFrame = frame
    }
}

/* ── the pointer over a larger surface ─────────────────────────────── */

private struct BotAvatarPointerModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { v in BotAvatarPointer.shared.location = v.location }
                .onEnded { _ in BotAvatarPointer.shared.location = nil }
        )
    }
}

public extension View {
    /// While a finger drags over this view, every `interactive` avatar
    /// within three head widths of it follows the finger — the web's
    /// pointer play over a whole page.
    func botAvatarPointer() -> some View { modifier(BotAvatarPointerModifier()) }
}
