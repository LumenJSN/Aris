//
//  ArisActivityModel.swift
//  Aris
//
//  What the 한 일 tab shows: today's activity log from aris-agent's /activity (the app is sandboxed; the log is in
//  ~/.config/aris), fetched when the tab opens and after an undo, never on a timer, so a closed tab costs nothing.
//  The undo itself goes through ArisController.undoEntry, the same /undo as "방금 거 취소해".
//

import Foundation

@MainActor
final class ArisActivityModel: ObservableObject {
    static let shared = ArisActivityModel()

    enum Load: Equatable { case loading, loaded, failed }

    @Published private(set) var items: [ArisActivityItem] = []
    @Published private(set) var load: Load = .loading
    /// The strip's pick. It and the undone marks live here, so switching teammates never loses them.
    @Published var filter: ArisActivityFilter = .everyone
    /// Entries whose undo is on its way (their button waits).
    @Published private(set) var undoing: Set<String> = []
    /// Why the last undo didn't happen; kept (also across reopening the tab) until the next undo.
    @Published private(set) var notice: String?
    /// While an undo waits on macOS's folder prompt (QA BUG-17): why, shown in the notice's place until it answers.
    @Published var waitingNotice: String?

    private var refreshing = false
    /// Asked again while a fetch was out (an undo finished): fetch once more, so stale rows never win.
    private var again = false

    /// The tab came into view.
    func opened() {
        // The faces in the strip are the ones the owner picked in the 팀원 settings.
        ArisTeamModel.shared.refresh()
        Task { await refresh() }
    }

    /// During the side panels' demo (ArisSideDemo) the rows are its samples: the agent's log is never asked.
    func refresh() async {
        if let samples = ArisSideDemo.shared.samples { return showDemo(samples) }
        guard !refreshing else { again = true; return }
        refreshing = true
        defer { refreshing = false }
        repeat {
            again = false
            await fetch()
        } while again
    }

    private func fetch() async {
        guard let fetched = await ArisAgentClient.activity(today: true) else {
            guard !ArisSideDemo.shared.isOn else { return }
            // Rows already shown stay; only an empty tab says the agent didn't answer.
            if items.isEmpty { load = .failed }
            return
        }
        // The demo began while this was on its way: its samples stay.
        guard !ArisSideDemo.shared.isOn else { return }
        items = fetched
        load = .loaded
        let mates = ArisActivityTab.teammates(fetched, now: Date(), calendar: .current)
        let kept = ArisActivityTab.resolved(filter, among: mates)
        if kept != filter { filter = kept }
    }

    /// The demo went on (its samples) or off (back to today's log, fetched again).
    func demoChanged() {
        notice = nil
        undoing = []
        filter = .everyone
        if let samples = ArisSideDemo.shared.samples { return showDemo(samples) }
        items = []
        load = .loading
        Task { await refresh() }
    }

    private func showDemo(_ samples: ArisSideDemoSamples) {
        // A sample undone a moment ago stays undone while the demo runs.
        if !items.allSatisfy({ $0.id.hasPrefix(ArisSideDemoSamples.idPrefix) }) || items.isEmpty { items = samples.activity }
        load = .loaded
    }

    func undo(_ id: String) async {
        // A demo row's 되돌리기 only marks it, in memory: no undo goes to the agent.
        if ArisSideDemo.shared.isOn { return items = ArisActivityTab.markingUndone(items, id: id) }
        guard !undoing.contains(id) else { return }
        undoing = undoing.union([id])
        notice = nil
        let outcome = await ArisController.shared.undoEntry(id)
        switch outcome {
        case .done?:
            items = ArisActivityTab.markingUndone(items, id: id)
        case .failed(let message)?:
            notice = ArisUndoWords.failure(message, korean: !ArisUIWords.english)
        case .refused?:
            notice = ArisActivityTab.refusedNotice()
        case .needsConfirm?:
            notice = ArisUndoWords.failure("", korean: !ArisUIWords.english)
        case nil:
            break
        }
        undoing = undoing.subtracting([id])
        await refresh()
    }
}
