// Tests for jv-memfix: three RAM trims after VM runs 15 and 16 (memory climbing with use). The clipboard list's
// thumbnails are read at the row's size, never whole; a long turn's recording gives its memory back when it starts
// over; the sprite atlases held in memory are capped at 24 MB, least recently used out first, never one on screen.
// Called from main.swift; uses its check().
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

func runMemfixTests() {
    memfixThumbnailSizeTests()
    MainActor.assumeIsolated { memfixThumbnailReadTests() }
    memfixRecordingTests()
    memfixSpriteCapTests()
    memfixBigAtlasTests()
}

private let memfixRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../Aris/private/Aris")

private func memfixSource(_ path: String) -> String {
    (try? String(contentsOf: memfixRoot.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

/// A `width` × `height` picture encoded as `type`, with an EXIF `orientation` when given.
private func memfixImageData(width: Int, height: Int, type: UTType = .png, orientation: Int? = nil) -> Data? {
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(CGColor(red: 0.9, green: 0.3, blue: 0.2, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width / 3, height: height / 2))
    guard let image = context.makeImage() else { return nil }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
    let properties: [CFString: Any] = orientation.map { [kCGImagePropertyOrientation: $0] } ?? [:]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    return CGImageDestinationFinalize(destination) ? data as Data : nil
}

private func memfixThumbnailSizeTests() {
    typealias T = ArisClipboardThumbnail
    // A Retina screenshot shows 20 points tall: read 40 pixels tall, its long edge in proportion.
    check(T.maxPixelSize(width: 3024, height: 1964) == 62, "memfix thumbnail: a 3024×1964 screenshot is read 62 px long (40 px tall)")
    check(T.maxPixelSize(width: 1964, height: 3024) == 40, "memfix thumbnail: a portrait one is read 40 px tall (its long edge)")
    // Never more than the image has, nor than the cap on a panorama.
    check(T.maxPixelSize(width: 100, height: 30) == 100, "memfix thumbnail: a small image isn't read larger than it is")
    check(T.maxPixelSize(width: 40_000, height: 200) == T.maxLongEdge, "memfix thumbnail: a panorama is read at most maxLongEdge long")
    check(T.maxPixelSize(width: 0, height: 10) == nil && T.maxPixelSize(width: 10, height: 0) == nil, "memfix thumbnail: an empty size reads nothing")
    check(T.heightPoints == 20 && memfixSource("ArisClipboardView.swift").contains(".frame(height: ArisClipboardThumbnail.heightPoints)"),
          "memfix thumbnail: the row still draws it 20 points tall, from the same number it is read at")
    check(!memfixSource("ArisClipboardView.swift").contains("NSImage(data:"), "memfix thumbnail: the list no longer decodes a copy whole")
}

@MainActor
private func memfixThumbnailReadTests() {
    let width = 3024, height = 1964
    guard let png = memfixImageData(width: width, height: height) else { return check(false, "memfix thumbnail: test PNG made") }
    let thumb = ArisClipboardThumbnail.make(from: png)
    let full = width * height * 4
    let bytes = thumb.map { $0.bytesPerRow * $0.height } ?? .max
    check(thumb?.height == 40 && (61...63).contains(thumb?.width ?? 0), "memfix thumbnail: the screenshot is read 40 px tall (\(thumb?.width ?? 0)×\(thumb?.height ?? 0))")
    check(bytes * 100 < full, "memfix thumbnail: it holds under 1% of the whole decode (\(bytes) bytes against \(full))")
    print("  memfix: clipboard thumbnail of a \(width)×\(height) PNG: \(bytes / 1024) KB, whole decode \(full / 1_048_576) MB")

    // Orientation 6 (a phone photo stored sideways): upright, so 40 px tall from its stored width.
    if let jpeg = memfixImageData(width: 400, height: 200, type: .jpeg, orientation: 6), let turned = ArisClipboardThumbnail.make(from: jpeg) {
        check(turned.height == 40 && turned.width == 20, "memfix thumbnail: a sideways photo is read upright (\(turned.width)×\(turned.height))")
    } else {
        check(false, "memfix thumbnail: a sideways photo is read")
    }
    check(ArisClipboardThumbnail.make(from: Data("not an image".utf8)) == nil, "memfix thumbnail: text isn't read as an image")

    // One read per item, kept small: the second draw gets the same picture; a text copy has none.
    let cache = ArisClipboardThumbnails(countLimit: 4)
    let image = ArisClipboard.Item(id: UUID(), contents: [ArisClipboard.Content(type: "public.png", data: png)], title: "",
                                   app: nil, appBundle: nil, firstCopied: Date(), lastCopied: Date())
    let first = cache.image(for: image), second = cache.image(for: image)
    check(first != nil && first === second, "memfix thumbnail: an item is read once, then kept")
    check(first?.size == NSSize(width: CGFloat(thumb?.width ?? 0) / 2, height: 20), "memfix thumbnail: shown 20 points tall at 2×")
    let text = ArisClipboard.Item(id: UUID(), contents: [ArisClipboard.Content(type: ArisClipboard.stringType, data: Data("hi".utf8))], title: "hi",
                                  app: nil, appBundle: nil, firstCopied: Date(), lastCopied: Date())
    check(cache.image(for: text) == nil, "memfix thumbnail: a text copy has no thumbnail")
}

private func memfixRecordingTests() {
    let rate = 16_000.0
    // A normal turn's buffer is kept for the next start; past 2 MB (about 31 s) it goes back.
    check(ArisLongTurn.keepsCapacity(0) && ArisLongTurn.keepsCapacity(Int(rate * 30)), "memfix recording: a 30 s turn's buffer is kept")
    check(ArisLongTurn.keepsCapacity(Int(rate * 8)), "memfix recording: the wake word's rolling 8 s is kept")
    check(!ArisLongTurn.keepsCapacity(Int(rate * 32)), "memfix recording: a 32 s turn's buffer is given back")
    check(!ArisLongTurn.keepsCapacity(ArisLongTurn.recordedLimit(sampleRate: rate)), "memfix recording: a five-minute turn's 19 MB are given back")
    // The rule as the recording uses it, on a real buffer.
    var long = [Float](repeating: 0, count: ArisLongTurn.recordedLimit(sampleRate: rate))
    long.removeAll(keepingCapacity: ArisLongTurn.keepsCapacity(long.capacity))
    var short = [Float](repeating: 0, count: Int(rate * 10))
    let shortCapacity = short.capacity
    short.removeAll(keepingCapacity: ArisLongTurn.keepsCapacity(short.capacity))
    check(long.capacity == 0 && short.capacity == shortCapacity, "memfix recording: a long buffer is freed, a short one kept (\(long.capacity), \(short.capacity))")
    check(memfixSource("ArisListener.swift").contains("stored.removeAll(keepingCapacity: ArisLongTurn.keepsCapacity(stored.capacity))")
          && !memfixSource("ArisListener.swift").contains("removeAll(keepingCapacity: true)"),
          "memfix recording: the recording starts over by that rule")
}

private func memfixSpriteCapTests() {
    let mb = 1024 * 1024
    check(ArisSpriteCache.memoryCapBytes == 24 * mb, "memfix sprites: the atlases in memory are capped at 24 MB")
    // The host's session of 2026-11-26 (decoded KB, minutes after launch it was last asked for); the two shown now
    // are pinned.
    let t0 = Date(timeIntervalSince1970: 1_795_000_000)
    func entry(_ name: String, _ kb: Int, _ minute: Double) -> ArisSpriteCache.Entry {
        ArisSpriteCache.Entry(name: name, bytes: kb * 1024, lastUsed: t0.addingTimeInterval(minute * 60))
    }
    let session = [entry("star20x2-sleeping", 4064, 0), entry("ghost44x1-working", 2875, 0), entry("ghost44x2-working", 6125, 1),
                   entry("ghost44x1-idle", 3573, 2), entry("ghost44x2-idle", 8235, 29), entry("ghost20x2-idle", 5906, 3),
                   entry("star20x2-idle", 6806, 29), entry("star20x2-follow", 900, 28), entry("star44x1-idle", 4083, 10),
                   entry("star48x1-idle", 4860, 12), entry("ghost20x1-idle", 2197, 27)]
    let shown: Set = ["ghost44x2-idle", "star20x2-idle"]
    let drop = ArisSpriteCache.evictions(session, cap: ArisSpriteCache.memoryCapBytes, pinned: shown)
    let kept = session.filter { !drop.contains($0.name) }
    let keptBytes = kept.reduce(0) { $0 + $1.bytes }
    check(shown.isSubset(of: Set(kept.map(\.name))), "memfix sprites: the clips on screen are never dropped")
    check(keptBytes <= ArisSpriteCache.memoryCapBytes, "memfix sprites: the rest fits the cap (\(keptBytes / mb) MB kept of \(session.reduce(0) { $0 + $1.bytes } / mb))")
    check(drop.first == "ghost44x1-working" && drop.contains("star20x2-sleeping") && !drop.contains("star20x2-follow") && !drop.contains("ghost20x1-idle"),
          "memfix sprites: the least recently used go first, the ones just used stay (\(drop))")
    // The store marks an atlas used each time a layer asks for it, and reads a dropped one back off the main thread.
    let store = memfixSource("Team/ArisSpriteStore.swift")
    check(store.contains("if let sheet = sheets[key] {\n            lastUsed[key] = Date()"), "memfix sprites: each ask marks the atlas used (LRU)")
    check(store.contains("await Task.detached(priority: .userInitiated) { Self.read(k) }.value"), "memfix sprites: a dropped atlas is read back off the main thread")
}

/// The decoded bytes of `clip`'s atlas for a star `size` points big at `scale` (a loop at its plan's most frames).
private func memfixAtlasBytes(_ size: CGFloat, scale: CGFloat = 2, _ clip: ArisSpriteClip) -> Int {
    let look = ArisSpriteLook(type: "star", colorHex: nil, shading: "fabric", size: size, scale: scale, dark: true)
    let key = ArisSpriteKey(look: look, clip: clip, version: "test")
    return ArisSpriteGrid(count: key.spec?.maxFrames ?? 3, cellPx: look.cellPx).bytes
}

/// What a character view shown `size` points big needs for `clip` (rest pose past ArisSpriteLook.animates).
private func memfixShownBytes(_ size: CGFloat, _ clip: ArisSpriteClip) -> Int {
    memfixAtlasBytes(ArisSpriteLook.bakeSize(size), ArisSpriteLook.animates(size) ? clip : .still)
}

private func memfixBigAtlasTests() {
    let mb = 1024 * 1024
    // The settings page's 48-pt star plays from the 44-pt atlas (9% up); a bigger one keeps its own size.
    check(ArisSpriteLook.bakeSize(48) == 44 && ArisSpriteLook.bakeSize(48.4) == 44 && ArisSpriteLook.bakeSize(49) == 49
          && ArisSpriteLook.bakeSize(132) == 132 && ArisSpriteLook.bakeSize(44) == 44, "memfix big atlas: 48 pt bakes at 44, past 48.4 its own size")
    check(ArisSpriteLook.animates(44) && ArisSpriteLook.animates(48) && !ArisSpriteLook.animates(49) && !ArisSpriteLook.animates(101.61)
          && !ArisSpriteLook.animates(132), "memfix big atlas: a character past 48.4 pt holds its rest pose")
    let star48Before = memfixAtlasBytes(48, .idle), star48After = memfixShownBytes(48, .idle)
    let star132Before = memfixAtlasBytes(132, .idle), star132After = memfixShownBytes(132, .idle)
    let star101Before = memfixAtlasBytes(101.61, .idle), star101After = memfixShownBytes(101.61, .idle)
    print("  memfix: star idle atlas at 2x, most frames: 48 pt \(star48Before / 1024) KB -> \(star48After / 1024) KB (shared with the 44-pt one), "
          + "101.6 pt \(star101Before / mb) MB -> \(star101After / 1024) KB, 132 pt \(star132Before / mb) MB -> \(star132After / 1024) KB")
    check(star48After < star48Before, "memfix big atlas: the 48-pt star's loop is the 44-pt one, smaller")
    check(star132Before > 50 * mb && star132After <= 3 * mb && star101After <= 2 * mb, "memfix big atlas: the 132-pt star's 88 MB loop becomes its rest pose's few MB")
    // The cap: whatever size a character view is given, no atlas it asks for passes 16 MB decoded at 2x.
    var worst = 0, worstAt: CGFloat = 0, oldWorst = 0
    for step in 2...400 {
        let size = CGFloat(step) / 2
        for clip in [ArisSpriteClip.still, .idle, .working, .sleeping] {
            let bytes = memfixShownBytes(size, clip)
            if bytes > worst { worst = bytes; worstAt = size }
            oldWorst = max(oldWorst, memfixAtlasBytes(size <= 44 ? ArisSpriteLook.bakeSize(size) : size, clip))
        }
    }
    check(worst <= 16 * mb, "memfix big atlas: no character view's atlas passes 16 MB at 2x (worst \(worst / mb) MB at \(worstAt) pt; before: \(oldWorst / mb) MB)")
    check(memfixSource("Team/ArisCharacterView.swift").contains("let resting = still || !ArisSpriteLook.animates(size)"),
          "memfix big atlas: the character view rests a character too big to animate")
}
