//
//  ArisSettingsLive.swift
//  Aris
//
//  The real work behind the new settings rows: API 키 (ArisKeysModel) through the Keychain, and 정보 › 데이터
//  (ArisDataModel) through the app's own files, the agent's /data route (ArisAgentClient+Data), save panels and
//  NSApp. Kept apart from the models and views so those render in a preview with stand-in actions.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension ArisKeysModel.Actions {
    @MainActor static let live = ArisKeysModel.Actions(
        read: { ArisKeychain.read($0) },
        save: { name, key in
            if case .failure(let failure) = ArisKeychain.save(key, as: name) { return failure.message }
            // The old hand-placed file, if any, goes too (the agent removes it: the app can't write there).
            Task { _ = await ArisKeychain.dropVerifiedFile(name, expecting: key) }
            return nil
        },
        delete: { await ArisKeychain.deleteKey($0) })
}

// MARK: - 정보 › 데이터

extension ArisDataModel.Actions {
    static var live: ArisDataModel.Actions {
        ArisDataModel.Actions(counts: liveCounts, export: liveExport, diagnostics: { await ArisDiagnostics.export() },
                              wipe: liveWipe, uninstall: liveUninstall, quit: { NSApp.terminate(nil) },
                              appPath: Bundle.main.bundleURL.path)
    }

    @MainActor
    private static func liveCounts() async -> ArisDataModel.Counts {
        var counts = ArisDataModel.Counts(history: ArisController.shared.pastTurns.count, clipboard: ArisClipboardModel.shared.items.count)
        if let places = ArisAppData.Places.current() {
            counts.spriteBytes = places.paths(for: .sprites).reduce(0) { $0 + folderSize($1) }
            counts.appLogBytes = places.paths(for: .logs).reduce(0) { $0 + folderSize($1) }
        }
        if let summary = await ArisAgentClient.dataSummary() {
            counts.memoryFacts = summary.memoryFacts
            counts.agentLogBytes = summary.logBytes
        }
        return counts
    }

    @MainActor
    private static func liveExport(history: Bool, memory: Bool, teammates: Bool, since: Date?) async -> String? {
        let agent = memory || teammates ? await ArisAgentClient.dataExport() : nil
        let now = Date()
        let data = ArisAppData.exportJSON(history: history ? ArisController.shared.pastTurns : nil,
                                          memory: memory ? agent?.memory : nil, teammates: teammates ? agent?.teammates : nil,
                                          since: since, now: now, extras: memory ? agent?.extras : nil)
        let name = ArisAppData.fileName("Aris 데이터", ext: "json", now: now)
        guard let url = savePanel(name: name, type: .json) else { return nil }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return "파일을 저장하지 못했어요: \(error.localizedDescription)"
        }
        let missed = (memory || teammates) && agent == nil
        return "“\(url.lastPathComponent)”을 저장했어요" + (missed ? ". 에이전트가 꺼져 있어서 대화 기록만 담았어요" : "")
    }

    @MainActor
    private static func liveWipe(items: [ArisAppData.Item], typed: String) async -> String {
        if items.contains(.history) { ArisController.shared.forgetPastTurns { _ in true } }
        if items.contains(.clipboard) { ArisClipboardModel.shared.clear(includingPinned: true) }
        let failed = ArisAppData.Places.current()?.remove(items) ?? []
        let agentItems = items.filter(\.agentSide).map(\.rawValue)
        let agentDone = agentItems.isEmpty ? true : await ArisAgentClient.wipeAgentData(agentItems, confirm: typed)
        if !agentDone { return "에이전트에 연결하지 못해서 기억과 에이전트 로그는 남아 있어요" }
        if !failed.isEmpty { return "\(failed.count)개 파일은 지우지 못했어요" }
        return "\(items.count)가지를 지웠어요"
    }

    @MainActor
    private static func liveUninstall(keepData: Bool, typed: String) async -> [ArisDataModel.UninstallStep]? {
        // 로그인 시 실행 goes first, while the app is still where macOS registered it; put back if nothing else happens.
        let wasLoginItem = ArisLoginItem.isEnabled
        ArisLoginItem.set(false)
        // Then the agent: without it nothing outside the app's container can go, so nothing goes at all.
        guard let reply = await ArisAgentClient.uninstall(confirm: typed, keepData: keepData) else {
            if wasLoginItem { ArisLoginItem.set(true) }
            return nil
        }
        let steps = reply.map { ArisDataModel.UninstallStep(step: $0.step, ok: $0.ok, note: $0.note) }
        // The app couldn't go to the Trash: the agent stopped there, and so does the app.
        guard steps.first(where: { $0.step == "app" })?.ok == true else {
            if wasLoginItem { ArisLoginItem.set(true) }
            return steps
        }
        ArisController.shared.forgetPastTurns { _ in true }
        ArisClipboardModel.shared.clear(includingPinned: true)
        _ = ArisAppData.Places.current()?.remove(ArisAppData.Item.allCases)
        for name in ArisKeyFile.names { ArisKeychain.delete(name); ArisKeychain.delete(ArisKeyFile.tombstone(name)) }
        if let id = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: id) }
        return steps
    }

    @MainActor
    private static func savePanel(name: String, type: UTType) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func folderSize(_ url: URL) -> Int {
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        var total = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        for case let file as URL in walker { total += (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
        return total
    }

    /// The diagnostics zip's save panel.
    @MainActor
    static func saveZip(name: String) -> URL? { savePanel(name: name, type: .zip) }
}
