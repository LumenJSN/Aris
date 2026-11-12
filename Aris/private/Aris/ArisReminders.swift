//
//  ArisReminders.swift
//  Aris
//
//  The 할 일 tab's store: Apple Reminders through EventKit. Shown are the incomplete reminders of the lists chosen
//  in settings (arisTodoLists; none chosen: the default list), new items go to the default list
//  (arisTodoDefaultList). Reloads whenever Reminders changes, from any app.
//
//  This is the main actor's half: what the views read (the lists, the open items, the last error), and the bookkeeping
//  around each change. EventKit itself is never called from here: its calls block, for seconds at times, and they are
//  made by ArisReminderStore on a queue of its own. So everything that reads or changes Reminders is `async`, and
//  the lists the tab shows and the list new items go to are worked out from the lists last read (ArisReminderLists).
//

import AppKit
import Defaults
import EventKit

struct ArisReminderList: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let source: String
    let colorHex: String
}

/// What the composer edits and a reminder is saved from.
struct ArisTodoDraft: Equatable, Sendable {
    var title = ""
    var notes = ""
    var due: Date?
    var hasTime = false
    var listID = ""

    init() {}

    init(_ item: ArisTodoItem) {
        title = item.title
        notes = item.notes ?? ""
        due = item.due
        hasTime = item.hasTime
        listID = item.listID
    }
}

@MainActor
final class ArisReminders: ObservableObject {
    static let shared = ArisReminders()

    /// The owner of the EKEventStore, off the main actor.
    private let store = ArisReminderStore()
    /// A new store is on its way (access has just turned on). Whatever is asked of the store next waits for it, as
    /// it did when the store was replaced on the spot: an item added the moment access was granted must not go to
    /// the store made before the grant, which may not see the lists.
    private var replacing: Task<Void, Never>?

    /// The store, once a replacement that was asked for is in place.
    private func ready() async -> ArisReminderStore {
        await replacing?.value
        return store
    }

    private func replaceStore() {
        let earlier = replacing
        replacing = Task { [store] in
            await earlier?.value
            await store.replace()
        }
    }
    @Published private(set) var status = EKEventStore.authorizationStatus(for: .reminder)
    @Published private(set) var lists: [ArisReminderList] = []
    /// Incomplete reminders of the included lists.
    @Published private(set) var items: [ArisTodoItem] = []
    @Published var lastError: String?
    /// Reminders' own default list, as last read.
    private var storeDefaultID: String?
    private var reloadGeneration = 0
    private var reloading: Task<Void, Never>?
    private var started = false
    /// macOS's own prompt for Reminders was answered in this run of the app, and with a yes.
    private var answeredThisRun = false
    private var grantedByRequest = false

    var authorized: Bool { ArisRemindersAccess.allowed(status: Self.plain(status), grantedByRequest: grantedByRequest) }

    private static func plain(_ status: EKAuthorizationStatus) -> ArisRemindersAccess.Status {
        switch status {
        case .fullAccess: return .full
        case .writeOnly: return .writeOnly
        case .denied: return .denied
        case .restricted: return .restricted
        default: return .notAsked
        }
    }

    func start() {
        guard !started else { return }
        started = true
        Task {
            await store.watch { Task { @MainActor in ArisReminders.shared.scheduleReload() } }
            await reload()
        }
    }

    /// Whether Aris may use Reminders, read from macOS now: never answered from the status kept here. Access that
    /// has just turned on gets a new store, and a changed answer reads the lists again.
    @discardableResult
    func accessNow() -> Bool {
        let fresh = EKEventStore.authorizationStatus(for: .reminder)
        let step = ArisRemindersAccess.seen(known: Self.plain(status), fresh: Self.plain(fresh))
        if step.newStore { replaceStore() }
        if fresh != status { status = fresh }
        if step.reload { Task { await reload() } }
        return authorized
    }

    /// The same for a request that would otherwise be answered "Aris can't use Reminders yet" (an add, the list,
    /// "Try again"): when macOS's prompt was already answered in this run and this process still reads "not asked
    /// yet", macOS is asked once more, which shows nothing and only brings its answer here (ArisRemindersAccess.asksAgain).
    func accessForRequest() async -> Bool {
        if accessNow() { return true }
        guard ArisRemindersAccess.asksAgain(fresh: Self.plain(status), answeredThisRun: answeredThisRun) else { return false }
        await ask()
        return authorized
    }

    /// Asks for access (only when the settings button is pressed).
    func requestAccess() async {
        if status == .denied || status == .restricted {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        await ask()
    }

    /// macOS's own request. Its yes is kept for this run, and the store is made anew after it.
    private func ask() async {
        if let granted = await ready().requestAccess() {
            answeredThisRun = true
            grantedByRequest = granted
            // The calendar's due to-dos keep this yes too (ArisCalendarStore.remindersGranted).
            if granted { Task { await ArisCalendarStore.shared.remindersGranted() } }
            if granted { replaceStore() }
        }
        status = EKEventStore.authorizationStatus(for: .reminder)
        await reload()
    }

    private func scheduleReload() {
        reloading?.cancel()
        reloading = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.reload()
        }
    }

    // MARK: - Reading

    /// What the settings chose, as it is now.
    private var prefs: ArisReminderPrefs {
        ArisReminderPrefs(chosen: Defaults[.arisTodoLists], configured: Defaults[.arisTodoListsConfigured], defaultChoice: Defaults[.arisTodoDefaultList])
    }

    /// Where new items go: the chosen list if it shows in the tab, else the first list that does, else Reminders' own
    /// (ArisReminderLists, from the lists last read).
    var defaultListID: String {
        ArisReminderLists.defaultListID(prefs, existing: lists.map(\.id), storeDefault: storeDefaultID)
    }

    /// The lists the tab shows: the chosen ones, else the default list.
    var includedIDs: [String] {
        ArisReminderLists.includedIDs(prefs, existing: lists.map(\.id), storeDefault: storeDefaultID)
    }

    func setIncluded(_ ids: [String]) {
        Defaults[.arisTodoListsConfigured] = true
        Defaults[.arisTodoLists] = ids
        Task { await reload() }
    }

    var includedLists: [ArisReminderList] { includedIDs.compactMap { id in lists.first { $0.id == id } } }

    func reload() async {
        reloadGeneration += 1
        let generation = reloadGeneration
        status = EKEventStore.authorizationStatus(for: .reminder)
        guard authorized else { lists = []; items = []; return }
        let loaded = await ready().load(prefs)
        lists = loaded.lists
        storeDefaultID = loaded.storeDefault
        // A change made here meanwhile (or a newer read) has the newer items.
        guard generation == reloadGeneration else { return }
        items = loaded.items
    }

    /// The included lists' reminders ticked off from `from` up to `to`, each with when (the day-end list's done
    /// to-dos: ArisDayEndModel); nil when Aris may not read Reminders.
    func completed(from: Date, to: Date) async -> [(item: ArisTodoItem, at: Date)]? {
        guard authorized else { return nil }
        return await ready().completed(from: from, to: to, prefs: prefs)
    }

    // MARK: - Writing

    @discardableResult
    func add(_ draft: ArisTodoDraft) async -> ArisTodoItem? {
        guard authorized else { return nil }
        return took(await ready().add(draft, prefs: prefs))
    }

    /// Whether the list new to-dos go to is the user's own; false without access (review 9, L2).
    func newItemsListIsOwn() async -> Bool {
        guard authorized else { return false }
        return await ready().newItemsListIsOwn(prefs: prefs)
    }

    @discardableResult
    func update(_ id: String, _ draft: ArisTodoDraft) async -> ArisTodoItem? {
        took(await ready().update(id, draft, prefs: prefs))
    }

    /// What a save came to, on this side: the item in the tab's list (or out of it), or why not. A reminder that is
    /// no longer there, and no list to add to, leave the last error as it was (as before).
    private func took(_ outcome: Result<ArisReminderStore.Saved, ArisReminderStore.Failure>) -> ArisTodoItem? {
        switch outcome {
        case .failure(.notFound), .failure(.noList):
            return nil
        case .failure(.noTitle):
            lastError = ArisTodoWords.failed(.noTitle)
            return nil
        case .failure(.store(let why)):
            lastError = ArisTodoWords.failed(.save, why)
            Task { await reload() }
            return nil
        case .success(let saved):
            lastError = nil
            reloadGeneration += 1
            items = ArisReminderLists.taking(saved.item, shown: saved.shown, into: items)
            return saved.item
        }
    }

    @discardableResult
    func complete(_ id: String) async -> Bool {
        lastError = nil
        if let failure = await ready().setCompleted(id, true) {
            lastError = failure == .notFound ? ArisTodoWords.failed(.missing) : ArisTodoWords.failed(.complete, Self.words(failure))
            return false
        }
        reloadGeneration += 1
        items.removeAll { $0.id == id }
        return true
    }

    /// A ticked item open again (undoing "체크했어요"); it comes back on the list at the next reload.
    func reopen(_ id: String) async -> Bool {
        lastError = nil
        if let failure = await ready().setCompleted(id, false) {
            lastError = failure == .notFound ? ArisTodoWords.failed(.missing) : ArisTodoWords.failed(.reopen, Self.words(failure))
            return false
        }
        reloadGeneration += 1
        return true
    }

    @discardableResult
    func remove(_ id: String) async -> Bool {
        lastError = nil
        if let failure = await ready().remove(id) {
            lastError = failure == .notFound ? ArisTodoWords.failed(.missing) : ArisTodoWords.failed(.delete, Self.words(failure))
            return false
        }
        reloadGeneration += 1
        items.removeAll { $0.id == id }
        return true
    }

    /// EventKit's own words for a refusal.
    private static func words(_ failure: ArisReminderStore.Failure) -> String {
        if case .store(let why) = failure { return why }
        return ""
    }

    func move(_ id: String, to listID: String) async {
        guard lists.contains(where: { $0.id == listID }), var draft = await ready().draft(of: id) else { return }
        draft.listID = listID
        _ = await update(id, draft)
    }

    /// "내일로 미루기": tomorrow, at the same time of day.
    func postponeToTomorrow(_ id: String) async {
        guard let draft = await ready().draftForTomorrow(of: id, now: .now) else { return }
        _ = await update(id, draft)
    }

    func openInReminders(_ id: String) {
        guard let url = URL(string: "x-apple-reminderkit://remcdreminder/\(id)") else { return }
        NSWorkspace.shared.open(url)
    }

    @discardableResult
    func createList(named name: String) async -> ArisReminderList? {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard authorized, !title.isEmpty, let created = await ready().createList(named: title) else { return nil }
        if !lists.contains(where: { $0.id == created.id }) { lists.append(created) }
        return created
    }

    /// Test harness cleanup: every reminder (open or done) whose title starts with `prefix`, in any list.
    func purge(titlePrefix prefix: String) async -> Int {
        guard authorized, !prefix.isEmpty else { return 0 }
        let count = await ready().purge(titlePrefix: prefix)
        await reload()
        return count
    }

    /// Harness read-back: title, due, list, notes and done state of every reminder starting with `prefix`.
    func describe(titlePrefix prefix: String) async -> [String] {
        await ready().describe(titlePrefix: prefix)
    }

    func deleteList(_ id: String) async {
        guard await ready().deleteList(id) else { return }
        lists.removeAll { $0.id == id }
        Defaults[.arisTodoLists].removeAll { $0 == id }
        await reload()
    }
}
