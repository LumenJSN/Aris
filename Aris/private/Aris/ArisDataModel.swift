//
//  ArisDataModel.swift
//  Aris
//
//  What the 정보 › 데이터 sheets show and do (mockup audit-4-settings-extra.html option C): 데이터 내보내기, 진단
//  내보내기, 데이터 지우기 and 제거, each red one confirmed by typing its word (ArisTypedConfirm). What touches files,
//  the agent or macOS comes in as Actions (ArisSettingsLive), so a preview renders any sheet without doing anything.
//

import SwiftUI

@MainActor
final class ArisDataModel: ObservableObject {
    typealias Item = ArisAppData.Item

    struct Counts: Equatable {
        var history = 0
        var clipboard = 0
        var spriteBytes = 0
        var appLogBytes = 0
        /// Nil while the agent can't be asked.
        var memoryFacts: Int?
        var agentLogBytes: Int?
    }

    struct Actions {
        var counts: @MainActor () async -> Counts
        /// The toast to show, or nil when the user cancelled the save panel.
        var export: @MainActor (_ history: Bool, _ memory: Bool, _ teammates: Bool, _ since: Date?) async -> String?
        var diagnostics: @MainActor () async -> String?
        /// The toast to show.
        var wipe: @MainActor (_ items: [Item], _ typed: String) async -> String
        /// What the agent did, step by step; nil when it couldn't be reached (then nothing was removed).
        var uninstall: @MainActor (_ keepData: Bool, _ typed: String) async -> [UninstallStep]?
        var quit: @MainActor () -> Void
        var appPath: String
    }

    /// One step the agent reported (ArisDataRoute's uninstall).
    struct UninstallStep: Equatable {
        let step: String
        let ok: Bool
        var note: String?
    }

    /// The list row each agent step belongs to.
    static func row(of step: String) -> String {
        switch step {
        case "hooks", "antigravity": "hooks"
        case "launchAgent": "agent"
        case "binaries": "tools"
        case "folder", "link": "data"
        default: step
        }
    }

    /// The uninstall list: (id, title, path); "data" is the one the user can keep.
    static func uninstallRows(appPath: String) -> [(id: String, title: String, path: String)] {
        [("app", "Aris 앱", appPath),
         ("hooks", "Claude Code · Codex · Gemini 연결", "Aris가 넣은 hook, 상태 줄, Antigravity 규칙만 (백업을 남겨요)"),
         ("agent", "백그라운드 에이전트", "~/Library/LaunchAgents/com.lumenjsn.aris.agent.plist"),
         ("tools", "에이전트 프로그램", "~/.config/aris/aris-tools"),
         ("data", "설정과 기록", "~/.config/aris"),
         ("container", "앱 데이터와 API 키", "대화 · 클립보드 기록, 키체인의 키, 로그인 시 실행")]
    }

    static let shared = ArisDataModel(actions: .live)

    let actions: Actions
    var toast: (String) -> Void = { ArisSettingsOverlay.shared.show($0) }
    var close: () -> Void = { ArisSettingsOverlay.shared.sheet = nil }

    @Published private(set) var counts = Counts()
    @Published var exportHistory = true
    @Published var exportMemory = true
    @Published var exportTeammates = true
    @Published var exportRecent = false
    @Published var wipeSelection: Set<Item> = Set(Item.allCases)
    @Published var wipeTyped = ""
    @Published var removeRecords = true
    @Published var uninstallTyped = ""
    /// Nil before it starts; then how many rows are done.
    @Published private(set) var uninstallDone: Int?
    @Published private(set) var uninstallError: String?
    /// Rows whose step the agent reported as failed.
    @Published private(set) var failedRows: Set<String> = []
    @Published private(set) var busy = false

    init(actions: Actions, counts: Counts = Counts()) {
        self.actions = actions
        self.counts = counts
    }

    func reload() async { counts = await actions.counts() }

    func resetSheet() {
        wipeTyped = ""
        uninstallTyped = ""
        uninstallError = nil
        if uninstallDone != nil, uninstallDone! < Self.uninstallRows(appPath: "").count { uninstallDone = nil }
    }

    var canWipe: Bool { !wipeSelection.isEmpty && ArisTypedConfirm.matches(wipeTyped, ArisTypedConfirm.wipeWord) && !busy }
    var canUninstall: Bool { ArisTypedConfirm.matches(uninstallTyped, ArisTypedConfirm.uninstallWord) && !busy && uninstallDone == nil }
    var canExport: Bool { (exportHistory || exportMemory || exportTeammates) && !busy }

    func export() async {
        guard canExport else { return }
        busy = true
        defer { busy = false }
        let since = exportRecent ? Date().addingTimeInterval(-30 * 86_400) : nil
        guard let message = await actions.export(exportHistory, exportMemory, exportTeammates, since) else { return }
        close()
        toast(message)
    }

    func diagnostics() async {
        busy = true
        defer { busy = false }
        guard let message = await actions.diagnostics() else { return }
        close()
        toast(message)
    }

    func wipe() async {
        guard canWipe else { return }
        busy = true
        let items = Item.allCases.filter(wipeSelection.contains)
        let message = await actions.wipe(items, wipeTyped)
        busy = false
        wipeTyped = ""
        close()
        toast(message)
        await reload()
    }

    func uninstall() async {
        guard canUninstall else { return }
        busy = true
        uninstallError = nil
        guard let steps = await actions.uninstall(!removeRecords, uninstallTyped) else {
            busy = false
            uninstallError = "백그라운드 에이전트에 연결하지 못해서 아무것도 지우지 않았어요. Aris를 다시 시작한 뒤 해 주세요."
            return
        }
        guard steps.first(where: { $0.step == "app" })?.ok == true else {
            busy = false
            let translocated = steps.first?.note?.contains("translocated") == true
            // Each line is whole, so the settings window finds its English (ArisSettingsCopy).
            uninstallError = translocated
                ? "Aris 앱을 휴지통으로 옮기지 못해서 멈췄어요. 아무것도 지우지 않았어요. Aris를 응용 프로그램 폴더로 옮겨서 연 뒤 다시 해 주세요."
                : "Aris 앱을 휴지통으로 옮기지 못해서 멈췄어요. 아무것도 지우지 않았어요."
            return
        }
        failedRows = Set(steps.filter { !$0.ok }.map { Self.row(of: $0.step) })
        // The agent already did its steps; the rows tick in order as the mockup does (380 ms each), a failed one marked.
        uninstallDone = 0
        for done in 1...Self.uninstallRows(appPath: "").count {
            try? await Task.sleep(for: .milliseconds(380))
            uninstallDone = done
        }
        if !failedRows.isEmpty {
            let names = Self.uninstallRows(appPath: "").filter { failedRows.contains($0.id) }.map(\.title)
            uninstallError = "이건 지우지 못했어요: \(names.joined(separator: ", ")). Finder에서 직접 지워 주세요."
        }
        busy = false
    }

    var uninstallFinished: Bool { (uninstallDone ?? 0) >= Self.uninstallRows(appPath: "").count }
}
