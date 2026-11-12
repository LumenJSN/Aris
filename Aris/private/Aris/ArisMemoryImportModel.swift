//
//  ArisMemoryImportModel.swift
//  Aris
//
//  설정 › 기억 › 다른 AI에서 가져오기: the sheet's live state. It carries the board (ArisMemoryImportBoard) between the
//  sheet and the agent: the request to copy comes from the agent, the paste goes to it to be read (never to an AI),
//  the ticked lines go to it to be written, and 되돌리기 takes that batch back. The memory page reloads after each.
//

import AppKit
import Foundation

@MainActor
final class ArisMemoryImportModel: ObservableObject {
    static let shared = ArisMemoryImportModel()

    @Published var board = ArisMemoryImportBoard()
    @Published private(set) var copied = false
    private var copiedTimer: Task<Void, Never>?
    /// The next preview joins the list that is there ("이어 붙이기").
    private var joining = false

    /// A fresh sheet; `source`: the AI named when it was opened by voice, if any.
    func open(source: String? = nil) {
        board = ArisMemoryImportBoard()
        board.source = source ?? ""
        joining = false
        copied = false
        Task {
            let prompt = await ArisAgentClient.importPrompt(english: ArisUILanguage.english)
            if board.prompt.isEmpty { board.prompt = prompt ?? "" }
        }
    }

    func copyPrompt() {
        guard !board.prompt.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(board.prompt, forType: .string)
        copied = true
        copiedTimer?.cancel()
        copiedTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.copied = false
        }
    }

    /// Another part of the same export: back to the paste box, and its lines join the list.
    func addMore() {
        joining = true
        board.step = .paste
    }

    func preview() async {
        guard board.canPreview else { return }
        board.busy = true
        board.failed = false
        let text = String(board.pasted.prefix(ArisMemoryImportBoard.mostPaste))
        guard let read = await ArisAgentClient.importPreview(text) else {
            board.busy = false
            board.failed = true
            return
        }
        board.show(read.lines, unreadable: read.unreadable, complete: read.complete, joining: joining)
        joining = false
    }

    func apply() async {
        guard board.canImport else { return }
        board.busy = true
        board.failed = false
        let receipt = await ArisAgentClient.importApply(source: board.source, lines: board.applyLines)
        board.busy = false
        guard let receipt else { return board.failed = true }
        board.receipt = receipt
        board.step = .done
        await ArisMemorySettingsModel.shared.reload()
    }

    func undo() async {
        guard let batch = board.receipt?.batch, !board.undone, !board.busy else { return }
        board.busy = true
        let done = await ArisAgentClient.importUndo(batch: batch)
        board.busy = false
        board.undone = done
        board.failed = !done
        await ArisMemorySettingsModel.shared.reload()
    }

    /// "다른 AI에서 기억 가져올래": the memory page opens with the sheet on it. `source`: the AI named, if one was.
    static func openFromWords(source: String?) {
        shared.open(source: source)
        ArisSettingsNav.shared.go(.memory, anchor: "memory.import")
        ArisSettingsOverlay.shared.sheet = .memoryImport
        ArisStepAside.showSettings()
    }

    /// What the sheet's buttons do, as the sheet takes them.
    var actions: ArisMemoryImportActions {
        ArisMemoryImportActions(copy: { [weak self] in self?.copyPrompt() }, preview: { [weak self] in Task { await self?.preview() } },
                                apply: { [weak self] in Task { await self?.apply() } }, undo: { [weak self] in Task { await self?.undo() } },
                                addMore: { [weak self] in self?.addMore() }, drop: { [weak self] in self?.drop($0) })
    }

    /// A file dropped on the paste box: a .txt or .md file's text goes into it.
    func drop(_ url: URL) {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count <= 4 * ArisMemoryImportBoard.mostPaste,
              let text = ArisMemoryImportBoard.dropped(name: url.lastPathComponent, data: data) else { return }
        board.pasted = text
    }
}
