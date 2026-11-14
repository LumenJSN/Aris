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

    func forgetSavedSteps(key: String) async -> Bool {
        let removed = await ArisAgentClient.forgetSavedSteps(key: key)
        savedSteps = await ArisAgentClient.savedSteps()
        return removed
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
