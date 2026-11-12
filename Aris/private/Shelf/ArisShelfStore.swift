//
//  ArisShelfStore.swift
//  Aris
//
//  The shelf: an ordered list of items, saved 1 s after each change (and at once at quit), with drops turned into
//  items. The user's home page and the notch read it through `ShelfStateViewModel.shared`.
//

import AppKit
import Combine
import Foundation

/// What a drop can offer, one kind at a time (NSItemProvider in the app, stand-ins in tests).
protocol ArisShelfSource {
    func fileURL() async -> URL?
    func webURL() async -> URL?
    func text() async -> String?
    func data() async -> (data: Data, name: String?)?
    func anyItem() async -> URL?
}

extension NSItemProvider: ArisShelfSource {
    func fileURL() async -> URL? { await extractFileURL() }
    func webURL() async -> URL? { await extractURL() }
    func text() async -> String? { await extractText() }
    func data() async -> (data: Data, name: String?)? { await loadData().map { ($0, suggestedName) } }
    func anyItem() async -> URL? { await extractItem() }
}

enum ArisShelfIntake {
    /// The item for one drop source; the first kind it offers wins: file URL, URL, text, data, any item.
    static func item(from source: ArisShelfSource, temp: ArisShelfTempFiles = ArisShelfTempFiles()) async -> ShelfItem? {
        if let url = await source.fileURL(), let item = file(url) { return item }
        if let url = await source.webURL() {
            if url.isFileURL { if let item = file(url) { return item } } else { return ShelfItem(kind: .link(url)) }
        }
        if let text = await source.text() { return ShelfItem(kind: .text(text)) }
        if let (data, name) = await source.data(), let url = temp.data(data, named: name),
           let bookmark = ArisBookmark.make(for: url) {
            return ShelfItem(kind: .file(bookmark: bookmark.data), isTemporary: true)
        }
        if let url = await source.anyItem(), url.isFileURL { return file(url) }
        return nil
    }

    static func file(_ url: URL) -> ShelfItem? {
        ArisBookmark.make(for: url).map { ShelfItem(kind: .file(bookmark: $0.data)) }
    }
}

@MainActor
final class ShelfStateViewModel: ObservableObject {
    static let shared = ShelfStateViewModel(archive: .standard)

    @Published private(set) var items: [ShelfItem] = []
    @Published private(set) var isLoading = false

    private let archive: ArisShelfArchive
    private let temp: ArisShelfTempFiles
    private let saver: ArisDebouncer
    /// items.json couldn't be read: leave it alone until the user changes the shelf.
    private var protectFile = false

    init(archive: ArisShelfArchive, temp: ArisShelfTempFiles = ArisShelfTempFiles(), saver: ArisDebouncer = ArisDebouncer(delay: 1)) {
        self.archive = archive
        self.temp = temp
        self.saver = saver
        let loaded = archive.read()
        items = loaded.items
        protectFile = !loaded.intact
    }

    var isEmpty: Bool { items.isEmpty }

    /// Adds after the existing items, skipping anything already on the shelf.
    func add(_ new: [ShelfItem]) {
        var seen = Set(items.map(\.identity))
        let fresh = new.filter { seen.insert($0.identity).inserted }
        guard !fresh.isEmpty else { return }
        items += fresh
        changed()
    }

    func remove(_ item: ShelfItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let gone = items.remove(at: index)
        if gone.isTemporary, let url = gone.fileURL, temp.owns(url) { temp.remove(url) }
        changed()
    }

    func remove(_ ids: Set<UUID>) {
        items.filter { ids.contains($0.id) }.forEach(remove)
    }

    /// Stores fresh bookmark bytes after a stale one was resolved.
    func updateBookmark(of id: UUID, to data: Data) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].kind = .file(bookmark: data)
        changed()
    }

    /// Turns dropped providers into items, all at once.
    func load(_ providers: [NSItemProvider]) {
        guard !providers.isEmpty else { return }
        isLoading = true
        let temp = temp
        Task {
            let made = await withTaskGroup(of: ShelfItem?.self) { group in
                for provider in providers {
                    nonisolated(unsafe) let provider = provider
                    group.addTask { await ArisShelfIntake.item(from: provider, temp: temp) }
                }
                var made: [ShelfItem] = []
                for await item in group { if let item { made.append(item) } }
                return made
            }
            add(made)
            isLoading = false
        }
    }

    /// Drops files that no longer exist.
    func cleanup() {
        let kept = items.filter { if case .file = $0.kind { return $0.fileURL != nil } else { return true } }
        guard kept.count != items.count else { return }
        items = kept
        changed()
    }

    /// Saves now (at quit) and deletes the shelf's scratch files.
    func flushSync() {
        saver.flush()
        if !protectFile { archive.save(items) }
        ArisShelfTempFiles.removeScratch()
    }

    /// Items in the order the strip shows them.
    func ordered(reversed: Bool) -> [ShelfItem] { reversed ? items.reversed() : items }

    /// A change the user made: saved (1 s later), even over an unreadable file.
    private func changed() {
        protectFile = false
        let archive = archive
        saver.call { [weak self] in
            guard let self else { return }
            archive.save(self.items)
        }
    }
}
