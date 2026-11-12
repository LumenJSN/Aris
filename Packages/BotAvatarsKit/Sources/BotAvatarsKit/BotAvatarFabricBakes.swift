import CoreGraphics
import Foundation

/* Fabric's bakes: the form and the pile per outline, kept and shared by
   every avatar of a type, made on a background queue. A port of the form
   and pile caches in plastic.ts at bfb396b (`formFor`, `furReady`,
   `furFor`, `warmPlastic`, `lightBin`, `furKey`, `bakesPending`,
   `onLanded`). The web bakes in idle-time steps on the main thread; here a
   bake is one job on a serial queue, so a screen full of types never
   stacks them into one frame and the main thread never runs one (unless a
   still frame asks for it now, as the web's does). */

private let SPAN = BOT_AVATAR_SPAN

/// What a pile is kept by: the outline, its depth, the pile's resolution,
/// the light in 15° bins, the style and the lights.
struct FurKey: Hashable {
    var key: String
    var halfDepth: Int
    var R: Int
    var bin: Int
    var style: BotAvatarFurStyle
    var lights: String
    /// the same shape at any size and light (a stand-in while this one bakes)
    var shape: String { "\(key)|\(halfDepth)" }
}

private struct FormKey: Hashable { var key: String; var N: Int; var halfDepth: Int }

/// light direction in 15° bins
func lightBin(_ lx: Double, _ ly: Double) -> Int { Int(jsRound(atan2(ly, lx) / (Double.pi / 12))) }

enum FabricBakes {
    private static let lock = NSLock()
    private static var forms: [FormKey: FabricForm] = [:]
    private static var furs: [FurKey: Fur] = [:]
    /** the order the piles were filed in, oldest first */
    private static var filed: [FurKey] = []
    private static var pending: Set<FurKey> = []
    private static let queue = DispatchQueue(label: "bot-avatars.fabric.bake", qos: .userInitiated)
    /** called on the main thread each time a pile lands */
    private static var landed: [UUID: () -> Void] = [:]

    /// The last bake's facts, for the tests and the bench: whether it ran
    /// on the main thread, and how long it took.
    struct Stats { var onMainThread = false; var seconds = 0.0; var count = 0 }
    private static var _stats = Stats()
    static var stats: Stats { lock.lock(); defer { lock.unlock() }; return _stats }

    /// Whether any pile is still being made.
    static var pendingAny: Bool { lock.lock(); defer { lock.unlock() }; return !pending.isEmpty }

    /// The form and pile for an outline, made now (`sync`) or on the bake
    /// queue (nil until then; meanwhile the same shape's pile at another
    /// size or light stands in, when there is one).
    static func ready(key: String, path: CGPath, N: Int, halfDepth: Double, capPx: Double, lx: Double, ly: Double, style: BotAvatarFurStyle, lights: FurLights, sync: Bool) -> (FabricForm, Fur)? {
        let R = furTier(capPx)
        let id = FurKey(key: key, halfDepth: Int(jsRound(halfDepth)), R: R, bin: lightBin(lx, ly), style: style, lights: lights.id)
        let fid = FormKey(key: key, N: N, halfDepth: Int(jsRound(halfDepth)))
        lock.lock()
        if let fur = furs[id], let form = forms[fid] { lock.unlock(); return (form, fur) }
        if sync {
            lock.unlock()
            let made = bake(id, fid, path: path, N: N, halfDepth: halfDepth, lx: lx, ly: ly, style: style, lights: lights)
            return made
        }
        if !pending.contains(id) {
            pending.insert(id)
            queue.async {
                _ = bake(id, fid, path: path, N: N, halfDepth: halfDepth, lx: lx, ly: ly, style: style, lights: lights)
                DispatchQueue.main.async { for fn in Array(landed.values) { fn() } }
            }
        }
        /* while it bakes, the same shape's pile at another tier or light will do */
        var standIn: (FabricForm, Fur)? = nil
        if let form = forms[fid] {
            for k in filed.reversed() where k.shape == id.shape { if let f = furs[k] { standIn = (form, f); break } }
        }
        lock.unlock()
        return standIn
    }

    /// The surface's height at (x, y) in the body box, from the outline's
    /// form at that depth, made at any tier (the web's `surfaceAt`, which takes
    /// the latest made; here the finest), shaped by `round`; nil before one is made.
    static func surfaceAt(key: String, halfDepth: Double, x: Double, y: Double, round: Double) -> Double? {
        let hd = Int(jsRound(halfDepth))
        lock.lock()
        let form = forms.filter { $0.key.key == key && $0.key.halfDepth == hd }.max { $0.key.N < $1.key.N }?.value
        lock.unlock()
        guard let form else { return nil }
        let N = form.N, h = form.h
        let u = SPAN / Double(N)
        let fx = min(Double(N - 1), max(0, (x + BOT_AVATAR_PAD) / u - 0.5)), fy = min(Double(N - 1), max(0, (y + BOT_AVATAR_PAD) / u - 0.5))
        let x0 = min(N - 2, Int(fx)), y0 = min(N - 2, Int(fy)), tx = fx - Double(x0), ty = fy - Double(y0), i = y0 * N + x0
        let v = (Double(h[i]) * (1 - tx) + Double(h[i + 1]) * tx) * (1 - ty) + (Double(h[i + N]) * (1 - tx) + Double(h[i + N + 1]) * tx) * ty
        let top = Double(h.max() ?? 0)
        if top <= 0 { return 0 }
        let q = max(0.05, min(1, round))
        return top * pow(max(0, v) / top, q)
    }

    /// Whether the form and pile for an outline are made (nothing is queued).
    static func has(key: String, N: Int, halfDepth: Double, capPx: Double, lx: Double, ly: Double, style: BotAvatarFurStyle, lights: FurLights) -> Bool {
        let id = FurKey(key: key, halfDepth: Int(jsRound(halfDepth)), R: furTier(capPx), bin: lightBin(lx, ly), style: style, lights: lights.id)
        let fid = FormKey(key: key, N: N, halfDepth: Int(jsRound(halfDepth)))
        lock.lock(); defer { lock.unlock() }
        return furs[id] != nil && forms[fid] != nil
    }

    /// Bake (or find) a form and a pile, and file them.
    private static func bake(_ id: FurKey, _ fid: FormKey, path: CGPath, N: Int, halfDepth: Double, lx: Double, ly: Double, style: BotAvatarFurStyle, lights: FurLights) -> (FabricForm, Fur)? {
        let t0 = CFAbsoluteTimeGetCurrent()
        let onMain = Thread.isMainThread
        lock.lock()
        let haveForm = forms[fid]
        lock.unlock()
        let form = haveForm ?? buildFabricForm(rasterizeBotAvatarOutline(path, N: N), N: N, halfDepth: halfDepth)
        let fur = FurBake(form: form, R: id.R, lx: lx, ly: ly, style: style, lights: lights).run()
        lock.lock()
        if forms[fid] == nil {
            if forms.count >= 48 { forms.removeAll() }
            forms[fid] = form
        }
        let kept = forms[fid] ?? form
        if furs[id] == nil {
            if furs.count >= 24, let old = filed.first { furs.removeValue(forKey: old); filed.removeFirst() }
            furs[id] = fur
            filed.append(id)
        }
        pending.remove(id)
        _stats = Stats(onMainThread: onMain, seconds: CFAbsoluteTimeGetCurrent() - t0, count: _stats.count + 1)
        let out = (kept, furs[id] ?? fur)
        lock.unlock()
        return out
    }

    /// Call `fn` on the main thread each time a pile lands, until the
    /// returned token is passed to `stopLanded`.
    @discardableResult
    static func onLanded(_ fn: @escaping () -> Void) -> UUID {
        let id = UUID()
        landed[id] = fn
        return id
    }
    static func stopLanded(_ id: UUID) { landed.removeValue(forKey: id) }

    /// Forget every form and pile (the tests' clean slate).
    static func clear() {
        lock.lock()
        forms.removeAll(); furs.removeAll(); filed.removeAll()
        lock.unlock()
    }

    /// Run `fn` on the bake queue (the halo's miss, measured off the main thread).
    static func onQueue(_ fn: @escaping () -> Void) { queue.async(execute: fn) }
}

/// The pile for an outline, baked now and not kept: the tests' and the
/// bench's own bake. `devicePx` is the avatar's size in device pixels.
func bakeFabricPile(_ type: BotAvatarType, devicePx: Double, depth: Double = 0.65, style: BotAvatarFurStyle = .stock, light: Double = 295) -> (FabricForm, Fur) {
    let N = botAvatarTier(devicePx), halfDepth = 15 * depth
    let a = light * Double.pi / 180
    let lx = sin(a), ly = -cos(a)
    let form = buildFabricForm(rasterizeBotAvatarOutline(type.shapeCGPath, N: N), N: N, halfDepth: halfDepth)
    let fur = FurBake(form: form, R: furTier((SPAN * devicePx / 100).rounded(.up)), lx: lx, ly: ly, style: style, lights: .stock(lx, ly)).run()
    return (form, fur)
}

/// Bake a type's fabric form and pile ahead of time, on the bake queue
/// (`warmPlastic(…, fabric = true)` on the web).
public func warmBotAvatarFabric(_ type: BotAvatarType, devicePx: Double = 192, depth: Double = 0.65, light: Double = 295, look: BotAvatarFabricLook = BotAvatarFabricLook()) {
    let a = light * Double.pi / 180
    let lx = sin(a), ly = -cos(a)
    _ = FabricBakes.ready(key: type.rawValue, path: type.shapeCGPath, N: botAvatarTier(devicePx), halfDepth: 15 * depth, capPx: (SPAN * devicePx / 100).rounded(.up), lx: lx, ly: ly, style: look.fur, lights: fabricLights(lx, ly, look), sync: false)
}

/// The lights a look asks for: the back light where it is given, else
/// from the key's; the key's front.
func fabricLights(_ lx: Double, _ ly: Double, _ look: BotAvatarFabricLook) -> FurLights {
    var l = FurLights.stock(lx, ly)
    if let b = look.backLight {
        let a = b * Double.pi / 180
        l.bx = sin(a); l.by = -cos(a)
    }
    l.front = min(85, max(0, look.lightFront)) * Double.pi / 180
    return l
}

/// Whether a config's fabric body can be drawn now, at a box of `box` points.
func fabricIsBaked(_ cfg: BotAvatarDrawConfig, box: Double) -> Bool {
    let la = cfg.lighting.light * Double.pi / 180
    let lx = sin(la), ly = -cos(la)
    let dev = cfg.fabricTierPx ?? box * cfg.scale
    return FabricBakes.has(key: cfg.typeKey, N: botAvatarTier(dev), halfDepth: 15 * cfg.depth, capPx: (SPAN * dev / 100).rounded(.up), lx: lx, ly: ly, style: cfg.fabric.fur, lights: fabricLights(lx, ly, cfg.fabric))
}

/// The latest fabric bake, for a demo's or a benchmark's counters: how many
/// have run, how long the last one took and whether it ran on the main
/// thread (only a still frame drawn without `bakeFabricOnIdle` bakes there).
public struct BotAvatarFabricBakeInfo: Sendable {
    public let count: Int
    public let seconds: Double
    public let onMainThread: Bool
    public static var last: BotAvatarFabricBakeInfo {
        let s = FabricBakes.stats
        return BotAvatarFabricBakeInfo(count: s.count, seconds: s.seconds, onMainThread: s.onMainThread)
    }
}

/// The fabric surface's height under a point of the body box (see `FabricBakes.surfaceAt`).
func fabricSurfaceAt(_ key: String, _ halfDepth: Double, _ x: Double, _ y: Double, _ round: Double) -> Double? {
    FabricBakes.surfaceAt(key: key, halfDepth: halfDepth, x: x, y: y, round: round)
}
