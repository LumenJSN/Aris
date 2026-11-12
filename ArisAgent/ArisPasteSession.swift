//
//  ArisPasteSession.swift
//  aris-agent
//
//  One dictation paste, without ever holding the main thread: the clipboard gets a lazy item (text, and HTML when
//  given), ⌘V is pressed, and the session returns at once. The app asking for the item is the paste-confirmed signal
//  (checked on short main-queue timers within the window); read: the user's clipboard comes back shortly after; not read:
//  the words stay as plain data (no promise left that needs this process) and his clipboard comes back later. Never
//  over something copied meanwhile. A paste that starts while an earlier one still owes the user their clipboard takes that
//  debt over (his saved clipboard, not the words on the board), and the earlier restore never runs. The pasteboard serves promises through the main run loop, which the agent runs
//  (main.swift ends in CFRunLoopRun), so other routes keep being answered during the window.
//

import AppKit

final class ArisPasteSession {
    struct Timing {
        var confirmWindow: TimeInterval
        var confirmedRestore: TimeInterval
        var unconfirmedRestore: TimeInterval
        var poll: TimeInterval

        static let standard = Timing(confirmWindow: ArisInsertText.confirmWindow, confirmedRestore: ArisInsertText.restoreDelay(confirmed: true),
                                     unconfirmedRestore: ArisInsertText.restoreDelay(confirmed: false), poll: 0.02)
    }

    /// nspasteboard.org markers: clipboard managers skip the item.
    static let markers = [NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
                          NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")]
    /// Sessions waiting on a timer (kept alive until they finish). Main thread only.
    nonisolated(unsafe) private static var live: [ObjectIdentifier: ArisPasteSession] = [:]
    /// By board, the session that still has to give the user's clipboard back. Main thread only.
    nonisolated(unsafe) private static var owing: [NSPasteboard.Name: ArisPasteSession] = [:]

    typealias Saved = [[(NSPasteboard.PasteboardType, Data)]]

    private let board: NSPasteboard
    private let text: String
    private let html: String?
    private let timing: Timing
    private let provider: ArisPasteProvider
    private let saved: Saved
    /// The board's change count while it holds what this session put there (the lazy item, then the plain words).
    private var ours = 0
    private var reported = false
    /// A later paste took over: this one touches the board no more.
    private var replaced = false
    private let began = Date()
    private let confirmed: (Bool) -> Void
    private let finished: () -> Void

    private init(board: NSPasteboard, text: String, html: String?, timing: Timing, saved: Saved,
                 confirmed: @escaping (Bool) -> Void, finished: @escaping () -> Void) {
        self.board = board
        self.text = text
        self.html = html
        self.timing = timing
        self.confirmed = confirmed
        self.finished = finished
        provider = ArisPasteProvider(text: text, html: html)
        self.saved = saved
    }

    /// What the board holds now, to give back later.
    private static func snapshot(_ board: NSPasteboard) -> Saved {
        board.pasteboardItems?.map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        } ?? []
    }

    /// The user's clipboard as a new paste on `board` should save it: an earlier session still owing it hands it over
    /// (when the board still holds that session's words) and stops; otherwise what's there now.
    private static func clipboardToSave(on board: NSPasteboard) -> Saved {
        guard let earlier = owing[board.name] else { return snapshot(board) }
        let stillItsWords = board.changeCount == earlier.ours
        earlier.handOver()
        return stillItsWords ? earlier.saved : snapshot(board)
    }

    /// On the main thread: puts the item up, `press`es ⌘V and returns. `confirmed` gets whether the app read it (once
    /// the window tells); `finished` runs once the user's clipboard is back (or left alone).
    static func start(text: String, html: String?, board: NSPasteboard = .general, timing: Timing = .standard,
                      press: () -> Void, confirmed: @escaping (Bool) -> Void, finished: @escaping () -> Void = {}) {
        let saved = clipboardToSave(on: board)
        let session = ArisPasteSession(board: board, text: text, html: html, timing: timing, saved: saved,
                                       confirmed: confirmed, finished: finished)
        live[ObjectIdentifier(session)] = session
        owing[board.name] = session
        board.clearContents()
        let item = NSPasteboardItem()
        item.setDataProvider(session.provider, forTypes: html == nil ? [.string] : [.string, .html])
        markers.forEach { item.setData(Data(), forType: $0) }
        board.writeObjects([item])
        session.ours = board.changeCount
        press()
        session.wait()
    }

    private func wait() {
        guard !replaced else { return }
        if provider.read { return confirm() }
        guard Date().timeIntervalSince(began) < timing.confirmWindow else { return unconfirmed() }
        DispatchQueue.main.asyncAfter(deadline: .now() + timing.poll) { self.wait() }
    }

    private func report(_ read: Bool) {
        guard !reported else { return }
        reported = true
        confirmed(read)
    }

    /// A later paste took over the user's clipboard: this one says whether it was read (if it hadn't yet) and ends.
    private func handOver() {
        report(provider.read)
        replaced = true
        end()
    }

    private func confirm() {
        report(true)
        // Still serving the item a moment (an app may ask for the HTML after the text), then the clipboard goes back.
        DispatchQueue.main.asyncAfter(deadline: .now() + timing.confirmedRestore) { self.restore(ifStill: self.ours) }
    }

    private func unconfirmed() {
        guard board.changeCount == ours else {
            // Something else was copied: leave it.
            report(false)
            return end()
        }
        board.clearContents()
        board.setString(text, forType: .string)
        if let html { board.setString(html, forType: .html) }
        Self.markers.forEach { board.setData(Data(), forType: $0) }
        ours = board.changeCount
        report(false)
        DispatchQueue.main.asyncAfter(deadline: .now() + timing.unconfirmedRestore) { self.restore(ifStill: self.ours) }
    }

    private func restore(ifStill ours: Int) {
        guard !replaced else { return }
        if ArisInsertText.shouldRestore(changeCount: board.changeCount, ours: ours) {
            board.clearContents()
            let items = saved.map { pairs -> NSPasteboardItem in
                let item = NSPasteboardItem()
                pairs.forEach { item.setData($1, forType: $0) }
                return item
            }
            if !items.isEmpty { board.writeObjects(items) }
        }
        end()
    }

    private func end() {
        guard Self.live[ObjectIdentifier(self)] != nil else { return }
        Self.live[ObjectIdentifier(self)] = nil
        if Self.owing[board.name] === self { Self.owing[board.name] = nil }
        finished()
    }
}

/// The lazy pasteboard item's data: asked for only when an app pastes it, which is how the paste is confirmed.
final class ArisPasteProvider: NSObject, NSPasteboardItemDataProvider {
    private let text: String
    private let html: String?
    private(set) var read = false

    init(text: String, html: String?) {
        self.text = text
        self.html = html
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        read = true
        if type == .html, let html { item.setString(html, forType: .html) } else { item.setString(text, forType: type) }
    }
}
