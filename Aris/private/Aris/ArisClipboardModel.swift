//
//  ArisClipboardModel.swift
//  Aris
//
//  Watches the clipboard twice a second (as Maccy does: macOS has no notification for it) and keeps ArisClipboard's
//  history: all of a copy's pasteboard data, merged from its items. Copy an item back, or paste it straight into the
//  app in front (aris-agent presses ⌘V), with or without formatting; pin, delete, clear, pause. Saved in the app's
//  own container (Application Support), items over 2 MB only for the session.
//

import AppKit
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "clipboard")

@MainActor
final class ArisClipboardModel: ObservableObject {
    static let shared = ArisClipboardModel()

    @Published private(set) var items: [ArisClipboard.Item] = []
    /// Not recording new copies (until turned back on).
    @Published var paused = false
    /// Skip only the next copy.
    @Published var skipNext = false

    private var lastChange = NSPasteboard.general.changeCount
    private var watching: Task<Void, Never>?
    private var saving: Task<Void, Never>?
    private static let checkEvery: Duration = .milliseconds(500)

    private static var file: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Aris/clipboard.json")
    }

    func watch() {
        items = Self.load()
        watching?.cancel()
        watching = Task { [weak self] in
            while !Task.isCancelled {
                self?.check()
                try? await Task.sleep(for: Self.checkEvery)
            }
        }
    }

    // MARK: - Using an item

    /// Puts the item back on the clipboard (marked as ours, so it isn't recorded again) and moves it up.
    func copy(_ item: ArisClipboard.Item, plain: Bool = false) {
        let board = NSPasteboard.general
        board.clearContents()
        let contents = plain ? ArisClipboard.plain(item.contents) : item.contents
        let files = contents.filter { $0.type == ArisClipboard.fileURLType }
        for content in contents where content.type != ArisClipboard.fileURLType {
            board.setData(content.data, forType: NSPasteboard.PasteboardType(content.type))
        }
        // Several files paste as several only when written as separate items.
        if !files.isEmpty {
            board.writeObjects(files.map { file in
                let entry = NSPasteboardItem()
                entry.setData(file.data, forType: .fileURL)
                return entry
            })
        }
        board.setString("", forType: NSPasteboard.PasteboardType(ArisClipboard.ownType))
        lastChange = board.changeCount
        var used = item
        used.lastCopied = Date()
        used.copies += 1
        update(ArisClipboard.sorted([used] + items.filter { $0.id != item.id }))
    }

    /// Copies it, then has aris-agent press ⌘V in the app in front (the notch never takes the focus).
    func paste(_ item: ArisClipboard.Item, plain: Bool = false) async {
        copy(item, plain: plain)
        // The notch had the keyboard (searching, arrows): hand it back, or ⌘V would land here.
        KeyboardFocus.arm(false)
        try? await Task.sleep(for: .milliseconds(120))
        if let problem = await ArisAgentClient.pressPaste() {
            log.error("clipboard paste: \(problem, privacy: .public)")
        }
    }

    func togglePin(_ item: ArisClipboard.Item) {
        update(ArisClipboard.sorted(items.map { $0.id == item.id ? pinned($0, !$0.pinned) : $0 }))
    }

    func delete(_ item: ArisClipboard.Item) {
        update(items.filter { $0.id != item.id })
    }

    /// Everything but the pinned ones, or everything.
    func clear(includingPinned: Bool = false) {
        update(includingPinned ? [] : items.filter(\.pinned))
    }

    // MARK: - Watching

    private func check() {
        let board = NSPasteboard.general
        guard board.changeCount != lastChange else { return }
        lastChange = board.changeCount
        // Nothing is recorded while paused, or while the 클립보드 tab is turned off in settings.
        guard !paused, ArisSidePanels.shared.shows(.clipboard) else { return }
        if skipNext {
            skipNext = false
            return
        }
        // Reading types on the pasteboard lists every item's (Maccy: some apps put the markers on a second item).
        let types = board.types?.map(\.rawValue) ?? []
        let front = NSWorkspace.shared.frontmostApplication
        guard ArisClipboard.keeps(types: types, app: front?.bundleIdentifier) else { return }
        // Some apps put two items on the pasteboard for one copy: their data is merged into one record.
        var contents: [ArisClipboard.Content] = []
        for entry in board.pasteboardItems ?? [] {
            if entry.types.contains(.string), (entry.string(forType: .string) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !entry.types.contains(.rtf), !entry.types.contains(.html), !entry.types.contains(.fileURL),
               !entry.types.contains(where: { ArisClipboard.imageTypes.contains($0.rawValue) }) {
                continue
            }
            for type in entry.types where ArisClipboard.keepsType(type.rawValue) {
                if let data = entry.data(forType: type) { contents.append(ArisClipboard.Content(type: type.rawValue, data: data)) }
            }
        }
        guard !contents.isEmpty, contents.reduce(0, { $0 + $1.data.count }) <= ArisClipboard.itemLimit else { return }
        let now = Date()
        let item = ArisClipboard.Item(id: UUID(), contents: contents, title: ArisClipboard.title(of: contents),
                                      app: front?.localizedName, appBundle: front?.bundleIdentifier, firstCopied: now, lastCopied: now)
        update(ArisClipboard.adding(item, to: items))
    }

    private func pinned(_ item: ArisClipboard.Item, _ on: Bool) -> ArisClipboard.Item {
        var changed = item
        changed.pinned = on
        return changed
    }

    // MARK: - Saving

    private func update(_ new: [ArisClipboard.Item]) {
        items = new
        saving?.cancel()
        saving = Task { [items] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            Self.save(items)
        }
    }

    /// A file that can't be read is kept aside, never overwritten by the next save (ArisJSONFile).
    private static func load() -> [ArisClipboard.Item] {
        guard let file else { return [] }
        return ArisJSONFile.load([ArisClipboard.Item].self, from: file, what: "clipboard")
    }

    private static func save(_ items: [ArisClipboard.Item]) {
        guard let file else { return }
        let kept = items.filter { $0.size <= ArisClipboard.savedItemLimit && !ArisClipboard.looksSecret($0) }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(kept).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch {
            log.error("clipboard: couldn't save: \(error.localizedDescription, privacy: .public)")
        }
    }
}
