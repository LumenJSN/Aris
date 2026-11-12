import AppKit
import BotAvatarsKit
import Foundation
import QuartzCore
import SwiftUI

/* What one fabric avatar costs the app while it animates:

     swift run -c release botavatar-bench [type] [--sizes=64,96] [--shading=fabric]
                                          [--no-cpu] [--no-offscreen]

   The acceptance measure is the LIVE frame: the avatar shown in a small
   window as the app shows it (a BotAvatar view on the shared frame clock),
   and the main thread's busy time per display frame — from the run loop
   waking to it going back to sleep: SwiftUI's update, the canvas's
   recording and the Core Animation commit (the render server and the GPU
   do the rest, in other processes). 600 frames after four seconds of
   settling, per size. Of that, how much the draw call itself took.

   Then, at the largest size, the process's CPU (user + system, all
   threads) over 30 s of animation, 10 s paused, 10 s with the view gone,
   and 10 s of the empty window for a baseline.

   Before each size the pile is baked as the view bakes it (queued from the
   main thread, made on the bake queue), and its time and thread reported.

   Last, unless --no-offscreen: the draw call alone and a whole frame
   rendered offscreen on the CPU (ImageRenderer into a Core Graphics
   bitmap), 600 frames each, for comparison.

   --threads and --motion[=sync]: see Modes.swift. */

let args = CommandLine.arguments.dropFirst()
let type = args.first(where: { !$0.hasPrefix("--") }).flatMap(BotAvatarType.init(rawValue:)) ?? .clover
func option(_ name: String) -> String? { args.first(where: { $0.hasPrefix("--\(name)=") }).map { String($0.dropFirst(name.count + 3)) } }
let sizes = option("sizes")?.split(separator: ",").compactMap { Double($0) } ?? [64, 96]
let shading = option("shading").flatMap(BotAvatarShading.init(rawValue:)) ?? .fabric
let measureCPU = !args.contains("--no-cpu")
let offscreen = !args.contains("--no-offscreen")
let FRAMES = 600, SCALE = 2.0

func percentile(_ v: [Double], _ p: Double) -> Double {
    let s = v.sorted()
    return s[min(s.count - 1, Int((p * Double(s.count - 1)).rounded()))]
}
func ms(_ s: Double) -> String { String(format: "%.3f", s * 1000) }

/// CPU seconds this process has used, all threads.
func cpuSeconds() -> Double {
    var u = rusage()
    getrusage(RUSAGE_SELF, &u)
    return Double(u.ru_utime.tv_sec) + Double(u.ru_utime.tv_usec) / 1e6 + Double(u.ru_stime.tv_sec) + Double(u.ru_stime.tv_usec) / 1e6
}

/// What the live window shows: the avatar, paused or not, or nothing.
@Observable final class Stage {
    var size = 96.0
    var paused = false
    var shown = true
}

struct StageView: View {
    let stage: Stage
    var body: some View {
        ZStack {
            if stage.shown {
                BotAvatar(type: type, size: stage.size, paused: stage.paused, shading: shading)
            }
        }
        .frame(width: 200, height: 200)
    }
}

@MainActor
func run(for seconds: Double) { RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds)) }

@MainActor
func bakeAndWait(size: Double) -> String {
    guard shading == .fabric else { return "" }
    let before = BotAvatarFabricBakeInfo.last.count
    let t0 = CACurrentMediaTime()
    warmBotAvatarFabric(type, devicePx: size * SCALE)
    let queued = CACurrentMediaTime() - t0
    while BotAvatarFabricBakeInfo.last.count == before { run(for: 0.005) }
    let s = BotAvatarFabricBakeInfo.last
    return "bake \(ms(s.seconds)) ms on \(s.onMainThread ? "the MAIN thread" : "the bake queue (off the main thread)"); queuing it took \(ms(queued)) ms on the main thread"
}

/// The main thread's busy time per display frame, and the draw call's share.
@MainActor
func liveFrames(_ stage: Stage) -> (busy: [Double], draw: [Double]) {
    var busy: [Double] = [], draw: [Double] = []
    var wake = 0.0, acc = 0.0, warm = 0
    let clock = BotAvatarClock.shared
    var lastFrame = clock.frame
    var lastDraw = clock.stats.drawSeconds
    let obs = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue, true, 0) { _, act in
        let now = CACurrentMediaTime()
        if act == .afterWaiting { wake = now; return }
        if wake > 0 { acc += now - wake }
        /* one sample per display frame, after four seconds of settling */
        if clock.frame != lastFrame {
            lastFrame = clock.frame
            warm += 1
            let d = clock.stats.drawSeconds - lastDraw
            lastDraw = clock.stats.drawSeconds
            if warm > 240 { busy.append(acc); draw.append(d) }
            acc = 0
        }
    }
    CFRunLoopAddObserver(CFRunLoopGetMain(), obs, .commonModes)
    while busy.count < FRAMES { run(for: 0.01) }
    CFRunLoopRemoveObserver(CFRunLoopGetMain(), obs, .commonModes)
    return (busy, draw)
}

/// The process's CPU over `seconds`, as a percentage of one core.
@MainActor
func cpuPercent(_ seconds: Double) -> Double {
    let c0 = cpuSeconds(), t0 = CACurrentMediaTime()
    run(for: seconds)
    return 100 * (cpuSeconds() - c0) / (CACurrentMediaTime() - t0)
}

/* the draw call and a whole offscreen frame, for comparison */
@MainActor
func offscreenFrames(size: Double, state: BotAvatarState) -> (draw: [Double], render: [Double]) {
    var cfg = BotAvatarDrawConfig(type: type)
    cfg.shading = shading
    cfg.scale = SCALE
    let sim = BotAvatarSim(seed: 0.37, state: state)
    let st = BotAvatarRenderState()
    let full = size * BOT_AVATAR_OVERSCAN
    let px = Int((full * SCALE).rounded())
    let g = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: px * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    var draws: [Double] = [], renders: [Double] = []
    for i in 0..<(FRAMES + 60) {
        sim.update(1.0 / 60)
        let pose = sim.pose
        var cost = 0.0
        let view = Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { ctx, _ in
            let t0 = CACurrentMediaTime()
            drawBotAvatarFrame(&ctx, box: size, pose: pose, cfg: cfg, state: st)
            cost = CACurrentMediaTime() - t0
        }.frame(width: full, height: full)
        let t0 = CACurrentMediaTime()
        g.clear(CGRect(x: 0, y: 0, width: px, height: px))
        ImageRenderer(content: view).render(rasterizationScale: SCALE) { _, draw in
            g.saveGState()
            g.scaleBy(x: SCALE, y: SCALE)
            draw(g)
            g.restoreGState()
        }
        let total = CACurrentMediaTime() - t0
        if i >= 60 { draws.append(cost); renders.append(total) }
    }
    return (draws, renders)
}

await MainActor.run {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    if args.contains("--threads") {
        threadsCheck()
        return
    }
    if let m = args.first(where: { $0.hasPrefix("--motion") }) {
        let out = URL(fileURLWithPath: option("out") ?? FileManager.default.currentDirectoryPath)
        motionCheck(sync: m == "--motion=sync", out: out)
        return
    }
    print("botavatar-bench: \(type.rawValue), \(shading.rawValue), scale \(Int(SCALE))×, \(FRAMES) frames per measure")
    let stage = Stage()
    let win = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
    win.isOpaque = false
    win.backgroundColor = .clear
    win.level = .floating
    stage.shown = false
    win.contentView = NSHostingView(rootView: StageView(stage: stage))
    win.orderFrontRegardless()
    run(for: 0.5)
    for size in sizes {
        print("\n\(Int(size)) pt (\(Int(size * SCALE)) px): \(bakeAndWait(size: size))")
        stage.size = size
        stage.paused = false
        stage.shown = true
        let r = liveFrames(stage)
        print("  LIVE main thread per frame   median \(ms(percentile(r.busy, 0.5))) ms   p95 \(ms(percentile(r.busy, 0.95))) ms   mean \(ms(r.busy.reduce(0, +) / Double(r.busy.count))) ms")
        print("       of which the draw call  median \(ms(percentile(r.draw, 0.5))) ms   p95 \(ms(percentile(r.draw, 0.95))) ms")
        stage.shown = false
        run(for: 0.3)
    }
    if measureCPU, let size = sizes.last {
        stage.size = size
        stage.paused = false
        stage.shown = true
        run(for: 4)
        let animating = cpuPercent(30)
        stage.paused = true
        run(for: 2)
        let paused = cpuPercent(10)
        stage.shown = false
        run(for: 2)
        let gone = cpuPercent(10)
        let link = BotAvatarClock.shared.isRunning
        win.contentView = NSHostingView(rootView: Color.clear.frame(width: 200, height: 200))
        run(for: 2)
        let empty = cpuPercent(10)
        print("\nprocess CPU at \(Int(size)) pt (% of one core, all threads; the render server's and the GPU's work is not in it):")
        print(String(format: "  animating 30 s  %.2f %%\n  paused 10 s     %.2f %%\n  view gone 10 s  %.2f %%  (frame loop running afterwards: %@)\n  empty window    %.2f %%", animating, paused, gone, link ? "yes" : "no", empty))
    }
    win.orderOut(nil)
    if offscreen {
        print("\nfor comparison, offscreen (not the acceptance measure):")
        for size in sizes {
            for state in [BotAvatarState.default, .working] {
                let r = offscreenFrames(size: size, state: state)
                print("  \(Int(size)) pt \(state.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0))  draw call median \(ms(percentile(r.draw, 0.5))) ms  p95 \(ms(percentile(r.draw, 0.95))) ms  |  whole frame on the CPU median \(ms(percentile(r.render, 0.5))) ms  p95 \(ms(percentile(r.render, 0.95))) ms")
            }
        }
    }
}
