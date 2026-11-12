import AppKit
import BotAvatarsKit
import Foundation
import ImageIO
import QuartzCore
import SwiftUI

/* Two checks of a fabric avatar's canvas when it renders asynchronously.

   --threads: where the canvas's drawing runs. A fabric avatar in a window,
   its type, size and light changed every second for twelve seconds (each
   change a new pile: a hold, a bake landing, a redraw), and every canvas
   draw counted on or off the main thread.

   --motion[=sync] [--out=dir]: whether the avatar keeps up with its frame.
   A fabric avatar moved every display-link tick along a line at 600 pt/s
   inside a window, with a red marker drawn by SwiftUI at its frame's
   corner in the same view. A region screen recording (the window only) is
   split into 60 fps frames, and in each the body's centre is measured
   against the marker's: with no lag the offset is the same in every frame
   (up to the idle animation), a frame behind it is off by 10 pt; a blank
   or doubled body shows in its pixel count and width. `=sync` draws the
   canvas synchronously, the baseline. */

/// What the threads check shows.
@Observable final class ThreadsStage {
    var type: BotAvatarType = .clover
    var size = 96.0
    var light = 295.0
}

@MainActor
func threadsCheck() {
    let stage = ThreadsStage()
    let win = benchWindow(NSRect(x: 40, y: 40, width: 200, height: 200), opaque: false)
    win.contentView = NSHostingView(rootView: ThreadsView(stage: stage))
    win.orderFrontRegardless()
    BotAvatarRendering.resetThreads()
    let bakes0 = BotAvatarFabricBakeInfo.last.count
    let types: [BotAvatarType] = [.clover, .cat, .cloud, .blob]
    let sizes = [96.0, 32.0, 64.0]
    for step in 0..<12 {
        stage.type = types[step % types.count]
        stage.size = sizes[step % sizes.count]
        /* a new light bin each step: a new pile, baked and landing while shown */
        stage.light = 295 + 20 * Double(step)
        run(for: 1)
    }
    let t = BotAvatarRendering.threads
    win.orderOut(nil)
    print("threads: \(t.main + t.offMain) canvas draws over 12 s with 12 changes of type, size and light, \(BotAvatarFabricBakeInfo.last.count - bakes0) bakes landed")
    print("  on the main thread: \(t.main)   off it: \(t.offMain)\(t.offMainNames.isEmpty ? "" : "   (threads: \(t.offMainNames.sorted().joined(separator: ", ")))")")
}

struct ThreadsView: View {
    let stage: ThreadsStage
    var body: some View {
        BotAvatar(type: stage.type, size: stage.size, shading: .fabric, light: stage.light)
            .frame(width: 200, height: 200)
    }
}

func benchWindow(_ rect: NSRect, opaque: Bool) -> NSWindow {
    let win = NSWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
    win.isOpaque = opaque
    win.backgroundColor = opaque ? NSColor(srgbRed: 17 / 255, green: 17 / 255, blue: 19 / 255, alpha: 1) : .clear
    win.level = .floating
    return win
}

/* ── motion ──────────────────────────────────────────────────────────── */

let MOTION_W = 900.0, MOTION_H = 240.0, MOTION_SIZE = 96.0, MOTION_SPEED = 600.0

@Observable final class Mover {
    var x = 0.0
}

final class MoveDriver: NSObject {
    let mover: Mover
    let t0 = CACurrentMediaTime()
    init(_ mover: Mover) { self.mover = mover }
    /* a triangle wave along the window, 600 pt/s, set every display tick */
    @objc func tick(_ link: CADisplayLink) {
        let span = MOTION_W - MOTION_SIZE - 40
        let d = ((link.targetTimestamp - t0) * MOTION_SPEED).truncatingRemainder(dividingBy: 2 * span)
        mover.x = 20 + (d < span ? d : 2 * span - d)
    }
}

struct MotionView: View {
    let mover: Mover
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(.sRGB, red: 17 / 255, green: 17 / 255, blue: 19 / 255, opacity: 1)
            ZStack(alignment: .topLeading) {
                BotAvatar(type: .clover, size: MOTION_SIZE, shading: .fabric, jump: BotAvatarJumpConfig(every: 0))
                /* the frame's corner, drawn synchronously in the same view */
                Rectangle().fill(Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)).frame(width: 8, height: 8)
            }
            .frame(width: MOTION_SIZE, height: MOTION_SIZE, alignment: .topLeading)
            .offset(x: mover.x, y: 90)
        }
        .frame(width: MOTION_W, height: MOTION_H)
    }
}

@MainActor
func motionCheck(sync: Bool, out: URL) {
    BotAvatarRendering.asynchronousFabric = !sync
    let label = sync ? "sync" : "async"
    let dir = out.appendingPathComponent("motion-\(label)")
    try? FileManager.default.removeItem(at: dir)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let origin = NSPoint(x: 60, y: 160)
    let win = benchWindow(NSRect(origin: origin, size: NSSize(width: MOTION_W, height: MOTION_H)), opaque: true)
    let mover = Mover()
    win.contentView = NSHostingView(rootView: MotionView(mover: mover))
    win.orderFrontRegardless()
    let driver = MoveDriver(mover)
    guard let screen = NSScreen.main, let link = Optional(screen.displayLink(target: driver, selector: #selector(MoveDriver.tick(_:)))) else { return }
    link.add(to: .main, forMode: .common)
    /* the pile bakes and the avatar fades in */
    run(for: 4)
    let mov = dir.appendingPathComponent("motion.mov")
    let top = screen.frame.height - origin.y - MOTION_H
    let rec = Process()
    rec.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    rec.arguments = ["-x", "-v", "-V", "4", "-R", "\(Int(origin.x)),\(Int(top)),\(Int(MOTION_W)),\(Int(MOTION_H))", mov.path]
    try? rec.run()
    while rec.isRunning { run(for: 0.05) }
    link.invalidate()
    win.orderOut(nil)
    let frames = dir.appendingPathComponent("frames")
    try? FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
    let ff = Process()
    ff.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    ff.arguments = ["ffmpeg", "-loglevel", "error", "-i", mov.path, "-vf", "fps=60", frames.appendingPathComponent("f%03d.png").path]
    try? ff.run()
    ff.waitUntilExit()
    analyse(frames: frames, label: label)
    /* only the frames are kept, not the recording */
    try? FileManager.default.removeItem(at: mov)
}

private struct FrameReading { var name: String; var marker: Int; var mx: Double; var body: Int; var bx: Double; var width: Double }

private func read(_ url: URL) -> FrameReading? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    let w = img.width, h = img.height
    var px = [UInt8](repeating: 0, count: w * h * 4)
    guard let g = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    g.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    var mN = 0, mX = 0.0, bN = 0, bX = 0.0
    var cols = [Int](repeating: 0, count: w)
    for y in 0..<h {
        for x in 0..<w {
            let i = (y * w + x) * 4
            let r = Int(px[i]), gg = Int(px[i + 1]), b = Int(px[i + 2])
            if r > 180 && gg < 80 && b < 80 { mN += 1; mX += Double(x) }
            /* the clover's blue pile */
            else if b > 120 && b > r + 50 && gg > 50 { bN += 1; bX += Double(x); cols[x] += 1 }
        }
    }
    let solid = cols.indices.filter { cols[$0] >= 3 }
    let width = solid.isEmpty ? 0 : Double(solid.last! - solid.first! + 1)
    return FrameReading(name: url.lastPathComponent, marker: mN, mx: mN > 0 ? mX / Double(mN) : .nan, body: bN, bx: bN > 0 ? bX / Double(bN) : .nan, width: width)
}

private func analyse(frames: URL, label: String) {
    let files = ((try? FileManager.default.contentsOfDirectory(at: frames, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "png" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    let rs = files.compactMap(read)
    guard !rs.isEmpty else { print("motion \(label): no frames"); return }
    let scale = 2.0
    let seen = rs.filter { $0.marker > 0 && $0.body > 0 }
    let d = seen.map { ($0.bx - $0.mx) / scale }
    let med = d.sorted()[d.count / 2]
    let bodyMed = Double(seen.map(\.body).sorted()[seen.count / 2]), widthMed = seen.map(\.width).sorted()[seen.count / 2]
    let off = seen.filter { abs(($0.bx - $0.mx) / scale - med) > 4 }
    let blank = rs.filter { $0.marker > 0 && Double($0.body) < 0.6 * bodyMed }
    let doubled = seen.filter { $0.width > 1.25 * widthMed }
    let noMarker = rs.filter { $0.marker == 0 }
    func r(_ v: Double) -> String { String(format: "%.1f", v) }
    print("motion \(label): \(rs.count) frames at 60 fps, the avatar moving at \(Int(MOTION_SPEED)) pt/s (\(Int(MOTION_SPEED / 60)) pt a frame)")
    print("  body centre − frame marker, pt: median \(r(med))  min \(r(d.min()!))  max \(r(d.max()!))  frames off the median by > 4 pt: \(off.count)")
    print("  body pixels median \(Int(bodyMed)), frames under 60 % of it (blank or partial): \(blank.count); body width median \(r(widthMed / scale)) pt, frames over 125 % of it (doubled): \(doubled.count); frames without the marker: \(noMarker.count)")
    /* the motion the recording caught: the marker's step from frame to frame */
    var steps: [Double] = []
    for i in 1..<rs.count where rs[i].marker > 0 && rs[i - 1].marker > 0 { steps.append(abs(rs[i].mx - rs[i - 1].mx) / scale) }
    let moving = steps.filter { $0 > 0.5 }
    print("  marker step per frame, pt: median \(r(moving.sorted()[moving.count / 2])) over \(moving.count) frames that moved, \(steps.count - moving.count) repeated frames (the recording's own)")
    for f in (off + blank + doubled).prefix(8) { print("    flagged \(f.name): offset \(r((f.bx - f.mx) / scale)) pt, body \(f.body) px, width \(r(f.width / scale)) pt") }
    /* keep a frame in ten and the flagged ones */
    let keep = Set((off + blank + doubled).map(\.name))
    for (i, f) in files.enumerated() where i % 10 != 0 && !keep.contains(f.lastPathComponent) { try? FileManager.default.removeItem(at: f) }
    print("  frames kept in \(frames.path)")
}
