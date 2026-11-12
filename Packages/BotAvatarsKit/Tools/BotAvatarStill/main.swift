import BotAvatarsKit
import BotAvatarsRendering
import Foundation

/* A paused, still avatar to PNG, for the side-by-side comparison with the
   web renderer:

     botavatar-still <type> <size> <shading> <dark|light> <out.png> [color] [yaw]

   The canvas is size × 1.5 points square at 2×, the body in its rest pose
   (turned by `yaw` radians when given), laid on the scheme's backdrop (the
   same one the web harness uses). */

let args = CommandLine.arguments
guard args.count >= 6,
      let type = BotAvatarType(rawValue: args[1]),
      let size = Double(args[2]),
      let shading = BotAvatarShading(rawValue: args[3]),
      let scheme = StillScheme(rawValue: args[4])
else {
    FileHandle.standardError.write(Data("usage: botavatar-still <type> <size> <shading> <dark|light> <out.png> [#color] [yaw]\n".utf8))
    exit(2)
}
let out = URL(fileURLWithPath: args[5])
let color = args.count > 6 ? BotColor(args[6]) : nil
let yaw = args.count > 7 ? Double(args[7]) ?? 0 : 0

let code: Int32 = await MainActor.run {
    var cfg = BotAvatarDrawConfig(type: type, color: color)
    cfg.shading = shading
    cfg.still = true
    var pose = BotAvatarPose.rest(.default)
    pose.yaw = yaw
    guard let img = StillRenderer.render(cfg, box: size, scale: 2, pose: pose),
          let laid = StillRenderer.onBackdrop(img, scheme)
    else { return 1 }
    do {
        try StillRenderer.writePNG(laid, to: out)
        return 0
    } catch {
        FileHandle.standardError.write(Data("could not write \(out.path): \(error)\n".utf8))
        return 1
    }
}
exit(code)
