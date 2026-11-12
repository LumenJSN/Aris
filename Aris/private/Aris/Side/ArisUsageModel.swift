//
//  ArisUsageModel.swift
//  Aris
//
//  Plan limits and local cost for every AI in use in one place, from aris-agent's /usage every few minutes (and when
//  the 사용량 tab is opened on a read more than a minute old). When Claude's own login can't be read (expired), its limits come from Claude Code's status
//  line (ClaudeStore). Feeds the left side panel's 사용량 tab and the menu-bar meter.
//  The reads every few minutes run only while the 사용량 tab shows (each one has aris-agent ask every service). With
//  the tab off, the settings window, which lists the services from the same reads, gets one when it comes up.
//  Every read ends within a stated time (ArisUsagePatience) and says how it ended (`read`): a Mac with none of these
//  AIs gets an empty answer, which the tab and the settings show as "none", never as "still loading".
//

import Combine
import Foundation

@MainActor
final class ArisUsageModel: ObservableObject {
    static let shared = ArisUsageModel()

    @Published private(set) var providers: [ArisUsageProvider] = []
    /// How the latest read stands: waiting, answered or unanswered. An empty list alone never means "still loading".
    @Published private(set) var read = ArisUsageRead.waiting

    /// What the 사용량 tab shows: the limits, or why there are none (ArisUsageTabState).
    var tabState: ArisUsageTabState { .of(hasProviders: !providers.isEmpty, read: read) }

    private static let every: TimeInterval = 180
    private var timer: Timer?
    private var fetched: [ArisUsageProvider] = []
    private var watching: AnyCancellable?
    private var refreshing = false
    private var settingsWatch: AnyCancellable?
    private var tabWatch: AnyCancellable?
    private var hiddenTabs: Set<String> = []
    private var lastRead: Date?

    func start() {
        guard watching == nil else { return }
        watching = ClaudeStore.shared.$usage.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.merge() }
        settingsWatch = ArisSettingsWindow.shared.$visible.removeDuplicates().filter { $0 }.sink { [weak self] _ in self?.settingsCameUp() }
        let panels = ArisSidePanels.shared
        tabWatch = panels.$open.combineLatest(panels.$leftTab).map { ArisSideTabWork.showsUsage(open: $0, leftTab: $1) }
            .removeDuplicates().filter { $0 }.sink { [weak self] _ in self?.usageTabOpened() }
        tabsChanged(hidden: panels.hiddenTabs)
    }

    /// The 사용량 tab came to the front of the open panel: what it shows is at most a minute old.
    private func usageTabOpened() {
        guard ArisSideTabWork.readsUsageOnOpen(lastRead: lastRead, now: Date()) else { return }
        Task { await refresh() }
    }

    /// The side notches' tabs as they are now: the timer runs while 사용량 is one of them (with a read right away when
    /// it is turned on), and stops when it is turned off.
    func tabsChanged(hidden: Set<String>) {
        hiddenTabs = hidden
        guard ArisSideTabWork.pollsUsage(hidden: hidden) else {
            timer?.invalidate()
            timer = nil
            return
        }
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.every, repeats: true) { _ in
            Task { @MainActor in await ArisUsageModel.shared.refresh() }
        }
        Task { await refresh() }
    }

    private func settingsCameUp() {
        guard ArisSideTabWork.readsUsageOnce(hidden: hiddenTabs, lastRead: lastRead, now: Date(), every: Self.every) else { return }
        Task { await refresh() }
    }

    /// One read. The agent answers within a few seconds with the AIs it has heard from and names the ones it is still
    /// asking (agy takes a while, a login may be slow); while any is named this asks again, up to a stated limit
    /// (ArisUsagePatience), so no AI holds the others back and the read always ends.
    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        let began = Date()
        lastRead = began
        read = read.beginning
        defer { refreshing = false }
        while true {
            let report = await ArisAgentClient.usage()
            if let report { fetched = report.providers }
            let again = ArisUsagePatience.asksAgain(pending: report?.pending, began: began, now: Date())
            read = read.after(answered: report != nil, asksAgain: again)
            merge()
            guard again else { return }
            try? await Task.sleep(for: .seconds(ArisUsagePatience.again))
        }
    }

    /// The fullest window of any provider, now.
    var peak: Double { providers.map { $0.peak(at: Date()) }.max() ?? 0 }

    private static let order = ["claude", "codex", "antigravity"]

    private func merge() {
        var all = fetched
        if let index = all.firstIndex(where: { $0.id == "claude" }) {
            if all[index].lanes.isEmpty, let status = statusLineClaude() { all[index].lanes = status.lanes }
        } else if let status = statusLineClaude() {
            all.append(status)
        }
        let rank = { (provider: ArisUsageProvider) in Self.order.firstIndex(of: provider.id) ?? Self.order.count }
        providers = all.sorted { rank($0) < rank($1) }
    }

    private static let savedClaudeKey = "arisLastClaudeUsage2"
    private var savedClaude: ArisUsageProvider?

    /// Claude's limits from its status line, which only reports while Claude Code runs; the last report is kept
    /// so a restart doesn't blank the row (each window still drops to 0 once its reset time passes).
    private func statusLineClaude() -> ArisUsageProvider? {
        if let usage = ClaudeStore.shared.usage, usage.fiveHour != nil || usage.sevenDay != nil {
            let window = { (window: UsageWindow?, seconds: Double) in
                window.map { ArisUsageWindow(percent: $0.percent, resetsAt: $0.resetsAt, windowSeconds: seconds) }
            }
            let provider = ArisUsageProvider(id: "claude", title: "Claude",
                                             lanes: [ArisUsageLane(name: "", fiveHour: window(usage.fiveHour, 18_000), weekly: window(usage.sevenDay, 604_800))],
                                             updatedAt: usage.updatedAt)
            if provider != savedClaude, let data = try? JSONEncoder().encode(provider) {
                UserDefaults.standard.set(data, forKey: Self.savedClaudeKey)
                savedClaude = provider
            }
            return provider
        }
        guard let data = UserDefaults.standard.data(forKey: Self.savedClaudeKey) else { return nil }
        return try? JSONDecoder().decode(ArisUsageProvider.self, from: data)
    }
}
