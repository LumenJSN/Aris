//
//  ArisSkillsModel.swift
//  Aris
//
//  The app's side of the user's skills: what aris-agent says (ArisSkillsStatus, read again whenever the agent nudges
//  com.lumenjsn.aris.skills, and every 0.6 s while something runs), the settings page's chat (the owner's pick C, "말로
//  시작": turning it on, a GitHub link, 말로 만들기, a dragged-in folder), and the notch's flow for "이 링크 스킬 추가해줘
//  <link>". Jobs live in the agent: closing the notch or the window never stops one; one nobody watched ends in the inbox.
//

import AppKit
import Defaults
import Foundation

@MainActor
final class ArisSkillsModel: ObservableObject, ArisSkillsSource {
    static let shared = ArisSkillsModel()

    @Published private(set) var status = ArisSkillsStatus()
    @Published private(set) var chat: [ArisSkillChatItem] = []
    @Published var draft = ""
    @Published private(set) var notchFlow: ArisSkillNotchFlow?
    /// Which settings rows are open.
    @Published var expanded: Set<String> = []
    /// The settings page or the notch's flow is on screen: polls carry "seen" (else a job that ends goes to the inbox).
    var settingsVisible = false
    var notchVisible = false

    /// The 말로 만들기 conversation so far, and the skill 말로 고치기 is changing.
    private var conversation: [(user: Bool, text: String)] = []
    private var editing: String?
    private var watching = false
    private var poller: Task<Void, Never>?

    private init() {}

    /// Starts listening for the agent's nudges (once, at launch).
    func start() {
        guard !watching else { return }
        watching = true
        DistributedNotificationCenter.default().addObserver(forName: .init("com.lumenjsn.aris.skills"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    private var brain: String { Defaults[.arisBrain] }

    /// Jobs the chat or the notch is showing.
    private var shownJobs: [String] {
        chat.compactMap { if case .job(let id) = $0.kind { return id } else { return nil } } + [notchFlow?.job].compactMap { $0 }
    }

    func refresh() {
        Task {
            let seen = settingsVisible || notchVisible ? shownJobs : []
            guard let answer = await ArisAgentClient.skills(["op": "status", "seen": seen]), answer.status == 200 else { return }
            apply(ArisSkillsStatus.parse(answer.object))
        }
    }

    private func apply(_ next: ArisSkillsStatus) {
        let wasReady = status.ready
        status = next
        if !wasReady, next.ready { becameReady() }
        keepPolling()
    }

    /// While the setup or a shown job runs, the status is read again every 0.6 s.
    private func keepPolling() {
        let busy = status.setup.state == "installing" || status.jobs.contains { shownJobs.contains($0.id) && $0.stage != "done" }
        guard busy, poller == nil else { return }
        poller = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            self?.poller = nil
            self?.refresh()
        }
    }

    // MARK: - The switch

    /// 켜 줘 / 켜기 / the page's switch.
    func turnOn(saying: Bool = true) {
        if saying { chat.append(.init(kind: .user("켜 줘", link: false))) }
        chat.append(.init(kind: .aris("준비하고 있어요. 1~2분이면 돼요.")))
        chat.append(.init(kind: .setup))
        Task {
            if let answer = await ArisAgentClient.skills(["op": "feature", "on": true, "brain": brain]), answer.status == 200 { apply(ArisSkillsStatus.parse(answer.object)) }
        }
    }

    func turnOff() {
        chat.removeAll()
        Task {
            if let answer = await ArisAgentClient.skills(["op": "feature", "on": false]), answer.status == 200 { apply(ArisSkillsStatus.parse(answer.object)) }
        }
    }

    func later() {
        chat.append(.init(kind: .user("나중에", link: false)))
        chat.append(.init(kind: .aris("알겠어요. 필요할 때 위의 스위치로 켜면 돼요.")))
        if notchFlow != nil { notchFlow?.dropped = true }
        Task { _ = await ArisAgentClient.skills(["op": "defer"]) }
    }

    func retry() {
        Task {
            if let answer = await ArisAgentClient.skills(["op": "retry", "brain": brain]), answer.status == 200 { apply(ArisSkillsStatus.parse(answer.object)) }
        }
    }

    private func becameReady() {
        if chat.contains(where: { $0.kind == .setup }) {
            chat.append(.init(kind: .aris("어떤 일을 스킬로 만들까요? 말로 설명하거나, GitHub 링크를 붙여 넣거나, 폴더를 끌어 놓으세요.")))
            chat.append(.init(kind: .suggestions))
        }
        // The notch asked to turn it on for a link: now the link.
        if var flow = notchFlow, flow.job == nil, !flow.dropped { startLink(&flow) }
    }

    // MARK: - The chat

    /// The composer: a GitHub link adds it; anything else is 말로 만들기 (or 말로 고치기).
    func send(_ raw: String? = nil) {
        let text = (raw ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, status.ready else { return }
        draft = ""
        if let link = ArisSkillIntent.link(in: text + " 스킬 추가") ?? (text.contains("github.com") ? text : nil) {
            chat.append(.init(kind: .user(link.replacingOccurrences(of: "https://", with: ""), link: true)))
            addLink(link)
            return
        }
        chat.append(.init(kind: .user(text, link: false)))
        conversation.append((user: true, text: text))
        askMaker()
    }

    private func addLink(_ link: String) {
        Task {
            guard let answer = await ArisAgentClient.skills(["op": "add", "text": link, "hold": true, "brain": brain]) else {
                return chat.append(.init(kind: .aris("Aris 에이전트가 답하지 않아요. 잠시 뒤 다시 해 주세요.")))
            }
            guard answer.status == 200, let id = answer.object["job"] as? String else {
                return chat.append(.init(kind: .aris(answer.object["error"] as? String ?? "링크를 받지 못했어요.")))
            }
            chat.append(.init(kind: .aris("받았어요. 추가하기 전에 같이 확인해요.")))
            chat.append(.init(kind: .job(id)))
            refresh()
        }
    }

    /// A folder dragged onto the page.
    func addFolder(_ url: URL) {
        guard status.ready else { return }
        chat.append(.init(kind: .user("폴더 · " + url.lastPathComponent, link: false)))
        Task {
            guard let answer = await ArisAgentClient.skills(["op": "add", "path": url.path, "brain": brain]), answer.status == 200,
                  let id = answer.object["job"] as? String else {
                return chat.append(.init(kind: .aris("폴더를 받지 못했어요.")))
            }
            chat.append(.init(kind: .aris("SkillSpector로 안전 검사를 할게요.")))
            chat.append(.init(kind: .job(id)))
            refresh()
        }
    }

    /// 검사하고 추가 / 그만두기 on a fetched link; 그래도 추가 / 취소 on a caution.
    func go(_ job: String) {
        chat.append(.init(kind: .aris("SkillSpector로 안전 검사를 할게요.")))
        Task {
            if let answer = await ArisAgentClient.skills(["op": "go", "job": job]), answer.status == 200 { apply(ArisSkillsStatus.parse(answer.object)) }
        }
    }

    func decide(_ job: String, accept: Bool) {
        Task {
            if let answer = await ArisAgentClient.skills(["op": "decide", "job": job, "accept": accept]), answer.status == 200 { apply(ArisSkillsStatus.parse(answer.object)) }
        }
    }

    private func askMaker() {
        chat.append(.init(kind: .thinking))
        let lines = conversation.map { ["user": $0.user, "text": $0.text] as [String: Any] }
        var body: [String: Any] = ["op": "draft", "conversation": lines, "brain": brain]
        if let editing { body["editing"] = editing }
        Task {
            let answer = await ArisAgentClient.skills(body, timeout: 300)
            chat.removeAll { $0.kind == .thinking }
            if let question = answer?.object["ask"] as? String {
                conversation.append((user: false, text: question))
                chat.append(.init(kind: .aris(question)))
            } else if let skill = answer?.object["skill"] as? String {
                conversation = []
                chat.append(.init(kind: .aris("초안을 썼어요. 연결한 AI 모두에서 되는지 시험하고 있어요. 고칠 곳은 말하거나 직접 고쳐 주세요.")))
                chat.append(.init(kind: .draft(skill)))
                save(skill)
            } else {
                chat.append(.init(kind: .aris(answer?.object["error"] as? String ?? "AI가 답하지 않았어요. 다시 말해 주세요.")))
            }
        }
    }

    /// The draft goes in like any skill (checked first); its card shows how that went.
    private func save(_ skill: String) {
        Task {
            guard let answer = await ArisAgentClient.skills(["op": "save", "skill": skill, "brain": brain]), answer.status == 200,
                  let id = answer.object["job"] as? String else { return }
            chat.append(.init(kind: .job(id)))
            refresh()
        }
    }

    /// The chip "시험 날짜 주면 공부 계획 짜기".
    func suggest(_ text: String) { send(text) }

    // MARK: - The list

    func toggle(_ name: String, on: Bool) {
        Task { if let answer = await ArisAgentClient.skills(["op": "enable", "name": name, "on": on]), answer.status == 200 { apply(ArisSkillsStatus.parse(answer.object)) } }
    }

    func remove(_ name: String) {
        expanded.remove(name)
        Task { if let answer = await ArisAgentClient.skills(["op": "remove", "name": name]), answer.status == 200 { apply(ArisSkillsStatus.parse(answer.object)) } }
    }

    func tryAll(_ name: String) {
        Task { if let answer = await ArisAgentClient.skills(["op": "try", "name": name]), answer.status == 200 { apply(ArisSkillsStatus.parse(answer.object)) } }
    }

    /// SKILL.md 직접 고치기 (opens it in TextEdit; saving it there checks it again).
    func edit(_ name: String) { Task { _ = await ArisAgentClient.skills(["op": "edit", "name": name]) } }

    /// 폴더에서: Finder at the skills folder.
    func reveal() { Task { _ = await ArisAgentClient.skills(["op": "reveal"]) } }

    /// 말로 고치기: the chat asks what to change.
    func speakFix(_ row: ArisSkillRow) {
        editing = row.name
        conversation = []
        chat.append(.init(kind: .aris("‘\(row.title)’ 스킬에서 무엇을 바꿀까요?")))
    }

    // MARK: - The notch

    /// "이 링크 스킬 추가해줘 <link>" in the notch: on first (asking), then the link, its check and the outcome there.
    func startNotchFlow(request: String, link: String) {
        var flow = ArisSkillNotchFlow(request: request, link: link)
        if status.ready { startLink(&flow) } else { notchFlow = flow }
        refresh()
    }

    private func startLink(_ flow: inout ArisSkillNotchFlow) {
        notchFlow = flow
        let link = flow.link
        Task {
            // The notch asks 검사하고 추가 too (security review M11).
            let answer = await ArisAgentClient.skills(["op": "add", "text": link, "hold": true, "brain": brain])
            if let id = answer?.object["job"] as? String { notchFlow?.job = id } else { notchFlow?.problem = answer?.object["error"] as? String ?? "링크를 받지 못했어요." }
            refresh()
        }
    }

    /// 검사하고 추가 on the notch's card.
    func notchGo(_ job: String) {
        Task {
            if let answer = await ArisAgentClient.skills(["op": "go", "job": job]), answer.status == 200 { apply(ArisSkillsStatus.parse(answer.object)) }
        }
    }

    /// 켜기 on the notch's card.
    func notchTurnOn() { turnOn(saying: false) }

    func notchLater() {
        notchFlow?.dropped = true
        Task { _ = await ArisAgentClient.skills(["op": "defer"]) }
    }

    func endNotchFlow() { notchFlow = nil }
}
