//
//  ArisSpriteStore.swift
//  Aris
//
//  The characters' atlases (ArisSpriteSheet), by look and clip: in memory while in use (48 MB, least recently used out
//  first, never one a layer is showing), on disk in Caches/<bundle id>/ArisSprites (96 MB) so a look bakes once, and
//  baked one at a time (ArisSpriteBaker) the first time a character asks for one. A bake that fails waits before it is
//  tried again, so it never holds up the others. Published when one lands.
//

import BotAvatarsKit
import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers

@MainActor
final class ArisSpriteStore: ObservableObject {
    static let shared = ArisSpriteStore()

    @Published private(set) var sheets: [ArisSpriteKey: ArisSpriteSheet] = [:]
    private var lastUsed: [ArisSpriteKey: Date] = [:]
    /// What each live layer holds: never evicted while held.
    private var holders: [ObjectIdentifier: Set<ArisSpriteKey>] = [:]
    /// Queued keys some layer has held: once none holds them, they leave the queue unbaked (ArisSpriteCache.runnable).
    private var everHeld: Set<ArisSpriteKey> = []
    private var queue: [ArisSpriteKey] = []
    private var queued: Set<ArisSpriteKey> = []
    private var failures: [ArisSpriteKey: (count: Int, retryAt: Date)] = [:]
    private var worker: Task<Void, Never>?
    private let log = Logger(subsystem: "com.lumenjsn.aris", category: "sprites")

    nonisolated private static let folder: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.lumenjsn.aris", isDirectory: true)
        .appendingPathComponent("ArisSprites", isDirectory: true)

    private init() {
        // The first sprite build kept its atlases straight in Caches/ArisSprites: gone, they'd never be read again.
        Task.detached(priority: .background) {
            guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
            try? FileManager.default.removeItem(at: caches.appendingPathComponent("ArisSprites", isDirectory: true))
        }
    }

    static func key(_ look: ArisSpriteLook, _ clip: ArisSpriteClip) -> ArisSpriteKey {
        ArisSpriteKey(look: look, clip: clip, version: botAvatarsKitRenderVersion)
    }

    /// The atlas for `clip`, or nil while it loads or bakes (the first ask queues it; `urgent` jumps the queue). A
    /// failed one is asked for again only once its back-off has passed.
    func sheet(_ look: ArisSpriteLook, _ clip: ArisSpriteClip, urgent: Bool = false) -> ArisSpriteSheet? {
        let key = Self.key(look, clip)
        if let sheet = sheets[key] {
            lastUsed[key] = Date()
            return sheet
        }
        if let f = failures[key], Date() < f.retryAt { return nil }
        if !queued.contains(key) {
            queued.insert(key)
            if urgent { queue.insert(key, at: 0) } else { queue.append(key) }
            work()
        }
        return nil
    }

    /// The atlases `holder` (a layer) shows or may show next: kept in memory until it lets go.
    func hold(_ keys: Set<ArisSpriteKey>, for holder: ObjectIdentifier) {
        if keys.isEmpty { holders[holder] = nil } else { holders[holder] = keys }
        everHeld.formUnion(keys.intersection(queued))
    }

    func release(_ holder: ObjectIdentifier) { holders[holder] = nil }

    private var pinned: Set<ArisSpriteKey> { holders.values.reduce(into: Set()) { $0.formUnion($1) } }

    private func work() {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            while let self, let key = self.next() {
                var sheet = await self.load(key)
                if sheet == nil { sheet = await self.bake(key) }
                self.queued.remove(key)
                self.everHeld.remove(key)
                guard let sheet else {
                    let n = (self.failures[key]?.count ?? 0) + 1
                    self.failures[key] = (n, Date().addingTimeInterval(ArisSpriteCache.retryDelay(failures: n)))
                    continue
                }
                self.failures[key] = nil
                self.sheets[key] = sheet
                self.lastUsed[key] = Date()
                self.trimMemory()
                if sheet.provisional {
                    // Drawn with the kit's stand-in: baked again once the pile has had time to land.
                    self.failures[key] = (0, Date().addingTimeInterval(ArisSpriteCache.retryDelay(failures: 1)))
                    DispatchQueue.main.asyncAfter(deadline: .now() + ArisSpriteCache.retryDelay(failures: 1)) { [weak self] in
                        guard let self, self.sheets[key]?.provisional == true else { return }
                        self.queued.insert(key)
                        self.queue.append(key)
                        self.work()
                    }
                }
            }
            self?.worker = nil
        }
    }

    /// The next key to bake; keys no layer holds any more are dropped on the way (asked again, they queue again).
    private func next() -> ArisSpriteKey? {
        let held = pinned
        while !queue.isEmpty {
            let key = queue.removeFirst()
            if ArisSpriteCache.runnable(key, everHeld: everHeld, held: held) {
                everHeld.remove(key)
                return key
            }
            queued.remove(key)
            everHeld.remove(key)
        }
        return nil
    }

    private func bake(_ key: ArisSpriteKey) async -> ArisSpriteSheet? {
        let start = CFAbsoluteTimeGetCurrent()
        guard let sheet = await ArisSpriteBaker.bake(key) else {
            log.error("sprite bake failed: \(key.canonical, privacy: .public)")
            return nil
        }
        log.info("baked \(key.canonical, privacy: .public): \(sheet.frames) frames, \(sheet.segments.count) variants, \(sheet.bytes / 1024) KB, \(Int((CFAbsoluteTimeGetCurrent() - start) * 1000)) ms\(sheet.provisional ? " (provisional)" : "", privacy: .public)")
        if !sheet.provisional {
            let image = sheet.image
            let meta = ArisSpriteMeta(canonical: key.canonical, count: sheet.grid.count, cellPx: sheet.grid.cellPx,
                                      segments: sheet.segments.map { [$0.lowerBound, $0.upperBound] }, poke: sheet.poke)
            let name = key.fileName
            Task.detached(priority: .utility) { Self.save(image, meta, name: name) }
        }
        return sheet
    }

    /// Drops the least recently used atlases past the memory cap, never one a layer holds; held ones alone past the cap
    /// stay (and are logged).
    private func trimMemory() {
        let pins = pinned
        let entries = sheets.map { ArisSpriteCache.Entry(name: $0.key.canonical, bytes: $0.value.bytes, lastUsed: lastUsed[$0.key] ?? .distantPast) }
        let pinnedNames = Set(pins.map(\.canonical))
        let drop = Set(ArisSpriteCache.evictions(entries, cap: ArisSpriteCache.memoryCapBytes, pinned: pinnedNames))
        for key in sheets.keys where drop.contains(key.canonical) {
            sheets[key] = nil
            lastUsed[key] = nil
        }
        if ArisSpriteCache.pinnedOverCap(entries, cap: ArisSpriteCache.memoryCapBytes, pinned: pinnedNames) {
            log.notice("sprite atlases in use are over the memory cap: \(pinnedNames.count) held")
        }
    }

    // MARK: disk

    private func load(_ key: ArisSpriteKey) async -> ArisSpriteSheet? {
        let k = key
        return await Task.detached(priority: .userInitiated) { Self.read(k) }.value
    }

    /// The atlas and its meta, both whole and both this key's; anything else deletes the pair (it bakes again).
    nonisolated private static func read(_ key: ArisSpriteKey) -> ArisSpriteSheet? {
        guard let folder else { return nil }
        let png = folder.appendingPathComponent(key.fileName + ".png"), json = folder.appendingPathComponent(key.fileName + ".json")
        let fm = FileManager.default
        guard fm.fileExists(atPath: png.path) || fm.fileExists(atPath: json.path) else { return nil }
        func discard() -> ArisSpriteSheet? {
            try? fm.removeItem(at: png)
            try? fm.removeItem(at: json)
            return nil
        }
        guard let data = try? Data(contentsOf: json), let meta = try? JSONDecoder().decode(ArisSpriteMeta.self, from: data),
              let source = CGImageSourceCreateWithURL(png as CFURL, nil), CGImageSourceGetStatus(source) == .statusComplete,
              // Decoded here, off the main thread, not on the first frame it shows.
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
              meta.matches(key, width: image.width, height: image.height)
        else { return discard() }
        // Marks it used, for the disk's eviction.
        try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: png.path)
        return ArisSpriteSheet(image: image, grid: ArisSpriteGrid(count: meta.count, cellPx: meta.cellPx), fps: key.fps,
                               segments: meta.ranges, poke: meta.poke)
    }

    /// Written whole or not at all: encoded in memory, then each file replaced atomically, the meta last.
    nonisolated private static func save(_ image: CGImage, _ meta: ArisSpriteMeta, name: String) {
        guard let folder else { return }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return }
            CGImageDestinationAddImage(dest, image, nil)
            guard CGImageDestinationFinalize(dest) else { return }
            try (data as Data).write(to: folder.appendingPathComponent(name + ".png"), options: .atomic)
            try JSONEncoder().encode(meta).write(to: folder.appendingPathComponent(name + ".json"), options: .atomic)
            trimDisk(folder)
        } catch {
            Logger(subsystem: "com.lumenjsn.aris", category: "sprites").error("sprite cache write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Orphans go (an atlas without its meta, or a meta without its atlas), then past the disk cap the least recently
    /// used atlases (with their metas).
    nonisolated private static func trimDisk(_ folder: URL) {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else { return }
        let pngs = Set(files.filter { $0.pathExtension == "png" }.map { $0.deletingPathExtension().lastPathComponent })
        let metas = Set(files.filter { $0.pathExtension == "json" }.map { $0.deletingPathExtension().lastPathComponent })
        let orphans = ArisSpriteCache.orphans(pngs: pngs, metas: metas)
        for name in orphans.pngs { try? FileManager.default.removeItem(at: folder.appendingPathComponent(name + ".png")) }
        for name in orphans.metas { try? FileManager.default.removeItem(at: folder.appendingPathComponent(name + ".json")) }
        let entries = files.filter { $0.pathExtension == "png" && !orphans.pngs.contains($0.deletingPathExtension().lastPathComponent) }
            .compactMap { url -> ArisSpriteCache.Entry? in
                guard let v = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
                return ArisSpriteCache.Entry(name: url.deletingPathExtension().lastPathComponent, bytes: v.fileSize ?? 0, lastUsed: v.contentModificationDate ?? .distantPast)
            }
        for name in ArisSpriteCache.evictions(entries, cap: ArisSpriteCache.diskCapBytes) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name + ".png"))
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name + ".json"))
        }
    }
}
