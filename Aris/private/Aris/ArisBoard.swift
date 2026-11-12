//
//  ArisBoard.swift
//  Aris
//
//  The Aris board, grown into the reader (the owner's 2A): what the AI was asked to put on a screen ("오른쪽 화면에 띄워줘"),
//  the notch's "답 열기", and a task's saved result (~/Documents/Aris/<date> <title>.md, which used to open raw in
//  TextEdit), in one floating glass panel that never takes the keyboard or mouse from what you're doing. aris-tools
//  board writes aris/board.json and nudges the app (com.lumenjsn.aris.board); a result is read through aris-agent (the
//  app is sandboxed). Links are shown as text and a click only copies them: the words may come from web pages or mail.
//

import AppKit
import SwiftUI
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "board")

@MainActor
final class ArisBoard {
    static let shared = ArisBoard()

    private var panel: NSPanel?
    private var presence = ArisReaderPresence()
    private var closing: Task<Void, Never>?
    private static var file: URL { URL(fileURLWithPath: ArisKeyFile.folder + "aris/board.json") }
    /// Under the open notch, as the mockup's reader sits (its top 212 below the screen's).
    private static let topOffset: CGFloat = 212

    func watch() {
        DistributedNotificationCenter.default().addObserver(forName: .init("com.lumenjsn.aris.board"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ArisBoard.shared.reload() }
        }
    }

    /// Out to .965 and 6 up over 200 ms, then gone.
    func close() {
        guard let panel else { return }
        withAnimation(ArisReaderView.dismiss) { presence.shown = false }
        closing = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self, self.panel === panel else { return }
            panel.orderOut(nil)
            self.panel = nil
        }
    }

    /// The notch's "Open answer": the whole answer under your words, on the screen with the pointer.
    func open(answer: String, question: String) {
        show(ArisReaderDocument.answer(answer, question: question), on: "here")
    }

    /// A saved task result in the reader, read through aris-agent (only a .md right in a result folder).
    func read(file: String) {
        Task { @MainActor in
            guard let result = await ArisAgentClient.readResult(file) else {
                log.error("reader: couldn't read a saved result")
                show(.answer(ArisUIWords.text("저장한 결과를 열지 못했어요. 파일이 옮겨졌거나 Aris 도우미가 꺼져 있어요.", "Couldn't open the saved result. The file was moved, or Aris's helper isn't running."), question: ""), on: "main")
                return
            }
            show(.result(markdown: result.text, file: file, modified: result.modified), on: "main")
        }
    }

    private func reload() {
        guard let data = try? Data(contentsOf: Self.file),
              let entry = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return log.error("board: couldn't read board.json")
        }
        if entry["close"] as? Bool == true { return close() }
        guard let markdown = entry["markdown"] as? String else { return }
        show(.board(markdown), on: entry["screen"] as? String ?? "here")
    }

    func show(_ document: ArisReaderDocument, on choice: String = "main") {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        closing?.cancel()
        let main = screens.firstIndex { $0.safeAreaInsets.top > 0 } ?? 0
        let screen = screens[ArisBoardContent.screenIndex(for: choice, screens: screens.map(\.frame), pointer: NSEvent.mouseLocation, main: main)]
        let area = screen.visibleFrame
        // As tall as a document a little taller than the panel needs, so its last line isn't cut at the lower edge.
        let width = min(ArisReaderView.size.width, area.width - 32), room = area.height - 32
        let size = CGSize(width: width, height: ArisBoardContent.readerHeight(needed: ArisReaderView.neededHeight(document, width: width),
                                                                                  base: min(ArisReaderView.size.height, room), tallest: min(ArisReaderView.tallest, room)))
        let top = min(screen.frame.maxY - Self.topOffset, area.maxY - 16)
        let frame = CGRect(x: area.midX - size.width / 2, y: max(area.minY + 16, top - size.height), width: size.width, height: size.height)

        let panel = self.panel ?? Self.makePanel()
        let presence = ArisReaderPresence()
        self.presence = presence
        let host = NSHostingView(rootView: ArisReaderView(document: document, actions: actions(for: document), presence: presence))
        host.wantsLayer = true
        host.layer?.backgroundColor = .clear
        panel.contentView = host
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel
        // In from .965 at the top on the opening clock, once it's on screen.
        DispatchQueue.main.async { withAnimation(ArisReaderView.present) { presence.shown = true } }
        log.notice("reader: \(document.blocks.count, privacy: .public) blocks on screen \(choice, privacy: .public)")
    }

    private func actions(for document: ArisReaderDocument) -> ArisReaderActions {
        let file = document.file
        return ArisReaderActions(
            copy: { Self.copy(ArisReaderDocument.plainText(document.blocks)) },
            note: file.map { path in { await ArisAgentClient.noteResult(path) } },
            openFile: file.map { path in { await ArisAgentClient.open(path) } },
            copyLink: { Self.copy($0.absoluteString) },
            close: { [weak self] in self?.close() })
    }

    private static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless, .resizable], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }
}
