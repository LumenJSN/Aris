//
//  ArisTeamModel.swift
//  Aris
//
//  The teammate list in the app: read from aris-agent when first asked for (and again when the 팀원 page or the 한 일
//  tab opens), shown at once when the user edits it, saved through the agent one save at a time, the latest edit winning.
//  Every face of a teammate (the notch, a window, the 한 일 tab) asks it for the look the owner picked.
//  A teammate made or removed by voice waits for its save (`applyAndWait`, audit team-11): it is announced only once
//  the agent stored it, a save that couldn't reach the agent is tried once more, and one that still failed puts the
//  list shown back as it was, so nothing unsaved is announced or can be called by name.
//

import Foundation

@MainActor
final class ArisTeamModel: ObservableObject {
    static let shared = ArisTeamModel()

    typealias Load = ArisTeamLoad

    @Published private(set) var teammates: [ArisTeammate] = []
    @Published private(set) var load = Load.loading
    /// The last save's refusal or failure, as the page says it; cleared by the next edit.
    @Published private(set) var notice: String?

    private var refreshing: Task<Void, Never>?
    private var saver: Task<Void, Never>?
    /// The newest edit not yet sent.
    private var pending: [ArisTeammate]?
    /// Every edit counted: a read started before one never puts back the older list (N17).
    private var edits = ArisEditStamp()
    /// The list as the agent last gave it (a read, or a save it stored): what the page goes back to when a save fails.
    private var stored: [ArisTeammate]?
    /// Those waiting to hear how the save carrying their edit ended (true: the agent stored the list).
    private var saveWaiters: [CheckedContinuation<Bool, Never>] = []

    private var faceWatch: NSObjectProtocol?

    private init() {
        refresh()
        // Every teammate's face is looked up with Aris's (ArisCharacterLook.of): when Aris's changes, they redraw.
        faceWatch = NotificationCenter.default.addObserver(forName: ArisFace.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.objectWillChange.send() }
        }
    }

    /// Reads the list again (a refresh asked while one runs is the same one).
    func refresh() {
        guard refreshing == nil else { return }
        let stamp = edits.now
        refreshing = Task { [weak self] in
            let list = await ArisAgentClient.teammates()
            guard let self else { return }
            self.refreshing = nil
            // An edit made meanwhile (even one already saved) is newer than what was read.
            guard self.pending == nil, self.saver == nil, self.edits.isCurrent(stamp) else { return }
            if let list { self.stored = list }
            if let list {
                self.teammates = list
                self.load = .ready
            } else if self.teammates.isEmpty {
                self.load = .unavailable
            }
        }
    }

    // MARK: - Brains, notes, 앱 노하우 (the 팀원 page)

    /// Which brains are set up on this Mac (empty until the agent answered: every brain counts as ready then).
    @Published private(set) var brains: [String: Bool] = [:]
    /// Each teammate's 기억, once read.
    @Published private(set) var notes: [String: [ArisNoteRow]] = [:]
    @Published private(set) var knowhow: [ArisNoteRow] = []

    func refreshExtras() {
        Task { [weak self] in
            let brains = await ArisAgentClient.teamBrains()
            let knowhow = await ArisAgentClient.knowhow()
            guard let self else { return }
            if let brains { self.brains = brains }
            if let knowhow { self.knowhow = knowhow }
        }
    }

    /// When the brains' readiness was last asked for.
    private var brainsAskedAt: Date?

    /// Asks again which brains are set up on this Mac, unless that was asked within `fresh` seconds (a hand-out reads
    /// them: ArisJobRouting). The 팀원 page's own refresh (refreshExtras) always asks.
    func refreshBrains(ifOlderThan fresh: TimeInterval = 60) {
        if let at = brainsAskedAt, Date().timeIntervalSince(at) < fresh { return }
        brainsAskedAt = Date()
        Task { [weak self] in
            guard let brains = await ArisAgentClient.teamBrains() else { return }
            self?.brains = brains
        }
    }

    func loadNotes(_ id: String) {
        Task { [weak self] in
            guard let rows = await ArisAgentClient.teammateNotes(id) else { return }
            self?.notes[id] = rows
        }
    }

    func forgetNote(_ id: String, note: String?) {
        notes[id] = note.map { gone in (notes[id] ?? []).filter { $0.id != gone } } ?? []
        Task { [weak self] in
            guard let rows = await ArisAgentClient.forgetTeammateNote(id, note: note) else { return }
            self?.notes[id] = rows
        }
    }

    func forgetKnowhow(_ note: String?) {
        knowhow = note.map { gone in knowhow.filter { $0.id != gone } } ?? []
        Task { [weak self] in
            guard let rows = await ArisAgentClient.forgetKnowhow(note) else { return }
            self?.knowhow = rows
        }
    }

    /// The user keeps a note learned from outside content (`teammate` nil: 앱 노하우).
    func keep(_ note: String, teammate: String?) {
        Task { [weak self] in
            guard let rows = await ArisAgentClient.keepNote(note, teammate: teammate), let self else { return }
            if let teammate { self.notes[teammate] = rows } else { self.knowhow = rows }
        }
    }

    /// Opens a terminal on `brain`'s login, then looks again a little later.
    func login(_ brain: String) {
        Task { [weak self] in
            _ = await ArisAgentClient.loginBrain(brain)
            try? await Task.sleep(for: .seconds(20))
            self?.refreshExtras()
        }
    }

    // MARK: - Made by voice or text

    /// The teammate asked for in words ("…팀원 하나 만들어줘"), shown on the notch's card and saved only on 확인 (M5).
    @Published var made: ArisTeamMade?
    /// The teammate the 팀원 page shows when it opens next (수정 on the made card); taken once.
    @Published var openOn: String?

    func takeOpenOn() -> String? {
        defer { openOn = nil }
        return openOn
    }

    /// Makes the teammate `request` asks for (the main brain, `brain`), saves it, and returns it; nil when the list is
    /// full or not read yet.
    func make(_ request: ArisTeamMaking.Request, brain: String, aris: ArisCharacterLook = .main) -> ArisTeammate? {
        guard load == .ready, let mate = ArisTeamMaking.make(request, in: teammates, aris: aris, brain: brain) else { return nil }
        apply(teammates + [mate])
        return mate
    }

    /// What `request` would make now, unsaved (the card's preview); nil when the list is full or not read yet.
    func preview(_ request: ArisTeamMaking.Request, brain: String, aris: ArisCharacterLook = .main) -> ArisTeammate? {
        guard load == .ready else { return nil }
        return ArisTeamMaking.make(request, in: teammates, aris: aris, brain: brain)
    }

    /// 확인 on the card: the preview is saved (made again if the list changed meanwhile); its id, or nil. The card is
    /// taken down at once; `saved` hears later whether the agent stored it (the teammate, or nil when it didn't: the
    /// list shown is then back as it was).
    @discardableResult
    func confirmMade(aris: ArisCharacterLook = .main, saved: ((ArisTeammate?) -> Void)? = nil) -> String? {
        guard let made else {
            saved?(nil)
            return nil
        }
        self.made = nil
        let fits = !teammates.contains { $0.id == made.preview.id || $0.name.lowercased() == made.preview.name.lowercased() }
            && teammates.count < ArisTeamEditing.maxTeammates
        guard load == .ready, let mate = fits ? made.preview : ArisTeamMaking.make(made.request, in: teammates, aris: aris, brain: made.brain) else {
            saved?(nil)
            return nil
        }
        guard let saved else {
            apply(teammates + [mate])
            return mate.id
        }
        let list = teammates + [mate]
        Task { saved(await self.applyAndWait(list) ? mate : nil) }
        return mate.id
    }

    /// The same, waited for: the teammate once the agent stored it, nil when it couldn't be made or saved.
    func confirmMadeAndWait(aris: ArisCharacterLook = .main) async -> ArisTeammate? {
        await withCheckedContinuation { continuation in
            confirmMade(aris: aris) { continuation.resume(returning: $0) }
        }
    }

    /// The face to show for a teammate (ArisCharacterLook.of).
    func look(teammateId: String?, name: String) -> ArisCharacterLook {
        .of(teammateId: teammateId, name: name, in: teammates)
    }

    /// Shows `list` now and saves it; edits made while a save runs go in one more save, the newest only. A save that
    /// couldn't reach the agent (it may be restarting) is tried once more (ArisTeamSaveRule).
    func apply(_ list: [ArisTeammate]) {
        edits.edit()
        teammates = list
        notice = nil
        pending = list
        guard saver == nil else { return }
        saver = Task { [weak self] in
            while let self, let next = self.pending {
                self.pending = nil
                var result = await ArisAgentClient.saveTeammates(next)
                var attempt = 1
                while ArisTeamSaveRule.retries(unreachable: result == .failed, attempt: attempt), self.pending == nil {
                    try? await Task.sleep(for: ArisTeamSaveRule.retryDelay)
                    guard self.pending == nil else { break }
                    attempt += 1
                    result = await ArisAgentClient.saveTeammates(next)
                }
                self.settle(result)
                // A newer edit is on its way: those waiting hear how that one ends.
                if self.pending == nil { self.tellWaiters(result) }
            }
            self?.saver = nil
        }
    }

    /// `apply`, then waits for the save: true when the agent stored the list. When it didn't, the list shown goes back
    /// to what it was before this edit (unless a newer edit came meanwhile).
    func applyAndWait(_ list: [ArisTeammate]) async -> Bool {
        let before = teammates
        apply(list)
        let saved = await withCheckedContinuation { saveWaiters.append($0) }
        if !saved, teammates == list, pending == nil { teammates = before }
        return saved
    }

    private func tellWaiters(_ result: ArisTeamSave) {
        let waiting = saveWaiters
        saveWaiters = []
        var saved = false
        if case .saved = result { saved = true }
        waiting.forEach { $0.resume(returning: saved) }
    }

    private func settle(_ result: ArisTeamSave) {
        switch result {
        case .saved(let list):
            stored = list
            if pending == nil { teammates = list }
        case .invalid(let code):
            notice = ArisTeamEditing.problemText(code)
            reloadAfterRefusal()
        case .refused:
            notice = "Aris 도우미가 이 앱을 확인하지 못해 저장하지 않았어요."
            reloadAfterRefusal()
        case .failed:
            // Still unreachable after the retry: the page shows what is stored again, and says so (the unsaved list used
            // to stay on screen with only this line under it).
            let back = ArisTeamSaveRule.shownAfterFailure(shown: teammates, stored: stored, newerEdit: pending != nil)
            notice = ArisTeamSaveRule.failedNotice(putBack: back != teammates)
            teammates = back
        }
    }

    /// What's stored is what shows after a refusal (unless a newer edit is on its way).
    private func reloadAfterRefusal() {
        guard pending == nil else { return }
        let stamp = edits.now
        Task { [weak self] in
            guard let list = await ArisAgentClient.teammates(), let self, self.pending == nil, self.edits.isCurrent(stamp) else { return }
            self.stored = list
            self.teammates = list
        }
    }
}
