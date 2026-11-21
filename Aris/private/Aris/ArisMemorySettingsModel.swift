//
//  ArisMemorySettingsModel.swift
//  Aris
//
//  설정 › 기억's live state: the agent's list (reloaded when the page opens and after each change), the search words,
//  the switch, and whether 모두 지우기 waits for its second press (which lapses after 5 s).
//

import Foundation

@MainActor
final class ArisMemorySettingsModel: ObservableObject {
    static let shared = ArisMemorySettingsModel()

    @Published private(set) var items: [ArisMemoryItem]?
    @Published private(set) var loaded = false
    @Published private(set) var auto = true
    @Published var query = ""
    @Published private(set) var confirmingClear = false
    private var confirmTimer: Task<Void, Never>?
    /// 일하면서 배운 것 (the agent's work memory): the lessons, how many episodes there are, its switch, and whether 배운 것
    /// 모두 지우기 waits for its second press.
    /// What waits for the user, the people and project pages, the tidy-up's changes and its switch (ArisMemoryReviewRows).
    @Published private(set) var held: [ArisMemoryHeldItem] = []
    @Published private(set) var conflicts: [ArisMemoryConflictItem] = []
    @Published private(set) var entities: [ArisMemoryEntityItem] = []
    @Published private(set) var changes: [ArisMemoryChangeItem] = []
    @Published private(set) var consolidate = true
    @Published private(set) var workLessons: [ArisWorkLessonItem]?
    @Published private(set) var workEpisodes = 0
    @Published private(set) var workOn = true
    @Published private(set) var confirmingWorkClear = false
    private var workTimer: Task<Void, Never>?
    /// 저장된 단계 (the agent's saved desktop steps).
    @Published private(set) var savedSteps: [ArisSavedStepsItem]?
    /// A taught procedure being renamed (its row's key), the name typed so far, and why the last 저장 didn't take.
    @Published private(set) var renaming: String?
    @Published var renameText = ""
    @Published private(set) var renameProblem: ArisSavedStepsSettingsRows.RenameProblem?
    /// The saved request whose 지우기 waits for its second press (정말 지우기), which lapses after 5 s (fifth VM run, M1:
    /// it was gone at the first press).
    @Published private(set) var confirmingForget: String?
    private var forgetTimer: Task<Void, Never>?
    /// When 정말 지우기 came up.
    private var confirmingSince: Date?

    func reload() async {
        let reply = await ArisAgentClient.memories()
        items = reply?.memories
        if let reply {
            auto = reply.auto
            consolidate = reply.consolidate ?? true
        }
        held = reply?.held ?? []
        conflicts = reply?.conflicts ?? []
        entities = reply?.entities ?? []
        changes = reply?.changes ?? []
        await reloadWork()
        savedSteps = await ArisAgentClient.savedSteps()
        loaded = true
    }

    private func reloadWork() async {
        let work = await ArisAgentClient.workMemory()
        workLessons = work?.lessons
        if let work {
            workOn = work.on
            workEpisodes = work.episodes
        }
    }

    func setWork(_ on: Bool) async {
        workOn = on
        if let now = await ArisAgentClient.setWorkMemory(on) { workOn = now } else { await reloadWork() }
    }

    /// 지우기 on a saved request: the first press asks (its row says it can't be undone and offers 취소 and 정말 지우기),
    /// the second forgets it. As 배운 것 모두 지우기 asks.
    func forgetSavedStepsPressed(key: String) async -> Bool {
        // 정말 지우기 comes up under the pointer, where 지우기 was: a press on it this soon is the same double-click, not a
        // second decision, and does nothing (sixth VM run, item 6b).
        if confirmingForget == key, !ArisSavedStepsSettingsRows.confirmCounts(since: confirmingSince, now: Date()) { return false }
        guard confirmingForget == key else {
            confirmingForget = key
            confirmingSince = Date()
            forgetTimer?.cancel()
            forgetTimer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                if self?.confirmingForget == key { self?.confirmingForget = nil }
            }
            return false
        }
        cancelForgetSavedSteps()
        return await forgetSavedSteps(key: key)
    }

    func cancelForgetSavedSteps() {
        forgetTimer?.cancel()
        confirmingForget = nil
    }

    /// The saved steps, asked for as the settings window opens (not only with 기억's page), so a search that lands on
    /// them finds their rows there (sixth VM run, item 3).
    func loadSavedSteps() async {
        guard savedSteps == nil else { return }
        savedSteps = await ArisAgentClient.savedSteps()
    }

    func forgetSavedSteps(key: String) async -> Bool {
        let removed = await ArisAgentClient.forgetSavedSteps(key: key)
        if renaming == key { endRename() }
        savedSteps = await ArisAgentClient.savedSteps()
        return removed
    }

    /// 이름 바꾸기 on a taught procedure's row: its field opens with the name it has; pressed again, it closes.
    func startRename(key: String) {
        guard renaming != key else { return endRename() }
        renaming = key
        renameText = savedSteps?.first { $0.key == key }?.request ?? ""
        renameProblem = nil
    }

    /// 저장: the name as typed goes to the helper; the field closes once it took it (or nothing changed).
    func saveRename(key: String) async -> Bool {
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard renaming == key, !name.isEmpty else { return false }
        if name == savedSteps?.first(where: { $0.key == key })?.request {
            endRename()
            return false
        }
        let said = await ArisAgentClient.renameSavedSteps(key: key, name: name)
        guard let said, said.renamed else {
            renameProblem = said?.taken == true ? .taken : .failed
            return false
        }
        endRename()
        savedSteps = await ArisAgentClient.savedSteps()
        return true
    }

    private func endRename() {
        renaming = nil
        renameText = ""
        renameProblem = nil
    }

    func forgetLesson(id: Int) async -> Bool {
        let removed = await ArisAgentClient.forgetWorkLesson(id: id)
        await reloadWork()
        return removed
    }

    /// First press asks; the second (within 5 s) deletes every episode and lesson.
    func clearWorkPressed() async -> Bool {
        guard confirmingWorkClear else {
            confirmingWorkClear = true
            workTimer?.cancel()
            workTimer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                self?.confirmingWorkClear = false
            }
            return false
        }
        cancelWorkClear()
        let done = await ArisAgentClient.forgetAllWork()
        await reloadWork()
        return done
    }

    func cancelWorkClear() {
        workTimer?.cancel()
        confirmingWorkClear = false
    }

    func forget(id: String) async -> Bool {
        let removed = await ArisAgentClient.forgetMemory(id: id)
        await reload()
        return removed
    }

    func confirm(id: String) async -> Bool {
        let confirmed = await ArisAgentClient.confirmMemory(id: id)
        await reload()
        return confirmed
    }

    /// First press asks; the second (within 5 s) deletes everything.
    func clearPressed() async -> Bool {
        guard confirmingClear else {
            confirmingClear = true
            confirmTimer?.cancel()
            confirmTimer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                self?.confirmingClear = false
            }
            return false
        }
        cancelClear()
        let done = await ArisAgentClient.forgetAllMemories()
        await reload()
        return done
    }

    func cancelClear() {
        confirmTimer?.cancel()
        confirmingClear = false
    }

    func keepHeld(id: String) async -> Bool { await then(ArisAgentClient.keepHeldMemory(id: id)) }
    func dropHeld(id: String) async -> Bool { await then(ArisAgentClient.dropHeldMemory(id: id)) }
    func settle(conflict id: String, keep: String) async -> Bool { await then(ArisAgentClient.settleMemoryConflict(id: id, keep: keep)) }
    func forgetEntity(id: String) async -> Bool { await then(ArisAgentClient.forgetMemoryEntity(id: id)) }
    func undoChange(id: Int) async -> Bool { await then(ArisAgentClient.undoMemoryChange(id: id)) }

    /// What a call answered, after the page is read again.
    private func then(_ done: Bool) async -> Bool {
        await reload()
        return done
    }

    func setConsolidate(_ on: Bool) async {
        consolidate = on
        if let now = await ArisAgentClient.setConsolidateMemory(on) { consolidate = now } else { await reload() }
    }

    func setAuto(_ on: Bool) async {
        auto = on
        if let now = await ArisAgentClient.setAutoMemory(on) { auto = now } else { await reload() }
    }
}
